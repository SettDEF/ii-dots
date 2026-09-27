pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property int editingIndex: -1
    property var editEntry: ({})

    readonly property var iconOptions: ["download","music_note","piano","folder","folder_open","library_music","audio_file","queue_music","inventory_2","storage"]
    readonly property var modeOptions: ["zip", "audio"]

    ColumnLayout {
        anchors { fill: parent; margins: 14 }
        spacing: 10

        // Header
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: qsTr("Watched Folders")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
                Layout.fillWidth: true
            }
            Rectangle {
                implicitWidth: addLbl.implicitWidth + 24; implicitHeight: 32; radius: 16
                color: addHov.hovered ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                HoverHandler { id: addHov }
                TapHandler { onTapped: root._startAdd() }
                RowLayout { anchors.centerIn: parent; spacing: 4
                    MaterialSymbol { text: "add"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer0 }
                    StyledText { id: addLbl; text: qsTr("Add"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0 }
                }
            }
        }

        // Path list
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: ShelfPaths.paths

            delegate: Item {
                required property var modelData
                required property int index
                width: ListView.view.width
                implicitHeight: root.editingIndex === index ? editForm.implicitHeight + 20 : pathRow.implicitHeight + 20

                Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1; border.color: Appearance.colors.colLayer0Border

                    // View mode
                    RowLayout {
                        id: pathRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                        spacing: 10
                        visible: root.editingIndex !== index
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        Rectangle {
                            implicitWidth: 32; implicitHeight: 32; radius: 8
                            color: Appearance.colors.colLayer2
                            MaterialSymbol { anchors.centerIn: parent; text: modelData.icon ?? "folder"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colPrimary }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            StyledText { text: modelData.label ?? ""; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium; color: Appearance.colors.colOnLayer0 }
                            StyledText { text: modelData.path ?? ""; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer0; opacity: 0.4; elide: Text.ElideLeft; Layout.fillWidth: true }
                        }

                        StyledText { text: modelData.mode ?? ""; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colPrimary; opacity: 0.7 }

                        Rectangle {
                            implicitWidth: 28; implicitHeight: 28; radius: 14; color: eHov.hovered ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer2)
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            HoverHandler { margin: Appearance.sizes.touchSlop; id: eHov }
                            TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root._startEdit(index, modelData) }
                            MaterialSymbol { anchors.centerIn: parent; text: "edit"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.5 }
                        }
                        Rectangle {
                            implicitWidth: 28; implicitHeight: 28; radius: 14; color: dHov.hovered ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer2)
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            HoverHandler { margin: Appearance.sizes.touchSlop; id: dHov }
                            TapHandler { margin: Appearance.sizes.touchSlop; onTapped: ShelfPaths.remove(index) }
                            MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3error; opacity: 0.6 }
                        }
                    }

                    // Edit form
                    ColumnLayout {
                        id: editForm
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8
                        visible: root.editingIndex === index
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        ShelfPathFormFields {
                            Layout.fillWidth: true
                            entry: root.editEntry
                            onFieldEdited: e => root.editEntry = e
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 70; implicitHeight: 28; radius: 14; color: Appearance.colors.colLayer2
                                TapHandler { onTapped: root.editingIndex = -1 }
                                StyledText { anchors.centerIn: parent; text: qsTr("Cancel"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0 }
                            }
                            Rectangle {
                                implicitWidth: 70; implicitHeight: 28; radius: 14; color: Appearance.colors.colPrimary
                                TapHandler { onTapped: { ShelfPaths.update(root.editingIndex, root.editEntry); root.editingIndex = -1 } }
                                StyledText { anchors.centerIn: parent; text: qsTr("Save"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onPrimary }
                            }
                        }
                    }
                }
            }

            // Add form at bottom
            footer: Item {
                width: ListView.view.width
                implicitHeight: root.editingIndex === -2 ? addForm.implicitHeight + 20 : 0
                clip: true
                Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent; anchors.bottomMargin: 0
                    radius: Appearance.rounding.normal; color: Appearance.colors.colLayer1
                    border.width: 1; border.color: Appearance.colors.colPrimaryContainer
                    visible: root.editingIndex === -2

                    ColumnLayout {
                        id: addForm
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        StyledText { text: qsTr("New folder"); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0 }

                        ShelfPathFormFields {
                            Layout.fillWidth: true
                            entry: root.editEntry
                            onFieldEdited: e => root.editEntry = e
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 70; implicitHeight: 28; radius: 14; color: Appearance.colors.colLayer2
                                TapHandler { onTapped: root.editingIndex = -1 }
                                StyledText { anchors.centerIn: parent; text: qsTr("Cancel"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0 }
                            }
                            Rectangle {
                                implicitWidth: 70; implicitHeight: 28; radius: 14; color: Appearance.colors.colPrimary
                                TapHandler { onTapped: { ShelfPaths.add(root.editEntry); root.editingIndex = -1 } }
                                StyledText { anchors.centerIn: parent; text: qsTr("Add"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onPrimary }
                            }
                        }
                    }
                }
            }
        }
    }

    function _startEdit(index, entry) {
        editingIndex = index
        editEntry = Object.assign({}, entry)
    }

    function _startAdd() {
        editingIndex = -2
        editEntry = { label: "", path: "", icon: "folder", filter: "wav,mp3,flac", mode: "audio", extractTo: "" }
    }

    // ── Inline form fields component ──────────────────────────────────────
    component ShelfPathFormFields: ColumnLayout {
        id: formRoot
        required property var entry
        signal fieldEdited(var e)
        spacing: 6

        function _emit(key, val) {
            const e = Object.assign({}, formRoot.entry)
            e[key] = val
            formRoot.fieldEdited(e)
        }

        Repeater {
            model: [
                { key: "label",     label: "Label",      hint: "Downloads"         },
                { key: "path",      label: "Path",       hint: "/home/user/folder" },
                { key: "filter",    label: "Extensions", hint: "wav,mp3,zip"       },
                { key: "extractTo", label: "Extract to", hint: "(optional)"        },
            ]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 8
                StyledText { text: modelData.label; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.55; Layout.preferredWidth: 80 }
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: fieldIn.implicitHeight + 10
                    radius: Appearance.rounding.small; color: Appearance.colors.colLayer2
                    border.width: 1; border.color: Appearance.colors.colLayer0Border
                    TextInput {
                        id: fieldIn
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        text: formRoot.entry[modelData.key] ?? ""
                        color: Appearance.colors.colOnLayer0; font.pixelSize: Appearance.font.pixelSize.small; selectByMouse: true
                        onTextChanged: formRoot._emit(modelData.key, text)
                    }
                }
            }
        }

        // Mode selector
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            StyledText { text: "Mode"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.55; Layout.preferredWidth: 80 }
            Repeater {
                model: ["zip", "audio"]
                delegate: Rectangle {
                    required property string modelData
                    implicitWidth: modeLbl.implicitWidth + 20; implicitHeight: 28; radius: 14
                    color: formRoot.entry.mode === modelData ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    TapHandler { onTapped: formRoot._emit("mode", modelData) }
                    StyledText {
                        id: modeLbl; anchors.centerIn: parent; text: modelData
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: formRoot.entry.mode === modelData ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }
}
