import QtQuick
import qs.Commons
import "Palette.js" as Palette

Item {
  id: root
  property bool active: false

  anchors.fill: parent
  visible: opacity > 0.01
  opacity: active ? 1 : 0

  Behavior on opacity {
    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.space(2)
    color: Palette.bg
    opacity: 0.74
  }

  Canvas {
    anchors.fill: parent
    property real pulse: 1
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPulseChanged: requestPaint()

    SequentialAnimation on pulse {
      running: root.active
      loops: Animation.Infinite
      NumberAnimation { from: 0.92; to: 1.08; duration: 1800; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.08; to: 0.92; duration: 1800; easing.type: Easing.InOutSine }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var cx = w / 2

      var sky = ctx.createLinearGradient(0, 0, 0, h * 0.5)
      sky.addColorStop(0, "#120018")
      sky.addColorStop(1, "#030308")
      ctx.fillStyle = sky
      ctx.fillRect(0, 0, w, h * 0.5)

      ctx.strokeStyle = Palette.cyan
      ctx.globalAlpha = 0.22
      ctx.lineWidth = 1
      for (var r = 0; r <= 6; r++) {
        var gy = h * 0.48 + (h * 0.52) * (r / 6) * (r / 6)
        ctx.beginPath()
        ctx.moveTo(0, gy)
        ctx.lineTo(w, gy)
        ctx.stroke()
      }
      for (var c = -5; c <= 5; c++) {
        ctx.beginPath()
        ctx.moveTo(cx + c * w * 0.05, h * 0.48)
        ctx.lineTo(cx + c * w * 0.38, h)
        ctx.stroke()
      }
      ctx.globalAlpha = 1

      // The sun. Flat gold at 0.35 alpha over a near-black sky came out olive
      // and read as a smudge rather than a shape. A gradient down into the
      // pink, and bands cut through the lower half, is what makes the disc
      // legible — and it is the one thing everybody's mental image of this
      // artwork has in it.
      var sunR = Math.min(w, h) * 0.085 * pulse
      var sunY = h * 0.22
      var sun = ctx.createLinearGradient(0, sunY - sunR, 0, sunY + sunR)
      sun.addColorStop(0, Palette.gold)
      sun.addColorStop(0.55, "#FF9E4D")
      sun.addColorStop(1, Palette.neon)

      ctx.save()
      ctx.beginPath()
      ctx.arc(cx, sunY, sunR, 0, Math.PI * 2)
      ctx.clip()
      ctx.fillStyle = sun
      ctx.globalAlpha = 0.9
      ctx.fillRect(cx - sunR, sunY - sunR, sunR * 2, sunR * 2)

      // Bands widen toward the bottom, so the disc dissolves into the sky
      // rather than ending on a hard edge.
      ctx.globalCompositeOperation = "destination-out"
      ctx.fillStyle = "#000000"
      ctx.globalAlpha = 1
      for (var b = 0; b < 6; b++) {
        var by = sunY + sunR * (0.12 + b * 0.16)
        ctx.fillRect(cx - sunR, by, sunR * 2, sunR * (0.02 + b * 0.018))
      }
      ctx.restore()

      // A halo, so it sits in the sky instead of on top of it. Radial, not a
      // flat disc at low alpha: that just draws a second, larger circle with a
      // visible edge, which is the opposite of a glow.
      var halo = ctx.createRadialGradient(cx, sunY, sunR * 0.9, cx, sunY, sunR * 2.4)
      halo.addColorStop(0, Palette.neon)
      halo.addColorStop(1, "transparent")
      ctx.globalAlpha = 0.3 * pulse
      ctx.fillStyle = halo
      ctx.beginPath()
      ctx.arc(cx, sunY, sunR * 2.4, 0, Math.PI * 2)
      ctx.fill()
      ctx.globalAlpha = 1
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(4)
    width: parent.width * 0.88

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "NEON VALLEY"
      color: Palette.cyanBright
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.letterSpacing: Style.space(6)
      opacity: 0.9
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "BUBBLE"
      color: Palette.neonBright
      font.family: Style.font.family
      font.pixelSize: Style.space(32)
      font.bold: true
      font.letterSpacing: Style.space(8)
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "◆ INSERT COIN ◆"
      color: Palette.gold
      font.family: Style.font.family
      font.pixelSize: Style.space(9)
      font.letterSpacing: Style.space(3)
      opacity: 0.85
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "▶  PRESS ENTER"
      color: Palette.neonBright
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.letterSpacing: Style.space(2)

      SequentialAnimation on opacity {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { from: 0.25; to: 1; duration: 620; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 1; to: 0.25; duration: 620; easing.type: Easing.InOutQuad }
      }
    }
  }
}
