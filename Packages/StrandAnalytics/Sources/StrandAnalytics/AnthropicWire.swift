import Foundation

// AnthropicWire.swift — pure helpers for the Anthropic Messages API as the current models speak it.
//
// Personal build. The coach's Anthropic client was written for models that answered with a single
// `text` block. Current Claude models (Opus 5.5, Fable 5.1, Sonnet 5) think adaptively by default, so a
// non-streamed reply starts with a `thinking` block (its text omitted by default) and the answer comes in
// a LATER block; thinking tokens also count against `max_tokens`. These helpers keep the parsing pure and
// unit-testable: no network, no UI types, only JSON dictionaries and strings.

public enum AnthropicWire {

    /// `max_tokens` for coach requests. Thinking tokens count against it on adaptive-thinking models, so
    /// the old 4096 cap could be spent before the answer began. A cap, not a target: the system prompt
    /// keeps replies short.
    public static let maxTokens = 16_000

    /// Models offered in the picker, newest first. Retired ids are not offered (a request to one fails).
    public static let modelOptions: [String] = [
        "claude-sonnet-5",
        "claude-opus-5-5",
        "claude-fable-5-1",
        "claude-haiku-4-5-20251001",
        "claude-opus-4-8",
        "claude-sonnet-4-6",
    ]

    /// Default for a fresh setup: fast, strong, and the one current model whose thinking can be tuned.
    public static let defaultModel = "claude-sonnet-5"

    /// Ids that no longer answer (retired by Anthropic). A persisted choice of one is migrated.
    public static let retiredModels: Set<String> = [
        "claude-3-7-sonnet-latest",
        "claude-3-5-sonnet-latest",
        "claude-3-5-haiku-latest",
        "claude-3-opus-latest",
        "claude-3-7-sonnet-20250219",
        "claude-3-5-sonnet-20241022",
        "claude-3-5-sonnet-20240620",
        "claude-3-5-haiku-20241022",
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307",
    ]

    /// A persisted model id, or the default when that id has been retired.
    public static func migratedModel(_ id: String) -> String {
        retiredModels.contains(id) ? defaultModel : id
    }

    /// Build the `messages` array for a request.
    ///
    /// The API requires the conversation to open with a `user` turn, and rejects empty text. The coach
    /// transcript can open with an assistant turn (the morning brief is stored as one), so a short user
    /// turn is placed in front of it rather than dropping the brief the user can see. Empty turns are
    /// skipped. `role` is the raw role string ("user" / "assistant").
    public static func messages(_ turns: [(role: String, content: String)]) -> [[String: Any]] {
        var wire: [[String: Any]] = []
        for t in turns {
            let text = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let role = (t.role == "assistant") ? "assistant" : "user"
            wire.append(["role": role, "content": t.content])
        }
        if let first = wire.first, (first["role"] as? String) == "assistant" {
            wire.insert(["role": "user", "content": openingUserTurn], at: 0)
        }
        return wire
    }

    /// The stand-in user turn placed before a transcript that opens with the coach's own message.
    public static let openingUserTurn = "(Start of today's conversation. Your earlier message follows.)"

    /// The answer text of a non-streamed Messages response: every `text` block joined in order,
    /// skipping `thinking`, `redacted_thinking` and any tool blocks. Nil when there is no text at all.
    public static func replyText(_ json: [String: Any]) -> String? {
        guard let content = json["content"] as? [[String: Any]] else { return nil }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The `stop_reason` of a non-streamed response.
    public static func stopReason(_ json: [String: Any]) -> String? {
        json["stop_reason"] as? String
    }

    /// Note appended when a reply ended because it hit `max_tokens`, so a cut-off answer is never
    /// presented as a complete one.
    public static let truncatedNote = "\n\n*(Reply cut off at the length limit. Ask me to continue.)*"

    /// An error the API reported INSIDE a 200 stream (`event: error` followed by
    /// `data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`). Returns the
    /// provider's message (or its error type when the message is empty); nil for every other payload.
    public static func streamError(_ payload: String) -> String? {
        guard let obj = jsonObject(payload), (obj["type"] as? String) == "error" else { return nil }
        let err = obj["error"] as? [String: Any]
        let message = ((err?["message"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }
        return (err?["type"] as? String) ?? "error"
    }

    /// The `stop_reason` carried by a streamed `message_delta` event; nil for every other event.
    public static func streamStopReason(_ payload: String) -> String? {
        guard let obj = jsonObject(payload), (obj["type"] as? String) == "message_delta",
              let delta = obj["delta"] as? [String: Any] else { return nil }
        return delta["stop_reason"] as? String
    }

    private static func jsonObject(_ payload: String) -> [String: Any]? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
