import QtQuick
import org.kde.kirigami as Kirigami
import qs.services
import qs.modules.common

Kirigami.Icon {
    id: root
    required property string iconName
    property bool separateLightDark: false
    property bool tryCustomIcon: true
    
    property real implicitSize: 26
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    animated: true
    roundToIconSize: false
    // an app whose icon is in no installed theme gets the generic one, as Windows does (its own
    // name as the fallback left the slot blank)
    fallback: tryCustomIcon ? root.iconName : "application-x-executable"
    source: tryCustomIcon ? `${Looks.iconsPath}/${root.iconName}${!root.separateLightDark ? "" : Looks.dark ? "-dark" : "-light"}.svg` : root.iconName

    color: Looks.colors.fg
}
