// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@MainActor
final class AIService: AIHandle {
    static let responseLimit = 1_048_576
    private let configurationStore: AIConfigurationStore
    private let transport: any AIHTTPTransport

    init(configurationStore: AIConfigurationStore, transport: (any AIHTTPTransport)? = nil) {
        self.configurationStore = configurationStore
        self.transport = transport ?? AIURLSessionTransport()
    }

    func complete(_ request: AIRequest) async throws -> AIResponse {
        if Task.isCancelled { throw AIError.cancelled }
        let profile = try configurationStore.profile(for: request)
        return try await complete(request, profile: profile, apiKey: configurationStore.credential(for: profile))
    }

    /// 连接测试只消费当前表单快照；不保存、不读取旧屏幕助手配置。
    /// apiKey 为该次测试的明确值，nil 表示不发送凭据。
    func complete(_ request: AIRequest, profile: AIModelProfile, apiKey: String?) async throws -> AIResponse {
        do {
            try Task.checkCancellation()
            let httpRequest = try AIWireAdapter.request(request, profile: profile, apiKey: apiKey)
            let response = try await transport.send(httpRequest, responseLimit: Self.responseLimit)
            try Task.checkCancellation()
            guard response.body.count <= Self.responseLimit else { throw AIError.responseTooLarge }
            guard (200...299).contains(response.statusCode) else { throw AIError.httpStatus(response.statusCode) }
            return try AIWireAdapter.response(response.body, protocol: profile.apiProtocol)
        } catch is CancellationError { throw AIError.cancelled }
        catch let error as AIError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw AIError.cancelled }
            if error.code == .timedOut { throw AIError.timedOut }
            throw AIError.transportFailed
        } catch { throw AIError.transportFailed }
    }
}

/// 纯协议转换，测试可以直接检查 wire shape；没有供应商 SDK 或固定模型列表。
enum AIWireAdapter {
    static func request(_ request: AIRequest, profile: AIModelProfile, apiKey: String?) throws -> URLRequest {
        guard profile.capabilities.contains(request.requiredCapability),
              !request.messages.contains(where: { !$0.images.isEmpty }) || profile.capabilities.contains(.vision) else {
            throw AIError.capabilityMismatch
        }
        guard !request.messages.isEmpty, request.maxOutputTokens > 0,
              !profile.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.messages.contains(where: { !$0.text.isEmpty || !$0.images.isEmpty }),
              request.messages.allSatisfy({ message in
                  (message.role != .system || message.images.isEmpty) && message.images.allSatisfy {
                      !$0.data.isEmpty && ["image/png", "image/jpeg", "image/gif", "image/webp"].contains($0.mimeType)
                  }
              }) else { throw AIError.invalidRequest }
        if let apiKey, apiKey.contains("\r") || apiKey.contains("\n") { throw AIError.invalidRequest }
        var http = URLRequest(url: try AIEndpoint.url(for: profile), timeoutInterval: 30)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any]
        switch profile.apiProtocol {
        case .openAICompatible:
            body = ["model": profile.modelID, "stream": false, "max_tokens": request.maxOutputTokens,
                    "messages": request.messages.map { message -> [String: Any] in
                        if message.images.isEmpty { return ["role": message.role.rawValue, "content": message.text] }
                        var content: [[String: Any]] = [["type": "text", "text": message.text]]
                        content += message.images.map {
                            ["type": "image_url", "image_url": ["url": "data:\($0.mimeType);base64,\($0.data.base64EncodedString())"]]
                        }
                        return ["role": message.role.rawValue, "content": content]
                    }]
            // DeepSeek 的思考模式默认打开；结构化短输出显式关闭，见
            // https://api-docs.deepseek.com/zh-cn/guides/thinking_mode/ 。只对 DeepSeek
            // 端点发该字段，避免把供应商私有参数发给严格的 OpenAI 兼容实现。
            if request.disablesReasoning, Self.supportsThinkingSwitch(profile) {
                body["thinking"] = ["type": "disabled"]
            }
            if let apiKey, !apiKey.isEmpty { http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            guard let apiKey, !apiKey.isEmpty else { throw AIError.missingCredential }
            http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": profile.modelID, "max_tokens": request.maxOutputTokens, "stream": false,
                    "messages": request.messages.filter { $0.role != .system }.map { message -> [String: Any] in
                        var content: [[String: Any]] = [["type": "text", "text": message.text]]
                        content += message.images.map {
                            ["type": "image", "source": ["type": "base64", "media_type": $0.mimeType,
                                                          "data": $0.data.base64EncodedString()]]
                        }
                        return ["role": message.role.rawValue, "content": content]
                    }]
            let system = request.messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
            if !system.isEmpty { body["system"] = system }
        case .gemini:
            guard let apiKey, !apiKey.isEmpty else { throw AIError.missingCredential }
            http.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            body = ["generationConfig": ["maxOutputTokens": request.maxOutputTokens],
                    "contents": request.messages.filter { $0.role != .system }.map { message -> [String: Any] in
                        var parts: [[String: Any]] = [["text": message.text]]
                        parts += message.images.map {
                            ["inlineData": ["mimeType": $0.mimeType, "data": $0.data.base64EncodedString()]]
                        }
                        return ["role": message.role == .assistant ? "model" : "user", "parts": parts]
                    }]
            let system = request.messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
            if !system.isEmpty { body["systemInstruction"] = ["parts": [["text": system]]] }
        case .ollama:
            body = ["model": profile.modelID, "stream": false, "options": ["num_predict": request.maxOutputTokens],
                    "messages": request.messages.map { message -> [String: Any] in
                        var value: [String: Any] = ["role": message.role.rawValue, "content": message.text]
                        if !message.images.isEmpty { value["images"] = message.images.map { $0.data.base64EncodedString() } }
                        return value
                    }]
            if let apiKey, !apiKey.isEmpty { http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        }
        if profile.apiProtocol == .anthropic || profile.apiProtocol == .gemini {
            guard request.messages.contains(where: { $0.role != .system }) else { throw AIError.invalidRequest }
        }
        do { http.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { throw AIError.invalidRequest }
        return http
    }

    /// thinking 是 DeepSeek 的 OpenAI 兼容扩展；其他兼容端点未必接受未知字段，
    /// 因此只在 host 或模型名能明确指向 DeepSeek 时发送。
    static func supportsThinkingSwitch(_ profile: AIModelProfile) -> Bool {
        guard profile.apiProtocol == .openAICompatible else { return false }
        let host = URLComponents(string: profile.baseURL)?.host?.lowercased() ?? ""
        return host == "api.deepseek.com" || host.hasSuffix(".deepseek.com")
            || profile.modelID.lowercased().hasPrefix("deepseek")
    }

    static func response(_ data: Data, protocol apiProtocol: AIProtocol) throws -> AIResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil else {
            throw AIError.invalidResponse
        }
        let text: String?
        switch apiProtocol {
        case .openAICompatible:
            let choice = (object["choices"] as? [[String: Any]])?.first
            let message = choice?["message"] as? [String: Any]
            if let value = message?["content"] as? String { text = value }
            else {
                text = (message?["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }.joined()
            }
        case .anthropic:
            text = (object["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
        case .gemini:
            let candidate = (object["candidates"] as? [[String: Any]])?.first
            let content = candidate?["content"] as? [String: Any]
            text = (content?["parts"] as? [[String: Any]])?.filter { $0["thought"] as? Bool != true }
                .compactMap { $0["text"] as? String }.joined()
        case .ollama:
            text = (object["message"] as? [String: Any])?["content"] as? String
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
        return AIResponse(text: text)
    }
}
