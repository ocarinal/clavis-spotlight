pragma Singleton
import QtQuick
import Quickshell
import Clavis.Niri
import Clavis.WindowPreview

Singleton {
    id: root

    // niri's ext identifier is its decimal IPC window ID. Do not infer this
    // relationship for other compositors or match windows by title/app-id.
    readonly property bool supported: Niri.connected && backend.supported
    readonly property bool connected: Niri.connected && !suspended
    readonly property int captureCount: backend.captureCount
    property bool suspended: false
    property int revision: 0
    property int nextConsumer: 0
    property bool initialized: false

    function createConsumer() {
        return "dock-preview-" + (++nextConsumer);
    }
    function setTargets(consumer, ids) {
        backend.setTargets(consumer, connected ? ids : []);
    }
    function release(consumer) {
        backend.release(consumer);
    }
    function captureFor(id) {
        return backend.captureFor(String(id));
    }
    function connectBackend() {
        if (!initialized)
            return;
        if (connected)
            backend.open(Quickshell.env("WAYLAND_DISPLAY"));
        else
            backend.close();
    }
    onConnectedChanged: connectBackend()
    Component.onCompleted: {
        initialized = true;
        connectBackend();
    }
    Component.onDestruction: backend.close()

    WindowPreviewManager {
        id: backend
        onCapturesChanged: root.revision++
    }
    Timer {
        interval: 3000
        repeat: true
        // Missing protocols are a stable capability result, not a retry loop.
        running: root.connected && !backend.ready && backend.error !== ""
        onTriggered: root.connectBackend()
    }
}
