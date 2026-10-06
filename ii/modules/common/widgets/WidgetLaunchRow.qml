import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

// "Open in <app>" at the foot of a dock widget's panel.
//
// Each dock widget has a small app behind it now. The panel stays the quick
// glance — it is one click from the dock and needs no window — and this is
// the way through to the app when the glance is not enough. Replacing the
// panel with a launch would have traded something instant for something that
// takes a second to appear.
//
// Shared so all five panels get the same affordance in the same place;
// a launch row that moves between panels is one nobody learns.
RippleButton {
    id: root

    /// Path to the app's .qml, run through quickshell.
    required property string appPath
    required property string appName

    Layout.fillWidth: true
    implicitHeight: 34
    buttonRadius: Appearance.rounding.small
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onClicked: {
        // execDetached, so the app outlives the panel that launched it — the
        // panel closes the moment focus leaves it.
        Quickshell.execDetached(["qs", "-p", root.appPath]);
        DockWidgetPanel.close();
    }

    contentItem: RowLayout {
        spacing: 8
        MaterialSymbol {
            Layout.leftMargin: 4
            text: "open_in_new"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Open in %1").arg(root.appName)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
    }
}
