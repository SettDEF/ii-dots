.pragma library

// Steam's "Add a non-Steam game" entries live in userdata/<id>/config/shortcuts.vdf,
// a binary key-value format: a type byte, a NUL-terminated key, then a value.
//   0x00 nested object (ends with 0x08)   0x01 string   0x02 uint32 little-endian
// Parsed here, in plain JS, so the launcher needs no helper program for it.

function _utf8(bytes) {
    let enc = "";
    for (let i = 0; i < bytes.length; i++) enc += "%" + (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16);
    try { return decodeURIComponent(enc); }
    catch (e) { return String.fromCharCode.apply(null, bytes); }   // not UTF-8: Latin-1 beats nothing
}

function _object(b, pos) {
    const out = {};
    let p = pos.p;
    const str = () => {
        const s = p;
        while (p < b.length && b[p] !== 0) p++;
        const v = _utf8(b.subarray(s, p));
        p++;                                    // the NUL
        return v;
    };
    while (p < b.length) {
        const type = b[p++];
        if (type === 8) break;                  // end of this object
        const key = str().toLowerCase();        // AppName / appname both occur in the wild
        if (type === 0) { pos.p = p; out[key] = _object(b, pos); p = pos.p; }
        else if (type === 1) out[key] = str();
        else if (type === 2) {
            out[key] = ((b[p]) | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)) >>> 0;
            p += 4;
        } else break;                           // a type we do not know: stop rather than guess
    }
    pos.p = p;
    return out;
}

// appid * 2^32 + 2^25, as a decimal string: the id steam://rungameid/ wants for
// a shortcut. It overflows a double, so it is done in base-1e7 limbs.
function gameId(appid) {
    const BASE = 1e7;
    let limbs = [appid % BASE, Math.floor(appid / BASE)];
    const mul = m => {
        let carry = 0;
        limbs = limbs.map(l => { const v = l * m + carry; carry = Math.floor(v / BASE); return v % BASE; });
        while (carry > 0) { limbs.push(carry % BASE); carry = Math.floor(carry / BASE); }
    };
    mul(65536); mul(65536);
    let carry = 33554432;
    for (let i = 0; i < limbs.length && carry > 0; i++) {
        const v = limbs[i] + carry; limbs[i] = v % BASE; carry = Math.floor(v / BASE);
    }
    while (carry > 0) { limbs.push(carry % BASE); carry = Math.floor(carry / BASE); }
    let s = String(limbs[limbs.length - 1]);
    for (let i = limbs.length - 2; i >= 0; i--) s += String(limbs[i]).padStart(7, "0");
    return s;
}

/// [{ name, exe, startDir, launchOptions, appid, gameId, hidden }]
function parse(buffer) {
    const b = new Uint8Array(buffer);
    if (b.length < 3 || b[0] !== 0) return [];
    const pos = { p: 1 };
    while (pos.p < b.length && b[pos.p] !== 0) pos.p++;   // the "shortcuts" key
    pos.p++;
    const root = _object(b, pos);
    return Object.keys(root).map(k => root[k]).filter(e => e && e.appname).map(e => ({
        name: e.appname,
        exe: e.exe ?? "",
        startDir: e.startdir ?? "",
        launchOptions: e.launchoptions ?? "",
        appid: e.appid ?? 0,
        gameId: gameId(e.appid ?? 0),
        hidden: (e.ishidden ?? 0) !== 0
    }));
}
