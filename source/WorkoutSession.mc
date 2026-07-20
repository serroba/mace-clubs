import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;

// Wraps the FIT recording session and custom developer fields.
class WorkoutSession {
    const FIELD_ID_SETS = 0;
    const FIELD_ID_BATTERY = 1;
    const FIELD_ID_ACCEL_RMS = 2;
    const FIELD_ID_ACCEL_PEAK = 3;
    const FIELD_ID_ACCEL_ZC = 4;

    private var _session as ActivityRecording.Session?;
    private var _setsField as FitContributor.Field?;
    private var _batteryField as FitContributor.Field?;
    private var _rmsField as FitContributor.Field?;
    private var _peakField as FitContributor.Field?;
    private var _zcField as FitContributor.Field?;
    private var _sets as Number = 0;
    private var _started as Boolean = false;
    private var _startBattery as Float?;
    private var _capturing as Boolean = false;
    private var _smoothnessEnabled as Boolean = false;
    private var _smoothness as Smoothness.Tracker;
    private var _setSmoothness as SmoothnessSetSummaries;
    private var _smoothnessHistory as Array<Number> = [];

    function initialize() {
        _smoothness = new Smoothness.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
        loadSmoothnessHistory();
    }

    function isStarted() as Boolean {
        return _started;
    }

    function isRecording() as Boolean {
        var session = _session;
        return session != null && session.isRecording();
    }

    function getSets() as Number {
        return _sets;
    }

    function start() as Void {
        if (_session == null) {
            var session = ActivityRecording.createSession(
                {
                    :name     => "Mace & Clubs",
                    :sport    => Activity.SPORT_TRAINING,
                    :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
                }
            );
            _setsField = session.createField(
                "total_sets",
                FIELD_ID_SETS,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "sets"}
            );
            _batteryField = session.createField(
                "battery_used",
                FIELD_ID_BATTERY,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"}
            );
            _startBattery = System.getSystemStats().battery;
            _session = session;
            startMotionCapture(session);
            beginSmoothnessSet();
        }
        (_session as ActivityRecording.Session).start();
        _started = true;
    }

    // Phase-1 motion research (opt-in via the motionCapture setting):
    // stream the accelerometer at 25Hz and log per-second features to
    // the FIT record stream for offline swing analysis. Accel only -
    // gyro support on the Instinct is unverified.
    private function startMotionCapture(session as ActivityRecording.Session) as Void {
        var exportEnabled = false;
        try {
            var mc = Application.Properties.getValue("motionCapture");
            if (mc instanceof Boolean) {
                exportEnabled = mc;
            }
            var smooth = Application.Properties.getValue("smoothnessEnabled");
            if (smooth instanceof Boolean) {
                _smoothnessEnabled = smooth;
            }
        } catch (e) {}
        if (!exportEnabled && !_smoothnessEnabled || !(Sensor has :registerSensorDataListener)) {
            return;
        }
        // Local smoothness does not create FIT fields. The separate research
        // setting remains the explicit opt-in path for exporting summaries.
        if (exportEnabled) {
            _rmsField = session.createField(
                "accel_rms",
                FIELD_ID_ACCEL_RMS,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"}
            );
            _peakField = session.createField(
                "accel_peak",
                FIELD_ID_ACCEL_PEAK,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"}
            );
            _zcField = session.createField(
                "accel_zc",
                FIELD_ID_ACCEL_ZC,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "crossings"}
            );
        }
        try {
            Sensor.registerSensorDataListener(
                method(:onSensorData),
                {:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25}}
            );
            _capturing = true;
        } catch (e) {
            // no high-rate accel on this device; features stay unwritten
        }
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        var session = _session;
        if (session == null || !session.isRecording()) {
            return;
        }
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        var f = Motion.features(accel.x as Array<Number>, accel.y as Array<Number>, accel.z as Array<Number>);
        if (_smoothnessEnabled && _setSmoothness.isOpen()) {
            _smoothness.add(f);
        }
        var rms = _rmsField;
        var peak = _peakField;
        var zc = _zcField;
        if (rms != null) {
            rms.setData(f[:rms] as Number);
        }
        if (peak != null) {
            peak.setData(f[:peak] as Number);
        }
        if (zc != null) {
            var crossings = f[:zc] as Number;
            zc.setData(crossings > 255 ? 255 : crossings);
        }
    }

    private function stopMotionCapture() as Void {
        if (_capturing && Sensor has :unregisterSensorDataListener) {
            Sensor.unregisterSensorDataListener();
            _capturing = false;
        }
    }

    function pause() as Void {
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
    }

    function resume() as Void {
        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }
    }

    // Each SELECT press during a workout marks a completed set.
    function addSet() as Void {
        if (_smoothnessEnabled) {
            if (_setSmoothness.isOpen()) {
                _setSmoothness.complete(_smoothness.getScoreTotal(), _smoothness.getScoredWindows());
            } else {
                // A delayed plan refresh can discover multiple completed sets
                // together. Preserve their numbering without inventing scores.
                _setSmoothness.completeMissing();
            }
        }
        _sets++;
        var field = _setsField;
        if (field != null) {
            field.setData(_sets);
        }
        if (Attention has :vibrate) {
            Attention.vibrate(
                [
                    new Attention.VibeProfile(100, 80),
                    new Attention.VibeProfile(0, 80),
                    new Attention.VibeProfile(100, 80)
                ]
            );
        }
    }

    function beginSmoothnessSet() as Void {
        if (_smoothnessEnabled) {
            _setSmoothness.begin(_smoothness.getScoreTotal(), _smoothness.getScoredWindows());
        }
    }

    function saveAndExit() as Void {
        stopMotionCapture();
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            recordBatteryUsed();
            saveSmoothnessSummary();
            session.save();
            _session = null;
        }
        System.exit();
    }

    function getSmoothnessScore() as Number {
        return _smoothness.getScore();
    }

    function getSmoothnessWindows() as Number {
        return _smoothness.getScoredWindows();
    }

    function getSetSmoothnessCount() as Number {
        return _setSmoothness.count();
    }

    function getSetSmoothnessScore(index as Number) as Number {
        return _setSmoothness.score(index);
    }

    function getSetSmoothnessWindows(index as Number) as Number {
        return _setSmoothness.windows(index);
    }

    function getLastSmoothnessScore() as Number {
        if (_smoothnessHistory.size() == 0) {
            return -1;
        }
        return _smoothnessHistory[_smoothnessHistory.size() - 2];
    }

    function getSmoothnessDelta() as Number {
        var current = getSmoothnessScore();
        if (current >= 0 && _smoothnessHistory.size() > 0) {
            return current - getLastSmoothnessScore();
        }
        if (_smoothnessHistory.size() >= 4) {
            var lastScore = _smoothnessHistory.size() - 2;
            return _smoothnessHistory[lastScore] - _smoothnessHistory[lastScore - 2];
        }
        return 0;
    }

    function hasSmoothnessDelta() as Boolean {
        if (getSmoothnessScore() >= 0) {
            return _smoothnessHistory.size() > 0;
        }
        return _smoothnessHistory.size() >= 4;
    }

    private function loadSmoothnessHistory() as Void {
        try {
            var stored = Storage.getValue("smoothnessHistoryV1");
            if (!(stored instanceof Array)) {
                return;
            }
            var entries = stored as Array<Storage.ValueType>;
            for (var i = 0; i + 1 < entries.size(); i += 2) {
                if (entries[i] instanceof Number && entries[i + 1] instanceof Number) {
                    _smoothnessHistory.add(entries[i] as Number);
                    _smoothnessHistory.add(entries[i + 1] as Number);
                }
            }
        } catch (e) {
            _smoothnessHistory = [];
        }
    }

    private function saveSmoothnessSummary() as Void {
        var score = getSmoothnessScore();
        var windows = getSmoothnessWindows();
        if (!_smoothnessEnabled || score < 0 || windows == 0) {
            return;
        }
        _smoothnessHistory = Smoothness.appendSummary(_smoothnessHistory, score, windows);
        try {
            var stored = [] as Array<Storage.ValueType>;
            for (var i = 0; i < _smoothnessHistory.size(); i++) {
                stored.add(_smoothnessHistory[i]);
            }
            Storage.setValue("smoothnessHistoryV1", stored);
        } catch (e) {}
    }

    // Session-level battery cost: start minus end, floored at zero
    // (solar charge or a charger mid-session would otherwise go negative).
    private function recordBatteryUsed() as Void {
        var field = _batteryField;
        var start = _startBattery;
        if (field == null || start == null) {
            return;
        }
        field.setData(batteryDelta(start, System.getSystemStats().battery));
    }

    function batteryDelta(startPct as Float, endPct as Float) as Float {
        var used = startPct - endPct;
        return used < 0.0 ? 0.0 : used;
    }

    // Discard the current FIT session and return this wrapper to its idle
    // state. Unlike saveAndExit(), this deliberately keeps the app open.
    function discard() as Void {
        stopMotionCapture();
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            session.discard();
            _session = null;
        }
        _setsField = null;
        _batteryField = null;
        _rmsField = null;
        _peakField = null;
        _zcField = null;
        _sets = 0;
        _started = false;
        _startBattery = null;
        _smoothnessEnabled = false;
        _smoothness = new Smoothness.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
    }
}
