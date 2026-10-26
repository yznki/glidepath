import SwiftUI
import UniformTypeIdentifiers

/// The Split builder's state: the PR being split (the builder is shown only while `shown`), its parts as the user edits
/// them, and the files the PR changes. Moves keep the file set, so `changed` stays the plan's union. Build writes the
/// edited parts to a temporary file and runs `tend split build --parts`, which checks and saves them under the PR's lock.
@MainActor
final class SplitBuilderModel: ObservableObject {
    @Published var shown = false
    @Published private(set) var slug = ""
    @Published private(set) var n = 0
    @Published private(set) var title = ""
    /// The parts as the user edits them. Each title is bound to its field.
    @Published var parts: [SplitPart] = []
    /// The part a dragged file is over, by index.
    @Published var target: Int?
    /// Why the edits could not be written for Build. Nil when they could, or when Build has not run.
    @Published private(set) var saveError: String?
    /// Failed writes so far: the Build button takes a new identity on each, so its hold starts again.
    @Published private(set) var saveFailures = 0
    /// The plan the builder opened on. Build runs against it.
    private var plan: SplitPlan?
    /// Every changed file, in the order the plan lists them.
    private(set) var changed: [String] = []

    /// The id the builder's commands run under: the same as the split need's id.
    var id: String { "\(slug)#\(n)/split" }
    /// The first problem with the parts, or nil. Build is off while there is one.
    var problem: String? { Split.validate(parts, changed: changed) }

    /// A builder open on a split need, for snapshot rendering. Closed when `id` is nil or names no need.
    static func preset(_ id: String?, store: Store) -> SplitBuilderModel {
        let model = SplitBuilderModel()
        if let id, let item = store.snap.approach?.needs.first(where: { $0.id == id }) {
            model.open(slug: item.slug, n: item.n, title: item.title, store: store)
        }
        return model
    }

    /// Opens the builder on the proposed plan the snapshot holds for the PR. Nothing opens without one.
    func open(slug: String, n: Int, title: String, store: Store) {
        guard let plan = store.snap.splits["\(slug)#\(n)"], plan.status == "proposed" else { return }
        self.plan = plan
        self.slug = slug
        self.n = n
        self.title = title
        parts = plan.parts
        changed = plan.parts.reduce(into: [String]()) { list, part in
            for file in part.files where !list.contains(file) { list.append(file) }
        }
        target = nil
        saveError = nil
        shown = true
    }

    func close() {
        shown = false
    }

    /// Moves a file into part `k` (0-based). It leaves the part it was in.
    func move(_ file: String, to k: Int) {
        guard parts.indices.contains(k), !parts[k].files.contains(file) else { return }
        for i in parts.indices { parts[i].files.removeAll { $0 == file } }
        parts[k].files.append(file)
    }

    /// Writes the edited parts to a temporary file, then runs `tend split build --parts` on it. The builder closes when the
    /// build works. A write that fails keeps the builder open with the reason. The CLI rejects edits that do not check.
    func build(store: Store) {
        guard problem == nil, plan != nil, !store.tendBusy.contains(id) else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("glidepath-split-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(parts).write(to: file, options: .atomic)
        } catch {
            saveError = "Could not write the split: \(error.localizedDescription)"
            saveFailures += 1
            return
        }
        saveError = nil
        store.tendCommand(["split", "build", slug, String(n), "--parts", file.path], item: id, timeout: 7200) { [weak self] ok in
            try? FileManager.default.removeItem(at: file)
            if ok { self?.close() }
        }
    }
}

/// The Split builder, drawn over the section it opened from, as the call Edit sheet is. A column per part: its title
/// (edited in place), why, and its file chips. A chip moves to another part by drag, or from its menu. Build stays off
/// while `Split.validate` names a problem. Escape and Cancel close it; a click on the scrim does not, so edits stay.
struct SplitBuilderCard: View {
    @ObservedObject var model: SplitBuilderModel
    @ObservedObject var store: Store
    @Environment(\.offscreenRender) private var offscreen
    @AppStorage("signalColour") private var signalKey = "amber"
    private var signal: Color { Gotham.signal(signalKey) }
    private let faint = Color.white.opacity(0.22)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {}
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { model.close() }
    }

    private var card: some View {
        let busy = store.tendBusy.contains(model.id)
        let problem = model.problem
        let error = model.saveError ?? store.tendErrors[model.id]
        let files = model.changed.count
        return VStack(alignment: .leading, spacing: 0) {
            capLabel("Split plan", signal)
                .padding(.bottom, 8)
            Text(model.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Gotham.fg)
                .lineLimit(2)
            Text(verbatim: "\(model.slug) #\(String(model.n)) · \(String(files)) files")
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .padding(.top, 3)
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.parts.indices, id: \.self) { k in
                    column(k)
                }
            }
            .padding(.top, 16)
            Text(problem ?? "Every file is in one part.")
                .font(.system(size: 12))
                .foregroundStyle(problem == nil ? Gotham.mute : signal)
                .padding(.top, 14)
            if let error {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(signal)
                    .lineLimit(2)
                    .padding(.top, 6)
            }
            HStack(spacing: 8) {
                SettingButton(title: "Keep as one", enabled: !busy) {
                    store.tendCommand(["split", "keep", model.slug, String(model.n)], item: model.id) { ok in
                        if ok { model.close() }
                    }
                }
                Spacer(minLength: 0)
                SettingButton(title: "Cancel") { model.close() }
                buildButton
            }
            .padding(.top, 18)
        }
        .padding(22)
        .frame(width: 820)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "0B0B0E")))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 40)
    }

    /// Build is a hold, as the Needs rows' pushes are. Off while the plan is invalid or a command runs.
    private var buildButton: some View {
        let disabled = model.problem != nil || store.tendBusy.contains(model.id)
        return GothamHoldButton(title: "Hold to build stack", doneTitle: "Building…", tint: signal, compact: true) {
            model.build(store: store)
        }
        // A failed build or save gives the hold a new identity, so it starts again.
        .id("\(model.id)#\(store.tendFailures[model.id] ?? 0)/\(model.saveFailures)")
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    /// One part: its number and title, why, and its file chips. The column takes a dropped file.
    @ViewBuilder private func column(_ k: Int) -> some View {
        let part = model.parts[k]
        let body = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(k + 1))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(faint)
                titleField(k)
            }
            Text(part.why)
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(part.files, id: \.self) { file in
                    chip(file, from: k)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Gotham.row))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(model.target == k ? signal : Gotham.edge, lineWidth: 1))
        // A drop target is drawn as a prohibition sign offscreen, so a snapshot leaves it off; the chips still show.
        if offscreen {
            body
        } else {
            body.onDrop(of: [UTType.plainText], isTargeted: targeting(k)) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { path, _ in
                    guard let path else { return }
                    Task { @MainActor in model.move(path, to: k) }
                }
                return true
            }
        }
    }

    @ViewBuilder private func titleField(_ k: Int) -> some View {
        if offscreen {
            FieldStandIn(text: model.parts[k].title, placeholder: "Part title", font: .system(size: 13, weight: .semibold),
                         height: 30, radius: 8)
        } else {
            TextField("Part title", text: $model.parts[k].title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Gotham.fg)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "0C0C10")))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
        }
    }

    /// One file: its name, with the path as its help. Drag it to another part, or move it from the menu, which is how
    /// the same move works without a drag.
    private func chip(_ file: String, from k: Int) -> some View {
        let name = String(file.split(separator: "/").last ?? Substring(file))
        return Text(name)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Gotham.mute)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: "111116")))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
            .help(file)
            .accessibilityLabel(file)
            .onDrag { NSItemProvider(object: file as NSString) }
            .contextMenu {
                ForEach(model.parts.indices.filter { $0 != k }, id: \.self) { j in
                    Button("Move to part \(j + 1)") { model.move(file, to: j) }
                }
            }
    }

    private func targeting(_ k: Int) -> Binding<Bool> {
        Binding(get: { model.target == k }, set: { on in
            if on { model.target = k } else if model.target == k { model.target = nil }
        })
    }
}
