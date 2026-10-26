import SwiftUI

/// Settings → Playbook: the repo's commands and lessons, from its playbook file. Commands are read-only. A lesson can be
/// edited or deleted, and the teach field adds one. Every change saves through `Playbook.save`; snapshots show it only.
struct PlaybookSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store
    @Environment(\.offscreenRender) private var offscreen

    /// The tended repos, in config order.
    private var slugs: [String] { (store.snap.config?.repos ?? []).filter(\.tend).map(\.slug) }

    /// The repo shown: the one picked when it is still tended, else the first tended repo.
    private var slug: String? {
        if let picked = model.playbookRepo, slugs.contains(picked) { return picked }
        return slugs.first
    }

    var body: some View {
        if model.matches(SettingsCopy.playbook) {
            SettingGroup(id: "g-playbook", title: "Playbook") {
                if let slug {
                    let book = model.playbook ?? store.snap.playbooks[slug] ?? Playbook()
                    SettingItem(label: SettingsCopy.playbookRepo.label, caption: SettingsCopy.playbookRepo.caption,
                                error: model.rowErrors["playbook"]) {
                        SettingSegmented(options: slugs.map { (value: $0, label: $0) }, selected: slug) { picked in
                            model.selectPlaybookRepo(picked, store: store)
                        }
                    }
                    commands(book)
                    lessons(book, slug: slug)
                    teach(slug: slug)
                } else {
                    SettingItem(label: "No repo to show",
                                caption: "Switch on tending for a repo in the Tending block, and its playbook appears here.") {
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: Commands

    @ViewBuilder private func commands(_ book: Playbook) -> some View {
        if book.commands.isEmpty {
            line(Text("No commands yet").font(.system(size: 13)).foregroundStyle(Gotham.mute),
                 "Commands appear here once a round verifies them.") { EmptyView() }
        }
        ForEach(Array(book.commands.enumerated()), id: \.offset) { _, command in
            line(Text(command.command)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Gotham.fg),
                 "verified \(command.verified)× · \(command.date.formatted(.dateTime.day().month(.abbreviated)))") {
                EmptyView()
            }
        }
    }

    // MARK: Lessons

    @ViewBuilder private func lessons(_ book: Playbook, slug: String) -> some View {
        if book.lessons.isEmpty {
            line(Text("No lessons yet").font(.system(size: 13)).foregroundStyle(Gotham.mute),
                 "Teach Glidepath a rule below.") { EmptyView() }
        }
        ForEach(Array(book.lessons.enumerated()), id: \.offset) { _, lesson in
            if model.editingLesson == lesson {
                editRow(slug: slug)
            } else {
                line(Text(lesson.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Gotham.fg)
                        .fixedSize(horizontal: false, vertical: true),
                     "\(lesson.source) · \(lesson.date.formatted(.dateTime.day().month(.abbreviated)))") {
                    HStack(spacing: 8) {
                        SettingButton(title: "Edit") { model.beginEdit(lesson) }
                        Button("Delete") { model.deleteLesson(lesson, store, slug: slug) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Gotham.mute)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                    }
                }
            }
        }
    }

    /// The open lesson's text, with Save and Cancel. Blank text keeps it open.
    private func editRow(slug: String) -> some View {
        let blank = model.lessonDraft.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 8) {
            well("Lesson", text: $model.lessonDraft) { model.saveEdit(store, slug: slug) }
            SettingButton(title: "Save", prominent: true, enabled: !blank) { model.saveEdit(store, slug: slug) }
            SettingButton(title: "Cancel") { model.cancelEdit() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Gotham.edge).frame(height: 1) }
    }

    // MARK: Teach

    private func teach(slug: String) -> some View {
        let blank = model.teachDraft.trimmingCharacters(in: .whitespaces).isEmpty
        return SettingItem(label: SettingsCopy.playbookTeach.label, caption: SettingsCopy.playbookTeach.caption, stacked: true) {
            HStack(spacing: 8) {
                well("Teach Glidepath about this repo… e.g. never edit migrations", text: $model.teachDraft) {
                    model.teach(store, slug: slug)
                }
                SettingButton(title: "Add", prominent: true, enabled: !blank) { model.teach(store, slug: slug) }
            }
        }
    }

    // MARK: Pieces

    /// A text field in the Gotham well, or its stand-in offscreen. Enter submits.
    private func well(_ placeholder: String, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        Group {
            if offscreen {
                FieldStandIn(text: text.wrappedValue, placeholder: placeholder, font: .system(size: 13), height: 30, radius: 8)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.fg)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Gotham.tint))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                    .onSubmit(submit)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One line in the list: a primary text with its secondary line under it, and the trailing controls.
    private func line<Primary: View, Trailing: View>(_ primary: Primary, _ secondary: String,
                                                     @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                primary
                Text(secondary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.mute)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Gotham.edge).frame(height: 1) }
    }
}
