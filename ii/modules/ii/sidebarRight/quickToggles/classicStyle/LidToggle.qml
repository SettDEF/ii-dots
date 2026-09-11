import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: Lid.enabled
    buttonIcon: "laptop"
    onClicked: Lid.toggle()
    StyledToolTip {
        text: Translation.tr("Lid close → screen off (keeps external monitor); sleeps if none")
    }
}
