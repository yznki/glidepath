import Foundation

import ServiceManagement

let argv = Array(CommandLine.arguments.dropFirst())
if argv.first == "--render-icon" {
    exit(IconCommand.run(Array(argv.dropFirst())))
}
if argv == ["--unregister-login"] {
    // Called by `uninstall` through the app bundle, because the login item belongs to the app.
    try? SMAppService.mainApp.unregister()
    exit(0)
}
if argv.isEmpty || argv == ["app"] || argv.first == "--snapshot" {
    GlidepathApp.main()
}
exit(CLI.main(argv))
