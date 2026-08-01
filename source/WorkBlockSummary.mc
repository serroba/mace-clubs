import Toybox.Lang;

// The app's authoritative description of one completed movement block.
// Garmin FIT laps are only a serialization of this model.
class WorkBlockSummary {
    private var _setNumber as Number;
    private var _workSeconds as Number;
    private var _restSeconds as Number = 0;
    private var _movementType as Number;
    private var _workingSide as Number;
    private var _equipmentType as Number;
    private var _equipmentCount as Number;
    private var _equipmentWeightGrams as Number;
    private var _watchWrist as Number;
    private var _smoothness as Number;
    // Set after construction like rest seconds: CIQ 3.1 devices cap methods
    // at nine arguments, and the constructor is already at that limit.
    private var _swings as Number = -1;

    function initialize(
        setNumber as Number,
        workSeconds as Number,
        movementType as Number,
        workingSide as Number,
        equipmentType as Number,
        equipmentCount as Number,
        equipmentWeightGrams as Number,
        watchWrist as Number,
        smoothness as Number
    ) {
        _setNumber = setNumber;
        _workSeconds = workSeconds;
        _movementType = movementType;
        _workingSide = workingSide;
        _equipmentType = equipmentType;
        _equipmentCount = equipmentCount;
        _equipmentWeightGrams = equipmentWeightGrams;
        _watchWrist = watchWrist;
        _smoothness = smoothness;
    }

    function getSetNumber() as Number {
        return _setNumber;
    }

    function getWorkSeconds() as Number {
        return _workSeconds;
    }

    function getRestSeconds() as Number {
        return _restSeconds;
    }

    function setRestSeconds(seconds as Number) as Void {
        _restSeconds = seconds;
    }

    function getMovementType() as Number {
        return _movementType;
    }

    function getWorkingSide() as Number {
        return _workingSide;
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

    function getWatchWrist() as Number {
        return _watchWrist;
    }

    function getSmoothness() as Number {
        return _smoothness;
    }

    // Detected swing cycles during this block's work phase; -1 when the
    // swing counter was not running.
    function getSwings() as Number {
        return _swings;
    }

    function setSwings(swings as Number) as Void {
        _swings = swings;
    }
}
