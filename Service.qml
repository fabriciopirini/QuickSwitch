import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "logic.js" as Logic

Item {
    id: root

    readonly property string shortAppId: "pirini.cmd-tab"

    property bool open: false
    property var windows: []  // one entry per app, in cycle order
    property int selected: 0
    property bool sawKeyEvent: false
    property bool modsHeld: false
    property string pendingAddr: ""
    property real lastRefreshTime: 0
    // Tile and icon size (logical px) of one app in the strip.
    readonly property int tileSize: 128
    readonly property int iconSize: 96

    // Hyprland bridge. The bindings in ~/.config/hypr/bindings.lua only route
    // SUPER+TAB here while cmdtab_loaded is set (otherwise the Omarchy
    // default "Next workspace" applies), and all in-switcher keys live in the
    // "cmdtab" submap, which is only active while the strip is open. That
    // keeps SUPER+Q/arrows untouched outside the switcher.
    readonly property string leaveSubmap:
        'if hl.get_current_submap() == "cmdtab" then hl.dispatch(hl.dsp.submap("reset")) end'

    function hlEval(code) { Quickshell.execDetached(["hyprctl", "eval", code]) }
    function announce() { hlEval('cmdtab_loaded = true; ' + leaveSubmap) }

    Component.onCompleted: announce()
    Component.onDestruction: hlEval('cmdtab_loaded = false; ' + leaveSubmap)

    onOpenChanged: {
        if (open) Hyprland.dispatch('hl.dsp.submap("cmdtab")')
        else hlEval(leaveSubmap)
    }

    function next() { if (windows.length) selected = (selected + 1) % windows.length }
    function prev() { if (windows.length) selected = (selected + windows.length - 1) % windows.length }

    function openSwitcher() {
        console.log("[task-switch] openSwitcher called")
        clientsProc.running = true
    }

    function close(doFocus) {
        if (!open) return
        const entry = (doFocus && windows.length) ? windows[selected] : null
        console.log("[task-switch] close focus=", doFocus, "sel=", selected, entry ? entry.cls : "-")
        open = false
        if (!entry) return
        pendingAddr = entry.address
        focusTimer.start()
    }

    Timer {
        id: focusTimer
        interval: 110
        onTriggered: {
            if (root.pendingAddr) {
                // Floating windows stay under their siblings on focus alone; raise the target too.
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.pendingAddr + '" })')
                Hyprland.dispatch('hl.dsp.window.bring_to_top({ window = "address:' + root.pendingAddr + '" })')
            }
            root.pendingAddr = ""
        }
    }

    // SUPER+Q quits the highlighted app (every window of it) but keeps the
    // switcher open (SUPER is still held). We close via the Lua dispatcher
    // (matches Omarchy's own close-all helper) and then re-fetch the app list so
    // the quit app disappears; focus is only switched on SUPER release.
    function quitSelected() {
        const entry = windows.length ? windows[selected] : null
        if (!entry || !entry.addresses.length) return
        console.log("[task-switch] quitSelected cls=", entry.cls, "windows=", entry.addresses.length)
        root.lastRefreshTime = Date.now()
        for (const addr of entry.addresses)
            Quickshell.execDetached(["hyprctl", "dispatch",
                'hl.dsp.window.close({ window = "address:' + addr + '" })'])
        refreshAfterQuit.restart()
    }

    // Keep the overlay mounted (open stays true) and refresh the list.
    Timer {
        id: refreshAfterQuit
        interval: 220
        onTriggered: {
            if (root.open) root.openSwitcher()
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // A config reload recreates the Lua state; re-announce.
            if (event.name === "configreloaded") root.announce()
        }
    }

    GlobalShortcut {
        appid: root.shortAppId
        name: "next"
        onPressed: {
            if (root.open) {
                root.sawKeyEvent = true
                root.modsHeld = true
                root.next()
            } else {
                root.openSwitcher()
            }
        }
    }

    // In-switcher keys. These are bound only inside the "cmdtab" submap
    // (see bindings.lua), so they never shadow the normal SUPER bindings.
    function stepFromKey(forward) {
        if (!root.open) return
        root.sawKeyEvent = true
        root.modsHeld = true
        if (forward) root.next(); else root.prev()
    }

    GlobalShortcut { appid: root.shortAppId; name: "prev"; onPressed: root.stepFromKey(false) }
    GlobalShortcut { appid: root.shortAppId; name: "focus-left"; onPressed: root.stepFromKey(false) }
    GlobalShortcut { appid: root.shortAppId; name: "focus-up"; onPressed: root.stepFromKey(false) }
    GlobalShortcut { appid: root.shortAppId; name: "focus-right"; onPressed: root.stepFromKey(true) }
    GlobalShortcut { appid: root.shortAppId; name: "focus-down"; onPressed: root.stepFromKey(true) }

    // SUPER+Q inside the switcher. As a SUPER-bound shortcut it cannot fire
    // from a plain Q press, and the user's global SUPER+Q (close focused
    // window) is inactive while the submap is on.
    GlobalShortcut {
        appid: root.shortAppId
        name: "quit"
        onPressed: if (root.open) root.quitSelected()
    }

    GlobalShortcut {
        appid: root.shortAppId
        name: "cancel"
        onPressed: root.close(false)
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let clients = []
                try { clients = JSON.parse(text) } catch (e) { return }
                fillWindows(clients)
            }
        }
    }

    function fillWindows(clients) {
        console.log("[task-switch] fillWindows called, n=", Array.isArray(clients) ? clients.length : "not-array")
        if (!Array.isArray(clients)) return
        const apps = Logic.groupByApp(Logic.orderClients(clients))
        if (!apps.length) return

        root.windows = apps
        root.selected = 0
        root.sawKeyEvent = false
        root.modsHeld = false
        root.open = true
    }

    function iconPathFor(cls, title) {
        return Logic.iconPathFor(DesktopEntries, Quickshell, cls, title)
    }

    function appNameFor(cls) {
        return Logic.appNameFor(DesktopEntries, cls)
    }

    LazyLoader {
        id: loader
        active: root.open
        PanelWindow {
            id: panel

                property bool mouseInside: true
                property bool hoverArmed: false
                property point initialPos: Qt.point(-1, -1)

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.namespace: root.shortAppId
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors { top: true; bottom: true; left: true; right: true }

                // Show the overlay only once SUPER is held for a moment, so a
                // quick SUPER+TAB tap switches straight to the previous app
                // without a flash (macOS Cmd+Tab behavior). The surface is
                // mapped right away, so the keyboard grab is active anyway.
                property bool shown: false
                Timer {
                    interval: 150
                    running: true
                    onTriggered: panel.shown = true
                }

                // A strip appearing under a resting pointer gets a synthetic
                // hover enter; that must not override the MRU selection. Hover
                // only counts after the pointer has actually moved.
                onHoverArmedChanged: if (hoverArmed) mouseInside = stripHover.hovered

                function trackPointer(p) {
                    if (hoverArmed) return
                    if (initialPos.x < 0) initialPos = Qt.point(p.x, p.y)
                    else if (Math.abs(p.x - initialPos.x) + Math.abs(p.y - initialPos.y) > 4) hoverArmed = true
                }

                function activate() { root.close(panel.mouseInside) }

                Timer {
                    id: noKeyTimer
                    interval: 150
                    repeat: true
                    running: true
                    // Poll SUPER for as long as the strip is open (not just
                    // until the first key event), so a missed release event
                    // can never leave the exclusive keyboard grab stuck. A
                    // failing hyprctl also closes the strip.
                    onTriggered: {
                        if (root.sawKeyEvent && !root.modsHeld) panel.activate()
                        else modCheck.running = true
                    }
                }

                Process {
                    id: modCheck
                    command: ["hyprctl", "eval",
                        'error(tostring(hl.is_key_down("Super_L") or hl.is_key_down("Super_R")))']
                    stdout: StdioCollector {
                        onStreamFinished: {
                            if (!root.open) return
                            if (Date.now() - root.lastRefreshTime < 300) return
                            if (!text.trim().endsWith("true"))
                                panel.activate()
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Color.menu.scrim
                    opacity: panel.shown ? 1 : 0

                    HoverHandler {
                        onPointChanged: panel.trackPointer(point.scenePosition)
                    }
                }

                // Clicking empty space dismisses without switching focus.
                MouseArea {
                    anchors.fill: parent
                    enabled: panel.shown
                    onClicked: root.close(false)
                }

                // Centered horizontal strip (macOS app-switcher style).
                Item {
                    id: stripWrap
                    anchors.centerIn: parent
                    width: strip.width
                    height: strip.height
                    focus: true
                    opacity: panel.shown ? 1 : 0
                    Keys.priority: Keys.BeforeItem

                    BorderSurface {
                        id: stripBg
                        anchors.fill: strip
                        radius: Style.cornerRadius
                        color: Color.popups.background
                        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 2)
                    }

                    Flow {
                        id: strip
                        anchors.centerIn: parent
                        padding: Style.spacing.panelPadding
                        spacing: Style.spacing.panelPadding
                        z: 2

                        readonly property real contentWidth: {
                            const n = root.windows.length
                            if (!n) return 0
                            const spacing = Style.spacing.panelPadding
                            const tileW = root.tileSize
                            const maxTiles = Math.floor((panel.width * 0.85 - 2 * padding + spacing) / (tileW + spacing))
                            return 2 * padding + Math.min(n, maxTiles) * tileW + Math.max(0, Math.min(n, maxTiles) - 1) * spacing
                        }
                        width: contentWidth

                        Repeater {
                            model: root.windows

                            delegate: Item {
                                required property int index
                                readonly property var win: root.windows[index]
                                readonly property bool isSelected: root.selected === index
                                readonly property bool hovered: hover.hovered && panel.hoverArmed
                                // Also fires when hover gets armed while the
                                // pointer already rests on this tile.
                                onHoveredChanged: if (hovered) root.selected = index

                                width: root.tileSize
                                height: root.tileSize

                                // Omarchy selection affordance: the menu's selected
                                // fill and border behind the highlighted app.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.cornerRadius
                                    color: isSelected ? Color.menu.selectedBackground : "transparent"
                                    border.width: isSelected ? 2 : 0
                                    border.color: Color.menu.selectedBorder
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: root.iconSize
                                    height: root.iconSize
                                    sourceSize.width: root.iconSize
                                    sourceSize.height: root.iconSize
                                    fillMode: Image.PreserveAspectFit
                                    source: win ? root.iconPathFor(win.cls, win.title) : ""
                                }

                                HoverHandler {
                                    id: hover
                                    onPointChanged: panel.trackPointer(point.scenePosition)
                                }

                                TapHandler {
                                    enabled: panel.shown
                                    onTapped: {
                                        root.selected = index
                                        root.close(true)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: titleLabel
                        anchors.horizontalCenter: strip.horizontalCenter
                        anchors.top: strip.bottom
                        anchors.topMargin: Style.spacing.xl
                        width: Math.min(strip.width, 640)
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: root.windows.length ? root.appNameFor(root.windows[root.selected].cls) : ""
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.heading
                        font.weight: Font.DemiBold
                    }

                    // Keyboard navigation. The exclusive keyboard grab keeps
                    // keyboard events flowing here while SUPER is held. Any key
                    // reaching here means SUPER is still held (otherwise the
                    // release/noKeyTimer path would have already closed it), so
                    // mark the modifier as held for every key press.
                    Keys.onPressed: (event) => {
                        root.sawKeyEvent = true
                        root.modsHeld = true
                        if (event.key === Qt.Key_Escape) {
                            root.close(false)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                            root.next()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                            root.prev()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            panel.activate()
                            event.accepted = true
                        }
                    }

                    Keys.onReleased: (event) => {
                        root.sawKeyEvent = true
                        const superReleasing = event.key === Qt.Key_Meta
                            || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
                        // event.modifiers is NOT reliably set through the
                        // exclusive grab (see the onPressed handler), so it
                        // must not gate closing. Releasing a non-SUPER key
                        // (Q, TAB, arrows) while the grab is active means
                        // SUPER is still held — keep the switcher open. Only
                        // an actual SUPER key release closes it.
                        if (superReleasing) {
                            // Closing a window can briefly disrupt the keyboard
                            // grab and deliver a synthetic SUPER release; ignore
                            // it right after a quit so the strip survives.
                            if (Date.now() - root.lastRefreshTime < 200) return
                            root.modsHeld = false
                            panel.activate()
                        } else {
                            root.modsHeld = true
                        }
                    }

                    HoverHandler {
                        id: stripHover
                        onPointChanged: panel.trackPointer(point.scenePosition)
                        onHoveredChanged: if (panel.hoverArmed) panel.mouseInside = hovered
                    }

                    Component.onCompleted: forceActiveFocus()
                }
            }
    }
}
