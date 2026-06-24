import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Foundation Models provider for iOS. The on-device and Private Cloud Compute variants share
/// the same `LanguageModelSession` chat path; the picker decides which model backs the session.
struct AppleFoundationModelsClient: AIProviderClient {
    enum Mode {
        case onDevice
        case privateCloud

        var modelName: String {
            switch self {
            case .onDevice: return "SystemLanguageModel.default"
            case .privateCloud: return "PrivateCloudComputeLanguageModel"
            }
        }
    }

    let mode: Mode

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
#if canImport(FoundationModels)
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
            throw AICoachError.network("Apple Foundation Models in NOOP require iOS 27 or later.")
        }

        return try await sendWithFoundationModels(
            systemPrompt: systemPrompt,
            messages: messages
        )
#else
        throw AICoachError.network("The Foundation Models framework is unavailable in this build.")
#endif
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        [mode.modelName]
    }

#if canImport(FoundationModels)
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func sendWithFoundationModels(
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)]
    ) async throws -> String {
        switch mode {
        case .onDevice:
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AICoachError.network("Apple Intelligence is not available or the on-device model is not ready.")
            }
            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            return try await responseText(from: session, messages: messages)

        case .privateCloud:
            let model = PrivateCloudComputeLanguageModel()
            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            return try await responseText(from: session, messages: messages)
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func responseText(
        from session: LanguageModelSession,
        messages: [(role: ChatMessage.Role, content: String)]
    ) async throws -> String {
        let prompt = messages.map { message in
            let speaker = message.role == .assistant ? "Assistant" : "User"
            return "\(speaker): \(message.content)"
        }.joined(separator: "\n\n")

        let response = try await session.respond(to: Prompt { "\(prompt)" })
        return response.content
    }
#endif
}
