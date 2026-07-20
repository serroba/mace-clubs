import Toybox.Application;
import Toybox.Lang;

// A compact, privacy-preserving description of the implement used for a
// workout. The profile is configured on the phone and written only into the
// user's activity FIT file and local smoothness-history key.
module Equipment {
    const TYPE_MACE = 0;
    const TYPE_CLUBS = 1;

    function type() as Number {
        return numberProperty("equipmentType", TYPE_MACE);
    }

    function count() as Number {
        if (type() == TYPE_MACE) {
            return 1;
        }
        return numberProperty("equipmentCount", 2) == 1 ? 1 : 2;
    }

    function weightGrams() as Number {
        var grams = numberProperty("equipmentWeightGrams", 10000);
        return grams < 0 ? 0 : grams;
    }

    function weightLabel(grams as Number) as String {
        var whole = grams / 1000;
        var tenths = grams % 1000 / 100;
        return tenths == 0 ? Lang.format("$1$ kg", [whole]) : Lang.format("$1$.$2$ kg", [whole, tenths]);
    }

    function labelFor(kind as Number, quantity as Number, grams as Number) as String {
        var weight = weightLabel(grams);
        if (kind == TYPE_CLUBS) {
            return quantity == 1 ? Lang.format("Club: $1$", [weight]) : Lang.format("Clubs: 2 x $1$", [weight]);
        }
        return Lang.format("Mace: $1$", [weight]);
    }

    function label() as String {
        return labelFor(type(), count(), weightGrams());
    }

    // Smoothness is only comparable when implement type, quantity, and
    // per-implement weight all match.
    function historyKeyFor(kind as Number, quantity as Number, grams as Number) as String {
        return Lang.format("smoothV2_$1$_$2$_$3$", [kind, quantity, grams]);
    }

    function historyKey() as String {
        return historyKeyFor(type(), count(), weightGrams());
    }

    function numberProperty(key as String, fallback as Number) as Number {
        try {
            var value = Application.Properties.getValue(key);
            if (value instanceof Number) {
                return value;
            }
        } catch (e) {}
        return fallback;
    }
}
