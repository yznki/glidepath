# Glidepath site: design

Launch site for Glidepath, a free, open-source Mac menu bar app that runs scheduled Claude Code reviews of a team's
pull requests, checks each finding against the code, and lands one review per PR. It replaces `docs/index.html`.

## Brief

- **Subject:** Glidepath (github.com/yznki/glidepath), MIT, by Yazan (GitHub: yznki).
- **Audience:** developers and team leads who use Claude Code on a Mac; arriving from r/ClaudeAI, Show HN, r/macapps, X.
- **Job:** in 3 seconds say what it is; within one scroll show why it's trustworthy and beautiful; end on `brew install`.
- **Assets:** app screenshots `docs/shots/app/{now,reviews,schedule,settings}-dark.png`, hero GIF `docs/media/hero.gif`,
  brand marks in `assets/brand/` (copied to `docs/site/` as SVG), social image `assets/brand/social.png`, the approved
  app prototype `docs/design/v1.3/prototype.html` (tokens, glass cards, card-stack JS).
- **Content source of truth:** README.md (top bullets, "How a run works", "Safe on public repos", "What it costs",
  "Questions"). No new claims. Every number on the site must already be in the README.
- **Constraints:** static, GitHub Pages at `https://yznki.github.io/glidepath/` (base path `/glidepath`), deployed by a
  GitHub Actions workflow from `site/dist`. No analytics, no external requests except fonts at build time (self-host).

## Stack

Astro (static output, minimal JS; motion is the product) + GSAP/ScrollTrigger + Lenis + Three.js (real 3D: a runway
in perspective and glass cards flying in it). Fonts self-hosted.

## Concepts

| | Idea | Anchor | Signature | O/F/Fe/P |
|---|---|---|---|---|
| **A. Night approach** (name) | Scrolling the page flies the final approach at night: you descend the 3° glide slope toward a runway of silver lights, passing four fixes (Gather, Review, Check, Land), and a PR card touches down as a verdict. | "Glidepath" is the descent path to a runway; the app's last step is literally "Land"; reviews happen while you're away, at night. | Scroll-scrubbed 3D descent along the runway lights with a glass PR card flying ahead of the camera, its stage word changing at each fix, touching down at the end. | 4 / 5 / 3 / 1 |
| B. The sweep (process) | A radar sweep scans a field of PR blips and each blip resolves into a verdict. | "sweep" is the product's word for a run. | Radar arm sweeping blips into cards. | 3 / 4 / 4 / 3 |
| C. The stack (formal) | Everything is one 3D card stack; each section is a card pulled out and opened. | The popover is a Wallet-style stack. | Cards fanning out in 3D on scroll. | 3 / 4 / 4 / 3 |

**Pick A.** Strongest fit (the name, the Land step, "before you're back"), and a full rule system: altitude readouts
as labels, fixes as section markers, approach lights as rhythm, "go around" as the 404. Steal from C for the
touchdown: landed cards drop into the live popover stack.

## Concept card

```
Idea:        Scrolling flies the night approach: you glide down to a runway of silver lights while a PR is reviewed on the way down.
Metaphor:    an instrument approach at night: glide slope, fixes, approach lights, altitude, touchdown.
Signature:   pinned, scroll-scrubbed Three.js descent; one glass PR card flies ahead, its stage word flips at each fix, it touches down as "Changes" (amber) or "Approved" (white).
Emotion:     calm, precise, a little cinematic. Quiet cockpit at 2 a.m.
Motion verb: glide: long, smooth, decelerating moves; things settle onto a line like wheels onto tarmac. Never bounce.
Screenshot:  the runway lights converging to a vanishing point in black, a glass card mid-air above them, "REVIEW · 1,200 FT" in mono at the edge.
```

## Art direction

**Palette** (from the app; dark only)
| role | value |
|---|---|
| ground | `#030304` |
| ink | `#ECECEF` |
| muted | `rgba(236,236,242,.62)` (AA on ground at 14 px+) |
| line | `rgba(255,255,255,.08)` |
| accent (the only colour) | `#D29B45` sodium amber: changes verdict, the PAPI-style signal light, focus of attention |
| curtain / glass tint | `#0B0B0E` at .84 |

**Type**
- Display and text: **Geist** (Google, self-hosted, 200/300/400/500). Display set at weight 200, tracking −0.045em at
  ≥ 96 px, −0.03em at 48 px; leading 0.95 for display, 1.5 for body (17 px).
- Instruments: **Geist Mono** 400, 11 to 13 px, uppercase, tracking +0.14em: altitude, fix names, stage words, the
  install command.
- Fluid scale: display `clamp(48px, 9vw, 152px)`, h2 `clamp(36px, 5.5vw, 88px)`, body 17px, mono 12px.

**Grid & rhythm:** 12 columns, 24 px gutter, 64 px outer margin (16 px on phones). Instruments align to the outer
margin; display type hangs on column 1 with an optical −0.04em indent. Section rhythm varies: pinned scene (300vh) /
tight split / wide gallery / narrow column / full-bleed type.

**Shape:** radius 20 for glass panels, 999 for buttons and pills, 0 for everything else. **Glass** only on things that
are cards in the app (PR cards, the popover, screenshot frames), never on sections or nav.

**Motion language:** one ease `cubic-bezier(.16,1,.3,1)` (expo out = glide). Large: 900 to 1400 ms; small: 280 ms.
Stagger 40 ms. Scroll scenes are scrubbed (`scrub: 1`) not triggered. Hovers: buttons fill like the hold-to-post
liquid (left-to-right clip-path fill, 280 ms), links get a silver underline that draws from the left.

**Idle state:** approach lights pulse in sequence toward the runway (the "rabbit" strobe), 1 cycle per 2.4 s, very low
amplitude; the hero card drifts ±2 px. Paused off screen and under reduced motion.

## Sections (composition plan)

```
0. INTRO (≤ 1.6 s, real load): black; approach lights switch on in sequence from the horizon toward you;
   headline letters settle. No progress bar.

1. HERO (100vh, the 3D scene is a fixed canvas behind sections 1-2)
   ┌──────────────────────────────────────────────────────────┐
   │ ◐ Glidepath                         GitHub ★   Install  │  nav (mono), steps aside on scroll down
   │                                                          │
   │ PRs reviewed                              ALT 3,000 FT  │  instruments right edge (mono, muted)
   │ before you're back.                       GS 3.0°       │
   │ [one-line sub, muted, 2 lines max]                       │
   │ [ brew install yznki/tap/glidepath   Copy ]  [GitHub]    │
   │                 · · · · · runway lights → vanishing pt   │
   └──────────────────────────────────────────────────────────┘

2. DESCENT (pinned 400vh, scrubbed): camera glides down the slope. A glass PR card ("mara · lumen/web #482") flies
   ahead. Four fixes pass as runway-side labels; at each, the left column swaps its copy (one sentence each, from
   README "How a run works"):
     GATHER · 2,400 FT   card shows diff stats + callers count ticking up
     REVIEW · 1,600 FT   card shows 3 findings appearing
     CHECK  ·   800 FT   one finding is struck through and fades (dropped: didn't match the code)
     LAND   ·     0 FT   card touches down, verdict word "CHANGES" in amber; altitude reads 0
   Progress rail on the right edge: 4 ticks, current one lit.

3. TOUCHDOWN → THE STACK (split): left: "Lands in your menu bar." + the six README bullets as a tight list;
   right: the LIVE popover demo (from the prototype: click springs a card open, hold-to-post fills, swipe discards
   the held card). The landed card from section 2 is the top card.

4. THE APP (wide gallery): four screenshots in 3D glass frames on a gentle arc; scroll rotates the arc
   (rotateY −12° → 12°), pointer tilts the hovered frame ±6°. Mono caption per frame: NOW / REVIEWS / SCHEDULE / SETTINGS.

5. CLEARED TO LAND (narrow column): "Safe on public repos." The five safety bullets as a pre-landing checklist:
   each line's checkbox ticks as it crosses the viewport centre. Link to docs/security.md on GitHub.

6. FUEL (instrument panel): "What it costs." Three thin horizontal gauges (under 300 / 300 to 1,500 / over 1,500
   changed lines → ~150k / ~240k / ~500k tokens) that fill when in view; one sentence on new setups.

7. QUESTIONS (narrow column): the six README Q&As as <details>, hairline rows, mono "+" that rotates.

8. FINAL (full-bleed type): giant "Cleared for approach." then the install block again, GitHub link, "MIT · Made for
   Claude Code · Codex: vote in #1". Runway lights return low at the bottom edge.

404. "Go around." Missed approach: the runway lights recede upward; link back home.
```

**Genericness test, changes made:** a generic model would land on "dark hero + floating 3D cards + feature grid".
Changed: no feature grid (bullets live beside the real demo); 3D is a specific place (a runway at night) not floating
shapes; section labels are real instrument readouts tied to the pipeline, not eyebrows; the cost section is gauges
because tokens are fuel, not a pricing table.

## Reduced motion / no-GL

Static: a pre-rendered still of the runway scene (exported PNG from the Three scene at the hero camera) as the hero
background; the descent becomes four stacked blocks (fix label + sentence + a static card state each); no Lenis, no
scrub; checklist shown ticked; gauges shown full; all text visible.

## Mobile (390 px)

Hero type `clamp` min 48 px, instruments move under the sub; descent pinned 250vh with fewer lights (≤ 120 points),
DPR capped at 1.5, card scaled 0.8; gallery becomes a single column of frames with a smaller rotation; demo full width.
Tap targets ≥ 44 px. Nothing depends on hover.
