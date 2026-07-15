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

    private var _timer as Timer.Timer;
    private var _bpm as Number = DEFAULT_BPM;
    private var _intervalMs as Float = 1200.0;
    private var _nextBeat as Float = 0.0;
    private var _running as Boolean = false;
    private var _toneEnabled as Boolean = true;
    private var _vibeEnabled as Boolean = true;

    function initialize() {
        _timer = new Timer.Timer();
        setBpm(DEFAULT_BPM);
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
        if (_toneEnabled && (Attention has :playTone)) {
            Attention.playTone(Attention.TONE_LOUD_BEEP);
        }
        if (_vibeEnabled && (Attention has :vibrate)) {
            Attention.vibrate([new Attention.VibeProfile(80, 100)]);
        }
    }
}
