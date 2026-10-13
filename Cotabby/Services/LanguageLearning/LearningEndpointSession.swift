import Foundation

/// Learning sends text only to the endpoint the user selected. A separate session reuses the
/// OpenAI-compatible wire implementation without letting redirects forward source text or keys
/// to another destination. URLSession retains its delegate for the session's lifetime.
nonisolated final class LearningEndpointSession: NSObject, URLSessionTaskDelegate {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: LearningEndpointSession(), delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
