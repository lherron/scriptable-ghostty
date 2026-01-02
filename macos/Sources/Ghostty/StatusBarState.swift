import Foundation

struct StatusBarState: Equatable {
    var left: String
    var center: String
    var right: String
    var visible: Bool

    static let hidden = StatusBarState(left: "", center: "", right: "", visible: false)
}
