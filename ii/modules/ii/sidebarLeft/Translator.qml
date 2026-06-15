import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Translator widget with the `trans` commandline tool.
 */
Item {
    id: root

    // Sizes
    property real padding: 4

    // Widgets
    property var inputField: inputCanvas.inputTextArea

    // Widget variables
    property bool translationFor: false // Indicates if the translation is for an autocorrected text
    property string translatedText: ""
    property list<string> languages: []

    // Options
    property string targetLanguage: Config.options.language.translator.targetLanguage
    property string sourceLanguage: Config.options.language.translator.sourceLanguage
    property string hostLanguage: targetLanguage

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language
    // Language `trans` auto-detected for the current input (only
    // meaningful while sourceLanguage === "auto").
    property string detectedLanguage: ""

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true
    }

    // Swap source ↔ target. When the source is "auto", the detected
    // language takes its place so the swap stays meaningful. Also
    // moves the current translation into the input box so a swap
    // immediately translates back the other way.
    function swapLanguages() {
        var newSource = root.targetLanguage;
        var newTarget = (root.sourceLanguage === "auto")
            ? (root.detectedLanguage !== "" ? root.detectedLanguage : root.targetLanguage)
            : root.sourceLanguage;
        root.sourceLanguage = newSource;
        root.targetLanguage = newTarget;
        Config.options.language.translator.sourceLanguage = newSource;
        Config.options.language.translator.targetLanguage = newTarget;
        if (root.translatedText.trim().length > 0)
            root.inputField.text = root.translatedText;
        translateTimer.restart();
    }

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (root.inputField.text.trim().length > 0) {
                // console.log("Translating with command:", translateProc.command);
                translateProc.running = false;
                translateProc.buffer = ""; // Clear the buffer
                translateProc.running = true; // Restart the process
                // Kick a language-identify pass when the source is auto.
                if (root.sourceLanguage === "auto") {
                    identifyProc.running = false;
                    identifyProc.buffer = "";
                    identifyProc.running = true;
                } else {
                    root.detectedLanguage = "";
                }
            } else {
                root.translatedText = "";
                root.detectedLanguage = "";
            }
        }
    }

    // Detects the source language when sourceLanguage === "auto".
    // `-no-ansi` keeps `trans` from emitting bold/colour escape codes
    // (they'd show up literally as "[1m…" in the label).
    Process {
        id: identifyProc
        command: ["bash", "-c", `trans -no-bidi -no-ansi -identify`
            + ` '${StringUtils.shellSingleQuoteEscape(root.inputField.text.trim())}'`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { identifyProc.buffer += data + "\n"; }
        }
        onExited: (exitCode, exitStatus) => {
            // `trans -identify` prints lines; the language name is the
            // first non-empty one. Strip any stray ANSI escapes that
            // slip through, keep it short.
            var lines = identifyProc.buffer
                .replace(/\[[0-9;]*m/g, "")
                .split("\n")
                .map(l => l.trim()).filter(l => l.length > 0);
            root.detectedLanguage = lines.length > 0 ? lines[0] : "";
        }
    }

    // Plays the translation audio via `trans -speak`.
    Process {
        id: speakProc
        command: ["bash", "-c", `trans -no-bidi -speak -no-translate`
            + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'`
            + ` '${StringUtils.shellSingleQuoteEscape(root.translatedText.trim())}'`]
    }

    Process {
        id: translateProc
        command: ["bash", "-c", `trans -brief -no-bidi`
            + ` -source '${StringUtils.shellSingleQuoteEscape(root.sourceLanguage)}'`
            + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'`
            + ` '${StringUtils.shellSingleQuoteEscape(root.inputField.text.trim())}'`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            // With -brief mode, we get output with no metadata
            root.translatedText = translateProc.buffer.trim();
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: ["auto"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                getLanguagesProc.bufferList.push(data.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Ensure "auto" is always the first language
            let langs = getLanguagesProc.bufferList
                .filter(lang => lang.trim().length > 0 && lang !== "auto")
                .sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = []; // Clear the buffer
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent

                RowLayout { // Target language + swap
                    Layout.fillWidth: true
                    spacing: 4

                    LanguageSelectorButton { // Target language button
                        id: targetLanguageButton
                        Layout.fillWidth: true
                        displayText: root.targetLanguage
                        onClicked: {
                            root.showLanguageSelectorDialog(true);
                        }
                    }

                    GroupButton { // Swap source ↔ target
                        id: swapButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "swap_vert"
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip { text: Translation.tr("Swap languages") }
                        onClicked: root.swapLanguages()
                    }
                }

                TextCanvas { // Content translation
                    id: outputCanvas
                    isInput: false
                    placeholderText: Translation.tr("Translation goes here...")
                    property bool hasTranslation: (root.translatedText.trim().length > 0)
                    text: hasTranslation ? root.translatedText : ""

                    // Translating spinner — sits in the action row
                    // while `trans` runs (TextCanvas routes children
                    // into its button row, so a centered overlay isn't
                    // possible here without anchor conflicts).
                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        implicitSize: 22
                        loading: translateProc.running
                        visible: translateProc.running
                    }

                    GroupButton { // Speak / pronounce the translation
                        id: speakButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "volume_up"
                            color: speakButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        StyledToolTip { text: Translation.tr("Listen") }
                        onClicked: {
                            speakProc.running = false;
                            speakProc.running = true;
                        }
                    }
                    GroupButton {
                        id: copyButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "content_copy"
                            color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            Quickshell.clipboardText = outputCanvas.displayedText
                        }
                    }
                    GroupButton {
                        id: searchButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "travel_explore"
                            color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                    }
                }

            }    
        }

        RowLayout { // Source language + auto-detect readout
            Layout.fillWidth: true
            spacing: 6

            LanguageSelectorButton { // Source language button
                id: sourceLanguageButton
                Layout.fillWidth: true
                displayText: root.sourceLanguage
                onClicked: {
                    root.showLanguageSelectorDialog(false);
                }
            }

            StyledText { // "detected: …" — only when source is auto
                Layout.alignment: Qt.AlignVCenter
                visible: root.sourceLanguage === "auto"
                      && root.detectedLanguage.length > 0
                text: Translation.tr("detected: %1").arg(root.detectedLanguage)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        TextCanvas { // Content input
            id: inputCanvas
            isInput: true
            placeholderText: Translation.tr("Enter text to translate...")
            onInputTextChanged: {
                translateTimer.restart();
            }
            GroupButton {
                id: pasteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "content_paste"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = Quickshell.clipboardText
                }
            }
            GroupButton {
                id: deleteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.inputTextArea.text.length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "close"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = ""
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: (result) => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return; // No selection made

                if (root.languageSelectorTarget) {
                    root.targetLanguage = result;
                    Config.options.language.translator.targetLanguage = result; // Save to config
                } else {
                    root.sourceLanguage = result;
                    Config.options.language.translator.sourceLanguage = result; // Save to config
                }

                translateTimer.restart(); // Restart translation after language change
            }
        }
    }
}
