import qs.modules.common
import QtQuick

/**
 * Month heatmap — calendar-shaped grid, each cell shaded by that day's
 * usage. `days` is an array of { day: int, total: Number } for the
 * whole month; `firstWeekday` is the column (0=Mon … 6=Sun) the 1st
 * falls in. Cells with no usage stay faint; the busiest day is full
 * accent.
 */
Item {
    id: root

    property var days: []
    property int firstWeekday: 0          // 0 = Monday
    property color accent: Appearance.m3colors.m3primary
    property int cell: 16
    property int gap: 4

    readonly property real maxTotal: {
        let m = 1
        for (const d of days)
            if ((d.total ?? 0) > m) m = d.total
        return m
    }

    implicitWidth: 7 * cell + 6 * gap
    implicitHeight: grid.implicitHeight

    Grid {
        id: grid
        columns: 7
        rowSpacing: root.gap
        columnSpacing: root.gap

        // Leading blanks so day 1 lands in the right column.
        Repeater {
            model: root.firstWeekday
            delegate: Item { width: root.cell; height: root.cell }
        }

        Repeater {
            model: root.days
            delegate: Rectangle {
                required property var modelData
                width: root.cell
                height: root.cell
                radius: 4
                readonly property real frac:
                    Math.min((modelData.total ?? 0) / root.maxTotal, 1)
                color: (modelData.total ?? 0) <= 0
                    ? Qt.alpha(Appearance.colors.colOnLayer0, 0.07)
                    : Qt.alpha(root.accent, 0.22 + 0.78 * frac)
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }
}
