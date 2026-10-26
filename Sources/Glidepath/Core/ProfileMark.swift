/// What a PR is doing, as the profile shows it.
enum MarkKind: Equatable {
    case active(stage: Int)   // 1...4 on the slope: a blue circle, labelled with its number
    case queued               // running, not started yet: a hollow grey circle at the top of the slope
    case landed(Verdict)      // on the runway: a circle (approved), triangle (changes) or dash (skipped)
    case dropped              // finished without a verdict: a hollow grey circle on the runway
}

struct ProfileMark: Equatable, Identifiable {
    let id: String
    let kind: MarkKind
    /// "#1113", shown above an in-flight dot.
    var label: String = ""
    /// Carried over from an earlier sweep: drawn in tertiary grey.
    var carried = false
}
