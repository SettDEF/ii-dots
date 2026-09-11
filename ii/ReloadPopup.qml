// Reload result popup.
//
// DELIBERATELY SELF-CONTAINED. It imports nothing from modules/common — no
// Appearance, no Config, no widgets. This is the one surface that has to work
// when the config is broken, and a theming dependency is a dependency that can
// fail with it. Hence the literal colours and plain Text/Rectangle.
//
// What it does beyond "a message appeared":
//   · the error is SELECTABLE and copyable, because the useful next step is
//     almost always pasting it somewhere
//   · long errors collapse to a few lines with a toggle, instead of a wall
//   · a failure does not auto-dismiss — the shell is still running the OLD
//     code at that point, which is exactly the thing you must not miss
//   · it names the log file and the command that follows it
//   · it pulls the first `@file[line:col]` out of the message so the location
//     is one copy away
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
	id: root
	property bool failed;
	property string errorString;
	property string stamp: "";

	// Resolved lazily, and only on failure — there is no reason to shell out
	// on a successful reload.
	property string logPath: "";

	readonly property var errorLines: root.errorString.length > 0
		? root.errorString.replace(/\s+$/, "").split("\n")
		: []
	// How many lines to show before the "show all" toggle.
	readonly property int collapsedLines: 6

	// Paths and copy actions start hidden behind the arrow.
	property bool detailsOpen: false

	// First `@some/file.qml[12:34]` in the message. That is the line you
	// actually want to open, and digging it out of the prose by hand is a
	// small tax paid on every broken reload.
	readonly property string firstLocation: {
		const m = /@([^\s\[]+)\[(\d+):(-?\d+)\]/.exec(root.errorString);
		return m ? (m[1] + ":" + m[2]) : "";
	}

	function copyToClipboard(text) {
		if (!text || text.length === 0) return;
		Quickshell.clipboardText = text;
	}

	Process {
		id: logProbe
		command: ["bash", "-c",
			"ls -t \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"/quickshell/by-id/*/log.qslog 2>/dev/null | head -1"]
		stdout: StdioCollector {
			onStreamFinished: root.logPath = String(text).trim()
		}
	}

	// Connect to the Quickshell global to listen for the reload signals.
	Connections {
		target: Quickshell

		function onReloadCompleted() {
			root.failed = false;
			root.errorString = "";
			popupLoader.loading = true;
		}

		function onReloadFailed(error: string) {
			// Close any existing popup before making a new one.
			popupLoader.active = false;

			root.failed = true;
			root.errorString = error;
			root.stamp = Qt.formatDateTime(new Date(), "HH:mm:ss");
			logProbe.running = true;
			popupLoader.loading = true;
		}
	}

	// Keep the popup in a loader because it isn't needed most of the time
	LazyLoader {
		id: popupLoader

		PanelWindow {
			id: popup

			exclusiveZone: 0
			anchors.top: true
			margins.top: 0

			implicitWidth: rect.width + shadow.radius * 2
			implicitHeight: rect.height + shadow.radius * 2

			WlrLayershell.namespace: "quickshell:reloadPopup"
			// OnDemand so clicking the popup gives it the keyboard (for Esc and
			// for dragging a selection) without stealing focus from whatever
			// you were typing in when the reload fired.
			WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

			// color blending is a bit odd as detailed in the type reference.
			color: "transparent"

			readonly property color fg: root.failed ? "#ff93000A" : "#ff0C1F13"
			readonly property color dim: root.failed ? "#bb93000A" : "#bb0C1F13"

			Rectangle {
				id: rect
				anchors.centerIn: parent
				color: root.failed ? "#ffe99195" : "#ffD1E8D5"

				implicitHeight: layout.implicitHeight + 30
				// Wide enough for a stack trace line without wrapping every
				// second word, but never wider than the screen.
				implicitWidth: Math.min(
					Math.max(layout.implicitWidth + 30, 420),
					(popup.screen?.width ?? 1920) - 40)
				radius: 12

				// Declared HERE, not on the ColumnLayout: every reader says
				// `rect.expanded`, and on the layout it silently resolved to
				// undefined — the toggle rendered but never expanded anything.
				property bool expanded: root.errorLines.length <= root.collapsedLines

				focus: true
				Keys.onEscapePressed: event => { popupLoader.active = false; event.accepted = true }
				Keys.onPressed: event => {
					if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
						root.copyToClipboard(root.errorString);
						event.accepted = true;
					}
				}

				// Hover tracking only. It no longer dismisses on press: a click
				// anywhere used to close the popup, which made selecting the
				// error text impossible — the drag that starts a selection is a
				// press. Dismissal is the Dismiss button and Esc now.
				MouseArea {
					id: mouseArea
					anchors.fill: parent
					acceptedButtons: Qt.NoButton
					hoverEnabled: true
				}

				ColumnLayout {
					id: layout
					spacing: 8
					anchors {
						top: parent.top
						left: parent.left
						right: parent.right
						topMargin: 10
						leftMargin: 15
						rightMargin: 15
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: 8

						Text {
							renderType: Text.NativeRendering
							font.family: "Google Sans Flex"
							font.pointSize: 14
							text: root.failed ? "Quickshell: Reload failed" : "Quickshell reloaded"
							color: popup.fg
						}
						Text {
							visible: root.stamp.length > 0 && root.failed
							renderType: Text.NativeRendering
							font.family: "JetBrains Mono NF"
							font.pointSize: 9
							text: root.stamp
							color: popup.dim
						}
						Item { Layout.fillWidth: true }
						// The details arrow lives in the HEADER, not down with the
						// buttons: it is the control that changes the SHAPE of this
						// card, and a disclosure that sits below the thing it
						// discloses moves as soon as you use it.
						// Round arrow: the only affordance for the details.
						Rectangle {
							visible: root.failed
							implicitWidth: 26
							implicitHeight: 26
							radius: 13
							color: detHov.hovered ? Qt.alpha(popup.fg, 0.18)
												  : Qt.alpha(popup.fg, 0.09)
							Behavior on color { ColorAnimation { duration: 120 } }
							HoverHandler { id: detHov; cursorShape: Qt.PointingHandCursor }
							TapHandler { onTapped: root.detailsOpen = !root.detailsOpen }
							Text {
								anchors.centerIn: parent
								renderType: Text.NativeRendering
								font.family: "Google Sans Flex"
								font.pointSize: 11
								text: "\u2304"          // ⌄
								color: popup.fg
								rotation: root.detailsOpen ? 180 : 0
								Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
							}
						}
					}

					// The shell keeps serving the PREVIOUS config after a failed
					// reload. Saying so is the difference between "an error
					// flashed" and "nothing I edit is taking effect".
					Text {
						visible: root.failed
						Layout.fillWidth: true
						renderType: Text.NativeRendering
						font.family: "Google Sans Flex"
						font.pointSize: 10
						text: "Still running the last config that loaded. Fix and save to retry."
						color: popup.dim
						wrapMode: Text.WordWrap
					}

					// ── The error itself ────────────────────────────────
					// TextEdit, not Text: read-only but selectable, so the
					// message can be dragged over and copied like any text.
					Rectangle {
						visible: root.errorString !== ""
						Layout.fillWidth: true
						color: "#22000000"
						radius: 8
						implicitHeight: Math.min(errFlick.contentHeight + 16, 420)

						Flickable {
							id: errFlick
							anchors.fill: parent
							anchors.margins: 8
							contentHeight: errText.implicitHeight
							contentWidth: width
							clip: true
							boundsBehavior: Flickable.StopAtBounds
							interactive: rect.expanded

							TextEdit {
								id: errText
								width: errFlick.width
								readOnly: true
								selectByMouse: true
								renderType: Text.NativeRendering
								font.family: "JetBrains Mono NF"
								font.pointSize: 11
								color: popup.fg
								selectionColor: popup.fg
								selectedTextColor: rect.color
								wrapMode: TextEdit.Wrap
								text: rect.expanded
									? root.errorString
									: root.errorLines.slice(0, root.collapsedLines).join("\n")
							}
						}
					}

					RowLayout {
						visible: root.errorLines.length > root.collapsedLines
							|| (root.failed && root.detailsOpen)
						Layout.fillWidth: true
						spacing: 6
						PlainButton {
							visible: root.errorLines.length > root.collapsedLines
							fg: popup.fg
							text: rect.expanded
								? "Show less"
								: ("Show all " + root.errorLines.length + " lines")
							onTapped: rect.expanded = !rect.expanded
						}
						Item { Layout.fillWidth: true }

						// Only once the card is expanded. Collapsed, the popup
						// is a one-line status and the countdown clears it on its
						// own; Esc still works either way.
						PlainButton { fg: popup.fg; text: "Dismiss"
							visible: root.failed && root.detailsOpen
							onTapped: popupLoader.active = false }

					}

					// ── Where to look next ──────────────────────────────
					// Collapsed behind the arrow. A reload popup is glanced at
					// and dismissed nine times out of ten; the paths and the
					// four copy actions are for the tenth, and having them
					// always open made the card twice as tall as its message.
					Text {
						visible: root.detailsOpen && root.failed && root.firstLocation.length > 0
						Layout.fillWidth: true
						renderType: Text.NativeRendering
						font.family: "JetBrains Mono NF"
						font.pointSize: 9
						text: "first error: " + root.firstLocation
						color: popup.dim
						elide: Text.ElideMiddle
					}
					Text {
						visible: root.detailsOpen && root.failed && root.logPath.length > 0
						Layout.fillWidth: true
						renderType: Text.NativeRendering
						font.family: "JetBrains Mono NF"
						font.pointSize: 9
						text: "log: " + root.logPath + "   ·   follow with:  qs -c ii log -f"
						color: popup.dim
						elide: Text.ElideMiddle
					}

					RowLayout {
						visible: root.detailsOpen && root.failed
						Layout.fillWidth: true
						Layout.bottomMargin: 4
						spacing: 6
						PlainButton { fg: popup.fg; text: "Copy error"
							onTapped: root.copyToClipboard(root.errorString) }
						PlainButton { fg: popup.fg; text: "Copy location"
							visible: root.firstLocation.length > 0
							onTapped: root.copyToClipboard(root.firstLocation) }
						PlainButton { fg: popup.fg; text: "Copy log path"
							visible: root.logPath.length > 0
							onTapped: root.copyToClipboard(root.logPath) }
						Item { Layout.fillWidth: true }
					}

					// Spacer so the countdown bar never sits on the text.
					Item { implicitHeight: 6 }
				}

				// A progress bar on the bottom of the screen, showing how long until the
				// popup is removed. Success only — a failure stays until dismissed.
				Rectangle {
					z: 2
					id: bar
					color: popup.fg
					anchors.bottom: parent.bottom
					anchors.left: parent.left
					anchors.margins: 10
					height: 5
					radius: 9999

					PropertyAnimation {
						id: anim
						target: bar
						property: "width"
						from: rect.width - bar.anchors.margins * 2
						to: 0
						duration: 1000
						onFinished: popupLoader.active = false

						// Pause the animation when the mouse is hovering over the popup,
						// so it stays onscreen while reading. This updates reactively
						// when the mouse moves on and off the popup.
						paused: mouseArea.containsMouse
					}
				}
				// Its bg
				Rectangle {
					z: 1
					id: bar_bg
					color: root.failed ? "#30af1b25" : "#4027643e"
					anchors.bottom: parent.bottom
					anchors.left: parent.left
					anchors.margins: 10
					height: 5
					radius: 9999
					width: rect.width - bar.anchors.margins * 2
				}

				// We could set `running: true` inside the animation, but the width of the
				// rectangle might not be calculated yet, due to the layout.
				// In the `Component.onCompleted` event handler, all of the component's
				// properties and children have been initialized.
				Component.onCompleted: anim.start()
			}

			DropShadow {
				id: shadow
				anchors.fill: rect
				horizontalOffset: 0
				verticalOffset: 2
				radius: 6
				samples: radius * 2 + 1 // Ideally should be 2 * radius + 1, see qt docs
				color: "#44000000"
				source: rect
			}
		}
	}

	// Minimal button, local to this file for the same reason as the colours:
	// no dependency on the widget library that may be the thing that broke.
	component PlainButton: Rectangle {
		id: btn
		property string text: ""
		property color fg: "#ff0C1F13"
		signal tapped()

		implicitHeight: 26
		implicitWidth: btnLabel.implicitWidth + 20
		radius: 13
		color: btnHov.hovered ? Qt.alpha(btn.fg, 0.18) : Qt.alpha(btn.fg, 0.09)
		Behavior on color { ColorAnimation { duration: 120 } }

		HoverHandler { id: btnHov; cursorShape: Qt.PointingHandCursor }
		TapHandler { onTapped: btn.tapped() }

		Text {
			id: btnLabel
			anchors.centerIn: parent
			renderType: Text.NativeRendering
			font.family: "Google Sans Flex"
			font.pointSize: 10
			text: btn.text
			color: btn.fg
		}
	}
}
