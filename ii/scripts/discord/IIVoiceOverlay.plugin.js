/**
 * @name IIVoiceOverlay
 * @author caesar
 * @version 0.1.0
 * @description Publishes your current voice channel (who is in it, who is speaking, mute and deafen state) to a file in the runtime dir for the shell's overlay to draw. Local only: nothing is sent anywhere.
 */

// Discord has no in-game overlay on Linux Wayland, and its RPC is whitelist-only,
// so the data is read from inside the client instead. Everything here is a read
// of Discord's own stores plus one file write; it controls nothing.
//
// The file is rewritten in place (it is tiny, so one write is effectively
// atomic) rather than renamed over, because the reader watches the path.

module.exports = class IIVoiceOverlay {
    constructor(meta) { this.meta = meta; }

    start() {
        const fs = require("fs");
        const path = require("path");
        const W = BdApi.Webpack;

        this.file = path.join(process.env.XDG_RUNTIME_DIR || "/tmp", "ii-discord-voice.json");
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

    snapshot() {
        const { channel, voice, user, chan, guild, member } = this.s;
        const channelId = channel.getVoiceChannelId?.();
        if (!channelId) return { inVoice: false };

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
        } catch (e) { /* runtime dir missing: nothing to publish to */ }
    }
};
