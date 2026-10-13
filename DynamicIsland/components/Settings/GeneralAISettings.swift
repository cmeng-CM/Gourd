// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import SwiftUI

/// 表单快照与保存分离；不在打开页面或选择 profile 时读取密钥。
@MainActor
final class GeneralAISettingsModel: ObservableObject {
    @Published private(set) var configuration: AIConfiguration
    @Published var draft: AIModelProfile { didSet { invalidateConnectionTest() } }
    @Published var apiKey = "" { didSet { invalidateConnectionTest() } }
    @Published var clearStoredKey = false { didSet { invalidateConnectionTest() } }
    @Published private(set) var feedback: String?
    @Published private(set) var connectionFeedback: String?
    @Published private(set) var isTesting = false
    let loadError: AIError?
    private let store: AIConfigurationStore?
    private let service: AIService?
    private var configurationObservation: AnyCancellable?
    private var revision = UUID()
    private(set) var connectionTask: Task<Void, Never>?

    init(runtime: GeneralAIRuntime) {
        store = runtime.configurationStore
        service = runtime.service
        loadError = runtime.loadError
        let initial = runtime.configurationStore?.configuration ?? AIConfiguration()
        configuration = initial
        draft = initial.profiles.first ?? Self.newProfile()
        configurationObservation = store?.$configuration.sink { [weak self] in
            self?.configuration = $0
        }
    }

    static func newProfile() -> AIModelProfile {
        AIModelProfile(displayName: "", apiProtocol: .openAICompatible, baseURL: "", modelID: "")
    }

    func select(_ profile: AIModelProfile?) {
        draft = profile ?? Self.newProfile()
        apiKey = ""
        clearStoredKey = false
        feedback = nil
    }

    func save() {
        guard let store else { return }
        invalidateConnectionTest()
        do {
            // Blank means keep, never erase. Only the explicit toggle clears a saved credential.
            try store.save(draft, apiKey: clearStoredKey ? "" : (apiKey.isEmpty ? nil : apiKey))
            if let saved = store.profiles.first(where: { $0.id == draft.id }) { draft = saved }
            apiKey = ""
            clearStoredKey = false
            feedback = String(localized: "ai.settings.saved")
        } catch { feedback = Self.message(error) }
    }

    func remove() {
        guard let store else { return }
        invalidateConnectionTest()
        do {
            try store.remove(profileID: draft.id)
            select(store.profiles.first)
            feedback = String(localized: "ai.settings.deleted")
        } catch { feedback = Self.message(error) }
    }

    func setDefault(_ id: UUID?, for capability: AICapability) {
        guard let store else { return }
        do {
            try store.setDefault(id, for: capability)
            feedback = String(localized: "ai.settings.defaultsSaved")
        } catch { feedback = Self.message(error) }
    }

    func testConnection() {
        guard let store, let service else { return }
        invalidateConnectionTest()
        let snapshot = draft
        let token = revision
        let explicitKey: String?
        do {
            // Reading the saved reference is authorized only by this explicit button action.
            explicitKey = clearStoredKey ? nil : (apiKey.isEmpty ? try store.credential(for: snapshot) : apiKey)
        } catch {
            connectionFeedback = Self.message(error)
            return
        }
        let capability: AICapability = snapshot.capabilities.contains(.text) ? .text : .vision
        let request = AIRequest(purpose: "settings.connection-test", messages: [
            AIMessage(role: .user, text: "Reply with OK.")
        ], requiredCapability: capability, maxOutputTokens: 16)
        isTesting = true
        connectionTask = Task { [weak self] in
            let result: String
            do {
                _ = try await service.complete(request, profile: snapshot, apiKey: explicitKey)
                result = String(localized: "ai.settings.testSucceeded")
            } catch { result = Self.message(error) }
            guard let self, self.revision == token else { return }
            self.isTesting = false
            self.connectionFeedback = result
            self.connectionTask = nil
        }
    }

    func invalidateConnectionTest() {
        revision = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isTesting = false
        connectionFeedback = nil
    }

    private static func message(_ error: Error) -> String {
        (error as? AIError ?? .invalidConfiguration).localizedDescription
    }
}

@MainActor
struct GeneralAISettings: View {
    @StateObject private var model: GeneralAISettingsModel

    init(runtime: GeneralAIRuntime? = nil) {
        _model = StateObject(wrappedValue: GeneralAISettingsModel(runtime: runtime ?? .shared))
    }

    var body: some View {
        Form {
            Section {
                Text("ai.settings.screenSeparate")
                Text("ai.settings.visionDeclaration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = model.loadError {
                    Text(error.localizedDescription).foregroundStyle(.red)
                }
            }
            if model.loadError == nil {
                defaultsSection
                profilesSection
                editorSection
            }
        }
        .navigationTitle(String(localized: "ai.settings.title"))
        .onDisappear { model.invalidateConnectionTest() }
    }

    private var defaultsSection: some View {
        Section {
            defaultPicker(.text, title: "ai.settings.defaultText")
            defaultPicker(.vision, title: "ai.settings.defaultVision")
        } header: {
            Text("ai.settings.defaults")
        } footer: {
            Text("ai.settings.defaultsImmediate")
        }
        .settingsHighlight(id: SettingsTab.generalAI.highlightID(for: "defaults"))
    }

    private func defaultPicker(_ capability: AICapability, title: LocalizedStringKey) -> some View {
        Picker(title, selection: Binding<UUID?>(
            get: {
                capability == .text ? model.configuration.defaultTextProfileID : model.configuration.defaultVisionProfileID
            },
            set: { model.setDefault($0, for: capability) }
        )) {
            Text("ai.settings.none").tag(Optional<UUID>.none)
            ForEach(model.configuration.profiles.filter { $0.capabilities.contains(capability) }) { profile in
                Text(profile.displayName).tag(Optional(profile.id))
            }
        }
    }

    private var profilesSection: some View {
        Section {
            ForEach(model.configuration.profiles) { profile in
                Button { model.select(profile) } label: {
                    HStack {
                        Text(profile.displayName)
                        Spacer()
                        if model.draft.id == profile.id { Image(systemName: "checkmark") }
                    }
                }
            }
            Button("ai.settings.add") { model.select(nil) }
        } header: {
            Text("ai.settings.profiles")
        }
    }

    private var editorSection: some View {
        Section {
            TextField("ai.settings.name", text: $model.draft.displayName)
            Picker("ai.settings.protocol", selection: $model.draft.apiProtocol) {
                ForEach(AIProtocol.allCases, id: \.self) { apiProtocol in
                    Text(protocolTitle(apiProtocol)).tag(apiProtocol)
                }
            }
            TextField("ai.settings.baseURL", text: $model.draft.baseURL)
            TextField("ai.settings.modelID", text: $model.draft.modelID)
            Toggle("ai.settings.textCapability", isOn: capabilityBinding(.text))
            Toggle("ai.settings.visionCapability", isOn: capabilityBinding(.vision))
            SecureField("ai.settings.apiKey", text: $model.apiKey)
                .disabled(model.clearStoredKey)
            Text(model.draft.secretReference == nil ? String(localized: "ai.settings.keyOptional") : String(localized: "ai.settings.keepKey"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.draft.secretReference != nil {
                Toggle("ai.settings.clearKey", isOn: $model.clearStoredKey)
            }
            HStack {
                Button("ai.settings.save") { model.save() }
                Button("ai.settings.delete", role: .destructive) { model.remove() }
                    .disabled(!model.configuration.profiles.contains { $0.id == model.draft.id })
                Spacer()
                if model.isTesting {
                    ProgressView().controlSize(.small)
                    Button("ai.settings.cancelTest") { model.invalidateConnectionTest() }
                } else {
                    Button("ai.settings.test") { model.testConnection() }
                        .disabled(model.draft.capabilities.isEmpty)
                }
            }
            if let feedback = model.feedback { Text(feedback).textSelection(.enabled) }
            if let feedback = model.connectionFeedback { Text(feedback).textSelection(.enabled) }
        } header: {
            Text("ai.settings.editor")
        } footer: {
            Text("ai.settings.testExplanation")
        }
    }

    private func capabilityBinding(_ capability: AICapability) -> Binding<Bool> {
        Binding(get: { model.draft.capabilities.contains(capability) }, set: { enabled in
            if enabled { model.draft.capabilities.insert(capability) }
            else { model.draft.capabilities.remove(capability) }
        })
    }

    private func protocolTitle(_ apiProtocol: AIProtocol) -> String {
        switch apiProtocol {
        case .openAICompatible: return String(localized: "ai.settings.protocol.openAICompatible")
        case .anthropic: return String(localized: "ai.settings.protocol.anthropic")
        case .gemini: return String(localized: "ai.settings.protocol.gemini")
        case .ollama: return String(localized: "ai.settings.protocol.ollama")
        }
    }
}
