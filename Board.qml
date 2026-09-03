import QtQuick
import qs.Commons
import "GameEngine.js" as Engine
import "Palette.js" as Palette

Item {
  id: root

  property var gameState: null
  property bool showAttract: false
  property bool showGameOver: false
  property string gameOverScore: ""
  property string gameOverSession: ""
  property bool gameOverNewBest: false

  readonly property real boardW: Engine.boardWidth()
  readonly property real boardH: Engine.boardHeight()

  // A strip reserved above the board for the score. It used to be drawn over
  // the top of the board, which put it on top of the bubbles — and the top
  // rows are exactly where the board is most crowded.
  readonly property real hudH: Style.space(17)

  readonly property real playW: width - Style.space(6)
  readonly property real sc: playW / boardW
  readonly property real originX: (width - boardW * sc) / 2
  readonly property real originY: hudH

  implicitWidth: Style.space(320)
  // Derived from the width it is actually given, not from the width it asked
  // for. Computing it from implicitWidth left a dead band under the board
  // whenever the panel handed it a different one.
  implicitHeight: hudH + (width - Style.space(6)) / boardW * boardH + Style.space(4)

  readonly property int tick: gameState ? (gameState.tick || 0) : 0
  readonly property real shake: { var _ = root.tick; return gameState ? Engine.boardShake(gameState) : 0 }
  readonly property real flash: { var _ = root.tick; return gameState ? Engine.boardFlash(gameState) : 0 }
  readonly property real pressure: { var _ = root.tick; return gameState ? Engine.boardPressure(gameState) : 0 }

  function px(x) { return originX + (x + root.shake) * sc }
  function py(y) { return originY + y * sc }
  function pr(r) { return r * sc }

  // One place decides what a colour looks like, so the board, the gun and the
  // falling bubbles can never disagree about it.
  function tint(name) {
    if (name === "pink") return Palette.neon
    if (name === "cyan") return Palette.cyan
    if (name === "gold") return Palette.gold
    if (name === "violet") return Palette.violet
    if (name === "lime") return Palette.lime
    return Palette.neonDim
  }

  function chan(hex, i) { return parseInt(hex.substr(1 + i * 2, 2), 16) }
  function rgba(hex, a) {
    return "rgba(" + chan(hex, 0) + "," + chan(hex, 1) + "," + chan(hex, 2) + "," + a + ")"
  }
  function mixHex(a, b, t) {
    function h(v) { var s = Math.round(v).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(chan(a, 0) + (chan(b, 0) - chan(a, 0)) * t)
               + h(chan(a, 1) + (chan(b, 1) - chan(a, 1)) * t)
               + h(chan(a, 2) + (chan(b, 2) - chan(a, 2)) * t)
  }

  Rectangle {
    anchors.fill: parent
    color: Palette.bg
    radius: Style.space(2)
  }

  Canvas {
    id: boardCanvas
    anchors.fill: parent
    property int frame: root.tick
    onFrameChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!root.gameState) return
      var s = root.gameState
      var R = Engine.bubbleR()
      var i, r, c

      var x0 = root.px(0), y0 = root.py(0)
      var x1 = root.px(root.boardW), y1 = root.py(root.boardH)
      var w = x1 - x0, h = y1 - y0

      // Floor: a deep violet that warms as the board fills, so the table
      // itself tells you how much trouble you are in.
      var floor = ctx.createLinearGradient(x0, y0, x0, y1)
      floor.addColorStop(0, root.mixHex("#150a20", "#2a0a24", root.pressure))
      floor.addColorStop(1, "#08050e")
      ctx.fillStyle = floor
      ctx.fillRect(x0, y0, w, h)

      // The cells a bubble can land in, as a faint dot grid. It is the
      // cyberpunk texture and it is also the most useful thing on the board:
      // it shows where a shot can actually come to rest.
      ctx.fillStyle = Palette.cyan
      ctx.globalAlpha = 0.09
      var rows = Engine.boardRows()
      for (r = 0; r < rows; r++) {
        if (Engine.boardCellY(r) > Engine.boardDeathY() + R) break
        var len = Engine.boardRowLen(r, s.parity)
        for (c = 0; c < len; c++) {
          if (s.grid[r][c]) continue
          ctx.beginPath()
          ctx.arc(root.px(Engine.boardCellX(r, c, s.parity)),
                  root.py(Engine.boardCellY(r)), Math.max(1, root.pr(1.6)), 0, Math.PI * 2)
          ctx.fill()
        }
      }
      ctx.globalAlpha = 1

      // Scanlines. Cheap, and the single strongest signal that a flat panel is
      // meant to be a screen.
      ctx.fillStyle = Palette.scanline
      ctx.globalAlpha = 0.045
      for (var sy = y0; sy < y1; sy += 3) ctx.fillRect(x0, sy, w, 1)
      ctx.globalAlpha = 1

      // A neon bubble is an emissive rim around a dark core, not a filled
      // disc. Flat fills read as plastic sweets; the glow, the gradient and
      // the bright ring are what make it look lit from the inside.
      function bubble(cx, cy, hex, alpha, scale) {
        var a = (alpha === undefined) ? 1 : alpha
        var rr = root.pr(R) * (scale === undefined ? 1 : scale)

        var glow = ctx.createRadialGradient(cx, cy, rr * 0.55, cx, cy, rr * 1.75)
        glow.addColorStop(0, root.rgba(hex, 0.42 * a))
        glow.addColorStop(1, root.rgba(hex, 0))
        ctx.fillStyle = glow
        ctx.beginPath()
        ctx.arc(cx, cy, rr * 1.75, 0, Math.PI * 2)
        ctx.fill()

        var body = ctx.createRadialGradient(cx - rr * 0.25, cy - rr * 0.3, rr * 0.1,
                                            cx, cy, rr * 0.92)
        body.addColorStop(0, root.rgba(root.mixHex(hex, "#ffffff", 0.55), a))
        body.addColorStop(0.5, root.rgba(hex, a * 0.92))
        body.addColorStop(1, root.rgba(root.mixHex(hex, "#12071c", 0.5), a))
        ctx.fillStyle = body
        ctx.beginPath()
        ctx.arc(cx, cy, rr * 0.92, 0, Math.PI * 2)
        ctx.fill()

        ctx.strokeStyle = root.rgba(root.mixHex(hex, "#ffffff", 0.35), a)
        ctx.lineWidth = Math.max(1.2, rr * 0.13)
        ctx.beginPath()
        ctx.arc(cx, cy, rr * 0.9, 0, Math.PI * 2)
        ctx.stroke()

        ctx.globalAlpha = a * 0.75
        ctx.fillStyle = "#ffffff"
        ctx.beginPath()
        ctx.ellipse(cx - rr * 0.34, cy - rr * 0.4, rr * 0.2, rr * 0.14, -0.6, 0, Math.PI * 2)
        ctx.fill()
        ctx.globalAlpha = 1
      }

      // The aim guide, from the same numbers the shot uses.
      if (s.phase === "aim") {
        var path = Engine.aimPath(s, 110)
        var gc = root.tint(s.current)
        ctx.strokeStyle = root.rgba(gc, 0.55)
        ctx.lineWidth = 2
        ctx.setLineDash([3, 8])
        ctx.lineDashOffset = -(root.tick % 11)
        ctx.beginPath()
        for (var pi = 0; pi < path.length; pi++) {
          var p = path[pi]
          if (pi === 0) ctx.moveTo(root.px(p.x), root.py(p.y))
          else ctx.lineTo(root.px(p.x), root.py(p.y))
        }
        ctx.stroke()
        ctx.setLineDash([])
        ctx.lineDashOffset = 0
        if (path.length > 1) {
          var end = path[path.length - 1]
          var beat = 0.85 + 0.12 * Math.sin(root.tick * 0.22)
          ctx.strokeStyle = root.rgba(gc, 0.85)
          ctx.lineWidth = 1.8
          ctx.beginPath()
          ctx.arc(root.px(end.x), root.py(end.y), root.pr(R * beat), 0, Math.PI * 2)
          ctx.stroke()
        }
      }

      // A slow diagonal wave across the wall. Three percent of a bubble is
      // nothing to look at directly and is the difference between a board that
      // is alive and a board that is a screenshot.
      var wave = root.tick * 0.055
      for (r = 0; r < rows; r++) {
        var len2 = Engine.boardRowLen(r, s.parity)
        for (c = 0; c < len2; c++) {
          var v = s.grid[r][c]
          if (!v) continue
          var puff = 1 + 0.035 * Math.sin(wave + r * 0.55 + c * 0.32)
          bubble(root.px(Engine.boardCellX(r, c, s.parity)),
                 root.py(Engine.boardCellY(r)), root.tint(v), 1, puff)
        }
      }

      // Falling clusters get a streak, so a screen full of them reads as
      // motion rather than as bubbles that have come unstuck from the grid.
      for (i = 0; i < s.falling.length; i++) {
        var fb = s.falling[i]
        var fx = root.px(fb.x), fy = root.py(fb.y)
        var tail = Math.min(root.pr(34), root.pr(fb.vy * 5))
        var streak = ctx.createLinearGradient(fx, fy - tail, fx, fy)
        streak.addColorStop(0, root.rgba(root.tint(fb.color), 0))
        streak.addColorStop(1, root.rgba(root.tint(fb.color), 0.4))
        ctx.fillStyle = streak
        ctx.fillRect(fx - root.pr(R) * 0.4, fy - tail, root.pr(R) * 0.8, tail)
        bubble(fx, fy, root.tint(fb.color), 0.85)
      }

      // The ring a pop leaves behind.
      for (i = 0; i < s.rings.length; i++) {
        var g = s.rings[i]
        var t = 1 - g.life
        ctx.strokeStyle = root.rgba(root.tint(g.color), g.life * 0.7)
        ctx.lineWidth = Math.max(1, root.pr(3) * g.life)
        ctx.beginPath()
        ctx.arc(root.px(g.x), root.py(g.y), root.pr(R * (0.8 + t * 3.4)), 0, Math.PI * 2)
        ctx.stroke()
      }

      for (i = 0; i < s.particles.length; i++) {
        var pt = s.particles[i]
        var psz = Math.max(2, root.pr(2.4 + pt.life * 3.2))
        var pa = Math.max(0, Math.min(1, pt.life))
        var pc = root.mixHex(root.tint(pt.color), "#ffffff", 0.5)
        ctx.globalAlpha = pa * 0.35
        ctx.fillStyle = pc
        ctx.fillRect(root.px(pt.x) - psz, root.py(pt.y) - psz, psz * 2, psz * 2)
        ctx.globalAlpha = pa
        ctx.fillRect(root.px(pt.x) - psz / 2, root.py(pt.y) - psz / 2, psz, psz)
      }
      ctx.globalAlpha = 1

      if (s.flying) bubble(root.px(s.flying.x), root.py(s.flying.y), root.tint(s.flying.color))

      // The line the board must not cross, drawn louder the closer it gets.
      var dy = root.py(Engine.boardDeathY())
      ctx.save()
      ctx.setLineDash([7, 7])
      ctx.strokeStyle = Palette.neon
      ctx.globalAlpha = 0.3 + root.pressure * 0.6
      ctx.lineWidth = 1.5 + root.pressure * 1.5
      ctx.beginPath()
      ctx.moveTo(x0 + 2, dy)
      ctx.lineTo(x1 - 2, dy)
      ctx.stroke()
      ctx.restore()

      // The gun. The loaded bubble sits in it; the next one waits beside it,
      // small and dim, so it reads as queued rather than as a stray bubble on
      // the playfield.
      var sx = root.px(Engine.shooterX()), sy = root.py(Engine.shooterY())
      var aim = s.angle - Math.PI / 2
      var barrel = root.pr(R * 2.3)
      ctx.strokeStyle = root.rgba(root.tint(s.current), 0.9)
      ctx.lineWidth = Math.max(2, root.pr(3.4))
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.moveTo(sx, sy)
      ctx.lineTo(sx + Math.cos(aim) * barrel, sy + Math.sin(aim) * barrel)
      ctx.stroke()
      ctx.lineCap = "butt"

      ctx.strokeStyle = root.rgba(Palette.cyan, 0.35)
      ctx.lineWidth = 1.4
      ctx.beginPath()
      ctx.arc(sx, sy, root.pr(R * 1.5), Math.PI, 0)
      ctx.stroke()

      if (!s.flying) bubble(sx, sy, root.tint(s.current))
      bubble(sx + root.pr(R * 3.1), sy + root.pr(R * 0.2), root.tint(s.next), 0.6, 0.62)

      var horizon = ctx.createLinearGradient(x0, y1 - h * 0.22, x0, y1)
      horizon.addColorStop(0, "rgba(0,0,0,0)")
      horizon.addColorStop(1, root.rgba(Palette.neon, 0.16))
      ctx.fillStyle = horizon
      ctx.fillRect(x0, y1 - h * 0.22, w, h * 0.22)

      // Frame, and a flash over the whole board on a pop.
      ctx.strokeStyle = root.mixHex(Palette.neonLine, Palette.neonBright, root.pressure)
      ctx.lineWidth = 2
      ctx.strokeRect(x0, y0, w, h)

      if (root.flash > 0) {
        ctx.fillStyle = root.rgba(Palette.neonBright, root.flash * 0.10)
        ctx.fillRect(x0, y0, w, h)
      }

      // A vignette, so the board does not end at a hard rectangle.
      var vig = ctx.createRadialGradient(x0 + w / 2, y0 + h * 0.45, w * 0.25,
                                         x0 + w / 2, y0 + h * 0.5, h * 0.75)
      vig.addColorStop(0, "rgba(0,0,0,0)")
      vig.addColorStop(1, "rgba(0,0,0,0.55)")
      ctx.fillStyle = vig
      ctx.fillRect(x0, y0, w, h)
    }
  }

  Row {
    visible: !root.showAttract && !root.showGameOver && gameState
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    height: root.hudH
    spacing: Style.space(12)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "SCORE " + (gameState ? gameState.score : 0)
      color: Palette.neonBright
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: gameState && gameState.combo > 1 ? "CHAIN x" + gameState.combo : ""
      visible: text.length > 0
      color: Palette.gold
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "DROP " + (gameState ? gameState.shotsToDrop : 0)
      color: root.pressure > 0.6 ? Palette.neonBright : Palette.cyan
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
    }
  }

  MenuAttract { active: root.showAttract }
  GameOverOverlay {
    active: root.showGameOver
    scoreLine: root.gameOverScore
    sessionLine: root.gameOverSession
    newBest: root.gameOverNewBest
  }
}
