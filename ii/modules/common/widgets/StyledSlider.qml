pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

/**
 * Material 3 slider. See https://m3.material.io/components/sliders/overview
 * It doesn't exactly match the spec because it does not make sense to have stuff on a computer that fucking huge.
 * Should be at 3/4 scale...
 */

Slider {
    id: root

    property list<real> stopIndicatorValues: [1]
    enum Configuration {
        Wavy = 4,
        XS = 12,
        S = 18,
        M = 30,
        L = 42,
        XL = 72
    }

    property var configuration: StyledSlider.Configuration.S

    property real handleDefaultWidth: 3
    property real handlePressedWidth: 1.5
    property color highlightColor: Appearance.colors.colPrimary
    property color trackColor: Appearance.colors.colSecondaryContainer
    property color handleColor: Appearance.colors.colPrimary
    property color dotColor: Appearance.m3colors.m3onSecondaryContainer
    property color dotColorHighlighted: Appearance.m3colors.m3onPrimary
    property real unsharpenRadius: Appearance.rounding.unsharpen
    property real trackWidth: configuration
    property real trackRadius: trackWidth >= StyledSlider.Configuration.XL ? 21
        : trackWidth >= StyledSlider.Configuration.L ? 12
        : trackWidth >= StyledSlider.Configuration.M ? 9
        : trackWidth >= StyledSlider.Configuration.S ? 6
        : height / 2
    property real handleHeight: (configuration === StyledSlider.Configuration.Wavy) ? 24 : Math.max(33, trackWidth + 9)
    property real handleWidth: root.pressed ? handlePressedWidth : handleDefaultWidth
    property real handleMargins: 4
    property real trackDotSize: 3
    /// Optional live meter drawn inside the track, independent of `value`:
    /// the slider sets a level, the meter shows what is actually coming out.
    /// 0..1, or -1 for no meter.
    property real level: -1
    /// Peak-hold marker, 0..1, or -1 for none.
    property real peakHold: -1
    /// Near clipping: the meter turns to the error colour.
    property bool levelHot: false
    property real meterThickness: Math.max(3, Math.round(root.trackWidth * 0.28))
    property bool usePercentTooltip: true
    property string tooltipContent: usePercentTooltip ? `${Math.round(((value - from) / (to - from)) * 100)}%` : `${Math.round(value)}`
    property bool wavy: configuration === StyledSlider.Configuration.Wavy // If true, the progress bar will have a wavy fill effect
    property bool animateWave: true
    property real waveAmplitudeMultiplier: wavy ? 0.5 : 0
    property real waveFrequency: 6
    property real waveFps: 60

    leftPadding: handleMargins
    rightPadding: handleMargins
    property real effectiveDraggingWidth: width - leftPadding - rightPadding

    Layout.fillWidth: true
    from: 0
    to: 1

    Behavior on value { // This makes the adjusted value (like volume) shift smoothly
        SmoothedAnimation {
            velocity: Appearance.animation.elementMoveFast.velocity
        }
    }

    Behavior on handleMargins {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    component TrackDot: Rectangle {
        required property real value
        property real normalizedValue: (value - root.from) / (root.to - root.from)
        anchors.verticalCenter: parent.verticalCenter
        x: root.handleMargins + (normalizedValue * root.effectiveDraggingWidth) - (root.trackDotSize / 2)
        width: root.trackDotSize
        height: root.trackDotSize
        radius: Appearance.rounding.full
        color: normalizedValue > root.visualPosition ? root.dotColor : root.dotColorHighlighted

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    // One half of the in-track meter. The track is two differently coloured
    // fills, so the meter is drawn twice - clipped to each fill, in a colour
    // that reads on that fill - rather than once in a colour that disappears
    // on one of them.
    component MeterHalf: Item {
        required property real clipX
        required property real clipWidth
        required property color barColor
        x: clipX
        width: Math.max(0, clipWidth)
        height: root.trackWidth
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        visible: root.level >= 0

        Rectangle {
            x: root.handleMargins - parent.clipX
            anchors.verticalCenter: parent.verticalCenter
            width: root.effectiveDraggingWidth * Math.max(0, Math.min(1, root.level))
            height: root.meterThickness
            radius: Appearance.rounding.full
            color: root.levelHot ? Appearance.m3colors.m3error : parent.barColor
            // Only the fall is eased: easing the rise would smooth away the
            // transient a meter exists to show.
            Behavior on width {
                enabled: root.level < 0 || width > root.effectiveDraggingWidth * root.level
                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            visible: root.peakHold >= 0
            x: root.handleMargins - parent.clipX
               + root.effectiveDraggingWidth * Math.max(0, Math.min(1, root.peakHold)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: Math.max(root.meterThickness + 4, root.trackWidth - 6)
            radius: 1
            color: root.levelHot ? Appearance.m3colors.m3error : parent.barColor
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => mouse.accepted = false
        cursorShape: root.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor 
    }

    background: Item {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        implicitHeight: trackWidth
        
        // Fill left — same Rectangle shape as the right fill so both
        // halves visually match.  (The wavy variant lives below.)
        Rectangle {
            visible: !root.wavy
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
            }
            width: root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth) - (root.handleWidth / 2 + root.handleMargins)
            height: root.trackWidth
            color: root.highlightColor
            radius: root.trackRadius
        }

        Loader {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
            }
            width: root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth) - (root.handleWidth / 2 + root.handleMargins)
            height: root.height
            active: root.wavy
            sourceComponent: WavyLine {
                id: wavyFill
                frequency: root.waveFrequency
                fullLength: root.width
                color: root.highlightColor
                amplitudeMultiplier: root.wavy ? 0.5 : 0
                width: root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth) - (root.handleWidth / 2 + root.handleMargins)
                height: root.trackWidth
                Connections {
                    target: root
                    function onValueChanged() { wavyFill.requestPaint(); }
                    function onHighlightColorChanged() { wavyFill.requestPaint(); }
                }
                FrameAnimation {
                    running: root.animateWave
                    onTriggered: {
                        wavyFill.requestPaint()
                    }
                }
            }   
        }

        // Fill right
        Rectangle {
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
            }
            width: root.handleMargins + ((1 - root.visualPosition) * root.effectiveDraggingWidth) - (root.handleWidth / 2 + root.handleMargins)
            height: root.trackWidth
            color: root.trackColor
            radius: root.trackRadius
        }

        // In-track meter: over the filled half in the colour that sits on the
        // fill, over the empty half in the fill's own colour.
        MeterHalf {
            clipX: 0
            clipWidth: root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth)
                       - (root.handleWidth / 2 + root.handleMargins)
            barColor: ColorUtils.transparentize(root.dotColorHighlighted, 0.35)
        }
        MeterHalf {
            clipX: parent.width - (root.handleMargins + ((1 - root.visualPosition) * root.effectiveDraggingWidth)
                   - (root.handleWidth / 2 + root.handleMargins))
            clipWidth: parent.width - clipX
            barColor: root.highlightColor
        }

        // Stop indicators
        Repeater {
            model: root.stopIndicatorValues
            TrackDot {
                required property real modelData
                value: modelData
                anchors.verticalCenter: parent?.verticalCenter
            }
        }
    }

    handle: Rectangle {
        id: handle

        implicitWidth: root.handleWidth
        implicitHeight: root.handleHeight
        x: root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth) - (root.handleWidth / 2)
        anchors.verticalCenter: parent.verticalCenter
        radius: Appearance.rounding.full
        color: root.handleColor

        Behavior on implicitWidth {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledToolTip {
            extraVisibleCondition: root.pressed
            text: root.tooltipContent
            font {
                family: Appearance.font.family.numbers
                variableAxes: Appearance.font.variableAxes.numbers
            }
        }
    }
}
