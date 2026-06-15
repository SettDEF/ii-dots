import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell

AndroidQuickToggleButton {
    id: root
    toggleModel: KdeConnectToggle {}
    // Tile may be size-1 (no altAction route) — wire the click straight to the dialog.
    mainAction: () => root.openMenu()
}
