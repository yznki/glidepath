import SwiftUI

struct Inspector: View {
    @Environment(Store.self) private var store

    var body: some View {
        switch store.inspected {
        case .pr(let id):
            if let pr = store.pr(id) { PRDetail(pr: pr) } else { nothing }
        case .repo(let name):
            if let i = store.repos.firstIndex(where: { $0.name == name }) { RepoDetail(index: i) } else { nothing }
        case nil:
            nothing
        }
    }

    private var nothing: some View {
        ContentUnavailableView("Nothing selected", systemImage: "sidebar.right",
                               description: Text("Pick a row to see it here."))
    }
}

// MARK: - PR page

struct PRDetail: View {
    @Environment(Store.self) private var store
    @Environment(\.undoManager) private var undo
    let pr: PR
    @State private var showLog = false
    @State private var reply = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Avatar(login: pr.author, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pr.ref).font(.subheadline).foregroundStyle(.secondary)
                            Text(pr.mine ? "Your PR" : "By \(pr.author)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text(pr.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let need = pr.need {
                        Text(need.label).font(.headline).foregroundStyle(Color.amber)
                    }
                    Text(sentence).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let need = pr.need {
                        HStack(spacing: 10) {
                            HoldButton(title: need.button, hint: need.hint, large: true, hold: need.isHold,
                                       external: store.spaceHeld) { store.complete(pr.id) }
                            Spacer()
                            PRMenu(pr: pr)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            }

            if pr.mine { yours } else { team }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { reply = pr.need == .ping ? pr.ping : pr.reply }
        .onChange(of: pr.id) { reply = pr.need == .ping ? pr.ping : pr.reply }
    }

    private var sentence: String {
        if !pr.mine && pr.state == .unchecked { return "Not checked yet. \(pr.lines) lines in \(pr.files) files. Next check at 5:00 PM." }
        return pr.reason
    }

    // Team PR: the review as it will appear on GitHub, findings, what was checked.
    @ViewBuilder private var team: some View {
        if pr.state == .skipped {
            Section("Skipped") {
                Label(pr.skip, systemImage: "forward")
                Button("Review Anyway") {}
            }
        } else if pr.state != .unchecked {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pr.review, id: \.self) { Text(.init($0)).fixedSize(horizontal: false, vertical: true) }
                }
                .textSelection(.enabled)
                .padding(.vertical, 4)
            } header: {
                Text(pr.state == .ready ? "Review, as it will appear on GitHub" : "Review posted on GitHub")
            } footer: {
                Text("Verdict: \(pr.verdict)").foregroundStyle(.secondary)
            }
            if !pr.findings.isEmpty {
                Section("Findings") {
                    ForEach(pr.findings, id: \.self) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: f.severity == .mustFix ? "circle.fill" : (f.severity == .shouldFix ? "circle.lefthalf.filled" : "circle"))
                                    .font(.caption2)
                                Text(f.severity.rawValue).font(.subheadline.weight(.semibold))
                            }
                            Text(.init(f.text)).fixedSize(horizontal: false, vertical: true)
                            Text(f.file).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("What Glidepath checked") {
                ForEach(pr.checked, id: \.self) { Label($0, systemImage: "checkmark") }
                if !pr.log.isEmpty {
                    DisclosureGroup("Show how it got there", isExpanded: $showLog) {
                        ForEach(pr.log, id: \.self) { m in
                            LabeledContent(m.text) { Text(m.time).monospacedDigit() }
                        }
                    }
                }
            }
        }
    }

    // Your PR: progress strip, the reply or fix waiting, then what Glidepath did.
    @ViewBuilder private var yours: some View {
        Section("Progress") {
            ProgressStrip(steps: pr.steps, spacing: 12)
                .fixedSize()
                .padding(.vertical, 4)
        }
        if pr.need == .reply {
            Section("Gadi asked") {
                Text(pr.ask)
            }
            Section {
                TextField("Reply", text: $reply, axis: .vertical)
                    .lineLimit(3...8)
                    .labelsHidden()
            } header: {
                Text("Reply, as it will appear on GitHub")
            }
        }
        if pr.need == .ping {
            Section {
                TextField("Message", text: $reply, axis: .vertical)
                    .lineLimit(3...8)
                    .labelsHidden()
            } header: {
                Text("Comment, as it will appear on GitHub")
            }
        }
        if pr.need == .push {
            Section("The fix (a3f9c1)") {
                ScrollView(.horizontal) {
                    Text(pr.fix)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
            }
        }
        Section("What Glidepath did") {
            ForEach(pr.timeline, id: \.self) { m in
                LabeledContent {
                    Text(m.time).monospacedDigit()
                } label: {
                    Text(m.text)
                }
            }
        }
        Section {
            Toggle("Look after this PR", isOn: lookAfter)
        } footer: {
            Text("Glidepath fixes CI, drafts replies and merges when ready, asking you first.")
                .foregroundStyle(.secondary)
        }
    }

    private var lookAfter: Binding<Bool> {
        Binding(get: { pr.lookAfter }, set: { v in if let i = store.index(pr.id) { store.prs[i].lookAfter = v } })
    }
}

// MARK: - Repo page

struct RepoDetail: View {
    @Environment(Store.self) private var store
    @Environment(\.undoManager) private var undo
    let index: Int
    @State private var teach = ""

    var body: some View {
        @Bindable var store = store
        let repo = $store.repos[index]
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.wrappedValue.name).font(.title2.weight(.semibold))
                    Text(repo.wrappedValue.last).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Toggle("Review team PRs", isOn: repo.review)
                Toggle("Look after my PRs", isOn: repo.lookAfter)
            }
            Section("Who to review") {
                Picker("Review PRs from", selection: repo.who) {
                    ForEach(Reviewers.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if repo.wrappedValue.who == .these {
                    LabeledContent("People") { Text(repo.wrappedValue.people.joined(separator: ", ")) }
                }
            }
            Section("Review rules") {
                LabeledContent("Rules file") {
                    Text(repo.wrappedValue.rules.isEmpty ? "None" : repo.wrappedValue.rules)
                        .font(repo.wrappedValue.rules.isEmpty ? .body : .body.monospaced())
                }
                Picker("Use them to", selection: repo.extend) {
                    Text("Extend the defaults").tag(true)
                    Text("Replace the defaults").tag(false)
                }
            }
            Section {
                ForEach(repo.wrappedValue.learned) { l in
                    LabeledContent {
                        Button("Remove") { store.repos[index].learned.removeAll { $0.id == l.id } }
                            .buttonStyle(.borderless)
                    } label: {
                        Text(l.text)
                        Text(l.kind)
                    }
                }
                TextField("New rule", text: $teach, prompt: Text("Teach Glidepath a rule"))
                    .onSubmit {
                        guard !teach.isEmpty else { return }
                        store.repos[index].learned.append(Learned(kind: "Rule", text: teach)); teach = ""
                    }
            } header: {
                Text("Learned")
            }
            Section("Look closer at") {
                ForEach(repo.wrappedValue.flags, id: \.self) { Text($0).font(.body.monospaced()) }
            }
            Section {
                Button("Remove Repo", role: .destructive) { store.removeRepo(repo.wrappedValue.name, undo: undo) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
