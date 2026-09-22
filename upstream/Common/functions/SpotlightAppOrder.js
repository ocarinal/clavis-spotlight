.pragma library

function normalizedOrder(value) {
    return ["smart", "most-used", "recently-used", "name"].indexOf(value) >= 0 ? value : "name";
}

function normalizedAppIds(value, limit) {
    if (!Array.isArray(value)) return [];
    const maximum = typeof limit === "number" && limit > 0 ? Math.floor(limit) : 128;
    const result = [];
    const seen = new Set();
    for (const entry of value) {
        if (typeof entry !== "string") continue;
        const id = entry.trim();
        if (id === "" || id.length > 512 || /[\u0000-\u001f]/.test(id) || seen.has(id)) continue;
        seen.add(id);
        result.push(id);
        if (result.length >= maximum) break;
    }
    return result;
}

function safeNumber(value) {
    return typeof value === "number" && isFinite(value) && value >= 0
        ? Math.min(Number.MAX_SAFE_INTEGER, Math.floor(value)) : 0;
}

function record(value) {
    return {
        launchCount: safeNumber(value && value.launchCount),
        lastLaunchedAt: safeNumber(value && value.lastLaunchedAt)
    };
}

function normalizeHistory(value) {
    const result = Object.create(null);
    if (!value || typeof value !== "object" || Array.isArray(value)) return result;
    Object.keys(value).forEach(id => {
        if (id.trim() === "") return;
        const entry = record(value[id]);
        if (entry.launchCount > 0) result[id] = entry;
    });
    return result;
}

function decodeHistory(text) {
    try {
        const value = JSON.parse(text);
        if (!value || value.schemaVersion !== 1 || !value.applications
            || typeof value.applications !== "object" || Array.isArray(value.applications)) return null;
        return normalizeHistory(value.applications);
    } catch (error) {
        return null;
    }
}

function addLaunch(history, id, now) {
    const next = normalizeHistory(history);
    if (typeof id !== "string" || id.trim() === "") return next;
    const previous = record(next[id]);
    next[id] = {
        launchCount: Math.min(Number.MAX_SAFE_INTEGER, previous.launchCount + 1),
        lastLaunchedAt: Math.max(previous.lastLaunchedAt, safeNumber(now))
    };
    return next;
}

// Launches can arrive before the asynchronous initial read completes.
function mergePending(history, pending) {
    const next = normalizeHistory(history);
    Object.keys(pending).forEach(id => {
        const previous = record(next[id]);
        const extra = record(pending[id]);
        next[id] = {
            launchCount: Math.min(Number.MAX_SAFE_INTEGER, previous.launchCount + extra.launchCount),
            lastLaunchedAt: Math.max(previous.lastLaunchedAt, extra.lastLaunchedAt)
        };
    });
    return next;
}

function usageScore(order, value, now) {
    const entry = record(value);
    if (order === "most-used") return entry.launchCount;
    if (order === "recently-used") return entry.lastLaunchedAt;
    if (order !== "smart" || entry.launchCount === 0) return 0;
    const hours = Math.max(0, now - entry.lastLaunchedAt) / 3600000;
    const bonus = entry.lastLaunchedAt === 0 ? 0 : hours < 1 ? 8 : hours < 24 ? 6
        : hours < 168 ? 4 : hours < 720 ? 2 : 0;
    return Math.log2(entry.launchCount + 1) + bonus;
}

function sortedResults(results, order, history, now, pinnedIds, manualOrder) {
    const selectedOrder = normalizedOrder(order);
    const pinOrder = Object.create(null);
    normalizedAppIds(pinnedIds).forEach((id, index) => pinOrder[id] = index);
    const manualIndex = Object.create(null);
    normalizedAppIds(manualOrder, 512).forEach((id, index) => manualIndex[id] = index);
    function manualPosition(id) {
        return Object.prototype.hasOwnProperty.call(manualIndex, id) ? manualIndex[id] : -1;
    }
    return results.slice().sort((left, right) => {
        // Usage never overrides the existing keyword relevance score.
        if (left.score !== right.score) return right.score - left.score;
        const leftPinned = Object.prototype.hasOwnProperty.call(pinOrder, left.id);
        const rightPinned = Object.prototype.hasOwnProperty.call(pinOrder, right.id);
        if (leftPinned !== rightPinned) return leftPinned ? -1 : 1;
        if (leftPinned && pinOrder[left.id] !== pinOrder[right.id])
            return pinOrder[left.id] - pinOrder[right.id];
        // A hand-arranged position outranks the automatic orders; apps the
        // user never moved keep following the selected order.
        const leftManual = manualPosition(left.id);
        const rightManual = manualPosition(right.id);
        if (leftManual !== rightManual) {
            if (leftManual < 0) return 1;
            if (rightManual < 0) return -1;
            return leftManual - rightManual;
        }
        const usage = usageScore(selectedOrder, history[right.id], now)
                    - usageScore(selectedOrder, history[left.id], now);
        if (usage !== 0) return usage;
        const byName = left.title.localeCompare(right.title);
        return byName !== 0 ? byName : left.id.localeCompare(right.id);
    });
}
