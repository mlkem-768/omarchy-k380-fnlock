import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "io.github.mlkem-768.k380-fnlock"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    // Desired = what will be (re)applied on reconnect.
    // Applied = what was actually last written to the keyboard.
    // They can briefly disagree right after a click, or if the
    // receiver is unplugged.
    property string desired: ""
    property string applied: ""

    readonly property bool pending: root.desired !== "" && root.desired !== root.applied

    // ---------- Priority row model + keyboard cursor ----------
    // Same Grid-of-equal-width-pills pattern as Display's SCALE row: two
    // Button pills stretched to split the row evenly. The keyboard-cursor
    // highlight only lights up once the user has actually touched the row
    // (mouse hover or a first h/l nudge); before that the persistent
    // selection alone (each pill's own `selected`) is enough.
    readonly property var modeOptions: [
        { value: "on", label: "Fn" },
        { value: "off", label: "Media" }
    ]
    property int selectedIndex: 0
    property bool cursorActive: false

    function indexForValue(value) {
        for (var i = 0; i < modeOptions.length; i++)
            if (modeOptions[i].value === value) return i
        return -1
    }

    function moveCursorH(delta) {
        if (!root.cursorActive) {
            root.cursorActive = true
            var current = root.indexForValue(root.desired)
            root.selectedIndex = current >= 0 ? current : 0
            return
        }
        var next = root.selectedIndex + delta
        if (next < 0) next = 0
        if (next > root.modeOptions.length - 1) next = root.modeOptions.length - 1
        root.selectedIndex = next
    }

    function activateCursor() {
        if (!root.cursorActive) return
        if (root.selectedIndex < 0 || root.selectedIndex >= root.modeOptions.length) return
        if (root.hostWidget) root.hostWidget.setMode(root.modeOptions[root.selectedIndex].value)
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction)
        return false
    }

    function statusLabel(value) {
        if (value === "on") return "Fn-keys priority"
        if (value === "off") return "Media keys priority"
        return "Not configured"
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(280))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }
            onMoveRequested: function(dx, dy) { if (dx !== 0) root.moveCursorH(dx) }
            onActivateRequested: root.activateCursor()

            Column {
                id: content
                width: parent.width
                spacing: Style.space(14)

                // ---------- Hero: title + status ----------
                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "K380 FnLock"
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.title
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: root.statusLabel(root.applied).toUpperCase()
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1.2
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                // ---------- Priority ----------
                PanelSeparator {
                    foreground: root.barForeground
                }

                Column {
                    width: parent.width
                    spacing: Style.space(10)

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(priorityHeader.implicitHeight, pendingLabel.implicitHeight)

                        PanelSectionHeader {
                            id: priorityHeader
                            text: "PRIORITY"
                            foreground: root.barForeground
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Only worth mentioning while the keyboard hasn't caught up yet.
                        Text {
                            id: pendingLabel
                            textFormat: Text.PlainText
                            text: "applying…"
                            visible: root.pending
                            color: Qt.darker(root.barForeground, 1.4)
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                            font.italic: true
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(6)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Grid {
                        id: modeRow
                        width: parent.width
                        columns: root.modeOptions.length
                        spacing: Style.spacing.xs

                        readonly property real cellWidth: root.modeOptions.length > 0
                            ? (width - spacing * (columns - 1)) / columns
                            : 0

                        Repeater {
                            model: root.modeOptions

                            PriorityPill {
                                required property var modelData
                                required property int index

                                optionValue: modelData.value
                                optionLabel: modelData.label
                                optionIndex: index
                                width: modeRow.cellWidth
                            }
                        }
                    }

                    // Reapply link — only shown while desired/applied disagree, so the
                    // two priority pills stay the only controls in the common case.
                    Text {
                        textFormat: Text.PlainText
                        text: "Reapply"
                        visible: root.pending
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.underline: reapplyArea.containsMouse

                        MouseArea {
                            id: reapplyArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.hostWidget) root.hostWidget.reapply()
                        }
                    }
                }
            }
        }
    }

    component PriorityPill: Button {
        id: pill
        required property string optionValue
        required property string optionLabel
        required property int optionIndex

        text: optionLabel
        fontSize: Style.font.caption
        foreground: root.barForeground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        horizontalPadding: Style.spacing.sm
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true

        selected: root.desired === optionValue
        hasCursor: root.cursorActive && root.selectedIndex === optionIndex

        onClicked: {
            root.cursorActive = true
            root.selectedIndex = optionIndex
            if (root.hostWidget) root.hostWidget.setMode(optionValue)
        }
        onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.selectedIndex = optionIndex
        }
    }
}
