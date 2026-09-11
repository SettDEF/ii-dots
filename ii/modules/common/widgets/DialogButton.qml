import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Material 3 dialog button. See https://m3.material.io/components/dialogs/overview
 */
RippleButton {
    id: root

    property string buttonText
    property bool loading: false
    padding: 14
    implicitHeight: 36
    implicitWidth: (root.loading ? (spinner.implicitWidth + 6) : 0) + buttonTextWidget.implicitWidth + padding * 2
    buttonRadius: Appearance?.rounding.full ?? 9999

    property color colEnabled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colDisabled: Appearance?.m3colors.m3outline ?? "#8D8C96"
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    property alias colText: buttonTextWidget.color

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                id: spinner
                visible: root.loading
                text: "progress_activity"
                iconSize: Appearance?.font.pixelSize.small ?? 12
                color: buttonTextWidget.color
                Layout.alignment: Qt.AlignVCenter

                RotationAnimation {
                    target: spinner
                    running: root.loading
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            StyledText {
                id: buttonTextWidget
                text: buttonText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance?.font.pixelSize.small ?? 12
                color: root.enabled ? root.colEnabled : root.colDisabled

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }

}
