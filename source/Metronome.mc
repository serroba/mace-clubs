import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Beat timer that re-anchors against System.getTimer() every beat,
// so the tempo does not drift over a long session.
class Metronome {
    const MIN_BPM = 5;
    const MAX_BPM = 240;
    const BPM_STEP = 5;
    const DEFAULT_BPM = 50;
    const MIN_VIBE = 10;
    const MAX_VIBE = 100;
    // Cue frequency modes (persisted as the cueMode setting).
    const CUE_LOOP_STARTS = 0; // one cue per loop (loop A and loop B both)
    const CUE_EVERY_BEAT = 1;  // classic full metronome
    const CUE_CYCLE_TOP = 2;   // one cue per full pattern cycle (top of loop A)

    private var _timer as Timer.Timer;
    private var _bpm as Number = DEFAULT_BPM;
    private var _intervalMs as Float = 1200.0;
    private var _nextBeat as Float = 0.0;
    private var _running as Boolean = false;
    // Beat feedback channels, independently toggleable from the phone.
    // Default is vibration-only: both at once is heavy on the wrist.
    private var _toneEnabled as Boolean = false;
    private var _vibeEnabled as Boolean = true;
    private var _vibeStrength as Number = 50;
    private var _softTone as Boolean = true;
    private var _beatCount as Number = 0;
    // Round pattern: loop lengths in beats, cycled in order. [4] is a
    // uniform 4-beat loop; [4, 2] alternates a 4-move loop with a 2-move
    // loop (the classic club "4-2").
    private var _pattern as Array<Number> = [4] as Array<Number>;
    private var _cycleBeats as Number = 4;
    private var _accentEnabled as Boolean = true;
    private var _cueMode as Number = CUE_LOOP_STARTS;

    function initialize() {
        _timer = new Timer.Timer();
        setBpm(DEFAULT_BPM);
        loadSettings();
    }

    // Reads app settings (configurable from Garmin Connect on the phone).
    // Keeps defaults if a key is missing, e.g. right after an app update.
    function loadSettings() as Void {
        try {
            var bpm = Application.Properties.getValue("defaultBpm");
            if (bpm instanceof Number) {
                setBpm(bpm);
            }
            var tone = Application.Properties.getValue("toneEnabled");
            if (tone instanceof Boolean) {
                _toneEnabled = tone;
            }
            var vibe = Application.Properties.getValue("vibeEnabled");
            if (vibe instanceof Boolean) {
                _vibeEnabled = vibe;
            }
            var strength = Application.Properties.getValue("beatVibeStrength");
            if (strength instanceof Number) {
                setVibeStrength(strength);
            }
            var soft = Application.Properties.getValue("softBeep");
            if (soft instanceof Boolean) {
                _softTone = soft;
            }
            var a = 4;
            var b = 0;
            var bpr = Application.Properties.getValue("beatsPerRound");
            if (bpr instanceof Number) {
                a = clampNum(bpr, 1, 16);
            }
            var bpr2 = Application.Properties.getValue("beatsPerRound2");
            if (bpr2 instanceof Number) {
                b = clampNum(bpr2, 0, 16);
            }
            applyPattern(a, b);
            var accent = Application.Properties.getValue("accentEnabled");
            if (accent instanceof Boolean) {
                _accentEnabled = accent;
            }
            var cm = Application.Properties.getValue("cueMode");
            if (cm instanceof Number) {
                setCueMode(cm);
            }
        } catch (e) {}
    }

    // Rounds derive exactly from the beat count: the metronome defines
    // the movement cadence, so beats / beatsPerRound is the number of
    // completed movement loops. Reset at each work interval / set mark.
    // Set the loop pattern from a loop-A / loop-B pair: loopB == 0 is a
    // single uniform loop, loopB > 0 alternates the two (the club 4-2).
    // Each workout preset applies its own pattern through here on start.
    function applyPattern(loopA as Number, loopB as Number) as Void {
        setPattern(loopB > 0 ? ([loopA, loopB] as Array<Number>) : ([loopA] as Array<Number>));
    }

    function setPattern(pattern as Array<Number>) as Void {
        if (pattern.size() == 0) {
            pattern = [4] as Array<Number>;
        }
        var total = 0;
        for (var i = 0; i < pattern.size(); i++) {
            total += pattern[i];
        }
        _pattern = pattern;
        _cycleBeats = total;
    }

    function getRounds() as Number {
        var cycles = _beatCount / _cycleBeats;
        var rem = _beatCount % _cycleBeats;
        var rounds = cycles * _pattern.size();
        var acc = 0;
        for (var i = 0; i < _pattern.size(); i++) {
            acc += _pattern[i];
            if (rem >= acc) {
                rounds++;
            } else {
                break;
            }
        }
        return rounds;
    }

    function resetBeatCount() as Void {
        _beatCount = 0;
    }

    // The downbeat: the first beat of each movement round. Meaningless
    // when every beat starts a round.
    function isRoundStart(beatNumber as Number) as Boolean {
        if (_cycleBeats == _pattern.size()) {
            // every beat is its own round; accenting all of them is noise
            return false;
        }
        var rem = (beatNumber - 1) % _cycleBeats;
        var acc = 0;
        for (var i = 0; i < _pattern.size(); i++) {
            if (rem == acc) {
                return true;
            }
            acc += _pattern[i];
        }
        return false;
    }

    // The top of a full pattern cycle: the first beat of loop A. For a
    // single-loop pattern this coincides with every round start.
    function isCycleStart(beatNumber as Number) as Boolean {
        return (beatNumber - 1) % _cycleBeats == 0;
    }

    function setCueMode(mode as Number) as Void {
        _cueMode = clampNum(mode, CUE_LOOP_STARTS, CUE_CYCLE_TOP);
    }

    // Loop-start cues (the default) pulse on every loop boundary; cycle-top
    // cues fire once per full pattern (halving cues on a 4-2 by skipping the
    // loop B switch); every-beat is the classic full metronome. All modes
    // degenerate to every beat when a round is a single beat, since there is
    // nothing coarser to mark.
    function shouldCue(beatNumber as Number) as Boolean {
        if (_cueMode == CUE_EVERY_BEAT || _cycleBeats == _pattern.size()) {
            return true;
        }
        if (_cueMode == CUE_CYCLE_TOP) {
            return isCycleStart(beatNumber);
        }
        return isRoundStart(beatNumber);
    }

    private function clampNum(v as Number, lo as Number, hi as Number) as Number {
        if (v < lo) {
            return lo;
        }
        if (v > hi) {
            return hi;
        }
        return v;
    }

    // Feedback channels; also consulted by the interval transition cue so
    // a silenced channel stays silent at set boundaries, not just on beats.
    function isToneEnabled() as Boolean {
        return _toneEnabled;
    }

    function isVibeEnabled() as Boolean {
        return _vibeEnabled;
    }

    function getVibeStrength() as Number {
        return _vibeStrength;
    }

    // Vibration duty cycle for the beat pulse. Floor of MIN_VIBE keeps a
    // configured beat from becoming imperceptible; use the vibration
    // toggle to silence it entirely.
    function setVibeStrength(strength as Number) as Void {
        if (strength < MIN_VIBE) {
            strength = MIN_VIBE;
        } else if (strength > MAX_VIBE) {
            strength = MAX_VIBE;
        }
        _vibeStrength = strength;
    }

    function getBpm() as Number {
        return _bpm;
    }

    function setBpm(bpm as Number) as Void {
        if (bpm < MIN_BPM) {
            bpm = MIN_BPM;
        } else if (bpm > MAX_BPM) {
            bpm = MAX_BPM;
        }
        _bpm = bpm;
        _intervalMs = 60000.0 / _bpm;
    }

    function adjustBpm(steps as Number) as Void {
        setBpm(_bpm + steps * BPM_STEP);
    }

    function isRunning() as Boolean {
        return _running;
    }

    function start() as Void {
        if (_running) {
            return;
        }
        _running = true;
        _nextBeat = System.getTimer().toFloat();
        onBeat();
    }

    function stop() as Void {
        _running = false;
        _timer.stop();
    }

    function onBeat() as Void {
        if (!_running) {
            return;
        }
        _beatCount++;
        if (shouldCue(_beatCount)) {
            playCue(_accentEnabled && isRoundStart(_beatCount));
        }
        _nextBeat += _intervalMs;
        var delay = (_nextBeat - System.getTimer()).toNumber();
        if (delay < 50) {
            delay = 50;
        }
        _timer.start(method(:onBeat), delay, false);
    }

    // The accent (downbeat) marks the first beat of each round with a
    // stronger, longer pulse and a step up in tone, so a side switch is
    // felt without reading the screen.
    private function playCue(accent as Boolean) as Void {
        if (_toneEnabled && Attention has :playTone) {
            // tone volume is not controllable from CIQ (it follows the
            // system sound setting); TONE_KEY is the softest cue available
            if (accent) {
                Attention.playTone(_softTone ? Attention.TONE_LOUD_BEEP : Attention.TONE_ALERT_HI);
            } else {
                Attention.playTone(_softTone ? Attention.TONE_KEY : Attention.TONE_LOUD_BEEP);
            }
        }
        if (_vibeEnabled && Attention has :vibrate) {
            var strength = accent ? clampNum(_vibeStrength + 40, MIN_VIBE, MAX_VIBE) : _vibeStrength;
            Attention.vibrate([new Attention.VibeProfile(strength, accent ? 250 : 100)]);
        }
    }
}
