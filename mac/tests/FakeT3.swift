// A stand-in for T3 Code's server, for mac/tests/run.sh only. It's built as "T3 Code.app/Contents/MacOS/T3 Code"
// in a temporary folder so the helper's listener check accepts it, listens on loopback only, and is driven by files
// in <t3 home>/control:
//   tokens      tokens the fake t3 command issued (one per line); only these are accepted
//   revoked     revoked tokens: rejected with 401, and their streams are closed at once (as T3 Code does)
//   fail        while it exists, the shell snapshot answers 503 (T3 Code not ready)
//   drop        closes every stream once, then is deleted
//   delay       "<seconds> <title>": the next snapshot waits that long and names its chat <title>; then deleted
import CryptoKit
import Foundation
import Network

let home = URL(fileURLWithPath: CommandLine.arguments[1])
let control = home.appendingPathComponent("control")
let q = DispatchQueue(label: "fake-t3")
let fm = FileManager.default

func lines(_ name: String) -> Set<String> {
    let s = (try? String(contentsOf: control.appendingPathComponent(name), encoding: .utf8)) ?? ""
    return Set(s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}

func exists(_ name: String) -> Bool { fm.fileExists(atPath: control.appendingPathComponent(name).path) }

/** Takes the file if it's there (so each control file acts once). */
func take(_ name: String) -> String? {
    let url = control.appendingPathComponent(name)
    guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    try? fm.removeItem(at: url)
    return s
}

func valid(_ token: String?) -> Bool {
    guard let token else { return false }
    return lines("tokens").contains(token) && !lines("revoked").contains(token)
}

func reply(_ c: NWConnection, _ code: Int, _ body: String, close: Bool = true) {
    let head = "HTTP/1.1 \(code) X\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
        + "Connection: close\r\n\r\n"
    c.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in if close { c.cancel() } })
}

let unauthorized = #"{"_tag":"EnvironmentAuthInvalidError","code":"auth_invalid","reason":"invalid_credential","traceId":"t"}"#

func snapshot(_ title: String) -> String {
    let now = ISO8601DateFormatter().string(from: Date())
    return #"{"snapshotSequence":1,"projects":[{"id":"p1","title":"Project"}],"threads":[{"id":"t1","title":"\#(title)","projectId":"p1","status":"running","activityRunStartedAt":"\#(now)"}]}"#
}

// ---- WebSocket streams ---------------------------------------------------------------------

final class Stream {
    let c: NWConnection
    let token: String
    var buf = Data()
    init(_ c: NWConnection, _ token: String) {
        self.c = c
        self.token = token
    }
}
var streams: [ObjectIdentifier: Stream] = [:]

func frame(_ opcode: UInt8, _ payload: Data) -> Data {
    var f = Data([0x80 | opcode])
    if payload.count < 126 { f.append(UInt8(payload.count)) }
    else { f.append(126); f.append(UInt8(payload.count >> 8)); f.append(UInt8(payload.count & 0xFF)) }
    return f + payload
}

func close(_ s: Stream) {
    streams[ObjectIdentifier(s)] = nil
    s.c.send(content: frame(0x8, Data([0x03, 0xE8])), completion: .contentProcessed { _ in s.c.cancel() })
}

/** Client frames are masked; only small text, ping and close frames are expected. */
func readFrames(_ s: Stream) {
    while s.buf.count >= 2 {
        let b = [UInt8](s.buf.prefix(14))
        let opcode = b[0] & 0x0F
        var len = Int(b[1] & 0x7F), at = 2
        if len == 126 {
            guard b.count >= 4 else { return }
            len = Int(b[2]) << 8 | Int(b[3])
            at = 4
        } else if len == 127 { return close(s) }
        guard s.buf.count >= at + 4 + len else { return }
        let start = s.buf.startIndex
        let mask = [UInt8](s.buf[start + at..<start + at + 4])
        let payload = Data(s.buf[start + at + 4..<start + at + 4 + len].enumerated().map { $1 ^ mask[$0 % 4] })
        s.buf.removeFirst(at + 4 + len)
        switch opcode {
        case 0x8: return close(s)
        case 0x9: s.c.send(content: frame(0xA, payload), completion: .contentProcessed { _ in })
        case 0x1:
            let msg = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
            if msg?["_tag"] as? String == "Ping" {
                s.c.send(content: frame(0x1, Data(#"{"_tag":"Pong"}"#.utf8)), completion: .contentProcessed { _ in })
            } else if msg?["tag"] as? String == "orchestration.subscribeShell", let id = msg?["id"] as? String {
                // Nothing new since the snapshot, but the subscription works (the helper resets its backoff).
                let chunk = #"{"_tag":"Chunk","requestId":"\#(id)","values":[]}"#
                s.c.send(content: frame(0x1, Data(chunk.utf8)), completion: .contentProcessed { _ in })
            }
        default: break
        }
    }
}

func pump(_ s: Stream) {
    s.c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
        guard streams[ObjectIdentifier(s)] != nil else { return }
        if let data { s.buf.append(data) }
        readFrames(s)
        if done || error != nil {
            streams[ObjectIdentifier(s)] = nil
            return s.c.cancel()
        }
        pump(s)
    }
}

func upgrade(_ c: NWConnection, _ headers: [String: String], _ token: String) {
    let key = headers["sec-websocket-key"] ?? ""
    let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)))
        .base64EncodedString()
    let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        + "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
    let s = Stream(c, token)
    streams[ObjectIdentifier(s)] = s
    c.send(content: Data(head.utf8), completion: .contentProcessed { _ in pump(s) })
}

// ---- HTTP -------------------------------------------------------------------------------

func handle(_ c: NWConnection) {
    c.start(queue: q)
    var buf = Data()
    func next() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
            if let data { buf.append(data) }
            guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if done || error != nil { return c.cancel() }
                return next()
            }
            let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = head[0].split(separator: " ")
            var headers: [String: String] = [:]
            for line in head.dropFirst() {
                guard let i = line.firstIndex(of: ":") else { continue }
                headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            let target = first.count > 1 ? String(first[1]) : "/"
            let path = String(target.split(separator: "?").first ?? "")
            let bearer = headers["authorization"].flatMap { $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : nil }
            route(c, String(first.first ?? ""), path, target, headers, bearer)
        }
    }
    next()
}

func route(_ c: NWConnection, _ method: String, _ path: String, _ target: String, _ headers: [String: String],
           _ bearer: String?) {
    switch (method, path) {
    case ("GET", "/api/orchestration/shell"):
        // Checked when the request arrives, as T3 Code does; the reply may come later.
        guard valid(bearer) else { return reply(c, 401, unauthorized) }
        if exists("fail") { return reply(c, 503, "{}") }
        if let d = take("delay") {
            let parts = d.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1)
            let wait = Double(parts.first ?? "0") ?? 0
            let title = parts.count > 1 ? String(parts[1]) : "Fresh chat"
            return q.asyncAfter(deadline: .now() + wait) { reply(c, 200, snapshot(title)) }
        }
        reply(c, 200, snapshot("Fresh chat"))
    case ("POST", "/api/auth/websocket-ticket"):
        guard valid(bearer), let bearer else { return reply(c, 401, unauthorized) }
        reply(c, 200, #"{"ticket":"ticket-\#(bearer)"}"#)
    case ("GET", "/ws"):
        let ticket = URLComponents(string: target)?.queryItems?.first { $0.name == "wsTicket" }?.value ?? ""
        let token = ticket.hasPrefix("ticket-") ? String(ticket.dropFirst(7)) : ""
        guard valid(token) else { return reply(c, 401, unauthorized) }
        upgrade(c, headers, token)
    default:
        reply(c, 404, "{}")
    }
}

// ---- Main -------------------------------------------------------------------------------

try? fm.createDirectory(at: control, withIntermediateDirectories: true)
try? fm.createDirectory(at: home.appendingPathComponent("userdata"), withIntermediateDirectories: true)
let params = NWParameters.tcp
params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
let listener = try NWListener(using: params)
listener.newConnectionHandler = handle
listener.stateUpdateHandler = { s in
    guard case .ready = s, let p = listener.port?.rawValue else { return }
    let runtime = #"{"port":\#(p),"pid":\#(getpid())}"#
    try? Data(runtime.utf8).write(to: home.appendingPathComponent("userdata/server-runtime.json"))
}
listener.start(queue: q)

// Revocation and drops reach open streams at once.
let watch = DispatchSource.makeTimerSource(queue: q)
watch.schedule(deadline: .now(), repeating: 0.05)
watch.setEventHandler {
    let drop = take("drop") != nil
    for s in streams.values where drop || !valid(s.token) { close(s) }
}
watch.resume()
dispatchMain()
