import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root

  readonly property var rclone: bar && bar.shell ? bar.shell.serviceFor("renuo.rclone") : null
  readonly property var mounts: rclone ? rclone.mounts : []
  readonly property var summary: rclone ? rclone.summary : Model.summary([])
  readonly property bool showCount: summary.state === "uploading" && !vertical

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.glyph(root.summary.state)
    labelText: root.showCount ? Commons.I18n.formatNumber(root.summary.pending) : ""
    slotSize: Style.bar.iconSlot * (root.showCount ? 2 : 1)
    dimmed: root.summary.state === "none"
    active: root.summary.state === "unreachable"
    tooltipText: Model.tooltip(root.mounts, strings, Commons.I18n.formatNumber)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.rclone) root.rclone.refresh()
      } else {
        Quickshell.execDetached(["uwsm-app", "--", "nautilus", Quickshell.env("HOME") + "/Cloud"])
      }
    }
  }
}
