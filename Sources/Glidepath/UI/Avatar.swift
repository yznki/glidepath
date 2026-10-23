import SwiftUI
import AppKit

/// Downloads GitHub avatars and keeps them in ~/Library/Caches/Glidepath/avatars for 7 days.
actor AvatarCache {
    static let shared = AvatarCache()

    private let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Glidepath/avatars", isDirectory: true)
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// Loads in flight, so a login asked for twice at once is fetched once.
    private var loads: [String: Task<Data?, Never>] = [:]

    /// The image bytes: the cached copy if it is fresh, else a download. A failed download falls back to any stale
    /// copy. The view makes the NSImage on the main actor.
    func data(for login: String) async -> Data? {
        if let task = loads[login] { return await task.value }
        let task = Task { await self.load(login) }
        loads[login] = task
        let data = await task.value
        loads[login] = nil
        return data
    }

    private func load(_ login: String) async -> Data? {
        let file = dir.appendingPathComponent("\(login).png")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge,
           let cached = try? Data(contentsOf: file) {
            return cached
        }
        guard let url = URL(string: "https://github.com/\(login).png?size=96"),
              let fetched = try? await URLSession.shared.data(from: url),
              (fetched.1 as? HTTPURLResponse)?.statusCode == 200 else {
            return try? Data(contentsOf: file)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fetched.0.write(to: file, options: .atomic)
        return fetched.0
    }
}

/// The loaded image for an `AvatarView`.
final class AvatarModel: ObservableObject {
    @Published var image: NSImage?
}

/// A round GitHub avatar in grayscale. Until it loads, or if it never does, graphite with initials.
struct AvatarView: View {
    let login: String
    let size: CGFloat

    @StateObject private var model = AvatarModel()

    var body: some View {
        ZStack {
            fallback
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .grayscale(1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .task(id: login) {
            model.image = nil
            let data = await AvatarCache.shared.data(for: login)
            model.image = data.flatMap { NSImage(data: $0) }
        }
    }

    /// The prototype `avBg` and `ini`: lightness from a hash of the login, initials from its word starts.
    private var fallback: some View {
        let h = Self.hash(login)
        return ZStack {
            LinearGradient(colors: [Self.hsl(0.26 + Double(h % 18) / 100, saturation: 0.04),
                                    Self.hsl(0.07 + Double(h % 6) / 100, saturation: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.initials(login))
                .font(.system(size: size * 0.33, weight: .medium))
                .tracking(size * 0.02)
                .foregroundStyle(Gotham.fg)
        }
    }

    /// Fold over the UTF-8 bytes, h = h * 31 + c, starting at 7, wrapping at 32 bits.
    private static func hash(_ s: String) -> UInt32 {
        s.utf8.reduce(UInt32(7)) { $0 &* 31 &+ UInt32($1) }
    }

    private static func initials(_ login: String) -> String {
        login.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }

    /// hsl(240, saturation, lightness) as a SwiftUI colour.
    private static func hsl(_ lightness: Double, saturation: Double) -> Color {
        let v = lightness + saturation * min(lightness, 1 - lightness)
        let s = v == 0 ? 0 : 2 * (1 - lightness / v)
        return Color(hue: 240.0 / 360, saturation: s, brightness: v)
    }
}
