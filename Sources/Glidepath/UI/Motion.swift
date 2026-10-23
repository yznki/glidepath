import SwiftUI

/// Spring presets from the 1.3 prototype, and the reduced-motion switch.
enum Motion {
    /// Cards springing open and closed in the stack.
    static let stack = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// Tilt and swipe release.
    static let release = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// True when the app's `motion` setting is "reduced" or the system asks for reduced motion.
    /// Views that read this also declare `@AppStorage("motion")` so they update when the setting changes.
    static func reduced(_ systemReduceMotion: Bool) -> Bool {
        systemReduceMotion || UserDefaults.standard.string(forKey: "motion") == "reduced"
    }
}

extension View {
    /// Animates changes to `value` with `spring`, or with a short ease-out when motion is reduced.
    func springy<V: Equatable>(_ spring: Animation = Motion.standard, value: V) -> some View {
        modifier(Springy(spring: spring, value: value))
    }
}

private struct Springy<V: Equatable>: ViewModifier {
    let spring: Animation
    let value: V
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.reduced(reduceMotion) ? .easeOut(duration: 0.15) : spring, value: value)
    }
}
