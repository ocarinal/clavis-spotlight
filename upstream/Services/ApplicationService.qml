pragma Singleton

import QtQuick
import Quickshell
import qs.Services

Singleton {
    id: root

    property var applications: []
    readonly property string settingsIconName: {
        // Re-evaluate availability after Qt has applied the selected theme.
        const revision = ThemeService.iconThemeRevision;
        for (const name of ["preferences-system", "preferences-desktop"]) {
            if (Quickshell.hasThemeIcon(name))
                return name;
        }
        return "";
    }
    readonly property var settingsApplication: ({
                                                    id: "org.clavis.Settings",
                                                    name: qsTranslate("ControlCenterWindow", "Settings"),
                                                    genericName: "Clavis",
                                                    keywords: ["Clavis", "settings", "preferences",
                                                        "control center"],
                                                    symbol: root.settingsIconName ? "" : "settings",
                                                    icon: root.settingsIconName
                                                })
    readonly property var spaceApplication: ({
                                                 id: "org.clavis.Space",
                                                 name: qsTr("Space"),
                                                 genericName: qsTr("Drag to Dock to add a blank space"),
                                                 keywords: ["space", "spacer", "blank", "dock"],
                                                 symbol: "check_box_outline_blank",
                                                 icon: "",
                                                 dragOnly: true
                                             })
    readonly property var smallSpaceApplication: ({
                                                      id: "org.clavis.SmallSpace",
                                                      name: qsTr("Small Space"),
                                                      genericName: qsTr("Drag to Dock to add a blank space"),
                                                      keywords: ["space", "spacer", "blank", "dock", "small",
                                                          "narrow"],
                                                      symbol: "check_box_outline_blank",
                                                      icon: "",
                                                      dragOnly: true
                                                  })
    // Internal shell entries belong in the launcher, not in default-app or
    // autostart pickers that require an installed desktop application.
    readonly property var launcherApplications: applications.concat([settingsApplication, spaceApplication,
                                                                     smallSpaceApplication])

    function launchCommand(command, workingDirectory) {
        const argv = Array.from(command || []);
        if (argv.length === 0 || !String(argv[0]).trim())
            return false;

        // Enter the scope before executing the app, so even its earliest
        // children cannot inherit clavis-shell.service's control group.
        // Scope mode preserves the caller's environment and working directory.
        const scopedCommand = ["systemd-run", "--user", "--scope", "--collect", "--quiet", "--slice=app.slice",
                               "--expand-environment=no"];
        if (workingDirectory)
            scopedCommand.push("--working-directory=" + String(workingDirectory));
        Quickshell.execDetached(scopedCommand.concat(["--"], argv));
        return true;
    }

    function launchApplication(application) {
        if (!application || application.dragOnly)
            return false;
        if (application.id === root.settingsApplication.id)
            return ControlCenterService.openOrFocus();
        return root.launchCommand(application.command, application.workingDirectory);
    }

    function openUrl(url) {
        const value = String(url || "");
        if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value))
            return false;
        // GIO honors the default desktop entry's Terminal=true and opens a
        // terminal through the system launcher (e.g. for Yazi). xdg-open's
        // generic backend executes these file handlers without a terminal.
        return root.launchCommand(/^(file|trash):/i.test(value) ? ["gio", "open", value] : ["xdg-open",
                                                                                            value]);
    }

    function isVisibleApplication(application) {
        if (!application)
            return false;
        if (application.noDisplay === true || application.hidden === true)
            return false;
        return String(application.id || "").trim() !== "" && String(application.execString || application.exec
                                                                    || "").trim() !== "";
    }

    function refresh() {
        const source = DesktopEntries.applications.values || [];
        const seen = new Set();
        const next = [];
        for (const application of source) {
            if (!root.isVisibleApplication(application))
                continue;
            const id = String(application.id);
            if (seen.has(id))
                continue;
            seen.add(id);
            next.push(application);
        }
        next.sort((left, right) => {
            const byName = String(left.name || left.id).localeCompare(String(right.name || right.id));
            return byName !== 0 ? byName : String(left.id).localeCompare(String(right.id));
        });
        root.applications = next;
    }

    function getVisibleApplications() {
        return root.applications.slice();
    }

    function findById(identifier) {
        const value = String(identifier || "");
        if (value === root.smallSpaceApplication.id)
            return root.smallSpaceApplication;
        if (value === root.spaceApplication.id)
            return root.spaceApplication;
        if (value === root.settingsApplication.id)
            return root.settingsApplication;
        const withoutSuffix = value.endsWith(".desktop") ? value.substring(0, value.length
                                                                           - ".desktop".length) : value;
        for (const application of root.applications) {
            const id = String(application.id || "");
            if (id === value || id === withoutSuffix || id === withoutSuffix + ".desktop") {
                return application;
            }
        }
        return null;
    }

    function iconSource(iconName) {
        const revision = ThemeService.iconThemeRevision;
        const value = String(iconName || "");
        if (value.startsWith("file://") || value.startsWith("image://"))
            return value;
        if (value.startsWith("/"))
            return "file://" + value;
        const resolved = Quickshell.iconPath(value || "application-x-executable", "application-x-executable");
        return resolved && resolved !== "" ? resolved : "image://icon/application-x-executable";
    }

    function iconSourceForEntry(entry) {
        if (!entry)
            return root.iconSource("");
        const application = root.findById(entry.id);
        if (application && application.icon)
            return root.iconSource(application.icon);
        if (entry.icon)
            return root.iconSource(entry.icon);

        const command = String(entry.exec || "").trim().split(/\s+/)[0];
        const commandName = command.substring(command.lastIndexOf("/") + 1);
        if (commandName) {
            for (const candidate of root.applications) {
                const candidateCommand = String(candidate.execString || candidate.exec || "").trim().split(
                          /\s+/)[0];
                if (candidateCommand.substring(candidateCommand.lastIndexOf("/") + 1) === commandName) {
                    return root.iconSource(candidate.icon);
                }
            }
        }
        return root.iconSource("");
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.refresh();
        }
    }

    Component.onCompleted: root.refresh()
}
