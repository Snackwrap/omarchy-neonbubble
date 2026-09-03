.pragma library

// Two bests. The all-time one is the usual arcade number; the daily one is the
// point of a daily board, and it is stamped with the day it belongs to so a
// stale file cannot claim today's high score.
function empty() {
  return { best: 0, last: 0, games: 0, dayKey: 0, dayBest: 0 }
}

function parse(raw) {
  var base = empty()
  if (!raw || String(raw).length === 0 || String(raw).length > 4096) return base
  try {
    var d = JSON.parse(String(raw))
    base.best = parseInt(d.best, 10) || 0
    base.last = parseInt(d.last, 10) || 0
    base.games = parseInt(d.games, 10) || 0
    base.dayKey = parseInt(d.dayKey, 10) || 0
    base.dayBest = parseInt(d.dayBest, 10) || 0
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
function recordGame(stats, score, dayKey) {
  var s = parse(serialize(stats))
  var sc = parseInt(score, 10) || 0
  var key = parseInt(dayKey, 10) || 0
  s.last = sc
  s.games++
  if (sc > s.best) s.best = sc
  if (key !== s.dayKey) { s.dayKey = key; s.dayBest = 0 }
  if (sc > s.dayBest) s.dayBest = sc
  return s
}

function todayBest(stats, dayKey) {
  var key = parseInt(dayKey, 10) || 0
  if (!stats || stats.dayKey !== key) return 0
  return stats.dayBest || 0
}

function reset(stats) { return empty() }

function sessionLine(stats, dayKey) {
  return "TODAY " + todayBest(stats, dayKey) + "  ·  BEST " + (stats ? stats.best : 0)
}
