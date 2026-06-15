import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Sleep timer")
    icon: "bedtime"

    toggled: SleepTimer.running
    hasStatusText: true
    statusText: SleepTimer.running
        ? SleepTimer.formatRemaining()
        : (SleepTimer.durationMinutes + " " + Translation.tr("min"))
    tooltipText: SleepTimer.running
        ? Translation.tr("Suspends in") + " " + SleepTimer.formatRemaining()
            + " — " + Translation.tr("tap to cancel, right-click to change")
        : Translation.tr("Tap to start, right-click to change duration")

    // Tap: start / cancel the countdown.
    mainAction: () => SleepTimer.toggle()
    // Right-click / long-press: step to the next preset duration.
    altAction: () => SleepTimer.cycleDuration()
}
