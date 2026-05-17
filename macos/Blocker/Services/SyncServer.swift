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
            if err != nil {
                conn.cancel()
                return
            }
            var buf = buffer
            if let data = data { buf.append(data) }

            if isComplete || self?.requestComplete(buf) == true {
                if let request = String(data: buf, encoding: .utf8) {
                    let response = self?.process(request) ?? Self.http(500, "{}")
                    conn.send(content: response.data(using: .utf8),
                              completion: .contentProcessed({ _ in conn.cancel() }))
                } else {
                    conn.cancel()
                }
            } else {
                self?.receiveAll(from: conn, buffer: buf)
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

    private func process(_ raw: String) -> String {
        DispatchQueue.main.async { [store] in
            store.lastExtensionContact = Date()
        }
        let parts = parseRequest(raw)
        let method = parts.method
        let path = parts.path
        let body = parts.body

        switch (method, path) {
        case ("GET", "/ping"):
            return Self.http(200, "pong")

        case ("POST", "/activate"):
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
            return Self.http(200, #"{"ok":true}"#)

        case ("GET", "/blocklist"):
            let json = encode(store.websiteTargets) ?? "[]"
            return Self.http(200, json)

        case ("GET", "/profile"):
            let json = encode(store.profile) ?? "{}"
            return Self.http(200, json)

        case ("GET", "/problem"):
            return handleProblem()

        case ("POST", "/judge"):
            return handleJudge(body: body)

        case ("POST", "/verify"):
            return handleVerify(body: body)

        case ("POST", "/history"):
            return handleHistory(body: body)

        case ("OPTIONS", _):
            return Self.http(200, "")

        default:
            return Self.http(404, #"{"error":"not found"}"#)
        }
    }

    private func parseRequest(_ raw: String) -> (method: String, path: String, body: String?) {
        let lines = raw.components(separatedBy: "\r\n")
        guard let first = lines.first else { return ("", "", nil) }
        let reqParts = first.components(separatedBy: " ")
        let method = reqParts.count > 0 ? reqParts[0] : ""
        let path = reqParts.count > 1 ? reqParts[1] : ""

        var body: String? = nil
        if let sep = raw.range(of: "\r\n\r\n") {
            body = String(raw[sep.upperBound...])
        }
        return (method, path, body)
    }

    // MARK: - Handlers

    private func handleProblem() -> String {
        let client = makeClient()
        guard !client.apiKey.isEmpty else {
            return Self.http(503, #"{"error":"API key not configured"}"#)
        }
        let sem = DispatchSemaphore(value: 0)
        var json = #"{"error":"timeout"}"#
        Task {
            let gen = ProblemGenerator(client: client, store: store)
            let problem = await gen.generate()
            if let data = try? JSONEncoder().encode(problem),
               let str = String(data: data, encoding: .utf8) {
                json = str
            }
            sem.signal()
        }
        sem.wait()
        return Self.http(200, json)
    }

    private func handleJudge(body: String?) -> String {
        guard let body = body,
              let data = body.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let appName = params["app_name"],
              let argument = params["argument"]
        else {
            return Self.http(400, #"{"error":"missing app_name or argument"}"#)
        }
        let client = makeClient()
        guard !client.apiKey.isEmpty else {
            return Self.http(503, #"{"error":"API key not configured"}"#)
        }
        let sem = DispatchSemaphore(value: 0)
        var json = #"{"error":"timeout"}"#
        Task {
            let judge = BlocklistJudge(client: client)
            let result = await judge.judge(appName: appName, argument: argument)
            if let data = try? JSONSerialization.data(withJSONObject: [
                "allowed": result.allowed, "reason": result.reason
            ]), let str = String(data: data, encoding: .utf8) {
                json = str
            }
            sem.signal()
        }
        sem.wait()
        return Self.http(200, json)
    }

    private func handleVerify(body: String?) -> String {
        guard let body = body,
              let data = body.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = params["answer"] as? String
        else {
            return Self.http(400, #"{"error":"missing answer"}"#)
        }
        let client = makeClient()
        guard !client.apiKey.isEmpty else {
            return Self.http(503, #"{"error":"API key not configured"}"#)
        }
        let sem = DispatchSemaphore(value: 0)
        var json = #"{"error":"timeout"}"#
        Task {
            let gen = ProblemGenerator(client: client, store: store)
            let problem = GeneratedProblem(
                problem: params["problem_text"] as? String ?? "",
                answer: params["expected_answer"] as? String ?? "",
                answerType: params["answer_type"] as? String ?? "numeric",
                tolerance: params["tolerance"] as? Double ?? 0.001,
                topic: params["topic"] as? String ?? "general"
            )
            let result = await gen.verify(problem: problem, studentAnswer: answer)
            if let data = try? JSONSerialization.data(withJSONObject: [
                "correct": result.correct, "explanation": result.explanation
            ]), let str = String(data: data, encoding: .utf8) {
                json = str
            }
            sem.signal()
        }
        sem.wait()
        return Self.http(200, json)
    }

    private func handleHistory(body: String?) -> String {
        guard let body = body,
              let data = body.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topic = params["topic"] as? String,
              let correct = params["correct"] as? Bool
        else {
            return Self.http(400, #"{"error":"missing topic or correct"}"#)
        }
        DispatchQueue.main.async { [store] in
            store.recordProblem(topic: topic, correct: correct)
        }
        return Self.http(200, #"{"ok":true}"#)
    }

    // MARK: - Helpers

    private func makeClient() -> AiClient {
        AiClient(apiKey: store.apiKey, endpoint: store.apiEndpoint, model: store.model, provider: store.selectedProvider)
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func http(_ code: Int, _ body: String) -> String {
        let reason: String
        switch code {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 503: reason = "Service Unavailable"
        default:  reason = "Error"
        }
        return """
        HTTP/1.1 \(code) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
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
