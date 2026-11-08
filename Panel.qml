import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar button plus popup. The button shows what the service polls from every
// mount. The popup has a card per remote: a switch for its mount, its
// settings and login, and for gdrive and onedrive a guide while they are
// missing. Logins and editors talk to a person, so ctl.sh runs them in
// Omarchy's floating terminal and the popup steps aside.
Panel {
  id: root
  moduleName: "renuo.rclone"
  ipcTarget: "rclone"

  readonly property var rclone: bar && bar.shell ? bar.shell.serviceFor("renuo.rclone") : null
  readonly property var mounts: rclone ? rclone.mounts : []
  readonly property var summary: rclone ? rclone.summary : Model.summary([])
  readonly property bool showCount: summary.state === "uploading" && !(bar && bar.vertical)
  readonly property string ctlPath: Model.pathFromUrl(Qt.resolvedUrl("ctl.sh"))
  readonly property string cloudDir: Quickshell.env("HOME") + "/Cloud"

  property var remotes: []
  property bool loaded: false
  property string actionError: ""
  // The remote whose mount switch is waiting for systemd.
  property string busyName: ""
  readonly property var cards: Model.cards(remotes, mounts)

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function refresh() {
    if (remotesProc.running) remotesProc.again = true
    else remotesProc.running = true
    if (rclone) rclone.refresh()
  }

  function setMount(name, on) {
    if (busyName !== "") return
    actionError = ""
    busyName = name
    mountProc.command = ["bash", ctlPath, "mount", name, on ? "on" : "off"]
    mountProc.running = true
  }

  // The terminal and the browser open behind a popup that holds the keyboard.
  function inTerminal(args) {
    Quickshell.execDetached(Model.terminalCommand(ctlPath, args))
    close()
  }

  function openUrl(url) {
    Quickshell.execDetached(["xdg-open", url])
    close()
  }

  function openFolder(path) {
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", path])
    close()
  }

  onOpenedChanged: if (opened) {
    actionError = ""
    refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: remotesProc
    property bool again: false
    command: ["bash", root.ctlPath, "remotes"]
    onRunningChanged: if (!running && again) {
      again = false
      running = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.remotes = Model.parseRemotes(text)
        root.loaded = true
      }
    }
  }

  Process {
    id: mountProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.actionError = Model.replyError(text)
        root.busyName = ""
        root.refresh()
      }
    }
  }

  // Only while someone looks: a login finished in the terminal shows up here.
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.glyph(root.summary.state)
    labelText: root.showCount ? Commons.I18n.formatNumber(root.summary.pending) : ""
    slotSize: Style.bar.iconSlot * (root.showCount ? 2 : 1)
    dimmed: root.summary.state === "none"
    active: root.summary.state === "unreachable"
    tooltipText: root.opened ? "" : Model.tooltip(root.mounts, strings, Commons.I18n.formatNumber)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else if (buttonCode === Qt.MiddleButton) root.openFolder(root.cloudDir)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(14)

          PanelHero {
            id: hero
            width: parent.width
            title: strings.t("title")
            meta: Model.heroMeta(root.mounts, strings, Commons.I18n.formatNumber)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: Model.glyph(root.summary.state)
                textFormat: Text.PlainText
                color: hero.foreground
                font.family: hero.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(6)

                PanelActionButton {
                  iconText: "󰝰" // folder-open
                  tooltipText: strings.t("action.openCloud")
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  onClicked: root.openFolder(root.cloudDir)
                }

                PanelActionButton {
                  iconText: "󰑐" // refresh
                  tooltipText: strings.t("action.refresh")
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  onClicked: root.refresh()
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Note {
            visible: root.actionError !== ""
            text: root.actionError
            color: root.urgent
          }

          Repeater {
            model: root.loaded ? root.cards : []

            RemoteCard {
              required property var modelData
              width: column.width
              remote: modelData
            }
          }

          PanelSeparator { foreground: root.foreground }

          Button {
            text: strings.t("action.config")
            iconText: "󰢻" // cog-outline
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.inTerminal(["config"])
          }
        }
      }
    }
  }

  component Note: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  component Action: Button {
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  component RemoteCard: Column {
    id: remoteCard
    property var remote: ({})
    readonly property bool drive: remote.type === "drive"
    readonly property bool onedrive: remote.type === "onedrive"

    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: Math.max(cardIcon.implicitHeight, cardTitle.implicitHeight, mountSwitch.implicitHeight)

      Text {
        id: cardIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: Model.typeGlyph(remoteCard.remote.type)
        textFormat: Text.PlainText
        color: remoteCard.remote.configured ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Column {
        id: cardTitle
        anchors.left: cardIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: mountSwitch.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: remoteCard.remote.name
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: Model.typeName(remoteCard.remote.type, strings) + " · " + Model.cardStatus(remoteCard.remote, strings, Commons.I18n.formatNumber)
          textFormat: Text.PlainText
          color: remoteCard.remote.state === "unreachable" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        id: mountSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: remoteCard.remote.configured
        checked: root.busyName === remoteCard.remote.name ? !remoteCard.remote.enabled : remoteCard.remote.enabled
        busy: root.busyName === remoteCard.remote.name
        interactive: remoteCard.remote.mountable
        foreground: root.foreground
        onToggled: root.setMount(remoteCard.remote.name, !remoteCard.remote.enabled)

        PanelToolTip {
          visible: mountSwitch.containsMouse
          text: !remoteCard.remote.mountable ? strings.t("toggle.unusable")
            : remoteCard.remote.enabled ? strings.t("toggle.off")
            : Model.format(strings.t("toggle.on"), [remoteCard.remote.name])
          fontFamily: root.fontFamily
        }
      }
    }

    // ---------- Set up: what the remote needs, then its controls ----------
    Column {
      visible: remoteCard.remote.configured
      width: parent.width
      spacing: Style.space(8)

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Action {
          visible: remoteCard.remote.state !== "off"
          text: strings.t("action.open")
          onClicked: root.openFolder(root.cloudDir + "/" + remoteCard.remote.name)
        }

        Action {
          visible: remoteCard.remote.mountable
          text: strings.t("action.settings")
          onClicked: root.inTerminal(["mount-settings", remoteCard.remote.name])
        }

        Action {
          text: strings.t("action.relogin")
          onClicked: root.inTerminal(["login", remoteCard.remote.name])
        }

        Action {
          visible: remoteCard.drive
          text: strings.t("action.client")
          onClicked: root.inTerminal(["client", remoteCard.remote.name])
        }
      }

      Note {
        visible: remoteCard.drive
        text: remoteCard.remote.sharedClient ? strings.t("drive.shared") : Model.format(strings.t("drive.project"), [remoteCard.remote.project])
        color: remoteCard.remote.sharedClient ? root.urgent : root.dim
      }

      Flow {
        visible: remoteCard.drive
        width: parent.width
        spacing: Style.space(6)

        Action {
          visible: !remoteCard.remote.sharedClient
          text: strings.t("action.credentials")
          onClicked: root.openUrl(Model.consoleUrl("credentials", remoteCard.remote.project))
        }

        Action {
          visible: !remoteCard.remote.sharedClient
          text: strings.t("action.audience")
          onClicked: root.openUrl(Model.consoleUrl("audience", remoteCard.remote.project))
        }

        Action {
          visible: remoteCard.remote.sharedClient
          text: strings.t("action.help")
          onClicked: root.openUrl(Model.helpUrl("drive"))
        }
      }

      Note {
        visible: remoteCard.onedrive && remoteCard.remote.driveType !== ""
        text: Model.driveTypeName(remoteCard.remote.driveType, strings)
      }
    }

    // ---------- Not set up yet: the guide ----------
    Column {
      visible: !remoteCard.remote.configured
      width: parent.width
      spacing: Style.space(8)

      Note {
        visible: remoteCard.drive
        text: remoteCard.remote.project !== ""
          ? Model.format(strings.t("guide.drive.clientKnown"), [remoteCard.remote.project])
          : strings.t("guide.drive.client")
      }

      Flow {
        visible: remoteCard.drive
        width: parent.width
        spacing: Style.space(6)

        Action {
          text: strings.t("action.credentials")
          onClicked: root.openUrl(Model.consoleUrl("credentials", remoteCard.remote.project))
        }

        Action {
          text: strings.t("action.help")
          onClicked: root.openUrl(Model.helpUrl("drive"))
        }
      }

      Note {
        text: strings.t(remoteCard.drive ? "guide.drive.login" : "guide.onedrive.login")
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Action {
          text: strings.t("action.login")
          iconText: "󰍂" // login
          onClicked: root.inTerminal(["login", remoteCard.remote.name])
        }

        Action {
          visible: remoteCard.onedrive
          text: strings.t("action.help")
          onClicked: root.openUrl(Model.helpUrl("onedrive"))
        }
      }

      Note { text: strings.t("guide.mount") }
    }
  }
}
