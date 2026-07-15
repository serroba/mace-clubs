import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Beat timer that re-anchors against System.getTimer() every beat,
// so the tempo does not drift over a long session.
class Metronome {
    const MIN_BPM = 20;
    const MAX_BPM = 240;
    const BPM_STEP = 5;
    const DEFAULT_BPM = 50;
    const MIN_VIBE = 10;
    const MAX_VIBE = 100;

    private var _timer as Timer.Timer;
    private var _bpm as Number = DEFAULT_BPM;
    private var _intervalMs as Float = 1200.0;
    private var _nextBeat as Float = 0.0;
    private var _running as Boolean = false;
    private var _toneEnabled as Boolean = true;
    private var _vibeEnabled as Boolean = true;
    private var _vibeStrength as Number = 50;
    private var _softTone as Boolean = true;
    private var _beatCount as Number = 0;
    private var _beatsPerRound as Number = 4;
    private var _accentEnabled as Boolean = true;
    private var _cueEveryBeat as Boolean = false;

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
            var bpr = Application.Properties.getValue("beatsPerRound");
            if (bpr instanceof Number) {
                _beatsPerRound = clampNum(bpr, 1, 16);
            }
            var accent = Application.Properties.getValue("accentEnabled");
            if (accent instanceof Boolean) {
                _accentEnabled = accent;
            }
            var cm = Application.Properties.getValue("cueMode");
            if (cm instanceof Number) {
                setCueEveryBeat(cm == 1);
            }
        } catch (e) {}
    }

    // Rounds derive exactly from the beat count: the metronome defines
    // the movement cadence, so beats / beatsPerRound is the number of
    // completed movement loops. Reset at each work interval / set mark.
    function getRounds() as Number {
        return _beatCount / _beatsPerRound;
    }

    function resetBeatCount() as Void {
        _beatCount = 0;
    }

    // The downbeat: the first beat of each movement round. Meaningless
    // when every beat starts a round.
    function isRoundStart(beatNumber as Number) as Boolean {
        return _beatsPerRound > 1 && (beatNumber - 1) % _beatsPerRound == 0;
    }

    function setCueEveryBeat(everyBeat as Boolean) as Void {
        _cueEveryBeat = everyBeat;
    }

    // Round cues (the default) pulse only on loop boundaries, cutting
    // vibration power by the beats-per-round factor; every-beat mode is
    // the classic full metronome. Degenerates to every beat when a
    // round is a single beat.
    function shouldCue(beatNumber as Number) as Boolean {
        return _cueEveryBeat || _beatsPerRound == 1 || (beatNumber - 1) % _beatsPerRound == 0;
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
