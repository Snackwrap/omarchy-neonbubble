import QtQuick
import qs.Commons
import "Palette.js" as Palette

Item {
  id: root

  property bool active: false
  property string scoreLine: ""
  property string sessionLine: ""
  property bool newBest: false

  anchors.fill: parent
  visible: opacity > 0.01
  opacity: active ? 1 : 0

  Behavior on opacity {
    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.space(2)
    color: Palette.bg
    opacity: 0.84
  }

  Canvas {
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      ctx.strokeStyle = Palette.neonLine
      ctx.lineWidth = 1.5
      ctx.strokeRect(w * 0.08, h * 0.1, w * 0.84, h * 0.78)
      ctx.strokeStyle = Palette.goldDim
      ctx.strokeRect(w * 0.1, h * 0.12, w * 0.8, h * 0.74)
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)
    width: parent.width * 0.86

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "GAME OVER"
      // neonDim is the colour of an unlit element; on the heading of the card
      // it left the two words all but unreadable over the darkened table.
      color: Palette.neon
      opacity: 0.75
      font.family: Style.font.family
      font.pixelSize: Style.space(10)
      font.letterSpacing: Style.space(4)
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.newBest ? "NEW HIGH SCORE" : "FINAL SCORE"
      color: root.newBest ? Palette.gold : Palette.neonBright
      font.family: Style.font.family
      font.pixelSize: Style.space(18)
      font.bold: true
      font.letterSpacing: Style.space(2)
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.scoreLine
      color: Palette.cyanBright
      font.family: Style.font.family
      font.pixelSize: Style.space(24)
      font.bold: true
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.sessionLine
      color: Palette.cyan
      font.family: Style.font.family
      font.pixelSize: Style.space(10)
      font.letterSpacing: Style.space(1)
      opacity: 0.9
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "ENTER — play again   R — reset best"
      color: Palette.neonBright
      font.family: Style.font.family
      font.pixelSize: Style.space(10)
      font.letterSpacing: Style.space(1)

      SequentialAnimation on opacity {
        running: root.active
        loops: Animation.Infinite
        // Floor raised from 0.35: the line is how you learn the two keys, and
        // for half of every cycle it was too faint to read.
        NumberAnimation { from: 0.55; to: 1; duration: 700 }
        NumberAnimation { from: 1; to: 0.55; duration: 700 }
      }
    }
  }
}
