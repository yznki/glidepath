import Foundation

import ServiceManagement

let argv = Array(CommandLine.arguments.dropFirst())
if argv == ["--unregister-login"] {
    // Called by `uninstall` through the app bundle, because the login item belongs to the app.
    try? SMAppService.mainApp.unregister()
    exit(0)
}
if argv.isEmpty || argv == ["app"] || argv.first == "--snapshot" {
    ReviewRadarApp.main()
}
exit(CLI.main(argv))
