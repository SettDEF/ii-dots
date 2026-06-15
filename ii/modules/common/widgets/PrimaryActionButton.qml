import qs.modules.common
import QtQuick

/**
 * DialogButton tinted with the M3 primary palette — the "filled" variant
 * used for the main action in inline dialog rows (e.g. Connect, Disconnect
 * in the Wi-Fi / Bluetooth lists). Default color overrides can still be
 * replaced per-instance for destructive actions (e.g. error palette for
 * "Forget" / "Disconnect").
 */
DialogButton {
    colBackground: Appearance.colors.colPrimary
    colBackgroundHover: Appearance.colors.colPrimaryHover
    colRipple: Appearance.colors.colPrimaryActive
    colText: Appearance.colors.colOnPrimary
}
