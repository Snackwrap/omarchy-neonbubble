import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GameEngine.js" as Engine
import "Palette.js" as Palette
import "Scores.js" as Scores

Panel {
  id: root
  moduleName: "com.leafbox.neonbubble"
  ipcTarget: "com.leafbox.neonbubble"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var panelFrame: null
  property string phase: "menu"
  property var gameState: null
  property bool holdLeft: false
  property bool holdRight: false
  property bool holdFire: false
  property var sessionStats: Scores.empty()
  property bool lastRecorded: false
  property int lastRecordedScore: -1

  readonly property string pluginId: "com.leafbox.neonbubble"

  readonly property string scoresDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/plugins/" + root.pluginId
  readonly property string scoresPath: scoresDir + "/scores.json"

  // The directory walk is descriptor-relative. Each component is opened with
  // O_NOFOLLOW | O_DIRECTORY and validated by fstat on that descriptor, and the
  // next component is opened *through* it as /proc/self/fd/N/<name>, which the
  // kernel resolves to the inode the descriptor holds rather than re-walking the
  // path. The temporary file and the rename that publishes it go through that
  // same descriptor, so the write is bound to the directories that were checked:
  // an ancestor cannot be a symlink, and cannot be swapped after the check. There
  // is no reopen by pathname afterwards -- O_EXCL creates the leaf 0600 already.
  readonly property string walkScript:
    "my $home = $ENV{HOME} or exit 1;" +
    "$home =~ s|/+$||;" +
    "my $id = \"" + root.pluginId + "\";" +
    "$SIG{ALRM} = sub { exit 1 }; alarm 5;" +
    "sysopen(my $dh, $home, O_RDONLY | O_DIRECTORY) or exit 1;" +
    "for my $part ('.local', 'state', 'omarchy', 'plugins', $id) {" +
    "  my $p = '/proc/self/fd/' . fileno($dh) . \"/$part\"; my $nh;" +
    "  unless (sysopen($nh, $p, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)) {" +
    "    exit 1 unless $create;" +
    "    mkdir($p, 0700);" +
    "    sysopen($nh, $p, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) or exit 1;" +
    "  }" +
    "  my @d = stat($nh) or exit 1;" +
    "  exit 1 unless S_ISDIR($d[2]);" +
    "  exit 1 unless $d[4] == $<;" +
    "  exit 1 if ($d[2] & 0022);" +
    "  close($dh); $dh = $nh;" +
    "}" +
    "my $dir = '/proc/self/fd/' . fileno($dh);"

  readonly property string safeReadScript:
    "use strict; use Fcntl qw(:DEFAULT :mode); my $create = 0;" +
    root.walkScript +
    "sysopen(my $fh, \"$dir/scores.json\", O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or exit 1;" +
    "my @s = stat($fh) or exit 1;" +
    "exit 1 unless S_ISREG($s[2]);" +
    "exit 1 unless $s[4] == $<;" +
    "exit 1 if $s[3] > 1;" +
    "exit 1 if $s[7] > 4096;" +
    "exit 1 if ($s[2] & 0022);" +
    "my $buf = \"\"; sysread($fh, $buf, 4096); print $buf;"

  readonly property string safeWriteScript:
    "use strict; use Fcntl qw(:DEFAULT :mode); my $create = 1;" +
    "my $payload = $ARGV[0];" +
    "exit 1 unless defined $payload;" +
    "exit 1 if length($payload) > 4096;" +
    root.walkScript +
    "my $tmp = \"$dir/.scores.json.tmp.$$\";" +
    "sysopen(my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or exit 1;" +
    "print $fh $payload or do { close($fh); unlink $tmp; exit 1 };" +
    "close($fh) or do { unlink $tmp; exit 1 };" +
    "rename($tmp, \"$dir/scores.json\") or do { unlink $tmp; exit 1 };"

  readonly property string perlBin: "/usr/bin/perl"

  property int scoresReadStartedMs: 0
  property int scoresSaveStartedMs: 0

  function boolSetting(name, dflt) {
    var v = setting(name, dflt)
    return v === true || v === "true" || v === 1
  }

  readonly property bool soundOn: boolSetting("sound", true)

  // Daily by default: everyone gets the same board on the same day, which is
  // the reason to open this more than once. "random" deals a fresh one every
  // game for people who would rather just play.
  readonly property string boardMode: {
    var v = String(setting("boardMode", "daily"))
    return (v === "random") ? "random" : "daily"
  }

  // Difficulty is the shape of the ceiling's descent and nothing else — the
  // board is identical on all three, so the daily puzzle stays comparable.
  // `difficultyChoice` is a session-only override for the D key: the manifest
  // setting remains the persistent policy, and this plugin never writes to a
  // configuration file.
  property string difficultyChoice: ""
  readonly property string difficultySetting: Engine.difficultyOf(setting("difficulty", "normal"))
  readonly property string difficulty:
    difficultyChoice !== "" ? Engine.difficultyOf(difficultyChoice) : difficultySetting

  readonly property int daySeed: Engine.boardTodaySeed()
  readonly property string debugPreviewScene: String(setting("debugPreviewScene", "off"))
  // Every frozen scene has to be listed here as well as in applyPreviewScene,
  // or the capture quietly photographs the attract screen instead — the shot
  // verifier only proves the popup was open, not that it showed the scene.
  readonly property var previewScenes: ["play", "chain", "gameover"]
  readonly property bool previewFrozen: previewScenes.indexOf(debugPreviewScene) >= 0
  readonly property bool debugGeometry: boolSetting("debugGeometry", false)

  readonly property bool inPlay: phase === "play"
    && gameState && gameState.phase !== "gameover"

  readonly property string label: {
    if (inPlay && gameState) return String(gameState.score)
    if (phase === "gameover" && gameState) return "HI"
    return "NB"
  }

  readonly property string tooltip: {
    if (inPlay && gameState)
      return "Neon Bubble Pop  " + gameState.score + " pts  ·  "
           + gameState.shotsToDrop + " to the drop"
    if (phase === "gameover" && gameState)
      return "Game over — " + gameState.score + " pts — Enter to play again"
    return "Neon Bubble Pop — Enter to play"
  }

  readonly property string sessionLine: Scores.sessionLine(sessionStats, daySeed, difficulty)

  // The board kind and the ladder the score beside it belongs to. Both matter:
  // BEST means nothing without knowing which curve produced it.
  readonly property string metaLine:
    "◆ " + (boardMode === "daily" ? "DAILY" : "RANDOM")
    + "  ·  " + difficulty.toUpperCase()

  // A save that arrives while one is in flight is queued rather than forced.
  // running = false does not reap the child before the next statement, so the
  // old code reassigned the payload — and with it the command binding — under a
  // live process, and the new score was written by nobody. Losing a high score
  // to that is the one bug this file exists to avoid.
  property string pendingSave: ""

  function saveScores(payload) {
    if (!Scores.isValidPayload(payload)) return
    if (scoresSaveProc.running) { pendingSave = payload; return }
    pendingSave = ""
    scoresSaveProc.payload = payload
    scoresSaveStartedMs = Date.now()
    scoresSaveProc.running = true
  }

  function stopScoreProcs() {
    pendingSave = ""
    scoresReader.running = false
    scoresSaveProc.running = false
    scoresReadStartedMs = 0
    scoresSaveStartedMs = 0
  }

  function openFromHotkey() { open() }

  function startGame() {
    // A random board still gets a seed, so a game is always reproducible from
    // the number it started with.
    var seed = (boardMode === "daily") ? daySeed
             : ((Date.now() & 0x7fffffff) | 0)
    gameState = Engine.create(seed, { daily: boardMode === "daily", difficulty: difficulty })
    phase = "play"
    lastRecorded = false
    lastRecordedScore = -1
    if (sfxLoader.item) sfxLoader.item.play("start")
    Qt.callLater(function() { if (gameInput) gameInput.forceActiveFocus() })
  }

  function resetGame() {
    gameState = null
    phase = "menu"
    holdLeft = false
    holdRight = false
    holdFire = false
    lastRecorded = false
    lastRecordedScore = -1
  }

  // Only between games: the curve is fixed when create() runs, so changing it
  // mid-game would leave the run on the old cadence and file the score under
  // the new ladder.
  function cycleDifficulty() {
    if (phase !== "menu" && phase !== "gameover") return
    var order = Engine.difficultyNames()
    var at = order.indexOf(difficulty)
    difficultyChoice = order[(at + 1) % order.length]
    if (sfxLoader.item) sfxLoader.item.play("wall")
  }

  function resetHighScores() {
    sessionStats = Scores.reset(sessionStats)
    saveScores(Scores.serialize(sessionStats))
  }

  function recordGameOver() {
    if (!gameState || gameState.phase !== "gameover") return
    // A frozen debug scene is not a game that was played. Without this, every
    // screenshot run wrote previewState's 12850 into the real high-score file
    // and counted itself as another game.
    if (previewFrozen) return
    if (lastRecorded && lastRecordedScore === gameState.score) return
    sessionStats = Scores.recordGame(sessionStats, gameState.score, daySeed, difficulty)
    lastRecorded = true
    lastRecordedScore = gameState.score
    saveScores(Scores.serialize(sessionStats))
  }

  readonly property string gameOverScoreLine: {
    if (!gameState) return ""
    return String(gameState.score) + " PTS"
  }

  readonly property bool gameOverNewBest: {
    if (!gameState || gameState.phase !== "gameover") return false
    // Scores.best(), not sessionStats.best: bests moved into per-difficulty
    // tracks, and reading the old top-level field gives undefined — which makes
    // `score >= undefined` false and the NEW BEST banner never appear.
    return gameState.score >= Scores.best(sessionStats, difficulty) && gameState.score > 0
  }

  function applyPreviewScene() {
    var scene = debugPreviewScene
    if (scene === "off" || scene === "") {
      resetGame()
      return
    }
    if (scene === "play" || scene === "chain") {
      gameState = Engine.previewState(scene)
      phase = "play"
      return
    }
    if (scene === "gameover") {
      gameState = Engine.previewState("gameover")
      phase = "gameover"
      return
    }
    resetGame()
  }

  Component.onCompleted: scoresReadTimer.restart()
  Component.onDestruction: {
    stopScoreProcs()
    if (sfxLoader.item && sfxLoader.item.stopAll) sfxLoader.item.stopAll()
  }

  Process {
    id: scoresSaveProc
    property string payload: ""
    running: false
    command: [root.perlBin, "-e", root.safeWriteScript, "--", payload]
    onExited: {
      root.scoresSaveStartedMs = 0
      if (root.pendingSave.length > 0) {
        var next = root.pendingSave
        root.pendingSave = ""
        root.saveScores(next)
      }
    }
  }

  Process {
    id: scoresReader
    running: false
    command: [root.perlBin, "-e", root.safeReadScript]
    onExited: root.scoresReadStartedMs = 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "")
        if (raw.length === 0 || raw.length > 4096) return
        root.sessionStats = Scores.parse(raw)
      }
    }
  }

  FileView {
    path: root.scoresPath
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: scoresReadTimer.restart()
  }

  Timer {
    id: scoresReadTimer
    interval: 250
    onTriggered: {
      if (scoresReader.running) return
      scoresReadStartedMs = Date.now()
      scoresReader.running = true
    }
  }

  Timer {
    interval: 1500
    running: true
    onTriggered: scoresReadTimer.restart()
  }

  Timer {
    interval: 1000
    running: scoresReader.running || scoresSaveProc.running
    repeat: true
    onTriggered: {
      var now = Date.now()
      if (scoresReader.running && scoresReadStartedMs && now - scoresReadStartedMs > 4000)
        scoresReader.running = false
      if (scoresSaveProc.running && scoresSaveStartedMs && now - scoresSaveStartedMs > 5000)
        scoresSaveProc.running = false
    }
  }

  onPhaseChanged: {
    if (phase === "play")
      Qt.callLater(function() { if (gameInput) gameInput.forceActiveFocus() })
    else if (keyCatcher)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    if (phase === "gameover") recordGameOver()
  }

  onOpenedChanged: {
    if (!opened) {
      resetGame()
      gameLoop.stop()
      return
    }
    holdLeft = false
    holdRight = false
    holdFire = false
    applyPreviewScene()
    scoresReadTimer.restart()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    if (debugGeometry) geometryTimer.restart()
  }

  Timer {
    id: geometryTimer
    interval: 900
    onTriggered: root.reportGeometry()
  }

  Connections {
    target: root.debugGeometry ? root.panelFrame : null
    function onHeightChanged() { geometryTimer.restart() }
  }

  function reportGeometry() {
    if (!panelFrame) return
    var inset = panel.padding + Math.max(1, Style.space(2))
    var origin = panelFrame.mapToGlobal(0, 0)
    console.log("NEON_BUBBLE_GEOMETRY "
                + Math.round(origin.x - inset) + " " + Math.round(origin.y - inset) + " "
                + Math.round(panelFrame.width + inset * 2) + " "
                + Math.round(panelFrame.height + inset * 2))
  }

  Timer {
    id: gameLoop
    interval: 16
    repeat: true
    running: root.opened && root.phase === "play" && root.gameState !== null && !root.previewFrozen
    onTriggered: {
      var prev = root.gameState
      root.gameState = Engine.step(prev, interval, root.holdLeft, root.holdRight, root.holdFire)
      // Fire is a tap, not a hold. The engine consumes it on the frame it sees
      // it, and leaving the flag raised would empty the gun as fast as it
      // reloads.
      if (root.holdFire) root.holdFire = false
      if (root.gameState.phase === "gameover" && root.phase !== "gameover")
        root.phase = "gameover"
      if (sfxLoader.item) sfxLoader.item.handleEvents(root.gameState.events)
    }
  }

  Loader {
    id: sfxLoader
    source: Qt.resolvedUrl("Sfx.qml")
    onLoaded: {
      if (item) item.enabled = root.soundOn
    }
  }

  onSoundOnChanged: {
    if (sfxLoader.item) sfxLoader.item.enabled = soundOn
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: String(root.setting("popupPosition", "icon")) === "center"
    focusTarget: root.phase === "play" ? gameInput : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(contentCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.phase === "play"

      Component.onCompleted: root.panelFrame = keyCatcher

      onActivateRequested: {
        if (root.phase === "menu" || root.phase === "gameover") root.startGame()
      }

      onTextKey: function(t) {
        if (root.phase !== "menu" && root.phase !== "gameover") return
        if (t === "r" || t === "R") root.resetHighScores()
        if (t === "d" || t === "D") root.cycleDifficulty()
      }

      onCloseRequested: root.close()

      Item {
        id: gameInput
        anchors.fill: parent
        focus: root.phase === "play"
        activeFocusOnTab: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.phase !== "play") return
          var k = event.key

          if (k === Qt.Key_Escape) {
            root.close()
            event.accepted = true
            return
          }

          if (k === Qt.Key_Left) {
            root.holdLeft = true
            event.accepted = true
            return
          }
          if (k === Qt.Key_Right) {
            root.holdRight = true
            event.accepted = true
            return
          }
          // One shot per press. Refusing auto-repeat is what makes holding
          // space a single shot rather than a stream of them.
          if (k === Qt.Key_Space) {
            if (!event.isAutoRepeat) root.holdFire = true
            event.accepted = true
            return
          }

          if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (root.gameState && root.gameState.phase === "gameover") root.startGame()
            event.accepted = true
          }
        }

        Keys.onReleased: function(event) {
          var k = event.key
          if (k === Qt.Key_Left) {
            root.holdLeft = false
            event.accepted = true
          } else if (k === Qt.Key_Right) {
            root.holdRight = false
            event.accepted = true
          } else if (k === Qt.Key_Space) {
            event.accepted = true
          }
        }
      }

      Column {
        id: contentCol
        width: parent.width
        spacing: Style.space(8)

        TitleHeader {
          width: parent.width
          sessionLine: root.sessionLine
          metaLine: root.metaLine
        }

        Board {
          width: parent.width
          gameState: root.gameState
          showAttract: root.phase === "menu"
          showGameOver: root.phase === "gameover"
          gameOverScore: root.gameOverScoreLine
          gameOverSession: root.sessionLine
          gameOverNewBest: root.gameOverNewBest
          difficulty: root.difficulty
        }

        Item {
          width: parent.width
          height: root.phase === "gameover" ? 0 : hintText.implicitHeight + Style.space(4)
          visible: root.phase !== "gameover"

          Text {
            id: hintText
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: Palette.neonBright
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            text: {
              if (root.phase === "menu")
                return "← → — aim   SPACE — fire\nENTER — start   R — reset best   ESC — close"
              if (root.gameState && root.gameState.phase === "launch")
                return "Hold SPACE to charge plunger — release to launch"
              if (root.gameState && root.gameState.phase === "drain")
                return "Ball drained…"
              if (root.gameState && root.gameState.jackpotReady)
                return "JACKPOT LIT — hit any bumper!"
              return "← → — aim   SPACE — fire"
            }
          }
        }
      }
    }
  }
}
