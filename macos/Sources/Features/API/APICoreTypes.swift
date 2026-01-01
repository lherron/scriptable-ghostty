import Foundation

struct APIRequest {
    let id: String?
    let version: String
    let method: String
    let path: String
    let query: [String: String]
    let body: Data?

    init(
        id: String? = nil,
        version: String,
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil
    ) {
        self.id = id
        self.version = version
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

struct APIResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data?

    static func json<T: Encodable>(_ value: T, statusCode: Int = 200) -> APIResponse {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        do {
            let data = try encoder.encode(value)
            return APIResponse(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: data
            )
        } catch {
            return internalError("Failed to encode JSON: \(error)")
        }
    }

    static func ok(_ message: String = "OK") -> APIResponse {
        let body = ["status": "ok", "message": message]
        return jsonBody(body, statusCode: 200)
    }

    static func badRequest(_ message: String) -> APIResponse {
        return jsonBody(["error": "bad_request", "message": message], statusCode: 400)
    }

    static func notFound(_ message: String) -> APIResponse {
        return jsonBody(["error": "not_found", "message": message], statusCode: 404)
    }

    static func methodNotAllowed(_ allowed: [String]) -> APIResponse {
        return jsonBody(["error": "method_not_allowed", "allowed": allowed], statusCode: 405, headers: [
            "Allow": allowed.joined(separator: ", ")
        ])
    }

    static func internalError(_ message: String) -> APIResponse {
        return jsonBody(["error": "internal_error", "message": message], statusCode: 500)
    }

    private static func jsonBody(
        _ body: [String: Any],
        statusCode: Int,
        headers: [String: String] = [:]
    ) -> APIResponse {
        let data = try? JSONSerialization.data(withJSONObject: body, options: [])
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"

        return APIResponse(
            statusCode: statusCode,
            headers: allHeaders,
            body: data
        )
    }
}
