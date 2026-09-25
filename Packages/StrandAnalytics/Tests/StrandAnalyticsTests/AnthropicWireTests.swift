import XCTest
@testable import StrandAnalytics

/// Personal build: the Anthropic reply shapes current Claude models actually send.
final class AnthropicWireTests: XCTestCase {

    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
    }

    func testReplyTextSkipsLeadingThinkingBlock() {
        // Adaptive-thinking models put a thinking block (text omitted by default) before the answer.
        let body = json("""
        {"content":[{"type":"thinking","thinking":"","signature":"abc"},
                    {"type":"text","text":"Train upper body today."}],
         "stop_reason":"end_turn"}
        """)
        XCTAssertEqual(AnthropicWire.replyText(body), "Train upper body today.")
        XCTAssertEqual(AnthropicWire.stopReason(body), "end_turn")
    }

    func testReplyTextJoinsAllTextBlocksInOrder() {
        let body = json("""
        {"content":[{"type":"text","text":"Part one. "},{"type":"redacted_thinking","data":"x"},
                    {"type":"text","text":"Part two."}]}
        """)
        XCTAssertEqual(AnthropicWire.replyText(body), "Part one. Part two.")
    }

    func testReplyTextNilWhenOnlyThinking() {
        let body = json(#"{"content":[{"type":"thinking","thinking":"","signature":"abc"}],"stop_reason":"max_tokens"}"#)
        XCTAssertNil(AnthropicWire.replyText(body))
        XCTAssertEqual(AnthropicWire.stopReason(body), "max_tokens")
    }

    func testMessagesPrependsUserTurnWhenTranscriptOpensWithAssistant() {
        let wire = AnthropicWire.messages([
            (role: "assistant", content: "Today's brief\n\nYou are primed."),
            (role: "user", content: "What should I train?"),
        ])
        XCTAssertEqual(wire.count, 3)
        XCTAssertEqual(wire[0]["role"] as? String, "user")
        XCTAssertEqual(wire[0]["content"] as? String, AnthropicWire.openingUserTurn)
        XCTAssertEqual(wire[1]["role"] as? String, "assistant")
        XCTAssertEqual(wire[2]["role"] as? String, "user")
    }

    func testMessagesDropsEmptyTurnsAndKeepsUserFirst() {
        let wire = AnthropicWire.messages([
            (role: "user", content: "Hi"),
            (role: "assistant", content: "   "),
            (role: "user", content: "How was my sleep?"),
        ])
        XCTAssertEqual(wire.map { $0["role"] as? String }, ["user", "user"])
    }

    func testStreamErrorEventIsRecognised() {
        let payload = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        XCTAssertEqual(AnthropicWire.streamError(payload), "Overloaded")
        let noMessage = #"{"type":"error","error":{"type":"api_error"}}"#
        XCTAssertEqual(AnthropicWire.streamError(noMessage), "api_error")
        XCTAssertNil(AnthropicWire.streamError(#"{"type":"content_block_delta","delta":{"type":"text_delta","text":"x"}}"#))
        XCTAssertNil(AnthropicWire.streamError("not json"))
    }

    func testStreamStopReasonFromMessageDelta() {
        let payload = #"{"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null},"usage":{"output_tokens":16000}}"#
        XCTAssertEqual(AnthropicWire.streamStopReason(payload), "max_tokens")
        XCTAssertNil(AnthropicWire.streamStopReason(#"{"type":"message_stop"}"#))
    }

    func testThinkingDeltasAreNotTreatedAsText() {
        let thinking = #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#
        let signature = #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#
        let text = #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Go."}}"#
        XCTAssertNil(SseDeltas.anthropicDelta(thinking))
        XCTAssertNil(SseDeltas.anthropicDelta(signature))
        XCTAssertEqual(SseDeltas.anthropicDelta(text), "Go.")
    }

    func testRetiredModelsMigrateToDefault() {
        XCTAssertEqual(AnthropicWire.migratedModel("claude-3-5-sonnet-latest"), AnthropicWire.defaultModel)
        XCTAssertEqual(AnthropicWire.migratedModel("claude-opus-5-5"), "claude-opus-5-5")
        XCTAssertTrue(AnthropicWire.modelOptions.contains(AnthropicWire.defaultModel))
        XCTAssertTrue(AnthropicWire.retiredModels.isDisjoint(with: AnthropicWire.modelOptions))
    }
}
