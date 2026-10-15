import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io

/// File name · aspect · undo/redo · Export.
Rectangle {
    id: bar
    required property var doc
    signal exportRequested()

    function fileMenu(item, x, y) {
        const d = bar.doc;
        const others = d.recents.filter(p => p !== d.dir).slice(0, 8);
        const items = [
            { icon: "folder_open", label: "Open recording folder", onTriggered: () => d.showInFolder(d.dir) },
            { icon: "movie", label: "Show exports", onTriggered: () => { if (d.lastExport.length > 0) d.reveal(d.lastExport); else d.showInFolder(d.config ? d.config.exports : d.dir); } },
            { icon: "edit", label: "Rename recording…", onTriggered: () => { renameField.text = d.dir.split("/").pop(); renamePopup.open(); } },
            { separator: true },
            { icon: "folder", label: "Open another recording…", onTriggered: () => { d.dir = ""; d.tl = null; } }
        ];
        if (others.length > 0) items.push({ icon: "history", label: "Recent", submenu: others.map(p => ({ icon: "movie", label: p.split("/").pop(), onTriggered: () => d.open(p) })) });
        items.push({ separator: true }, { icon: "settings", label: "Settings file…", onTriggered: () => d.openConfig() });
        d.menu(item, x, y, items);
    }

    /// Rename the recording folder (refuses to overwrite).
    Process {
        id: renamer
        property string target: ""
        onExited: (code) => {
            if (code === 0) {
                const old = bar.doc.dir;
                bar.doc.recents = bar.doc.recents.filter(p => p !== old);
                bar.doc.open(renamer.target);
                renamePopup.close();
            } else {
                renameError.text = code === 3 ? "A folder with that name exists" : "Could not rename";
            }
        }
    }
    Popup {
        id: renamePopup
        objectName: "renamePopup"
        x: 16; y: bar.height
        width: 360
        padding: 14
        modal: true
        focus: true
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        onOpened: { renameError.text = ""; renameField.forceActiveFocus(); renameField.selectAll(); }
        function commit() {
            const name = renameField.text.trim();
            if (name.length === 0 || name.indexOf("/") >= 0 || name === "." || name === "..") { renameError.text = "Not a valid folder name"; return; }
            const parentDir = bar.doc.dir.replace(/\/[^/]*$/, "");
            renamer.target = parentDir + "/" + name;
            renamer.command = ["sh", "-c", '[ -e "$2" ] && exit 3; mv -- "$1" "$2"', "sh", bar.doc.dir, renamer.target];
            renamer.running = true;
        }
        contentItem: ColumnLayout {
            spacing: 10
            StyledText { text: "Rename recording"; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
            MaterialTextField {
                id: renameField
                objectName: "renameField"
                Layout.fillWidth: true
                onAccepted: renamePopup.commit()
            }
            StyledText { id: renameError; visible: text.length > 0; color: Appearance.m3colors.m3error; font.pixelSize: Appearance.font.pixelSize.smaller }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                DialogButton { buttonText: "Cancel"; onClicked: renamePopup.close() }
                PrimaryActionButton { objectName: "renameOk"; buttonText: "Rename"; onClicked: renamePopup.commit() }
            }
        }
    }
    implicitHeight: 60
    color: Appearance.colors.colLayer0

    RowLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
        spacing: 14

        MaterialSymbol {
            text: "movie_edit"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colPrimary
        }
        ColumnLayout {
            id: titleBlock
            objectName: "fileTitle"
            spacing: 0
            // Right-click (or click) the name: folder, exports, rename, other recordings.
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (ev) => bar.fileMenu(titleBlock, ev.position.x, ev.position.y + 8)
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            StyledText {
                text: bar.doc.dir.split("/").filter(s => s.length > 0).pop() || "—"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: bar.doc.tl
                    ? bar.doc.tl.source.width + "×" + bar.doc.tl.source.height + " · " + bar.doc.fmt(bar.doc.duration)
                      + (bar.doc.outDuration < bar.doc.duration - 0.01 ? "  →  " + bar.doc.fmt(bar.doc.outDuration) : "")
                    : ""
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
            }
        }

        Item { Layout.fillWidth: true }

        SegmentedButtons {
            Layout.preferredWidth: 380
            segmentHeight: 34
            model: [
                { id: "auto", label: "Auto" },
                { id: "16:9", label: "16:9" },
                { id: "9:16", label: "9:16" },
                { id: "1:1", label: "1:1" },
                { id: "4:3", label: "4:3" }
            ]
            currentId: bar.doc.tl ? (bar.doc.tl.style.aspect || "auto") : "auto"
            onSelected: id => bar.doc.edit(t => t.style.aspect = id)
        }

        Item { Layout.fillWidth: true }

        RippleButton {
            implicitWidth: 38; implicitHeight: 38
            buttonRadius: Appearance.rounding.full
            enabled: bar.doc.canUndo
            onClicked: bar.doc.undo()
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: "undo"
                iconSize: Appearance.font.pixelSize.larger
                color: bar.doc.canUndo ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
            }
            StyledToolTip { text: "Undo (Ctrl+Z)" }
        }
        RippleButton {
            implicitWidth: 38; implicitHeight: 38
            buttonRadius: Appearance.rounding.full
            enabled: bar.doc.canRedo
            onClicked: bar.doc.redo()
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: "redo"
                iconSize: Appearance.font.pixelSize.larger
                color: bar.doc.canRedo ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
            }
            StyledToolTip { text: "Redo (Ctrl+Shift+Z)" }
        }

        // Autosave state: every edit is written to timeline.json (undo survives).
        RowLayout {
            objectName: "saveState"
            spacing: 4
            opacity: 0.8
            MaterialSymbol {
                text: bar.doc.saveTimer.running ? "sync" : "cloud_done"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: bar.doc.saveTimer.running ? "Saving…" : "Saved"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            implicitHeight: 40
            implicitWidth: exportRow.implicitWidth + 36
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: bar.exportRequested()
            contentItem: Item {
                // A Control sizes its contentItem, so centre the row inside one.
                RowLayout {
                id: exportRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol { text: "ios_share"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnPrimary }
                StyledText { text: "Export"; font.weight: Font.DemiBold; color: Appearance.colors.colOnPrimary }
            }
            }
        }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Appearance.colors.colLayer0Border
    }
}
