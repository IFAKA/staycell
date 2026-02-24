import Foundation
import os.log

/// Local Ollama LLM service for the Reflect tab.
/// Uses nonisolated static methods so they can be called from async contexts
/// without requiring main-actor dispatch.
@MainActor
final class OllamaService {
    nonisolated private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "ollama")
    nonisolated private static let baseURL = URL(string: "http://localhost:11434")!

    /// The local model used for focus coaching.
    nonisolated static let model = "llama3.2:latest"

    struct ChatMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    // MARK: - Health check

    /// Returns true if Ollama is reachable at localhost:11434.
    nonisolated static func isRunning() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Returns true if the given model name (matched by prefix) is installed.
    nonisolated static func isModelInstalled(_ model: String) async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return false }
            let prefix = model.components(separatedBy: ":").first ?? model
            return models.contains { ($0["name"] as? String ?? "").hasPrefix(prefix) }
        } catch {
            return false
        }
    }

    // MARK: - Model pulling

    /// Pulls a model from Ollama, streaming progress via `onProgress`.
    /// `onProgress` receives (0.0–1.0, statusString). Dispatch to @MainActor at call site.
    nonisolated static func pullModel(
        _ model: String,
        onProgress: @Sendable (Double, String) -> Void
    ) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": model])

        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let status = json["status"] as? String ?? ""
            let completed = json["completed"] as? Double ?? 0
            let total = json["total"] as? Double ?? 1
            let progress = total > 0 ? min(completed / total, 1.0) : 0
            onProgress(progress, status)
        }
    }

    // MARK: - Chat

    /// Streams a chat response from Ollama.
    /// `system` is injected as the first message. `onToken` called per streamed token.
    /// Dispatch `onToken` to @MainActor at call site.
    nonisolated static func chat(
        model: String,
        messages: [ChatMessage],
        system: String,
        onToken: @Sendable (String) -> Void
    ) async throws {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemMsg: [String: String] = ["role": "system", "content": system]
        let msgDicts = [systemMsg] + messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": msgDicts, "stream": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StayCellError.ollamaRequestFailed(
                underlying: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.isEmpty else { continue }
            onToken(content)
        }
    }
}
