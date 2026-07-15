import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
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
        }
        (_session as ActivityRecording.Session).start();
        _started = true;
    }

    // Phase-1 motion research (opt-in via the motionCapture setting):
    // stream the accelerometer at 25Hz and log per-second features to
    // the FIT record stream for offline swing analysis. Accel only -
    // gyro support on the Instinct is unverified.
    private function startMotionCapture(session as ActivityRecording.Session) as Void {
        var enabled = false;
        try {
            var mc = Application.Properties.getValue("motionCapture");
            if (mc instanceof Boolean) {
                enabled = mc;
            }
        } catch (e) {}
        if (!enabled || !(Sensor has :registerSensorDataListener)) {
            return;
        }
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
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        var f = Motion.features(accel.x as Array<Number>, accel.y as Array<Number>, accel.z as Array<Number>);
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

    function saveAndExit() as Void {
        stopMotionCapture();
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            recordBatteryUsed();
            session.save();
            _session = null;
        }
        System.exit();
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

    function discardAndExit() as Void {
        stopMotionCapture();
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            session.discard();
            _session = null;
        }
        System.exit();
    }
}
