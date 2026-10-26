import Foundation

import ServiceManagement

let argv = Array(CommandLine.arguments.dropFirst())
if argv == ["--unregister-login"] {
    // Called by `uninstall` through the app bundle, because the login item belongs to the app.
    try? SMAppService.mainApp.unregister()
    exit(0)
}
if argv.isEmpty || argv == ["app"] {
    // One menu bar app at a time. The lock lasts as long as the app; the kernel releases it if the app crashes.
    var lock: RunLock?
    do {
        guard let held = try RunLock.acquire(Paths().stateDir + "/app.lock") else {
            eprint("Glidepath is already running in the menu bar")
            exit(0)
        }
        lock = held
    } catch {
        lock = nil // the lock file cannot be created; start anyway rather than refuse to open
    }
    withExtendedLifetime(lock) { GlidepathApp.main() }
}
if argv == ["--seed-demo"] {
    do { try WindowFixtures.seedDemo(Paths()) } catch { eprint("\(error)"); exit(1) }
    exit(0)
}
if argv.first == "--kit-gallery" {
    MainActor.assumeIsolated { KitGallery.run(argv.dropFirst().first) }
}
if argv.first == "--snapshot" {
    GlidepathApp.main()
}
exit(CLI.main(argv))
