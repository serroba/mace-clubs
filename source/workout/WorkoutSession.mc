import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;

// Wraps the FIT recording session; FitFields owns the developer fields.
class WorkoutSession {
    private var _session as ActivityRecording.Session?;
    private var _fit as FitFields;
    private var _sets as Number = 0;
    private var _started as Boolean = false;
    private var _startBattery as Float?;
    private var _capturing as Boolean = false;
    private var _smoothnessEnabled as Boolean = false;
    private var _loadExposureEnabled as Boolean = false;
    private var _swingDebugEnabled as Boolean = false;
    private var _smoothness as Smoothness.Tracker;
    private var _loadExposure as LoadExposure.Tracker;
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
    private var _swingCounter as SwingCounter.Counter;
    private var _swingSeries as SwingSeries.Tracker;
    private var _swingCounting as Boolean = false;
    private var _forceSwingCounting as Boolean = false;
    private var _workOpen as Boolean = false;
    private var _swingsAtBlockStart as Number = 0;

    function initialize() {
        _fit = new FitFields();
        _smoothness = new Smoothness.Tracker();
        _loadExposure = new LoadExposure.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
        _swingCounter = newSwingCounter();
        _swingSeries = new SwingSeries.Tracker();
        reloadEquipment();
    }

    // Mace uses the validated gyro-primary detector. Clubs and bulava retain
    // the accelerometer detector until their own labelled gyro recordings
    // justify a production change.
    private function newSwingCounter() as SwingCounter.Counter {
        return _equipmentType == Equipment.TYPE_MACE
            ? SwingCounter.maceCounter()
            : SwingCounter.defaultCounter();
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
        _equipmentCount = kind == Equipment.TYPE_CLUBS ? quantity : 1;
        _equipmentWeightGrams = Equipment.defaultWeightGrams(kind);
        _movementType = Movement.resolveFor(_movementType, kind);
        loadComparableHistory();
    }

    // Valid before and during a session: pre-start it re-keys the smoothness
    // trend, mid-session it only redirects what upcoming work blocks record
    // (the session-level trend keeps comparing against the starting movement).
    function selectMovement(movementType as Number) as Void {
        _movementType = Movement.resolveFor(movementType, _equipmentType);
        if (_movementType == Movement.TYPE_COMBO) {
            // One combo cycle works both hands equally.
            _workingSide = Movement.SIDE_ALTERNATING;
        }
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
            // Equipment can change while idle (reloadEquipment doesn't touch
            // the counter), so rebuild it now that the session - and the
            // equipment it locks in - is final.
            _swingCounter = newSwingCounter();
            _fit.createCoreFields(session);
            recordSessionSummary();
            _startBattery = System.getSystemStats().battery;
            _session = session;
            startMotionCapture(session);
            beginSmoothnessSet();
        }
        (_session as ActivityRecording.Session).start();
        _started = true;
        _workOpen = true;
    }

    // Phase-1 motion research (opt-in via the motionCapture setting):
    // stream the accelerometer at 25Hz and log per-second features to
    // the FIT record stream for offline swing analysis. Gyroscope capture
    // rides along whenever export or calibration logging is on - gyro_peak
    // is charted for every export-enabled user (see createMotionExportFields),
    // while the raw per-axis samples stay calibration-only. Note: gyro data
    // does not appear in the Connect IQ simulator, only on a real device.
    private function startMotionCapture(session as ActivityRecording.Session) as Void {
        var exportEnabled = false;
        var debugEnabled = false;
        try {
            var mc = Application.Properties.getValue("motionCapture");
            if (mc instanceof Boolean) {
                exportEnabled = mc;
            }
            var smooth = Application.Properties.getValue("smoothnessEnabled");
            if (smooth instanceof Boolean) {
                _smoothnessEnabled = smooth;
            }
            var load = Application.Properties.getValue("loadExposureEnabled");
            if (load instanceof Boolean) {
                _loadExposureEnabled = load;
            }
            // One switch for calibration recordings: the accel_peak trace and
            // the swing_event trace only line up against each other when both
            // are captured on the same recording, which is easy to forget
            // wiring up from the two separate settings below.
            var debug = Application.Properties.getValue("swingDebugEnabled");
            if (debug instanceof Boolean) {
                debugEnabled = debug;
            }
        } catch (e) {}
        if (debugEnabled) {
            exportEnabled = true;
        }
        _swingDebugEnabled = debugEnabled;
        // Swing counting shares the same accelerometer stream. Challenge
        // presets force it on (the count is the whole point of the mode);
        // regular sessions opt in via the swingCounter setting.
        var swingEnabled = _forceSwingCounting || debugEnabled;
        if (!swingEnabled) {
            try {
                var sc = Application.Properties.getValue("swingCounter");
                if (sc instanceof Boolean) {
                    swingEnabled = sc;
                }
            } catch (e) {}
        }
        if (!exportEnabled && !_smoothnessEnabled && !swingEnabled && !_loadExposureEnabled) {
            return;
        }
        if (!(Sensor has :registerSensorDataListener)) {
            _loadExposureEnabled = false;
            return;
        }
        if (_loadExposureEnabled) {
            _fit.createLoadExposureFields(session);
        }
        if (swingEnabled) {
            _fit.createSwingFields(session);
        }
        // Local smoothness does not create FIT fields. The separate research
        // setting remains the explicit opt-in path for exporting summaries.
        if (exportEnabled) {
            _fit.createMotionExportFields(session, _smoothnessEnabled);
        }
        if (_swingDebugEnabled) {
            _fit.createSwingDebugFields(session);
        }
        var sensorOptions = {:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25}};
        // Every supported device now has a gyroscope; requesting it is a hard
        // runtime requirement rather than an optional enhancement.
        sensorOptions[:gyroscope] = {:enabled => true, :sampleRate => 25};
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), sensorOptions);
            _capturing = true;
            _swingCounting = swingEnabled;
        } catch (e) {
            // Unsupported/broken sensor registration must not silently fall
            // back to a counter we know badly undercounts slow heavy mace.
            _loadExposureEnabled = false;
            _fit.clearLoadExposureFields();
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
        var f = Motion.processWindow(
            accel.x as Array<Number>,
            accel.y as Array<Number>,
            accel.z as Array<Number>,
            _smoothnessEnabled ? _smoothness : null,
            _setSmoothness.isOpen(),
            _loadExposureEnabled ? _loadExposure : null,
            _workOpen,
            _swingCounting ? _swingCounter : null,
            _swingCounting
        );
        _fit.writeMotionFeatures(f[:rms] as Number, f[:peak] as Number, f[:zc] as Number);
        _fit.writeRecordSmoothness(_smoothness.getScore());
        _fit.writeWorkPhase(_workOpen);
        if (_swingDebugEnabled) {
            _fit.writeAccelMin(f[:min] as Number);
            _fit.writeCountingState(_workOpen, _swingCounting);
            _fit.writeRawMagnitudes(
                Motion.rawMagnitudes(
                    accel.x as Array<Number>,
                    accel.y as Array<Number>,
                    accel.z as Array<Number>
                )
            );
        }
        // gyro_peak is charted for every export-enabled user, not just
        // calibration recordings (see createMotionExportFields), so this
        // runs whenever gyro data exists at all.
        var gyro = data.gyroscopeData;
        if (gyro != null) {
            var gyroX = gyro.x as Array<Float>;
            var gyroY = gyro.y as Array<Float>;
            var gyroZ = gyro.z as Array<Float>;
            var g = Motion.gyroFeatures(gyroX, gyroY, gyroZ);
            _fit.writeGyroPeak(g[:peak] as Float);
            if (_swingCounting) {
                _swingCounter.addGyroSamples(gyroX, gyroY, gyroZ, _workOpen);
            }
            if (_swingDebugEnabled) {
                // Stride must match FitFields.GYRO_AXIS_SAMPLE_COUNT, which
                // sizes the gyro_x/y/z fields this feeds.
                var gyroAxisStride = 2;
                _fit.writeRawGyroAxes(
                    Motion.decimatedAxisValues(gyroX, gyroAxisStride),
                    Motion.decimatedAxisValues(gyroY, gyroAxisStride),
                    Motion.decimatedAxisValues(gyroZ, gyroAxisStride)
                );
            }
        }
        if (_swingCounting) {
            var swingPoint = _swingSeries.addTotal(_swingCounter.getCount());
            _fit.writeSwingPoint(
                swingPoint[:total] as Number,
                swingPoint[:event] as Number,
                swingPoint[:cadence] as Number
            );
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
        _workOpen = false;
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
        if (_swingCounting) {
            block.setSwings(_swingCounter.getCount() - _swingsAtBlockStart);
            _swingsAtBlockStart = _swingCounter.getCount();
        }
        if (_loadExposureEnabled) {
            block.setLoadExposure(
                _loadExposure.getExposure(),
                _loadExposure.getPeak(),
                _loadExposure.getActiveSeconds()
            );
            _loadExposure.reset();
        }
        _blocks.add(block);
        _fit.writeSets(_sets);
        // Connect IQ cannot emit Garmin's native strength-set messages. A lap
        // is the supported FIT boundary that preserves each completed set's
        // timestamp and duration for Garmin Connect and exported FIT analysis.
        var session = _session;
        if (_fit.hasLapFields() && session != null && session.isRecording()) {
            _fit.writeLapBoundary(_sets, 1, block);
            session.addLap();
            _fit.prepareOpenLap(0);
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
        if (_sets == 0 || durationSeconds <= 0) {
            return;
        }
        _blocks[_sets - 1].setRestSeconds(clampDuration(durationSeconds));
        var session = _session;
        if (_fit.hasLapFields() && session != null && session.isRecording()) {
            _fit.writeLapBoundary(0, 0, _blocks[_sets - 1]);
            session.addLap();
            _fit.prepareOpenLap(1);
        }
    }

    private function clampDuration(durationSeconds as Number) as Number {
        if (durationSeconds < 0) {
            return 0;
        }
        return durationSeconds > 65535 ? 65535 : durationSeconds;
    }

    function beginSmoothnessSet() as Void {
        // Every work phase begins here (or in start()), so the swing counter
        // shares the boundary: swings during rest never count.
        _workOpen = true;
        if (_smoothnessEnabled) {
            _setSmoothness.begin(_smoothness.getScoreTotal(), _smoothness.getScoredWindows());
        }
    }

    // Persists the FIT session; the caller decides when the app actually
    // exits (the post-workout summary shows first).
    function save() as Void {
        stopMotionCapture();
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            recordBatteryUsed();
            recordSwingTotal();
            recordSessionSummary();
            saveSmoothnessSummary();
            appendHistoryLog();
            session.save();
            _session = null;
        }
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

    // Records one browsable history entry (date, implement, session and per-set
    // scores) for the on-watch History view. Kept separate from the trend list
    // above, which stays a like-for-like comparison keyed by implement.
    private function appendHistoryLog() as Void {
        var score = getSmoothnessScore();
        if (_blocks.size() == 0) {
            return;
        }
        var sets = [] as Array<Number>;
        for (var i = 0; i < _blocks.size(); i++) {
            sets.add(_blocks[i].getSmoothness());
        }
        var rec = SmoothnessLog.record(
            Time.now().value(),
            _equipmentType,
            _equipmentCount,
            _equipmentWeightGrams,
            _movementType,
            _workingSide,
            score,
            sets
        );
        rec = SmoothnessLog.withDetails(rec, getTotalWorkSeconds(), getTotalRestSeconds(), _blocks);
        try {
            var stored = Storage.getValue(SmoothnessLog.STORAGE_KEY);
            var log = stored instanceof Array
                ? stored as Array<Storage.ValueType>
                : [] as Array<Storage.ValueType>;
            Storage.setValue(SmoothnessLog.STORAGE_KEY, SmoothnessLog.append(log, rec));
        } catch (e) {}
    }

    // Force-enables swing counting for challenge presets, where the rep
    // count is the point of the mode. Must be set before start().
    function forceSwingCounting(force as Boolean) as Void {
        if (!_started) {
            _forceSwingCounting = force;
        }
    }

    function isSwingCounting() as Boolean {
        return _swingCounting;
    }

    function getTotalSwings() as Number {
        return _swingCounter.getCount();
    }

    function getCurrentSetSwings() as Number {
        if (!_swingCounting || !_workOpen) {
            return 0;
        }
        var count = _swingCounter.getCount() - _swingsAtBlockStart;
        return count < 0 ? 0 : count;
    }

    // A missed or false-positive detection can be corrected before SELECT
    // commits the current set. The same corrected counter feeds FIT output.
    function adjustCurrentSetSwings(delta as Number) as Void {
        if (!_swingCounting || !_workOpen || delta == 0) {
            return;
        }
        if (delta < 0 && getCurrentSetSwings() == 0) {
            return;
        }
        _swingCounter.adjust(delta > 0 ? 1 : -1);
        _swingSeries.align(_swingCounter.getCount());
    }

    private function recordSwingTotal() as Void {
        if (_swingCounting) {
            _fit.writeSwingTotal(getTotalSwings());
        }
    }

    // Session fields are written at the end of the recording. Keep their
    // Field objects alive and refresh every value just before save; values
    // submitted only during setup can be lost before the session message is
    // serialized on some devices.
    private function recordSessionSummary() as Void {
        _fit.writeSessionSummary(
            _equipmentType,
            _equipmentCount,
            _equipmentWeightGrams,
            _watchWrist,
            getTotalWorkSeconds(),
            getTotalRestSeconds(),
            Equipment.implementName(_equipmentType)
        );
    }

    // Session-level battery cost: start minus end, floored at zero
    // (solar charge or a charger mid-session would otherwise go negative).
    private function recordBatteryUsed() as Void {
        var start = _startBattery;
        if (start == null) {
            return;
        }
        _fit.writeBatteryUsed(batteryDelta(start, System.getSystemStats().battery));
    }

    function batteryDelta(startPct as Float, endPct as Float) as Float {
        var used = startPct - endPct;
        return used < 0.0 ? 0.0 : used;
    }

    // Discard the current FIT session and return this wrapper to its idle
    // state. Unlike save(), this deliberately keeps the app open.
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
        _fit.reset();
        _sets = 0;
        _blocks = [];
        _started = false;
        _startBattery = null;
        _smoothnessEnabled = false;
        _loadExposureEnabled = false;
        _swingDebugEnabled = false;
        _smoothness = new Smoothness.Tracker();
        _loadExposure = new LoadExposure.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
        _swingCounter = newSwingCounter();
        _swingSeries = new SwingSeries.Tracker();
        _swingCounting = false;
        _forceSwingCounting = false;
        _workOpen = false;
        _swingsAtBlockStart = 0;
    }
}
