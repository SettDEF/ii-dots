pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects

/**
 * The copy card, as pure UI: everything it shows comes in through properties
 * and everything it does goes out through signals, so it can be rendered
 * with test data (no clipboard, no window).
 *
 *   ┌──────────────────────────────────────────┐
 *   │ [ wide preview — pictures and videos ]   │
 *   │ ▣  Copied file                      ✕    │
 *   │    name / text / link                    │
 *   │ (Open) (Folder) (Xperia 1 IV) (Edit)     │
 *   └──────────────────────────────────────────┘
 *
 * Sharing is inline: each reachable phone is one chip in the action row,
 * instead of a second sheet floating above the card.
 */
Rectangle {
    id: root

    /// "text" | "link" | "image" | "file"
    property string kind: "text"
    property string text: ""            // copied text (preview), or the link
    property string imageSource: ""     // copied image, or a file's picture / video still
    property string filePath: ""
    property bool fileIsDir: false
    property bool fileIsVideo: false
    property var devices: []            // reachable KDE Connect devices
    property bool editing: false

    signal openRequested()
    signal folderRequested()
    signal saveRequested()
    signal sendRequested(string deviceId)
    signal editRequested()
    /// an image: open it in the screenshot editor
    signal markupRequested()
    signal editCommitted(string text)
    signal editCancelled()
    signal closeRequested()
    signal shareRequested()
    signal pinToggled()
    /// kept open (no timer) until closed
    property bool pinned: false

    function setEditText(t) { editor.text = t; editor.forceActiveFocus(); editor.selectAll(); }

    readonly property string fileName: filePath.replace(/\/+$/, "").split("/").pop() || "/"
    readonly property string fileExt: fileName.includes(".") ? fileName.split(".").pop().toLowerCase() : ""
    readonly property string fileFolder: {
        const parts = filePath.replace(/\/+$/, "").split("/").filter(p => p.length > 0);
        return parts.length > 1 ? parts[parts.length - 2] : "/";
    }
    readonly property bool wide: imageSource.length > 0 && !editing

    implicitWidth: 340
    implicitHeight: col.implicitHeight + 24
    radius: Appearance.rounding.large
    // Raw M3 role, not colLayer*: those go through contentTransparency and
    // let the app behind show through.
    color: Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    function _icon() {
        if (kind === "link") return "link";
        if (kind === "image") return "image";
        if (kind === "text") return "content_paste";
        if (fileIsDir) return "folder";
        if (fileIsVideo) return "movie";
        const e = fileExt;
        if (["png","jpg","jpeg","webp","gif","bmp","svg"].includes(e)) return "image";
        if (["mp3","wav","flac","ogg","opus","m4a","aiff","aif"].includes(e)) return "audio_file";
        if (["zip","rar","7z","tar","gz","bz2","xz","zst"].includes(e)) return "folder_zip";
        if (e === "pdf") return "picture_as_pdf";
        if (["qml","js","ts","rs","py","sh","c","cpp","h","lua","go","java"].includes(e)) return "code";
        if (["txt","md","json","toml","yaml","yml","ini","conf","log","csv"].includes(e)) return "description";
        return "draft";
    }
    function _title() {
        if (editing) return Translation.tr("Edit and copy again");
        if (kind === "link") return Translation.tr("Copied link");
        if (kind === "image") return Translation.tr("Copied image");
        if (kind === "file") return fileIsDir ? Translation.tr("Copied folder") : Translation.tr("Copied file");
        return Translation.tr("Copied text");
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── wide preview: pictures and video stills ──
        Rectangle {
            id: previewBox
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(170, Math.max(90, width * pic.aspect)) : 0
            visible: root.wide && pic.status !== Image.Error
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHighest
            // clip only cuts square; the mask gives the picture the rounded corners.
            layer.enabled: visible
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: previewBox.width
                    height: previewBox.height
                    radius: previewBox.radius
                }
            }
            Image {
                id: pic
                readonly property real aspect: implicitWidth > 0 ? implicitHeight / implicitWidth : 0.56
                anchors.fill: parent
                source: root.wide ? root.imageSource : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: 640
            }
            MaterialSymbol {
                visible: root.fileIsVideo && pic.status === Image.Ready
                anchors.centerIn: parent
                text: "play_circle"
                fill: 1
                iconSize: 40
                color: "white"
                opacity: 0.85
            }
        }

        // ── what was copied ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3primaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root._icon()
                    fill: 1
                    iconSize: 22
                    color: Appearance.m3colors.m3onPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root._title()
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }
                // file: name + folder
                StyledText {
                    Layout.fillWidth: true
                    visible: root.kind === "file" && !root.editing
                    text: root.fileName
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
                RowLayout {
                    visible: root.kind === "file" && !root.editing
                    Layout.fillWidth: true
                    spacing: 3
                    MaterialSymbol { text: "folder"; iconSize: 13; color: Appearance.colors.colSubtext }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.fileFolder
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // pin · pop out · share · close, together in a pill
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: hdrRow.implicitWidth + 8
                implicitHeight: 32
                radius: 16
                color: Appearance.colors.colLayer2
                Row {
                    id: hdrRow
                    anchors.centerIn: parent
                    spacing: 0
                    HdrBtn { icon: "keep"; on: root.pinned; tip: root.pinned ? Translation.tr("Pinned: stays until closed") : Translation.tr("Pin: keep it open"); onHit: root.pinToggled() }
                    // out into a window of its own: the text in zett, a file or link opened
                    HdrBtn {
                        visible: root.kind !== "image"
                        icon: "open_in_new"
                        tip: root.kind === "text" ? Translation.tr("Open in zett") : Translation.tr("Open")
                        onHit: {
                            if (root.kind === "text") { Quickshell.execDetached([Quickshell.env("HOME") + "/.scripts/apps/zett/zett-edit"]); root.closeRequested(); }
                            else root.openRequested();
                        }
                    }
                    HdrBtn { visible: !root.editing; icon: "ios_share"; tip: Translation.tr("Share (Super+Shift+U)"); onHit: root.shareRequested() }
                    HdrBtn { icon: "close"; tip: Translation.tr("Close"); onHit: root.closeRequested() }
                }
            }
        }

        // text / link: the content itself, the card's full width under the header row
        StyledText {
            Layout.fillWidth: true
            visible: (root.kind === "text" || root.kind === "link") && !root.editing
            text: root.text
            wrapMode: root.kind === "link" ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: root.kind === "link" ? 1 : 4
            elide: root.kind === "link" ? Text.ElideMiddle : Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3onSurfaceVariant
        }

        // ── editor (text only) ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            visible: root.editing
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainerHighest
            border.width: editor.activeFocus ? 2 : 0
            border.color: Appearance.m3colors.m3primary
            StyledFlickable {
                id: flick
                anchors { fill: parent; margins: 8 }
                contentHeight: editor.implicitHeight
                clip: true
                TextEdit {
                    id: editor
                    width: flick.width
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.main
                    color: Appearance.m3colors.m3onSurface
                    selectByMouse: true
                    selectionColor: Appearance.colors.colPrimary
                    selectedTextColor: Appearance.colors.colOnPrimary
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y < flick.contentY) flick.contentY = cursorRectangle.y;
                        else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                            flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height;
                    }
                    Keys.onEscapePressed: root.editCancelled()
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && (event.modifiers & Qt.ControlModifier)) {
                            root.editCommitted(editor.text);
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        // ── actions ──
        // one row: past three chips the secondary ones fold to their icons
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            readonly property bool dense: visibleChildren.length > 3
            layoutDirection: Qt.LeftToRight

            ToastChip {
                visible: root.editing
                icon: "check"; label: Translation.tr("Copy"); primary: true
                tip: Translation.tr("Ctrl+Enter")
                onActivated: root.editCommitted(editor.text)
            }
            ToastChip {
                visible: root.editing
                icon: "undo"; label: Translation.tr("Cancel")
                tip: Translation.tr("Esc")
                onActivated: root.editCancelled()
            }

            ToastChip {
                visible: !root.editing && (root.kind === "link" || root.kind === "file")
                icon: "open_in_new"; label: Translation.tr("Open"); primary: true
                onActivated: root.openRequested()
            }
            ToastChip {
                visible: !root.editing && root.kind === "file"
                icon: "folder_open"; label: Translation.tr("Folder")
                tip: Translation.tr("Show in folder")
                onActivated: root.folderRequested()
            }
            ToastChip {
                visible: !root.editing && root.kind === "image"
                icon: "draw"; label: Translation.tr("Edit")
                tip: Translation.tr("Mark it up in the editor")
                onActivated: root.markupRequested()
            }
            ToastChip {
                visible: !root.editing && root.kind === "image"
                icon: "download"; label: Translation.tr("Save"); primary: true
                tip: "~/Pictures/Clipboard"
                onActivated: root.saveRequested()
            }
            Repeater {
                model: root.editing || (root.kind === "file" && root.fileIsDir) ? [] : root.devices
                delegate: ToastChip {
                    required property var modelData
                    icon: "send_to_mobile"
                    label: modelData.name ?? "Phone"
                    tip: Translation.tr("Send to %1").arg(modelData.name ?? "phone")
                    onActivated: root.sendRequested(modelData.id)
                }
            }
            ToastChip {
                visible: !root.editing && (root.kind === "text" || root.kind === "link")
                icon: "edit"; label: Translation.tr("Edit")
                onActivated: root.editRequested()
            }
            // the whole text in zett, each save back on the clipboard (zett-edit)
            ToastChip {
                visible: !root.editing && root.kind === "text"
                icon: "edit_note"; label: "zett"
                tip: Translation.tr("Edit it in zett (Super+Shift+E)")
                onActivated: { Quickshell.execDetached([Quickshell.env("HOME") + "/.scripts/apps/zett/zett-edit"]); root.closeRequested(); }
            }
        }
    }
}
