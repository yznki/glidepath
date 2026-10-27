import SwiftUI

/// The morning briefing at the top of Approach: what landed, what waits on someone, and what Glidepath did since the last
/// briefing. Dismiss stamps `dismissedAt` in the briefing file (the caller does that).
struct BriefingCard: View {
    let briefing: Briefing
    /// The rows that wait on the user now, from the live needs. The briefing's own list goes stale until the next briefing.
    let blocked: [String]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                capLabel("Morning briefing")
                Spacer(minLength: 8)
                Text(HeaderCopy.clock(briefing.at))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.22))
                SettingButton(title: "Dismiss") { onDismiss() }
            }
            Text(headline)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Gotham.fg)
                .padding(.top, 10)
            Text(verbatim: "Glidepath ran \(briefing.rounds) rounds, answered \(briefing.threads) threads and used \(compactTokens(briefing.tokens)) tokens.")
                .font(.system(size: 13))
                .foregroundStyle(Gotham.mute)
                .padding(.top, 4)
            HStack(alignment: .top, spacing: 22) {
                column("Landed", briefing.landed, empty: "Nothing landed")
                column("Blocked", blocked, empty: "Nothing blocked")
                column("Glidepath did", did, empty: "No rounds")
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RadialGradient(colors: [Gotham.signal("amber").opacity(0.16), .clear], center: UnitPoint(x: 1, y: 0),
                           startRadius: 0, endRadius: 320)
        )
        .background(Color(hex: "08080B"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
    }

    private var headline: String {
        let landed = briefing.landed.isEmpty ? "Nothing landed" : "\(briefing.landed.count) landed"
        let waiting = blocked.isEmpty ? "nothing blocked" : "\(blocked.count) blocked"
        return "\(landed), \(waiting)."
    }

    private var did: [String] {
        guard briefing.rounds > 0 || briefing.threads > 0 || briefing.councils > 0 else { return [] }
        return ["\(briefing.rounds) rounds · \(briefing.threads) threads",
                "\(briefing.councils) \(briefing.councils == 1 ? "council" : "councils")"]
    }

    private func column(_ title: String, _ lines: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            capLabel(title)
                .padding(.bottom, 8)
            if lines.isEmpty {
                Text(empty)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.mute)
                    .padding(.vertical, 6)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Gotham.edge).frame(height: 1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
