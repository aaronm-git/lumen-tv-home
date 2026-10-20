// Lumen Agents: a small Mac helper that follows T3 Code's chats and shares their status with Lumen on the TV.
//
// It reads T3 Code with a read-only token (`t3 auth session issue --scope orchestration:read`), loads the thread
// list over HTTP, then follows the server's shell stream so it only wakes when a chat changes. The TV finds it over
// Bonjour (_lumen-agents._tcp) and must be paired once: the TV shows a code that never goes over the network, and
// typing it here completes the key. Requests are signed and replies encrypted with that key, so other devices on the
// network can neither read nor fake them.
//
//   lumen-agents serve          run the helper (launchd does this)
//   lumen-agents pair <code>    approve the TV showing that code (K7QM-9XRT-4HNP-2WVD; any case, dashes optional)
//   lumen-agents devices        list paired TVs
//   lumen-agents unpair all     forget every TV (or pass a name)
//   lumen-agents status         print what the TV would see
import CryptoKit
import Foundation
import Network

let env = ProcessInfo.processInfo.environment
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
// LUMEN_AGENTS_PORT and LUMEN_AGENTS_DIR run a second, test instance; it isn't advertised over Bonjour.
let port: UInt16 = env["LUMEN_AGENTS_PORT"].flatMap { UInt16($0) }.flatMap { $0 > 0 ? $0 : nil } ?? 47837
let dir = env["LUMEN_AGENTS_DIR"].map { URL(fileURLWithPath: $0) }
    ?? home.appendingPathComponent("Library/Application Support/Lumen Agents")
let advertise = env["LUMEN_AGENTS_PORT"] == nil && env["LUMEN_AGENTS_DIR"] == nil
let t3Home = env["T3CODE_HOME"].map { URL(fileURLWithPath: $0) }
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
    let url = dir.appendingPathComponent(name)
    try? data.write(to: url, options: .atomic)
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func json(_ data: Data?) -> [String: Any]? {
    data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

func encode(_ obj: Any) -> Data {
    // JSONSerialization raises (not throws) on objects it can't encode.
    guard JSONSerialization.isValidJSONObject(obj) else { return Data() }
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
}

func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func unhex(_ s: String) -> Data? {
    let digits = s.utf8.map { c -> UInt8? in
        switch c {
        case 48...57: return c - 48
        case 97...102: return c - 87
        case 65...70: return c - 55
        default: return nil
        }
    }
    guard digits.count % 2 == 0, digits.count <= 256 else { return nil }
    var out = Data(capacity: digits.count / 2)
    for i in stride(from: 0, to: digits.count, by: 2) {
        guard let hi = digits[i], let lo = digits[i + 1] else { return nil }
        out.append(hi << 4 | lo)
    }
    return out
}

/** Without control or invisible formatting characters (names and titles end up in logs and the terminal), capped. */
func clean(_ s: String, _ max: Int) -> String {
    var out = String.UnicodeScalarView()
    for u in s.unicodeScalars {
        if u.properties.isWhitespace { out.append(" ") }
        else if u.value == 0x200D || ![.control, .format].contains(u.properties.generalCategory) { out.append(u) }
    }
    let t = String(out)
    return t.count > max ? String(t.prefix(max - 1)) + "…" : t
}

/** Compares secrets in constant time. */
func same(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    return x.count == y.count && zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
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
        let p = runtime?["port"] as? Int ?? 3773
        return URL(string: "http://127.0.0.1:\((1...65535).contains(p) ? p : 3773)")!
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
            guard let wsURL = url.url else { return later() }
            let task = session.webSocketTask(with: wsURL)
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
                    return lost(task, "stream ended: \(clean(String(decoding: data ?? Data(), as: UTF8.self), 300))")
                default:
                    break
                }
                receive(task)
            }
        }
    }

    private func send(_ task: URLSessionWebSocketTask, _ obj: [String: Any]) {
        task.send(.string(String(decoding: encode(obj), as: UTF8.self))) { _ in }
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
            var chat: [String: Any] = ["id": clean(t.id, 100), "title": clean(t.title, 200), "state": state,
                                       "detail": detail, "project": clean(projects[t.project] ?? "", 80),
                                       "brand": t.brand, "model": clean(t.model, 80)]
            if let at { chat["age"] = Int(max(0, min(now.timeIntervalSince(at), 1e9))) }
            let s = clean(text?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? "", 280)
            if !s.isEmpty { chat["text"] = s }
            out.append((rank, at ?? now, chat))
        }
        out.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.at > $1.at }
        return out.prefix(20).map(\.chat)
    }
}

// ---- Pairing ------------------------------------------------------------------------------

struct Device {
    let name: String
    let key: SymmetricKey
}

/** Crockford base32, as the TV writes the code. */
let codeAlphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

/** The code as typed: any case, dashes and spaces optional, O for 0 and I or L for 1. */
func normalize(_ typed: String) -> String? {
    let code = String(typed.uppercased().compactMap { c -> Character? in
        switch c {
        case "-", " ": return nil
        case "O": return "0"
        case "I", "L": return "1"
        default: return c
        }
    })
    return code.count == 16 && code.allSatisfy(codeAlphabet.contains) ? code : nil
}

/** SHA-256 over length-prefixed parts (AgentStatus.derive on the TV does the same). */
func derive(_ parts: [Data]) -> SymmetricKey {
    var h = SHA256()
    for p in parts {
        h.update(data: Data([UInt8(p.count >> 8 & 0xFF), UInt8(p.count & 0xFF)]))
        h.update(data: p)
    }
    return SymmetricKey(data: h.finalize())
}

final class Pairing {
    private(set) var devices: [String: Device] = [:]
    /**
     * TVs waiting for `lumen-agents pair <code>`, dropped after 15 minutes. The key needs the code too, which never
     * leaves the TV, so until then the Mac keeps the ECDH secret and the TV's latest signed request, and checks that
     * request against the code you type.
     */
    private var pending: [String: Pending] = [:]
    private var lastTime: [String: Int64] = [:]
    private var pairTimes: [Date] = []

    struct Pending {
        let name: String
        let secret, tvKey, macKey: Data
        let expires: Date
        var request: (signed: Data, mac: Data, time: Int64)?
    }

    init() {
        for (id, v) in json(read("devices.json")) ?? [:] {
            guard let d = v as? [String: Any], let k = (d["key"] as? String).flatMap(unhex), k.count == 32 else { continue }
            devices[id] = Device(name: clean(d["name"] as? String ?? "TV", 60), key: SymmetricKey(data: k))
        }
    }

    private func save() {
        var out: [String: Any] = [:]
        for (id, d) in devices {
            out[id] = ["name": d.name, "key": d.key.withUnsafeBytes { hex($0) }]
        }
        write("devices.json", encode(out))
    }

    /** Agrees a secret with the TV (P-256 ECDH). Ten tries a minute and eight waiting TVs at most. */
    func begin(_ body: [String: Any]) -> (Int, [String: Any]) {
        let now = Date()
        pairTimes = pairTimes.filter { now.timeIntervalSince($0) < 60 }
        pending = pending.filter { $0.value.expires > now }
        guard pairTimes.count < 10, pending.count < 8 else { return (429, ["error": "busy"]) }
        pairTimes.append(now)
        guard let b64 = body["key"] as? String, b64.count < 400, let der = Data(base64Encoded: b64),
              let tvKey = try? P256.KeyAgreement.PublicKey(derRepresentation: der) else { return (400, ["error": "bad key"]) }
        let mine = P256.KeyAgreement.PrivateKey()
        guard let shared = try? mine.sharedSecretFromKeyAgreement(with: tvKey) else { return (400, ["error": "bad key"]) }
        let id = hex(SHA256.hash(data: der).prefix(8))
        guard pending[id] == nil, devices[id] == nil else { return (400, ["error": "bad key"]) }
        let name = clean(body["name"] as? String ?? "TV", 60)
        pending[id] = Pending(name: name, secret: shared.withUnsafeBytes { Data($0) }, tvKey: der,
                              macKey: mine.publicKey.derRepresentation, expires: now.addingTimeInterval(900))
        log("pairing requested by \(name)")
        return (200, ["key": mine.publicKey.derRepresentation.base64EncodedString(), "mac": macName])
    }

    /** Pairs the waiting TV whose latest request was signed with the key this code makes. */
    func approve(_ typed: String) -> String? {
        guard let code = normalize(typed) else { return nil }
        let now = Date()
        for (id, p) in pending where p.expires > now {
            guard let r = p.request else { continue }
            let key = derive([Data("lumen-agents/v2".utf8), p.secret, Data(code.utf8), p.tvKey, p.macKey])
            guard HMAC<SHA256>.isValidAuthenticationCode(r.mac, authenticating: r.signed, using: key) else { continue }
            pending[id] = nil
            devices[id] = Device(name: p.name, key: key)
            lastTime[id] = r.time
            save()
            return p.name
        }
        return nil
    }

    func forget(_ which: String) -> Int {
        let gone = devices.filter { which == "all" || $0.key == which || $0.value.name == which }.map(\.key)
        for id in gone {
            devices[id] = nil
            lastTime[id] = nil
        }
        save()
        return gone.count
    }

    enum Check { case ok(SymmetricKey), pending, unknown }

    /**
     * X-Lumen-Auth is HMAC(key, "GET <path and query>\n<time>"); times must be recent and only go up, so replays
     * fail. A waiting TV's request can't be checked yet, so it's only kept for approve().
     */
    func check(_ r: Request) -> Check {
        guard let id = r.headers["x-lumen-device"], let time = r.headers["x-lumen-time"], let t = Int64(time),
              let mac = r.headers["x-lumen-auth"].flatMap(unhex) else { return .unknown }
        // Bounds around now rather than now - t, which a huge t could overflow.
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard t > now - 600_000, t < now + 600_000, t > lastTime[id] ?? 0 else { return .unknown }
        let signed = Data("\(r.method) \(r.target)\n\(time)".utf8)
        if let d = devices[id] {
            guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: signed, using: d.key) else { return .unknown }
            lastTime[id] = t
            return .ok(d.key)
        }
        guard var p = pending[id], p.expires > Date() else { return .unknown }
        p.request = (signed, mac, t)
        pending[id] = p
        return .pending
    }
}

// ---- LAN server ---------------------------------------------------------------------------

struct Request {
    let method, path, target: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    enum Parsed { case more, bad, ok(Request) }

    /** Parses a complete HTTP/1.1 request; anything odd is .bad. Small heads and bodies only (the TV sends tiny ones). */
    static func parse(_ buf: Data) -> Parsed {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else { return buf.count > 8192 ? .bad : .more }
        guard end.lowerBound - buf.startIndex <= 8192,
              let head = String(data: buf[..<end.lowerBound], encoding: .utf8) else { return .bad }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2].hasPrefix("HTTP/1."), !first[0].isEmpty, first[0].allSatisfy(\.isUppercase),
              first[1].hasPrefix("/"), first[1].count <= 2048 else { return .bad }
        let target = String(first[1])
        let q = target.firstIndex(of: "?")
        var qs: [String: String] = [:]
        for pair in q.map({ target[target.index(after: $0)...].split(separator: "&") }) ?? [] {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { qs[String(kv[0])] = String(kv[1]) }
        }
        var h: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let c = line.firstIndex(of: ":"), c != line.startIndex, h.count < 64 else { return .bad }
            let name = line[..<c].lowercased()
            // One plain length only: no chunked bodies, no conflicting lengths.
            if name == "transfer-encoding" || (name == "content-length" && h[name] != nil) { return .bad }
            h[name] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        var length = 0
        if let cl = h["content-length"] {
            guard (1...5).contains(cl.utf8.count), cl.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(cl),
                  n <= 16384 else { return .bad }
            length = n
        }
        let start = end.upperBound
        guard buf.endIndex - start >= length else { return .more }
        return .ok(Request(method: String(first[0]), path: String(target[..<(q ?? target.endIndex)]), target: target,
                           query: qs, headers: h, body: Data(buf[start..<start + length])))
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
    private var open = 0
    /** The lumen-agents command reads this file (only you can) and sends it with each request. New every start. */
    private let adminSecret = hex(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })

    init(_ t3: T3) {
        self.t3 = t3
        if let id = read("id").flatMap({ String(data: $0, encoding: .utf8) }), !id.isEmpty { helperId = id }
        else {
            helperId = hex(SymmetricKey(size: .bits128).withUnsafeBytes { Array($0.prefix(8)) })
            write("id", Data(helperId.utf8))
        }
        write("admin", Data(adminSecret.utf8))
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
            let l = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            if advertise {
                l.service = NWListener.Service(name: nil, type: "_lumen-agents._tcp", domain: nil,
                                               txtRecord: NWTXTRecord(["id": helperId]))
            }
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
        // A few TVs and the command line need a handful; more is a flood.
        guard open < 64 else { return c.cancel() }
        open += 1
        c.stateUpdateHandler = { [self, weak c] s in
            if case .failed = s { c?.cancel() }
            if case .cancelled = s { open -= 1 }
        }
        c.start(queue: q)
        var buf = Data()
        var complete = false
        // Weak, so a closed connection isn't kept for the full 90 s.
        q.asyncAfter(deadline: .now() + 10) { [weak c] in if !complete { c?.cancel() } }
        q.asyncAfter(deadline: .now() + 90) { [weak c] in c?.cancel() }
        func next() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [self] data, _, done, error in
                if let data { buf.append(data) }
                switch Request.parse(buf) {
                case .ok(let r):
                    complete = true
                    return respond(c, r)
                case .bad:
                    complete = true
                    return send(c, 400, ["error": "bad request"])
                case .more:
                    if done || error != nil { return c.cancel() }
                    next()
                }
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
        // Browsers send Origin; the TV and the lumen-agents command never do.
        if r.headers["origin"] != nil { return send(c, 403, ["error": "forbidden"]) }
        switch (r.method, r.path) {
        case ("GET", "/status"):
            switch pairing.check(r) {
            case .ok(let key):
                if r.query["wait"] == String(version) && waiting.count < 32 {
                    waiting.append((c, r, key, Date().addingTimeInterval(45)))
                } else {
                    sealed(c, 200, status(), key, r)
                }
            // Not sealed: there's no key until the code is typed here. The TV only trusts sealed replies once paired.
            case .pending: send(c, 403, ["error": "pending"])
            case .unknown: send(c, 401, ["error": "unknown device"])
            }
        case ("POST", "/pair"):
            let (code, reply) = pairing.begin(json(r.body) ?? [:])
            send(c, code, reply)
        case (_, "/approve"), (_, "/devices"), (_, "/unpair"), (_, "/debug"):
            admin(c, r)
        default:
            send(c, 404, ["error": "not found"])
        }
    }

    /**
     * For the lumen-agents command on this Mac only: from loopback, with the admin secret, and addressed to
     * 127.0.0.1 or localhost (so a web page can't reach it through DNS rebinding).
     */
    private func admin(_ c: NWConnection, _ r: Request) {
        guard isLocal(c) else { return send(c, 404, ["error": "not found"]) }
        guard ["127.0.0.1:\(port)", "localhost:\(port)"].contains((r.headers["host"] ?? "").lowercased()),
              same(r.headers["authorization"] ?? "", "Bearer " + adminSecret)
        else { return send(c, 403, ["error": "forbidden"]) }
        switch (r.method, r.path) {
        case ("POST", "/approve"):
            if let name = pairing.approve(String(decoding: r.body, as: UTF8.self)) { send(c, 200, ["paired": name]) }
            else { send(c, 404, ["error": "No TV is showing that code. Open Lumen's home screen and try again."]) }
        case ("GET", "/devices"):
            send(c, 200, ["devices": pairing.devices.map { ["id": $0.key, "name": $0.value.name] }])
        case ("POST", "/unpair"):
            send(c, 200, ["removed": pairing.forget(String(decoding: r.body, as: UTF8.self))])
        case ("GET", "/debug"):
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
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                      429: "Too Many Requests"][code] ?? ""
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
    let secret = read("admin").map { String(decoding: $0, as: UTF8.self) } ?? ""
    r.setValue("Bearer " + secret.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "Authorization")
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
    print(code == 200 ? "Paired \(reply["paired"] ?? "TV"). It will show your chats in a few seconds." : "\(reply["error"] ?? "Failed (HTTP \(code))")")
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
