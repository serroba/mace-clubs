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
        } catch (e) {}
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
        playCue();
        _nextBeat += _intervalMs;
        var delay = (_nextBeat - System.getTimer()).toNumber();
        if (delay < 50) {
            delay = 50;
        }
        _timer.start(method(:onBeat), delay, false);
    }

    private function playCue() as Void {
        if (_toneEnabled && Attention has :playTone) {
            // tone volume is not controllable from CIQ (it follows the
            // system sound setting); TONE_KEY is the softest cue available
            Attention.playTone(_softTone ? Attention.TONE_KEY : Attention.TONE_LOUD_BEEP);
        }
        if (_vibeEnabled && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(_vibeStrength, 100)]);
        }
    }
}
