import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property real buttonPadding: 5

    property Item lastHoveredButton
    property bool buttonHovered: false
    property bool requestDockShow: previewPopup.show || appMenu.visible

    // Popup takes the hovered app icon's average colour.
    readonly property string hoveredIcon: root.lastHoveredButton
        ? AppSearch.guessIcon(root.lastHoveredButton.appToplevel?.appId ?? "") : ""
    onHoveredIconChanged: AppIconColors.request(root.hoveredIcon)
    // Hovering a file manager offers its folders, the way hovering any other
    // app offers its windows.
    readonly property string hoveredAppId: String(root.lastHoveredButton?.appToplevel?.appId ?? "")
    readonly property bool hoveredIsFiles:
        /dolphin|nautilus|thunar|nemo|pcmanfm|caja|dde-file-manager|org\.gnome\.files/i.test(root.hoveredAppId)
    readonly property string folderGridMode: Config.options?.dock.folderGrid ?? "always"
    readonly property int hoveredWindowCount: root.lastHoveredButton?.appToplevel?.toplevels?.length ?? 0
    /// Whether the folder grid belongs in this hover.
    readonly property bool showFolderGrid: root.hoveredIsFiles
        && root.folderGridMode !== "off"
        && (root.folderGridMode !== "noWindows" || root.hoveredWindowCount === 0)

    readonly property color iconColor: {
        const hex = AppIconColors.colors[root.hoveredIcon] ?? "";
        return hex.length > 0 ? hex : Appearance.colors.colPrimaryContainer;
    }
    // A tonal ramp built from the icon, rather than a mix toward a container
    // colour. Mixing pulled the panel toward the icon's own LIGHTNESS, so a
    // pale icon (Dolphin's is grey-blue) produced a pale panel in a dark
    // shell; the saturated ones went muddy. Keeping the icon's hue and
    // saturation and forcing the tone gives the app's colour at full strength
    // AND a surface that always sits right in the theme.
    readonly property bool _dark: Appearance.m3colors.darkmode
    /// Hue from the icon, tone fixed, and chroma pulled WAY down. Keeping the
    /// icon's own saturation turned a soft blue icon into a navy panel; real
    /// tonal palettes give surfaces a fraction of the source's chroma so the
    /// colour reads as identity, not as paint.
    function _tone(c, lightness, chroma) {
        const q = Qt.color(c);
        return Qt.hsla(q.hslHue, Math.min(1, q.hslSaturation * chroma), lightness, 1);
    }
    readonly property color panelColor: root._tone(root.iconColor, root._dark ? 0.115 : 0.95, 0.30)
    readonly property color panelRaised: root._tone(root.iconColor, root._dark ? 0.185 : 0.88, 0.26)
    readonly property color panelText: root._tone(root.iconColor, root._dark ? 0.94 : 0.14, 0.14)
    readonly property color panelSubtext: root._tone(root.iconColor, root._dark ? 0.70 : 0.38, 0.12)

    property QtObject popupColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.iconColor, Appearance.colors.colPrimaryContainer, 0.45)
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut // why does this work
    implicitWidth: listView.implicitWidth
    
    StyledListView {
        id: listView
        spacing: 2
        orientation: ListView.Horizontal
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        implicitWidth: contentWidth

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            required property var modelData
            appToplevel: modelData
            appListRoot: root

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
        }
    }


    // One menu for the whole dock, not one per button.
    DockAppMenu { id: appMenu }
    function openMenu(button, entry) {
        appMenu.openFor(entry, button);
    }
    // Hovering a different app is a dismissal; the menu has no outside grab.
    onLastHoveredButtonChanged: appMenu.close()

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.lastHoveredButton?.appToplevel

        // Show as soon as a hovered button has windows. The old gate waited
        // for every ScreencopyView to report content, which a reused view
        // never re-signalled — that was the popup skipping hovers.
        readonly property int previewCount: previewPopup.appTopLevel?.toplevels?.length ?? 0
        property bool hovered: popupMouseArea.containsMouse || root.buttonHovered
        // A file manager is worth hovering even with nothing open.
        property bool shouldShow: previewPopup.hovered
            && (previewPopup.previewCount > 0 || root.showFolderGrid)
        property bool show: false

        onShouldShowChanged: updateTimer.restart()
        Timer {
            id: updateTimer
            interval: 100
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow
            }
        }
        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: Edges.Top | Edges.Right
            edges: Edges.Top | Edges.Left

        }
        visible: popupBackground.visible
        color: "transparent"
        implicitWidth: root.QsWindow.window?.width ?? 1
        implicitHeight: popupMouseArea.implicitHeight

        MouseArea {
            id: popupMouseArea
            anchors.bottom: parent.bottom
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            // Follows the CONTENT. It was a fixed preview-sized box, so the
            // folder grid added above the previews overflowed and was clipped.
            implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: {
                // Guarded: mapFromItem throws before the dock is in a window.
                const button = root.lastHoveredButton;
                if (!button || !root.QsWindow?.window) return 0;
                const itemCenter = root.QsWindow.mapFromItem(button, button.width / 2, 0);
                return (itemCenter?.x ?? 0) - width / 2;
            }
            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                // Rises and settles rather than only fading: a panel that
                // appears at full size reads as a different surface arriving,
                // one that grows from the dock reads as the icon's own.
                transform: Translate {
                    y: previewPopup.show ? 0 : 8
                    Behavior on y {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: root.panelColor
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                radius: Appearance.rounding.normal
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: previewColumn.implicitHeight + padding * 2
                implicitWidth: previewColumn.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    id: previewColumn
                    anchors.centerIn: parent
                    spacing: 6

                    PlacesGrid {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.margins: 4
                        visible: root.showFolderGrid
                        columns: 4
                        // A DARK scrim, not a tinted layer: the panel takes the
                        // app icon's average colour, and Dolphin's is pale, so
                        // chips derived from it vanished into the background.
                        chipColor: root.panelRaised
                        chipText: root.panelText
                    }

                RowLayout {
                    id: previewRowLayout
                    Layout.alignment: Qt.AlignHCenter
                    Repeater {
                        model: ScriptModel {
                            values: previewPopup.appTopLevel?.toplevels ?? []
                        }
                        RippleButton {
                            id: windowButton
                            required property var modelData
                            padding: 0
                            middleClickAction: () => {
                                windowButton.modelData?.close();
                            }
                            onClicked: {
                                windowButton.modelData?.activate();
                            }
                            contentItem: ColumnLayout {
                                implicitWidth: screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2
                                    WrapperRectangle {
                                        Layout.fillWidth: true
                                        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        radius: Appearance.rounding.small
                                        margin: 5
                                        StyledText {
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowButton.modelData?.title
                                            elide: Text.ElideRight
                                            color: root.panelText
                                        }
                                    }
                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        baseWidth: windowControlsHeight
                                        baseHeight: windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: root.panelText
                                        }
                                        onClicked: {
                                            windowButton.modelData?.close();
                                        }
                                    }
                                }
                                ScreencopyView {
                                    id: screencopyView
                                    // Both gated on the popup being up. live:true
                                    // captured every previewed window every
                                    // frame for the life of the popup object —
                                    // a GPU copy per window per frame, running
                                    // while nothing was on screen.
                                    //
                                    // Detaching captureSource when hidden also
                                    // forces a fresh attach on the next hover.
                                    // A delegate reused with its source still
                                    // set never re-signalled new content, which
                                    // is the hover that works once and then
                                    // shows nothing.
                                    captureSource: previewPopup.show ? windowButton.modelData : null
                                    live: previewPopup.show
                                    paintCursor: true
                                    constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: screencopyView.width
                                            height: screencopyView.height
                                            radius: Appearance.rounding.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }
}
