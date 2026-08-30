import Foundation
import Testing
@testable import Ghostty

@Suite
struct APITabModelsTests {
    @Test func windowPreservesTabGroupingAndFlatTerminalUnion() throws {
        let firstTab = TabModelV2(
            id: "tab-a",
            title: "Build",
            selected: true,
            focused: true,
            terminalIds: ["pane-a1", "pane-a2"]
        )
        let secondTab = TabModelV2(
            id: "tab-b",
            title: "Logs",
            selected: false,
            focused: false,
            terminalIds: ["pane-b1"]
        )

        let window = WindowModelV2(
            id: "window-1",
            title: "Build",
            focused: true,
            tabs: [firstTab, secondTab],
            metadata: [:]
        )

        #expect(window.tabs.map(\.terminalIds) == [
            ["pane-a1", "pane-a2"],
            ["pane-b1"],
        ])
        #expect(window.terminalIds == ["pane-a1", "pane-a2", "pane-b1"])

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(window)) as? [String: Any]
        )
        let encodedTabs = try #require(object["tabs"] as? [[String: Any]])
        #expect(object["terminal_ids"] as? [String] == ["pane-a1", "pane-a2", "pane-b1"])
        #expect(encodedTabs[0]["terminal_ids"] as? [String] == ["pane-a1", "pane-a2"])
        #expect(encodedTabs[1]["terminal_ids"] as? [String] == ["pane-b1"])
    }

    @Test func terminalEncodesTabIdentityNextToManagedWindowIdentity() throws {
        let terminal = TerminalModelV2(
            id: "pane-a1",
            windowId: "window-1",
            tabId: "tab-a",
            title: "Build",
            workingDirectory: "/tmp",
            kind: "normal",
            focused: true,
            realized: true,
            columns: 120,
            rows: 40,
            cellWidth: 10,
            cellHeight: 20
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(terminal)) as? [String: Any]
        )
        #expect(object["window_id"] as? String == "window-1")
        #expect(object["tab_id"] as? String == "tab-a")
    }
}
