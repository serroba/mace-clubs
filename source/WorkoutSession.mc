import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;

// Wraps the FIT recording session and custom developer fields.
class WorkoutSession {

    const FIELD_ID_SETS = 0;

    private var _session as ActivityRecording.Session?;
    private var _setsField as FitContributor.Field?;
    private var _sets as Number = 0;
    private var _started as Boolean = false;

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
            var session = ActivityRecording.createSession({
                :name => "Mace & Clubs",
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });
            _setsField = session.createField("total_sets", FIELD_ID_SETS,
                FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "sets" });
            _session = session;
        }
        (_session as ActivityRecording.Session).start();
        _started = true;
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
            Attention.vibrate([
                new Attention.VibeProfile(100, 80),
                new Attention.VibeProfile(0, 80),
                new Attention.VibeProfile(100, 80)
            ]);
        }
    }

    function saveAndExit() as Void {
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            session.save();
            _session = null;
        }
        System.exit();
    }

    function discardAndExit() as Void {
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
