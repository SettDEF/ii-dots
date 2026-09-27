import qs.services
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

/**
 * Renders one pack effect. Used both by the window overlay and by the small
 * live previews in the effect lists, so an effect is described in exactly one
 * place — previously the overlay owned the only implementation, which is why
 * a preview was impossible without copying all of it.
 *
 * Properties
 *   fx        : the effect descriptor ({ kind, color, strength, speed, ... })
 *   values    : resolved parameter overrides; falls back to fx.values
 *   rounding  : corner radius in px, so it can match a window's corners
 *   animated  : false freezes the clock (previews you have toggled off)
 *   fps       : tick rate. 30 by default — this runs for as long as an app is
 *               focused, and a vsync-locked repaint of a full-window overlay
 *               on a 180Hz panel is real battery cost for motion nobody
 *               perceives above ~30.
 */
Item {
    id: root

    property var fx: null
    property var values: null
    // The window to sample for effects that DISPLACE what is underneath them
    // (a Toplevel). Without it a shader can only composite on top, because a
    // Wayland surface cannot read the pixels beneath itself.
    property var captureSource: null
    // An item to sample DIRECTLY, bypassing screen capture entirely. The
    // wallpaper is already ours to render, so a warp effect over it needs no
    // ScreencopyView at all — this is both cheaper and available on surfaces
    // that have no Toplevel behind them.
    property Item sourceItem: null
    property real rounding: 0
    // Previews may substitute a stand-in when there is no window to sample.
    // A real overlay must NOT: if the capture fails there, drawing a stand-in
    // paints fake content over your actual window, which is far worse than
    // simply showing nothing.
    property bool previewMode: false
    property bool animated: true
    // Per-effect tick rate: a cheap tint has no business running as fast as a
    // sampling warp, and a sampling warp has no business running faster than
    // the eye resolves. Effects declare "fps" in their JSON.
    property real fps: root.fx?.fps ?? 30

    readonly property var v: root.values ?? root.fx?.values ?? ({})
    readonly property string kind: root.fx?.kind ?? ""

    function num(id, dflt) {
        return root.v[id] !== undefined ? root.v[id] : dflt;
    }

    readonly property real amt: root.num("strength", root.fx?.strength ?? 0.3)
    readonly property real rate: root.num("speed", root.fx?.speed ?? 1.0)
    // Resolve theme roles HERE rather than in the service. Reading
    // Appearance through AppDisplay.themeColor() inside a binding makes this
    // depend on the theme, so "@primary" repaints the moment the wallpaper
    // palette changes instead of staying at whatever it was when the effect
    // was applied.
    function col(id, dflt) {
        const raw = root.v[id] !== undefined ? root.v[id] : dflt;
        return (typeof raw === "string" && raw.startsWith("@"))
            ? AppDisplay.themeColor(raw) : raw;
    }

    readonly property color tone: root.col("color", root.fx?.color ?? "#FFFFFF")

    // A glsl effect computes every pixel from `time` and rounds its own edge,
    // so it needs neither the mask pass nor a fade — compositing either on top
    // would layer a second, unrelated animation over the shader's own.
    readonly property bool rawGlsl: root.kind === "glsl"

    property real phase: 0
    Timer {
        // `visible` is the real gate: an effect whose row is scrolled out of
        // view, or whose panel is closed, must not keep burning frames.
        running: root.animated && root.fx !== null && root.visible
        repeat: true
        interval: Math.max(16, Math.round(1000 / root.fps))
        onTriggered: root.phase += (1.0 / root.fps) * root.rate
    }

    // 0..1 breathing curve shared by every pulsing kind.
    readonly property real puls: 0.5 + 0.5 * Math.sin(root.phase * 6.2831)

    Item {
        id: fxMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: root.rounding
            antialiasing: true
            color: "white"
        }
    }

    // The mask is an offscreen texture round-trip of the whole surface, every
    // frame. The drawn kinds need it (Item.clip is rectangular, so they would
    // square off the corners); glsl does not.
    MultiEffect {
        anchors.fill: parent
        visible: !root.rawGlsl
        source: fxContent
        maskEnabled: true
        maskSource: fxMask
    }

    Item {
        id: fxContent
        anchors.fill: parent
        // Drawn directly for glsl (no mask pass), captured into a layer for
        // the kinds that are masked.
        visible: root.rawGlsl
        layer.enabled: !root.rawGlsl

        // ── Sampling GLSL: warps the window itself ──────────────────────
        // The live capture of the window is fed in as `source`, so the shader
        // can move pixels rather than tint them — this is what makes text look
        // like it is rippling instead of merely changing colour. It costs a
        // continuous capture of the window, so only effects that declare
        // "samples": true pay for it.
        Loader {
            anchors.fill: parent
            active: root.kind === "glsl" && root.fx?.samples === true
                    && (root.captureSource !== null || root.sourceItem !== null
                        || root.previewMode)
            sourceComponent: Item {
                // With a window to sample we warp the real thing; without one
                // (the list previews) we warp a stand-in, so you can still see
                // WHAT the distortion does to text instead of a blank tile.
                ScreencopyView {
                    id: grab
                    anchors.fill: parent
                    captureSource: root.captureSource
                    live: true
                    visible: false
                    layer.enabled: root.sourceItem === null && root.captureSource !== null
                }
                Item {
                    id: standIn
                    anchors.fill: parent
                    visible: false
                    layer.enabled: root.previewMode && root.captureSource === null
                                   && root.sourceItem === null
                    Rectangle { anchors.fill: parent; color: "#11151F" }
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                required property int index
                                width: standIn.width * (index % 2 === 0 ? 0.62 : 0.44)
                                height: Math.max(2, standIn.height * 0.09)
                                radius: 1
                                color: "#C8D4E8"
                            }
                        }
                    }
                }
                ShaderEffect {
                    anchors.fill: parent
                    property var source: root.sourceItem !== null ? root.sourceItem
                                       : root.captureSource !== null ? grab : standIn
                    visible: root.sourceItem !== null || root.captureSource !== null
                             || root.previewMode
                    fragmentShader: root.fx?.shader
                        ? Qt.resolvedUrl("shaders/" + root.fx.shader) : ""
                    property real time: root.phase
                    property real strength: root.amt
                    property real aspect: height > 0 ? width / height : 1.0
                    property real radius: root.rounding
                    property real pxh: height
                    property real p1: root.num("p1", 0.42)
                    property real p2: root.num("p2", 4.0)
                    property real p3: root.num("p3", 0.28)
                    property real p4: root.num("p4", 1.18)
                    property color c1: root.col("c1", "#121B6B")
                    property color c2: root.col("c2", "#BD1A36")
                }
            }
        }

        // ── Real GLSL ───────────────────────────────────────────────────
        // Gated on the KIND, never on `visible`: this item is visible:false
        // whenever it feeds the mask, and QML's `visible` reads EFFECTIVE
        // visibility, so reading it here is always false and the shader would
        // never load. The layer still renders; only the property lies.
        ShaderEffect {
            anchors.fill: parent
            readonly property bool armed: root.kind === "glsl" && root.fx !== null
                && root.fx?.samples !== true
            visible: armed
            fragmentShader: armed && root.fx?.shader
                ? Qt.resolvedUrl("shaders/" + root.fx.shader) : ""
            // Declared even though a non-sampling shader never reads it: Qt
            // resolves the sampler by name against this item's properties, and
            // without one it warns per instance — thirteen lines every time the
            // effects list opens. Null is the honest value; there is no window
            // being sampled on this path, which is what distinguishes it from
            // the sampling branch above.
            property var source: null
            // The rest must match the shader's ABI block exactly.
            property real time: root.phase
            property real strength: root.amt
            property real aspect: height > 0 ? width / height : 1.0
            property real radius: root.rounding
            property real pxh: height
            property real p1: root.num("p1", 0.42)
            property real p2: root.num("p2", 4.0)
            property real p3: root.num("p3", 0.28)
            property real p4: root.num("p4", 1.18)
            property color c1: root.col("c1", "#121B6B")
            property color c2: root.col("c2", "#BD1A36")
        }

        // ── Vignette ────────────────────────────────────────────────────
        // Painted once into a Canvas and merely faded; repainting a radial
        // gradient every tick would dominate the frame budget.
        Canvas {
            anchors.fill: parent
            visible: root.kind === "vignette"
            opacity: root.amt * (0.35 + 0.65 * root.puls)
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2;
                const g = ctx.createRadialGradient(cx, cy, Math.min(width, height) * 0.25,
                                                   cx, cy, Math.max(width, height) * 0.72);
                const c = root.tone;
                g.addColorStop(0.0, Qt.alpha(c, 0.0));
                g.addColorStop(0.6, Qt.alpha(c, 0.45));
                g.addColorStop(1.0, Qt.alpha(c, 1.0));
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, width, height);
            }
        }

        // ── Scanlines ───────────────────────────────────────────────────
        Item {
            id: scanBox
            anchors.fill: parent
            visible: root.kind === "scanlines"
            clip: true
            opacity: root.amt
            Column {
                id: scanCol
                width: scanBox.width
                y: -6 + ((root.phase * 60) % 6)
                Repeater {
                    // Named ids, not `parent`. A Repeater delegate has NO
                    // parent while it is being constructed, so `parent.width`
                    // here threw "Cannot read property 'width' of null" on
                    // every single row it built — 12,900 of them in the
                    // current log, by far the loudest thing in the shell.
                    // `parent.parent` on the Repeater was the same trap one
                    // level up.
                    model: Math.ceil(scanBox.height / 6) + 2
                    delegate: Rectangle {
                        width: scanCol.width
                        height: 3
                        color: root.tone
                    }
                }
            }
        }

        // ── Grain ───────────────────────────────────────────────────────
        // Pre-rendered noise tiles cycled, so no pixels are generated per frame.
        Item {
            anchors.fill: parent
            visible: root.kind === "grain"
            clip: true
            opacity: root.amt
            Repeater {
                model: 4
                delegate: Canvas {
                    required property int index
                    anchors.fill: parent
                    visible: Math.floor(root.phase * 8) % 4 === index
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const c = root.tone;
                        for (let i = 0; i < 900; ++i) {
                            const x = (i * 7919 + index * 104729) % Math.max(1, width);
                            const y = (i * 104729 + index * 7919) % Math.max(1, height);
                            ctx.fillStyle = Qt.alpha(c, 0.35);
                            ctx.fillRect(x, y, 2, 2);
                        }
                    }
                }
            }
        }

        // ── Flat colour pulse ───────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            visible: root.kind === "tint"
            radius: root.rounding
            antialiasing: true
            color: Qt.alpha(root.tone, root.amt * root.puls)
        }

        // ── Hue cycle ───────────────────────────────────────────────────
        // Alpha is constant and only the hue moves, so it reads as a colour
        // shift rather than a flicker.
        Rectangle {
            anchors.fill: parent
            visible: root.kind === "hue"
            radius: root.rounding
            antialiasing: true
            color: Qt.hsla((root.phase * 0.35) % 1.0, 0.85, 0.55, root.amt)
        }

        // ── Shimmer ─────────────────────────────────────────────────────
        // Rectangle gradients are vertical only, so the band is built upright
        // and the whole item rotated.
        Item {
            anchors.fill: parent
            visible: root.kind === "shimmer"
            clip: true
            Rectangle {
                readonly property real span: parent.width + parent.height
                width: span * 0.30
                height: span * 1.8
                y: -parent.height * 0.4
                x: -width + ((root.phase * 0.5) % 1.35) * (parent.width + width)
                rotation: 24
                transformOrigin: Item.Center
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.alpha(root.tone, root.amt) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // ── Plasma ──────────────────────────────────────────────────────
        // Each blob is painted ONCE into its own Canvas and then just moved.
        Item {
            id: plasmaBox
            anchors.fill: parent
            visible: root.kind === "plasma"
            clip: true
            opacity: root.amt
            Repeater {
                model: [
                    { hue: 0.60, ax: 0.30, ay: 0.22, sx: 0.7, sy: 1.1 },
                    { hue: 0.95, ax: 0.26, ay: 0.30, sx: 1.3, sy: 0.8 },
                    { hue: 0.76, ax: 0.34, ay: 0.18, sx: 0.9, sy: 1.5 }
                ]
                delegate: Canvas {
                    required property var modelData
                    required property int index
                    // See the scanlines note: `parent` is null while a
                    // Repeater delegate is being built.
                    readonly property real blobSize: Math.max(plasmaBox.width, plasmaBox.height) * 0.85
                    width: blobSize
                    height: blobSize
                    x: plasmaBox.width * (0.5 + modelData.ax
                        * Math.sin(root.phase * modelData.sx + index)) - blobSize / 2
                    y: plasmaBox.height * (0.5 + modelData.ay
                        * Math.cos(root.phase * modelData.sy + index)) - blobSize / 2
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const r = blobSize / 2;
                        const g = ctx.createRadialGradient(r, r, 0, r, r, r);
                        const c = Qt.hsla(modelData.hue, 0.9, 0.55, 1.0);
                        g.addColorStop(0.0, Qt.alpha(c, 0.85));
                        g.addColorStop(0.55, Qt.alpha(c, 0.30));
                        g.addColorStop(1.0, Qt.alpha(c, 0.0));
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, width, height);
                    }
                }
            }
        }

        // ── Sparkle ─────────────────────────────────────────────────────
        // Deterministic positions and staggered phases: cheap, and it stops
        // the dots from blinking in unison.
        Item {
            anchors.fill: parent
            visible: root.kind === "sparkle"
            clip: true
            Repeater {
                model: 26
                delegate: Rectangle {
                    required property int index
                    readonly property real seedX: ((index * 7919) % 997) / 997
                    readonly property real seedY: ((index * 104729) % 991) / 991
                    readonly property real off: ((index * 37) % 100) / 100
                    width: 3 + (index % 3)
                    height: width
                    radius: width / 2
                    x: seedX * (parent.width - width)
                    y: seedY * (parent.height - height)
                    color: root.tone
                    opacity: root.amt * Math.max(0.0,
                        Math.sin((root.phase + off) * 6.2831))
                }
            }
        }

        // ── Neon rim ────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            visible: root.kind === "edgeGlow"
            radius: root.rounding
            antialiasing: true
            color: "transparent"
            border.width: 2 + 4 * root.puls
            border.color: Qt.alpha(root.tone, root.amt * (0.4 + 0.6 * root.puls))
        }
    }
}






