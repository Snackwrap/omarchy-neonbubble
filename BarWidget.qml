import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "com.leafbox.neonbubble"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.resetGame) panelLoader.item.resetGame()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool pillPulse: panelLoader.item ? panelLoader.item.inPlay === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  TextMetrics {
    id: pillMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: button.text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : "NP"
    slotSize: Math.max(Style.bar.statusSlot,
                       Math.ceil(pillMetrics.width) + Style.space(9))
    opticalSize: slotSize
    tooltipText: panelLoader.item ? panelLoader.item.tooltip : "Neon Bubble Pop"
    foreground: root.pillPulse ? "#FF006E" : (root.bar ? root.bar.barForeground : Color.foreground)

    SequentialAnimation on opacity {
      running: root.pillPulse
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.62; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.62; to: 1; duration: 900; easing.type: Easing.InOutSine }
    }

    onOpacityChanged: if (!root.pillPulse && opacity < 1) opacity = 1

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
