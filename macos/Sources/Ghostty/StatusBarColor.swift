import AppKit

/// Parses color strings for the status bar API.
/// Supports 24 named colors (ANSI + supplementary), hex values, and "default" keyword.
enum StatusBarColor {
    // MARK: - Named Colors (24 total)

    /// ANSI terminal colors (16)
    private static let ansiColors: [String: NSColor] = [
        "black": NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        "red": NSColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1),
        "green": NSColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1),
        "yellow": NSColor(srgbRed: 0.8, green: 0.8, blue: 0, alpha: 1),
        "blue": NSColor(srgbRed: 0, green: 0, blue: 0.8, alpha: 1),
        "magenta": NSColor(srgbRed: 0.8, green: 0, blue: 0.8, alpha: 1),
        "cyan": NSColor(srgbRed: 0, green: 0.8, blue: 0.8, alpha: 1),
        "white": NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1),
        "brightblack": NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1),
        "brightred": NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
        "brightgreen": NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
        "brightyellow": NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1),
        "brightblue": NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
        "brightmagenta": NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1),
        "brightcyan": NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1),
        "brightwhite": NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
    ]

    /// Supplementary CSS colors (8)
    private static let supplementaryColors: [String: NSColor] = [
        "orange": NSColor(srgbRed: 1, green: 0.533, blue: 0, alpha: 1),
        "pink": NSColor(srgbRed: 1, green: 0.412, blue: 0.706, alpha: 1),
        "purple": NSColor(srgbRed: 0.5, green: 0, blue: 0.5, alpha: 1),
        "teal": NSColor(srgbRed: 0, green: 0.5, blue: 0.5, alpha: 1),
        "navy": NSColor(srgbRed: 0, green: 0, blue: 0.5, alpha: 1),
        "maroon": NSColor(srgbRed: 0.5, green: 0, blue: 0, alpha: 1),
        "gray": NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1),
        "silver": NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1),
    ]

    /// All named colors combined
    private static let allNamedColors: [String: NSColor] = {
        var colors = ansiColors
        colors.merge(supplementaryColors) { $1 }
        return colors
    }()

    /// List of all supported color names
    static var supportedColorNames: [String] {
        Array(allNamedColors.keys).sorted()
    }

    // MARK: - Parsing

    /// Parse result for color strings
    enum ParseResult {
        case color(NSColor)
        case useDefault
        case invalid(String)
    }

    /// Parse a color string.
    /// - Parameter value: The color string to parse (named color, hex, or "default")
    /// - Returns: ParseResult indicating the color, default, or error
    static func parse(_ value: String) -> ParseResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // Check for "default" keyword
        if lowercased == "default" {
            return .useDefault
        }

        // Check named colors (case-insensitive)
        if let color = allNamedColors[lowercased] {
            return .color(color)
        }

        // Try to parse as hex
        if let color = parseHex(trimmed) {
            return .color(color)
        }

        return .invalid(trimmed)
    }

    /// Parse a hex color string.
    /// Supports formats: #RGB, #RRGGBB, RGB, RRGGBB
    private static func parseHex(_ value: String) -> NSColor? {
        var hex = value
        if hex.hasPrefix("#") {
            hex = String(hex.dropFirst())
        }

        // Expand 3-character hex to 6-character
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }

        guard hex.count == 6 else {
            return nil
        }

        guard let rgb = UInt64(hex, radix: 16) else {
            return nil
        }

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0

        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Generate an error message for invalid colors
    static func errorMessage(for invalidValue: String) -> String {
        "Invalid color '\(invalidValue)'. Use named color (\(supportedColorNames.prefix(5).joined(separator: ", ")), ...), hex (#RRGGBB), or 'default'"
    }
}
