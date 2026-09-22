import QtQuick
import Quickshell
import qs.Services
import "../../Common/functions/SpotlightLocalSearch.js" as LocalSearch

Item {
    id: root

    property string query: ""
    property var results: []
    property int limit: 50
    property string order: UiPreferences.spotlightAppOrder
    // Managing hidden apps is a temporary launcher state: hidden apps stay in
    // the list only while the user asks to see them.
    property bool showHidden: false
    readonly property int hiddenCount: UiPreferences.spotlightHiddenAppIds.length
    onOrderChanged: rebuild()
    onShowHiddenChanged: rebuild()

    function rebuild() {
        if (!active || DockService.externalDragActive)
            return;
        const source = LocalSearch.visibleApps(ApplicationService.launcherApplications,
                                               UiPreferences.spotlightHiddenAppIds, root.showHidden);
        const ordered = LocalSearch.appResults(source, root.query, root.order, SpotlightAppUsage.records, Date.now(),
                                               UiPreferences.spotlightPinnedAppIds,
                                               UiPreferences.spotlightManualAppOrder);
        root.results = root.limit > 0 ? ordered.slice(0, root.limit) : ordered;
    }

    // Hand-arranging is only meaningful on the complete list, so it is refused
    // while a query filters the results or a limit truncates them.
    function reorder(fromId, toId) {
        if (root.query !== "" || root.limit > 0)
            return false;
        const ids = root.results.map(result => String(result.id));
        const from = ids.indexOf(String(fromId));
        const to = ids.indexOf(String(toId));
        if (from < 0 || to < 0 || from === to)
            return false;
        const moved = ids.splice(from, 1)[0];
        ids.splice(to, 0, moved);
        return UiPreferences.setSpotlightManualAppOrder(ids);
    }

    function execute(index) {
        const result = root.results[index];
        if (!result || !result.appObject || result.appObject.dragOnly)
            return false;
        return SpotlightAppUsage.launch(result.id);
    }

    property bool active: true
    onActiveChanged: rebuild()

    onQueryChanged: rebuild()
    onLimitChanged: rebuild()
    Component.onCompleted: rebuild()

    Connections {
        target: DockService
        function onExternalDragActiveChanged() {
            if (!DockService.externalDragActive)
                root.rebuild();
        }
    }

    Connections {
        target: UiPreferences
        function onSpotlightAppOrderChanged() {
            root.rebuild();
        }
        function onSpotlightPinnedAppIdsChanged() {
            root.rebuild();
        }
        function onSpotlightHiddenAppIdsChanged() {
            if (root.hiddenCount === 0)
                root.showHidden = false;
            root.rebuild();
        }
        function onSpotlightManualAppOrderChanged() {
            root.rebuild();
        }
    }
    Connections {
        target: SpotlightAppUsage
        function onReadyChanged() {
            if (SpotlightAppUsage.ready)
                root.rebuild();
        }
    }

    Connections {
        target: ApplicationService

        function onLauncherApplicationsChanged() {
            root.rebuild();
        }
    }
}
