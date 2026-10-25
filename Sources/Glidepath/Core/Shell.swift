import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

enum Shell {
    /// Runs an executable without a shell. A bare name is looked up in `PATH` (from `env` or this process).
    /// `input`, when given, is written to the process's stdin and then closed. Keep it small: it is written before stdout is read.
    static func run(_ exe: String, _ args: [String], cwd: String? = nil,
                    env: [String: String]? = nil, timeout: TimeInterval = 600, input: String? = nil) -> ShellResult {
        guard let path = exe.contains("/") ? exe : find(exe, path: env?["PATH"]) else {
            return ShellResult(status: 127, stdout: "", stderr: "\(exe): not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if let env { process.environment = env }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let stdin = input == nil ? nil : Pipe()
        if let stdin { process.standardInput = stdin }
        do {
            try process.run()
        } catch {
            return ShellResult(status: 126, stdout: "", stderr: "\(exe): \(error.localizedDescription)")
        }
        if let input, let stdin {
            try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        done.wait()
        killer.cancel()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self))
    }

    /// Runs with stdout and stderr connected to this process, so output appears as it is produced.
    static func inherit(_ exe: String, _ args: [String], env: [String: String]? = nil) -> Int32 {
        guard let path = exe.contains("/") ? exe : find(exe, path: env?["PATH"]) else {
            eprint("\(exe): not found")
            return 127
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let env { process.environment = env }
        do {
            try process.run()
        } catch {
            eprint("\(exe): \(error.localizedDescription)")
            return 126
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func find(_ name: String, path: String? = nil) -> String? {
        let dirs = (path ?? ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for dir in dirs {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
