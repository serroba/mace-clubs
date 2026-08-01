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
    const FIELD_ID_EQUIPMENT_TYPE = 5;
    const FIELD_ID_EQUIPMENT_COUNT = 6;
    const FIELD_ID_EQUIPMENT_WEIGHT = 7;
    const FIELD_ID_SET_NUMBER = 8;
    const FIELD_ID_WATCH_WRIST = 9;
    const FIELD_ID_PHASE = 10;
    const FIELD_ID_PHASE_DURATION = 11;
    const FIELD_ID_LAP_WEIGHT = 12;
    const FIELD_ID_LAP_WRIST = 13;
    const FIELD_ID_SET_SMOOTHNESS = 14;
    const FIELD_ID_MOVEMENT_TYPE = 15;
    const FIELD_ID_WORKING_SIDE = 16;

    private var _session as ActivityRecording.Session?;
    private var _setsField as FitContributor.Field?;
    private var _setNumberField as FitContributor.Field?;
    private var _phaseField as FitContributor.Field?;
    private var _phaseDurationField as FitContributor.Field?;
    private var _lapWeightField as FitContributor.Field?;
    private var _lapWristField as FitContributor.Field?;
    private var _setSmoothnessField as FitContributor.Field?;
    private var _movementTypeField as FitContributor.Field?;
    private var _workingSideField as FitContributor.Field?;
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
    private var _smoothnessHistoryKey as String = "";
    private var _equipmentType as Number = Equipment.TYPE_MACE;
    private var _equipmentCount as Number = 1;
    private var _equipmentWeightGrams as Number = 4000;
    private var _watchWrist as Number = 0;
    private var _movementType as Number = Movement.TYPE_360;
    private var _workingSide as Number = Movement.SIDE_TWO_HANDED;
    private var _blocks as Array<WorkBlockSummary> = [];

    function initialize() {
        _smoothness = new Smoothness.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
        reloadEquipment();
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

    function getSetWorkSeconds(index as Number) as Number {
        var block = getBlock(index);
        return block == null ? 0 : (block as WorkBlockSummary).getWorkSeconds();
    }

    function getSetRestSeconds(index as Number) as Number {
        var block = getBlock(index);
        return block == null ? 0 : (block as WorkBlockSummary).getRestSeconds();
    }

    function getTotalWorkSeconds() as Number {
        var total = 0;
        for (var i = 0; i < _blocks.size(); i++) {
            total += _blocks[i].getWorkSeconds();
        }
        return total;
    }

    function getTotalRestSeconds() as Number {
        var total = 0;
        for (var i = 0; i < _blocks.size(); i++) {
            total += _blocks[i].getRestSeconds();
        }
        return total;
    }

    function getBlock(index as Number) as WorkBlockSummary? {
        if (index < 0 || index >= _blocks.size()) {
            return null;
        }
        return _blocks[index];
    }

    function selectEquipment(kind as Number, quantity as Number) as Void {
        if (_started) {
            return;
        }
        _equipmentType = kind;
        _equipmentCount = kind == Equipment.TYPE_MACE ? 1 : quantity;
        _equipmentWeightGrams = Equipment.defaultWeightGrams(kind);
        _movementType = Movement.resolveFor(_movementType, kind);
        loadComparableHistory();
    }

    // Valid before and during a session: pre-start it re-keys the smoothness
    // trend, mid-session it only redirects what upcoming work blocks record
    // (the session-level trend keeps comparing against the starting movement).
    function selectMovement(movementType as Number) as Void {
        _movementType = Movement.resolveFor(movementType, _equipmentType);
        if (!_started) {
            loadComparableHistory();
        }
    }

    function getMovementType() as Number {
        return _movementType;
    }

    function selectWorkingSide(side as Number) as Void {
        _workingSide = side >= 0 && side < Movement.SIDE_COUNT ? side : Movement.SIDE_TWO_HANDED;
        if (!_started) {
            loadComparableHistory();
        }
    }

    function getWorkingSide() as Number {
        return _workingSide;
    }

    // Completed single-side work sets per hand: [left, right]. Alternating
    // and two-handed blocks are balanced by construction and stay out.
    function getSideSetCounts() as Array<Number> {
        var left = 0;
        var right = 0;
        for (var i = 0; i < _blocks.size(); i++) {
            var side = _blocks[i].getWorkingSide();
            if (side == Movement.SIDE_LEFT) {
                left++;
            } else if (side == Movement.SIDE_RIGHT) {
                right++;
            }
        }
        return [left, right] as Array<Number>;
    }

    function getEquipmentLabel() as String {
        return Equipment.labelFor(_equipmentType, _equipmentCount, _equipmentWeightGrams);
    }

    function getEquipmentType() as Number {
        return _equipmentType;
    }

    function getEquipmentCount() as Number {
        return _equipmentCount;
    }

    function getEquipmentWeightGrams() as Number {
        return _equipmentWeightGrams;
    }

    function start() as Void {
        if (_session == null) {
            var session = ActivityRecording.createSession(
                {
                    :name     => getEquipmentLabel(),
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
            _setNumberField = session.createField(
                "set_number",
                FIELD_ID_SET_NUMBER,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "set"}
            );
            _phaseField = session.createField(
                "phase",
                FIELD_ID_PHASE,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "0=rest 1=work"}
            );
            _phaseDurationField = session.createField(
                "phase_duration",
                FIELD_ID_PHASE_DURATION,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"}
            );
            _lapWeightField = session.createField(
                "implement_weight",
                FIELD_ID_LAP_WEIGHT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "g"}
            );
            _lapWristField = session.createField(
                "watch_wrist",
                FIELD_ID_LAP_WRIST,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "0=left 1=right"}
            );
            _setSmoothnessField = session.createField(
                "set_smoothness",
                FIELD_ID_SET_SMOOTHNESS,
                FitContributor.DATA_TYPE_SINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "score"}
            );
            _movementTypeField = session.createField(
                "movement_type",
                FIELD_ID_MOVEMENT_TYPE,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "movement"}
            );
            _workingSideField = session.createField(
                "working_side",
                FIELD_ID_WORKING_SIDE,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "side"}
            );
            _batteryField = session.createField(
                "battery_used",
                FIELD_ID_BATTERY,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"}
            );
            var equipmentType = session.createField(
                "implement_type",
                FIELD_ID_EQUIPMENT_TYPE,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "0=mace 1=clubs"}
            );
            var equipmentCount = session.createField(
                "implement_count",
                FIELD_ID_EQUIPMENT_COUNT,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "implements"}
            );
            var equipmentWeight = session.createField(
                "implement_weight",
                FIELD_ID_EQUIPMENT_WEIGHT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "g"}
            );
            var watchWrist = session.createField(
                "watch_wrist",
                FIELD_ID_WATCH_WRIST,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "0=left 1=right"}
            );
            equipmentType.setData(_equipmentType);
            equipmentCount.setData(_equipmentCount);
            equipmentWeight.setData(_equipmentWeightGrams);
            watchWrist.setData(_watchWrist);
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
        addSetWithDuration(0);
    }

    function addSetWithDuration(durationSeconds as Number) as Void {
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
        var smoothness = _sets <= getSetSmoothnessCount() ? getSetSmoothnessScore(_sets - 1) : -1;
        var block = new WorkBlockSummary(
            _sets,
            clampDuration(durationSeconds),
            _movementType,
            _workingSide,
            _equipmentType,
            _equipmentCount,
            _equipmentWeightGrams,
            _watchWrist,
            smoothness
        );
        _blocks.add(block);
        var field = _setsField;
        if (field != null) {
            field.setData(_sets);
        }
        // Connect IQ cannot emit Garmin's native strength-set messages. A lap
        // is the supported FIT boundary that preserves each completed set's
        // timestamp and duration for Garmin Connect and exported FIT analysis.
        var setNumberField = _setNumberField;
        var session = _session;
        if (setNumberField != null && session != null && session.isRecording()) {
            setNumberField.setData(_sets);
            writeLapMetadata(1, block);
            session.addLap();
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

    // Close the rest segment before a timed plan starts its next work set.
    // A zero set number distinguishes rest laps from completed work-set laps.
    function endRestLap() as Void {
        endRestLapWithDuration(0);
    }

    function endRestLapWithDuration(durationSeconds as Number) as Void {
        if (_sets == 0) {
            return;
        }
        _blocks[_sets - 1].setRestSeconds(clampDuration(durationSeconds));
        var setNumberField = _setNumberField;
        var session = _session;
        if (setNumberField != null && session != null && session.isRecording()) {
            setNumberField.setData(0);
            writeLapMetadata(0, _blocks[_sets - 1]);
            session.addLap();
        }
    }

    private function clampDuration(durationSeconds as Number) as Number {
        if (durationSeconds < 0) {
            return 0;
        }
        return durationSeconds > 65535 ? 65535 : durationSeconds;
    }

    // FIT is an adapter over the app's block model. It does not define it.
    private function writeLapMetadata(phase as Number, block as WorkBlockSummary) as Void {
        var phaseField = _phaseField;
        var durationField = _phaseDurationField;
        var weightField = _lapWeightField;
        var wristField = _lapWristField;
        var smoothnessField = _setSmoothnessField;
        var movementField = _movementTypeField;
        var workingSideField = _workingSideField;
        if (phaseField != null) {
            phaseField.setData(phase);
        }
        if (durationField != null) {
            durationField.setData(phase == 1 ? block.getWorkSeconds() : block.getRestSeconds());
        }
        if (weightField != null) {
            weightField.setData(block.getEquipmentWeightGrams());
        }
        if (wristField != null) {
            wristField.setData(block.getWatchWrist());
        }
        if (smoothnessField != null) {
            smoothnessField.setData(phase == 1 ? block.getSmoothness() : -1);
        }
        if (movementField != null) {
            movementField.setData(block.getMovementType());
        }
        if (workingSideField != null) {
            workingSideField.setData(block.getWorkingSide());
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

    function reloadEquipment() as Void {
        if (_started) {
            return;
        }
        _equipmentType = Equipment.type();
        _equipmentCount = Equipment.count();
        _equipmentWeightGrams = Equipment.defaultWeightGrams(_equipmentType);
        _movementType = Movement.typeFor(_equipmentType);
        _workingSide = Movement.workingSide();
        try {
            var wrist = Application.Properties.getValue("watchWrist");
            if (wrist instanceof Number) {
                _watchWrist = wrist == 1 ? 1 : 0;
            }
        } catch (e) {
            _watchWrist = 0;
        }
        loadComparableHistory();
    }

    private function loadComparableHistory() as Void {
        // Movement and working side affect the accelerometer signature, so
        // smoothness trends only compare like-for-like blocks.
        _smoothnessHistoryKey = Lang.format(
            "$1$_m$2$_s$3$",
            [
                Equipment.historyKeyFor(_equipmentType, _equipmentCount, _equipmentWeightGrams),
                _movementType,
                _workingSide
            ]
        );
        _smoothnessHistory = [];
        loadSmoothnessHistory();
    }

    private function loadSmoothnessHistory() as Void {
        try {
            var stored = Storage.getValue(_smoothnessHistoryKey);
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
            Storage.setValue(_smoothnessHistoryKey, stored);
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
        _setNumberField = null;
        _phaseField = null;
        _phaseDurationField = null;
        _lapWeightField = null;
        _lapWristField = null;
        _setSmoothnessField = null;
        _movementTypeField = null;
        _workingSideField = null;
        _batteryField = null;
        _rmsField = null;
        _peakField = null;
        _zcField = null;
        _sets = 0;
        _blocks = [];
        _started = false;
        _startBattery = null;
        _smoothnessEnabled = false;
        _smoothness = new Smoothness.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
    }
}
