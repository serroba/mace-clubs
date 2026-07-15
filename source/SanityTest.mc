import Toybox.Lang;
import Toybox.Test;

// Pipeline canary: proves the CI test job compiles and executes tests.
(:test)
function testSanity(logger as Test.Logger) as Boolean {
    return true;
}
