pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The standalone Spotlight profile keeps its own isolated Clavis
// configuration, so writing through WallpaperService would never reach the
// running desktop. This session renders the desktop wallpaper through
// Noctalia, which owns the surface and the generated palette, so applying and
// reading the current wallpaper go through its IPC.
Singleton {
    id: root

    readonly property string command: Quickshell.env("CLAVIS_NOCTALIA") || "noctalia"
    readonly property int actionTimeoutMs: 10000

    property bool probeComplete: false
    property bool available: false
    property bool refreshing: false
    property bool applying: false
    property bool cycling: false
    property string currentPath: ""
    property string pendingPath: ""
    property string lastError: ""
    property string _currentOutput: ""
    property bool _currentStdoutFinished: false
    property bool _currentStarted: false
    property bool _currentExited: false
    property int _currentExitCode: -1
    property int _currentExitStatus: 1
    property bool _applyStarted: false
    property bool _applyExited: false
    property int _applyExitCode: -1
    property int _applyExitStatus: 1
    property bool _cycleStarted: false
    property bool _cycleExited: false
    property int _cycleExitCode: -1
    property int _cycleExitStatus: 1

    signal applied(string path)
    signal applyFailed(string path, string message)

    function firstPath(text) {
        const lines = String(text || "").split("\n");
        for (let index = 0; index < lines.length; index += 1) {
            const value = lines[index].trim();
            if (value.startsWith("/"))
                return value;
        }
        return "";
    }

    function refresh() {
        if (currentProcess.running)
            return false;
        root._currentOutput = "";
        root._currentStdoutFinished = false;
        root._currentStarted = false;
        root._currentExited = false;
        root._currentExitCode = -1;
        root._currentExitStatus = 1;
        root.refreshing = true;
        currentProcess.command = [root.command, "msg", "wallpaper-get"];
        currentProcess.running = true;
        currentWatchdog.restart();
        return true;
    }

    function finishCurrent() {
        if (!root._currentExited || !root._currentStdoutFinished)
            return;
        currentWatchdog.stop();
        root.refreshing = false;
        const succeeded = root._currentStarted && root._currentExitCode === 0 && root._currentExitStatus
              === 0;
        root.probeComplete = true;
        root.available = succeeded;
        if (!succeeded) {
            root.lastError = qsTr("Desktop wallpaper service is unavailable");
            return;
        }
        const path = root.firstPath(root._currentOutput);
        if (path !== "") {
            root.currentPath = path;
            root.lastError = "";
        }
    }

    function failCurrent() {
        root.refreshing = false;
        root.probeComplete = true;
        root.available = false;
        root.lastError = qsTr("Desktop wallpaper service is unavailable");
    }

    function apply(path) {
        const target = String(path || "").trim();
        if (target === "" || root.applying)
            return false;
        root.pendingPath = target;
        root.lastError = "";
        root.applying = true;
        root._applyStarted = false;
        root._applyExited = false;
        root._applyExitCode = -1;
        root._applyExitStatus = 1;
        applyProcess.command = [root.command, "msg", "wallpaper-set", target];
        applyProcess.running = true;
        applyWatchdog.restart();
        return true;
    }

    function finishApply() {
        if (!root._applyExited)
            return;
        applyWatchdog.stop();
        const target = root.pendingPath;
        const succeeded = root._applyStarted && root._applyExitCode === 0 && root._applyExitStatus === 0;
        root.applying = false;
        root.pendingPath = "";
        if (!succeeded) {
            root.available = false;
            root.lastError = qsTr("Could not set the wallpaper");
            root.applyFailed(target, root.lastError);
            return;
        }
        root.available = true;
        root.currentPath = target;
        root.lastError = "";
        root.applied(target);
        root.refresh();
    }

    // Wallpaper cycling stays on the desktop owner as well: Noctalia owns the
    // rotation history, so the launcher only asks for the next step.
    function cycle(action) {
        const verb = String(action || "");
        if (["wallpaper-next", "wallpaper-previous", "wallpaper-random"].indexOf(verb) < 0)
            return false;
        if (root.cycling)
            return false;
        root.cycling = true;
        root.lastError = "";
        root._cycleStarted = false;
        root._cycleExited = false;
        root._cycleExitCode = -1;
        root._cycleExitStatus = 1;
        cycleProcess.command = [root.command, "msg", verb];
        cycleProcess.running = true;
        cycleWatchdog.restart();
        return true;
    }

    function finishCycle() {
        if (!root._cycleExited)
            return;
        cycleWatchdog.stop();
        const succeeded = root._cycleStarted && root._cycleExitCode === 0 && root._cycleExitStatus === 0;
        root.cycling = false;
        if (!succeeded) {
            root.lastError = qsTr("Could not change the wallpaper");
            return;
        }
        root.lastError = "";
        root.refresh();
    }

    Timer {
        id: currentWatchdog

        interval: root.actionTimeoutMs
        repeat: false
        onTriggered: {
            if (root._currentExited)
                return;
            currentProcess.running = false;
            root._currentStdoutFinished = true;
            root._currentExited = true;
            root.failCurrent();
        }
    }

    Timer {
        id: applyWatchdog

        interval: root.actionTimeoutMs
        repeat: false
        onTriggered: {
            if (root._applyExited)
                return;
            applyProcess.running = false;
            root._applyExited = true;
            root.finishApply();
        }
    }

    Timer {
        id: cycleWatchdog

        interval: root.actionTimeoutMs
        repeat: false
        onTriggered: {
            if (root._cycleExited)
                return;
            cycleProcess.running = false;
            root._cycleExited = true;
            root.finishCycle();
        }
    }

    Process {
        id: currentProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root._currentOutput = text;
                root._currentStdoutFinished = true;
                root.finishCurrent();
            }
        }
        onStarted: root._currentStarted = true
        onExited: (exitCode, exitStatus) => {
            root._currentExitCode = exitCode;
            root._currentExitStatus = exitStatus;
            root._currentExited = true;
            root.finishCurrent();
        }
        onRunningChanged: {
            if (running || root._currentExited)
                return;
            // A failed spawn reports no exit signal; the watchdog covers a
            // command that starts but never terminates.
            if (!root._currentStarted) {
                root._currentStdoutFinished = true;
                root._currentExited = true;
                currentWatchdog.stop();
                root.failCurrent();
            }
        }
    }

    Process {
        id: applyProcess

        onStarted: root._applyStarted = true
        onExited: (exitCode, exitStatus) => {
            root._applyExitCode = exitCode;
            root._applyExitStatus = exitStatus;
            root._applyExited = true;
            root.finishApply();
        }
        onRunningChanged: {
            if (running || root._applyExited)
                return;
            if (!root._applyStarted) {
                root._applyExited = true;
                applyWatchdog.stop();
                root.finishApply();
            }
        }
    }

    Process {
        id: cycleProcess

        onStarted: root._cycleStarted = true
        onExited: (exitCode, exitStatus) => {
            root._cycleExitCode = exitCode;
            root._cycleExitStatus = exitStatus;
            root._cycleExited = true;
            root.finishCycle();
        }
        onRunningChanged: {
            if (running || root._cycleExited)
                return;
            if (!root._cycleStarted) {
                root._cycleExited = true;
                cycleWatchdog.stop();
                root.finishCycle();
            }
        }
    }
}
