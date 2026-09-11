import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * In-page setup for the finance tab.
 *
 * Replaces "go read the README and run three commands in a terminal". Every
 * step the backend can do without a human is driven from here; the one step
 * that genuinely cannot — registering an application in Enable Banking's
 * control panel, which is a web form on their site behind their login — is
 * reduced to a button that opens it and a redirect URL you can copy.
 *
 * The backend does the rest: `finance-sync setup --json` finds the downloaded
 * key, installs it 600, writes the credentials, opens the consent page and
 * catches the redirect on localhost itself, so there is no code to copy back.
 * It reports progress as newline-delimited JSON, which is what lets this show
 * real stages instead of an indeterminate spinner.
 */
Item {
    id: root

    /// 0 register · 1 key · 2 bank · 3 authorize · 4 done
    property int step: 0
    property string keyPath: ""
    property string country: "DE"
    property var banks: []
    property string selectedBank: ""
    property string statusText: ""
    property string errorText: ""
    property string fallbackUrl: ""
    readonly property string redirectUrl: "http://localhost:8899/callback"

    /// Whether the 6-hour refresh timer is enabled. Without it a linked bank
    /// still never updates — the shell only ever paints from cache, so the
    /// timer is what makes the data live rather than a one-off snapshot.
    property bool timerActive: false

    signal finished()

    implicitHeight: content.implicitHeight

    function reset() {
        root.step = 0; root.keyPath = ""; root.banks = [];
        root.selectedBank = ""; root.statusText = ""; root.errorText = "";
        root.fallbackUrl = "";
    }

    // ── Backend calls ───────────────────────────────────────────────────
    Process {
        id: findKey
        command: ["bash", "-c",
            // The filename IS the application id, so the newest UUID-named .pem
            // in Downloads is the one just fetched from the control panel.
            "ls -t ~/Downloads/*.pem 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.keyPath = (text ?? "").trim();
                root.statusText = root.keyPath.length > 0
                    ? qsTr("Found %1").arg(root.keyPath.split("/").pop())
                    : qsTr("No .pem found in ~/Downloads");
            }
        }
    }

    Process {
        id: listBanks
        stderr: StdioCollector { id: banksErr }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.banks = JSON.parse(text || "[]");
                    root.errorText = root.banks.length === 0
                        ? qsTr("No banks returned for %1").arg(root.country) : "";
                } catch (e) {
                    root.banks = [];
                    root.errorText = (banksErr.text ?? "").trim().split("\n")[0]
                        || qsTr("Could not read the bank list");
                }
            }
        }
    }
    function loadBanks() {
        root.errorText = ""; root.banks = [];
        listBanks.command = [`${Directories.scriptPath}/finance/finance-sync`,
                             "banks", "--country", root.country, "--json"];
        listBanks.running = false;
        listBanks.running = true;
    }

    Process {
        id: runSetup
        stderr: StdioCollector { id: setupErr }
        // Read line-by-line, not at exit: the consent stage waits on a human in
        // a browser and can take minutes. Waiting for the process to finish
        // before showing anything would leave the panel looking hung through
        // the one step that most needs explaining.
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const t = (line ?? "").trim();
                if (t.length === 0) return;
                try {
                    const o = JSON.parse(t);
                    if (o.stage === "url") { root.fallbackUrl = o.url ?? ""; return }
                    if (o.message) root.statusText = o.message;
                } catch (e) {
                    root.statusText = t;
                }
            }
        }
        onExited: (code) => {
            if (code === 0) {
                root.step = 4;
                root.refreshTimerStatus();
                root.statusText = qsTr("Linked. Fetching your accounts…");
                Finance.sync();
            } else {
                root.errorText = (setupErr.text ?? "").trim().split("\n")[0]
                    || qsTr("Setup failed (exit %1)").arg(code);
            }
        }
    }
    function startSetup() {
        root.errorText = ""; root.fallbackUrl = "";
        root.statusText = qsTr("Starting…");
        const cmd = [`${Directories.scriptPath}/finance/finance-sync`, "setup",
                     "--country", root.country, "--bank", root.selectedBank,
                     "--redirect", root.redirectUrl, "--json"];
        if (root.keyPath.length > 0) { cmd.push("--key"); cmd.push(root.keyPath) }
        runSetup.command = cmd;
        runSetup.running = false;
        runSetup.running = true;
        root.step = 3;
    }

    Process {
        id: timerStatus
        command: ["systemctl", "--user", "is-active", "finance-sync.timer"]
        stdout: StdioCollector {
            onStreamFinished: root.timerActive = (text ?? "").trim() === "active"
        }
    }
    function refreshTimerStatus() {
        timerStatus.running = false;
        timerStatus.running = true;
    }

    Process {
        id: timerToggle
        stderr: StdioCollector { id: timerErr }
        onExited: (code) => {
            if (code !== 0) {
                root.errorText = (timerErr.text ?? "").trim().split("\n")[0]
                    || qsTr("Could not change the refresh timer");
            }
            root.refreshTimerStatus();
        }
    }
    function setTimer(on) {
        root.errorText = "";
        timerToggle.command = on
            ? ["bash", `${Directories.scriptPath}/finance/install.sh`]
            : ["systemctl", "--user", "disable", "--now", "finance-sync.timer"];
        timerToggle.running = false;
        timerToggle.running = true;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 14

        // Step indicator
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 3
                    radius: Appearance.rounding.full
                    color: index <= root.step ? Appearance.colors.colPrimary
                                              : Appearance.colors.colLayer2
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
        }

        // ── 0. Register the application ─────────────────────────────────
        SetupSection {
            visible: root.step === 0
            icon: "app_registration"
            title: qsTr("Register an application")
            body: qsTr("Enable Banking's Restricted Production tier is free and reads only your own accounts. "
                     + "Create an application there, then whitelist the redirect URL below. "
                     + "Your browser will download a .pem — leave it in Downloads.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    StyledText {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: Text.AlignVCenter
                        text: root.redirectUrl
                        elide: Text.ElideMiddle
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: "content_copy"
                    mainText: qsTr("Copy")
                    onClicked: Quickshell.execDetached(["wl-copy", root.redirectUrl])
                    StyledToolTip { text: qsTr("Copy the redirect URL to whitelist") }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "open_in_new"
                    mainText: qsTr("Open control panel")
                    onClicked: Quickshell.execDetached(["xdg-open", "https://enablebanking.com/cp/"])
                }
                Item { Layout.fillWidth: true }
                PrimaryActionButton {
                    buttonText: qsTr("Next")
                    onClicked: { root.step = 1; findKey.running = true }
                }
            }
        }

        // ── 1. Find the key ─────────────────────────────────────────────
        SetupSection {
            visible: root.step === 1
            icon: "key"
            title: qsTr("Find your key")
            body: qsTr("The .pem your browser downloaded. Its filename is your application id.")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 8
                    MaterialSymbol {
                        text: root.keyPath.length > 0 ? "check_circle" : "search_off"
                        iconSize: 17
                        color: root.keyPath.length > 0 ? Appearance.colors.colPrimary
                                                       : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.statusText
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "refresh"
                    mainText: qsTr("Look again")
                    onClicked: findKey.running = true
                }
                Item { Layout.fillWidth: true }
                PrimaryActionButton {
                    buttonText: qsTr("Next")
                    enabled: root.keyPath.length > 0
                    onClicked: { root.step = 2; root.loadBanks() }
                }
            }
        }

        // ── 2. Pick the bank ────────────────────────────────────────────
        SetupSection {
            visible: root.step === 2
            icon: "account_balance"
            title: qsTr("Choose your bank")
            body: qsTr("Pick the institution holding the account you want to read.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PillTextField {
                    id: countryField
                    Layout.preferredWidth: 60
                    text: root.country
                    placeholderText: "DE"
                    onAccepted: { root.country = text.toUpperCase(); root.loadBanks() }
                }
                PillTextField {
                    id: filterField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Filter banks…")
                }
                RippleButtonWithIcon {
                    materialIcon: "refresh"
                    mainText: ""
                    onClicked: { root.country = countryField.text.toUpperCase(); root.loadBanks() }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 190
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                clip: true

                StyledText {
                    anchors.centerIn: parent
                    visible: root.banks.length === 0
                    text: listBanks.running ? qsTr("Loading…") : qsTr("No banks")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledListView {
                    anchors { fill: parent; margins: 4 }
                    spacing: 2
                    model: ScriptModel {
                        values: root.banks.filter(b => filterField.text.length === 0
                            || (b.name ?? "").toLowerCase().includes(filterField.text.toLowerCase()))
                    }
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: modelData.name === root.selectedBank
                        width: ListView.view ? ListView.view.width : 0
                        implicitHeight: 32
                        radius: Appearance.rounding.verysmall
                        color: sel ? Appearance.colors.colPrimaryContainer
                            : (bankHov.hovered ? Appearance.colors.colLayer2Hover : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: bankHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.selectedBank = modelData.name }
                        StyledText {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.name ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: parent.sel ? Appearance.colors.colOnPrimaryContainer
                                              : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "arrow_back"
                    mainText: qsTr("Back")
                    onClicked: root.step = 1
                }
                Item { Layout.fillWidth: true }
                PrimaryActionButton {
                    buttonText: qsTr("Authorize")
                    enabled: root.selectedBank.length > 0
                    onClicked: root.startSetup()
                }
            }
        }

        // ── 3. Consent in the browser ───────────────────────────────────
        SetupSection {
            visible: root.step === 3
            icon: "verified_user"
            title: qsTr("Approve in your browser")
            body: qsTr("Your bank's consent page has opened. Approve access there — "
                     + "the redirect is caught automatically, so there is nothing to copy back.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "hourglass_top"
                    iconSize: 17
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: root.fallbackUrl.length > 0
                materialIcon: "open_in_new"
                mainText: qsTr("Open the consent page manually")
                onClicked: Quickshell.execDetached(["xdg-open", root.fallbackUrl])
            }

            RippleButtonWithIcon {
                materialIcon: "close"
                mainText: qsTr("Cancel")
                onClicked: { runSetup.running = false; root.step = 2 }
            }
        }

        // ── 4. Done ─────────────────────────────────────────────────────
        SetupSection {
            visible: root.step === 4
            icon: "check_circle"
            title: qsTr("Linked")
            body: qsTr("Your account is linked and the first sync is running. "
                     + "A timer refreshes it every 6 hours; consent lasts 90 days and "
                     + "the footer warns you 14 days before it expires.")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 8
                    MaterialSymbol {
                        text: root.timerActive ? "schedule" : "schedule_send"
                        iconSize: 17
                        color: root.timerActive ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: qsTr("Refresh every 6 hours")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            // PSD2 allows ~4 unattended calls per account per
                            // day, so 6 hours is the ceiling, not a preference.
                            text: root.timerActive
                                ? qsTr("On — a user timer keeps the data current")
                                : qsTr("Off — the data will not update on its own")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledSwitch {
                        checked: root.timerActive
                        onToggled: root.setTimer(checked)
                    }
                }
            }

            PrimaryActionButton {
                buttonText: qsTr("Done")
                onClicked: root.finished()
            }
        }

        // ── Errors ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            implicitHeight: errRow.implicitHeight + 20
            radius: Appearance.rounding.small
            // Tint, not a filled error slab — the palette's error red is the
            // only saturated colour in a wallpaper-derived theme.
            color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.88)
            RowLayout {
                id: errRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 8
                MaterialSymbol { text: "error"; iconSize: 17; color: Appearance.m3colors.m3error }
                StyledText {
                    Layout.fillWidth: true
                    text: root.errorText
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3error
                }
            }
        }
    }
}
