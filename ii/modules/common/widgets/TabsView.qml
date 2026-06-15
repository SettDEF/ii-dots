// TabsView — orientation-aware tab container with sliding content and
// lazy-loaded panes.
//
// Usage:
//   TabsView {
//       tabs: [
//           { id: "explorer", label: "Explorer", icon: "folder_open" },
//           { id: "recent",   label: "Recent",   icon: "history"     }
//       ]
//       currentId: "explorer"
//       tabBarPosition: Qt.AlignLeft
//
//       // One Component per tab id (returned by `componentFor`):
//       function componentFor(id) {
//           return id === "explorer" ? explorerComp : recentComp
//       }
//   }
//
// Animation direction follows the tab-bar axis: vertical tab bar slides
// content vertically, horizontal slides horizontally. Inactive tabs are
// wrapped in TabLoader so they hydrate on demand + pre-warm later.
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // Required ── caller supplies tabs and a component-resolver function.
    required property var tabs                  // [{ id, label, icon }]
    property string currentId
    property var componentFor: (id) => null     // (id) → Component | null

    // Layout ── where the tab bar sits relative to the content.
    property int tabBarPosition: Qt.AlignTop    // Top | Bottom | Left | Right

    // Animation ──
    property int animationDuration: 360
    property int animationEasing: Easing.InOutCubic

    // Lazy loading ──
    property bool lazy: true
    property int  prewarmDelay: 250

    signal tabSelected(string tabId)

    readonly property bool _vertical: tabBarPosition === Qt.AlignLeft || tabBarPosition === Qt.AlignRight
    readonly property int _index: {
        for (let i = 0; i < tabs.length; i++) if (tabs[i].id === currentId) return i
        return 0
    }

    // ── Layout: tab bar on chosen side, content on the other ───────────
    GridLayout {
        anchors.fill: parent
        rows:    root._vertical ? 1 : 2
        columns: root._vertical ? 2 : 1
        rowSpacing: 0
        columnSpacing: 0

        // Position ordering:
        //   Top    → tabBar=row0,col0 ; content=row1,col0
        //   Bottom → content=row0     ; tabBar=row1
        //   Left   → tabBar=col0      ; content=col1
        //   Right  → content=col0     ; tabBar=col1
        // Inline tab bar — orientation-aware Grid of PillTabs.
        Item {
            id: tabBar
            Layout.row:       root.tabBarPosition === Qt.AlignBottom ? 1 : 0
            Layout.column:    root.tabBarPosition === Qt.AlignRight  ? 1 : 0
            Layout.fillWidth:  !root._vertical
            Layout.fillHeight:  root._vertical
            Layout.alignment:   root._vertical ? Qt.AlignTop : Qt.AlignHCenter
            Layout.topMargin:   root._vertical ? 4 : 0
            implicitWidth:  tabBarGrid.implicitWidth  + 8
            implicitHeight: tabBarGrid.implicitHeight + 8

            GridLayout {
                id: tabBarGrid
                anchors.centerIn: parent
                rows:    root._vertical ? root.tabs.length : 1
                columns: root._vertical ? 1 : root.tabs.length
                rowSpacing: 4
                columnSpacing: 4

                Repeater {
                    model: root.tabs
                    delegate: PillTab {
                        required property var modelData
                        Layout.fillWidth: root._vertical
                        horizontalPadding: 10
                        verticalPadding: root._vertical ? 8 : 0
                        iconSize: Appearance.font.pixelSize.small
                        labelSize: Appearance.font.pixelSize.smaller
                        dimInactive: true
                        icon: modelData.icon ?? ""
                        label: modelData.label ?? ""
                        active: root.currentId === modelData.id
                        onTriggered: {
                            root.currentId = modelData.id
                            root.tabSelected(modelData.id)
                        }
                    }
                }
            }
        }

        // Content area: sliding viewport — fills all remaining space.
        Item {
            id: viewport
            Layout.row:    root.tabBarPosition === Qt.AlignBottom ? 0
                         : root.tabBarPosition === Qt.AlignTop    ? 1
                         : 0
            Layout.column: root.tabBarPosition === Qt.AlignRight  ? 0
                         : root.tabBarPosition === Qt.AlignLeft   ? 1
                         : 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            clip: true

            // Sliding strip — all tabs stacked along the bar axis.
            Item {
                id: strip
                width:  root._vertical ? viewport.width  : viewport.width  * root.tabs.length
                height: root._vertical ? viewport.height * root.tabs.length : viewport.height
                x: root._vertical ? 0 : -root._index * viewport.width
                y: root._vertical ? -root._index * viewport.height : 0
                Behavior on x { NumberAnimation { duration: root.animationDuration; easing.type: root.animationEasing } }
                Behavior on y { NumberAnimation { duration: root.animationDuration; easing.type: root.animationEasing } }

                Repeater {
                    model: root.tabs
                    delegate: TabLoader {
                        required property var modelData
                        required property int index
                        x: root._vertical ? 0 : index * viewport.width
                        y: root._vertical ? index * viewport.height : 0
                        width:  viewport.width
                        height: viewport.height
                        active: index === root._index
                        prewarmDelay: root.prewarmDelay
                        prewarmEnabled: root.lazy
                        sourceComponent: root.componentFor(modelData.id)
                    }
                }
            }
        }
    }
}
