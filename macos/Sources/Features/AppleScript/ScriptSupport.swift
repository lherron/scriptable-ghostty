import AppKit

extension NSApplication {
    @objc var isAppleScriptEnabled: Bool {
        true
    }

    @objc func validateScript(command: NSScriptCommand) -> Bool {
        isAppleScriptEnabled
    }
}

extension ObjectIdentifier {
    var hexString: String {
        String(UInt(bitPattern: self), radix: 16)
    }
}

@MainActor
@objc(GhosttyScriptTerminal)
final class ScriptTerminal: NSObject {
    private weak var surfaceView: Ghostty.SurfaceView?

    init(surfaceView: Ghostty.SurfaceView) {
        self.surfaceView = surfaceView
    }

    @objc(id)
    var idValue: String {
        surfaceView?.id.uuidString ?? ""
    }

    @objc(title)
    var title: String {
        surfaceView?.window?.title ?? ""
    }
}

@MainActor
@objc(GhosttyScriptWindow)
final class ScriptWindow: NSObject {
    private weak var controller: BaseTerminalController?

    init(controller: BaseTerminalController) {
        self.controller = controller
    }

    func tabIndex(for controller: BaseTerminalController) -> Int {
        self.controller === controller ? 1 : 0
    }

    func tabIsSelected(_ controller: BaseTerminalController) -> Bool {
        self.controller === controller
    }
}
