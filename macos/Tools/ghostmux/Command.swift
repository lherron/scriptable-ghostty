import Foundation

struct CommandContext {
    let args: [String]
    let client: GhostmuxClient
}

protocol GhostmuxCommand {
    static var name: String { get }
    static var aliases: [String] { get }
    static var help: String { get }
    static func run(context: CommandContext) throws
}
