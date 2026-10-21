import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One poll for every bar surface: a widget per monitor would otherwise each
// run status.sh against every mount.
Item {
  id: root

  property var mounts: []
  readonly property var summary: Model.summary(mounts)
  readonly property string scriptPath: Model.pathFromUrl(Qt.resolvedUrl("status.sh"))

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  Process {
    id: statusProcess
    command: ["bash", root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mounts = Model.parseMounts(text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
