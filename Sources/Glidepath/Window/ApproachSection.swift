import SwiftUI

/// The Approach section: every PR tend is working on, on the approach chart, with what needs the user below it.
struct ApproachSectionView: View {
    @ObservedObject var store: Store

    var body: some View {
        WinScroll {
            Text("Approach")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Gotham.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, WinMetrics.titlebarZone)
        }
    }
}
