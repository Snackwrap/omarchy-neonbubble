.pragma library

// Bests are kept per difficulty.
//
// The all-time number is the usual arcade one and the daily number is the point
// of a daily board, stamped with the day it belongs to so a stale file cannot
// claim today's high score. What changed is that a score is only comparable
// against another score played on the same curve — the ceiling comes down at a
// different rate on each setting — so each difficulty keeps its own pair rather
// than all three fighting over one number that would mean nothing.
var DIFFS = ["easy", "normal", "hard"]
var DEFAULT_DIFF = "normal"

function emptyTrack() {
  return { best: 0, last: 0, games: 0, dayKey: 0, dayBest: 0 }
}

function empty() {
  var s = { v: 2, tracks: {} }
  for (var i = 0; i < DIFFS.length; i++) s.tracks[DIFFS[i]] = emptyTrack()
  return s
}

// An unknown or absent name reads as normal, so a caller that does not know
// about difficulty at all — the QML panel passes none — still gets the one
// track it means, and a file written by a newer build cannot wedge an older one.
function diffName(difficulty) {
  for (var i = 0; i < DIFFS.length; i++) if (DIFFS[i] === difficulty) return DIFFS[i]
  return DEFAULT_DIFF
}

function track(stats, difficulty) {
  var name = diffName(difficulty)
  if (stats && stats.tracks && stats.tracks[name]) return stats.tracks[name]
  return emptyTrack()
}

function readTrack(d) {
  var t = emptyTrack()
  if (!d) return t
  t.best = parseInt(d.best, 10) || 0
  t.last = parseInt(d.last, 10) || 0
  t.games = parseInt(d.games, 10) || 0
  t.dayKey = parseInt(d.dayKey, 10) || 0
  t.dayBest = parseInt(d.dayBest, 10) || 0
  return t
}

function parse(raw) {
  var base = empty()
  if (!raw || String(raw).length === 0 || String(raw).length > 4096) return base
  try {
    var d = JSON.parse(String(raw))
    if (d && d.tracks) {
      for (var i = 0; i < DIFFS.length; i++) {
        base.tracks[DIFFS[i]] = readTrack(d.tracks[DIFFS[i]])
      }
      return base
    }
    // A payload from before difficulty existed: one flat set of numbers. They
    // land in normal, because every one of them was played on a fixed cadence
    // of six and that is where normal starts. Normal tightens now where the old
    // game did not, so an inherited best is a slightly easier best — but any
    // other track would misreport what was actually played, and throwing them
    // away would be worse than either.
    base.tracks[DEFAULT_DIFF] = readTrack(d)
  } catch (e) { /* keep defaults */ }
  return base
}

function serialize(stats) { return JSON.stringify(stats) }

function isValidPayload(raw) {
  if (typeof raw !== "string") return false
  if (raw.length === 0 || raw.length > 4096) return false
  try { JSON.parse(raw); return true } catch (e) { return false }
}

// dayKey is the same number the board is seeded from, so "today's best" and
// "today's board" can never disagree about which day it is.
function recordGame(stats, score, dayKey, difficulty) {
  var s = parse(serialize(stats))
  var t = s.tracks[diffName(difficulty)]
  var sc = parseInt(score, 10) || 0
  var key = parseInt(dayKey, 10) || 0
  t.last = sc
  t.games++
  if (sc > t.best) t.best = sc
  if (key !== t.dayKey) { t.dayKey = key; t.dayBest = 0 }
  if (sc > t.dayBest) t.dayBest = sc
  return s
}

function todayBest(stats, dayKey, difficulty) {
  var t = track(stats, difficulty)
  var key = parseInt(dayKey, 10) || 0
  if (t.dayKey !== key) return 0
  return t.dayBest || 0
}

function best(stats, difficulty) { return track(stats, difficulty).best || 0 }
function games(stats, difficulty) { return track(stats, difficulty).games || 0 }

// With no difficulty named, every track goes — that is what the QML panel's
// reset key has always meant and it keeps that call working unchanged. Name one
// and only that ladder is cleared, which is what per-difficulty bests need:
// wiping your hard board should not cost you easy.
function reset(stats, difficulty) {
  if (difficulty === undefined || difficulty === null) return empty()
  var s = parse(serialize(stats))
  s.tracks[diffName(difficulty)] = emptyTrack()
  return s
}

function sessionLine(stats, dayKey, difficulty) {
  return "TODAY " + todayBest(stats, dayKey, difficulty) +
         "  ·  BEST " + best(stats, difficulty)
}
