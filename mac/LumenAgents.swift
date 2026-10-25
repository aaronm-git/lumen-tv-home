import CryptoKit
import Foundation
import Network

let env = ProcessInfo.processInfo.environment
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser

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

func read(_ name: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(name)) }

func write(_ name: String, _ data: Data) throws {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func delete(_ name: String) throws {
    do {
        try fm.removeItem(at: dir.appendingPathComponent(name))
    } catch CocoaError.fileNoSuchFile {
    }
}

func json(_ data: Data?) -> [String: Any]? {
    data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

func encode(_ obj: Any) -> Data {

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

func sanitizeBoundedDisplayLine(_ s: String, _ max: Int) -> String {
    var out = String.UnicodeScalarView()
    var kept = 0, marks = 0, cut = false
    for (i, u) in s.unicodeScalars.enumerated() {
        guard kept < max * 4, i < max * 16 else {
            cut = true
            break
        }
        let kind = u.properties.generalCategory
        marks = [.nonspacingMark, .spacingMark, .enclosingMark].contains(kind) ? marks + 1 : 0
        if marks > 4 { continue }
        if u.properties.isWhitespace {
            if out.last != " " { out.append(" ") }
        } else if u.value == 0x200D || ![.control, .format].contains(kind) {
            out.append(u)
        } else {
            continue
        }
        kept += 1
    }
    let t = String(out).trimmingCharacters(in: .whitespaces)
    return cut || t.count > max ? String(t.prefix(max - 1)) + "…" : t
}

func secretEqualsWithoutByteEarlyExit(_ a: String, _ b: String) -> Bool {
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

func isCurrentUsersT3Listener(_ pid: Int32, _ port: Int) -> Bool {
    var info = proc_bsdinfo()
    let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
          info.pbi_uid == getuid(), info.pbi_ruid == getuid() else { return false }
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
    let parts = String(cString: path).split(separator: "/").suffix(4).map(String.init)
    guard parts.count == 4, parts[0] == parts[3] + ".app", parts[1] == "Contents", parts[2] == "MacOS",
          parts[3].hasPrefix("T3 Code") else { return false }
    let fdSize = MemoryLayout<proc_fdinfo>.size
    let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard size > 0 else { return false }
    var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / fdSize + 16)
    let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * fdSize))
    guard got > 0 else { return false }
    for fd in fds.prefix(Int(got) / fdSize) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
        var s = socket_fdinfo()
        let n = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &s, n) == n, s.psi.soi_kind == SOCKINFO_TCP
        else { continue }
        let tcp = s.psi.soi_proto.pri_tcp
        if tcp.tcpsi_state == TSI_S_LISTEN,
           Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))) == port { return true }
    }
    return false
}

struct Thread {
    let id, title, project, status: String

    let root: String?
    let hidden: Bool
    let pendingKind: String?
    let pendingAt, startedAt, completedAt, visitedAt, snoozedUntil: Date?
    let planReady: Bool
    let errorClass, error, message: String?

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

    var unseen: Bool {
        guard let done = completedAt, let seen = visitedAt else { return false }
        return done > seen
    }
}

let workingStates: Set<String> = ["preparing", "queued", "starting", "running", "waiting"]

final class T3 {
    var threads: [String: Thread] = [:]
    var projects: [String: String] = [:]

    var state = "offline" {
        didSet { if state != oldValue { onChange?() } }
    }

    var onChange: (() -> Void)?
    private var sequence = 0
    private var ws: URLSessionWebSocketTask?
    private var retry = 1.0
    private var lastPong = Date()
    private var nextRequest = 1

    private var generation = 0
    private var issuing = false

    private var rejected = false
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

    private var base: URL? {
        let runtime = json(try? Data(contentsOf: t3Home.appendingPathComponent("userdata/server-runtime.json")))
        guard let p = runtime?["port"] as? Int, (1...65535).contains(p), let pid = runtime?["pid"] as? Int,
              (1..<Int(Int32.max)).contains(pid), isCurrentUsersT3Listener(Int32(pid), p) else { return nil }
        return URL(string: "http://127.0.0.1:\(p)")
    }

    private var token: String? {
        let url = dir.appendingPathComponent("t3-token")
        guard !rejected, read("t3-blocked") == nil,
              let made = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(made) < 365 * 86_400 else { return nil }
        let t = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return t?.isEmpty == false ? t : nil
    }

    private func request(_ base: URL, _ path: String, _ token: String, post: Bool = false) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        r.httpMethod = post ? "POST" : "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("2", forHTTPHeaderField: "x-t3-orchestration-protocol")
        return r
    }

    private func connect() {
        guard let token else {
            reset()
            if state != "auth" { log("no T3 Code access: run lumen-agents authorize") }
            state = "auth"

            onChange?()
            return
        }
        guard let server = base else { return offline() }
        let gen = generation
        session.dataTask(with: request(server, "api/orchestration/shell", token)) { [self] data, response, error in
            guard gen == generation else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return reject("shell snapshot: HTTP \(code)") }
            guard code == 200, let snap = json(data) else {
                if code != 0 { log("shell snapshot: HTTP \(code)") }
                return offline()
            }
            applySnapshot(snap)
            state = "ok"
            onChange?()
            subscribe(token, gen)
        }.resume()
    }

    private func subscribe(_ token: String, _ gen: Int) {
        guard let server = base else { return offline() }
        session.dataTask(with: request(server, "api/auth/websocket-ticket", token, post: true)) { [self] data, response, _ in
            guard gen == generation else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return reject("WebSocket ticket: HTTP \(code)") }
            guard code == 200, let ticket = json(data)?["ticket"] as? String, let server = base,
                  var url = URLComponents(url: server.appendingPathComponent("ws"), resolvingAgainstBaseURL: false)
            else { return offline() }
            url.scheme = "ws"
            url.queryItems = [URLQueryItem(name: "orchestrationProtocol", value: "2"),
                              URLQueryItem(name: "wsTicket", value: ticket)]
            guard let wsURL = url.url else { return offline() }
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

                    retry = 1
                    for v in msg["values"] as? [[String: Any]] ?? [] { apply(v) }
                    onChange?()

                    send(task, ["_tag": "Ack", "requestId": msg["requestId"] ?? ""])
                case "Pong":
                    lastPong = Date()
                case "Ping":
                    send(task, ["_tag": "Pong"])
                case "Exit", "Defect", "ClientProtocolError":
                    return lost(task, "stream ended: \(sanitizeBoundedDisplayLine(String(decoding: data ?? Data(), as: UTF8.self), 300))")
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
        offline()
    }

    private func reset() {
        generation += 1
        if let task = ws {
            ws = nil
            task.cancel(with: .goingAway, reason: nil)
        }
        threads = [:]
        projects = [:]
        sequence = 0
    }

    private func offline() {
        reset()
        state = "offline"
        onChange?()
        later()
    }

    private func reject(_ why: String) {
        log("T3 Code rejected the token (\(why)); run lumen-agents authorize to allow it again")
        reset()
        rejected = true
        do { try write("t3-blocked", Data()) } catch { log("couldn't save t3-blocked: \(error)") }
        do { try delete("t3-token") } catch { log("couldn't delete the rejected token: \(error)") }
        state = "auth"
        onChange?()
    }

    private func later() {
        let wait = retry, gen = generation
        retry = min(retry * 2, 30)

        q.asyncAfter(deadline: .now() + wait) { [self] in if gen == generation && ws == nil { connect() } }
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

    func authorize(_ done: @escaping (String?) -> Void) {
        guard !issuing else { return done("Already asking T3 Code for a token; try again in a moment.") }
        let cli = t3Home.appendingPathComponent("bin/t3")
        guard fm.isExecutableFile(atPath: cli.path) else { return done("T3 Code's t3 command isn't at \(cli.path).") }
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
                issuing = false
                guard proc.terminationStatus == 0 && !token.isEmpty else {
                    return done("t3 auth session issue failed (\(proc.terminationStatus)). Is T3 Code installed?")
                }

                do {
                    try write("t3-token", Data(token.utf8))
                    try delete("t3-blocked")
                } catch {
                    return done("Couldn't save the token in \(dir.path): \(error.localizedDescription)")
                }
                rejected = false
                retry = 1
                reset()
                connect()
                done(nil)
            }
        }
        issuing = true
        do { try p.run() } catch {
            issuing = false
            done("Couldn't run t3: \(error.localizedDescription)")
        }
    }

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
            var chat: [String: Any] = ["id": sanitizeBoundedDisplayLine(t.id, 100), "title": sanitizeBoundedDisplayLine(t.title, 200), "state": state,
                                       "detail": detail, "project": sanitizeBoundedDisplayLine(projects[t.project] ?? "", 80),
                                       "brand": t.brand, "model": sanitizeBoundedDisplayLine(t.model, 80)]
            if let at { chat["age"] = Int(max(0, min(now.timeIntervalSince(at), 1e9))) }
            let s = sanitizeBoundedDisplayLine(text ?? "", 280)
            if !s.isEmpty { chat["text"] = s }
            out.append((rank, at ?? now, chat))
        }
        out.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.at > $1.at }
        return out.prefix(20).map(\.chat)
    }
}

struct Device {
    let name: String
    let key: SymmetricKey
}

let codeAlphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

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

func deriveLengthPrefixedPairingKey(_ parts: [Data]) -> SymmetricKey {
    var h = SHA256()
    for p in parts {
        h.update(data: Data([UInt8(p.count >> 8 & 0xFF), UInt8(p.count & 0xFF)]))
        h.update(data: p)
    }
    return SymmetricKey(data: h.finalize())
}

final class Pairing {
    private(set) var devices: [String: Device] = [:]

    private var pending: [String: Pending] = [:]
    private var lastTime: [String: Int64] = [:]

    private var pairTimes: [String: [Date]] = [:]

    private(set) var unsaved = false

    struct Pending {
        let name, source: String
        let secret, tvKey, macKey: Data
        let made, expires: Date

        var seen: Date
        var request: (signed: Data, mac: Data, time: Int64)?
    }

    init() {
        var old = 0
        for (id, v) in json(read("devices.json")) ?? [:] {
            guard let d = v as? [String: Any], d["v"] as? Int == 2, let k = (d["key"] as? String).flatMap(unhex),
                  k.count == 32 else {
                old += 1
                continue
            }
            devices[id] = Device(name: sanitizeBoundedDisplayLine(d["name"] as? String ?? "TV", 60), key: SymmetricKey(data: k))
        }
        if old > 0 {
            log("dropped \(old) TV key(s) from an older pairing scheme; those TVs pair again")
            if case .failed(let why) = persistRemovalOrDeletePairingStore() { log(why) }
        }
    }

    private func save() throws {
        var out: [String: Any] = [:]
        for (id, d) in devices {
            out[id] = ["v": 2, "name": d.name, "key": d.key.withUnsafeBytes { hex($0) }]
        }
        try write("devices.json", encode(out))
        unsaved = false
    }

    enum Saved {
        case saved, cleared, failed(String)

        var survivesRestart: Bool {
            if case .failed = self { return false }
            return true
        }
    }

    private func persistRemovalOrDeletePairingStore() -> Saved {
        do {
            try save()
            return .saved
        } catch {
            log("couldn't save paired TVs: \(error)")
        }
        do {
            try delete("devices.json")
            log("deleted devices.json instead: after a restart, every TV pairs again")
            unsaved = false
            return .cleared
        } catch {
            unsaved = true
            return .failed("Couldn't save that in \(dir.path) (\(error.localizedDescription)), so the removed key "
                + "comes back when Lumen Agents restarts. Fix that folder's permissions, then unpair again.")
        }
    }

    func begin(_ body: [String: Any], from: String) -> (Int, [String: Any]) {
        let now = Date()
        pairTimes = pairTimes.compactMapValues { times in
            let recent = times.filter { now.timeIntervalSince($0) < 60 }
            return recent.isEmpty ? nil : recent
        }
        pending = pending.filter { $0.value.expires > now }
        guard (pairTimes[from]?.count ?? 0) < 10, pairTimes.values.joined().count < 120 else {
            return (429, ["error": "busy"])
        }
        pairTimes[from, default: []].append(now)
        guard let b64 = body["key"] as? String, b64.count < 400, let der = Data(base64Encoded: b64),
              let tvKey = try? P256.KeyAgreement.PublicKey(derRepresentation: der) else { return (400, ["error": "bad key"]) }
        let mine = P256.KeyAgreement.PrivateKey()
        guard let shared = try? mine.sharedSecretFromKeyAgreement(with: tvKey) else { return (400, ["error": "bad key"]) }
        let id = hex(SHA256.hash(data: der).prefix(8))
        guard pending[id] == nil, devices[id] == nil else { return (400, ["error": "bad key"]) }
        let name = sanitizeBoundedDisplayLine(body["name"] as? String ?? "TV", 60)
        let theirs = pending.filter { $0.value.source == from }
        if theirs.count >= 2, let oldest = theirs.min(by: { $0.value.made < $1.value.made }) { pending[oldest.key] = nil }
        if pending.count >= 64, let quiet = pending.min(by: { $0.value.seen < $1.value.seen }) { pending[quiet.key] = nil }
        pending[id] = Pending(name: name, source: from, secret: shared.withUnsafeBytes { Data($0) }, tvKey: der,
                              macKey: mine.publicKey.derRepresentation, made: now,
                              expires: now.addingTimeInterval(900), seen: now)
        log("pairing requested by \(name)")
        return (200, ["key": mine.publicKey.derRepresentation.base64EncodedString(), "mac": macName])
    }

    func approve(_ typed: String) throws -> String? {
        guard let code = normalize(typed) else { return nil }
        let now = Date()
        for (id, p) in pending where p.expires > now {
            guard let r = p.request else { continue }
            let key = deriveLengthPrefixedPairingKey([Data("lumen-agents/v2".utf8), p.secret, Data(code.utf8), p.tvKey, p.macKey])
            guard HMAC<SHA256>.isValidAuthenticationCode(r.mac, authenticating: r.signed, using: key) else { continue }
            devices[id] = Device(name: p.name, key: key)
            do { try save() } catch {
                devices[id] = nil
                throw error
            }
            pending[id] = nil
            lastTime[id] = r.time
            return p.name
        }
        return nil
    }

    func remove(_ id: String) -> Saved {
        guard let d = devices.removeValue(forKey: id) else { return unsaved ? persistRemovalOrDeletePairingStore() : .saved }
        lastTime[id] = nil
        log("\(d.name) forgot its key")
        return persistRemovalOrDeletePairingStore()
    }

    func forget(_ which: String) -> (gone: [String], saved: Saved) {
        let gone = devices.filter { which == "all" || $0.key == which || $0.value.name == which }.map(\.key)
        for id in gone {
            devices[id] = nil
            lastTime[id] = nil
        }
        return (gone, gone.isEmpty && !unsaved ? .saved : persistRemovalOrDeletePairingStore())
    }

    enum Check { case ok(String, SymmetricKey), pending, unknown }

    func check(_ r: Request) -> Check {
        guard let id = r.headers["x-lumen-device"], let time = r.headers["x-lumen-time"], let t = Int64(time),
              let mac = r.headers["x-lumen-auth"].flatMap(unhex) else { return .unknown }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard t > now - 600_000, t < now + 600_000, t > lastTime[id] ?? 0 else { return .unknown }
        let signed = Data("\(r.method) \(r.target)\n\(time)".utf8)
        if let d = devices[id] {
            guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: signed, using: d.key) else { return .unknown }
            lastTime[id] = t
            return .ok(id, d.key)
        }

        guard r.method == "GET", r.path == "/status", var p = pending[id], p.expires > Date() else { return .unknown }
        p.request = (signed, mac, t)
        p.seen = Date()
        pending[id] = p
        return .pending
    }
}

struct Request {
    let method, path, target: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    enum Parsed { case more, bad, ok(Request) }

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

    private var version = Int.random(in: 1..<1_000_000)
    private var shownKey = ""
    private var waiting: [(c: NWConnection, r: Request, id: String, key: SymmetricKey, until: Date)] = []
    private var open = 0

    private var sources: [String: Int] = [:]

    private let adminSecret = hex(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })

    init(_ t3: T3) {
        self.t3 = t3
        if let id = read("id").flatMap({ String(data: $0, encoding: .utf8) }), !id.isEmpty { helperId = id }
        else {
            helperId = hex(SymmetricKey(size: .bits128).withUnsafeBytes { Array($0.prefix(8)) })
            do { try write("id", Data(helperId.utf8)) } catch { log("couldn't save the helper's id: \(error)") }
        }
        do { try write("admin", Data(adminSecret.utf8)) } catch { log("couldn't save the admin secret: \(error)") }
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

    private func drop(_ ids: [String]) {
        for w in waiting where ids.contains(w.id) { w.c.cancel() }
        waiting.removeAll { ids.contains($0.id) }
    }

    private func listen() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let at = NWEndpoint.Port(integerLiteral: port)
            if !advertise { params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: at) }
            let l = advertise ? try NWListener(using: params, on: at) : try NWListener(using: params)
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

        let from = source(c), mine = sources[from] ?? 0
        guard mine < 8, from == "local" || open - (sources["local"] ?? 0) < 56 else { return c.cancel() }
        open += 1
        sources[from] = mine + 1
        c.stateUpdateHandler = { [self, weak c] s in
            if case .failed = s { c?.cancel() }
            if case .cancelled = s {
                open -= 1
                let left = (sources[from] ?? 1) - 1
                sources[from] = left > 0 ? left : nil
            }
        }
        c.start(queue: q)
        var buf = Data()
        var complete = false

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

    private func source(_ c: NWConnection) -> String {
        guard case .hostPort(let host, _) = c.endpoint else { return "?" }
        switch host {
        case .ipv4(let a): return a.isLoopback ? "local" : hex(a.rawValue)
        case .ipv6(let a):
            if let v4 = a.asIPv4 { return v4.isLoopback ? "local" : hex(v4.rawValue) }
            return a.isLoopback ? "local" : hex(a.rawValue)
        default: return "?"
        }
    }

    private func respond(_ c: NWConnection, _ r: Request) {

        if r.headers["origin"] != nil { return send(c, 403, ["error": "forbidden"]) }
        switch (r.method, r.path) {
        case ("GET", "/status"):
            switch pairing.check(r) {
            case .ok(let id, let key):
                if r.query["wait"] == String(version) && waiting.count < 32 {
                    waiting.append((c, r, id, key, Date().addingTimeInterval(45)))
                } else {
                    sealed(c, 200, status(), key, r)
                }

            case .pending: send(c, 403, ["error": "pending"])
            case .unknown: send(c, 401, ["error": "unknown device"])
            }
        case ("POST", "/pair"):
            let (code, reply) = pairing.begin(json(r.body) ?? [:], from: source(c))
            send(c, code, reply)
        case ("POST", "/forget"):
            guard case .ok(let id, let key) = pairing.check(r) else { return send(c, 401, ["error": "unknown device"]) }
            let saved = pairing.remove(id)
            drop([id])
            if case .failed(let why) = saved { log(why) }

            sealed(c, 200, encode(["forgot": saved.survivesRestart]), key, r)
        case (_, "/approve"), (_, "/devices"), (_, "/unpair"), (_, "/debug"), (_, "/authorize"):
            admin(c, r)
        default:
            send(c, 404, ["error": "not found"])
        }
    }

    private func admin(_ c: NWConnection, _ r: Request) {
        guard source(c) == "local" else { return send(c, 404, ["error": "not found"]) }
        guard ["127.0.0.1:\(port)", "localhost:\(port)"].contains((r.headers["host"] ?? "").lowercased()),
              secretEqualsWithoutByteEarlyExit(r.headers["authorization"] ?? "", "Bearer " + adminSecret)
        else { return send(c, 403, ["error": "forbidden"]) }
        switch (r.method, r.path) {
        case ("POST", "/approve"):
            do {
                if let name = try pairing.approve(String(decoding: r.body, as: UTF8.self)) {
                    send(c, 200, ["paired": name])
                } else {
                    send(c, 404, ["error": "No TV is showing that code. Open Lumen's home screen and try again."])
                }
            } catch {
                send(c, 500, ["error": "Couldn't save the pairing in \(dir.path) (\(error.localizedDescription)), "
                    + "so the TV isn't paired. Fix that folder's permissions and try again."])
            }
        case ("GET", "/devices"):
            send(c, 200, ["devices": pairing.devices.map { ["id": $0.key, "name": $0.value.name] }])
        case ("POST", "/unpair"):
            let retry = pairing.unsaved
            let (gone, saved) = pairing.forget(String(decoding: r.body, as: UTF8.self))
            drop(gone)
            switch saved {
            case .saved where retry:
                send(c, 200, ["removed": gone.count, "note": "Saved the earlier removal too: it lasts after a restart."])
            case .saved: send(c, 200, ["removed": gone.count])
            case .cleared:
                send(c, 200, ["removed": gone.count, "warning": "Couldn't update the list of paired TVs, so it was "
                    + "deleted: after Lumen Agents restarts, every TV pairs again."])
            case .failed(let why): send(c, 500, ["removed": gone.count, "error": why])
            }
        case ("POST", "/authorize"):
            t3.authorize { [self] error in
                if let error { send(c, 500, ["error": error]) } else { send(c, 200, ["authorized": true]) }
            }
        case ("GET", "/debug"):
            send(c, 200, encode(["t3": t3.state, "threads": t3.threads.count,
                                 "chats": t3.state == "ok" ? t3.chats() : []]))
        default:
            send(c, 404, ["error": "not found"])
        }
    }

    private func status() -> Data {
        var chats = t3.state == "ok" ? t3.chats() : []
        var withText = true
        while true {
            let body = encode(["v": 1, "version": version, "mac": macName, "t3": t3.state, "chats": chats])
            if body.count <= 65_536 || chats.isEmpty { return body }
            if withText {
                withText = false
                chats = chats.map { $0.filter { $0.key != "text" } }
            } else {
                chats.removeLast()
            }
        }
    }

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
                      429: "Too Many Requests", 500: "Internal Server Error"][code] ?? ""
        var head = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in ["Content-Type": "application/json"].merging(extra, uniquingKeysWith: { $1 }) {
            head += "\(k): \(v)\r\n"
        }
        c.send(content: Data((head + "\r\n").utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }
}

func local(_ method: String, _ path: String, _ body: String = "", wait: TimeInterval = 5) -> (Int, [String: Any]) {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!, timeoutInterval: wait)
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
case "authorize" where args.count == 1:

    let (code, reply) = local("POST", "/authorize", wait: 60)
    print(code == 200 ? "T3 Code access allowed. The TV shows your chats in a few seconds."
        : "\(reply["error"] ?? "Failed (HTTP \(code))")")
    exit(code == 200 ? 0 : 1)
case "unpair" where args.count == 2:
    let (code, reply) = local("POST", "/unpair", args.last!)
    print("Removed \(reply["removed"] ?? 0)")
    if let note = reply["error"] ?? reply["warning"] ?? reply["note"] { print("\(note)") }
    exit(code == 200 ? 0 : 1)
case "status":
    let data = encode(local("GET", "/debug").1)
    let pretty = (try? JSONSerialization.jsonObject(with: data)).flatMap {
        try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys])
    } ?? data
    print(String(data: pretty, encoding: .utf8) ?? "")
default:
    print("""
    usage: lumen-agents serve | authorize | pair <code> | devices | unpair <name|id|all> | status
    """)
    exit(2)
}
