// Standalone "performance switcher" — extracted from RogView so it can
// also be used as a child widget inside the ROG container drawer.
// Default state shows a pill-shaped track with a circular thumb at left,
// "Profile / <name>" text alongside.  Tap the thumb to enter slider
// mode; drag the thumb (or tap a dot) to set the profile.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: track
    property real pad: 2
    property real btnH: 56
    // Works whether placed in a Layout (fillWidth) or a positioner like
    // Grid (parent-bound width).
    Layout.fillWidth: true
    width: parent ? parent.width : 0
    height: btnH
    implicitHeight: btnH
    radius: btnH / 2
    // No outer gray pill — the thumb carries the accent.
    color: "transparent"

    readonly property int  profileIndex: Rog.profiles.indexOf(Rog.profile)
    readonly property bool isPerf: Rog.profile === "Performance"
    readonly property color colFg: Appearance.colors.colOnLayer2
    property bool selectMode: false

    function iconFor(name) {
        if (name === "Quiet")       return "bedtime"
        if (name === "Balanced")    return "balance"
        if (name === "Performance") return "speed"
        return "speed"
    }

    readonly property real thumbDiameter: height - pad * 2
    readonly property real availW: width - pad * 2 - thumbDiameter
    readonly property real leftRestX: pad
    readonly property var stops: {
        const n = Rog.profiles.length
        if (n <= 1) return [leftRestX + thumbDiameter / 2]
        const out = []
        for (let i = 0; i < n; i++) {
            out.push(leftRestX + thumbDiameter / 2 + availW * (i / (n - 1)))
        }
        return out
    }

    // Default-state label
    ColumnLayout {
        anchors {
            left: profileThumb.right
            leftMargin: 10
            right: parent.right
            rightMargin: track.pad + 4
            verticalCenter: parent.verticalCenter
        }
        spacing: -2
        opacity: track.selectMode ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        StyledText {
            text: Translation.tr("Profile")
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: track.colFg
        }
        StyledText {
            text: Rog.profile
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.25)
        }
    }

    // Slider-state dots
    Repeater {
        model: Rog.profiles
        delegate: Rectangle {
            required property int index
            required property string modelData
            readonly property bool isActive: Rog.profile === modelData
            x: track.stops[index] - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: track.colFg
            opacity: track.selectMode && !isActive ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -12
                enabled: track.selectMode
                onClicked: {
                    Rog.setProfile(modelData)
                    track.selectMode = false
                }
                cursorShape: Qt.PointingHandCursor
            }
        }
    }

    // Thumb
    Rectangle {
        id: profileThumb
        width: track.thumbDiameter; height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter

        readonly property real restX: track.leftRestX
        readonly property real targetX: track.stops[track.profileIndex] - width / 2
        property real dragOffset: 0

        x: track.selectMode
            ? (dragHandler.active
                ? Math.max(track.stops[0] - width / 2,
                    Math.min(track.stops[Rog.profiles.length - 1] - width / 2,
                        targetX + dragOffset))
                : targetX)
            : restX
        Behavior on x {
            enabled: !dragHandler.active
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
        color: track.isPerf ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        readonly property int snapIndex: {
            const center = x + width / 2
            let bestI = 0, bestD = Infinity
            for (let i = 0; i < Rog.profiles.length; i++) {
                const d = Math.abs(center - track.stops[i])
                if (d < bestD) { bestD = d; bestI = i }
            }
            return bestI
        }

        HoverHandler { id: thumbHov }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: thumbHov.hovered && !dragHandler.active
                ? (track.isPerf ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover)
                : ColorUtils.transparentize((track.isPerf ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover))
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        DragHandler {
            id: dragHandler
            target: null
            enabled: track.selectMode
            xAxis.enabled: true
            yAxis.enabled: false
            onTranslationChanged: profileThumb.dragOffset = translation.x
            onActiveChanged: {
                if (!active) {
                    Rog.setProfile(Rog.profiles[profileThumb.snapIndex])
                    profileThumb.dragOffset = 0
                    track.selectMode = false
                }
            }
        }
        TapHandler {
            onTapped: track.selectMode = !track.selectMode
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: track.iconFor(Rog.profile)
            iconSize: 20
            fill: 1
            color: track.isPerf ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
    }
}
