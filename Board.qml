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
  readonly property real aspect: boardW / boardH
  implicitWidth: Style.space(320)
  implicitHeight: Math.round(implicitWidth / aspect) + Style.space(8)

  readonly property real playW: width - Style.space(6)
  readonly property real playH: height - Style.space(6)
  readonly property real sc: Math.min(playW / boardW, playH / boardH)
  readonly property real originX: (width - boardW * sc) / 2
  readonly property real originY: Style.space(3)
  readonly property int tick: gameState ? (gameState.tick || 0) : 0

  function px(x) { return originX + x * sc }
  function py(y) { return originY + y * sc }
  function pr(r) { return r * sc }

  // One place decides what a colour looks like, so the board, the loaded
  // bubble and the falling ones can never disagree about it.
  function tint(name) {
    if (name === "pink") return Palette.neon
    if (name === "cyan") return Palette.cyan
    if (name === "gold") return Palette.gold
    if (name === "violet") return Palette.violet
    if (name === "lime") return Palette.lime
    return Palette.neonDim
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

      var x0 = root.px(0), y0 = root.py(0)
      var x1 = root.px(root.boardW), y1 = root.py(root.boardH)

      var floor = ctx.createLinearGradient(x0, y0, x0, y1)
      floor.addColorStop(0, "#150a1e")
      floor.addColorStop(1, "#0a0612")
      ctx.fillStyle = floor
      ctx.fillRect(x0, y0, x1 - x0, y1 - y0)

      ctx.strokeStyle = Palette.neonLine
      ctx.lineWidth = 2
      ctx.strokeRect(x0, y0, x1 - x0, y1 - y0)

      // The line the board must not cross. It is the only warning the player
      // gets, so it is drawn as a hazard rather than a hairline.
      var dy = root.py(Engine.boardDeathY())
      ctx.save()
      ctx.setLineDash([6, 6])
      ctx.strokeStyle = Palette.neon
      ctx.globalAlpha = 0.55
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(x0 + 2, dy)
      ctx.lineTo(x1 - 2, dy)
      ctx.stroke()
      ctx.restore()

      // The aim guide, from the same numbers the shot uses.
      if (s.phase === "aim") {
        var path = Engine.aimPath(s, 110)
        ctx.strokeStyle = root.tint(s.current)
        ctx.globalAlpha = 0.5
        ctx.lineWidth = 2
        ctx.setLineDash([3, 7])
        ctx.beginPath()
        for (var pi = 0; pi < path.length; pi++) {
          var p = path[pi]
          if (pi === 0) ctx.moveTo(root.px(p.x), root.py(p.y))
          else ctx.lineTo(root.px(p.x), root.py(p.y))
        }
        ctx.stroke()
        ctx.setLineDash([])
        ctx.globalAlpha = 1
      }

      function bubble(cx, cy, colour, alpha, popping) {
        var rr = root.pr(R) * (popping ? 1.35 : 1)
        ctx.globalAlpha = (alpha === undefined ? 1 : alpha) * 0.22
        ctx.fillStyle = colour
        ctx.beginPath()
        ctx.arc(cx, cy, rr * 1.32, 0, Math.PI * 2)
        ctx.fill()
        ctx.globalAlpha = (alpha === undefined ? 1 : alpha)
        ctx.fillStyle = colour
        ctx.beginPath()
        ctx.arc(cx, cy, rr * 0.86, 0, Math.PI * 2)
        ctx.fill()
        // A highlight, so a flat disc reads as a sphere.
        ctx.globalAlpha = (alpha === undefined ? 1 : alpha) * 0.5
        ctx.fillStyle = "#ffffff"
        ctx.beginPath()
        ctx.arc(cx - rr * 0.3, cy - rr * 0.32, rr * 0.22, 0, Math.PI * 2)
        ctx.fill()
        ctx.globalAlpha = 1
      }

      var rows = Engine.boardRows()
      for (var r = 0; r < rows; r++) {
        var len = Engine.boardRowLen(r, s.parity)
        for (var c = 0; c < len; c++) {
          var v = s.grid[r][c]
          if (!v) continue
          bubble(root.px(Engine.boardCellX(r, c, s.parity)),
                 root.py(Engine.boardCellY(r)), root.tint(v))
        }
      }

      for (var fi = 0; fi < s.falling.length; fi++) {
        var fb = s.falling[fi]
        bubble(root.px(fb.x), root.py(fb.y), root.tint(fb.color), 0.75)
      }

      if (s.flying) bubble(root.px(s.flying.x), root.py(s.flying.y), root.tint(s.flying.color))

      // The gun: the loaded bubble, and the next one waiting behind it.
      var sx = root.px(Engine.shooterX()), sy = root.py(Engine.shooterY())
      var aim = s.angle - Math.PI / 2
      ctx.strokeStyle = root.tint(s.current)
      ctx.lineWidth = 4
      ctx.globalAlpha = 0.85
      ctx.beginPath()
      ctx.moveTo(sx, sy)
      ctx.lineTo(sx + Math.cos(aim) * root.pr(R * 2.1), sy + Math.sin(aim) * root.pr(R * 2.1))
      ctx.stroke()
      ctx.globalAlpha = 1
      if (!s.flying) bubble(sx, sy, root.tint(s.current))
      bubble(sx + root.pr(R * 2.6), sy + root.pr(R * 0.5), root.tint(s.next), 0.45)
    }
  }

  Row {
    visible: !root.showAttract && !root.showGameOver && gameState
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: Style.space(4)
    spacing: Style.space(12)

    Text {
      textFormat: Text.PlainText
      text: "SCORE " + (gameState ? gameState.score : 0)
      color: Palette.neonBright
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: gameState && gameState.combo > 1 ? "x" + gameState.combo : ""
      visible: text.length > 0
      color: Palette.gold
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: "DROP " + (gameState ? gameState.shotsToDrop : 0)
      color: Palette.cyan
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
