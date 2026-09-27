// Fuzzy match scoring for the launcher, the clipboard history and the emoji
// picker. Every function returns 0..1, higher is a better match, so callers can
// keep one threshold and sort descending.
//
// Two scores rather than one, because the two jobs pull in opposite directions:
// an app name is about as long as what you typed, so the whole string matters;
// a clipboard entry is a paragraph, so only the best-matching window of it does.

/// Wagner-Fischer, two rows instead of a full matrix: the haystack can be a
/// whole clipboard entry, and an n*m matrix of those is worth avoiding.
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

/// The best the needle scores against any window of the haystack its own
/// length. This is what lets "fox" find "the quick brown fox" at all: whole
/// string similarity of those two is near zero.
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

/// For short labels — an app name against what was typed. Weighted toward the
/// whole string, because with two short strings a window match is nearly free
/// and would rank every three-letter app equally.
function computeScore(s1, s2) {
    if (s1 === s2) return 1;
    if (s1.length === 0 || s2.length === 0) return 0;

    const short = s1.length <= s2.length ? s1 : s2;
    const long = s1.length <= s2.length ? s2 : s1;

    let score = 0.85 * similarity(s1, s2) + 0.15 * bestWindow(short, long);

    // Typing usually starts at the start of a word, so agreeing there is
    // evidence and disagreeing there is evidence against.
    score += 0.02 * sharedPrefix(s1, s2);
    if (s1[0] !== s2[0]) score -= 0.05;

    if (long.indexOf(short) !== -1) score += 0.06;

    // A big length gap means most of the match came from padding.
    const gap = long.length - short.length;
    if (gap >= 3) score -= 0.05 * gap / long.length;

    return clamp01(score);
}

/// For long text — a clipboard entry or an emoji description. Weighted toward
/// the window match, since the query is a fragment of something much longer and
/// whole-string similarity would just measure the length difference.
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
