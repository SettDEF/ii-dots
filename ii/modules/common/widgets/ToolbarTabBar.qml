pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property alias currentIndex: tabBar.currentIndex
    required property var tabButtonList

    function incrementCurrentIndex() {
        tabBar.incrementCurrentIndex();
    }
    function decrementCurrentIndex() {
        tabBar.decrementCurrentIndex();
    }
    function setCurrentIndex(index) {
        tabBar.setCurrentIndex(index);
    }

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    implicitWidth: contentItem.implicitWidth
    implicitHeight: 40

    property Component delegate: ToolbarTabButton {
        required property int index
        required property var modelData
        current: index == root.currentIndex
        text: modelData.name
        materialSymbol: modelData.icon
        onClicked: {
            root.setCurrentIndex(index);
        }
    }

    Row {
        id: contentItem
        z: 1
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: root.tabButtonList
            delegate: root.delegate
        }
    }

    Rectangle {
        id: activeIndicator
        z: 0
        color: Appearance.colors.colSecondaryContainer
        radius: height / 2
        // Animation
        property Item targetItem: contentItem.children[root.currentIndex]
        // `targetItem.x` is relative to the `contentItem` Row, but this
        // Rectangle is positioned relative to the ToolbarTabBar root.
        // Add the Row's own offset so the highlight lands exactly on
        // the active button (and thus its centered icon).
        readonly property real targetX:
            targetItem ? contentItem.x + targetItem.x : 0
        readonly property real targetW: targetItem ? targetItem.width : 0
        AnimatedTabIndexPair {
            id: leftBound
            idx1Duration: 50
            idx2Duration: 200
            index: activeIndicator.targetX
        }
        AnimatedTabIndexPair {
            id: rightBound
            idx1Duration: 50
            idx2Duration: 200
            index: activeIndicator.targetX + activeIndicator.targetW
        }
        x: Math.min(leftBound.idx1, leftBound.idx2)
        width: Math.max(rightBound.idx1, rightBound.idx2) - x
        // Vertically center on the Row instead of pinning to y=0.
        height: targetItem ? targetItem.height : root.height
        y: contentItem.y + (targetItem ? targetItem.y : 0)
    }

    MouseArea {
        anchors.fill: parent
        z: 2
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        onWheel: event => {
            if (event.angleDelta.y < 0) {
                root.incrementCurrentIndex();
            } else {
                root.decrementCurrentIndex();
            }
        }
    }

    // TabBar doesn't allow tabs to be of different sizes. That's what I thought...
    // We use it only for the logic and draw stuff manually
    TabBar {
        id: tabBar
        z: -1
        background: null
        Repeater {
            // This is to fool the TabBar that it has tabs so it does the indices properly
            model: root.tabButtonList.length
            delegate: TabButton {
                background: null
            }
        }
    }
}
