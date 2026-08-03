import Toybox.Lang;

// The app's own version, shown in the settings menu. Connect IQ manifests
// carry no version and the store numbers uploads with its own counter, so
// this constant is the only way the watch can say what it runs. The
// release workflow refuses to build a tag that does not match it.
module AppVersion {
    const LABEL = "0.9.1";
}
