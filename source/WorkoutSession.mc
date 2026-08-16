import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;

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
    const FIELD_ID_TOTAL_SWINGS = 17;
    const FIELD_ID_LAP_SWINGS = 18;
    const FIELD_ID_MOTION_EXPOSURE = 19;
    const FIELD_ID_MOTION_PEAK = 20;
    const FIELD_ID_ACTIVE_SECONDS = 21;
    const FIELD_ID_WEIGHT_VOLUME = 22;
    const FIELD_ID_TOTAL_WORK_SECONDS = 23;
    const FIELD_ID_TOTAL_REST_SECONDS = 24;
    const FIELD_ID_PHASE_NAME = 25;
    const FIELD_ID_EQUIPMENT_NAME = 26;

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
    private var _totalSwingsField as FitContributor.Field?;
    private var _lapSwingsField as FitContributor.Field?;
    private var _motionExposureField as FitContributor.Field?;
    private var _motionPeakField as FitContributor.Field?;
    private var _activeSecondsField as FitContributor.Field?;
    private var _weightVolumeField as FitContributor.Field?;
    private var _batteryField as FitContributor.Field?;
    private var _equipmentTypeField as FitContributor.Field?;
    private var _equipmentCountField as FitContributor.Field?;
    private var _equipmentWeightField as FitContributor.Field?;
    private var _watchWristField as FitContributor.Field?;
    private var _totalWorkField as FitContributor.Field?;
    private var _totalRestField as FitContributor.Field?;
    private var _phaseNameField as FitContributor.Field?;
    private var _equipmentNameField as FitContributor.Field?;
    private var _rmsField as FitContributor.Field?;
    private var _peakField as FitContributor.Field?;
    private var _zcField as FitContributor.Field?;
    private var _sets as Number = 0;
    private var _started as Boolean = false;
    private var _startBattery as Float?;
    private var _capturing as Boolean = false;
    private var _smoothnessEnabled as Boolean = false;
    private var _loadExposureEnabled as Boolean = false;
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
    private var _swingCounting as Boolean = false;
    private var _forceSwingCounting as Boolean = false;
    private var _workOpen as Boolean = false;
    private var _swingsAtBlockStart as Number = 0;

    function initialize() {
        _smoothness = new Smoothness.Tracker();
        _loadExposure = new LoadExposure.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
        _swingCounter = new SwingCounter.Counter();
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
            _totalSwingsField = session.createField(
                "total_swings",
                FIELD_ID_TOTAL_SWINGS,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "swings"}
            );
            _lapSwingsField = session.createField(
                "swing_count",
                FIELD_ID_LAP_SWINGS,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "swings"}
            );
            _batteryField = session.createField(
                "battery_used",
                FIELD_ID_BATTERY,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"}
            );
            _equipmentTypeField = session.createField(
                "implement_type",
                FIELD_ID_EQUIPMENT_TYPE,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "0=mace 1=clubs"}
            );
            _equipmentCountField = session.createField(
                "implement_count",
                FIELD_ID_EQUIPMENT_COUNT,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "implements"}
            );
            _equipmentWeightField = session.createField(
                "implement_weight",
                FIELD_ID_EQUIPMENT_WEIGHT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "g"}
            );
            _watchWristField = session.createField(
                "watch_wrist",
                FIELD_ID_WATCH_WRIST,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "0=left 1=right"}
            );
            _totalWorkField = session.createField(
                "work_time",
                FIELD_ID_TOTAL_WORK_SECONDS,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"}
            );
            _totalRestField = session.createField(
                "rest_time",
                FIELD_ID_TOTAL_REST_SECONDS,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"}
            );
            _phaseNameField = session.createField(
                "phase_name",
                FIELD_ID_PHASE_NAME,
                FitContributor.DATA_TYPE_STRING,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :count => 5, :units => ""}
            );
            _equipmentNameField = session.createField(
                "implement_name",
                FIELD_ID_EQUIPMENT_NAME,
                FitContributor.DATA_TYPE_STRING,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :count => 8, :units => ""}
            );
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
            var load = Application.Properties.getValue("loadExposureEnabled");
            if (load instanceof Boolean) {
                _loadExposureEnabled = load;
            }
        } catch (e) {}
        // Swing counting shares the same accelerometer stream. Challenge
        // presets force it on (the count is the whole point of the mode);
        // regular sessions opt in via the swingCounter setting.
        var swingEnabled = _forceSwingCounting;
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
            _motionExposureField = session.createField(
                "motion_exposure",
                FIELD_ID_MOTION_EXPOSURE,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "mg-s"}
            );
            _motionPeakField = session.createField(
                "motion_peak",
                FIELD_ID_MOTION_PEAK,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "mg"}
            );
            _activeSecondsField = session.createField(
                "active_seconds",
                FIELD_ID_ACTIVE_SECONDS,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"}
            );
            _weightVolumeField = session.createField(
                "weight_volume",
                FIELD_ID_WEIGHT_VOLUME,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "kg-swings"}
            );
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
            _swingCounting = swingEnabled;
        } catch (e) {
            // no high-rate accel on this device; features stay unwritten
            _loadExposureEnabled = false;
            _motionExposureField = null;
            _motionPeakField = null;
            _activeSecondsField = null;
            _weightVolumeField = null;
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
        if (_sets == 0 || durationSeconds <= 0) {
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
        var lapSwingsField = _lapSwingsField;
        var exposureField = _motionExposureField;
        var motionPeakField = _motionPeakField;
        var activeSecondsField = _activeSecondsField;
        var weightVolumeField = _weightVolumeField;
        var phaseNameField = _phaseNameField;
        if (phaseNameField != null) {
            phaseNameField.setData(phase == 1 ? "Work" : "Rest");
        }
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
        if (lapSwingsField != null) {
            var swings = phase == 1 ? block.getSwings() : 0;
            lapSwingsField.setData(swings < 0 ? 0 : swings);
        }
        if (exposureField != null) {
            var exposure = phase == 1 ? block.getMotionExposure() : 0;
            exposureField.setData(exposure < 0 ? 0 : exposure);
        }
        if (motionPeakField != null) {
            var peak = phase == 1 ? block.getMotionPeak() : 0;
            motionPeakField.setData(peak < 0 ? 0 : peak);
        }
        if (activeSecondsField != null) {
            var active = phase == 1 ? block.getActiveSeconds() : 0;
            activeSecondsField.setData(active < 0 ? 0 : active);
        }
        if (weightVolumeField != null) {
            weightVolumeField.setData(phase == 1 ? block.getWeightVolume() : 0);
        }
    }

    function beginSmoothnessSet() as Void {
        // Every work phase begins here (or in start()), so the swing counter
        // shares the boundary: swings during rest never count.
        _workOpen = true;
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
            recordSwingTotal();
            recordSessionSummary();
            saveSmoothnessSummary();
            appendHistoryLog();
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
    }

    private function recordSwingTotal() as Void {
        var field = _totalSwingsField;
        if (field != null && _swingCounting) {
            field.setData(getTotalSwings());
        }
    }

    // Session fields are written at the end of the recording. Keep their
    // Field objects alive and refresh every value just before save; values
    // submitted only during setup can be lost before the session message is
    // serialized on some devices.
    private function recordSessionSummary() as Void {
        var equipmentType = _equipmentTypeField;
        var equipmentCount = _equipmentCountField;
        var equipmentWeight = _equipmentWeightField;
        var watchWrist = _watchWristField;
        var totalWork = _totalWorkField;
        var totalRest = _totalRestField;
        var equipmentName = _equipmentNameField;
        if (equipmentType != null) {
            equipmentType.setData(_equipmentType);
        }
        if (equipmentCount != null) {
            equipmentCount.setData(_equipmentCount);
        }
        if (equipmentWeight != null) {
            equipmentWeight.setData(_equipmentWeightGrams);
        }
        if (watchWrist != null) {
            watchWrist.setData(_watchWrist);
        }
        if (totalWork != null) {
            totalWork.setData(getTotalWorkSeconds());
        }
        if (totalRest != null) {
            totalRest.setData(getTotalRestSeconds());
        }
        if (equipmentName != null) {
            equipmentName.setData(Equipment.implementName(_equipmentType));
        }
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
        _totalSwingsField = null;
        _lapSwingsField = null;
        _motionExposureField = null;
        _motionPeakField = null;
        _activeSecondsField = null;
        _weightVolumeField = null;
        _batteryField = null;
        _equipmentTypeField = null;
        _equipmentCountField = null;
        _equipmentWeightField = null;
        _watchWristField = null;
        _totalWorkField = null;
        _totalRestField = null;
        _phaseNameField = null;
        _equipmentNameField = null;
        _rmsField = null;
        _peakField = null;
        _zcField = null;
        _sets = 0;
        _blocks = [];
        _started = false;
        _startBattery = null;
        _smoothnessEnabled = false;
        _loadExposureEnabled = false;
        _smoothness = new Smoothness.Tracker();
        _loadExposure = new LoadExposure.Tracker();
        _setSmoothness = new SmoothnessSetSummaries();
        _swingCounter = new SwingCounter.Counter();
        _swingCounting = false;
        _forceSwingCounting = false;
        _workOpen = false;
        _swingsAtBlockStart = 0;
    }
}
