import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/// Light/dark as a picture of the result rather than two words. The mock
/// scales off its own width, so the same button works in a 500px welcome
/// screen and in a 190px panel column.
RippleButton {
    id: root
    required property bool dark

    /// Width the mock was drawn at; everything inside is a fraction of it.
    readonly property real designWidth: 250
    readonly property real u: Math.max(0.45, preview.width / designWidth)

    property color previewBg: dark
        ? ColorUtils.colorWithHueOf("#3f3838", Appearance.m3colors.m3primary)
        : ColorUtils.colorWithHueOf("#F7F9FF", Appearance.m3colors.m3primary)
    property color previewFg: dark ? Qt.lighter(previewBg, 2.2)
                                   : ColorUtils.mix(previewBg, "#292929", 0.85)

    padding: 5
    Layout.fillWidth: true
    toggled: Appearance.m3colors.darkmode === dark
    colBackground: Appearance.colors.colLayer2
    // Same selection colour as every other toggle in the shell.
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    /// What picking this side does. Overridden where the choice is staged
    /// rather than applied on the spot (the Palette panel applies on
    /// Reprocess, so switching the live theme here would be wrong).
    property var apply: mode => Quickshell.execDetached(["bash", "-c",
        `${Directories.wallpaperSwitchScriptPath} --mode ${mode} --noswitch`])
    onClicked: root.apply(root.dark ? "dark" : "light")

    contentItem: ColumnLayout {
        spacing: 4

        Rectangle {
            id: preview
            Layout.fillWidth: true
            implicitWidth: root.designWidth
            implicitHeight: skeleton.implicitHeight + 20 * root.u
            radius: root.buttonRadius - root.padding
            color: root.previewBg
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant

            ColumnLayout {
                id: skeleton
                anchors.fill: parent
                anchors.margins: 10 * root.u
                spacing: 10 * root.u

                RowLayout {
                    spacing: 8 * root.u
                    Rectangle {
                        radius: Appearance.rounding.full
                        color: root.previewFg
                        implicitWidth: 50 * root.u
                        implicitHeight: 50 * root.u
                    }
                    ColumnLayout {
                        spacing: 4 * root.u
                        Rectangle {
                            radius: Appearance.rounding.unsharpenmore
                            color: root.previewFg
                            Layout.fillWidth: true
                            implicitHeight: 22 * root.u
                        }
                        Rectangle {
                            radius: Appearance.rounding.unsharpenmore
                            color: root.previewFg
                            Layout.fillWidth: true
                            Layout.rightMargin: 45 * root.u
                            implicitHeight: 18 * root.u
                        }
                    }
                }

                StyledProgressBar {
                    Layout.topMargin: 5 * root.u
                    Layout.bottomMargin: 5 * root.u
                    Layout.fillWidth: true
                    value: 0.7
                    wavy: true
                    // Only the chosen side animates: a still mock next to a
                    // moving one says which is live without a second marker.
                    animateWave: root.toggled
                    highlightColor: root.toggled ? Appearance.m3colors.m3primary : root.previewFg
                    trackColor: ColorUtils.mix(root.previewBg, root.previewFg, 0.5)
                }

                RowLayout {
                    spacing: 2 * root.u
                    Rectangle {
                        radius: Appearance.rounding.full
                        color: root.toggled ? Appearance.m3colors.m3primary : root.previewFg
                        Layout.fillWidth: true
                        implicitHeight: 30 * root.u
                        MaterialSymbol {
                            visible: root.toggled
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "check"
                            iconSize: 20 * root.u
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                    Rectangle {
                        radius: Appearance.rounding.unsharpenmore
                        color: root.toggled ? Appearance.m3colors.m3secondaryContainer : root.previewFg
                        Layout.fillWidth: true
                        implicitHeight: 30 * root.u
                    }
                    Rectangle {
                        topLeftRadius: Appearance.rounding.unsharpenmore
                        bottomLeftRadius: Appearance.rounding.unsharpenmore
                        topRightRadius: Appearance.rounding.full
                        bottomRightRadius: Appearance.rounding.full
                        color: root.toggled ? Appearance.m3colors.m3secondaryContainer : root.previewFg
                        Layout.fillWidth: true
                        implicitHeight: 30 * root.u
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            MaterialSymbol {
                text: root.dark ? "dark_mode" : "light_mode"
                iconSize: Appearance.font.pixelSize.normal
                color: root.toggled ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: root.dark ? Translation.tr("Dark") : Translation.tr("Light")
                font.weight: root.toggled ? Font.Medium : Font.Normal
                color: root.toggled ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colOnLayer2
            }
        }
    }
}
