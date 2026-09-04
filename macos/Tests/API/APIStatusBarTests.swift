import Foundation
import Testing
@testable import Ghostty

@Suite
struct APIStatusBarTests {
    @MainActor
    @Test func absentBarDefaultsToPrimary() throws {
        let response = handlers.getStatusBarV2(uuid: UUID().uuidString, query: [:])

        #expect(response.statusCode == 404)
        #expect(try errorBody(response)["error"] as? String == "terminal_not_found")
    }

    @MainActor
    @Test func secondaryBarIsTrimmedAndCaseInsensitive() throws {
        let response = handlers.getStatusBarV2(
            uuid: UUID().uuidString,
            query: ["bar": "  SeCoNdArY\n"]
        )

        #expect(response.statusCode == 404)
        #expect(try errorBody(response)["error"] as? String == "terminal_not_found")
    }

    @MainActor
    @Test func invalidBarReturnsInvalidAction() throws {
        let response = handlers.getStatusBarV2(
            uuid: UUID().uuidString,
            query: ["bar": " NOPE "]
        )
        let body = try errorBody(response)

        #expect(response.statusCode == 400)
        #expect(body["error"] as? String == "invalid_action")
        #expect(body["message"] as? String == "Invalid bar: nope")
    }

    @MainActor
    @Test func invalidBarInPostWinsOverMissingMutationFields() throws {
        let response = handlers.setStatusBarV2(
            uuid: UUID().uuidString,
            body: Data(#"{"bar":"nope"}"#.utf8)
        )
        let body = try errorBody(response)

        #expect(response.statusCode == 400)
        #expect(body["error"] as? String == "invalid_action")
        #expect(body["message"] as? String == "Invalid bar: nope")
    }

    @Test func responseAlwaysEncodesSelectedBar() throws {
        let response = StatusBarStateResponse(
            left: "",
            center: "",
            right: "",
            visible: false,
            fg: nil,
            bg: nil,
            scope: "surface",
            bar: "primary"
        )
        let encoded = try JSONEncoder().encode(response)
        let body = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(body["bar"] as? String == "primary")
    }

    @MainActor
    private var handlers: APIHandlers {
        APIHandlers(surfaceProvider: { [] })
    }

    private func errorBody(_ response: APIResponse) throws -> [String: Any] {
        let data = try #require(response.body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
