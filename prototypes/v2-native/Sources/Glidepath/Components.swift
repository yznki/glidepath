import SwiftUI

extension Color {
    /// Amber means "needs you" and nothing else.
    static let amber = Color(red: 0.98, green: 0.71, blue: 0.27)
}

extension Color {
    /// Graphite: the app's accent for switches, sidebar icons and selection.
    static let graphite = Color(white: 0.62)
}

/// The one hold component for everything that goes to GitHub as you. 0.6 s; a tap shows the hint with a small shake.
/// Given `progress`, the light fills the parent's glass pane instead of the button.
struct HoldButton: View {
    let title: String
    let hint: String
    var large = false
    var hold = true               // false: a plain click, for actions that stay on this Mac (Try again)
    var external = false          // hold Space on the selected row drives the same button
    var progress: Binding<CGFloat>?
    let action: () -> Void

    @State private var own: CGFloat = 0
    @State private var pressedAt: Date?
    @State private var showHint = false
    @State private var shakes: CGFloat = 0
    @State private var externalTask: Task<Void, Never>?

    private var fill: Binding<CGFloat> { progress ?? $own }

    var body: some View {
        HStack(spacing: 8) {
            if showHint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            if hold {
                label
                    .modifier(Shake(animatableData: shakes))
                    .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 24, perform: complete, onPressingChanged: pressing)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(hint)
                    .accessibilityAction { action() }
            } else {
                Button(action: action) { label }.buttonStyle(.plain)
            }
        }
        .onChange(of: external) { _, held in
            guard hold else { if held { action() }; return }
            pressing(held)
            externalTask?.cancel()
            if held {
                externalTask = Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    if !Task.isCancelled { complete() }
                }
            }
        }
    }

    @ViewBuilder private var label: some View {
        let text = Text(title)
            .font(large ? .body.weight(.semibold) : .callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 18 : 13)
            .padding(.vertical, large ? 8 : 5)
        if progress != nil {
            // Inside a glass pane: no glass on glass, a quiet capsule.
            text.background(.white.opacity(0.1), in: .capsule).contentShape(.capsule)
        } else {
            text
                .background(alignment: .leading) {
                    GeometryReader { g in LightFill(progress: own).frame(width: g.size.width) }
                }
                .clipShape(.capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
    }

    private func pressing(_ down: Bool) {
        if down {
            pressedAt = .now
            withAnimation(.linear(duration: 0.6)) { fill.wrappedValue = 1 }
        } else if let at = pressedAt {
            pressedAt = nil
            withAnimation(.easeOut(duration: 0.3)) { fill.wrappedValue = 0 }
            if Date.now.timeIntervalSince(at) < 0.3 { tapped() }
        }
    }

    private func complete() {
        pressedAt = nil
        action()
        if progress == nil { withAnimation(.easeOut(duration: 0.4)) { own = 0 } }
    }

    private func tapped() {
        withAnimation(.snappy) { showHint = true }
        withAnimation(.linear(duration: 0.3)) { shakes += 1 }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.smooth) { showHint = false }
        }
    }
}

/// Light pouring along the line direction, left to right, brightest at its soft leading edge.
struct LightFill: View {
    var progress: CGFloat
    var body: some View {
        GeometryReader { g in
            let w = g.size.width * progress
            LinearGradient(stops: [.init(color: .white.opacity(0.06), location: 0),
                                   .init(color: .white.opacity(0.26), location: 0.7),
                                   .init(color: .white.opacity(0.55), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: w)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: max(0, 1 - 40 / max(w, 1))),
                                             .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                .opacity(progress > 0.001 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(animatableData * .pi * 4), y: 0))
    }
}

struct Avatar: View {
    let login: String
    var size: CGFloat = 28
    var body: some View {
        let initials = login.split(whereSeparator: { $0 == "-" || $0 == "_" }).compactMap(\.first).prefix(2).map(String.init).joined().uppercased()
        Circle()
            .fill(Color.gray.gradient)
            .frame(width: size, height: size)
            .overlay {
                if login == "dependabot" {
                    Image(systemName: "gearshape.fill").font(.system(size: size * 0.45)).foregroundStyle(.white)
                } else {
                    Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}

/// CI · Comments · Approval · Merge.
struct ProgressStrip: View {
    let steps: [Step]
    var spacing: CGFloat = 12
    static let names = ["CI", "Comments", "Approval", "Merge"]

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 4) {
                    icon(s)
                    Text(Self.names[i]).foregroundStyle(s == .needs ? Color.amber : (s == .todo ? Color.secondary : Color.primary))
                }
                .help("\(Self.names[i]): \(word(s))")
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func icon(_ s: Step) -> some View {
        switch s {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
        case .todo: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .needs: Image(systemName: "circle.fill").foregroundStyle(Color.amber)
        case .running: Image(systemName: "circle.dotted").foregroundStyle(.secondary).symbolEffect(.rotate, options: .repeating)
        }
    }
    private func word(_ s: Step) -> String {
        switch s { case .done: "done"; case .todo: "not yet"; case .needs: "needs you"; case .running: "Glidepath is on it" }
    }
}

struct BannerView: View {
    let banner: Banner
    let undo: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Text(banner.text).font(.callout)
            if banner.canUndo {
                Button("Undo", action: undo).buttonStyle(.glass).keyboardShortcut("z", modifiers: .command)
            }
        }
        .padding(.leading, 18).padding(.trailing, banner.canUndo ? 8 : 18).padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// "Review ready to post" in amber, then where it lives.
struct NeedLine: View {
    let pr: PR
    var body: some View {
        if let need = pr.need {
            Text("\(Text(need.label).foregroundStyle(Color.amber))  ·  \(pr.ref)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(pr.ref).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
