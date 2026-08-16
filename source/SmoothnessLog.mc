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
    const DETAIL_MAGIC = 20260816;
    const DETAIL_HEADER = 4;
    const DETAIL_STRIDE = 8;
    const DETAIL_WORK = 0;
    const DETAIL_REST = 1;
    const DETAIL_MOVE = 2;
    const DETAIL_SIDE = 3;
    const DETAIL_SWINGS = 4;
    const DETAIL_EXPOSURE = 5;
    const DETAIL_PEAK = 6;
    const DETAIL_ACTIVE = 7;

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

    // New records append a versioned detail section after the legacy score
    // array. Old records remain readable because their original indexes and
    // declared score count never move.
    function detailedRecord(
        epoch as Number,
        eqType as Number,
        eqCount as Number,
        weightG as Number,
        moveType as Number,
        side as Number,
        sessionScore as Number,
        setScores as Array<Number>,
        totalWork as Number,
        totalRest as Number,
        blocks as Array<WorkBlockSummary>
    ) as Array<Storage.ValueType> {
        var rec = record(epoch, eqType, eqCount, weightG, moveType, side, sessionScore, setScores);
        var n = blocks.size();
        if (n > MAX_SETS) {
            n = MAX_SETS;
        }
        rec.add(DETAIL_MAGIC);
        rec.add(totalWork);
        rec.add(totalRest);
        rec.add(n);
        for (var i = 0; i < n; i++) {
            var block = blocks[i];
            rec.add(block.getWorkSeconds());
            rec.add(block.getRestSeconds());
            rec.add(block.getMovementType());
            rec.add(block.getWorkingSide());
            rec.add(block.getSwings());
            rec.add(block.getMotionExposure());
            rec.add(block.getMotionPeak());
            rec.add(block.getActiveSeconds());
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

    function hasDetails(rec as Array<Storage.ValueType>) as Boolean {
        var start = detailStart(rec);
        return rec.size() >= start + DETAIL_HEADER && field(rec, start) == DETAIL_MAGIC;
    }

    function totalWorkOf(rec as Array<Storage.ValueType>) as Number {
        return hasDetails(rec) ? field(rec, detailStart(rec) + 1) : 0;
    }

    function totalRestOf(rec as Array<Storage.ValueType>) as Number {
        return hasDetails(rec) ? field(rec, detailStart(rec) + 2) : 0;
    }

    function blockCountOf(rec as Array<Storage.ValueType>) as Number {
        if (!hasDetails(rec)) {
            return 0;
        }
        var start = detailStart(rec);
        var declared = field(rec, start + 3);
        var available = (rec.size() - start - DETAIL_HEADER) / DETAIL_STRIDE;
        return declared < available ? declared : available;
    }

    function blockWorkOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_WORK, 0);
    }

    function blockRestOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_REST, 0);
    }

    function blockMoveOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_MOVE, moveOf(rec));
    }

    function blockSideOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_SIDE, sideOf(rec));
    }

    function blockSwingsOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_SWINGS, -1);
    }

    function blockExposureOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_EXPOSURE, -1);
    }

    function blockPeakOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_PEAK, -1);
    }

    function blockActiveOf(rec as Array<Storage.ValueType>, index as Number) as Number {
        return blockField(rec, index, DETAIL_ACTIVE, -1);
    }

    function detailStart(rec as Array<Storage.ValueType>) as Number {
        return IDX_SETS + setCountOf(rec);
    }

    function blockField(rec as Array<Storage.ValueType>, index as Number, offset as Number, fallback as Number) as Number {
        if (index < 0 || index >= blockCountOf(rec)) {
            return fallback;
        }
        return field(rec, detailStart(rec) + DETAIL_HEADER + index * DETAIL_STRIDE + offset);
    }

    function field(rec as Array<Storage.ValueType>, index as Number) as Number {
        if (index < 0 || index >= rec.size()) {
            return 0;
        }
        var value = rec[index];
        return value instanceof Number ? value : 0;
    }
}
