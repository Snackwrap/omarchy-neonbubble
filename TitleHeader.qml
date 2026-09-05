import QtQuick
import qs.Commons
import "Palette.js" as Palette

Item {
  id: root

  property string sessionLine: ""
  // Was hardcoded "◆ DAILY BOARD", which was wrong in random mode and had
  // nowhere to say which difficulty the score beside it belongs to.
  property string metaLine: "◆ DAILY BOARD"
  implicitWidth: Style.space(400)
  implicitHeight: titleBlock.implicitHeight + Style.space(6)

  Column {
    id: titleBlock
    width: parent.width
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.space(4)
      Rectangle { width: Style.space(18); height: 1; color: Palette.neonLine; anchors.verticalCenter: parent.verticalCenter }
      Rectangle { width: parent.width - Style.space(36); height: 1; color: Palette.neonDim; anchors.verticalCenter: parent.verticalCenter; opacity: 0.6 }
      Rectangle { width: Style.space(18); height: 1; color: Palette.neonLine; anchors.verticalCenter: parent.verticalCenter }
    }

    Item {
      width: parent.width
      height: Math.max(titleGlow.implicitHeight, titleMain.implicitHeight)

      Text {
        id: titleGlow
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "NEON BUBBLE"
        color: Palette.neon
        opacity: 0.28
        font.family: Style.font.family
        font.pixelSize: Style.space(22)
        font.bold: true
        font.letterSpacing: Style.space(4)
        y: Style.space(2)
      }

      Text {
        id: titleMain
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "NEON BUBBLE"
        color: Palette.neonBright
        font.family: Style.font.family
        font.pixelSize: Style.space(22)
        font.bold: true
        font.letterSpacing: Style.space(4)
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: "NEON VALLEY  ·  CHAIN POP  '86"
      color: Palette.cyan
      opacity: 0.82
      font.family: Style.font.family
      font.pixelSize: Style.space(9)
      font.letterSpacing: Style.space(2)
    }

    Item {
      width: parent.width
      height: metaRow.implicitHeight

      Text {
        id: metaRow
        // The score sits at the right of this same row, so the meta line gets
        // whatever is left and elides rather than running underneath it.
        anchors.left: parent.left
        anchors.right: sessionText.left
        anchors.rightMargin: Style.space(6)
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.metaLine
        color: Palette.neonDim
        font.family: Style.font.family
        font.pixelSize: Style.space(8)
        font.letterSpacing: Style.space(1)
      }

      Text {
        id: sessionText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sessionLine
        color: Palette.gold
        font.family: Style.font.family
        font.pixelSize: Style.space(8)
        font.letterSpacing: Style.space(1)
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(4)
      Rectangle { width: Style.space(10); height: 1; color: Palette.cyanDim; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
      Rectangle { width: parent.width - Style.space(20); height: 1; color: Palette.neonLine; anchors.verticalCenter: parent.verticalCenter; opacity: 0.45 }
      Rectangle { width: Style.space(10); height: 1; color: Palette.cyanDim; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
    }
  }
}
