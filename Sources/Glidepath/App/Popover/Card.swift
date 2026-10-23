import SwiftUI
import AppKit

extension Verdict {
    /// The verdict word on a card and in the header.
    var word: String {
        switch self {
        case .approve: return "Approved"
        case .changes: return "Changes"
        case .skipped: return "Skipped"
        }
    }
}

extension Strip {
    /// A held draft: waiting for Post or Discard, with no post or discard running.
    var awaitsHold: Bool { draft && draftAction == nil }
    /// A PR skipped for size, which its card offers to review.
    var offersReview: Bool { skipReason == "size" && verdict == .skipped }
}

/// Non-held cards give under a drag like a rubber band (prototype `rubber`).
private func rubber(_ x: CGFloat) -> CGFloat { x * 280 * 0.55 / (280 + 0.55 * abs(x)) }

/// The pointer's tilt on one card, in degrees: width turns about the vertical axis, height about the horizontal one.
/// Each card owns one, so a move re-draws that card alone.
final class CardTiltModel: ObservableObject {
    @Published var active = false
    @Published var angle = CGSize.zero
}

/// One card of the popover stack (prototype `cardEl`, `paint`, `bindCard`): the strip row, and the body under it that
/// opens. The parent places it and orders it; the card draws itself, tilts, and takes its tap and swipe.
struct StackCard: View {
    let strip: Strip
    /// A sweep is running, so a card with no verdict and no stage is queued rather than unreviewed.
    let running: Bool
    let open: Bool
    /// Another card is open and this one piles below it.
    let piled: Bool
    /// The top card of that pile. Only it shows its row; the others sit behind it.
    let front: Bool
    let store: Store
    @ObservedObject var model: PopoverModel
    @StateObject private var tilt = CardTiltModel()

    @AppStorage("signalColour") private var signalKey = "amber"
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    private var height: CGFloat { open ? StackGeometry.open : StackGeometry.closed }
    private var held: Bool { strip.awaitsHold }
    private var queued: Bool { strip.verdict == nil && !strip.active && running }
    private var tilted: Bool { tilt.active && !Motion.reduced(reduceMotion) }
    /// A piled card's row shows only on the front of the pile, so no card's text shows through another's glass.
    private var rowHidden: Bool { piled && !front }
    private var signal: Color { Gotham.signal(signalKey) }

    /// The verdict word, or the stage while the card runs.
    private var word: String {
        if let verdict = strip.verdict { return verdict.word }
        if strip.active { return Presentation.phaseWords[min(max(strip.stage, 1), 4) - 1] }
        return running ? "Queued" : "No result"
    }

    private var wordColour: Color {
        switch strip.verdict {
        case .approve?: return Gotham.approve
        case .changes?: return signal
        case .skipped?, nil: return Gotham.mute
        }
    }

    private var light: VerdictLight {
        switch strip.verdict {
        case .approve?: return .approve
        case .changes?: return .changes
        case .skipped?: return .skipped
        case nil: return strip.active ? .running : .skipped
        }
    }

    /// The dot before the word: filled for a verdict or a running card, hollow otherwise.
    private var markerFill: Color? {
        if strip.active && strip.verdict == nil { return Gotham.run }
        switch strip.verdict {
        case .approve?: return Gotham.approve
        case .changes?: return signal
        case .skipped?, nil: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            row
            details
                .frame(height: StackGeometry.open - StackGeometry.closed, alignment: .top)
        }
        .frame(width: StackGeometry.cardWidth, height: height, alignment: .top)
        .clipped()
        .glassCard(radius: 20, verdict: light, held: held, piled: piled)
        .overlay { if strip.active && running { Tracer(shape: shape, lineWidth: 1) } }
        .contentShape(shape)
        .offset(x: model.drag[strip.id] ?? 0)
        .rotation3DEffect(.degrees(tilted ? Double(tilt.angle.width) : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .rotation3DEffect(.degrees(tilted ? Double(tilt.angle.height) : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .opacity(model.gone.contains(strip.id) ? 0 : 1)
        .animation(Motion.release, value: tilt.angle)
        .onTapGesture { toggle() }
        .gesture(swipe, including: running ? .subviews : .all)
        .onHover(perform: hover)
        .onContinuousHover(perform: pointer)
    }

    // MARK: Parts

    private var row: some View {
        HStack(spacing: 13) {
            AvatarView(login: strip.author ?? "", size: 36)
                .opacity(queued ? 0.35 : 1)
            Text(strip.author ?? "unknown")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(queued ? Gotham.mute : Gotham.fg)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                marker
                Text(word).cap().foregroundStyle(wordColour)
            }
            .fixedSize()
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .frame(height: StackGeometry.closed)
        .opacity(rowHidden ? 0 : 1)
        .animation(Motion.release, value: rowHidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(strip.author ?? "unknown"), \(word)\(held ? ", waiting for you" : ""): \(strip.title ?? "")")
    }

    private var marker: some View {
        Group {
            if let fill = markerFill {
                Circle().fill(fill).shadow(color: fill.opacity(0.8), radius: 4)
            } else {
                Circle().strokeBorder(Gotham.mute, lineWidth: 1)
            }
        }
        .frame(width: 6, height: 6)
    }

    /// Title, `#n · repo`, reason and actions. Hidden until the card opens.
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strip.title ?? "Untitled PR")
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.4)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(verbatim: "#\(strip.number) · \(strip.repo)")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .lineLimit(1)
                if strip.isDraftPR { tag("Draft PR") }
                if held { tag("Waiting") }
            }
            if let reason = strip.reason, strip.verdict != nil {
                Text(reason)
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.fg.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let error = strip.draftError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Gotham.fg.opacity(0.7))
                    .lineLimit(2)
            }
            // Only the open card renders its actions, so a closed card's buttons cannot take keyboard focus.
            if open { actions }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 18)
        .opacity(open ? 1 : 0)
        .allowsHitTesting(open)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Gotham.mute)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Gotham.row))
    }

    @ViewBuilder
    private var actions: some View {
        if held {
            // HoldButton ignores the environment's disabled state, so a running sweep is shown and blocked here.
            HStack(spacing: 8) {
                HoldButton(title: "Hold to post", doneTitle: "Posted",
                           tint: strip.verdict == .changes ? signal : Gotham.approve) {
                    store.postDraft(strip)
                }
                .allowsHitTesting(!running)
                .opacity(running ? 0.4 : 1)
                Button("Discard") { Confirm.discard(strip, store: store) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.mute)
                    .padding(.horizontal, 6)
                    .disabled(running)
            }
        } else if strip.offersReview {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.reviewWarning(strip))
                    .font(.system(size: 11))
                    .foregroundStyle(Gotham.mute)
                    .lineLimit(2)
                pill("Review") { store.reviewPR(strip) }
                    .disabled(store.snap.running)
            }
        } else {
            pill("Open on GitHub") { openOnGitHub() }
        }
    }

    private func pill(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Gotham.fg)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Gotham.row))
                .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func openOnGitHub() {
        if let url = URL(string: "https://github.com/\(strip.repo)/pull/\(strip.number)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Gestures

    private func toggle() {
        model.openID = open ? nil : strip.id
        model.highlight = nil
    }

    /// A horizontal drag: a held card follows 1:1, others rubber-band. Released past 160 pt (by where the drag would
    /// carry it) a held card flies off and is discarded; otherwise it springs back.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) else { return }
                model.drag[strip.id] = held ? dx : rubber(dx)
            }
            .onEnded { value in
                guard model.drag[strip.id] != nil else { return }
                let projected = value.predictedEndTranslation.width
                if held && abs(projected) > 160 {
                    withAnimation(Motion.release) {
                        model.drag[strip.id] = projected < 0 ? -480 : 480
                        model.gone.insert(strip.id)
                    }
                    let id = strip.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { finishSwipe(id) }
                } else {
                    withAnimation(Motion.release) { model.drag[strip.id] = nil }
                }
            }
    }

    /// After the card has flown off: discards it if it is still a held draft and no sweep runs. A refusal, a launch
    /// failure, or a card that is no longer held brings it back.
    private func finishSwipe(_ id: String) {
        guard let current = store.strips.first(where: { $0.id == id }), current.awaitsHold, !store.snap.running else {
            return springBack(id)
        }
        store.discardDraft(current)
        if store.draftErrors[id] != nil { springBack(id) }
    }

    private func springBack(_ id: String) {
        withAnimation(Motion.release) {
            model.drag[id] = nil
            model.gone.remove(id)
        }
    }

    private func hover(_ inside: Bool) {
        if inside {
            if model.openID == nil { model.highlight = strip.id }
        } else {
            if model.highlight == strip.id { model.highlight = nil }
            resetTilt()
        }
    }

    private func resetTilt() {
        tilt.active = false
        tilt.angle = .zero
    }

    /// Tilt of up to 4 degrees about the horizontal and 5 about the vertical, from where the pointer is on the card.
    private func pointer(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            guard !Motion.reduced(reduceMotion) else { return }
            let px = min(max(point.x / StackGeometry.cardWidth, 0), 1)
            let py = min(max(point.y / height, 0), 1)
            tilt.active = true
            tilt.angle = CGSize(width: (px - 0.5) * 10, height: (0.5 - py) * 8)
        case .ended:
            resetTilt()
        }
    }
}
