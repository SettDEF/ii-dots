// Renders the open container's rich content below the toggle grid.
// In normal mode it shows the original full UI (RogView / QuickSliders);
// in edit mode it shows the chip-grid editor where children can be
// reordered (↑↓), extracted to the main grid (↗), and new ones added
// from the "Add: …" row or by drag-dropping a tray tile onto the drawer.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight
import qs.modules.ii.cornerPopup
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: drawer
    width: parent ? parent.width : 0
    property bool editMode: false
    property string containerType: ""
    property int tabIndex: -1
    property int buttonIndex: -1

    // Preview mode: drawer was opened without a real container entry in
    // the grid — used by tray long-press for a no-commitment peek.
    // Edits aren't possible here; the editor is suppressed.
    readonly property bool _preview: drawer.buttonIndex < 0

    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    implicitHeight: bodyCol.implicitHeight + 12

    // ── Container metadata --------------------------------------------------
    function _typeName() {
        switch (drawer.containerType) {
            case "rog":              return Translation.tr("ROG")
            case "sliders":          return Translation.tr("Sliders")
            case "bluetoothDevices": return Translation.tr("Bluetooth")
            case "midi":             return Translation.tr("MIDI")
            case "phone":            return Translation.tr("Phone")
        }
        return drawer.containerType
    }
    function _typeIcon() {
        switch (drawer.containerType) {
            case "rog":              return "memory"
            case "sliders":          return "tune"
            case "bluetoothDevices": return "devices_other"
            case "midi":             return "piano"
            case "phone":            return "smartphone"
        }
        return "widgets"
    }

    // Read the container entry from config (live binding via Config).
    readonly property var containerEntry: {
        if (!Config.ready) return null
        const cfg = Config.options.sidebar.quickToggles.android
        if (drawer.tabIndex < 0) {
            return (cfg.toggles ?? [])[drawer.buttonIndex] ?? null
        }
        const tab = cfg.tabs?.[drawer.tabIndex]
        if (!tab) return null
        return (tab.toggles ?? [])[drawer.buttonIndex] ?? null
    }

    // Default child sets per container type — used when the saved entry
    // has no children field at all.
    function _defaultChildrenFor(type) {
        switch (type) {
            case "rog":
                return [{ "type": "rogProfile" }, { "type": "rogGpu" },
                        { "type": "rogBattery" }, { "type": "rogCharge" }]
            case "sliders":
                return [{ "type": "brightnessSlider" }, { "type": "volumeSlider" },
                        { "type": "micSlider" }]
        }
        return []
    }
    readonly property var children_:
        (drawer.containerEntry?.children !== undefined)
            ? drawer.containerEntry.children
            : _defaultChildrenFor(drawer.containerType)
    function _allTypes() {
        return _defaultChildrenFor(drawer.containerType).map(c => c.type)
    }
    readonly property var missingChildTypes: {
        const have = drawer.children_.map(c => c.type)
        return _allTypes().filter(t => !have.includes(t))
    }

    // ── Mutate children list ───────────────────────────────────────────────
    // Resolve the index of the container entry in `list` (PURE — does NOT
    // mutate any singleton). drawer.buttonIndex is the originally-opened
    // slot, but it can drift if the user moved or extracted other tiles in
    // the same edit session — fall back to a type lookup. In preview mode
    // (no real container in the grid yet) we lazily CREATE one so the
    // chip-grid edits aren't silently dropped.
    //
    // Returns { bi, materialised } — caller is responsible for syncing
    // OpenContainerState.buttonIndex to `bi` AFTER writing cfg.tabs so the
    // drawer's containerEntry binding never observes an intermediate state
    // where buttonIndex points at a slot that doesn't exist yet.
    function _resolveContainerIdx(list) {
        let bi = drawer.buttonIndex
        if (bi >= 0 && bi < list.length && list[bi]?.type === drawer.containerType)
            return { bi: bi, materialised: false }
        bi = list.findIndex(t => t && t.type === drawer.containerType)
        if (bi >= 0) return { bi: bi, materialised: false }
        list.push({ type: drawer.containerType, size: 3 })
        return { bi: list.length - 1, materialised: true }
    }
    function _syncOpenState(bi) {
        if (drawer.tabIndex === OpenContainerState.tabIndex
            && OpenContainerState.type === drawer.containerType
            && bi !== OpenContainerState.buttonIndex) {
            OpenContainerState.buttonIndex = bi
        }
    }
    function _writeChildren(newChildren) {
        const cfg = Config.options.sidebar.quickToggles.android
        if (drawer.tabIndex < 0) {
            const list = (cfg.toggles ?? []).slice()
            const r = _resolveContainerIdx(list)
            list[r.bi] = Object.assign({}, list[r.bi], { children: newChildren })
            cfg.toggles = list
            _syncOpenState(r.bi)
            return
        }
        if (!cfg.tabs || drawer.tabIndex >= cfg.tabs.length) return
        const tabs = cfg.tabs.slice()
        const tab  = tabs[drawer.tabIndex]
        if (!tab) return
        const list = (tab.toggles ?? []).slice()
        const r = _resolveContainerIdx(list)
        list[r.bi] = Object.assign({}, list[r.bi], { children: newChildren })
        tabs[drawer.tabIndex] = Object.assign({}, tab, { toggles: list })
        cfg.tabs = tabs
        _syncOpenState(r.bi)
    }

    function extractChild(idx) {
        const cfg = Config.options.sidebar.quickToggles.android
        const cur = drawer.children_.slice()
        if (idx < 0 || idx >= cur.length) return
        const child = cur[idx]
        cur.splice(idx, 1)
        // Atom widgets need horizontal room when standalone — render the
        // styled slider/wide-button instead of just an icon.
        const wideAtoms = ["volumeSlider","brightnessSlider","micSlider",
                           "rogProfile","rogGpu","rogBattery","rogCharge"]
        const newEntry = {
            type: child.type,
            size: wideAtoms.includes(child.type) ? 3 : 1
        }

        const list = drawer.tabIndex < 0
            ? (cfg.toggles ?? []).slice()
            : ((cfg.tabs?.[drawer.tabIndex]?.toggles ?? []).slice())

        let containerIdx = drawer.buttonIndex
        if (!(containerIdx >= 0 && containerIdx < list.length && list[containerIdx]?.type === drawer.containerType)) {
            containerIdx = list.findIndex(t => t && t.type === drawer.containerType)
        }

        if (containerIdx >= 0) {
            list[containerIdx] = Object.assign({}, list[containerIdx], { children: cur })
            list.splice(containerIdx + 1, 0, newEntry)
        } else {
            // Preview mode: container tile itself is not in the active grid.
            // Just append the extracted child standalone!
            list.push(newEntry)
        }

        if (drawer.tabIndex < 0) {
            cfg.toggles = list
        } else {
            const tabs = cfg.tabs.slice()
            const tab  = tabs[drawer.tabIndex]
            if (tab) {
                tabs[drawer.tabIndex] = Object.assign({}, tab, { toggles: list })
                cfg.tabs = tabs
            }
        }

        if (containerIdx >= 0) {
            _syncOpenState(containerIdx)
        }
    }
    function moveChild(from, to) {
        if (drawer._preview) return
        if (from === to) return
        const cur = drawer.children_.slice()
        if (from < 0 || from >= cur.length || to < 0 || to >= cur.length) return
        const [item] = cur.splice(from, 1)
        cur.splice(to, 0, item)
        _writeChildren(cur)
    }
    function addChild(type) {
        if (drawer._preview) return
        const cur = drawer.children_.slice()
        if (cur.find(c => c.type === type)) return
        cur.push({ type: type })
        _writeChildren(cur)
    }

    // Drop-from-tray accept: only types that belong inside this container
    // and aren't already in it.
    readonly property bool dragAccepted:
        QuickToggleDragState.active &&
        drawer.editMode &&
        drawer._allTypes().includes(QuickToggleDragState.sourceType) &&
        !(drawer.children_.map(c => c.type)
                          .includes(QuickToggleDragState.sourceType))

    // ── Body ───────────────────────────────────────────────────────────────
    ColumnLayout {
        id: bodyCol
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: drawer._typeIcon()
                iconSize: 22
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: drawer._typeName()
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: closeHov.hovered
                    ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colLayer2
                HoverHandler { id: closeHov }
                TapHandler { onTapped: OpenContainerState.close() }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"; iconSize: 14
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // Body — Loader picks the right component per (type, editMode).
        // Preview mode (buttonIndex < 0) bypasses the editor since edits
        // can't be persisted without a real container entry.
        Loader {
            id: contentLoader
            Layout.fillWidth: true
            asynchronous: false   // load in one frame so the drawer doesn't pop
            sourceComponent: {
                switch (drawer.containerType) {
                    case "rog":     return (drawer.editMode && !drawer._preview) ? drawer.editorComp : drawer.rogGridComp
                    case "sliders": return (drawer.editMode && !drawer._preview) ? drawer.editorComp : drawer.qsViewComp
                    case "bluetoothDevices": return drawer.btViewComp
                    case "midi":    return drawer.midiViewComp
                    case "phone":   return drawer.phoneViewComp
                }
                return null
            }
        }
    }

    // ── Components ─────────────────────────────────────────────────────────
    property Component qsViewComp:    Component { QuickSliders {} }
    property Component btViewComp:    Component { DevicesView { popupRounding: Appearance.rounding.normal; isSidebar: true } }
    property Component midiViewComp:  Component { MidiView           { popupRounding: Appearance.rounding.normal; isSidebar: true } }
    property Component phoneViewComp: Component { PhoneCard {} }

    // ROG grid — children rendered as the original RogView styling.
    // 2 columns wide, wraps to multiple rows for many children.  In
    // edit mode each tile gets a × overlay (extract) and ↔ arrows
    // (reorder).
    property Component rogGridComp: Component {
        Grid {
            id: rogGrid
            columns: 2
            spacing: 6
            width: parent ? parent.width : 0

            Repeater {
                model: drawer.children_

                delegate: Item {
                    id: cell
                    required property int index
                    required property var modelData
                    width: (rogGrid.width - rogGrid.spacing) / rogGrid.columns
                    height: 56

                    HoverHandler { id: cellHov }

                    // The actual styled widget (Profile slider / WideBtn).
                    // Disabled in edit mode so the rog atom can't grab
                    // presses meant for the action chips.
                    Loader {
                        id: cellWidget
                        anchors.fill: parent
                        enabled: !drawer.editMode
                        sourceComponent: {
                            switch (cell.modelData.type) {
                                case "rogProfile": return profileComp
                                case "rogGpu":     return gpuComp
                                case "rogBattery": return batteryComp
                                case "rogCharge":  return chargeComp
                            }
                            return null
                        }
                    }

                    // Edit-mode action overlay. Chips fade in on hover.
                    ContainerChildActions {
                        anchors.fill: parent
                        visible: drawer.editMode
                        style: "grid"
                        revealOnHover: true
                        parentHovered: cellHov.hovered
                        index: cell.index
                        totalCount: drawer.children_.length
                        allowReorder: !drawer._preview
                        onMoveBack:    drawer.moveChild(cell.index, cell.index - 1)
                        onMoveForward: drawer.moveChild(cell.index, cell.index + 1)
                        onExtract:     drawer.extractChild(cell.index)
                    }
                }
            }

            // Per-child render components
            Component {
                id: profileComp
                RogProfileSwitcher {}
            }
            Component {
                id: gpuComp
                RogWideBtn {
                    iconName:   "memory"
                    label:      Translation.tr("GPU")
                    statusText: Rog.gpuMode === "AsusMuxDiscreet" ? "dGPU" : Rog.gpuMode
                    toggled:    Rog.gpuMode !== "Integrated"
                    onTap: {
                        const m = ["Integrated","Hybrid","AsusMuxDiscreet"]
                        const i = Math.max(0, m.indexOf(Rog.gpuMode))
                        Rog.setGpuMode(m[(i + 1) % m.length])
                    }
                }
            }
            Component {
                id: batteryComp
                RogWideBtn {
                    iconName:   "battery_saver"
                    label:      Translation.tr("Battery")
                    statusText: Rog.batteryLimit + "%"
                    toggled:    Rog.batteryLimit < 100
                    onTap: {
                        const stops = [80, 90, 100]
                        let i = stops.indexOf(Rog.batteryLimit)
                        if (i < 0) i = stops.length - 1
                        Rog.setBatteryLimit(stops[(i + 1) % stops.length])
                    }
                }
            }
            Component {
                id: chargeComp
                RogWideBtn {
                    iconName:   "bolt"
                    label:      Translation.tr("Charge")
                    statusText: ["Default","Balanced","Full"][Rog.chargeMode] ?? "Default"
                    toggled:    Rog.chargeMode > 0
                    onTap: Rog.setChargeMode((Rog.chargeMode + 1) % 3)
                }
            }
        }
    }

    // Shared edit-mode chip list, used by both ROG and Sliders.
    property Component editorComp: Component {
        ColumnLayout {
            spacing: 6

            // Add-back chips for missing types
            Item {
                Layout.fillWidth: true
                implicitHeight: 28
                visible: drawer.missingChildTypes.length > 0
                RowLayout {
                    anchors.fill: parent
                    spacing: 4
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Add:")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                    Repeater {
                        model: drawer.missingChildTypes
                        delegate: Rectangle {
                            id: addChip
                            required property var modelData
                            readonly property string chipType: modelData
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 24
                            implicitWidth: addRow.implicitWidth + 16
                            radius: 12
                            color: addHov.hovered
                                ? Qt.alpha(Appearance.colors.colPrimary, 0.18)
                                : Appearance.colors.colLayer2
                            HoverHandler { id: addHov }
                            TapHandler { onTapped: drawer.addChild(addChip.chipType) }
                            RowLayout {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: drawer._iconFor(addChip.chipType)
                                    iconSize: 14
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: drawer._labelFor(addChip.chipType)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            Repeater {
                model: drawer.children_
                delegate: Rectangle {
                    id: childRow
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Appearance.rounding.normal
                    color: rowHov.hovered
                        ? Appearance.colors.colLayer2Hover
                        : Appearance.colors.colLayer2
                    HoverHandler { id: rowHov }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: drawer._iconFor(childRow.modelData.type)
                            iconSize: 18
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            text: drawer._labelFor(childRow.modelData.type)
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: Font.DemiBold
                        }
                        ContainerChildActions {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 84   // 3 chips × 22 + 2 gaps
                            Layout.preferredHeight: 24
                            style: "row"
                            revealOnHover: false        // list shows them always
                            index: childRow.index
                            totalCount: drawer.children_.length
                            onMoveBack:    drawer.moveChild(childRow.index, childRow.index - 1)
                            onMoveForward: drawer.moveChild(childRow.index, childRow.index + 1)
                            onExtract:     drawer.extractChild(childRow.index)
                        }
                    }
                }
            }
        }
    }

    // Per-type label / icon helpers
    function _iconFor(type) {
        switch (type) {
            case "rogProfile":       return "speed"
            case "rogGpu":           return "memory"
            case "rogBattery":       return "battery_saver"
            case "rogCharge":        return "bolt"
            case "volumeSlider":     return "volume_up"
            case "brightnessSlider": return "brightness_6"
            case "micSlider":        return "mic"
        }
        return "widgets"
    }
    function _labelFor(type) {
        switch (type) {
            case "rogProfile":       return Translation.tr("Profile")
            case "rogGpu":           return Translation.tr("GPU")
            case "rogBattery":       return Translation.tr("Battery")
            case "rogCharge":        return Translation.tr("Charge")
            case "volumeSlider":     return Translation.tr("Volume")
            case "brightnessSlider": return Translation.tr("Brightness")
            case "micSlider":        return Translation.tr("Mic")
        }
        return type
    }

    // Drop overlay — drag a tile from the tray onto the drawer to add it.
    Rectangle {
        anchors.fill: parent
        z: 50
        visible: drawer.dragAccepted
        radius: parent.radius
        color: dropHov.hovered
            ? Qt.alpha(Appearance.colors.colPrimary, 0.20)
            : Qt.alpha(Appearance.colors.colPrimary, 0.08)
        border.width: 2
        border.color: dropHov.hovered
            ? Appearance.colors.colPrimary
            : Qt.alpha(Appearance.colors.colPrimary, 0.4)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler {
            id: dropHov
            onHoveredChanged: {
                if (!QuickToggleDragState.active) return
                if (hovered) {
                    QuickToggleDragState.dropContainerTab   = drawer.tabIndex
                    QuickToggleDragState.dropContainerIndex = drawer.buttonIndex
                } else if (QuickToggleDragState.dropContainerTab === drawer.tabIndex
                           && QuickToggleDragState.dropContainerIndex === drawer.buttonIndex) {
                    QuickToggleDragState.dropContainerTab   = -2
                    QuickToggleDragState.dropContainerIndex = -2
                }
            }
        }
        StyledText {
            anchors.centerIn: parent
            text: dropHov.hovered
                ? Translation.tr("Drop to add to %1").arg(drawer._typeName())
                : Translation.tr("Drag here to add to %1").arg(drawer._typeName())
            color: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
        }
    }
}
