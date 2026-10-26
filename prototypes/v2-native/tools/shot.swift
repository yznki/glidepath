// Usage: swift tools/shot.swift <command-for-app|-> <out.png> [window-title-substring|popover]
// Sends a debug command to the running prototype, waits, then captures one of its windows.
import AppKit
let args = CommandLine.arguments
if args[1] != "-" {
    DistributedNotificationCenter.default().postNotificationName(.init("glidepath.proto"), object: args[1], userInfo: nil, deliverImmediately: true)
    Thread.sleep(forTimeInterval: 1.2)
}
guard args.count > 2 else { exit(0) }
let want = args.count > 3 ? args[3] : ""
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Glidepath" && ($0[kCGWindowLayer as String] as? Int) != nil }
for w in mine { print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, w[kCGWindowName as String] ?? "", w[kCGWindowBounds as String]!) }
let pick = mine.first { w in
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let h = (w[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0
    if want == "popover" { return layer > 0 && h > 60 }
    return layer == 0 && (want.isEmpty || name.contains(want))
}
guard let id = pick?[kCGWindowNumber as String] as? Int else { print("no window"); exit(1) }
let p = Process(); p.launchPath = "/usr/sbin/screencapture"; p.arguments = ["-x", "-o", "-l\(id)", args[2]]
try! p.run(); p.waitUntilExit()
print("saved", args[2])
