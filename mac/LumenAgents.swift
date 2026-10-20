// Lumen Agents: a small Mac helper that follows T3 Code's chats and shares their status with Lumen on the TV.
//
// It reads T3 Code with a read-only token (`t3 auth session issue --scope orchestration:read`), loads the thread
// list over HTTP, then follows the server's shell stream so it only wakes when a chat changes. The TV finds it over
// Bonjour (_lumen-agents._tcp) and must be paired once: both sides show the same six-digit code. Requests are signed
// and replies encrypted with the key they agreed, so other devices on the network can neither read nor fake them.
//
//   lumen-agents serve          run the helper (launchd does this)
//   lumen-agents pair 123456    approve the TV showing that code
//   lumen-agents devices        list paired TVs
//   lumen-agents unpair all     forget every TV (or pass a name)
//   lumen-agents status         print what the TV would see
import CryptoKit
import Foundation
import Network

let port: UInt16 = 47837
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let dir = home.appendingPathComponent("Library/Application Support/Lumen Agents")
let t3Home = ProcessInfo.processInfo.environment["T3CODE_HOME"].map { URL(fileURLWithPath: $0) }
    ?? home.appendingPathComponent(".t3")
let q = DispatchQueue(label: "lumen-agents")
let macName = Host.current().localizedName ?? "Mac"

func log(_ s: String) {
    FileHandle.standardError.write(Data("\(ISO8601DateFormatter().string(from: Date())) \(s)\n".utf8))
}

// ---- Files --------------------------------------------------------------------------------

func read(_ name: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(name)) }

func write(_ name: String, _ data: Data) {
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
}

func json(_ data: Data?) -> [String: Any]? {
    data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

func encode(_ obj: Any) -> Data { (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data() }

func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func unhex(_ s: String) -> Data? {
    guard s.count % 2 == 0 else { return nil }
    var out = Data(capacity: s.count / 2)
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
        out.append(b)
        i = j
    }
    return out
}

let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
let isoPlain = ISO8601DateFormatter()

func date(_ v: Any?) -> Date? {
    guard let s = v as? String else { return nil }
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

// ---- T3 Code ------------------------------------------------------------------------------

/** The parts of a T3 thread the TV needs. */
struct Thread {
    let id, title, project, status: String
    /** Top-level thread a subagent belongs to; nil for chats you started. */
    let root: String?
    let hidden: Bool
    let pendingKind: String?
    let pendingAt, startedAt, completedAt, visitedAt, snoozedUntil: Date?
    let planReady: Bool
    let errorClass, error, message: String?
    /** The model's maker, for the TV's icon: claude, openai, grok, gemini, cursor or opencode. */
    let brand, model: String

    init?(_ j: [String: Any]) {
        guard let id = j["id"] as? String else { return nil }
        self.id = id
        title = j["title"] as? String ?? "Untitled"
        project = j["projectId"] as? String ?? ""
        status = j["status"] as? String ?? "idle"
        let lineage = j["lineage"] as? [String: Any]
        root = lineage?["relationshipToParent"] as? String == "subagent" ? lineage?["rootThreadId"] as? String : nil
        hidden = j["archivedAt"] is String || j["deletedAt"] is String
        let pending = j["pendingRuntimeRequest"] as? [String: Any]
        pendingKind = pending?["kind"] as? String
        pendingAt = date(pending?["createdAt"])
        startedAt = date(j["activityRunStartedAt"]) ?? date(j["latestRunStartedAt"])
        completedAt = date(j["latestRunCompletedAt"])
        visitedAt = date(j["lastVisitedAt"])
        snoozedUntil = date(j["snoozedUntil"])
        planReady = j["interactionMode"] as? String == "plan" && j["hasActionableProposedPlan"] as? Bool == true
        errorClass = j["lastErrorClass"] as? String
        error = j["lastError"] as? String
        message = (j["latestVisibleMessage"] as? [String: Any])?["text"] as? String
        model = (j["modelSelection"] as? [String: Any])?["model"] as? String ?? ""
        brand = Thread.brand(model: model.lowercased(), provider: (j["providerInstanceId"] as? String ?? "").lowercased())
    }

    /** By model first (Cursor can run Grok), then by provider. */
    static func brand(model m: String, provider p: String) -> String {
        if m.hasPrefix("claude") { return "claude" }
        if m.hasPrefix("gpt") || m.hasPrefix("codex") || m.range(of: "^o[0-9]", options: .regularExpression) != nil {
            return "openai"
        }
        if m.hasPrefix("grok") { return "grok" }
        if m.hasPrefix("gemini") { return "gemini" }
        if m.hasPrefix("composer") { return "cursor" }
        for (key, b) in [("claude", "claude"), ("codex", "openai"), ("openai", "openai"), ("grok", "grok"),
                         ("gemini", "gemini"), ("cursor", "cursor"), ("opencode", "opencode")] where p.contains(key) {
            return b
        }
        return ""
    }

    /** Finished since you last opened it (the desktop's "Completed" pill). */
    var unseen: Bool {
        guard let done = completedAt, let seen = visitedAt else { return false }
        return done > seen
    }
}

let workingStates: Set<String> = ["preparing", "queued", "starting", "running", "waiting"]

final class T3 {
    var threads: [String: Thread] = [:]
    var projects: [String: String] = [:]
    /** ok, offline (server not running) or auth (token rejected). */
    var state = "offline" {
        didSet { if state != oldValue { onChange?() } }
    }
    /** Called after anything that might change what the TV shows. */
    var onChange: (() -> Void)?
    private var sequence = 0
    private var ws: URLSessionWebSocketTask?
    private var retry = 1.0
    private var lastPong = Date()
    private var lastIssue = Date.distantPast
    private var nextRequest = 1
    private let session: URLSession = {
        let ops = OperationQueue()
        ops.underlyingQueue = q
        ops.maxConcurrentOperationCount = 1
        return URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: ops)
    }()

    func start() {
        connect()
        let ping = DispatchSource.makeTimerSource(queue: q)
        ping.schedule(deadline: .now() + 20, repeating: 20)
        ping.setEventHandler { [self] in
            guard let ws else { return }
            if Date().timeIntervalSince(lastPong) > 65 { return lost(ws, "no pong") }
            send(ws, ["_tag": "Ping"])
        }
        ping.resume()
        pingTimer = ping
    }
    private var pingTimer: DispatchSourceTimer?

    private var base: URL {
        let runtime = json(try? Data(contentsOf: t3Home.appendingPathComponent("userdata/server-runtime.json")))
        return URL(string: "http://127.0.0.1:\(runtime?["port"] as? Int ?? 3773)")!
    }

    private var token: String? {
        read("t3-token").flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func request(_ path: String, _ token: String, post: Bool = false) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        r.httpMethod = post ? "POST" : "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("2", forHTTPHeaderField: "x-t3-orchestration-protocol")
        return r
    }

    /** Loads every thread over HTTP, then follows changes over the WebSocket from that point. */
    private func connect() {
        guard let token, !token.isEmpty else { return issueToken() }
        session.dataTask(with: request("api/orchestration/shell", token)) { [self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let snap = json(data) else {
                if code == 401 || code == 403 {
                    state = "auth"
                    return issueToken()
                }
                state = "offline"
                if code != 0 { log("shell snapshot: HTTP \(code)") }
                return later()
            }
            applySnapshot(snap)
            state = "ok"
            onChange?()
            retry = 1
            subscribe(token)
        }.resume()
    }

    private func subscribe(_ token: String) {
        session.dataTask(with: request("api/auth/websocket-ticket", token, post: true)) { [self] data, _, _ in
            guard let ticket = json(data)?["ticket"] as? String,
                  var url = URLComponents(url: base.appendingPathComponent("ws"), resolvingAgainstBaseURL: false)
            else { return later() }
            url.scheme = "ws"
            url.queryItems = [URLQueryItem(name: "orchestrationProtocol", value: "2"),
                              URLQueryItem(name: "wsTicket", value: ticket)]
            let task = session.webSocketTask(with: url.url!)
            task.maximumMessageSize = 64 << 20
            ws = task
            lastPong = Date()
            task.resume()
            let id = String(nextRequest)
            nextRequest += 1
            send(task, ["_tag": "Request", "id": id, "tag": "orchestration.subscribeShell",
                        "payload": ["afterSequence": sequence], "headers": [] as [Any]])
            receive(task)
        }.resume()
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [self] result in
            guard task === ws else { return }
            switch result {
            case .failure(let e):
                lost(task, e.localizedDescription)
            case .success(let m):
                var data: Data?
                switch m {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: break
                }
                guard let msg = json(data) else { return receive(task) }
                switch msg["_tag"] as? String {
                case "Chunk":
                    for v in msg["values"] as? [[String: Any]] ?? [] { apply(v) }
                    onChange?()
                    // The server waits for an Ack before it sends the next chunk.
                    send(task, ["_tag": "Ack", "requestId": msg["requestId"] ?? ""])
                case "Pong":
                    lastPong = Date()
                case "Ping":
                    send(task, ["_tag": "Pong"])
                case "Exit", "Defect", "ClientProtocolError":
                    return lost(task, "stream ended: \(String(data: data ?? Data(), encoding: .utf8)?.prefix(300) ?? "")")
                default:
                    break
                }
                receive(task)
            }
        }
    }

    private func send(_ task: URLSessionWebSocketTask, _ obj: [String: Any]) {
        task.send(.string(String(data: encode(obj), encoding: .utf8)!)) { _ in }
    }

    private func lost(_ task: URLSessionWebSocketTask, _ why: String) {
        guard task === ws else { return }
        log("T3 stream lost: \(why)")
        ws = nil
        task.cancel(with: .goingAway, reason: nil)
        later()
    }

    private func later() {
        let wait = retry
        retry = min(retry * 2, 30)
        q.asyncAfter(deadline: .now() + wait) { [self] in if ws == nil { connect() } }
    }

    private func applySnapshot(_ snap: [String: Any]) {
        sequence = snap["snapshotSequence"] as? Int ?? sequence
        var next: [String: Thread] = [:]
        for j in snap["threads"] as? [[String: Any]] ?? [] {
            if let t = Thread(j) { next[t.id] = t }
        }
        threads = next
        projects = [:]
        applyProjects(snap["projects"])
    }

    private func applyProjects(_ list: Any?) {
        for p in list as? [[String: Any]] ?? [] {
            if let id = p["id"] as? String { projects[id] = p["title"] as? String ?? "" }
        }
    }

    private func apply(_ item: [String: Any]) {
        if let s = item["sequence"] as? Int { sequence = max(sequence, s) }
        switch item["kind"] as? String {
        case "snapshot":
            guard let snap = item["snapshot"] as? [String: Any] else { return }
            // Repository-identity refreshes reuse this shape but only carry projects.
            if item["resolvedRepositoryIdentityRoots"] != nil { applyProjects(snap["projects"]) }
            else { applySnapshot(snap) }
        case "project.updated":
            applyProjects([item["project"] ?? [:]])
        case "project.removed":
            if let id = item["projectId"] as? String { projects[id] = nil }
        case "thread.updated":
            guard let j = item["thread"] as? [String: Any], let t = Thread(j) else { return }
            threads[t.id] = item["location"] as? String == "archive" ? nil : t
        case "thread.removed":
            if let id = item["threadId"] as? String { threads[id] = nil }
        default:
            break
        }
    }

    /** Mints a fresh read-only token with T3's own CLI (at most every ten minutes). */
    private func issueToken() {
        guard Date().timeIntervalSince(lastIssue) > 600 else { return later() }
        lastIssue = Date()
        let cli = t3Home.appendingPathComponent("bin/t3")
        guard fm.isExecutableFile(atPath: cli.path) else {
            log("T3 Code's t3 command isn't at \(cli.path)")
            return later()
        }
        log("issuing a read-only T3 Code token")
        let p = Process()
        p.executableURL = cli
        p.arguments = ["auth", "session", "issue", "--scope", "orchestration:read", "--ttl", "365d",
                       "--label", "Lumen TV", "--token-only"]
        let out = Pipe()
        p.standardOutput = out
        p.terminationHandler = { [self] proc in
            let token = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            q.async { [self] in
                if proc.terminationStatus == 0 && !token.isEmpty { write("t3-token", Data(token.utf8)) }
                else { log("t3 auth session issue failed (\(proc.terminationStatus))") }
                connect()
            }
        }
        do { try p.run() } catch {
            log("couldn't run t3: \(error)")
            later()
        }
    }

    /** What the TV shows: chats working, waiting for you, or finished since you last looked. */
    func chats() -> [[String: Any]] {
        let now = Date()
        var subagentRequests: [String: Thread] = [:]
        for t in threads.values where t.root != nil && t.pendingKind != nil { subagentRequests[t.root!] = t }

        var out: [(rank: Int, at: Date, chat: [String: Any])] = []
        for t in threads.values where t.root == nil && !t.hidden {
            let asking = t.pendingKind != nil ? t : subagentRequests[t.id]
            var state: String, detail: String, at: Date?, rank: Int
            var text = t.message
            if let a = asking {
                (state, rank, at) = ("waiting", 0, a.pendingAt)
                detail = a.pendingKind == "user_input" ? "Input needed" : "Approval needed"
            } else if workingStates.contains(t.status) {
                (state, rank, at, text) = ("working", 3, t.startedAt, nil)
                detail = ["preparing", "queued", "starting"].contains(t.status) ? "Starting" : "Working"
            } else if t.planReady && t.unseen {
                (state, detail, rank, at) = ("waiting", "Plan ready", 0, t.completedAt)
            } else if t.unseen, let done = t.completedAt, now.timeIntervalSince(done) < 86_400,
                      (t.snoozedUntil ?? .distantPast) < now, t.status == "completed" || t.status == "failed" {
                if t.status == "failed" {
                    (state, rank) = ("failed", 1)
                    detail = t.errorClass == "usage_limit" ? "Usage limit reached" : "Failed"
                    text = t.error ?? text
                } else {
                    (state, detail, rank) = ("done", "Finished", 2)
                }
                at = done
            } else {
                continue
            }
            var chat: [String: Any] = ["id": t.id, "title": t.title, "state": state, "detail": detail,
                                       "project": projects[t.project] ?? "", "brand": t.brand, "model": t.model]
            if let at { chat["age"] = max(0, Int(now.timeIntervalSince(at))) }
            if var s = text?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !s.isEmpty {
                if s.count > 280 { s = String(s.prefix(279)) + "…" }
                chat["text"] = s
            }
            out.append((rank, at ?? now, chat))
        }
        out.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.at > $1.at }
        return out.map(\.chat)
    }
}

// ---- Pairing ------------------------------------------------------------------------------

struct Device {
    let name: String
    let key: SymmetricKey
}

final class Pairing {
    private(set) var devices: [String: Device] = [:]
    /** Waiting for `lumen-agents pair <code>`; dropped after 15 minutes. */
    private var pending: [String: (device: Device, code: String, expires: Date)] = [:]
    private var lastTime: [String: Int64] = [:]

    init() {
        for (id, v) in json(read("devices.json")) ?? [:] {
            guard let d = v as? [String: Any], let k = (d["key"] as? String).flatMap(unhex) else { continue }
            devices[id] = Device(name: d["name"] as? String ?? "TV", key: SymmetricKey(data: k))
        }
    }

    private func save() {
        var out: [String: Any] = [:]
        for (id, d) in devices {
            out[id] = ["name": d.name, "key": d.key.withUnsafeBytes { hex($0) }]
        }
        write("devices.json", encode(out))
    }

    /**
     * Agrees a key with the TV (P-256). The code both sides show is a hash of both public keys, so a device in
     * the middle would make the codes differ.
     */
    func begin(_ body: [String: Any]) -> [String: Any]? {
        guard let b64 = body["key"] as? String, let der = Data(base64Encoded: b64),
              let tvKey = try? P256.KeyAgreement.PublicKey(derRepresentation: der) else { return nil }
        let mine = P256.KeyAgreement.PrivateKey()
        guard let shared = try? mine.sharedSecretFromKeyAgreement(with: tvKey) else { return nil }
        let macDer = mine.publicKey.derRepresentation
        let secret = shared.withUnsafeBytes { Data($0) }
        let key = SymmetricKey(data: SHA256.hash(data: Data("lumen-agents/v1".utf8) + secret))
        let id = hex(SHA256.hash(data: der).prefix(8))
        let digest = Array(SHA256.hash(data: der + macDer))
        let n = (UInt32(digest[0]) << 24 | UInt32(digest[1]) << 16 | UInt32(digest[2]) << 8 | UInt32(digest[3]))
        let code = String(format: "%06u", n % 1_000_000)

        let now = Date()
        pending = pending.filter { $0.value.expires > now }
        if pending.count >= 8, let oldest = pending.min(by: { $0.value.expires < $1.value.expires }) {
            pending[oldest.key] = nil
        }
        let name = String((body["name"] as? String ?? "TV").prefix(60))
        pending[id] = (Device(name: name, key: key), code, now.addingTimeInterval(900))
        log("pairing requested by \(name); code \(code)")
        return ["key": macDer.base64EncodedString(), "mac": macName]
    }

    func approve(_ code: String) -> String? {
        let now = Date()
        guard let (id, p) = pending.first(where: { $0.value.code == code && $0.value.expires > now }) else { return nil }
        pending[id] = nil
        devices[id] = p.device
        save()
        return p.device.name
    }

    func forget(_ which: String) -> Int {
        let before = devices.count
        devices = devices.filter { which != "all" && $0.key != which && $0.value.name != which }
        save()
        return before - devices.count
    }

    enum Check { case ok(SymmetricKey), pending(SymmetricKey), unknown }

    /** X-Lumen-Auth is HMAC(key, "GET /status\n<time>"); times must be recent and only go up, so replays fail. */
    func check(_ r: Request) -> Check {
        guard let id = r.headers["x-lumen-device"], let time = r.headers["x-lumen-time"], let t = Int64(time),
              let mac = r.headers["x-lumen-auth"].flatMap(unhex) else { return .unknown }
        let found = devices[id].map { (key: $0.key, paired: true) }
            ?? pending[id].flatMap { $0.expires > Date() ? (key: $0.device.key, paired: false) : nil }
        guard let found,
              HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data("\(r.method) \(r.path)\n\(time)".utf8),
                                                     using: found.key),
              abs(Int64(Date().timeIntervalSince1970 * 1000) - t) < 600_000, t > lastTime[id] ?? 0
        else { return .unknown }
        lastTime[id] = t
        return found.paired ? .ok(found.key) : .pending(found.key)
    }
}

// ---- LAN server ---------------------------------------------------------------------------

struct Request {
    let method, path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    /** Parses a complete HTTP/1.1 request, or returns nil if more bytes are needed. */
    init?(_ buf: Data) {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buf[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        method = String(first[0])
        let target = first[1].split(separator: "?", maxSplits: 1)
        path = String(target[0])
        var qs: [String: String] = [:]
        for pair in target.count > 1 ? target[1].split(separator: "&") : [] {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { qs[String(kv[0])] = String(kv[1]) }
        }
        query = qs
        var h: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let c = line.firstIndex(of: ":") else { continue }
            h[line[..<c].lowercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        headers = h
        let length = Int(h["content-length"] ?? "0") ?? 0
        guard buf.count - end.upperBound >= length else { return nil }
        body = buf[end.upperBound..<end.upperBound + length]
    }
}

final class Server {
    let t3: T3
    let pairing = Pairing()
    private var listener: NWListener?
    private let helperId: String
    /**
     * Long polling: the TV sends the version it has, and the reply waits until something changes (or 45 s pass),
     * so it hears about a finished chat at once without asking every few seconds.
     */
    private var version = Int.random(in: 1..<1_000_000)
    private var shownKey = ""
    private var waiting: [(c: NWConnection, r: Request, key: SymmetricKey, until: Date)] = []

    init(_ t3: T3) {
        self.t3 = t3
        if let id = read("id").flatMap({ String(data: $0, encoding: .utf8) }), !id.isEmpty { helperId = id }
        else {
            helperId = hex(SymmetricKey(size: .bits128).withUnsafeBytes { Array($0.prefix(8)) })
            write("id", Data(helperId.utf8))
        }
    }

    func start() {
        t3.onChange = { [self] in changed() }
        let tick = DispatchSource.makeTimerSource(queue: q)
        tick.schedule(deadline: .now() + 10, repeating: 10)
        tick.setEventHandler { [self] in changed() }
        tick.resume()
        ticker = tick
        listen()
    }
    private var ticker: DispatchSourceTimer?

    /** Wakes waiting TVs when the chats change, and lets the others go after 45 s. */
    private func changed() {
        let key = t3.state + "\n" + t3.chats().map { "\($0["id"] ?? "") \($0["state"] ?? "") \($0["detail"] ?? "") \($0["title"] ?? "")" }
            .joined(separator: "\n")
        if key != shownKey {
            shownKey = key
            version += 1
        }
        let now = Date()
        let due = waiting.filter { $0.until > now && $0.r.query["wait"] == String(version) }
        for w in waiting where !due.contains(where: { $0.c === w.c }) { sealed(w.c, 200, status(), w.key, w.r) }
        waiting = due
    }

    private func listen() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.service = NWListener.Service(name: nil, type: "_lumen-agents._tcp", domain: nil,
                                           txtRecord: NWTXTRecord(["id": helperId]))
            l.stateUpdateHandler = { [self] s in
                log("listener: \(s)")
                if case .failed = s { listener?.cancel(); q.asyncAfter(deadline: .now() + 5) { self.listen() } }
            }
            l.serviceRegistrationUpdateHandler = { change in log("bonjour: \(change)") }
            l.newConnectionHandler = { [self] c in handle(c) }
            l.start(queue: q)
            listener = l
        } catch {
            log("can't listen on \(port): \(error)")
            q.asyncAfter(deadline: .now() + 5) { self.listen() }
        }
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: q)
        var buf = Data()
        var complete = false
        q.asyncAfter(deadline: .now() + 10) { if !complete { c.cancel() } }
        q.asyncAfter(deadline: .now() + 90) { c.cancel() }
        func next() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [self] data, _, done, error in
                if let data { buf.append(data) }
                if let r = Request(buf) {
                    complete = true
                    return respond(c, r)
                }
                if done || error != nil || buf.count > 65536 { return c.cancel() }
                next()
            }
        }
        next()
    }

    private func isLocal(_ c: NWConnection) -> Bool {
        guard case .hostPort(let host, _) = c.endpoint else { return false }
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback || a.asIPv4?.isLoopback == true
        default: return false
        }
    }

    private func respond(_ c: NWConnection, _ r: Request) {
        let local = isLocal(c)
        switch (r.method, r.path) {
        case ("GET", "/status"):
            switch pairing.check(r) {
            case .ok(let key):
                if r.query["wait"] == String(version) && waiting.count < 32 {
                    waiting.append((c, r, key, Date().addingTimeInterval(45)))
                } else {
                    sealed(c, 200, status(), key, r)
                }
            case .pending(let key): sealed(c, 403, encode(["error": "pending"]), key, r)
            case .unknown: send(c, 401, ["error": "unknown device"])
            }
        case ("POST", "/pair"):
            if let reply = json(r.body).flatMap(pairing.begin) { send(c, 200, reply) }
            else { send(c, 400, ["error": "bad key"]) }
        // The rest is for the lumen-agents command on this Mac only.
        case ("POST", "/approve") where local:
            let code = String(data: r.body, encoding: .utf8)?.filter(\.isNumber) ?? ""
            if let name = pairing.approve(code) { send(c, 200, ["paired": name]) }
            else { send(c, 404, ["error": "No TV is showing that code. Open Lumen's home screen and try again."]) }
        case ("GET", "/devices") where local:
            send(c, 200, ["devices": pairing.devices.map { ["id": $0.key, "name": $0.value.name] }])
        case ("POST", "/unpair") where local:
            send(c, 200, ["removed": pairing.forget(String(data: r.body, encoding: .utf8) ?? "")])
        case ("GET", "/debug") where local:
            send(c, 200, encode(["t3": t3.state, "threads": t3.threads.count, "chats": t3.chats()]))
        default:
            send(c, 404, ["error": "not found"])
        }
    }

    private func status() -> Data {
        encode(["v": 1, "version": version, "mac": macName, "t3": t3.state, "chats": t3.state == "ok" ? t3.chats() : []])
    }

    /**
     * AES-GCM with the paired key, bound to the request's time: nonce + ciphertext + tag. Only the TV can read it,
     * and it can tell the reply is really from this Mac and for this request.
     */
    private func sealed(_ c: NWConnection, _ code: Int, _ body: Data, _ key: SymmetricKey, _ r: Request) {
        let aad = Data((r.headers["x-lumen-time"] ?? "").utf8)
        guard let box = try? AES.GCM.seal(body, using: key, authenticating: aad).combined else {
            return send(c, 500, Data())
        }
        send(c, code, box, ["Content-Type": "application/octet-stream"])
    }

    private func send(_ c: NWConnection, _ code: Int, _ obj: [String: Any]) { send(c, code, encode(obj)) }

    private func send(_ c: NWConnection, _ code: Int, _ body: Data, _ extra: [String: String] = [:]) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found"][code] ?? ""
        var head = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in ["Content-Type": "application/json"].merging(extra, uniquingKeysWith: { $1 }) {
            head += "\(k): \(v)\r\n"
        }
        c.send(content: Data((head + "\r\n").utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }
}

// ---- Command line -------------------------------------------------------------------------

/** Talks to the running helper on this Mac. */
func local(_ method: String, _ path: String, _ body: String = "") -> (Int, [String: Any]) {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!, timeoutInterval: 5)
    r.httpMethod = method
    if method == "POST" { r.httpBody = Data(body.utf8) }
    var result: (Int, [String: Any]) = (0, [:])
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: r) { data, response, _ in
        result = ((response as? HTTPURLResponse)?.statusCode ?? 0, json(data) ?? [:])
        done.signal()
    }.resume()
    done.wait()
    if result.0 == 0 {
        print("Lumen Agents isn't running. Start it with: launchctl kickstart -k gui/\(getuid())/local.lumen.agents")
        exit(1)
    }
    return result
}

umask(0o077)
let args = CommandLine.arguments.dropFirst()
switch args.first {
case "serve":
    let t3 = T3()
    let server = Server(t3)
    q.async {
        t3.start()
        server.start()
    }
    dispatchMain()
case "pair" where args.count == 2:
    let (code, reply) = local("POST", "/approve", args.last!)
    print(code == 200 ? "Paired \(reply["paired"] ?? "TV"). It will show your chats in a few seconds." : "\(reply["error"] ?? "Failed")")
    exit(code == 200 ? 0 : 1)
case "devices":
    let list = local("GET", "/devices").1["devices"] as? [[String: Any]] ?? []
    if list.isEmpty { print("No TVs paired.") }
    for d in list { print("\(d["name"] ?? "")  (\(d["id"] ?? ""))") }
case "unpair" where args.count == 2:
    print("Removed \(local("POST", "/unpair", args.last!).1["removed"] ?? 0)")
case "status":
    let data = encode(local("GET", "/debug").1)
    let pretty = (try? JSONSerialization.jsonObject(with: data)).flatMap {
        try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys])
    } ?? data
    print(String(data: pretty, encoding: .utf8) ?? "")
default:
    print("""
    usage: lumen-agents serve | pair <code> | devices | unpair <name|id|all> | status
    """)
    exit(2)
}
