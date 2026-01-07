import AppKit

struct StatusBarState: Equatable {
    var left: String
    var center: String
    var right: String
    var visible: Bool
    var fgColor: NSColor?
    var bgColor: NSColor?

    static let hidden = StatusBarState(left: "", center: "", right: "", visible: false, fgColor: nil, bgColor: nil)
}
