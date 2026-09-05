.pragma library

// Neon Bubble Pop — the whole simulation, with no Qt types in it, so the same
// code runs under node in tools/sim.mjs. A bubble shooter's bugs are the kind
// that are invisible in any one frame and obvious in aggregate: a cluster left
// hanging off nothing, a colour dealt that cannot be matched, a shot that
// reflects off a wall at the wrong angle.

// ---------------------------------------------------------------- geometry

// A staggered hex grid. Even rows hold COLS bubbles flush to the left wall,
// odd rows hold COLS-1 offset by half a bubble, which is what makes the
// packing hexagonal rather than square.
var COLS = 8
var BUBBLE_R = 16.5
var W = COLS * BUBBLE_R * 2          // 264
var H = 480
var ROW_H = BUBBLE_R * Math.sqrt(3)  // centres of adjacent rows

var ROWS = 16                        // as many as the board can ever hold
var DEATH_Y = 372                    // a bubble centred below this ends it
var SHOOTER_Y = 432
var SHOOTER_X = W / 2

var SHOT_SPEED = 13
var AIM_MIN = deg(-78)               // straight up is 0; limits stop you
var AIM_MAX = deg(78)                // shooting into your own gun
var AIM_RATE = deg(2.6)              // per frame-unit held

var DROP_EVERY = 6                   // shots between the ceiling coming down
var START_ROWS = 5

// The ceiling used to come down every DROP_EVERY shots for the whole run, which
// meant the game never got harder — a player who survived the first minute had
// solved it, and the rest was arithmetic. The cadence now tightens one shot
// every DROP_RAMP shots fired, down to a DROP_FLOOR it never passes, so a long
// run keeps taking something away.
//
// The floor is what stops the ramp becoming a brick wall: below it there is no
// room left to build a cluster before the ceiling moves again. Three is
// normal's. Hard deliberately goes to two, which is about as tight as the board
// stays playable — measured with tools/sim.mjs, where hard still averages 15
// shots a game against normal's 20 rather than collapsing.
var DROP_FLOOR = 3
var DROP_RAMP = 10

// Difficulty is the shape of that curve, and nothing else. It deliberately does
// not touch the board seed or the colours dealt: the daily board has to stay the
// same board for everybody, or comparing scores on it stops meaning anything.
// What changes is how fast the ceiling takes the room away.
var DIFFICULTIES = {
  easy:   { dropEvery: 8, dropFloor: 5, dropRamp: 16 },
  normal: { dropEvery: DROP_EVERY, dropFloor: DROP_FLOOR, dropRamp: DROP_RAMP },
  hard:   { dropEvery: 4, dropFloor: 2, dropRamp: 7 }
}
var DEFAULT_DIFFICULTY = "normal"

function difficultyOf(name) {
  return DIFFICULTIES[name] ? name : DEFAULT_DIFFICULTY
}

// Easiest first, so a caller cycling through them walks the curve in order
// rather than in whatever order the object happens to enumerate.
function difficultyNames() {
  return ["easy", "normal", "hard"]
}

// The interval the ceiling is currently on. Derived from shots fired rather
// than stored as a countdown of its own, so it cannot drift out of step with
// the run and a snapshot carries no extra state to get wrong.
function dropIntervalFor(state) {
  var notches = Math.floor(state.shots / state.dropRamp)
  return Math.max(state.dropFloor, state.dropEvery - notches)
}

var POP_MIN = 3                      // bubbles of a colour that must touch
var POP_SCORE = 60
var DROP_SCORE = 110                 // per bubble detached, worth more
var CLEAR_BONUS = 4000

var COLORS = ["pink", "cyan", "gold", "violet", "lime"]

// Specials are earned, not dealt at random: every CHARGE_NEED bubbles you take
// off the board loads one into the gun. That makes a big clear worth building
// toward rather than a lucky draw, and it keeps the daily board fair — the
// charge comes from what you actually cleared, so the same play earns the same
// specials for everybody.
var CHARGE_NEED = 11
var BOMB_SCORE = 90
var WILD = "wild"
var BOMB = "bomb"

// Stars ride down with the ceiling. They are worth having and they are at the
// top, which is the one place the board otherwise gives you no reason to shoot.
var STAR_CHANCE = 0.55           // per descent, at most one star
var STAR_SCORE = 900
// Two on the starting board as well. Arriving only with the ceiling, a star
// spends its life in the top rows, which are the last thing anybody clears:
// across 300 games 495 of them came down and exactly one was ever collected.
// Seeding a couple into the opening board is what makes the mechanic something
// the player meets in the first minute rather than in theory.
var START_STARS = 2

// Sparks, and the two short-lived numbers the renderer reads to shake and
// flash. Capped, because a long chain spawns from every popped cell at once
// and an uncapped burst quietly becomes thousands of objects.
var PARTICLE_CAP = 90
var SPARKS_PER_POP = 7
var SPARKS_PER_DROP = 4
var SHAKE_MS = 260
var FLASH_MS = 220

function deg(d) { return d * Math.PI / 180 }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// Row length and alignment depend on the row's parity, and the board carries a
// parity of its own. That is what makes the ceiling able to come down by a
// single row: shifting every row down one flips each one's index parity, which
// would turn a row of eight into a row of seven and lose a bubble — so the
// board's parity flips at the same time and the two cancel. Every row keeps
// its length and its contents, and the whole wall steps half a bubble sideways,
// which is exactly what the real machine does.
function rowLen(r, parity) { return ((r + (parity || 0)) % 2 === 0) ? COLS : COLS - 1 }
function rowOffset(r, parity) { return ((r + (parity || 0)) % 2 === 0) ? 0 : BUBBLE_R }

function cellX(r, c, parity) { return rowOffset(r, parity) + BUBBLE_R + c * BUBBLE_R * 2 }
function cellY(r) { return BUBBLE_R + r * ROW_H }

// The six neighbours of a hex cell. The horizontal pair is the same on every
// row; the four diagonals shift by one column depending on whether the row is
// offset, which is the one place a staggered grid is easy to get wrong.
function neighbors(r, c, parity) {
  var odd = ((r + (parity || 0)) % 2 !== 0)
  var d = odd ? 0 : -1
  return [
    { r: r, c: c - 1 }, { r: r, c: c + 1 },
    { r: r - 1, c: c + d }, { r: r - 1, c: c + d + 1 },
    { r: r + 1, c: c + d }, { r: r + 1, c: c + d + 1 }
  ]
}

function inGrid(r, c, parity) {
  return r >= 0 && r < ROWS && c >= 0 && c < rowLen(r, parity)
}

function cellAt(grid, r, c, parity) {
  if (!inGrid(r, c, parity)) return null
  return grid[r][c]
}

// Deterministic from the same seed as the board, so the daily puzzle places
// its stars in the same cells for everyone.
function buildStars(seed, rows, parity) {
  var g = emptyStars(parity)
  var rnd = mulberry32((seed ^ 0x9e3779b9) | 0)
  var n = Math.max(1, Math.min(rows || START_ROWS, ROWS - 4))
  var placed = 0
  for (var attempt = 0; attempt < 60 && placed < START_STARS; attempt++) {
    // The lower half of the opening board: high enough to be worth a shot,
    // low enough to be reachable before the game is over.
    var r = Math.floor(n / 2) + Math.floor(rnd() * Math.ceil(n / 2))
    if (r >= n) continue
    var c = Math.floor(rnd() * rowLen(r, parity))
    if (g[r][c]) continue
    g[r][c] = true
    placed++
  }
  return g
}

function emptyStars(parity) {
  var g = []
  for (var r = 0; r < ROWS; r++) {
    var row = []
    for (var c = 0; c < rowLen(r, parity); c++) row.push(false)
    g.push(row)
  }
  return g
}

function starAt(state, r, c) {
  if (!state.stars || !inGrid(r, c, state.parity)) return false
  return !!state.stars[r][c]
}

function emptyGrid(parity) {
  var g = []
  for (var r = 0; r < ROWS; r++) {
    var row = []
    for (var c = 0; c < rowLen(r, parity); c++) row.push(null)
    g.push(row)
  }
  return g
}

// ---------------------------------------------------------------- random

// Deterministic, so a date always produces the same board and a seeded run in
// the harness repeats exactly.
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0
    var t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// The daily board. Every player gets the same puzzle on the same day, which is
// the point of opening this thing more than once — and it is a plain function
// of the date, so the harness can check two dates differ and one repeats.
function seedForDate(y, m, d) {
  return (y * 10000 + m * 100 + d) | 0
}

function todaySeed(now) {
  var t = now ? new Date(now) : new Date()
  return seedForDate(t.getFullYear(), t.getMonth() + 1, t.getDate())
}

// ---------------------------------------------------------------- board

function buildBoard(seed, rows, parity) {
  var rnd = mulberry32(seed)
  var g = emptyGrid(parity)
  var n = Math.max(1, Math.min(rows || START_ROWS, ROWS - 4))
  // Four colours to start rather than five: a board dealt from the full set is
  // noticeably harder to open, and the fifth arrives as the board grows.
  var palette = COLORS.slice(0, 4)
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < rowLen(r, parity); c++) {
      g[r][c] = palette[Math.floor(rnd() * palette.length) % palette.length]
    }
  }
  return g
}

function gridColors(grid, parity) {
  // A null prototype and an allowlist, because the key is a colour name and a
  // plain object answers for everything on Object.prototype.
  var seen = Object.create(null)
  var out = []
  for (var r = 0; r < ROWS; r++) {
    for (var c = 0; c < rowLen(r, parity); c++) {
      var v = grid[r][c]
      if (v && COLORS.indexOf(v) >= 0 && !seen[v]) { seen[v] = true; out.push(v) }
    }
  }
  return out
}

function countBubbles(grid, parity) {
  var n = 0
  for (var r = 0; r < ROWS; r++)
    for (var c = 0; c < rowLen(r, parity); c++) if (grid[r][c]) n++
  return n
}

// Same colour, touching, reachable from the cell played.
function findCluster(grid, r0, c0, parity) {
  var color = cellAt(grid, r0, c0, parity)
  if (!color) return []
  var seen = Object.create(null)
  var stack = [{ r: r0, c: c0 }]
  var out = []
  seen[r0 + ":" + c0] = true
  while (stack.length) {
    var cur = stack.pop()
    out.push(cur)
    var ns = neighbors(cur.r, cur.c, parity)
    for (var i = 0; i < ns.length; i++) {
      var n = ns[i]
      var k = n.r + ":" + n.c
      if (seen[k]) continue
      if (cellAt(grid, n.r, n.c, parity) !== color) continue
      seen[k] = true
      stack.push(n)
    }
  }
  return out
}

// Anything not reachable from the top row is hanging off nothing and falls.
// Getting this wrong leaves bubbles floating in mid-air, which is the single
// most obvious way a bubble shooter looks broken.
function findFloating(grid, parity) {
  var anchored = Object.create(null)
  var stack = []
  for (var c = 0; c < rowLen(0, parity); c++) {
    if (grid[0][c]) { anchored["0:" + c] = true; stack.push({ r: 0, c: c }) }
  }
  while (stack.length) {
    var cur = stack.pop()
    var ns = neighbors(cur.r, cur.c, parity)
    for (var i = 0; i < ns.length; i++) {
      var n = ns[i]
      var k = n.r + ":" + n.c
      if (anchored[k]) continue
      if (!cellAt(grid, n.r, n.c, parity)) continue
      anchored[k] = true
      stack.push(n)
    }
  }
  var out = []
  for (var r = 0; r < ROWS; r++)
    for (var cc = 0; cc < rowLen(r, parity); cc++)
      if (grid[r][cc] && !anchored[r + ":" + cc]) out.push({ r: r, c: cc })
  return out
}

function lowestFilledY(grid, parity) {
  var y = 0
  for (var r = 0; r < ROWS; r++)
    for (var c = 0; c < rowLen(r, parity); c++)
      if (grid[r][c]) y = Math.max(y, cellY(r))
  return y
}

// ---------------------------------------------------------------- the shot

// Where a bubble arriving at (x, y) belongs: the nearest empty cell that is
// actually attached to something. Searching every cell rather than converting
// the coordinate back to a row and column, because the arithmetic inverse gets
// the answer wrong exactly at the seams between rows, which is where a shot
// fired up a narrow gap always lands.
function snapCell(grid, parity, x, y) {
  var best = null
  var bestD = Infinity
  for (var r = 0; r < ROWS; r++) {
    var len = rowLen(r, parity)
    for (var c = 0; c < len; c++) {
      if (grid[r][c]) continue
      var supported = (r === 0)
      if (!supported) {
        var ns = neighbors(r, c, parity)
        for (var i = 0; i < ns.length; i++) {
          if (cellAt(grid, ns[i].r, ns[i].c, parity)) { supported = true; break }
        }
      }
      if (!supported) continue
      var dx = x - cellX(r, c, parity)
      var dy = y - cellY(r)
      var d = dx * dx + dy * dy
      if (d < bestD) { bestD = d; best = { r: r, c: c } }
    }
  }
  return best
}

// Deal a colour that is still on the board. Dealing one that is not is the
// classic bubble-shooter insult: a bubble you cannot possibly match, wasting a
// shot and pushing the ceiling down for nothing.
function dealColor(state) {
  var live = gridColors(state.grid, state.parity)
  if (live.length === 0) live = COLORS.slice(0, 4)
  return live[Math.floor(state.rnd() * live.length) % live.length]
}

function create(seed, opts) {
  var o = opts || {}
  var s = Math.abs((seed === undefined || seed === null || !isFinite(seed))
    ? todaySeed() : (parseInt(seed, 10) | 0))
  var parity = 0
  // An unknown name falls back to normal rather than throwing: this comes off a
  // stored preference, and a file written by a newer build should degrade to a
  // playable game instead of a broken one.
  var diff = difficultyOf(o.difficulty)
  var curve = DIFFICULTIES[diff]
  var state = {
    seed: s,
    daily: o.daily !== false,
    difficulty: diff,
    dropEvery: curve.dropEvery,
    dropFloor: curve.dropFloor,
    dropRamp: curve.dropRamp,
    parity: parity,
    grid: buildBoard(s, o.rows || START_ROWS, parity),
    stars: buildStars(s, o.rows || START_ROWS, parity),
    rnd: mulberry32(s ^ 0x5bf03635),
    phase: "aim",
    score: 0,
    shots: 0,
    shotsToDrop: curve.dropEvery,
    angle: 0,
    flying: null,
    popping: [],
    falling: [],
    current: null,
    next: null,
    currentKind: "normal",
    nextKind: "normal",
    charge: 0,
    lastLanded: null,
    combo: 0,
    particles: [],
    rings: [],
    flashT: 0,
    shakeT: 0,
    shakeMag: 0,
    events: [],
    tick: 0
  }
  state.current = dealColor(state)
  state.next = dealColor(state)
  return snapshot(state)
}

// If the meter is full, the bubble going into the gun is a special and the
// meter resets. Which special is drawn from the game's own seeded generator, so
// a given board plays out the same way for everybody.
function takeSpecial(state) {
  if (state.charge < CHARGE_NEED) return "normal"
  state.charge -= CHARGE_NEED
  var kind = (state.rnd() < 0.5) ? BOMB : WILD
  state.events.push("charged")
  return kind
}

function fire(state) {
  if (state.phase !== "aim" || state.flying) return false

  // The next bubble is dealt when the previous one is fired, so the shot that
  // followed can have removed the last of its colour in the meantime. Re-deal
  // rather than fire a bubble that cannot match anything — it is rare, and it
  // is exactly the insult the deal is written to avoid.
  if (state.currentKind === "normal") {
    var live = gridColors(state.grid, state.parity)
    if (live.length && live.indexOf(state.current) < 0) state.current = dealColor(state)
  }

  var a = state.angle - Math.PI / 2          // 0 aims straight up
  state.flying = {
    x: SHOOTER_X, y: SHOOTER_Y,
    vx: Math.cos(a) * SHOT_SPEED,
    vy: Math.sin(a) * SHOT_SPEED,
    color: state.current,
    kind: state.currentKind
  }
  state.currentKind = state.nextKind
  state.current = state.next
  state.nextKind = takeSpecial(state)
  state.next = dealColor(state)
  state.phase = "fly"
  state.events.push("fire")
  return true
}

function spawnSparks(state, x, y, color, n) {
  var room = PARTICLE_CAP - state.particles.length
  if (room <= 0) return
  if (n > room) n = room
  for (var i = 0; i < n; i++) {
    var a = (i / n) * Math.PI * 2 + state.tick * 0.37
    var sp = 1.3 + (i % 3) * 0.85
    state.particles.push({
      x: x, y: y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 0.5,
      color: color, life: 1
    })
  }
}

function updateEffects(state, dt, dtMs) {
  if (state.flashT > 0) state.flashT = Math.max(0, state.flashT - dtMs)
  if (state.shakeT > 0) state.shakeT = Math.max(0, state.shakeT - dtMs)
  var out = []
  for (var i = 0; i < state.particles.length; i++) {
    var p = state.particles[i]
    p.life -= dtMs / 560
    if (p.life <= 0) continue
    p.x += p.vx * dt
    p.y += p.vy * dt
    p.vy += 0.19 * dt
    p.vx *= 0.982
    out.push(p)
  }
  state.particles = out
  var rings = []
  for (var r = 0; r < state.rings.length; r++) {
    var g = state.rings[r]
    g.life -= dtMs / 420
    if (g.life > 0) rings.push(g)
  }
  state.rings = rings
}

// Everything that happens once a bubble comes to rest: the cluster it joined,
// then whatever that cluster was holding up.
// Clearing a set of cells: the sparks, the star bonus and the grid itself.
// Everything that removes bubbles goes through here so none of those can be
// forgotten by one caller and not another.
function clearCells(state, cells, color) {
  var stars = 0
  for (var i = 0; i < cells.length; i++) {
    var cc = cells[i]
    var col = color || state.grid[cc.r][cc.c]
    spawnSparks(state, cellX(cc.r, cc.c, state.parity), cellY(cc.r), col, SPARKS_PER_POP)
    if (starAt(state, cc.r, cc.c)) {
      stars++
      state.stars[cc.r][cc.c] = false
      state.rings.push({ x: cellX(cc.r, cc.c, state.parity), y: cellY(cc.r),
                         color: "gold", life: 1 })
    }
    state.grid[cc.r][cc.c] = null
  }
  if (stars > 0) {
    state.score += stars * STAR_SCORE
    state.events.push("star")
  }
  return cells.length
}

function land(state, cell, color, kind) {
  // A wildcard takes the colour of whatever it is touching most of. With
  // nothing to touch it becomes a colour still on the board, so it can never
  // be a bubble that cannot match.
  if (kind === WILD) {
    // The colour that makes the biggest cluster, not the one it happens to
    // touch most or first. Counting neighbours is the obvious rule and it is
    // the wrong one: a wildcard beside one bubble of a colour that is part of
    // a run of six should join the six, and on a tie the obvious rule picks
    // whichever the neighbour list reached first, which is arbitrary.
    var ns = neighbors(cell.r, cell.c, state.parity)
    var tried = Object.create(null)
    var bestC = null, bestN = 0
    for (var t = 0; t < ns.length; t++) {
      var nv = cellAt(state.grid, ns[t].r, ns[t].c, state.parity)
      if (!nv || COLORS.indexOf(nv) < 0 || tried[nv]) continue
      tried[nv] = true
      state.grid[cell.r][cell.c] = nv
      var size = findCluster(state.grid, cell.r, cell.c, state.parity).length
      if (size > bestN) { bestN = size; bestC = nv }
    }
    state.grid[cell.r][cell.c] = null
    color = bestC || dealColor(state)
    state.events.push("wild")
  }

  state.grid[cell.r][cell.c] = color
  state.lastLanded = { r: cell.r, c: cell.c }

  // A bomb takes out everything it touches, whatever colour it is.
  if (kind === BOMB) {
    var blast = [{ r: cell.r, c: cell.c }]
    var bn = neighbors(cell.r, cell.c, state.parity)
    for (var b = 0; b < bn.length; b++) {
      if (cellAt(state.grid, bn[b].r, bn[b].c, state.parity)) blast.push(bn[b])
    }
    state.combo++
    state.score += clearCells(state, blast, color) * BOMB_SCORE * state.combo
    state.charge += blast.length
    state.popping = blast.slice(0)
    state.flashT = FLASH_MS
    state.shakeT = SHAKE_MS
    state.shakeMag = 0.7
    state.events.push("bomb")
    state.events.push("pop")
    detachFloaters(state)
    return
  }

  var cluster = findCluster(state.grid, cell.r, cell.c, state.parity)
  if (cluster.length < POP_MIN) {
    state.combo = 0
    state.events.push("stick")
    return
  }

  var i
  clearCells(state, cluster, color)
  state.rings.push({
    x: cellX(cell.r, cell.c, state.parity), y: cellY(cell.r),
    color: color, life: 1
  })
  state.combo++
  state.score += cluster.length * POP_SCORE * state.combo
  state.charge += cluster.length
  state.popping = cluster.slice(0)
  state.flashT = FLASH_MS
  state.events.push("pop")
  detachFloaters(state)
}

// Whatever the clear was holding up now falls.
function detachFloaters(state) {
  var loose = findFloating(state.grid, state.parity)
  if (!loose.length) return
  for (var i = 0; i < loose.length; i++) {
    var f = loose[i]
    var fc = state.grid[f.r][f.c]
    spawnSparks(state, cellX(f.r, f.c, state.parity), cellY(f.r), fc, SPARKS_PER_DROP)
    state.falling.push({
      x: cellX(f.r, f.c, state.parity), y: cellY(f.r),
      vy: 1.4 + (i % 3) * 0.5, color: fc, life: 1
    })
    if (starAt(state, f.r, f.c)) {
      state.score += STAR_SCORE
      state.stars[f.r][f.c] = false
      state.events.push("star")
    }
    state.grid[f.r][f.c] = null
  }
  state.score += loose.length * DROP_SCORE * state.combo
  state.charge += loose.length
  state.events.push("drop")
}

// The ceiling comes down. Parity flips with the shift so every row keeps its
// length and its alignment; see the note on rowLen.
function dropCeiling(state) {
  state.parity = state.parity ? 0 : 1
  state.grid.pop()
  state.stars.pop()
  var row = []
  var starRow = []
  var len = rowLen(0, state.parity)
  for (var c = 0; c < len; c++) {
    row.push(COLORS[Math.floor(state.rnd() * COLORS.length) % COLORS.length])
    starRow.push(false)
  }
  // At most one star per descent, so it stays worth going after.
  if (state.rnd() < STAR_CHANCE) {
    starRow[Math.floor(state.rnd() * len) % len] = true
    state.events.push("star_in")
  }
  state.grid.unshift(row)
  state.stars.unshift(starRow)
  state.shotsToDrop = dropIntervalFor(state)
  // The ceiling coming down is the pressure in this game, so it is the one
  // thing that moves the whole board.
  state.shakeT = SHAKE_MS
  state.shakeMag = 1
  state.events.push("descend")
}

function checkLost(state) {
  if (lowestFilledY(state.grid, state.parity) >= DEATH_Y) {
    state.phase = "gameover"
    state.events.push("gameover")
    return true
  }
  return false
}

function checkCleared(state) {
  if (countBubbles(state.grid, state.parity) > 0) return false
  state.score += CLEAR_BONUS
  state.phase = "gameover"
  state.events.push("cleared")
  state.events.push("gameover")
  return true
}

function step(state, dtMs, aimLeft, aimRight, wantFire) {
  if (!state) return state
  state.events = []
  var dt = clamp(dtMs / 16.667, 0.25, 2.5)
  updateEffects(state, dt, dtMs)

  var i
  for (i = state.falling.length - 1; i >= 0; i--) {
    var fb = state.falling[i]
    fb.vy += 0.55 * dt
    fb.y += fb.vy * dt
    if (fb.y > H + 40) state.falling.splice(i, 1)
  }
  if (state.popping.length && !state.flying) state.popping = []

  if (state.phase === "gameover") return snapshot(state)

  if (state.phase === "aim") {
    if (aimLeft) state.angle = clamp(state.angle - AIM_RATE * dt, AIM_MIN, AIM_MAX)
    if (aimRight) state.angle = clamp(state.angle + AIM_RATE * dt, AIM_MIN, AIM_MAX)
    if (wantFire) fire(state)
    return snapshot(state)
  }

  if (state.phase === "fly" && state.flying) {
    // Substepped for the same reason the pinball flippers are: one frame of
    // travel is most of a bubble diameter, and a bubble that passes through the
    // gap between two others lands somewhere impossible.
    var sub = 4
    var sd = dt / sub
    for (var si = 0; si < sub && state.flying; si++) {
      var b = state.flying
      b.x += b.vx * sd
      b.y += b.vy * sd

      if (b.x < BUBBLE_R) { b.x = BUBBLE_R; b.vx = Math.abs(b.vx); state.events.push("wall") }
      if (b.x > W - BUBBLE_R) { b.x = W - BUBBLE_R; b.vx = -Math.abs(b.vx); state.events.push("wall") }

      var hit = (b.y <= BUBBLE_R)
      if (!hit) {
        for (var r = 0; r < ROWS && !hit; r++) {
          var len = rowLen(r, state.parity)
          for (var c = 0; c < len; c++) {
            if (!state.grid[r][c]) continue
            var dx = b.x - cellX(r, c, state.parity)
            var dy = b.y - cellY(r)
            if (dx * dx + dy * dy < (BUBBLE_R * 2) * (BUBBLE_R * 2) * 0.92) { hit = true; break }
          }
        }
      }
      if (!hit && b.y > H) { state.flying = null; state.phase = "aim"; break }
      if (!hit) continue

      var cell = snapCell(state.grid, state.parity, b.x, b.y)
      var color = b.color
      var kind = b.kind
      state.flying = null
      state.phase = "aim"
      if (!cell) break
      land(state, cell, color, kind)
      state.shots++
      state.shotsToDrop--
      if (checkCleared(state)) break
      if (state.shotsToDrop <= 0) dropCeiling(state)
      checkLost(state)
      break
    }
  }

  return snapshot(state)
}

function snapshot(state) {
  var grid = []
  for (var r = 0; r < ROWS; r++) grid.push(state.grid[r].slice(0))
  return {
    seed: state.seed,
    daily: state.daily,
    // The curve rides in the snapshot because step() runs off the object
    // snapshot() returns. Leave these out and the second shot of every game
    // computes its cadence from undefined.
    difficulty: state.difficulty,
    dropEvery: state.dropEvery,
    dropFloor: state.dropFloor,
    dropRamp: state.dropRamp,
    parity: state.parity,
    grid: grid,
    rnd: state.rnd,
    phase: state.phase,
    score: state.score,
    shots: state.shots,
    shotsToDrop: state.shotsToDrop,
    angle: state.angle,
    flying: state.flying
      ? { x: state.flying.x, y: state.flying.y, vx: state.flying.vx,
          vy: state.flying.vy, color: state.flying.color, kind: state.flying.kind }
      : null,
    popping: state.popping.slice(0),
    falling: state.falling.map(function (f) {
      return { x: f.x, y: f.y, vy: f.vy, color: f.color, life: f.life }
    }),
    stars: state.stars.map(function (row) { return row.slice(0) }),
    current: state.current,
    next: state.next,
    currentKind: state.currentKind,
    nextKind: state.nextKind,
    charge: state.charge,
    lastLanded: state.lastLanded,
    combo: state.combo,
    particles: state.particles.map(function (p) {
      return { x: p.x, y: p.y, color: p.color, life: p.life }
    }),
    rings: state.rings.map(function (g) {
      return { x: g.x, y: g.y, color: g.color, life: g.life }
    }),
    flashT: state.flashT,
    shakeT: state.shakeT,
    shakeMag: state.shakeMag,
    events: state.events.slice(0),
    tick: (state.tick || 0) + 1
  }
}

// --------------------------------------------------------- for the renderer
function boardWidth() { return W }
function boardHeight() { return H }
function bubbleR() { return BUBBLE_R }
function boardRows() { return ROWS }
function boardRowLen(r, parity) { return rowLen(r, parity) }
function boardCellX(r, c, parity) { return cellX(r, c, parity) }
function boardCellY(r) { return cellY(r) }
function boardColors() { return COLORS.slice(0) }
function boardDeathY() { return DEATH_Y }
function shooterX() { return SHOOTER_X }
function shooterY() { return SHOOTER_Y }
function boardSeedForDate(y, m, d) { return seedForDate(y, m, d) }

// A decaying oscillation rather than a single offset: a cabinet you shove
// rocks back. Same shape the pinball table uses, for the same reason.
function boardShake(state) {
  if (!state || !state.shakeT) return 0
  var t = state.shakeT / SHAKE_MS
  return Math.sin(t * Math.PI * 3.5) * t * 4.5 * (state.shakeMag || 1)
}

function boardFlash(state) {
  if (!state || !state.flashT) return 0
  return clamp(state.flashT / FLASH_MS, 0, 1)
}

// How close the board is to the line, 0 to 1. The renderer uses it to make the
// warning louder as it gets worse rather than only at the moment it is lost.
function boardCharge(state) {
  if (!state) return 0
  return clamp((state.charge || 0) / CHARGE_NEED, 0, 1)
}

function boardStarAt(state, r, c) { return starAt(state, r, c) }

function boardPressure(state) {
  if (!state) return 0
  var low = lowestFilledY(state.grid, state.parity)
  var from = DEATH_Y - ROW_H * 4
  return clamp((low - from) / (DEATH_Y - from), 0, 1)
}
function boardTodaySeed(now) { return todaySeed(now) }

// The dotted line the player is aiming along, reflected off the side walls the
// same way the shot will be. Drawn from the same numbers the shot uses, so the
// guide cannot promise a path the bubble does not take.
function aimPath(state, maxLen) {
  var pts = []
  if (!state || state.phase !== "aim") return pts
  var a = state.angle - Math.PI / 2
  var x = SHOOTER_X, y = SHOOTER_Y
  var vx = Math.cos(a), vy = Math.sin(a)
  var stepLen = 6
  var limit = maxLen || 90
  pts.push({ x: x, y: y })
  for (var i = 0; i < limit; i++) {
    x += vx * stepLen
    y += vy * stepLen
    if (x < BUBBLE_R) { x = BUBBLE_R; vx = Math.abs(vx) }
    if (x > W - BUBBLE_R) { x = W - BUBBLE_R; vx = -Math.abs(vx) }
    if (y <= BUBBLE_R) { pts.push({ x: x, y: y }); break }
    var blocked = false
    for (var r = 0; r < ROWS && !blocked; r++) {
      var len = rowLen(r, state.parity)
      for (var c = 0; c < len; c++) {
        if (!state.grid[r][c]) continue
        var dx = x - cellX(r, c, state.parity)
        var dy = y - cellY(r)
        if (dx * dx + dy * dy < (BUBBLE_R * 2) * (BUBBLE_R * 2) * 0.92) { blocked = true; break }
      }
    }
    pts.push({ x: x, y: y })
    if (blocked) break
  }
  return pts
}

// The frozen scenes the listing card is shot from. Each composes a state and
// returns a snapshot of it, the same shape step() returns.
function previewState(scene) {
  var s
  if (scene === "play") {
    s = create(seedForDate(2026, 9, 4), { daily: true })
    s.score = 7400
    s.shots = 11
    s.shotsToDrop = 3
    s.angle = deg(-22)
    s.flying = { x: 96, y: 250, vx: -3, vy: -12, color: s.current }
    s.phase = "fly"
    return snapshot(s)
  }
  if (scene === "chain") {
    s = create(seedForDate(2026, 9, 11), { daily: true })
    s.score = 19850
    s.shots = 24
    s.shotsToDrop = 2
    s.combo = 3
    s.angle = deg(14)
    // Mid-chain: a cluster gone and the bubbles it was holding on their way
    // down. This is the moment the game is about, so it is the shot.
    var live = gridColors(s.grid, s.parity)
    s.falling = [
      { x: 60, y: 210, vy: 3.1, color: live[0], life: 1 },
      { x: 96, y: 236, vy: 2.4, color: live[1 % live.length], life: 1 },
      { x: 132, y: 198, vy: 3.8, color: live[2 % live.length], life: 1 },
      { x: 168, y: 252, vy: 2.0, color: live[0], life: 1 }
    ]
    for (var c = 2; c < 6 && c < rowLen(2, s.parity); c++) {
      spawnSparks(s, cellX(2, c, s.parity), cellY(2), live[0], SPARKS_PER_POP)
      s.grid[2][c] = null
    }
    s.rings.push({ x: cellX(2, 3, s.parity), y: cellY(2), color: live[0], life: 0.62 })
    // A star up top, a bomb in the gun and a wildcard queued behind it: the
    // three things that are not just a coloured circle.
    s.stars[1][4] = true
    s.currentKind = BOMB
    s.nextKind = WILD
    s.charge = CHARGE_NEED - 2
    s.flashT = FLASH_MS * 0.7
    // Mid-flight, so the sparks are spread rather than all at their origin.
    for (var f = 0; f < 14; f++) updateEffects(s, 1, 16.667)
    return snapshot(s)
  }
  if (scene === "gameover") {
    s = create(seedForDate(2026, 9, 4), { daily: true, rows: 11 })
    s.phase = "gameover"
    s.score = 41200
    s.shots = 38
    return snapshot(s)
  }
  return null
}
