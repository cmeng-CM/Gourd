// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct AIHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

@MainActor
protocol AIHTTPTransport: AnyObject {
    func send(_ request: URLRequest, responseLimit: Int) async throws -> AIHTTPResponse
}

enum AIEndpoint {
    static func url(for profile: AIModelProfile) throws -> URL {
        guard var components = URLComponents(string: profile.baseURL),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(),
              !host.isEmpty, components.user == nil, components.password == nil,
              components.fragment == nil, components.query == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { throw AIError.invalidEndpoint }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let ipv4Loopback = octets.count == 4 && octets.first == "127" && octets.allSatisfy {
            $0.allSatisfy(\.isNumber) && Int($0).map { (0...255).contains($0) } == true
        }
        let loopback = host == "localhost" || ipv4Loopback || host == "::1" || host == "[::1]"
        guard scheme == "https" || (scheme == "http" && loopback) else { throw AIError.invalidEndpoint }
        var segments = components.path.split(separator: "/").map(String.init)
        switch profile.apiProtocol {
        case .openAICompatible:
            if segments.suffix(2) == ["chat", "completions"] { segments.removeLast(2) }
            if segments.last != "v1" { segments.append("v1") }
            segments += ["chat", "completions"]
        case .anthropic:
            if segments.last == "messages" { segments.removeLast() }
            if segments.last != "v1" { segments.append("v1") }
            segments.append("messages")
        case .gemini:
            guard !profile.modelID.isEmpty,
                  profile.modelID.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").inverted) == nil else {
                throw AIError.invalidConfiguration
            }
            if let models = segments.firstIndex(of: "models") { segments = Array(segments.prefix(models)) }
            if segments.last != "v1" && segments.last != "v1beta" { segments.append("v1beta") }
            segments += ["models", "\(profile.modelID):generateContent"]
        case .ollama:
            if segments.last == "chat" { segments.removeLast() }
            if segments.last != "api" { segments.append("api") }
            segments.append("chat")
        }
        components.path = "/" + segments.joined(separator: "/")
        guard let url = components.url else { throw AIError.invalidEndpoint }
        return url
    }
}

/// 每次调用独立 session/task；在接收回调内、追加 data 之前检查限额。
@MainActor
final class AIURLSessionTransport: AIHTTPTransport {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    func send(_ request: URLRequest, responseLimit: Int) async throws -> AIHTTPResponse {
        guard responseLimit > 0 else { throw AIError.invalidRequest }
        let receiver = AILimitedHTTPReceiver(limit: responseLimit, configuration: configuration)
        return try await withTaskCancellationHandler {
            if Task.isCancelled { throw AIError.cancelled }
            return try await withCheckedThrowingContinuation { continuation in
                receiver.start(request: request, continuation: continuation)
            }
        } onCancel: {
            receiver.finish(.failure(AIError.cancelled))
        }
    }
}

/// URLSession delegate callbacks和Task取消可能并发，锁只保护该次请求状态。
final class AILimitedHTTPReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    private var statusCode: Int?
    private var continuation: CheckedContinuation<AIHTTPResponse, Error>?
    private var session: URLSession?
    private var finished: Result<AIHTTPResponse, Error>?
    private let configuration: URLSessionConfiguration

    init(limit: Int, configuration: URLSessionConfiguration) {
        self.limit = limit
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }

    func start(request: URLRequest, continuation: CheckedContinuation<AIHTTPResponse, Error>) {
        lock.lock()
        if let finished {
            lock.unlock()
            continuation.resume(with: finished)
            return
        }
        self.continuation = continuation
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        lock.unlock()
        task.resume()
    }

    func finish(_ result: Result<AIHTTPResponse, Error>) {
        lock.lock()
        guard finished == nil else { lock.unlock(); return }
        finished = result
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            finish(.failure(AIError.invalidResponse))
            completionHandler(.cancel)
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            finish(.failure(AIError.responseTooLarge))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        statusCode = response.statusCode
        let active = finished == nil
        lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard finished == nil else { lock.unlock(); return }
        let exceedsLimit = data.count > limit - buffer.count
        if !exceedsLimit { buffer.append(data) }
        lock.unlock()
        if exceedsLimit { finish(.failure(AIError.responseTooLarge)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError {
            finish(.failure(error.code == .timedOut ? AIError.timedOut :
                (error.code == .cancelled ? AIError.cancelled : AIError.transportFailed)))
            return
        }
        if error != nil { finish(.failure(AIError.transportFailed)); return }
        lock.lock()
        let status = statusCode
        let data = buffer
        lock.unlock()
        guard let status else { finish(.failure(AIError.invalidResponse)); return }
        finish(.success(AIHTTPResponse(statusCode: status, body: data)))
    }

    /// 拒绝所有 redirect，避免 POST 改写和任何凭据的跨源传播。
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        finish(.failure(AIError.redirectRejected))
        completionHandler(nil)
    }
}
