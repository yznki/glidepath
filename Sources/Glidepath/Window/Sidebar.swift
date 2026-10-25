import SwiftUI

/// The window's sidebar (prototype `.side`): brand row, scope, the five sections with SF Symbols, and the next-sweep
/// footer. It sits on a faint black pane over the glass.
struct Sidebar: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var store: Store
    @AppStorage("signalColour") private var signalKey = "amber"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GlidepathMark(size: 22, n: 7)
                Text("Glidepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Gotham.fg)
            }
            .padding(.horizontal, 10)
            .frame(height: WinMetrics.navRow)

            // The scope sits under the brand text, not the mark.
            Text(scope)
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .padding(.leading, 42)
                .padding(.bottom, WinMetrics.s24)

            VStack(spacing: 2) {
                ForEach(WindowSection.allCases, id: \.self) { section in
                    navRow(section)
                }
            }

            Spacer(minLength: WinMetrics.s24)

            VStack(alignment: .leading, spacing: 0) {
                Text(nextTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gotham.mute)
                Text(nextDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute.opacity(0.7))
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.horizontal, 10)
        .padding(.bottom, WinMetrics.s24)
        .frame(width: 196, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Gotham.edge).frame(width: 1)
        }
    }

    private var scope: String {
        let n = store.snap.repoCount
        return "\(n) repo\(n == 1 ? "" : "s")"
    }

    /// "Next sweep 7:00 PM": the time of the next sweep, from the same function the Schedule subtitle reads.
    private var nextTitle: String {
        guard let next = store.snap.nextRun else { return "No sweep scheduled" }
        return "Next sweep \(HeaderCopy.clock(next))"
    }

    /// "in 2 h 41 min · v1.3.0".
    private var nextDetail: String {
        guard let next = store.snap.nextRun else { return "v\(Version.current)" }
        return "in \(HeaderCopy.untilText(next, store.snap.now ?? Date())) · v\(Version.current)"
    }

    /// The SF Symbol each section shows in the sidebar.
    static func symbol(_ section: WindowSection) -> String {
        switch section {
        case .now: return "waveform.path.ecg"
        case .approach: return "scope"
        case .reviews: return "rectangle.stack"
        case .repos: return "arrow.triangle.branch"
        case .schedule: return "clock"
        case .settings: return "slider.horizontal.3"
        }
    }

    private func navRow(_ section: WindowSection) -> some View {
        let on = router.section == section
        let count = section == .now ? store.waitingCount : 0
        let inAir = store.snap.approach?.planes.filter { $0.phase != .landed }.count ?? 0
        return Button {
            router.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(section))
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18)
                    .opacity(0.7)
                Text(section.title)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                if section == .approach {
                    // The planes tend has in the air: small and faint, not a count.
                    if inAir > 0 {
                        Text("\(inAir) in the air")
                            .font(.system(size: 11))
                            .foregroundStyle(Gotham.mute.opacity(0.7))
                            .lineLimit(1)
                    }
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Gotham.signal(signalKey))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Gotham.row : Color.clear))
            .foregroundStyle(Gotham.fg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
