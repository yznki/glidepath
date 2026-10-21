import Foundation

let argv = Array(CommandLine.arguments.dropFirst())
if argv.isEmpty || argv == ["app"] || argv.first == "--snapshot" {
    ReviewRadarApp.main()
}
exit(CLI.main(argv))
