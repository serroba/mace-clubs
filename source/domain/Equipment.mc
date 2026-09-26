import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

// A compact, privacy-preserving description of the implement used for a
// workout. The profile is configured on the phone and written only into the
// user's activity FIT file and local smoothness-history key.
module Equipment {
    const TYPE_MACE = 0;
    const TYPE_CLUBS = 1;
    const TYPE_BULAVA = 2;
    // Appended, like the bulava before it, so the implement_type already
    // written into every existing FIT file keeps its meaning.
    const TYPE_MUDGAR = 3;

    function type() as Number {
        return numberProperty("equipmentType", TYPE_MACE);
    }

    // Only clubs come in pairs here. A mudgar is swung as a pair in the
    // Indian tradition as often as singly, but the app records one at a time
    // until there is a reason to model the pair - the quantity is part of the
    // smoothness history key, so adding it later starts new histories rather
    // than corrupting old ones.
    function count() as Number {
        if (type() != TYPE_CLUBS) {
            return 1;
        }
        return numberProperty("equipmentCount", 2) == 1 ? 1 : 2;
    }

    function weightKeyFor(kind as Number) as String {
        if (kind == TYPE_CLUBS) {
            return "clubWeightGrams";
        }
        if (kind == TYPE_BULAVA) {
            return "bulavaWeightGrams";
        }
        if (kind == TYPE_MUDGAR) {
            return "mudgarWeightGrams";
        }
        return "maceWeightGrams";
    }

    // Starting weights, in grams, for an athlete who has not set their own.
    // A bulava and a mudgar are both typically heavier than a starter mace or
    // club; these match the defaults in resources/settings/properties.xml,
    // which is what a watch actually reads.
    function startingGramsFor(kind as Number) as Number {
        if (kind == TYPE_BULAVA) {
            return 6000;
        }
        if (kind == TYPE_MUDGAR) {
            return 5000;
        }
        return 4000;
    }

    function defaultWeightGrams(kind as Number) as Number {
        var grams = numberProperty(weightKeyFor(kind), startingGramsFor(kind));
        return grams < 0 ? 0 : grams;
    }

    function implementName(kind as Number) as String {
        if (kind == TYPE_CLUBS) {
            return "Club";
        }
        if (kind == TYPE_BULAVA) {
            return "Bulava";
        }
        if (kind == TYPE_MUDGAR) {
            return "Mudgar";
        }
        return "Mace";
    }

    function weightLabel(grams as Number) as String {
        if (usesPounds()) {
            var poundTenths = grams * 10000 + 226796;
            poundTenths /= 453592;
            return decimalLabel(poundTenths, "lb");
        }
        return decimalLabel(grams / 100, "kg");
    }

    function decimalLabel(tenths as Number, unit as String) as String {
        var whole = tenths / 10;
        var decimal = tenths % 10;
        return decimal == 0
            ? Lang.format("$1$ $2$", [whole, unit])
            : Lang.format("$1$.$2$ $3$", [whole, decimal, unit]);
    }

    function usesPounds() as Boolean {
        try {
            var settings = System.getDeviceSettings();
            return settings.weightUnits == System.UNIT_STATUTE;
        } catch (e) {}
        return false;
    }

    function editorTenths(grams as Number, pounds as Boolean) as Number {
        if (!pounds) {
            return grams / 100;
        }
        var poundTenths = grams * 10000 + 226796;
        return poundTenths / 453592;
    }

    function gramsFromEditorTenths(tenths as Number, pounds as Boolean) as Number {
        return pounds ? tenths * 453592 / 10000 : tenths * 100;
    }

    function labelFor(kind as Number, quantity as Number, grams as Number) as String {
        var weight = weightLabel(grams);
        if (kind == TYPE_CLUBS && quantity != 1) {
            return Lang.format("Clubs: 2 x $1$", [weight]);
        }
        return Lang.format("$1$: $2$", [implementName(kind), weight]);
    }

    function label() as String {
        return labelFor(type(), count(), defaultWeightGrams(type()));
    }

    // Smoothness is only comparable when implement type, quantity, and
    // per-implement weight all match.
    function historyKeyFor(kind as Number, quantity as Number, grams as Number) as String {
        return Lang.format("smoothV2_$1$_$2$_$3$", [kind, quantity, grams]);
    }

    function historyKey() as String {
        return historyKeyFor(type(), count(), defaultWeightGrams(type()));
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
