// Offline tests for Lumen Agents' T3 Code access and pairing removal; run with mac/tests/run.sh. They build the
// helper from mac/LumenAgents.swift and run it against FakeT3 and a fake t3 command, all in a temporary folder:
// nothing on this Mac's real T3 Code, Lumen Agents or TVs is read or changed, and nothing leaves loopback.
//   AgentsTests <helper> <fake T3 Code binary> <work folder>
import CryptoKit
import Foundation

let helper = CommandLine.arguments[1]
let fakeT3 = CommandLine.arguments[2]
let work = URL(fileURLWithPath: CommandLine.arguments[3])
let agentsDir = work.appendingPathComponent("agents")
let t3Home = work.appendingPathComponent("t3")
let control = t3Home.appendingPathComponent("control")
let port = Int.random(in: 40_000..<60_000)
let fm = FileManager.default
var failed = 0

func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok    \(what)" : "  FAIL  \(what)")
    if !ok { failed += 1 }
}

func hex(_ d: some Sequence<UInt8>) -> String { d.map { String(format: "%02x", $0) }.joined() }

func file(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

func json(_ url: URL) -> [String: Any] {
    (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

func touch(_ name: String, _ text: String = "") {
    try? Data(text.utf8).write(to: control.appendingPathComponent(name))
}

func append(_ name: String, _ line: String) { touch(name, file(control.appendingPathComponent(name)) + line + "\n") }

/** How many tokens the fake t3 command has issued. */
var issued: Int { file(control.appendingPathComponent("tokens")).split(separator: "\n").count }

func until(_ seconds: Double, _ test: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if test() { return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return test()
}

// ---- Processes ------------------------------------------------------------------------------

let env: [String: String] = {
    var e = ProcessInfo.processInfo.environment
    e["LUMEN_AGENTS_DIR"] = agentsDir.path
    e["LUMEN_AGENTS_PORT"] = String(port)
    e["T3CODE_HOME"] = t3Home.path
    return e
}()

var serving: Process?

func startHelper() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: helper)
    p.arguments = ["serve"]
    p.environment = env
    let log = work.appendingPathComponent("helper.log")
    if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
    let h = try! FileHandle(forWritingTo: log)
    h.seekToEndOfFile()
    p.standardError = h
    try! p.run()
    serving = p
    _ = until(10) { admin("GET", "/devices").0 == 200 }
}

func stopHelper() {
    serving?.terminate()
    serving?.waitUntilExit()
    serving = nil
}

/** Runs the lumen-agents command against the test helper. */
func command(_ args: String...) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: helper)
    p.arguments = args
    p.environment = env
    let out = Pipe()
    p.standardOutput = out
    try! p.run()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return (p.terminationStatus, text)
}

// ---- HTTP -------------------------------------------------------------------------------------

let session = URLSession(configuration: .ephemeral)

func http(_ r: URLRequest) -> (Int, Data) {
    var result = (0, Data())
    let done = DispatchSemaphore(value: 0)
    session.dataTask(with: r) { data, response, _ in
        result = ((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data())
        done.signal()
    }.resume()
    done.wait()
    return result
}

/** What the lumen-agents command sends; pass the secret when the folder it's in can't be read. */
func admin(_ method: String, _ path: String, _ body: String = "", secret: String? = nil) -> (Int, Data) {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!, timeoutInterval: 5)
    r.httpMethod = method
    if method == "POST" { r.httpBody = Data(body.utf8) }
    r.setValue("Bearer " + (secret ?? file(agentsDir.appendingPathComponent("admin"))),
               forHTTPHeaderField: "Authorization")
    return http(r)
}

/** This Mac's own addresses other than loopback, where something else on the network would connect. */
func networkAddresses() -> [String] {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return [] }
    defer { freeifaddrs(list) }
    var out: [String] = []
    for p in sequence(first: list!, next: { $0.pointee.ifa_next }) {
        guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { continue }
        let s = String(cString: host)
        if !s.hasPrefix("127.") { out.append(s) }
    }
    return out
}

/** Whether a TCP connection to address:port is accepted. */
func accepts(_ address: String, _ port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var a = sockaddr_in()
    a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_family = sa_family_t(AF_INET)
    a.sin_port = in_port_t(UInt16(port).bigEndian)
    inet_pton(AF_INET, address, &a.sin_addr)
    return withUnsafePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    } == 0
}

/** A TV, doing what AgentStatus.java does. */
final class TV {
    let mine = P256.KeyAgreement.PrivateKey()
    var key = SymmetricKey(size: .bits256)
    var code = ""
    var id: String { hex(SHA256.hash(data: mine.publicKey.derRepresentation).prefix(8)) }
    private var last: Int64 = 0

    /** Starts pairing, as the TV does when it shows a code; returns the code to type on the Mac. */
    func begin() -> String {
        let der = mine.publicKey.derRepresentation
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/pair")!, timeoutInterval: 5)
        r.httpMethod = "POST"
        r.httpBody = try! JSONSerialization.data(withJSONObject: ["key": der.base64EncodedString(), "name": "Test TV"])
        let (got, body) = http(r)
        precondition(got == 200, "pair: HTTP \(got)")
        let reply = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let macDer = Data(base64Encoded: reply["key"] as! String)!
        let secret = try! mine.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(derRepresentation: macDer))
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        code = String((0..<16).map { _ in alphabet.randomElement()! })
        var h = SHA256()
        for p in [Data("lumen-agents/v2".utf8), secret.withUnsafeBytes { Data($0) }, Data(code.utf8), der, macDer] {
            h.update(data: Data([UInt8(p.count >> 8 & 0xFF), UInt8(p.count & 0xFF)]))
            h.update(data: p)
        }
        key = SymmetricKey(data: h.finalize())
        // The Mac keeps the latest signed request to check the code against.
        _ = status()
        return code
    }

    /** Pairs it for good: begin(), then lumen-agents pair. */
    func pair() {
        let code = begin()
        let r = command("pair", code)
        precondition(r.status == 0, "lumen-agents pair: \(r.out)")
    }

    /** A signed /status; the reply opened when it's sealed with our key. */
    func status(wait version: Int? = nil, timeout: Double = 5) -> (code: Int, body: [String: Any]?) {
        let target = version.map { "/status?wait=\($0)" } ?? "/status"
        last = max(Int64(Date().timeIntervalSince1970 * 1000), last + 1)
        let time = String(last)
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(target)")!, timeoutInterval: timeout)
        r.setValue(id, forHTTPHeaderField: "X-Lumen-Device")
        r.setValue(time, forHTTPHeaderField: "X-Lumen-Time")
        let mac = HMAC<SHA256>.authenticationCode(for: Data("GET \(target)\n\(time)".utf8), using: key)
        r.setValue(hex(mac), forHTTPHeaderField: "X-Lumen-Auth")
        let (code, box) = http(r)
        guard code == 200, let sealed = try? AES.GCM.SealedBox(combined: box),
              let body = try? AES.GCM.open(sealed, using: key, authenticating: Data(time.utf8)) else { return (code, nil) }
        return (code, try? JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    var t3: String { status().body?["t3"] as? String ?? "" }
    var titles: [String] {
        (status().body?["chats"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
    }
    var version: Int { status().body?["version"] as? Int ?? -1 }
}

// ---- Setup ------------------------------------------------------------------------------------

try! fm.createDirectory(at: control, withIntermediateDirectories: true)
try! fm.createDirectory(at: t3Home.appendingPathComponent("bin"), withIntermediateDirectories: true)
// The fake t3 command: records each token it issues (FakeT3 accepts only those) and the arguments it got.
let cli = t3Home.appendingPathComponent("bin/t3")
try! """
#!/bin/sh
n=$(( $(wc -l < '\(control.path)/tokens' 2>/dev/null || echo 0) + 1 ))
echo "tok-$n" >> '\(control.path)/tokens'
echo "$*" >> '\(control.path)/args'
echo "tok-$n"
""".write(to: cli, atomically: true, encoding: .utf8)
try! fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)

let fake = Process()
fake.executableURL = URL(fileURLWithPath: fakeT3)
fake.arguments = [t3Home.path]
try! fake.run()
precondition(until(5) { fm.fileExists(atPath: t3Home.appendingPathComponent("userdata/server-runtime.json").path) })

startHelper()
let tv = TV()
tv.pair()

// ---- Tests ------------------------------------------------------------------------------------

print("The test helper is on loopback only")
check(accepts("127.0.0.1", port), "it accepts connections on 127.0.0.1")
let addresses = networkAddresses()
if addresses.isEmpty {
    print("  skip  no network address on this Mac to try")
} else {
    check(!addresses.contains { accepts($0, port) }, "but not on this Mac's network addresses (\(addresses.joined(separator: ", ")))")
    let fakePort = json(t3Home.appendingPathComponent("userdata/server-runtime.json"))["port"] as? Int ?? 0
    check(fakePort > 0 && accepts("127.0.0.1", fakePort) && !addresses.contains { accepts($0, fakePort) },
          "nor is FakeT3")
}

print("First start, never authorized")
check(until(5) { tv.t3 == "auth" }, "the TV hears T3 Code access is needed")
Thread.sleep(forTimeInterval: 2)
check(issued == 0, "no token is issued without lumen-agents authorize")
check(tv.titles.isEmpty, "no chats")

print("lumen-agents authorize")
var r = command("authorize")
check(r.status == 0, "it succeeds")
check(issued == 1, "exactly one token is issued")
check(file(control.appendingPathComponent("args")).contains("--scope orchestration:read"), "read-only scope")
check(file(control.appendingPathComponent("args")).contains("--ttl 365d"), "lasting a year")
check(until(5) { tv.titles == ["Fresh chat"] && tv.t3 == "ok" }, "the TV gets the chats")

print("T3 Code drops the stream and isn't ready for a moment")
touch("fail")
touch("drop")
check(until(5) { tv.t3 == "offline" }, "the TV hears it's offline")
check(tv.titles.isEmpty, "no chats from before the drop while it's offline")
try? fm.removeItem(at: control.appendingPathComponent("fail"))
check(until(10) { tv.t3 == "ok" && tv.titles == ["Fresh chat"] }, "it reconnects on its own")
check(issued == 1, "with the same token (none issued)")

print("A reply to a request made before the connection was replaced")
// The next snapshot is slow and stale; meanwhile you authorize again and the old token is revoked.
touch("delay", "3 STALE")
touch("drop")
check(until(3) { tv.t3 == "offline" }, "the drop is seen")
Thread.sleep(forTimeInterval: 1.2)
r = command("authorize")
append("revoked", "tok-1")
check(r.status == 0 && issued == 2, "authorize issues a second token")
var sawStale = false
_ = until(5) {
    if tv.titles.contains("STALE") { sawStale = true }
    return false
}
check(!sawStale, "the stale reply never reaches the TV")
check(tv.t3 == "ok" && tv.titles == ["Fresh chat"], "and it doesn't undo the new authorization")

print("Revoking the token in T3 Code")
let v = tv.version
var woke: (code: Int, body: [String: Any]?) = (0, nil)
let waited = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    woke = tv.status(wait: v, timeout: 60)
    waited.signal()
}
Thread.sleep(forTimeInterval: 0.5)
let revokedAt = Date()
append("revoked", "tok-2")
check(waited.wait(timeout: .now() + 10) == .success, "a waiting TV is answered at once")
check(Date().timeIntervalSince(revokedAt) < 5, "within a few seconds")
check(woke.code == 200 && (woke.body?["chats"] as? [Any])?.isEmpty == true && woke.body?["t3"] as? String != "ok",
      "with no chats")
check(until(5) { tv.t3 == "auth" }, "then T3 Code access is needed")
Thread.sleep(forTimeInterval: 3)
check(issued == 2, "no new token is issued")
check(!fm.fileExists(atPath: agentsDir.appendingPathComponent("t3-token").path), "the rejected token is deleted")
check(fm.fileExists(atPath: agentsDir.appendingPathComponent("t3-blocked").path), "t3-blocked is saved")

print("Restarting the helper after a revocation")
stopHelper()
startHelper()
check(until(5) { tv.t3 == "auth" }, "still no access")
try? fm.removeItem(at: agentsDir.appendingPathComponent("t3-blocked"))
stopHelper()
startHelper()
check(until(5) { tv.t3 == "auth" }, "nor with t3-blocked deleted (there's no token)")
// An old token put back while blocked isn't used either.
try! Data("tok-2".utf8).write(to: agentsDir.appendingPathComponent("t3-token"))
try! Data().write(to: agentsDir.appendingPathComponent("t3-blocked"))
stopHelper()
startHelper()
check(until(5) { tv.t3 == "auth" }, "nor with a token put back while t3-blocked is there")
Thread.sleep(forTimeInterval: 2)
check(issued == 2, "no token is issued across restarts")
check(tv.titles.isEmpty, "no chats")

print("Authorizing again")
r = command("authorize")
check(r.status == 0 && issued == 3, "lumen-agents authorize issues a new token")
check(until(5) { tv.t3 == "ok" && tv.titles == ["Fresh chat"] }, "and the TV gets chats again")
check(!fm.fileExists(atPath: agentsDir.appendingPathComponent("t3-blocked").path), "t3-blocked is cleared")

print("An old token")
// Backdates the token file, which is how the helper tells its age.
func age(_ days: Double) {
    try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)],
                          ofItemAtPath: agentsDir.appendingPathComponent("t3-token").path)
}
age(31)
stopHelper()
startHelper()
check(until(10) { tv.t3 == "ok" && tv.titles == ["Fresh chat"] }, "one older than 30 days is still used")
age(366)
stopHelper()
startHelper()
check(until(5) { tv.t3 == "auth" }, "one older than a year isn't")
Thread.sleep(forTimeInterval: 2)
check(issued == 3, "and no new token is issued")
check(tv.titles.isEmpty, "no chats")
r = command("authorize")
check(r.status == 0 && issued == 4, "lumen-agents authorize issues a new token")
check(until(5) { tv.t3 == "ok" && tv.titles == ["Fresh chat"] }, "and the TV gets chats again")

print("Unpairing one of two TVs")
let other = TV()
other.pair()
check(other.t3 == "ok", "a second TV is paired")
let va = tv.version, vb = other.version
var gotA: (code: Int, body: [String: Any]?) = (0, nil), gotB: (code: Int, body: [String: Any]?) = (0, nil)
let doneA = DispatchSemaphore(value: 0), doneB = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    gotA = tv.status(wait: va, timeout: 60)
    doneA.signal()
}
DispatchQueue.global().async {
    gotB = other.status(wait: vb, timeout: 60)
    doneB.signal()
}
Thread.sleep(forTimeInterval: 0.5)
r = command("unpair", tv.id)
check(r.status == 0 && r.out.contains("Removed 1"), "lumen-agents unpair <id> removes it")
check(doneA.wait(timeout: .now() + 5) == .success && gotA.body == nil, "its waiting request closes without data")
check(doneB.wait(timeout: .now() + 0.5) == .timedOut, "the other TV's request keeps waiting")
touch("drop")
check(doneB.wait(timeout: .now() + 10) == .success && gotB.body != nil, "and is answered when something changes")
check(tv.status().code == 401, "the removed TV is turned away")
check(until(10) { other.t3 == "ok" }, "the other TV gets chats again")
stopHelper()
startHelper()
check(tv.status().code == 401, "after a restart too")
check(until(10) { other.t3 == "ok" }, "and the other TV is still paired")

print("Unpairing when the change can't be saved")
let devices = agentsDir.appendingPathComponent("devices.json")
let keep = TV()
keep.pair()
let perms = (try? fm.attributesOfItem(atPath: agentsDir.path))?[.posixPermissions] as? Int ?? 0o700
let before = file(devices)
try! fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: agentsDir.path)
r = command("unpair", other.id)
try! fm.setAttributes([.posixPermissions: perms], ofItemAtPath: agentsDir.path)
check(r.status != 0, "lumen-agents unpair fails")
check(r.out.contains("comes back when Lumen Agents restarts"), "and says the key would come back")
check(file(devices) == before, "(devices.json is unchanged)")
check(other.status().code == 401, "the TV is still turned away at once")

print("Running the same unpair again once the folder is fixed")
r = command("unpair", other.id)
check(r.status == 0 && r.out.contains("Removed 0") && r.out.contains("Saved the earlier removal"),
      "it saves the earlier removal and says so")
check(file(devices) != before && !file(devices).contains(other.id), "devices.json no longer has that TV")
stopHelper()
startHelper()
check(other.status().code == 401, "the removed TV is still turned away after a restart")
check(keep.status().code == 200, "and the TV that wasn't unpaired still works")

print("Unpairing when the folder can't even be searched")
// The lumen-agents command reads the admin secret from that folder, so this asks the helper directly.
let secret = file(agentsDir.appendingPathComponent("admin"))
let kept = file(devices)
try! fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: agentsDir.path)
let (code0, body0) = admin("POST", "/unpair", keep.id, secret: secret)
try! fm.setAttributes([.posixPermissions: perms], ofItemAtPath: agentsDir.path)
let reply0 = (try? JSONSerialization.jsonObject(with: body0)) as? [String: Any] ?? [:]
check(code0 == 500 && (reply0["error"] as? String)?.contains("comes back") == true,
      "the helper reports a failure, not a removal that lasts")
check(file(devices) == kept && fm.fileExists(atPath: devices.path), "(devices.json is untouched)")
check(keep.status().code == 401, "the TV is turned away at once")
r = command("unpair", keep.id)
check(r.status == 0 && r.out.contains("Saved the earlier removal"), "running it again saves it")
stopHelper()
startHelper()
check(keep.status().code == 401, "and it lasts after a restart")

print("Unpairing when devices.json can't be rewritten but can be deleted")
let fourth = TV()
fourth.pair()
try! fm.removeItem(at: devices)
try! fm.createDirectory(at: devices, withIntermediateDirectories: false)
try! Data().write(to: devices.appendingPathComponent("x"))
r = command("unpair", fourth.id)
check(r.status == 0 && r.out.contains("every TV pairs again"), "it deletes devices.json and says so")
stopHelper()
startHelper()
check(fourth.status().code == 401, "the key doesn't come back after a restart")

print("Pairing when the key can't be saved")
let third = TV()
let code = third.begin()
try! fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: agentsDir.path)
r = command("pair", code)
try! fm.setAttributes([.posixPermissions: perms], ofItemAtPath: agentsDir.path)
check(r.status != 0 && r.out.contains("isn't paired"), "lumen-agents pair fails and says so")
check(third.status().code == 403, "the TV is still waiting, not paired")

stopHelper()
fake.terminate()
print(failed == 0 ? "All passed." : "\(failed) failed.")
exit(failed == 0 ? 0 : 1)
