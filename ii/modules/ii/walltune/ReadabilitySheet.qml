import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

/// Look > Colour > Readability: the text-on-fill pairs of the colours in use, measured (WCAG), and
/// fixed: tinct moves the text colour to the nearest tone that reads; the fix is an override (Edit
/// colours shows it, reset there undoes it), for the exact theme or for the wallpaper's colours.
PanelSheet {
    id: sheet
    title: qsTr("Readability")
    subtitle: failing.length === 0 ? qsTr("All %1 pairs read").arg(pairs.length)
                                   : qsTr("%1 of %2 pairs hard to read").arg(failing.length).arg(pairs.length)

    // text, the fill it sits on, the ratio it needs (4.5 text, 3 large or a shape)
    readonly property var spec: [
        ["on_primary", "primary", 4.5], ["on_secondary", "secondary", 4.5], ["on_tertiary", "tertiary", 4.5],
        ["on_error", "error", 4.5], ["on_primary_container", "primary_container", 4.5],
        ["on_secondary_container", "secondary_container", 4.5], ["on_tertiary_container", "tertiary_container", 4.5],
        ["on_error_container", "error_container", 4.5], ["on_background", "background", 4.5],
        ["on_surface", "surface", 4.5], ["on_surface", "surface_container", 4.5],
        ["on_surface", "surface_container_high", 4.5], ["on_surface", "surface_container_highest", 4.5],
        ["on_surface_variant", "surface", 4.5], ["on_surface_variant", "surface_container", 4.5],
        ["on_surface_variant", "surface_container_high", 4.5], ["primary", "surface", 3], ["outline", "surface", 3]
    ]
    function hexOf(role) {
        const c = Appearance.m3colors["m3" + role.replace(/_([a-z])/g, (g) => g[1].toUpperCase())];
        return c === undefined ? "" : ("#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join(""));
    }
    readonly property var pairs: spec.map(([fg, bg, need]) => {
        const f = hexOf(fg), b = hexOf(bg);
        return { fg, bg, need, f, b, ratio: f && b ? ColorPick.contrast(f, b) : 21 };
    })
    readonly property var failing: pairs.filter(p => p.ratio < p.need)

    // the fix: per text colour, against the fill it reads worst on
    property bool fixing: false
    function fixAll() {
        const worst = {};
        for (const p of failing) if (!worst[p.fg] || p.ratio < worst[p.fg].ratio) worst[p.fg] = p;
        const args = [];
        for (const k in worst) args.push(k, worst[k].f, worst[k].b, String(worst[k].need));
        if (!args.length) return;
        fixProc.command = ["sh", "-c",
            'while [ $# -ge 4 ]; do s=$("$T" contrast "$2" "$3" --target "$4" -f json | jq -r \'.[] | select(.check=="suggestion") | .value\'); [ -n "$s" ] && [ "$s" != null ] && echo "$1 $s"; shift 4; done',
            "sh"].concat(args);
        fixProc.environment = { T: ExactTheme.tinct };
        sheet.fixing = true;
        fixProc.running = true;
    }
    Process {
        id: fixProc
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const [k, v] = line.trim().split(" ");
                    if (k && /^#[0-9a-fA-F]{6}$/.test(v ?? "")) map[k] = v.toLowerCase();
                }
                if (Object.keys(map).length) ExactTheme.setColors(map);
                sheet.fixing = false;
            }
        }
    }

    PaletteCard {
        Repeater {
            model: sheet.pairs
            delegate: ColumnLayout {
                id: pr
                required property var modelData
                required property int index
                readonly property bool ok: modelData.ratio >= modelData.need
                Layout.fillWidth: true
                spacing: 0
                PaletteDivider { visible: pr.index > 0 }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    spacing: 10
                    // the text on its fill, as it looks
                    Rectangle {
                        implicitWidth: 38; implicitHeight: 26
                        radius: Appearance.rounding.verysmall
                        color: pr.modelData.b
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        StyledText { anchors.centerIn: parent; text: "Aa"; color: pr.modelData.f; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: pr.modelData.fg.replace(/_/g, " ") + "  on  " + pr.modelData.bg.replace(/_/g, " ")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: pr.modelData.ratio.toFixed(1) + " : 1"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: pr.ok ? Appearance.colors.colSubtext : Appearance.m3colors.m3error
                    }
                    MaterialSymbol {
                        text: pr.ok ? "check" : "error"
                        iconSize: 16
                        color: pr.ok ? Appearance.colors.colSubtext : Appearance.m3colors.m3error
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Needs 4.5 : 1 for text, 3 : 1 for large text and shapes. A fix moves the text colour only; Edit colours can undo it.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
        DialogButton {
            buttonText: sheet.fixing ? qsTr("Fixing…") : qsTr("Fix all")
            enabled: sheet.failing.length > 0 && !sheet.fixing
            onClicked: sheet.fixAll()
        }
    }
}
