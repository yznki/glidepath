// All copy for the launch site. Source: README.md (top bullets, "How a run works", "Safe on public repos",
// "What it costs", "Questions"). No claim or number here is new; see site/DESIGN.md.

export const site = {
  name: 'Glidepath',
  url: 'https://yznki.github.io/glidepath/',
  origin: 'https://yznki.github.io',
  base: '/glidepath/',
  title: 'Glidepath: PRs reviewed before you’re back',
  description:
    'Free, open-source Mac menu bar app. It runs Claude Code reviews of your team’s pull requests on a schedule and lands one checked review per PR.',
  repo: 'https://github.com/yznki/glidepath',
  install: 'brew install yznki/tap/glidepath',
  author: 'Yazan',
  license: 'MIT',
  issue1: 'https://github.com/yznki/glidepath/issues/1',
  security: 'https://github.com/yznki/glidepath/blob/main/docs/security.md',
};

export const hero = {
  headline: ['PRs reviewed', 'before you’re back.'],
  sub: 'A free, open-source Mac menu bar app that runs Claude Code reviews of your team’s pull requests on a schedule.',
};

// DESCENT fixes, in order. `at` is the scroll progress where the fix passes; `ft` the altitude readout.
export const fixes = [
  {
    name: 'Gather',
    at: 0.12,
    ft: 2400,
    stage: 'Gathering',
    copy: 'A small model reads the diff and every caller of the changed code outside it.',
  },
  {
    name: 'Review',
    at: 0.37,
    ft: 1600,
    stage: 'Reviewing',
    copy: 'A stronger model reviews the change against a written rubric and your rules for the repo.',
  },
  {
    name: 'Check',
    at: 0.62,
    ft: 800,
    stage: 'Checking',
    copy: 'A second pass re-opens every quoted line and drops any finding that does not match the code.',
  },
  {
    name: 'Land',
    at: 1,
    ft: 0,
    stage: 'Landing',
    copy: 'One review per PR lands. On a new repo it waits for you to hold to post.',
  },
];

export const bullets = [
  ['Gist at a glance.', 'Approved, changes or skipped, and who the PR is from. Click a card for the reason.'],
  ['Checked, not guessed.', 'A second pass re-opens every quoted line and drops findings that don’t match the code.'],
  ['You stay in control.', 'New repos hold each review until you press and hold to post. Swipe to discard.'],
  ['Runs on your schedule.', 'A 24-hour dial, weekdays or any days you pick, pause for an hour or until tomorrow.'],
  ['Your rules.', 'A Markdown file per repo with what your team cares about.'],
  ['Your plan, your Mac.', 'Uses the Claude Code you already have. No account, no server, no telemetry.'],
];

export const shots = [
  { src: 'shots/now-dark.webp', caption: 'Now', note: 'Now shows the live sweep, with its stages, tokens and hold to stop.', alt: 'The Now view during a sweep: each PR with its stages, tokens and verdict.', w: 1800, h: 1177 },
  { src: 'shots/reviews-dark.webp', caption: 'Reviews', note: 'Reviews keeps the history.', alt: 'The Reviews view: one row per PR with its verdict.', w: 1800, h: 1177 },
  { src: 'shots/schedule-dark.webp', caption: 'Schedule', note: 'Schedule is a 24-hour dial.', alt: 'The Schedule view: a 24-hour dial with the sweep times.', w: 1800, h: 1177 },
  { src: 'shots/settings-dark.webp', caption: 'Settings', note: 'Settings has search and a live view of the config file.', alt: 'The Settings view with search and the config file.', w: 1800, h: 1177 },
];

export const safety = [
  'Claude may run only Glidepath’s own commands, each bound to the current run.',
  'A strict filter rejects any other shell command.',
  'Reads and writes stay inside the repo checkout and the run’s scratch folder.',
  'GitHub tokens never reach the model.',
  'Only collaborators’ PRs are reviewed. New repos hold each review as a draft until you post it.',
];

// Measured on a real team repo: 60 PRs across 16 sweeps (October 2026). Bar length is tokens over 500k.
export const costs = [
  { label: 'under 300', size: 'changed lines', tokens: '~150k', value: 150 },
  { label: '300 to 1,500', size: 'changed lines', tokens: '~240k', value: 240 },
  { label: 'over 1,500', size: 'changed lines', tokens: '~500k', value: 500 },
];

export const questions = [
  [
    'Do I need an API key?',
    'No. Glidepath runs the `claude` CLI you already use, on your Claude plan. An `ANTHROPIC_API_KEY` in your environment is passed through if you prefer API billing.',
  ],
  [
    'What leaves my Mac?',
    'Only what Claude Code and `gh` already send: the PR diffs and code Claude reads go to Anthropic, and the reviews you post go to GitHub. Glidepath itself talks only to github.com (and its API, to check for updates). No analytics, no server.',
  ],
  [
    'Does it post as me?',
    'Yes, through your `gh` login. New repos hold every review for you to post. Existing configs keep the posting mode they already have.',
  ],
  ['Private repos?', 'Yes, anything your `gh` login can read.'],
  ['How much does it use?', 'See the costs above. New setups start on Sonnet with five PRs a sweep.'],
  ['Linux or Windows?', 'No, it’s a native Mac app. The `glidepath` CLI is macOS-only too (it uses launchd).'],
];
