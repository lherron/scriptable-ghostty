import Foundation

/// A simple HTTP/1.1 request representation
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    /// Parse HTTP request data into an HTTPRequest struct
    static func parse(data: Data) -> HTTPRequest? {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Split headers and body
        let parts = string.components(separatedBy: "\r\n\r\n")
        guard !parts.isEmpty else { return nil }

        let headerSection = parts[0]
        let bodyData: Data? = if parts.count > 1 && !parts[1].isEmpty {
            parts[1].data(using: .utf8)
        } else {
            nil
        }

        // Parse request line and headers
        let lines = headerSection.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        // Parse request line: "GET /path HTTP/1.1"
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }

        let method = requestLine[0]
        let path = requestLine[1]

        // Parse headers
        var headers: [String: String] = [:]
        for i in 1..<lines.count {
            let headerLine = lines[i]
            if let colonIndex = headerLine.firstIndex(of: ":") {
                let key = String(headerLine[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(headerLine[headerLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: bodyData)
    }
}

/// A simple HTTP/1.1 response builder
struct HTTPResponse {
    let statusCode: Int
    let statusMessage: String
    let headers: [String: String]
    let body: Data?

    /// Serialize the response to Data for sending over the network
    func serialize() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(statusMessage)\r\n"

        // Add headers
        var allHeaders = headers
        if let body = body {
            allHeaders["Content-Length"] = "\(body.count)"
        }
        allHeaders["Connection"] = "close"

        for (key, value) in allHeaders {
            response += "\(key): \(value)\r\n"
        }

        response += "\r\n"

        var data = response.data(using: .utf8) ?? Data()
        if let body = body {
            data.append(body)
        }

        return data
    }

    // MARK: - Factory Methods

    /// Create a JSON response with the given Encodable value
    static func json<T: Encodable>(_ value: T, statusCode: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        do {
            let data = try encoder.encode(value)
            return HTTPResponse(
                statusCode: statusCode,
                statusMessage: statusMessage(for: statusCode),
                headers: ["Content-Type": "application/json"],
                body: data
            )
        } catch {
            return internalError("Failed to encode JSON: \(error)")
        }
    }

    /// Create a 200 OK response
    static func ok(_ message: String = "OK") -> HTTPResponse {
        let body = "{\"status\": \"ok\", \"message\": \"\(message)\"}".data(using: .utf8)
        return HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    /// Create a 400 Bad Request response
    static func badRequest(_ message: String) -> HTTPResponse {
        let body = "{\"error\": \"bad_request\", \"message\": \"\(escapeJSON(message))\"}".data(using: .utf8)
        return HTTPResponse(
            statusCode: 400,
            statusMessage: "Bad Request",
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    /// Create a 404 Not Found response
    static func notFound(_ message: String) -> HTTPResponse {
        let body = "{\"error\": \"not_found\", \"message\": \"\(escapeJSON(message))\"}".data(using: .utf8)
        return HTTPResponse(
            statusCode: 404,
            statusMessage: "Not Found",
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    /// Create a 405 Method Not Allowed response
    static func methodNotAllowed(_ allowed: [String]) -> HTTPResponse {
        let body = "{\"error\": \"method_not_allowed\", \"allowed\": [\(allowed.map { "\"\($0)\"" }.joined(separator: ", "))]}".data(using: .utf8)
        return HTTPResponse(
            statusCode: 405,
            statusMessage: "Method Not Allowed",
            headers: [
                "Content-Type": "application/json",
                "Allow": allowed.joined(separator: ", ")
            ],
            body: body
        )
    }

    /// Create a 500 Internal Server Error response
    static func internalError(_ message: String) -> HTTPResponse {
        let body = "{\"error\": \"internal_error\", \"message\": \"\(escapeJSON(message))\"}".data(using: .utf8)
        return HTTPResponse(
            statusCode: 500,
            statusMessage: "Internal Server Error",
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    // MARK: - Helpers

    private static func statusMessage(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    private static func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
