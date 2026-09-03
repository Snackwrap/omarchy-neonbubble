# Neon Bubble Pop — Omarchy bar plugin

A neon bubble shooter in the [Omarchy](https://omarchy.org) bar, with a **daily
board**: everyone gets the same puzzle each day, and a score to beat on it.

Click the **NB** pill to open the board. Middle-click resets to the menu.

## Controls

| Input | Action |
|-------|--------|
| **← →** | Aim (hold) |
| **SPACE** | Fire |
| **ENTER** | Start game / play again |
| **R** | Reset high-score tracker (menu or game over) |
| **ESC** | Close |

## How it plays

Match **three or more** touching bubbles of a colour and they pop. Anything the
popped cluster was holding up is no longer attached to the ceiling, so it comes
loose and falls — and a bubble you drop is worth more than one you pop, which is
the whole game. Aim at the walls: the shot reflects off them, and the useful
shots are usually the ones that go round something rather than at it.

Every **six shots** the ceiling comes down a row. Let the board reach the dashed
line and it is over.

The colour in the gun is only ever one still on the board, so a shot is never
wasted on a colour that cannot match.

## The daily board

By default the board is seeded from the date: the same puzzle for everybody,
every day, with today's best tracked separately from your all-time best. It is
a bar widget — you open it for a minute at a time — so a puzzle that resets
daily suits it better than an endless one.

Set `boardMode` to `random` for a fresh board every game.

## What is checked, and against what

`GameEngine.js` has no Qt types in it, so `tools/sim.mjs` runs the whole game
under node — 300 games, thousands of shots — and asserts on the outcomes rather
than on how it looks:

```bash
node tools/sim.mjs            # 300 games, summary
node tools/sim.mjs --check    # assertions, non-zero exit on failure
```

The invariants are the ones a bubble shooter lives or dies by, and each is
checked after **every shot** rather than at the end, because one bad resolve is
enough to see:

- **No bubble is ever left hanging off nothing.** Every bubble on the board must
  be reachable from the top row.
- **No unmatchable colour is ever dealt** — a bubble of a colour no longer on
  the board is a wasted shot that still brings the ceiling down.
- **A board past the line always ends the game**, rather than growing quietly
  off the bottom.
- **The hex grid is consistent**: at both board parities, every neighbour
  relation is mutual, every neighbour is exactly one bubble away, and no cell
  sits outside the walls. A staggered grid gets this wrong the moment a row
  offset changes sign, and the symptom is clusters that fail to match along one
  diagonal only.
- **The ceiling drop carries every row down intact.** The board's parity flips
  with the shift so each row keeps its length and alignment — checked by
  actually dropping a filled board, because the arithmetic version of that test
  was wrong while the code was right.
- **The daily board is a function of the date**: the same day repeats exactly,
  adjacent days differ, and no daily board holds a colour fewer than three
  times — a colour you cannot ever clear is not a puzzle.
- **The aim guide describes the path the shot takes**, drawn from the same
  numbers, so it cannot promise a bounce the bubble will not make.

## Requirements

- Omarchy **Quattro (v4)** with `omarchy-shell`
- `paplay` on `PATH` for sound (optional)
- `perl` for the high-score file (Omarchy depends on it)

## Install

```bash
omarchy plugin add https://github.com/Snackwrap/omarchy-neonbubble.git --enable
omarchy bar move com.leafbox.neonbubble right
```

## Settings

```bash
omarchy bar set com.leafbox.neonbubble boardMode random
omarchy restart shell
```

| Setting | Key | Default |
|---------|-----|---------|
| Sound effects | `sound` | `true` |
| Board | `boardMode` | `daily` — or `random` |
| Popup position | `popupPosition` | `icon` |
| Freeze a scene for a screenshot | `debugPreviewScene` | `off` |
| Print the popup's own frame to the journal | `debugGeometry` | `false` |

The last two exist for `tools/capture-preview.sh` and are not much use
otherwise.

## Files and processes

The high score is the only thing written to disk, and the only reason this
plugin starts a process at all besides `paplay`. It holds five integers, in
`~/.local/state/omarchy/plugins/com.leafbox.neonbubble/scores.json`:

- The reader opens it `O_RDONLY | O_NOFOLLOW | O_NONBLOCK` and checks *through
  that descriptor* that it is a regular file we own, with no extra links, not
  group- or world-writable, and small.
- The writer refuses any target but that one literal path, checks every
  directory on the way down the same way, writes to a temporary opened
  `O_CREAT | O_EXCL | O_NOFOLLOW` and renames it into place.
- A save arriving while one is in flight is queued and started from `onExited`,
  because setting `running = false` does not reap the child.
- The daily best is stamped with the day it belongs to, so a stale file cannot
  claim today's score.

Nothing here touches the network.

## License

MIT.
