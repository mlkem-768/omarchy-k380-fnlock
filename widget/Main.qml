import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.mlkem-768.k380-fnlock"

  // Parsed from `omarchy-k380-fnlock status`, which prints two lines:
  //   Desired: on|off|not set
  //   Applied: on|off|not set
  property string desired: ""
  property string applied: ""

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.desired = root.desired
    panelLoader.item.applied = root.applied
  }

  // `status` output looks like:
  //   Desired: on
  //   Applied: on
  // (or "not set" for either line before anything has run).
  function parseStatus(text) {
    let desired = ""
    let applied = ""
    const lines = text.split("\n")
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      let m = line.match(/^Desired:\s*(.+)$/)
      if (m) desired = m[1].trim()
      m = line.match(/^Applied:\s*(.+)$/)
      if (m) applied = m[1].trim()
    }
    return { desired: desired, applied: applied }
  }

  function refreshStatus() {
    statusProc.running = false
    statusProc.running = true
  }

  function run(args) {
    cmdProc.command = ["omarchy-k380-fnlock"].concat(args)
    cmdProc.running = false
    cmdProc.running = true
  }

  function setMode(next) {
    run(["set", next])
  }

  function quickToggle() {
    run(["toggle"])
  }

  function reapply() {
    run(["apply"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onDesiredChanged: injectPanel()
  onAppliedChanged: injectPanel()

  Process {
    id: statusProc
    command: ["omarchy-k380-fnlock", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parsed = root.parseStatus(this.text)
        root.desired = parsed.desired
        root.applied = parsed.applied
      }
    }
  }

  // toggle / set / apply all funnel through here; any of them can change
  // hardware state, so always re-read status once the command exits.

  property string lastError: ""

  Process {
    id: cmdProc
    stdout: StdioCollector {}
    stderr: StdioCollector {
      id: cmdStderr
    }
    onExited: function(exitCode) {
      root.lastError = exitCode === 0 ? "" : cmdStderr.text.trim()
      if (exitCode !== 0)
        console.warn("K380 FnLock: command failed (" + exitCode + "): " + root.lastError)
      root.refreshStatus()
    }
  }

  // Background poll in case the mode changed elsewhere (CLI, another
  // widget instance, the udev-triggered apply on reconnect).
  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: root.refreshStatus()

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    readonly property string shown: root.applied === "on" || root.applied === "off"
      ? root.applied
      : "?"

    text: shown === "on" ? "FN" : (shown === "off" ? "fn" : "FN?")
    tooltipText: shown === "on"
      ? "K380 FnLock: Fn-keys \u2014 right-click to switch"
      : shown === "off"
        ? "K380 FnLock: Media keys \u2014 right-click to switch"
        : "K380 FnLock: not configured yet \u2014 right-click to enable Fn-keys"

    onPressed: function(buttonCode) {
      // Left = open the panel, right = quick toggle the mode.
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.quickToggle()
    }
  }
}
