import SwiftUI

/// The window's sidebar: brand row on the title line, scope, section list, and the next-sweep footer.
struct Sidebar: View {
    @ObservedObject var router: WindowRouter

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
                Text("v1.2.0")
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

    private func navRow(_ section: WindowSection) -> some View {
        let on = router.section == section
        return Button {
            router.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(section))
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16, height: 16)
                Text(section.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
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

    private func symbol(_ section: WindowSection) -> String {
        switch section {
        case .overview: return "circle.grid.2x1"
        case .reviews: return "list.bullet"
        case .repos: return "arrow.triangle.branch"
        case .schedule: return "clock"
        case .settings: return "gearshape"
        }
    }
}
