// Headless harness for GameEngine.js.
//
// The engine is pure JavaScript with no Qt types in it, so the whole game can
// be played here thousands of times a second and *measured* rather than judged
// by eye through a bar popup. A bubble shooter's bugs are the kind that are
// invisible in any one frame and glaring in aggregate: a cluster left hanging
// off nothing, a colour dealt that cannot be matched, a shot that reflects off
// a wall at the wrong angle, a board that overflows without ending the game.
//
//   node tools/sim.mjs                 summary over many random games
//   node tools/sim.mjs --check         assertions, non-zero exit on failure
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const src = readFileSync(join(here, "..", "GameEngine.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
const names = [...src.matchAll(/^function ([a-zA-Z0-9_]+)/gm)].map(m => m[1])
const vars = [...src.matchAll(/^var ([A-Z][A-Z0-9_]*) =/gm)].map(m => m[1])
const G = new Function(`${src}\nreturn {${names.concat(vars).join(",")}}`)()

const FRAME = 16.667

// Every bubble on the board must be reachable from the top row. This is the
// invariant a bubble shooter lives or dies by, and it is checked after every
// single shot rather than at the end, because one bad resolve is enough.
function floatingCount(s) {
  return G.findFloating(s.grid, s.parity).length
}

// Play a whole game with a policy that aims somewhere plausible and fires.
function playGame(seed, opts = {}) {
  let rng = seed >>> 0
  const rand = () => (((rng = (rng * 1664525 + 1013904223) >>> 0) / 4294967296))
  let s = G.create(seed, { daily: false, difficulty: opts.difficulty })

  const stats = {
    shots: 0, pops: 0, drops: 0, descends: 0, cleared: 0,
    floatingSeen: 0, deadColorDealt: 0, overflowMissed: 0,
    stuckAiming: 0, score: 0, frames: 0, specialsFired: 0, starsTaken: 0,
  }

  let frames = 0
  while (s.phase !== "gameover" && frames < 40000) {
    // Aim at a random angle, then fire. Holding the aim key is how a player
    // does it, so it is how the harness does it.
    const target = (rand() * 2 - 1) * G.AIM_MAX
    let guard = 0
    while (Math.abs(s.angle - target) > G.AIM_RATE && s.phase === "aim" && guard++ < 200) {
      s = G.step(s, FRAME, s.angle > target, s.angle < target, false)
      frames++
    }
    if (s.phase !== "aim") { stats.stuckAiming++; break }

    // What was actually fired must have been matchable when it left the gun.
    // Checked on the bubble in flight rather than on `current` before the step,
    // because the engine re-deals a colour that died between being dealt and
    // being fired — reading the pre-step value reports that correction as the
    // very fault it is correcting.
    const live = G.gridColors(s.grid, s.parity)
    const special = s.currentKind && s.currentKind !== "normal"
    if (special) stats.specialsFired++

    s = G.step(s, FRAME, false, false, true)
    frames++
    stats.shots++

    if (s.flying && (!s.flying.kind || s.flying.kind === "normal")
        && live.length && !live.includes(s.flying.color)) stats.deadColorDealt++

    let settle = 0
    while (s.phase === "fly" && settle++ < 400) { s = G.step(s, FRAME, false, false, false); frames++ }

    for (const e of s.events || []) {
      if (e === "pop") stats.pops++
      if (e === "drop") stats.drops++
      if (e === "descend") stats.descends++
      if (e === "cleared") stats.cleared++
      if (e === "star") stats.starsTaken++
    }

    const floats = floatingCount(s)
    if (floats > 0) {
      stats.floatingSeen += floats
      if (opts.report) opts.report(`  shot ${stats.shots}: ${floats} bubble(s) left floating`)
    }
    // A board past the death line that did not end the game.
    if (s.phase !== "gameover" && G.lowestFilledY(s.grid, s.parity) >= G.DEATH_Y) {
      stats.overflowMissed++
    }
  }
  stats.score = s.score
  stats.frames = frames
  return { stats, final: s }
}

const argv = process.argv.slice(2)
const GAMES = 300
const totals = { shots: 0, pops: 0, drops: 0, descends: 0, cleared: 0,
                 floatingSeen: 0, deadColorDealt: 0, overflowMissed: 0,
                 stuckAiming: 0, frames: 0, bestScore: 0,
                 specialsFired: 0, starsTaken: 0 }
for (let g = 0; g < GAMES; g++) {
  const { stats } = playGame(g * 7919 + 13)
  for (const k of Object.keys(totals)) {
    if (k === "bestScore") totals[k] = Math.max(totals[k], stats.score)
    else totals[k] += stats[k] || 0
  }
}

console.log(`\n${GAMES} games, ${totals.shots} shots\n`)
for (const [k, v] of [
  ["shots fired", totals.shots],
  ["clusters popped", totals.pops],
  ["clusters detached and fell", totals.drops],
  ["ceiling descents", totals.descends],
  ["boards cleared", totals.cleared],
  ["BUBBLES LEFT FLOATING", totals.floatingSeen],
  ["unmatchable colours dealt", totals.deadColorDealt],
  ["overflows that did not end the game", totals.overflowMissed],
  ["games that jammed while aiming", totals.stuckAiming],
  ["specials fired", totals.specialsFired],
  ["stars collected", totals.starsTaken],
  ["best score", totals.bestScore],
]) console.log(`  ${String(v).padStart(8)}  ${k}`)

if (argv.includes("--check")) {
  let bad = 0
  const fail = (m) => { console.log(`\nFAIL  ${m}`); bad++ }
  const ok = (cond, m) => { if (!cond) fail(m) }

  ok(totals.floatingSeen === 0, `${totals.floatingSeen} bubbles left hanging off nothing`)
  ok(totals.deadColorDealt === 0, `${totals.deadColorDealt} unmatchable colours dealt`)
  ok(totals.overflowMissed === 0, `${totals.overflowMissed} boards overflowed without ending`)
  ok(totals.stuckAiming === 0, `${totals.stuckAiming} games jammed while aiming`)
  ok(totals.pops > GAMES, `only ${totals.pops} pops across ${GAMES} games — is anything matching?`)
  ok(totals.drops > 0, "no cluster ever detached — is findFloating doing anything?")
  ok(totals.descends > 0, "the ceiling never came down")
  // Both of these are earned, so if random play never sees one the feature is
  // decoration. Stars used to come back 1 in 300 games, which is not a feature.
  ok(totals.specialsFired > GAMES / 4, `only ${totals.specialsFired} specials fired across ${GAMES} games`)
  ok(totals.starsTaken > GAMES / 8, `only ${totals.starsTaken} stars collected across ${GAMES} games`)

  for (const m of checkGeometry()) fail(m)
  for (const m of checkDaily()) fail(m)
  for (const m of checkRules()) fail(m)
  for (const m of checkSpecials()) fail(m)
  for (const m of checkDifficulty()) fail(m)

  console.log(bad ? `\n${bad} FAILED\n` : "\nall checks passed\n")
  process.exit(bad ? 1 : 0)
}
console.log()

// ------------------------------------------------------------------ checks

function checkGeometry() {
  const fails = []
  const ok = (c, m) => { if (!c) fails.push(m) }

  for (const parity of [0, 1]) {
    // Neighbours must be mutual, and exactly one bubble apart. A staggered
    // grid gets this wrong the moment the row-offset sign is flipped, and the
    // symptom is clusters that fail to match along one diagonal only.
    let asym = 0, wrongDist = 0, checked = 0
    for (let r = 0; r < G.boardRows(); r++) {
      for (let c = 0; c < G.boardRowLen(r, parity); c++) {
        for (const n of G.neighbors(r, c, parity)) {
          if (!G.inGrid(n.r, n.c, parity)) continue
          checked++
          if (!G.neighbors(n.r, n.c, parity).some(m => m.r === r && m.c === c)) asym++
          const d = Math.hypot(G.boardCellX(r, c, parity) - G.boardCellX(n.r, n.c, parity),
                               G.boardCellY(r) - G.boardCellY(n.r))
          if (Math.abs(d - 2 * G.bubbleR()) > 0.5) wrongDist++
        }
      }
    }
    ok(checked > 100, `parity ${parity}: only ${checked} neighbour pairs to check`)
    ok(asym === 0, `parity ${parity}: ${asym} neighbour relations are not mutual`)
    ok(wrongDist === 0, `parity ${parity}: ${wrongDist} neighbours are not one bubble apart`)
    // No cell may sit outside the walls.
    for (let r = 0; r < G.boardRows(); r++) {
      for (let c = 0; c < G.boardRowLen(r, parity); c++) {
        const x = G.boardCellX(r, c, parity)
        ok(x - G.bubbleR() >= -0.01 && x + G.bubbleR() <= G.boardWidth() + 0.01,
           `parity ${parity}: cell (${r},${c}) at x=${x.toFixed(1)} pokes through the wall`)
      }
    }
  }
  return fails
}

function checkDaily() {
  const fails = []
  const ok = (c, m) => { if (!c) fails.push(m) }
  const key = (s) => s.grid.map(r => r.map(v => v || ".").join("")).join("|")

  const a = G.create(G.boardSeedForDate(2026, 9, 3), { daily: true })
  const b = G.create(G.boardSeedForDate(2026, 9, 3), { daily: true })
  const c = G.create(G.boardSeedForDate(2026, 9, 4), { daily: true })
  ok(key(a) === key(b), "the same date must produce the same board")
  ok(key(a) !== key(c), "a different date must produce a different board")
  ok(a.current === b.current && a.next === b.next,
     "the same date must deal the same first bubbles")

  // The date has to actually reach the seed, in both directions.
  ok(G.boardSeedForDate(2026, 9, 3) !== G.boardSeedForDate(2026, 9, 4), "adjacent days must differ")
  ok(G.boardSeedForDate(2026, 9, 3) !== G.boardSeedForDate(2027, 9, 3), "adjacent years must differ")
  ok(G.boardTodaySeed(Date.UTC(2026, 8, 3, 12)) === G.boardSeedForDate(2026, 9, 3),
     "todaySeed must agree with seedForDate")

  // A board nobody can open is not a puzzle. Every colour present must appear
  // at least POP_MIN times, or it can never be cleared.
  let thin = 0
  for (let d = 1; d <= 60; d++) {
    const s = G.create(G.boardSeedForDate(2026, 9, d), { daily: true })
    const counts = Object.create(null)
    for (let r = 0; r < G.boardRows(); r++)
      for (let cc = 0; cc < G.boardRowLen(r, s.parity); cc++) {
        const v = s.grid[r][cc]
        if (v) counts[v] = (counts[v] || 0) + 1
      }
    for (const col of Object.keys(counts)) if (counts[col] < G.POP_MIN) thin++
  }
  ok(thin === 0, `${thin} daily boards hold a colour fewer than ${G.POP_MIN} times`)
  return fails
}

// Specials and stars. The thing that matters most here is that neither can
// leave the board in a state the ordinary rules would not have produced —
// a bomb clearing a hole without dropping what sat on top of it is the same
// bug as a pop that forgets to, and it is worth checking separately because
// it goes through a different path.
function checkSpecials() {
  const fails = []
  const ok = (c, m) => { if (!c) fails.push(m) }
  const blank = (rows) => {
    const s = G.create(1234, { daily: false, rows: rows === undefined ? 1 : rows })
    for (let r = 0; r < G.boardRows(); r++)
      for (let c = 0; c < G.boardRowLen(r, s.parity); c++) s.grid[r][c] = null
    return s
  }

  // The meter has to fill from clearing, and load a special when it does.
  let s = G.create(4242, { daily: false })
  ok(s.currentKind === "normal" && s.nextKind === "normal",
     "a new game must not start with a special loaded")
  s.charge = G.CHARGE_NEED
  const kind = G.takeSpecial(s)
  ok(kind === G.BOMB || kind === G.WILD, `a full meter must load a special, got ${kind}`)
  ok(s.charge === 0, "loading a special must spend the meter")
  ok(G.takeSpecial(s) === "normal", "an empty meter must load a normal bubble")

  // A bomb takes out what it touches whatever the colour, and drops whatever
  // that was holding up.
  s = blank()
  s.grid[0][2] = "pink"; s.grid[0][3] = "cyan"; s.grid[0][4] = "gold"
  s.grid[1][2] = "violet"; s.grid[1][3] = "lime"
  const before = G.countBubbles(s.grid, s.parity)
  const sc0 = s.score
  G.land(s, { r: 1, c: 3 }, "pink", G.BOMB)
  const after = G.countBubbles(s.grid, s.parity)
  ok(after < before, `a bomb must remove bubbles, ${before} -> ${after}`)
  ok(s.score > sc0, "a bomb must score")
  ok(G.findFloating(s.grid, s.parity).length === 0,
     "a bomb must drop whatever it cut loose")

  // A wildcard picks the colour that makes the biggest cluster, not the one it
  // touches most. Here it touches one pink and one cyan, but the cyan is part
  // of a run of three, so joining the cyan is the shot that pays.
  s = blank()
  s.grid[0][2] = "cyan"; s.grid[0][3] = "cyan"; s.grid[0][4] = "cyan"
  s.grid[1][1] = "pink"; s.grid[1][0] = "pink"
  const wildBefore = G.countBubbles(s.grid, s.parity)
  G.land(s, { r: 1, c: 2 }, "gold", G.WILD)
  ok((s.events || []).includes("pop"),
     "a wildcard that can complete a cluster must pop it")
  ok(G.countBubbles(s.grid, s.parity) < wildBefore,
     `a wildcard must clear bubbles, ${wildBefore} -> ${G.countBubbles(s.grid, s.parity)}`)
  ok(s.grid[0][2] === null && s.grid[0][3] === null && s.grid[0][4] === null,
     "the wildcard must have joined the cyan run rather than the pink pair")

  // With nothing to touch it still has to be a colour that exists.
  s = blank()
  s.grid[0][0] = "lime"
  G.land(s, { r: 0, c: 4 }, "gold", G.WILD)
  const placed = s.grid[0][4]
  ok(placed === null || G.boardColors().includes(placed),
     `a lone wildcard must resolve to a real colour, got ${placed}`)

  // Stars ride down with the ceiling and stay attached to their bubble.
  s = G.create(99, { daily: false })
  let seenStar = false
  for (let i = 0; i < 40 && !seenStar; i++) {
    G.dropCeiling(s)
    for (let c = 0; c < G.boardRowLen(0, s.parity); c++) if (s.stars[0][c]) seenStar = true
  }
  ok(seenStar, "the ceiling must eventually bring a star down")

  // The star grid must stay the same shape as the colour grid, or a descent
  // silently drops a column of flags.
  s = G.create(7, { daily: false })
  for (let i = 0; i < 12; i++) {
    G.dropCeiling(s)
    // Length as well as shape: a descent that unshifts without popping keeps
    // the alignment correct and grows the array forever, which nothing else
    // here would notice.
    ok(s.stars.length === G.boardRows(),
       `after ${i + 1} descents the star grid is ${s.stars.length} rows, board is ${G.boardRows()}`)
    for (let r = 0; r < G.boardRows(); r++) {
      ok(s.stars[r].length === G.boardRowLen(r, s.parity),
         `star row ${r} is ${s.stars[r].length} long, board row is ${G.boardRowLen(r, s.parity)}`)
    }
  }

  // Popping a star pays the bonus, once.
  s = blank()
  s.grid[0][1] = "pink"; s.grid[0][2] = "pink"
  s.stars[0][1] = true
  const sc1 = s.score
  G.land(s, { r: 0, c: 3 }, "pink")
  ok(s.score >= sc1 + G.STAR_SCORE, "popping a star must pay the bonus")
  ok(!s.stars[0][1], "a popped star must be cleared from the star grid")

  return fails
}

function checkRules() {
  const fails = []
  const ok = (c, m) => { if (!c) fails.push(m) }

  // Three of a colour pop; two do not.
  const mk = (cells) => {
    const s = G.create(1234, { daily: false, rows: 1 })
    for (let r = 0; r < G.boardRows(); r++)
      for (let c = 0; c < G.boardRowLen(r, s.parity); c++) s.grid[r][c] = null
    for (const [r, c, v] of cells) s.grid[r][c] = v
    return s
  }

  let s = mk([[0, 0, "pink"], [0, 1, "pink"]])
  ok(G.findCluster(s.grid, 0, 0, s.parity).length === 2, "two touching must be a cluster of two")

  s = mk([[0, 0, "pink"], [0, 1, "pink"], [0, 2, "pink"]])
  ok(G.findCluster(s.grid, 0, 0, s.parity).length === 3, "three in a row must be one cluster")

  s = mk([[0, 0, "pink"], [0, 2, "pink"]])
  ok(G.findCluster(s.grid, 0, 0, s.parity).length === 1, "a gap must break the cluster")

  // Colour matters.
  s = mk([[0, 0, "pink"], [0, 1, "cyan"], [0, 2, "pink"]])
  ok(G.findCluster(s.grid, 0, 0, s.parity).length === 1, "a different colour must break the cluster")

  // Anything not reachable from the top row is floating.
  s = mk([[0, 0, "pink"], [3, 3, "cyan"]])
  const f = G.findFloating(s.grid, s.parity)
  ok(f.length === 1 && f[0].r === 3 && f[0].c === 3,
     `an unattached bubble must be floating, got ${JSON.stringify(f)}`)

  s = mk([[0, 0, "pink"], [1, 0, "cyan"]])
  ok(G.findFloating(s.grid, s.parity).length === 0,
     "a bubble hanging off the top row must not be floating")

  // The ceiling drop must carry every row down intact. Checked by actually
  // dropping a board full of distinguishable rows rather than by reasoning
  // about parity arithmetic — the arithmetic version of this test was wrong
  // while the engine was right, which is the least useful way round.
  let dc = G.create(777, { daily: false })
  const tag = []
  for (let r = 0; r < G.boardRows(); r++) {
    const row = []
    for (let cc = 0; cc < G.boardRowLen(r, dc.parity); cc++) {
      row.push(G.boardColors()[(r + cc) % G.boardColors().length])
    }
    dc.grid[r] = row
    tag.push(row.join(","))
  }
  const parityBefore = dc.parity
  G.dropCeiling(dc)
  ok(dc.parity !== parityBefore, "the ceiling drop must flip the board parity")
  for (let r = 0; r < G.boardRows() - 1; r++) {
    ok(dc.grid[r + 1].join(",") === tag[r],
       `row ${r} lost contents coming down: ${dc.grid[r + 1].length} cells, was ${tag[r].split(",").length}`)
    ok(dc.grid[r + 1].length === G.boardRowLen(r + 1, dc.parity),
       `row ${r + 1} is the wrong length for its new parity`)
  }
  ok(dc.grid[0].length === G.boardRowLen(0, dc.parity),
     "the new top row must be the right length for the new parity")

  // The aim guide must describe the path the shot actually takes.
  let a = G.create(4242, { daily: false })
  a.angle = G.AIM_MAX * 0.8
  const guide = G.aimPath(a, 200)
  ok(guide.length > 3, "the aim guide must produce a path")
  ok(guide.every(p => p.x >= G.bubbleR() - 0.01 && p.x <= G.boardWidth() - G.bubbleR() + 0.01),
     "the aim guide must stay inside the walls")
  const bounced = guide.some((p, i) => i > 1 && Math.abs(p.x - G.bubbleR()) < 0.01)
                || guide.some((p, i) => i > 1 && Math.abs(p.x - (G.boardWidth() - G.bubbleR())) < 0.01)
  ok(bounced, "a shot aimed hard at the wall must show a bounce in the guide")

  // Aim limits.
  let lim = G.create(4242, { daily: false })
  for (let i = 0; i < 400; i++) lim = G.step(lim, FRAME, true, false, false)
  ok(Math.abs(lim.angle - G.AIM_MIN) < 1e-6, `aiming left must stop at the limit, got ${lim.angle}`)
  for (let i = 0; i < 800; i++) lim = G.step(lim, FRAME, false, true, false)
  ok(Math.abs(lim.angle - G.AIM_MAX) < 1e-6, `aiming right must stop at the limit, got ${lim.angle}`)

  return fails
}

// ------------------------------------------------------------- difficulty
// The ramp is the whole point: DROP_EVERY used to be fixed for a whole run, so
// a player who survived the first minute had solved the game. These check that
// the curve exists, that it bottoms out rather than becoming a brick wall, and
// that harder is measurably harder — not merely differently configured.
function checkDifficulty() {
  const out = []
  const names = G.difficultyNames()
  if (names.join(",") !== "easy,normal,hard") out.push(`difficultyNames() is ${names}`)

  // An unknown or missing name must land on normal rather than throw: it comes
  // off a stored setting a newer build might have written.
  for (const bogus of ["", "IMPOSSIBLE", null, undefined]) {
    const st = G.create(1, { difficulty: bogus })
    if (st.difficulty !== "normal") out.push(`difficulty ${JSON.stringify(bogus)} became ${st.difficulty}`)
  }

  // The interval must actually tighten with shots fired, and must stop at the
  // floor. Without a floor the ramp eventually drops the ceiling every shot,
  // which leaves no room to build a cluster at all.
  for (const name of names) {
    const st = G.create(1, { difficulty: name })
    const at = (n) => G.dropIntervalFor(Object.assign({}, st, { shots: n }))
    if (at(0) !== st.dropEvery) out.push(`${name}: first interval is ${at(0)}, not ${st.dropEvery}`)
    if (at(st.dropRamp) !== st.dropEvery - 1) out.push(`${name}: interval did not tighten after ${st.dropRamp} shots`)
    if (at(100000) !== st.dropFloor) out.push(`${name}: interval bottoms out at ${at(100000)}, not ${st.dropFloor}`)
    for (let n = 0; n < 400; n++) {
      if (at(n) < st.dropFloor) { out.push(`${name}: interval fell below the floor at ${n} shots`); break }
      if (n && at(n) > at(n - 1)) { out.push(`${name}: interval got looser at ${n} shots`); break }
    }
  }

  // The curve has to survive snapshot(): step() runs off the object snapshot()
  // returns, so a field left out makes the second shot of every game compute
  // its cadence from undefined.
  for (const name of names) {
    const snap = G.snapshot(G.create(1, { difficulty: name }))
    for (const k of ["difficulty", "dropEvery", "dropFloor", "dropRamp"]) {
      if (snap[k] === undefined) out.push(`${name}: snapshot() drops ${k}`)
    }
  }

  // And the end of it: harder must mean shorter games and more descents, over
  // enough games that one lucky board cannot carry the result.
  const N = 120
  const runs = {}
  for (const name of names) {
    let shots = 0, descends = 0
    for (let g = 0; g < N; g++) {
      const { stats } = playGame(g * 7919 + 13, { difficulty: name })
      shots += stats.shots
      descends += stats.descends
    }
    runs[name] = { shots: shots / N, descends: descends / N }
  }
  if (!(runs.easy.shots > runs.normal.shots && runs.normal.shots > runs.hard.shots))
    out.push(`games do not shorten with difficulty: ${names.map(n => n + " " + runs[n].shots.toFixed(1)).join(", ")}`)
  if (!(runs.easy.descends < runs.normal.descends && runs.normal.descends < runs.hard.descends))
    out.push(`the ceiling does not come down more often: ${names.map(n => n + " " + runs[n].descends.toFixed(1)).join(", ")}`)

  // The board itself must not change with difficulty, or the daily puzzle stops
  // being the same puzzle and comparing scores on it means nothing.
  const board = (name) => JSON.stringify(G.create(20260904, { daily: true, difficulty: name }).grid)
  if (board("easy") !== board("hard") || board("easy") !== board("normal"))
    out.push("difficulty changed the board — the daily puzzle must be identical on all three")

  return out
}
