import Foundation

/// The onboarding steps in order. The rail draws one glide point per step.
enum OnboardingStep: Int, CaseIterable {
    case welcome, tools, repos, review, schedule, firstSweep

    /// The rail's label for the step.
    var label: String {
        switch self {
        case .welcome: return "Welcome"
        case .tools: return "Your tools"
        case .repos: return "Repos"
        case .review: return "How to review"
        case .schedule: return "Schedule"
        case .firstSweep: return "First sweep"
        }
    }
}

/// Whether each tool is ready. Claude Code, gh and git are required; GitNexus only adds the code graph.
struct ToolStatus: Equatable {
    var claudeSignedIn = false
    var ghSignedIn = false
    var gitReady = false
    var gitNexus = false

    var requiredMet: Bool { claudeSignedIn && ghSignedIn && gitReady }
}

/// The first sweep's outcome, as the last step shows it.
enum FirstSweep: Equatable {
    case notRun
    case running
    /// The dry run finished. `reviews` is how many PRs it reviewed; `summary` is the landing line.
    case finished(reviews: Int, summary: String)
    case failed(String)
}

extension OnboardingState {
    /// The step a reopened window starts on. A config that exists and a first sweep that failed reopen on the first
    /// sweep step, so "Try again" is there; anything else starts at the welcome step.
    static func resumeStep(configExists: Bool, failedSweep: String?) -> OnboardingStep {
        configExists && failedSweep != nil ? .firstSweep : .welcome
    }

    /// The failure text of a first sweep that failed, or nil.
    static func failure(of sweep: FirstSweep) -> String? {
        if case .failed(let text) = sweep { return text }
        return nil
    }
}

/// The failure of the last first sweep, kept across closing the window (the app stays running), so the window can
/// reopen on it. Cleared when a sweep starts or succeeds.
enum OnboardingResume {
    static var failedSweep: String?
}

/// The onboarding wizard's state. Pure: the window fills it in and drives it; nothing here touches disk or the network.
struct OnboardingState: Equatable {
    var step: OnboardingStep = .welcome
    var tools = ToolStatus()
    /// Selected repo slugs, in the order they were picked.
    var repos: [String] = []
    /// New repos start as drafts that wait for you to post them. A config without `posting` still means comment.
    var posting: Posting = .draft
    var authors: AuthorPolicy = .collaborators
    var schedule: [ScheduleTime] = Config.defaultSchedule.compactMap(ScheduleTime.init)
    var days: ScheduleDays = .weekdays
    var firstSweep: FirstSweep = .notRun

    /// Starts from an existing config when there is one, so the wizard shows what is already set up.
    static func initial(existing: Config?) -> OnboardingState {
        guard let existing else { return OnboardingState() }
        var state = OnboardingState()
        state.repos = existing.repos.map(\.slug)
        state.schedule = existing.schedule
        state.days = existing.days
        return state
    }

    /// Whether Continue may leave `step`. The tools step needs the three required tools; GitNexus never blocks.
    func canContinue(from step: OnboardingStep) -> Bool {
        switch step {
        case .welcome: return true
        case .review:
            // "These people" with no login is not a valid config.
            if case .logins(let logins) = authors { return !logins.isEmpty }
            return true
        case .tools: return tools.requiredMet
        case .repos: return !repos.isEmpty
        case .schedule: return !schedule.isEmpty
        case .firstSweep:
            if case .finished = firstSweep { return true }
            return false
        }
    }

    /// The step after `step`, or nil on the last one.
    func next(from step: OnboardingStep) -> OnboardingStep? {
        OnboardingStep(rawValue: step.rawValue + 1)
    }

    /// The step before `step`, or nil on the welcome step.
    func back(from step: OnboardingStep) -> OnboardingStep? {
        OnboardingStep(rawValue: step.rawValue - 1)
    }

    /// Back is offered on every step but the first.
    func canGoBackFrom(_ step: OnboardingStep) -> Bool {
        back(from: step) != nil
    }

    /// The config this state describes. Repos already in `base` keep their settings; each newly selected repo gets the
    /// posting mode and authors policy chosen here. Repos not selected are dropped.
    func config(base: Config?, home: String) -> Config {
        var config = base ?? Config.newSetup(schedule: schedule, repos: [])
        config.schedule = schedule
        config.days = days
        let kept = config.repos.filter { repos.contains($0.slug) }
        let added = repos.filter { slug in !kept.contains { $0.slug == slug } }.map { slug in
            RepoConfig(slug: slug, clone: ConfigEditor.defaultClone(slug: slug, home: home),
                       posting: posting, authors: authors)
        }
        config.repos = kept + added
        return config
    }
}
