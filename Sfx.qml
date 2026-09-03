import QtQuick
import Quickshell.Io

Item {
  id: root

  property bool enabled: true
  property int bounceCooldownMs: 60
  property int lastBounceMs: 0

  readonly property string paplayBin: "/usr/bin/paplay"
  // Compared against true rather than tested for truthiness: a plain object
  // answers for every key on Object.prototype, so `allowedSfx["constructor"]`
  // is a Function and passes a truthiness check.
  readonly property var allowedSfx: ({
    bomb: true, charged: true, cleared: true, descend: true,
    drop: true, fire: true, gameover: true, pop: true,
    star: true, star_in: true, start: true, stick: true,
    wall: true, wild: true
  })

  function isSfx(name) {
    return typeof name === "string" && root.allowedSfx[name] === true
  }

  property int sfxStartedMs: 0
  property string pending: ""

  function localPath(name) {
    if (!isSfx(name)) return ""
    var url = Qt.resolvedUrl("assets/sfx/" + name + ".wav").toString()
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.slice(7))
    return url
  }

  function stopAll() {
    pending = ""
    sfxProc.running = false
    sfxStartedMs = 0
  }

  // Setting running = false does not reap the child before the next line runs,
  // so assigning command and running = true straight after lands on a process
  // that is still alive and the sound is silently dropped. Hand the path to
  // onExited instead. Only the newest is kept: during a bumper flurry the
  // interesting sound is the one that just happened.
  function launch(path) {
    if (sfxProc.running) { pending = path; return }
    pending = ""
    sfxProc.command = [paplayBin, "--volume=42000", path]
    sfxStartedMs = Date.now()
    sfxProc.running = true
  }

  function play(name) {
    if (!enabled) return
    if (!isSfx(name)) return
    var path = localPath(name)
    if (!path) return
    if (name === "bounce") {
      var now = Date.now()
      if (now - lastBounceMs < bounceCooldownMs) return
      lastBounceMs = now
    }
    launch(path)
  }

  function handleEvents(events) {
    if (!events || !events.length) return
    for (var i = 0; i < events.length; i++) {
      var e = events[i]
      if (isSfx(e)) play(e)
    }
  }

  Process {
    id: sfxProc
    running: false
    onExited: {
      root.sfxStartedMs = 0
      if (root.pending.length > 0) {
        var next = root.pending
        root.pending = ""
        root.launch(next)
      }
    }
  }

  Timer {
    interval: 1000
    running: sfxProc.running
    repeat: true
    onTriggered: {
      if (root.sfxStartedMs && Date.now() - root.sfxStartedMs > 5000)
        root.stopAll()
    }
  }

  Component.onDestruction: stopAll()
}
