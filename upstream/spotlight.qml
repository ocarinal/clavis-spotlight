//@ pragma UseQApplication
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.Dock
import qs.Modules.Launcher
import qs.Modules.ControlCenter
import qs.Services

ShellRoot {
    // The standalone entry loads the launcher without AppShell, so nothing
    // would instantiate the translator singleton: the whole surface would stay
    // in the source language.
    // Search actions are dispatched by the same catalog as the full shell;
    // this entry only owns the wallpaper ones, which belong to the desktop
    // owner in this session.
    function executeSearchAction(entry) {
        if (entry.target !== "wallpaper")
            return false;
        return NoctaliaWallpaperService.cycle(entry.method);
    }

    Component.onCompleted: {
        I18nService.initialize();
        SpotlightCatalog.actionExecutor = entry => executeSearchAction(entry);
    }

    LauncherWindow {
        id: launcher
    }

    // 与 Spotlight 同一套配色与模糊的 dock，替代 Noctalia 自带的 dock。
    DockHost {}

    LazyLoader {
        id: controlCenterLoader

        active: false
        Component.onCompleted: ControlCenterService.registerLoader(controlCenterLoader)
        onItemChanged: {
            if (item)
                ControlCenterService.registerWindow(item);
        }

        ControlCenterWindow {
            id: controlCenterWindow

            onPopoutClosed: ControlCenterService.windowClosed(controlCenterWindow)
        }
    }

    Timer {
        id: expandModesTimer

        interval: 60
        repeat: false
        onTriggered: launcher.setRailExpanded(true)
    }

    IpcHandler {
        target: "spotlight"

        function toggle(): string {
            if (launcher.windowPhase === "hidden" || launcher.windowPhase === "closing") {
                launcher.openSpotlight("apps");
                expandModesTimer.restart();
            } else {
                expandModesTimer.stop();
                launcher.requestClose();
            }
            return launcher.windowPhase.toUpperCase();
        }

        function open(): string {
            launcher.openSpotlight();
            return launcher.windowPhase.toUpperCase();
        }

        function close(): string {
            expandModesTimer.stop();
            launcher.requestClose();
            return launcher.windowPhase.toUpperCase();
        }

        function modes(): string {
            launcher.openSpotlight("apps");
            expandModesTimer.restart();
            return "MODES";
        }

        function web(): string {
            launcher.openWebMode();
            return "WEB";
        }

        function openMode(mode: string): string {
            if (launcher.normalizedMode(mode || "") === "")
                return "INVALID_MODE";

            launcher.openSpotlight(mode);
            return String(mode).toUpperCase();
        }
    }
}
