import SwiftUI
import AppKit

/// Liquid Glass on macOS 26, standard materials on 14 and 15, same layout on both.
enum KitGlass {
    /// `GLIDEPATH_FORCE_FALLBACK_GLASS=1` draws the macOS 14–15 materials on macOS 26, to check the fallback.
    static let forceFallback = ProcessInfo.processInfo.environment["GLIDEPATH_FORCE_FALLBACK_GLASS"] == "1"

    /// True when the glass helpers draw Liquid Glass.
    static var isLiquid: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return !forceFallback }
        #endif
        return false
    }
}

extension View {
    /// A pane of glass: rows you act on, the status band, the banner.
    func glassPane(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassPane(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                           tint: tint, interactive: interactive))
    }

    /// A capsule of glass: buttons and small controls.
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassPane(shape: Capsule(), tint: tint, interactive: interactive))
    }

    /// Lets this glass morph into another piece with the same id in the same `GlassGroup` (macOS 26 only).
    @ViewBuilder func glassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !KitGlass.forceFallback {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The system's glass button style, bordered on macOS 14–15.
    @ViewBuilder func glassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !KitGlass.forceFallback {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.bordered)
        #endif
    }

    /// The smoked window background: the wallpaper reads through, the tone stays near-black.
    @ViewBuilder func smokedWindow() -> some View {
        if #available(macOS 15, *) {
            containerBackground(for: .window) { SmokedGlass() }
        } else {
            background(SmokedGlass().ignoresSafeArea())
        }
    }
}

private struct GlassPane<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !KitGlass.forceFallback {
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26, *)
    private var glass: Glass {
        let base = tint.map { Glass.regular.tint($0) } ?? .regular
        return interactive ? base.interactive() : base
    }
    #endif

    /// The same shape on a standard material, with a hairline edge where Liquid Glass would catch the light.
    private func fallback(_ content: Content) -> some View {
        content
            .background(shape.fill(tint ?? .clear))
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }
}

/// Glass pieces that sit close together and blend or morph as one. A plain stack on macOS 14–15.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !KitGlass.forceFallback {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Smoked glass: the wallpaper still shows through, blurred, but the tone stays near-black and calm on any wallpaper.
struct SmokedGlass: View {
    var body: some View {
        ZStack {
            BehindWindow()
            Color.black.opacity(0.52)
        }
    }
}

/// The desktop behind the window, blurred. Stays glass when another app is in front.
private struct BehindWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
