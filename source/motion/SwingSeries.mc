import Toybox.Lang;

// Converts the detector's cumulative count into record-level training data.
// Cadence is a trailing ten-second rate: responsive enough to show changes
// without turning one missed sample into a distracting 0/60 oscillation.
module SwingSeries {
    const WINDOW_SECONDS = 10;

    class Tracker {
        private var _lastTotal as Number = 0;
        private var _events as Array<Number> = [];
        private var _windowTotal as Number = 0;

        function addTotal(total as Number) as Dictionary {
            var event = total - _lastTotal;
            if (event < 0) {
                event = 0;
            } else if (event > 255) {
                event = 255;
            }
            _lastTotal = total;
            _events.add(event);
            _windowTotal += event;
            if (_events.size() > WINDOW_SECONDS) {
                var removed = _events[0];
                _events.remove(0);
                _windowTotal -= removed;
            }
            var seconds = _events.size();
            var cadence = seconds == 0 ? 0 : _windowTotal * 60 / seconds;
            return {:total => total, :event => event, :cadence => cadence};
        }

        // Manual count corrections are bookkeeping, not newly detected
        // swings. Aligning prevents the next sensor record inventing an event.
        function align(total as Number) as Void {
            _lastTotal = total;
        }

        function reset() as Void {
            _lastTotal = 0;
            _events = [];
            _windowTotal = 0;
        }
    }
}
