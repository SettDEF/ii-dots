/**
 * @name IIVoiceOverlay
 * @author caesar
 * @version 0.2.0
 * @description Publishes your voice channel and your voice settings to a file for the desktop shell (overlay, dock menu), and applies voice-setting changes the shell asks for (mute, deafen, push to talk, noise suppression, volumes, devices). Local only: nothing is sent anywhere.
 */

// Discord has no in-game overlay on Linux Wayland, and its RPC is whitelist-only,
// so the data is read from inside the client instead.
//
// Out:  ii-discord-voice.json — the channel, its members, and `settings` (your
//       voice settings as Discord holds them).
// In:   ii-discord-cmd.json   — { id, action, value } from the shell's dock menu.
//       Applied through Discord's own action creators, so a change made from
//       the dock is exactly the change the Voice & Video settings page makes,
//       and is saved the same way.
//
// The file is rewritten in place (it is tiny, so one write is effectively
// atomic) rather than renamed over, because the reader watches the path.

module.exports = class IIVoiceOverlay {
    constructor(meta) { this.meta = meta; }

    start() {
        // A throw here used to be silent: no toast, no file, and the overlay
        // just said "not in a channel". Say what broke instead.
        try { this.init(); }
        catch (e) { BdApi.UI.showToast(`IIVoiceOverlay failed to start: ${e?.message ?? e}`, { type: "error", timeout: 8000 }); }
    }

    init() {
        const fs = require("fs");
        const path = require("path");
        const W = BdApi.Webpack;

        // Next to BetterDiscord's own data, not $XDG_RUNTIME_DIR: BD's
        // `process` shim may carry no environment at all, which threw on
        // process.env and stopped the plugin before its first write. The
        // shell's services/DiscordVoice.qml reads this same path.
        this.file = path.join(BdApi.Plugins.folder, "..", "data", "ii-discord-voice.json");
        this.fs = fs;
        this.speaking = new Set();
        this.last = "";

        // Stores by name; getStore is the supported lookup, the filter is the
        // fallback for builds where it is missing.
        const store = name => (W.getStore ? W.getStore(name) : null)
            ?? W.getModule(m => m?.getName?.() === name, { searchExports: true });
        this.s = {
            channel: store("SelectedChannelStore"),
            voice: store("VoiceStateStore"),
            user: store("UserStore"),
            chan: store("ChannelStore"),
            guild: store("GuildStore"),
            member: store("GuildMemberStore"),
        };
        this.dispatcher = W.getModule(W.Filters.byKeys("dispatch", "subscribe", "unsubscribe"));

        // Voice settings: read from MediaEngineStore, changed through the
        // audio action creators. Each is optional — a Discord update that
        // renames one costs that one control, not the plugin.
        this.media = store("MediaEngineStore");
        this.audio = W.getModule(W.Filters.byKeys("toggleSelfMute", "toggleSelfDeaf"))
            ?? W.getModule(W.Filters.byKeys("toggleSelfMute"), { searchExports: true });
        this.engine = W.getModule(W.Filters.byKeys("setInputVolume", "setOutputVolume"))
            ?? W.getModule(W.Filters.byKeys("setInputVolume"), { searchExports: true });
        this.cmdFile = path.join(BdApi.Plugins.folder, "..", "data", "ii-discord-cmd.json");
        this.lastCmd = null;
        this.onMedia = () => this.schedule();
        this.media?.addChangeListener?.(this.onMedia);
        // A command file is polled, not watched: fs.watch on a file replaced
        // by the writer stops firing after the first replace.
        this.cmdPoll = setInterval(() => this.readCommand(), 250);

        if (!this.dispatcher || !this.s.channel || !this.s.voice || !this.s.user) {
            BdApi.UI.showToast("IIVoiceOverlay: could not find Discord's voice stores", { type: "error" });
            return;
        }

        this.onEvent = () => this.schedule();
        this.onSpeaking = e => {
            if (!e?.userId) return;
            if (e.speakingFlags > 0) this.speaking.add(e.userId); else this.speaking.delete(e.userId);
            this.schedule();
        };
        this.onSelect = () => { this.speaking.clear(); this.schedule(); };

        this.dispatcher.subscribe("VOICE_STATE_UPDATES", this.onEvent);
        this.dispatcher.subscribe("VOICE_CHANNEL_SELECT", this.onSelect);
        this.dispatcher.subscribe("SPEAKING", this.onSpeaking);
        this.dispatcher.subscribe("RTC_CONNECTION_STATE", this.onEvent);

        // The reader treats a file older than ~25 s as stale, so a Discord that
        // dies mid-call does not leave a ghost overlay up. This keeps a live
        // call fresh.
        this.beat = setInterval(() => this.publish(true), 10000);
        this.publish(true);
    }

    stop() {
        try {
            this.dispatcher?.unsubscribe("VOICE_STATE_UPDATES", this.onEvent);
            this.dispatcher?.unsubscribe("VOICE_CHANNEL_SELECT", this.onSelect);
            this.dispatcher?.unsubscribe("SPEAKING", this.onSpeaking);
            this.dispatcher?.unsubscribe("RTC_CONNECTION_STATE", this.onEvent);
        } catch (e) { /* already gone */ }
        try { this.media?.removeChangeListener?.(this.onMedia); } catch (e) { /* gone */ }
        clearInterval(this.cmdPoll);
        clearInterval(this.beat);
        clearTimeout(this.pending);
        this.write({ inVoice: false, updatedAt: Date.now() });
    }

    // Speaking toggles many times a second; one write per 60 ms is plenty.
    schedule() {
        if (this.pending) return;
        this.pending = setTimeout(() => { this.pending = null; this.publish(false); }, 60);
    }

    avatarUrl(user, guildId) {
        let url = "";
        try { url = user?.getAvatarURL?.(guildId, 64, false) ?? ""; } catch (e) { /* use fallback */ }
        if (!url && user) {
            url = user.avatar
                ? `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png?size=64`
                : `https://cdn.discordapp.com/embed/avatars/${this.defaultAvatar(user.id)}.png`;
        }
        if (url.startsWith("//")) url = "https:" + url;
        // Qt may not have a webp reader; the CDN will serve png on request.
        return url.replace(/\.webp(\?|$)/, ".png$1");
    }

    // Discord picks the default avatar from the id; a malformed id should cost
    // one picture, not the whole overlay.
    defaultAvatar(id) {
        try { return Number((BigInt(id) >> 22n) % 6n); } catch (e) { return 0; }
    }

    // Your voice settings, as the Voice & Video page shows them.
    settings() {
        const m = this.media;
        if (!m) return null;
        const call = (f, ...a) => { try { return typeof m[f] === "function" ? m[f](...a) : undefined; } catch (e) { return undefined; } };
        const devices = list => Object.values(list ?? {}).map(d => ({ id: d.id, name: d.name }));
        const opts = call("getModeOptions") ?? {};
        return {
            mute: !!call("isSelfMute"),
            deaf: !!call("isSelfDeaf"),
            mode: call("getMode") ?? null,                 // "VOICE_ACTIVITY" | "PUSH_TO_TALK"
            autoThreshold: opts.autoThreshold ?? null,     // automatic input sensitivity
            threshold: opts.threshold ?? null,             // dB, when not automatic
            noiseSuppression: call("getNoiseSuppression") ?? null,
            noiseCancellation: call("getNoiseCancellation") ?? null,   // Krisp
            echoCancellation: call("getEchoCancellation") ?? null,
            automaticGainControl: call("getAutomaticGainControl") ?? null,
            inputVolume: call("getInputVolume") ?? null,   // 0..100
            outputVolume: call("getOutputVolume") ?? null, // 0..200
            inputDevice: call("getInputDeviceId") ?? null,
            outputDevice: call("getOutputDeviceId") ?? null,
            inputDevices: devices(call("getInputDevices")),
            outputDevices: devices(call("getOutputDevices")),
            can: {
                mute: !!this.audio?.toggleSelfMute, deaf: !!this.audio?.toggleSelfDeaf,
                mode: !!this.audio?.setMode, noise: !!(this.audio?.setNoiseSuppression ?? this.engine?.setNoiseSuppression),
                krisp: !!(this.audio?.setNoiseCancellation ?? this.engine?.setNoiseCancellation),
                echo: !!(this.audio?.setEchoCancellation ?? this.engine?.setEchoCancellation),
                agc: !!(this.audio?.setAutomaticGainControl ?? this.engine?.setAutomaticGainControl),
                volume: !!this.engine?.setInputVolume,
                device: !!(this.engine?.setInputDevice ?? this.audio?.setInputDevice),
            },
        };
    }

    // One command from the shell: { id, action, value }. Each id runs once.
    readCommand() {
        let cmd;
        try { cmd = JSON.parse(this.fs.readFileSync(this.cmdFile, "utf8")); } catch (e) { return; }
        if (!cmd?.id || cmd.id === this.lastCmd) return;
        this.lastCmd = cmd.id;
        // a command older than 10 s is from before this Discord started
        if (cmd.at && Date.now() - cmd.at > 10000) return;
        const a = this.audio ?? {}, e = this.engine ?? {};
        const fn = name => a[name] ?? e[name];
        const v = cmd.value;
        try {
            switch (cmd.action) {
                case "toggleMute": fn("toggleSelfMute")?.(); break;
                case "toggleDeaf": fn("toggleSelfDeaf")?.(); break;
                case "mode": {
                    const opts = this.media?.getModeOptions?.() ?? {};
                    fn("setMode")?.(v, opts);
                    break;
                }
                case "autoThreshold": {
                    const opts = { ...(this.media?.getModeOptions?.() ?? {}), autoThreshold: !!v };
                    fn("setMode")?.(this.media?.getMode?.() ?? "VOICE_ACTIVITY", opts);
                    break;
                }
                case "threshold": {
                    const opts = { ...(this.media?.getModeOptions?.() ?? {}), autoThreshold: false, threshold: Number(v) };
                    fn("setMode")?.(this.media?.getMode?.() ?? "VOICE_ACTIVITY", opts);
                    break;
                }
                case "noiseSuppression": fn("setNoiseSuppression")?.(!!v); break;
                case "noiseCancellation": fn("setNoiseCancellation")?.(!!v); break;
                case "echoCancellation": fn("setEchoCancellation")?.(!!v); break;
                case "automaticGainControl": fn("setAutomaticGainControl")?.(!!v); break;
                case "inputVolume": fn("setInputVolume")?.(Number(v)); break;
                case "outputVolume": fn("setOutputVolume")?.(Number(v)); break;
                case "inputDevice": fn("setInputDevice")?.(String(v)); break;
                case "outputDevice": fn("setOutputDevice")?.(String(v)); break;
                default: return;
            }
        } catch (err) {
            BdApi.UI.showToast(`IIVoiceOverlay: "${cmd.action}" failed: ${err?.message ?? err}`, { type: "error" });
        }
        // the store's change listener publishes too; this covers builds where it does not fire
        setTimeout(() => this.publish(true), 150);
    }

    snapshot() {
        const settings = this.settings();
        const { channel, voice, user, chan, guild, member } = this.s;
        const channelId = channel.getVoiceChannelId?.();
        if (!channelId) return { inVoice: false, settings };

        const ch = chan?.getChannel?.(channelId);
        const guildId = ch?.guild_id ?? null;
        const states = voice.getVoiceStatesForChannel?.(channelId) ?? {};
        const me = user.getCurrentUser?.()?.id;

        const members = Object.values(states).map(vs => {
            const u = user.getUser(vs.userId);
            const nick = guildId ? member?.getNick?.(guildId, vs.userId) : null;
            return {
                id: vs.userId,
                name: nick || u?.globalName || u?.username || vs.userId,
                avatar: this.avatarUrl(u, guildId),
                speaking: this.speaking.has(vs.userId),
                muted: !!(vs.mute || vs.selfMute),
                deafened: !!(vs.deaf || vs.selfDeaf),
                streaming: !!vs.selfStream,
                video: !!vs.selfVideo,
                self: vs.userId === me,
            };
        }).sort((a, b) => a.name.localeCompare(b.name));

        return {
            inVoice: true,
            channel: ch?.name || (ch?.type === 3 ? "Group call" : "Call"),
            guild: guildId ? (guild?.getGuild?.(guildId)?.name ?? "") : "",
            members,
            settings,
        };
    }

    publish(force) {
        let state;
        try { state = this.snapshot(); } catch (e) { state = { inVoice: false, error: String(e) }; }
        const body = JSON.stringify(state);
        // Skip identical content, except the heartbeat, which exists to touch it.
        if (!force && body === this.last) return;
        this.last = body;
        this.write(state);
    }

    write(state) {
        try {
            this.fs.writeFileSync(this.file, JSON.stringify({ ...state, updatedAt: Date.now() }));
        } catch (e) {
            // Once, not every 10 s heartbeat.
            if (!this.warned) BdApi.UI.showToast(`IIVoiceOverlay cannot write ${this.file}: ${e?.message ?? e}`, { type: "error", timeout: 8000 });
            this.warned = true;
        }
    }
};
