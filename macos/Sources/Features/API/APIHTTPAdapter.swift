import Foundation

struct APIHTTPAdapter {
    func toAPIRequest(_ request: HTTPRequest) -> APIRequest {
        let components = request.path
            .split(separator: "/")
            .map(String.init)

        guard components.count >= 2, components[0] == "api" else {
            return APIRequest(
                version: "",
                method: request.method,
                path: request.path,
                query: request.query,
                body: request.body
            )
        }

        let version = components[1]
        let apiPathComponents = components.dropFirst(2)
        let apiPath = apiPathComponents.isEmpty
            ? "/"
            : "/" + apiPathComponents.joined(separator: "/")

        return APIRequest(
            version: version,
            method: request.method,
            path: apiPath,
            query: request.query,
            body: request.body
        )
    }

    func toHTTPResponse(_ response: APIResponse) -> HTTPResponse {
        HTTPResponse(
            statusCode: response.statusCode,
            statusMessage: statusMessage(for: response.statusCode),
            headers: response.headers,
            body: response.body
        )
    }

    private func statusMessage(for code: Int) -> String {
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
}
