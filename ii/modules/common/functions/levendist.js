// Fuzzy match scoring. Every function returns 0..1, higher is better, so
// callers share one threshold and sort descending.

/// Two rows, not an n*m matrix: the haystack can be a whole clipboard entry.
function editDistance(a, b) {
    if (a === b) return 0;
    if (a.length === 0) return b.length;
    if (b.length === 0) return a.length;

    let prev = new Array(b.length + 1);
    let curr = new Array(b.length + 1);
    for (let j = 0; j <= b.length; j++) prev[j] = j;

    for (let i = 1; i <= a.length; i++) {
        curr[0] = i;
        const ca = a.charCodeAt(i - 1);
        for (let j = 1; j <= b.length; j++) {
            const cost = ca === b.charCodeAt(j - 1) ? 0 : 1;
            const del = prev[j] + 1;
            const ins = curr[j - 1] + 1;
            const sub = prev[j - 1] + cost;
            curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
        }
        const swap = prev; prev = curr; curr = swap;
    }
    return prev[b.length];
}

/// Similarity of two strings of any length, 0..1.
function similarity(a, b) {
    const longest = Math.max(a.length, b.length);
    if (longest === 0) return 1;
    return 1 - editDistance(a, b) / longest;
}

/// Best score against any window of the haystack the needle's own length.
/// Whole-string similarity of "fox" and "the quick brown fox" is near zero.
function bestWindow(needle, hay) {
    if (needle.length === 0) return 1;
    if (needle.length >= hay.length) return similarity(needle, hay);

    let best = 0;
    for (let i = 0; i + needle.length <= hay.length; i++) {
        const score = 1 - editDistance(needle, hay.substr(i, needle.length)) / needle.length;
        if (score > best) best = score;
        if (best === 1) break;
    }
    return best;
}

/// How many leading characters two strings share.
function sharedPrefix(a, b) {
    const limit = Math.min(a.length, b.length);
    let n = 0;
    while (n < limit && a[n] === b[n]) n++;
    return n;
}

function clamp01(x) {
    return x < 0 ? 0 : (x > 1 ? 1 : x);
}

/// For short labels. Weighted to the whole string: between two short strings
/// a window match is nearly free and would rank every 3-letter app alike.
function computeScore(s1, s2) {
    if (s1 === s2) return 1;
    if (s1.length === 0 || s2.length === 0) return 0;

    const short = s1.length <= s2.length ? s1 : s2;
    const long = s1.length <= s2.length ? s2 : s1;

    let score = 0.85 * similarity(s1, s2) + 0.15 * bestWindow(short, long);

    // Typing starts at the start of a word, so the first character is evidence.
    score += 0.02 * sharedPrefix(s1, s2);
    if (s1[0] !== s2[0]) score -= 0.05;

    if (long.indexOf(short) !== -1) score += 0.06;

    // A big length gap means most of the match came from padding.
    const gap = long.length - short.length;
    if (gap >= 3) score -= 0.05 * gap / long.length;

    return clamp01(score);
}

/// For long text. Weighted to the window match: the query is a fragment, so
/// whole-string similarity would only measure the length difference.
function computeTextMatchScore(s1, s2) {
    if (s1 === s2) return 1;
    if (s1.length === 0 || s2.length === 0) return 0;

    const short = s1.length <= s2.length ? s1 : s2;
    const long = s1.length <= s2.length ? s2 : s1;

    let score = 0.4 * similarity(s1, s2) + 0.6 * bestWindow(short, long);

    score += 0.01 * sharedPrefix(s1, s2);
    if (long.indexOf(short) !== -1) score += 0.2;

    const gap = long.length - short.length;
    if (gap >= 10) score -= 0.02 * gap / long.length;

    return clamp01(score);
}
