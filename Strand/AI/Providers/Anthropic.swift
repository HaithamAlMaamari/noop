import Foundation
import StrandAnalytics

struct AnthropicClient: AIProviderClient {

    // Personal build: current Claude models (Opus 5.5, Fable 5.1, Sonnet 5) think adaptively before they
    // answer. A non-streamed reply therefore opens with a `thinking` block and carries the answer in a
    // later `text` block, thinking tokens count against `max_tokens`, and a stream can report an error
    // inside a 200 response. The pure parsing lives in `AnthropicWire` (StrandAnalytics, unit-tested).

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        let body: [String: Any] = [
            "model": AnthropicWire.migratedModel(model),
            "max_tokens": AnthropicWire.maxTokens,
            "system": systemPrompt,
            "messages": AnthropicWire.messages(messages.map { (role: $0.role.rawValue, content: $0.content) })
        ]

        let json = try await performRequest(try request(key: key, body: body), session: session)
        guard let text = AnthropicWire.replyText(json) else {
            throw emptyReplyError(json)   // #1074: surface the provider's real error if the 200 body has one
        }
        if AnthropicWire.stopReason(json) == "max_tokens" {
            return text + AnthropicWire.truncatedNote
        }
        return text
    }

    /// K1: Stream via `stream: true`. Anthropic SSE uses typed events; text arrives as `content_block_delta`
    /// / `text_delta` (thinking deltas are skipped by `SseDeltas.anthropicDelta`). An `error` event inside
    /// the 200 stream is thrown instead of being read as the end of a complete reply, and a reply stopped
    /// by the token cap says so.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        let body: [String: Any] = [
            "model": AnthropicWire.migratedModel(model),
            "max_tokens": AnthropicWire.maxTokens,
            "system": systemPrompt,
            "messages": AnthropicWire.messages(messages.map { (role: $0.role.rawValue, content: $0.content) }),
            "stream": true
        ]

        var stopReason: String?
        try await performStreamingRequest(try request(key: key, body: body), session: session) { payload in
            if let message = AnthropicWire.streamError(payload) {
                throw AICoachError.emptyReply("Anthropic stopped mid-reply: \(message). Try again in a moment.")
            }
            if let reason = AnthropicWire.streamStopReason(payload) { stopReason = reason }
            if let delta = SseDeltas.anthropicDelta(payload) {
                onDelta(delta)
            }
        }
        if stopReason == "max_tokens" { onDelta(AnthropicWire.truncatedNote) }
    }

    private func request(key: String, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: AIProvider.anthropic.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        var req = URLRequest(url: AIProvider.anthropic.modelsEndpoint)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        return parseModels(try await performRequest(req, session: session))
    }

    /// Pure: unwrap the `/models` body into ids (Anthropic keeps all non-empty). No network — unit-tested.
    func parseModels(_ json: [String: Any]) -> [String] {
        guard let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return id
        }
    }
}
