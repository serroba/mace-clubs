import Toybox.Lang;

// The persistence policy for saved session scores.
//
// This module used to hold the scoring model too: a per-window comparison of
// wrist acceleration against an adaptive reference. That model measured
// something other than rhythm - it ran against effort, and could not fall
// with fatigue because its reference followed the athlete down - and it has
// been replaced by SwingSeries.steadiness, which measures the gaps between
// detected swings. docs/smoothness-physics.md has the evidence.
//
// The name survives in storage keys, FIT fields and settings, where changing
// it would break saved data for no gain.
module Smoothness {
    const HISTORY_LIMIT = 12;

    // Return a new bounded history so callers can test the persistence policy
    // without touching Application.Storage.
    function appendSummary(history as Array<Number>, score as Number, windows as Number) as Array<Number> {
        var result = [] as Array<Number>;
        var storedSessions = history.size() / 2;
        var start = storedSessions >= HISTORY_LIMIT ? 2 : 0;
        for (var i = start; i < history.size(); i++) {
            result.add(history[i]);
        }
        result.add(score);
        result.add(windows);
        return result;
    }
}
