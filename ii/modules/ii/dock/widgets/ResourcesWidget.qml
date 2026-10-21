import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Two rising bars — a meter, so it can't be mistaken for the other tiles.
DockTile {
    id: root
    // Mid step: secondaryContainer is nearly identical to primaryContainer
    // in this palette, so it is mixed rather than picked.
    tint: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.45)
    // Vitals (its background service) adds what generic numbers miss: the
    // temperature and power, and anything it has judged wrong right now.
    tooltip: {
        let t = Translation.tr("CPU %1%  ·  RAM %2%")
            .arg(Math.round(ResourceUsage.cpuUsage * 100))
            .arg(Math.round(ResourceUsage.memoryUsedPercentage * 100));
        const l = Vitals.latest;
        if (l && l.temp != null) t += `  ·  ${Math.round(l.temp)} °C`;
        if (l && l.pkg_w != null) t += `  ·  ${Math.round(l.pkg_w)} W`;
        const found = Vitals.findings;
        if (Array.isArray(found)) {
            const shown = found.filter(x => x && x.sev !== "info").slice(0, 3);
            for (let i = 0; i < shown.length; i++)
                t += `\n${shown[i].sev === "critical" ? "●" : "○"} ${shown[i].title}`;
        }
        return t;
    }

    // a dot when Vitals has something to say: red critical, amber warning
    Rectangle {
        visible: (Vitals.critical ?? 0) + (Vitals.warnings ?? 0) > 0
        z: 2
        anchors { top: parent.top; right: parent.right; margins: 3 }
        width: 9; height: 9; radius: 4.5
        color: Vitals.critical > 0 ? Appearance.m3colors.m3error : Appearance.m3colors.m3tertiary
        border.width: 1.5
        border.color: root.tint
    }

    component Bar: Item {
        required property real fraction
        // in 5% steps (about a pixel here): Vitals reports the temperature many times a second, and
        // every tenth of a degree restarted the animation, the dock redrawing ~15 times a second
        readonly property real shown: Math.round(Math.max(0.10, Math.min(1, fraction)) * 20) / 20
        Layout.fillHeight: true
        implicitWidth: 9
        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.alpha(Appearance.colors.colOnPrimary, 0.25)
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * shown
            radius: 4
            color: fraction > 0.9 ? Appearance.m3colors.m3error : Appearance.colors.colOnPrimary
            Behavior on height {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    RowLayout {
        anchors.centerIn: parent
        height: parent.height - 10
        spacing: 4
        Bar { fraction: ResourceUsage.cpuUsage }
        Bar { fraction: ResourceUsage.memoryUsedPercentage }
        Bar {
            visible: DockWidgets.get("resources", "showSwap") === true
            fraction: ResourceUsage.swapUsedPercentage
        }
        // CPU temperature, from the Vitals service: 40 °C empty, 100 °C full,
        // red from 90 (the bar's own >0.9 rule). Absent when Vitals has none.
        Bar {
            readonly property real temp: Vitals.latest?.temp ?? -1
            visible: temp > 0 && DockWidgets.get("resources", "showTemp") !== false
            fraction: Math.max(0, Math.min(1, (temp - 40) / 55.5))
        }
    }
}
