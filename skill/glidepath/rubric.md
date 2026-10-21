# Review rubric

The default bar for glidepath. A repo can extend it with a rules file (`rules_mode = "extend"`) or
replace the review bar with one (`rules_mode = "replace"`). Untrusted input rules, accuracy rules and
the output format always apply.

## Review bar: strict

Approve only code you would be happy to maintain. "It works" is not enough. Read the surrounding code on
the default branch first, so you judge the change against how this repo already does things.

- **Reuse.** New code that re-implements a helper, hook, component, type, query or pattern that already
  exists in the repo. Search for it, and name the existing piece with its path. Copy-pasted blocks
  that will drift apart.
- **Responsibility and cohesion.** Functions, components or modules doing several unrelated jobs; a
  change that forces edits in unrelated places.
- **Open/closed, Liskov, interface segregation, dependency inversion.** A type or flag switch that
  every new case must edit; a subtype that breaks the parent's contract; a wide interface callers use
  half of; business logic hard-wired to infrastructure it should receive.
- **KISS and YAGNI.** Speculative abstractions, configuration for values that never change, interfaces
  with one implementation, dead code, unused exports, commented-out code.
- **Layering.** Logic in the wrong layer or package; UI doing data access; leaky abstractions across
  module boundaries.
- **Coupling.** Reaching into another module's internals; circular imports; shared mutable state.
- **Correctness.** Swallowed or generic errors; unhandled edge cases (empty, null, maximum size,
  concurrency, retries); magic numbers or strings without a name; misleading names.
- **Tests.** New or changed non-trivial logic (a branch, parser, calculation, state machine, permission
  check) without a test that would fail if it broke. Tests that only assert that mocks were called.
- **Consistency.** Diverging from the repo's established convention for the same problem, without a
  reason written in the PR.

A principle violation is a blocker only when you can name the concrete cost: what drifts, what breaks,
or what gets harder. "Violates SRP" alone is not a finding. Say what to extract or reuse, and where it lives.

### Security and data boundaries

Always a blocker when present:

- A new query, mutation or file access without the tenancy or authorization check the repo requires.
  Check where the resource is loaded and whether access is asserted right after loading.
- Input from a request, message or file used without validation at the boundary.
- Secrets, tokens, credentials or signed URLs printed, logged, stored in fixtures or committed.
- Migrations or schema changes that weaken row-level security, constraints or grants.
- Workflows or CI changes that widen permissions or run untrusted PR code with secrets.

## Performance

Read the repo's performance notes if it has them. Then check:

- **Database.** Queries inside loops (N+1). A new `where` or `orderBy` with no matching index in the
  migration. Unbounded reads with no `take` or cursor. List endpoints selecting heavy columns. Filters on
  geometry or full-text without an index. Transactions held open across network or storage calls.
- **API.** Per-row heavy work on list endpoints; large payloads; slow synchronous work in a request
  that belongs on a queue; missing pagination.
- **Workers and jobs.** Whole files in memory where streaming works; no concurrency cap; retries that
  redo expensive work or are not idempotent; external calls without a timeout.

Rule: a performance finding names the input size that makes it hurt ("500 items per order, each
calling X on every row") and the growth (linear, quadratic). No speculative micro-optimisation. Prefer
the simplest fix: an index, a `select`, a `take`.

## Architecture

- **Ownership.** Logic in the module that owns it. Dependency direction unchanged; no new upward or
  cross-module imports.
- **Depth.** Pass-through layers that add nothing. Interfaces wider than their implementation. Seams
  where nothing varies.
- **Contracts and rollout.** Changes stay compatible while old clients, workers or migrations are still
  running during deploy (expand, then contract). Producers, consumers and shared types change together.
  Migrations are safe on a live table.
- **Failure modes.** What happens when a dependency is down, slow or returns garbage. Backpressure.
  Partial-failure cleanup. New failure paths are logged or measured.

Rule: an architecture finding names the concrete change that becomes harder or the failure that
happens. "Not clean" is not a finding.

## UI (only for UI files)

Read the repo's design guidance first: a design-system doc, the component library, and the tokens. The
repo's own rules beat this section.

- **Reinventing the wheel.** Hand-rolled tables, lists, dialogs, menus, forms or empty states where a
  shared component already does it. Name the component and its path.
- **Design drift.** Raw colours or one-off pixel sizes where the repo has tokens; spacing off the repo's
  grid; a restyle inside a page stylesheet instead of a component variant; the same fact shown twice.
- **Change at the source.** Patching a page around a shared component instead of fixing the token,
  variant or component.
- **Quality floor.** Keyboard reach and visible focus. Dialogs and drawers have titles. No content only
  visible on hover. Touch targets large enough for the platform. Strings go through the repo's i18n
  mechanism, and layouts survive right-to-left if the app supports it. Loading, empty and error states on
  data views.
- **React and component hygiene.** Request waterfalls; effects that should be derived state; unstable
  dependencies that cause refetch loops; heavy imports (maps, charts) not code-split.

UI blockers: reinventing a shared component or list system; raw values that bypass tokens; a page-level
restyle of a shared component; a missing i18n key; an untitled or unreachable dialog; a data view with no
loading, empty or error state. Pure taste is never a finding. Each UI finding names the rule's source (a
repo doc or the component it should use) and the fix.

## Blockers (REQUEST_CHANGES)

- security and data-boundary issues above;
- an N+1 or unbounded query on a table that grows;
- a missing index for a new hot query;
- a rollout that breaks running clients or workers;
- an external call with no timeout or failure handling;
- an ownership violation across modules;
- duplication of existing code that will drift;
- logic in the wrong layer;
- untested non-trivial logic;
- coupling that makes the next change risky;
- swallowed errors.

Naming, minor style and taste are comments, never blockers. If you are unsure whether something is a
blocker, make it a comment.

## Comments

- At most 5 per review, the most important. Rank by impact, not by file order.
- Each comment is one problem: what is wrong, the line, and what to change.
- `line` sits inside a hunk of the diff, on the RIGHT side.
- No praise padding, no restating the diff, no "nit:" prefixes unless the repo uses them.
