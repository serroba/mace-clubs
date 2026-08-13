import Toybox.Application.Storage;
import Toybox.Lang;

// Persisted, browsable per-session smoothness history. Deliberately separate
// from Smoothness' per-(equipment, movement, side) trend list: that one exists
// only to compute a like-for-like delta, whereas this is a single chronological
// log across all equipment, each record self-describing so the history view can
// label it without any extra lookups.
//
// The Storage read/write lives in the view layer (HistoryMenu) and the save
// path (WorkoutSession); everything here stays pure so the retention policy is
// unit-testable without Application.Storage, mirroring Smoothness.appendSummary.
// Records use the same Array<Storage.ValueType> shape the rest of the app
// persists, so values round-trip through Storage unchanged.
module SmoothnessLog {
    const STORAGE_KEY = "smoothLog";

    // Watch storage is small; both caps are generous for the data size (a
    // capped log is ~20 * ~30 numbers) and keep a runaway history bounded.
    const MAX_SESSIONS = 20;
    const MAX_SETS = 24;

    // Flat record layout, matching the array style of Smoothness.appendSummary:
    //   [ epoch, eqType, eqCount, weightG, moveType, side, sessionScore, nSets,
    //     s0, s1, ... ]
    const IDX_EPOCH = 0;
    const IDX_EQ_TYPE = 1;
    const IDX_EQ_COUNT = 2;
    const IDX_WEIGHT = 3;
    const IDX_MOVE = 4;
    const IDX_SIDE = 5;
    const IDX_SCORE = 6;
    const IDX_NSETS = 7;
    const IDX_SETS = 8;

    function record(
        epoch as Number,
        eqType as Number,
        eqCount as Number,
        weightG as Number,
        moveType as Number,
        side as Number,
        sessionScore as Number,
        setScores as Array<Number>
    ) as Array<Storage.ValueType> {
        var n = setScores.size();
        if (n > MAX_SETS) {
            n = MAX_SETS;
        }
        var rec = [epoch, eqType, eqCount, weightG, moveType, side, sessionScore, n] as Array<Storage.ValueType>;
        for (var i = 0; i < n; i++) {
            rec.add(setScores[i]);
        }
        return rec;
    }

    // Pure: append newest at the end, dropping the oldest beyond MAX_SESSIONS.
    function append(log as Array<Storage.ValueType>, rec as Array<Storage.ValueType>) as Array<Storage.ValueType> {
        var result = [] as Array<Storage.ValueType>;
        var start = log.size() >= MAX_SESSIONS ? log.size() - MAX_SESSIONS + 1 : 0;
        for (var i = start; i < log.size(); i++) {
            result.add(log[i]);
        }
        result.add(rec);
        return result;
    }

    function epochOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_EPOCH);
    }

    function eqTypeOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_EQ_TYPE);
    }

    function eqCountOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_EQ_COUNT);
    }

    function weightOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_WEIGHT);
    }

    function moveOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_MOVE);
    }

    function sideOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_SIDE);
    }

    function scoreOf(rec as Array<Storage.ValueType>) as Number {
        return field(rec, IDX_SCORE);
    }

    // Trust the shorter of the declared count and what is actually stored, so a
    // truncated or corrupt record read back from Storage can never over-read.
    function setCountOf(rec as Array<Storage.ValueType>) as Number {
        var declared = field(rec, IDX_NSETS);
        var available = rec.size() - IDX_SETS;
        if (available < 0) {
            available = 0;
        }
        return declared < available ? declared : available;
    }

    function setScoreOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        if (index < 0 || index >= setCountOf(rec)) {
            return -1;
        }
        return field(rec, IDX_SETS + index);
    }

    function field(rec as Array<Storage.ValueType>, index as Number) as Number {
        if (index < 0 || index >= rec.size()) {
            return 0;
        }
        var value = rec[index];
        return value instanceof Number ? value : 0;
    }
}
