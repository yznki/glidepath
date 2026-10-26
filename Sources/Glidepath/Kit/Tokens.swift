import SwiftUI

extension Color {
    /// Amber means "needs you" and nothing else: beads, the needs-you label, the count.
    static let amber = Color(red: 0.98, green: 0.71, blue: 0.27)
    /// Graphite: the app's accent for switches, sidebar icons and selection.
    static let graphite = Color(white: 0.62)
}

/// The type ladder (spec §6a): system text styles only, one name per job.
enum Ladder {
    /// The one large moment: "Nothing needs you" on an empty page.
    static let hero = Font.largeTitle.weight(.semibold)
    /// A page or popover title.
    static let title = Font.title3.weight(.semibold)
    /// A row's title.
    static let rowTitle = Font.headline
    /// Everything else.
    static let body = Font.body
    /// Button labels and the status sentence's control.
    static let action = Font.callout.weight(.semibold)
    /// The line under a row title, the status sentence under a page title.
    static let secondary = Font.subheadline
    /// Hints and small print.
    static let fine = Font.footnote
}

extension Animation {
    /// "Glide and settle": a long ease-out with no bounce.
    static let glide = Animation.spring(duration: 0.9, bounce: 0)
    /// What replaces motion when Reduce Motion is on: a short cross-fade.
    static let fade = Animation.easeInOut(duration: 0.3)
}
