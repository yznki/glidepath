import Foundation

/// The morning briefing, `stateDir/tend/briefing.json`. The CLI writes it once a day; the app reads it and stamps
/// `dismissedAt` when the card is dismissed.
enum BriefingFile {
    static func path(_ paths: Paths) -> String {
        TendStore(paths: paths).dir + "/briefing.json"
    }

    static func load(_ paths: Paths) -> Briefing? {
        guard let data = FileManager.default.contents(atPath: path(paths)) else { return nil }
        return try? RunStore.decoder().decode(Briefing.self, from: data)
    }

    /// Stamps `dismissedAt` on the file's briefing. Nothing else in it changes.
    static func dismiss(_ paths: Paths, now: Date = Date()) throws {
        guard var briefing = load(paths) else { return }
        briefing.dismissedAt = now
        try TendStore(paths: paths).write(RunStore.encoder().encode(briefing), to: path(paths))
    }
}
