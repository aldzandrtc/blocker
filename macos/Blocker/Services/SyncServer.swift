import Foundation
import Network
import AppKit

extension Notification.Name {
    static let syncServerActivate = Notification.Name("syncServerActivate")
}

final class SyncServer {
    private let store: SettingsStore
    private var listener: NWListener?
    let port: UInt16 = 14923

    init(store: SettingsStore) {
        self.store = store
    }

    /// Returns true if the server started successfully on the port.
    func start() -> Bool {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params) else {
            print("SyncServer: failed to create listener on port \(port)")
            return false
        }

        let sem = DispatchSemaphore(value: 0)
        var started = false

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                started = true
                sem.signal()
            case .failed(let err):
                print("SyncServer: failed — \(err)")
                sem.signal()
            case .cancelled:
                break
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener

        _ = sem.wait(timeout: .now() + 2)

        if started {
            print("SyncServer: listening on 127.0.0.1:\(port)")
        }
        return started
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        receiveAll(from: conn, buffer: Data())
    }

    private func receiveAll(from conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
            [weak self] data, _, isComplete, err in
            guard let self else { conn.cancel(); return }
            if err != nil {
                conn.cancel()
                return
            }
            var buf = buffer
            if let data = data { buf.append(data) }

            if isComplete || self.requestComplete(buf) {
                guard let request = String(data: buf, encoding: .utf8) else {
                    conn.cancel()
                    return
                }
                // Handlers await the AI, so the whole response path is async —
                // no blocking the network queue on a semaphore.
                Task {
                    let response = await self.process(request)
                    conn.send(content: response.data(using: .utf8),
                              completion: .contentProcessed({ _ in conn.cancel() }))
                }
            } else {
                self.receiveAll(from: conn, buffer: buf)
            }
        }
    }

    private func requestComplete(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8) else { return true }
        if str.hasPrefix("GET") || str.hasPrefix("HEAD") || str.hasPrefix("OPTIONS") {
            return str.contains("\r\n\r\n")
        }
        if let clRange = str.range(of: "Content-Length:") {
            let after = str[clRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            if let clEnd = after.firstIndex(where: { !$0.isNumber }),
               let contentLength = Int(after[..<clEnd]) {
                if let bodyStart = str.range(of: "\r\n\r\n") {
                    let body = str[bodyStart.upperBound...]
                    return body.utf8.count >= contentLength
                }
            }
        }
        return str.contains("\r\n\r\n")
    }

    // MARK: - Request Processing

    private func process(_ raw: String) async -> String {
        let parts = parseRequest(raw)
        let method = parts.method
        let path = parts.path
        let body = parts.body
        // Only the extension may talk to us. Without this, any web page you visit
        // could read the blocklist and profile, or burn API credits.
        let origin = parts.origin.flatMap { $0.hasPrefix("chrome-extension://") ? $0 : nil }

        await MainActor.run { store.lastExtensionContact = Date() }

        switch (method, path) {
        case ("GET", "/ping"):
            return Self.http(200, "pong", origin: origin, contentType: "text/plain")

        case ("POST", "/activate"):
            await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
            return Self.http(200, #"{"ok":true}"#, origin: origin)

        case ("GET", "/blocklist"):
            let json = await MainActor.run { encode(blockedWebsites()) } ?? "[]"
            return Self.http(200, json, origin: origin)

        case ("GET", "/profile"):
            let json = await MainActor.run { encode(store.profile) } ?? "{}"
            return Self.http(200, json, origin: origin)

        case ("GET", "/problem"):
            return await handleProblem(origin: origin)

        case ("POST", "/judge"):
            return await handleJudge(body: body, origin: origin)

        case ("POST", "/verify"):
            return await handleVerify(body: body, origin: origin)

        case ("POST", "/history"):
            return await handleHistory(body: body, origin: origin)

        case ("OPTIONS", _):
            return Self.http(200, "", origin: origin)

        default:
            return Self.http(404, #"{"error":"not found"}"#, origin: origin)
        }
    }

    private func parseRequest(_ raw: String) -> (method: String, path: String, body: String?, origin: String?) {
        let headerEnd = raw.range(of: "\r\n\r\n")
        let headerSection = headerEnd.map { String(raw[..<$0.lowerBound]) } ?? raw
        let lines = headerSection.components(separatedBy: "\r\n")

        guard let first = lines.first else { return ("", "", nil, nil) }
        let reqParts = first.components(separatedBy: " ")
        let method = reqParts.count > 0 ? reqParts[0] : ""
        let path = reqParts.count > 1 ? reqParts[1] : ""

        let origin = lines.dropFirst()
            .first { $0.lowercased().hasPrefix("origin:") }
            .map { String($0.dropFirst("origin:".count)).trimmingCharacters(in: .whitespaces) }

        let body = headerEnd.map { String(raw[$0.upperBound...]) }
        return (method, path, body, origin)
    }

    // MARK: - Handlers

    private func handleProblem(origin: String?) async -> String {
        let client = await MainActor.run { makeClient() }
        guard !client.apiKey.isEmpty else {
            return Self.http(503, #"{"error":"API key not configured"}"#, origin: origin)
        }
        do {
            let gen = ProblemGenerator(client: client, store: store)
            let problem = try await gen.generate()
            guard let data = try? JSONEncoder().encode(problem),
                  let json = String(data: data, encoding: .utf8) else {
                return Self.http(500, #"{"error":"could not encode problem"}"#, origin: origin)
            }
            return Self.http(200, json, origin: origin)
        } catch let error as AiError {
            return Self.http(502, errorJSON(error.message), origin: origin)
        } catch {
            return Self.http(502, errorJSON("Could not generate a problem."), origin: origin)
        }
    }

    private func handleJudge(body: String?, origin: String?) async -> String {
        guard let params = jsonObject(from: body),
              let appName = params["app_name"] as? String,
              let argument = params["argument"] as? String
        else {
            return Self.http(400, #"{"error":"missing app_name or argument"}"#, origin: origin)
        }
        let client = await MainActor.run { makeClient() }
        guard !client.apiKey.isEmpty else {
            return Self.http(503, #"{"error":"API key not configured"}"#, origin: origin)
        }

        let judge = BlocklistJudge(client: client)
        let result = await judge.judge(appName: appName, argument: argument)
        let json = (try? JSONSerialization.data(withJSONObject: [
            "allowed": result.allowed, "reason": result.reason
        ])).flatMap { String(data: $0, encoding: .utf8) }
        return Self.http(200, json ?? #"{"allowed":false,"reason":"Denied."}"#, origin: origin)
    }

    private func handleVerify(body: String?, origin: String?) async -> String {
        guard let params = jsonObject(from: body),
              let answer = params["answer"] as? String
        else {
            return Self.http(400, #"{"error":"missing answer"}"#, origin: origin)
        }
        let client = await MainActor.run { makeClient() }
        guard !client.apiKey.isEmpty else {
            return Self.http(503, #"{"error":"API key not configured"}"#, origin: origin)
        }

        let gen = ProblemGenerator(client: client, store: store)
        let problem = GeneratedProblem(
            problem: params["problem_text"] as? String ?? "",
            answer: params["expected_answer"] as? String ?? "",
            answerType: params["answer_type"] as? String ?? "numeric",
            tolerance: params["tolerance"] as? Double ?? 0.001,
            topic: params["topic"] as? String ?? "general"
        )
        let result = await gen.verify(problem: problem, studentAnswer: answer)
        let json = (try? JSONSerialization.data(withJSONObject: [
            "correct": result.correct, "explanation": result.explanation
        ])).flatMap { String(data: $0, encoding: .utf8) }
        return Self.http(200, json ?? #"{"correct":false,"explanation":"Could not verify."}"#, origin: origin)
    }

    private func handleHistory(body: String?, origin: String?) async -> String {
        guard let params = jsonObject(from: body),
              let topic = params["topic"] as? String,
              let correct = params["correct"] as? Bool
        else {
            return Self.http(400, #"{"error":"missing topic or correct"}"#, origin: origin)
        }
        await MainActor.run { store.recordProblem(topic: topic, correct: correct) }
        return Self.http(200, #"{"ok":true}"#, origin: origin)
    }

    // MARK: - Helpers

    /// Flat shape for the extension. The stored `BlockedTarget` encodes its enum
    /// as nested objects and drops `displayName` (it is computed), which the
    /// extension cannot use directly.
    private struct WebsiteTarget: Encodable {
        let domain: String
        let label: String
        let category: String
    }

    @MainActor
    private func blockedWebsites() -> [WebsiteTarget] {
        store.blockedTargets.compactMap { target in
            guard case .website(let domain, let label) = target.kind else { return nil }
            return WebsiteTarget(
                domain: domain,
                label: label.isEmpty ? domain : label,
                category: target.category.rawValue
            )
        }
    }

    private func jsonObject(from body: String?) -> [String: Any]? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func errorJSON(_ message: String) -> String {
        let payload = (try? JSONSerialization.data(withJSONObject: ["error": message]))
            .flatMap { String(data: $0, encoding: .utf8) }
        return payload ?? #"{"error":"unknown"}"#
    }

    @MainActor
    private func makeClient() -> AiClient {
        AiClient(apiKey: store.apiKey, endpoint: store.apiEndpoint, model: store.model, provider: store.selectedProvider)
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func http(_ code: Int,
                     _ body: String,
                     origin: String? = nil,
                     contentType: String = "application/json") -> String {
        let reason: String
        switch code {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 500: reason = "Internal Server Error"
        case 502: reason = "Bad Gateway"
        case 503: reason = "Service Unavailable"
        default:  reason = "Error"
        }

        // CORS headers are emitted only for the Chrome extension. Anything else
        // gets the response without them, so the browser blocks it.
        var cors = ""
        if let origin {
            cors = """
            Access-Control-Allow-Origin: \(origin)\r
            Access-Control-Allow-Methods: GET, POST, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type\r
            Vary: Origin\r

            """
        }

        return """
        HTTP/1.1 \(code) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        \(cors)Connection: close\r
        \r
        \(body)
        """
    }

    // MARK: - Single-instance check (static)

    /// Returns true if another Blocker instance is already running on the sync port.
    static func isAlreadyRunning(port: UInt16 = 14923) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/ping") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        var running = false
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data, String(data: data, encoding: .utf8) == "pong" {
                running = true
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return running
    }

    /// Activate an existing Blocker instance.
    static func activateExisting(port: UInt16 = 14923) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/activate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 1
        URLSession.shared.dataTask(with: req).resume()
    }
}
