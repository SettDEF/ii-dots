import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Windows")
    tooltipText: Translation.tr("Windows VM | Right-click to re-open screen")
    icon: "desktop_windows"

    mainAction: () => {
        if (root.toggled) {
            Quickshell.execDetached(["/home/caesar/.scripts/start_windows_vm.sh", "stop"])
        } else {
            Quickshell.execDetached(["/home/caesar/.scripts/start_windows_vm.sh", "start"])
        }
    }

    altAction: () => {
        Quickshell.execDetached(["virt-viewer", "--connect", "qemu:///system", "--attach", "win11-gaming"])
    }

    // Check VM status periodically
    Process {
        id: vmCheckProc
        command: ["bash", "-c", "virsh --connect qemu:///system domstate win11-gaming | grep -q running"]
        onExited: (exitCode, exitStatus) => {
            root.toggled = (exitCode === 0)
        }
    }

    // Background notification daemon managed by Quickshell
    Process {
        id: vmNotificationDaemon
        running: true
        command: ["/home/caesar/.config/quickshell/ii/scripts/vm_notification_daemon.py"]
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: vmCheckProc.running = true
    }

    Component.onCompleted: vmCheckProc.running = true
}
