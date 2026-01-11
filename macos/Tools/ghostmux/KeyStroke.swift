import Foundation

func keyStrokeForScalar(_ scalar: UnicodeScalar) -> KeyStroke? {
    switch scalar.value {
    case 0x09:
        return KeyStroke(key: "tab", mods: [], text: "\t", unshiftedCodepoint: scalar.value)
    case 0x0A, 0x0D:
        return KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A)
    case 0x20:
        return KeyStroke(key: "space", mods: [], text: " ", unshiftedCodepoint: scalar.value)
    case 0x30...0x39:
        return KeyStroke(key: "digit\(scalar.value - 0x30)", mods: [], text: String(scalar), unshiftedCodepoint: scalar.value)
    case 0x41...0x5A:
        let lower = UnicodeScalar(scalar.value + 0x20)!
        return KeyStroke(
            key: String(lower),
            mods: ["shift"],
            text: String(scalar),
            unshiftedCodepoint: lower.value
        )
    case 0x61...0x7A:
        return KeyStroke(
            key: String(scalar),
            mods: [],
            text: String(scalar),
            unshiftedCodepoint: scalar.value
        )
    default:
        break
    }

    let char = Character(scalar)
    switch char {
    case "`": return KeyStroke(key: "backquote", mods: [], text: "`", unshiftedCodepoint: 0x60)
    case "~": return KeyStroke(key: "backquote", mods: ["shift"], text: "~", unshiftedCodepoint: 0x60)
    case "-": return KeyStroke(key: "minus", mods: [], text: "-", unshiftedCodepoint: 0x2D)
    case "_": return KeyStroke(key: "minus", mods: ["shift"], text: "_", unshiftedCodepoint: 0x2D)
    case "=": return KeyStroke(key: "equal", mods: [], text: "=", unshiftedCodepoint: 0x3D)
    case "+": return KeyStroke(key: "equal", mods: ["shift"], text: "+", unshiftedCodepoint: 0x3D)
    case "[": return KeyStroke(key: "bracketLeft", mods: [], text: "[", unshiftedCodepoint: 0x5B)
    case "{": return KeyStroke(key: "bracketLeft", mods: ["shift"], text: "{", unshiftedCodepoint: 0x5B)
    case "]": return KeyStroke(key: "bracketRight", mods: [], text: "]", unshiftedCodepoint: 0x5D)
    case "}": return KeyStroke(key: "bracketRight", mods: ["shift"], text: "}", unshiftedCodepoint: 0x5D)
    case "\\": return KeyStroke(key: "backslash", mods: [], text: "\\", unshiftedCodepoint: 0x5C)
    case "|": return KeyStroke(key: "backslash", mods: ["shift"], text: "|", unshiftedCodepoint: 0x5C)
    case ";": return KeyStroke(key: "semicolon", mods: [], text: ";", unshiftedCodepoint: 0x3B)
    case ":": return KeyStroke(key: "semicolon", mods: ["shift"], text: ":", unshiftedCodepoint: 0x3B)
    case "'": return KeyStroke(key: "quote", mods: [], text: "'", unshiftedCodepoint: 0x27)
    case "\"": return KeyStroke(key: "quote", mods: ["shift"], text: "\"", unshiftedCodepoint: 0x27)
    case ",": return KeyStroke(key: "comma", mods: [], text: ",", unshiftedCodepoint: 0x2C)
    case "<": return KeyStroke(key: "comma", mods: ["shift"], text: "<", unshiftedCodepoint: 0x2C)
    case ".": return KeyStroke(key: "period", mods: [], text: ".", unshiftedCodepoint: 0x2E)
    case ">": return KeyStroke(key: "period", mods: ["shift"], text: ">", unshiftedCodepoint: 0x2E)
    case "/": return KeyStroke(key: "slash", mods: [], text: "/", unshiftedCodepoint: 0x2F)
    case "?": return KeyStroke(key: "slash", mods: ["shift"], text: "?", unshiftedCodepoint: 0x2F)
    case "!": return KeyStroke(key: "digit1", mods: ["shift"], text: "!", unshiftedCodepoint: 0x31)
    case "@": return KeyStroke(key: "digit2", mods: ["shift"], text: "@", unshiftedCodepoint: 0x32)
    case "#": return KeyStroke(key: "digit3", mods: ["shift"], text: "#", unshiftedCodepoint: 0x33)
    case "$": return KeyStroke(key: "digit4", mods: ["shift"], text: "$", unshiftedCodepoint: 0x34)
    case "%": return KeyStroke(key: "digit5", mods: ["shift"], text: "%", unshiftedCodepoint: 0x35)
    case "^": return KeyStroke(key: "digit6", mods: ["shift"], text: "^", unshiftedCodepoint: 0x36)
    case "&": return KeyStroke(key: "digit7", mods: ["shift"], text: "&", unshiftedCodepoint: 0x37)
    case "*": return KeyStroke(key: "digit8", mods: ["shift"], text: "*", unshiftedCodepoint: 0x38)
    case "(": return KeyStroke(key: "digit9", mods: ["shift"], text: "(", unshiftedCodepoint: 0x39)
    case ")": return KeyStroke(key: "digit0", mods: ["shift"], text: ")", unshiftedCodepoint: 0x30)
    default: return nil
    }
}

func strokesForLiteral(_ text: String) throws -> [KeyStroke] {
    var strokes: [KeyStroke] = []
    for scalar in text.unicodeScalars {
        guard let stroke = keyStrokeForScalar(scalar) else {
            throw GhostmuxError.message("unsupported character: \(scalar)")
        }
        strokes.append(stroke)
    }
    return strokes
}

func strokesForToken(_ token: String) throws -> [KeyStroke] {
    let lower = token.lowercased()
    let namedKeys: [String: KeyStroke] = [
        "enter": KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A),
        "return": KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A),
        "tab": KeyStroke(key: "tab", mods: [], text: "\t", unshiftedCodepoint: 0x09),
        "space": KeyStroke(key: "space", mods: [], text: " ", unshiftedCodepoint: 0x20),
        "escape": KeyStroke(key: "escape", mods: [], text: nil, unshiftedCodepoint: 0),
        "esc": KeyStroke(key: "escape", mods: [], text: nil, unshiftedCodepoint: 0),
        "bspace": KeyStroke(key: "backspace", mods: [], text: nil, unshiftedCodepoint: 0),
        "backspace": KeyStroke(key: "backspace", mods: [], text: nil, unshiftedCodepoint: 0),
        "dc": KeyStroke(key: "delete", mods: [], text: nil, unshiftedCodepoint: 0),
        "delete": KeyStroke(key: "delete", mods: [], text: nil, unshiftedCodepoint: 0),
    ]

    if let named = namedKeys[lower] {
        return [named]
    }

    let ctrlPrefixes = ["c-", "ctrl-"]
    for prefix in ctrlPrefixes {
        if lower.hasPrefix(prefix) {
            let remainder = String(token.dropFirst(prefix.count))
            if remainder.isEmpty {
                throw GhostmuxError.message("invalid key: \(token)")
            }
            if let named = namedKeys[remainder.lowercased()] {
                return [KeyStroke(
                    key: named.key,
                    mods: ["ctrl"] + named.mods,
                    text: nil,
                    unshiftedCodepoint: named.unshiftedCodepoint
                )]
            }
            if remainder.count == 1, let scalar = remainder.unicodeScalars.first,
               let base = keyStrokeForScalar(scalar) {
                return [KeyStroke(
                    key: base.key,
                    mods: ["ctrl"] + base.mods,
                    text: nil,
                    unshiftedCodepoint: base.unshiftedCodepoint
                )]
            }
            throw GhostmuxError.message("unsupported key: \(token)")
        }
    }

    if token.count == 1, let scalar = token.unicodeScalars.first, let stroke = keyStrokeForScalar(scalar) {
        return [stroke]
    }

    return try strokesForLiteral(token)
}
