import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;

// The FIT adapter for a workout: owns every developer Field object, from
// creation through per-second record writes, lap metadata, and the session
// summary. FIT is an adapter over the app's block model - it does not define
// it; WorkoutSession owns the model and calls in here to mirror it.
class FitFields {
    // FIT developer field ids are the contract with resources/fitfields.xml,
    // the tools/ pipeline, and every previously recorded activity. Never
    // renumber or reuse an id.
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
    const FIELD_ID_RECORD_SWING_TOTAL = 27;
    const FIELD_ID_RECORD_SWING_EVENT = 28;
    const FIELD_ID_SWING_CADENCE = 29;
    const FIELD_ID_RECORD_SMOOTHNESS = 30;
    const FIELD_ID_ACCEL_MIN = 31;
    const FIELD_ID_COUNTING_STATE = 32;

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
    private var _recordSwingTotalField as FitContributor.Field?;
    private var _recordSwingEventField as FitContributor.Field?;
    private var _swingCadenceField as FitContributor.Field?;
    private var _recordSmoothnessField as FitContributor.Field?;
    private var _accelMinField as FitContributor.Field?;
    private var _countingStateField as FitContributor.Field?;

    // The session and lap fields every recording carries.
    function createCoreFields(session as ActivityRecording.Session) as Void {
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
    }

    function createLoadExposureFields(session as ActivityRecording.Session) as Void {
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

    // Drops the load-exposure fields when the accelerometer stream cannot be
    // registered; their values would never be written.
    function clearLoadExposureFields() as Void {
        _motionExposureField = null;
        _motionPeakField = null;
        _activeSecondsField = null;
        _weightVolumeField = null;
    }

    function createSwingFields(session as ActivityRecording.Session) as Void {
        _recordSwingTotalField = session.createField(
            "swing_total",
            FIELD_ID_RECORD_SWING_TOTAL,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "swings"}
        );
        _recordSwingEventField = session.createField(
            "swing_event",
            FIELD_ID_RECORD_SWING_EVENT,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "swings"}
        );
        _swingCadenceField = session.createField(
            "swing_cadence",
            FIELD_ID_SWING_CADENCE,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "spm"}
        );
    }

    // Calibration-only: the per-second trough, alongside the existing peak.
    // Whether a swing detector's re-arm floor (LOW_MG) actually gets cleared
    // between reps is invisible from the peak alone.
    function createSwingDebugFields(session as ActivityRecording.Session) as Void {
        _accelMinField = session.createField(
            "accel_min",
            FIELD_ID_ACCEL_MIN,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"}
        );
        // bit0 = workOpen, bit1 = swingCounting. A recording where a whole
        // work lap counts zero swings despite a clean accelerometer trace
        // could be a gating bug (these bits false when they should be true)
        // rather than a detection-threshold problem - invisible from the
        // motion features alone.
        _countingStateField = session.createField(
            "counting_state",
            FIELD_ID_COUNTING_STATE,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "bit0=workOpen bit1=swingCounting"}
        );
    }

    function createMotionExportFields(session as ActivityRecording.Session, includeSmoothness as Boolean) as Void {
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
        if (includeSmoothness) {
            _recordSmoothnessField = session.createField(
                "smoothness_score",
                FIELD_ID_RECORD_SMOOTHNESS,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "score"}
            );
        }
    }

    // True once the lap fields exist, i.e. a recording session was created.
    function hasLapFields() as Boolean {
        return _setNumberField != null;
    }

    function writeSets(sets as Number) as Void {
        var field = _setsField;
        if (field != null) {
            field.setData(sets);
        }
    }

    function writeMotionFeatures(rms as Number, peak as Number, crossings as Number) as Void {
        var rmsField = _rmsField;
        var peakField = _peakField;
        var zcField = _zcField;
        if (rmsField != null) {
            rmsField.setData(rms);
        }
        if (peakField != null) {
            peakField.setData(peak);
        }
        if (zcField != null) {
            zcField.setData(crossings > 255 ? 255 : crossings);
        }
    }

    function writeAccelMin(min as Number) as Void {
        var field = _accelMinField;
        if (field != null) {
            field.setData(min);
        }
    }

    function writeCountingState(workOpen as Boolean, swingCounting as Boolean) as Void {
        var field = _countingStateField;
        if (field != null) {
            var state = (workOpen ? 0x1 : 0x0) | (swingCounting ? 0x2 : 0x0);
            field.setData(state);
        }
    }

    function writeRecordSmoothness(score as Number) as Void {
        var field = _recordSmoothnessField;
        if (field != null && score >= 0) {
            field.setData(score);
        }
    }

    function writeSwingPoint(total as Number, event as Number, cadence as Number) as Void {
        var totalField = _recordSwingTotalField;
        var eventField = _recordSwingEventField;
        var cadenceField = _swingCadenceField;
        if (totalField != null) {
            totalField.setData(total);
        }
        if (eventField != null) {
            eventField.setData(event);
        }
        if (cadenceField != null) {
            cadenceField.setData(cadence);
        }
    }

    // Stamps the closing lap with a completed block's metadata. A zero set
    // number distinguishes rest laps from completed work-set laps.
    function writeLapBoundary(setNumber as Number, phase as Number, block as WorkBlockSummary) as Void {
        var setNumberField = _setNumberField;
        if (setNumberField != null) {
            setNumberField.setData(setNumber);
        }
        var phaseNameField = _phaseNameField;
        if (phaseNameField != null) {
            phaseNameField.setData(phase == 1 ? "Work" : "Rest");
        }
        var phaseField = _phaseField;
        if (phaseField != null) {
            phaseField.setData(phase);
        }
        var durationField = _phaseDurationField;
        if (durationField != null) {
            durationField.setData(phase == 1 ? block.getWorkSeconds() : block.getRestSeconds());
        }
        var weightField = _lapWeightField;
        if (weightField != null) {
            weightField.setData(block.getEquipmentWeightGrams());
        }
        var wristField = _lapWristField;
        if (wristField != null) {
            wristField.setData(block.getWatchWrist());
        }
        var smoothnessField = _setSmoothnessField;
        if (smoothnessField != null) {
            smoothnessField.setData(phase == 1 ? block.getSmoothness() : -1);
        }
        var movementField = _movementTypeField;
        if (movementField != null) {
            movementField.setData(block.getMovementType());
        }
        var workingSideField = _workingSideField;
        if (workingSideField != null) {
            workingSideField.setData(block.getWorkingSide());
        }
        var lapSwingsField = _lapSwingsField;
        if (lapSwingsField != null) {
            var swings = phase == 1 ? block.getSwings() : 0;
            lapSwingsField.setData(swings < 0 ? 0 : swings);
        }
        var exposureField = _motionExposureField;
        if (exposureField != null) {
            var exposure = phase == 1 ? block.getMotionExposure() : 0;
            exposureField.setData(exposure < 0 ? 0 : exposure);
        }
        var motionPeakField = _motionPeakField;
        if (motionPeakField != null) {
            var peak = phase == 1 ? block.getMotionPeak() : 0;
            motionPeakField.setData(peak < 0 ? 0 : peak);
        }
        var activeSecondsField = _activeSecondsField;
        if (activeSecondsField != null) {
            var active = phase == 1 ? block.getActiveSeconds() : 0;
            activeSecondsField.setData(active < 0 ? 0 : active);
        }
        var weightVolumeField = _weightVolumeField;
        if (weightVolumeField != null) {
            weightVolumeField.setData(phase == 1 ? block.getWeightVolume() : 0);
        }
    }

    // ActivityRecording writes a final partial lap when the session is
    // saved. Never leave the completed set's metadata attached to that open
    // lap, or Garmin exports a tiny duplicate of the final work set.
    function prepareOpenLap(phase as Number) as Void {
        var setNumberField = _setNumberField;
        if (setNumberField != null) {
            setNumberField.setData(0);
        }
        var phaseField = _phaseField;
        if (phaseField != null) {
            phaseField.setData(phase);
        }
        var durationField = _phaseDurationField;
        if (durationField != null) {
            durationField.setData(0);
        }
        var phaseNameField = _phaseNameField;
        if (phaseNameField != null) {
            phaseNameField.setData(phase == 1 ? "Work" : "Rest");
        }
        var lapSwingsField = _lapSwingsField;
        if (lapSwingsField != null) {
            lapSwingsField.setData(0);
        }
    }

    function writeSessionSummary(
        equipmentType as Number,
        equipmentCount as Number,
        equipmentWeightGrams as Number,
        watchWrist as Number,
        totalWorkSeconds as Number,
        totalRestSeconds as Number,
        implementName as String
    ) as Void {
        var equipmentTypeField = _equipmentTypeField;
        if (equipmentTypeField != null) {
            equipmentTypeField.setData(equipmentType);
        }
        var equipmentCountField = _equipmentCountField;
        if (equipmentCountField != null) {
            equipmentCountField.setData(equipmentCount);
        }
        var equipmentWeightField = _equipmentWeightField;
        if (equipmentWeightField != null) {
            equipmentWeightField.setData(equipmentWeightGrams);
        }
        var watchWristField = _watchWristField;
        if (watchWristField != null) {
            watchWristField.setData(watchWrist);
        }
        var totalWorkField = _totalWorkField;
        if (totalWorkField != null) {
            totalWorkField.setData(totalWorkSeconds);
        }
        var totalRestField = _totalRestField;
        if (totalRestField != null) {
            totalRestField.setData(totalRestSeconds);
        }
        var equipmentNameField = _equipmentNameField;
        if (equipmentNameField != null) {
            equipmentNameField.setData(implementName);
        }
    }

    function writeBatteryUsed(delta as Float) as Void {
        var field = _batteryField;
        if (field != null) {
            field.setData(delta);
        }
    }

    function writeSwingTotal(total as Number) as Void {
        var field = _totalSwingsField;
        if (field != null) {
            field.setData(total);
        }
    }

    // Drop every Field reference so a discarded session leaves no stale
    // handles behind for the next recording.
    function reset() as Void {
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
        _recordSwingTotalField = null;
        _recordSwingEventField = null;
        _swingCadenceField = null;
        _recordSmoothnessField = null;
        _accelMinField = null;
        _countingStateField = null;
    }
}
