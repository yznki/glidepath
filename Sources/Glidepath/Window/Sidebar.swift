import SwiftUI

/// The window's sidebar: brand row on the title line, scope, section list, and the next-sweep footer.
struct Sidebar: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GlidepathMark(size: 22, n: 7)
                Text("Glidepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WinTheme.text)
            }
            .padding(.horizontal, WinMetrics.s12)
            .frame(height: WinMetrics.navRow)

            // Scope sits under the brand text, not the mark: 44 in from the sidebar's edge.
            Text("2 repos · yznki")
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.faint)
                .padding(.leading, 44)
                .padding(.bottom, WinMetrics.s24)

            VStack(spacing: WinMetrics.navGap) {
                ForEach(WindowSection.allCases, id: \.self) { section in
                    navRow(section)
                }
            }

            Spacer(minLength: WinMetrics.s24)

            VStack(alignment: .leading, spacing: 0) {
                Text("Next sweep")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WinTheme.muted)
                Text("\(untilNext) · v\(Version.current)")
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
            }
            .padding(.horizontal, WinMetrics.s12)
        }
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.horizontal, WinMetrics.sidebarInset)
        .padding(.bottom, WinMetrics.s24)
        .frame(width: WinMetrics.sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            Rectangle().fill(WinTheme.line).frame(width: 1)
        }
    }

    /// "in 2 h 41 min" to the next sweep. The store's next run when known, else the fixture's.
    private var untilNext: String {
        guard let next = store.snap.nextRun else { return "no sweep scheduled" }
        let minutes = max(0, Int(next.timeIntervalSinceNow / 60))
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "in \(h) h \(m) min" : "in \(m) min"
    }

    private func navRow(_ section: WindowSection) -> some View {
        let on = router.section == section
        let count = section == .reviews ? store.waitingCount : 0
        return Button {
            router.section = section
        } label: {
            HStack(spacing: 10) {
                NavGlyph(kind: section)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                Text(section.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.amberInk)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, WinMetrics.s12)
            .frame(height: WinMetrics.navRow)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? WinTheme.active : Color.clear)
            )
            .foregroundStyle(on ? WinTheme.text : WinTheme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The five sidebar icons, drawn from kit.js `ICON` in their 16 x 16 viewBox. Stroke it at 1.5 pt.
struct NavGlyph: Shape {
    let kind: WindowSection

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
            CGRect(x: rect.minX + (x - r) * s, y: rect.minY + (y - r) * s, width: 2 * r * s, height: 2 * r * s)
        }
        var path = Path()
        switch kind {
        case .overview:
            path.addEllipse(in: circle(8, 8, 6.2))
            path.move(to: p(3, 6.5)); path.addLine(to: p(13, 6.5))
            path.move(to: p(2.4, 9.5)); path.addLine(to: p(13.6, 9.5))
        case .reviews:
            path.move(to: p(3, 4)); path.addLine(to: p(13, 4))
            path.move(to: p(3, 8)); path.addLine(to: p(13, 8))
            path.move(to: p(3, 12)); path.addLine(to: p(9, 12))
        case .repos:
            path.addEllipse(in: circle(4.5, 3.8, 1.6))
            path.addEllipse(in: circle(4.5, 12.2, 1.6))
            path.addEllipse(in: circle(11.5, 6, 1.6))
            path.move(to: p(4.5, 5.4)); path.addLine(to: p(4.5, 10.6))
            path.move(to: p(11.5, 7.6))
            path.addCurve(to: p(4.5, 10.6), control1: p(11.5, 10.1), control2: p(4.5, 9.1))
        case .schedule:
            path.addEllipse(in: circle(8, 8, 6.2))
            path.move(to: p(8, 4.5)); path.addLine(to: p(8, 8)); path.addLine(to: p(10.5, 9.5))
        case .settings:
            path.addEllipse(in: circle(8, 8, 2.2))
            let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (8, 1.8, 8, 3.8), (8, 12.2, 8, 14.2), (1.8, 8, 3.8, 8), (12.2, 8, 14.2, 8),
                (3.6, 3.6, 5, 5), (11, 11, 12.4, 12.4), (3.6, 12.4, 5, 11), (11, 5, 12.4, 3.6),
            ]
            for r in rays {
                path.move(to: p(r.0, r.1)); path.addLine(to: p(r.2, r.3))
            }
        }
        return path
    }
}
