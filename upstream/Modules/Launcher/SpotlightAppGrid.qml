pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets.common

GridView {
    id: root

    required property SpotlightStyle style
    required property var results
    required property int selectedIndex
    property bool searchActive: false
    property real revealProgress: 1
    property real populationProgress: 0
    property int previousResultCount: 0
    // A long press opens a reorder window: dragging a tile then arranges the
    // launcher instead of handing the app off to the Dock, and the slot under
    // the pointer marks where the tile will land.
    property bool reorderMode: false
    property int dragIndex: -1
    property int dropIndex: -1
    // The gesture is carried by ids so a provider refresh mid-drag cannot
    // retarget it at whatever ends up sitting at the old index.
    property string dragId: ""
    property string dropId: ""
    readonly property bool reordering: reorderMode || dragIndex >= 0
    readonly property int columns: Math.max(1, Math.floor(width / style.appGridCellWidth))

    signal selectionRequested(int index)
    signal activationRequested(int index)
    signal contextRequested(int index, var sourceItem)
    signal reorderRequested(string fromId, string toId)

    model: root.results
    currentIndex: root.selectedIndex
    cellWidth: Math.min(width, root.style.appGridCellWidth)
    cellHeight: root.style.appGridCellHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: false
    interactive: !DockService.externalDragActive
    // A nonvisual highlight lets the view animate scrolling to the current
    // item, including retargeting while an earlier movement is still running.
    highlight: Item {}
    highlightMoveDuration: root.style.resultScrollDuration

    ScrollBar.vertical: StyledScrollBar {}

    function revealPopulation() {
        populationAnimation.stop();
        populationProgress = 0;
        populationAnimation.restart();
    }

    function armReorder(index) {
        if (root.searchActive || index < 0 || index >= root.count)
            return;
        root.reorderMode = true;
        root.dropIndex = index;
    }

    function disarmReorder() {
        if (root.dragIndex >= 0)
            return;
        root.reorderMode = false;
        root.dropIndex = -1;
    }

    function idAt(index) {
        const entry = root.results ? root.results[index] : null;
        return entry ? String(entry.id) : "";
    }

    function beginReorder(index) {
        if (index < 0 || index >= root.count)
            return;
        root.dragIndex = index;
        root.dropIndex = index;
        root.dragId = root.idAt(index);
        root.dropId = root.dragId;
    }

    function clearReorder() {
        root.reorderMode = false;
        root.dragIndex = -1;
        root.dropIndex = -1;
        root.dragId = "";
        root.dropId = "";
    }

    function indexAt(sceneX, sceneY) {
        const local = root.mapFromItem(null, sceneX, sceneY);
        const column = Math.max(0, Math.min(root.columns - 1, Math.floor(local.x / root.cellWidth)));
        const row = Math.max(0, Math.floor((local.y + root.contentY) / root.cellHeight));
        return Math.max(0, Math.min(root.count - 1, row * root.columns + column));
    }

    function updateReorder(sceneX, sceneY) {
        if (root.dragIndex < 0)
            return;
        root.dropIndex = root.indexAt(sceneX, sceneY);
        root.dropId = root.idAt(root.dropIndex);
    }

    function finishReorder() {
        const fromId = root.dragId;
        const toId = root.dropId;
        const dragging = root.dragIndex >= 0;
        root.clearReorder();
        if (!dragging || fromId === "" || toId === "" || fromId === toId)
            return;
        root.reorderRequested(fromId, toId);
    }

    onResultsChanged: {
        const count = root.results ? root.results.length : 0;
        if (root.visible && count > 0 && root.previousResultCount === 0)
            root.revealPopulation();
        root.previousResultCount = count;
    }
    onVisibleChanged: {
        if (visible && root.results && root.results.length > 0)
            root.revealPopulation();
        else if (!visible)
            root.clearReorder();
    }
    Component.onCompleted: {
        root.previousResultCount = root.results ? root.results.length : 0;
        if (root.previousResultCount > 0)
            root.revealPopulation();
    }

    NumberAnimation {
        id: populationAnimation

        target: root
        property: "populationProgress"
        from: 0
        to: 1
        duration: root.style.panelRevealDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.style.effectsCurve
    }

    delegate: Item {
        id: tile

        required property int index
        required property var modelData
        readonly property bool selected: tile.index === root.selectedIndex
        readonly property bool hiddenApp: !!tile.modelData && UiPreferences.isSpotlightAppHidden(
                                              tile.modelData.id)
        readonly property bool dropTarget: root.dragIndex >= 0 && root.dropIndex === tile.index
        readonly property bool lifted: root.dragIndex === tile.index
        readonly property int gridRow: Math.floor(tile.index / Math.max(1, root.columns))
        readonly property int gridColumn: tile.index % Math.max(1, root.columns)
        readonly property real revealDelay: Math.min(0.34, gridRow * 0.055 + gridColumn * 0.014)
        readonly property real reveal: root.style.smoothstep((Math.min(root.revealProgress,
                                                                       root.populationProgress)
                                                              - revealDelay) / Math.max(0.01, 1
                                                                                        - revealDelay))
        width: root.cellWidth
        height: root.cellHeight
        opacity: reveal * (tile.hiddenApp ? 0.55 : 1) * (tile.lifted ? 0.4 : 1)
        scale: 0.90 + 0.10 * reveal
        transformOrigin: Item.Center
        transform: Translate {
            y: 14 * (1 - tile.reveal)
        }

        Accessible.description: tile.modelData.subtitle || ""
        Accessible.name: tile.modelData.title
        Accessible.role: Accessible.ListItem
        Accessible.selected: tile.selected
        Accessible.onPressAction: root.activationRequested(tile.index)

        Rectangle {
            id: tileSurface

            anchors.fill: parent
            anchors.margins: root.style.appGridGap / 2
            radius: Appearance.rounding.large
            color: tile.dropTarget ? Appearance.applyAlpha(Appearance.colors.colPrimary, 0.16) : root.searchActive
                                     && tile.selected ? root.style.selectedColor : tileHover.hovered
                                                        ? root.style.hoverColor : "transparent"
            border.width: tile.dropTarget ? 2 : tileHover.hovered || root.searchActive && tile.selected ? 1 :
                                                                                                          0
            border.color: tile.dropTarget ? Appearance.colors.colPrimary : root.style.appGridTileBorderColor
            scale: tileTap.pressed ? root.style.appGridPressedScale : tileHover.hovered ? 1.025 : 1

            Behavior on color {
                ColorAnimation {
                    duration: 150
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.style.effectsCurve
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: root.style.panelDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.style.effectsCurve
                }
            }

            Behavior on border.width {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.style.effectsCurve
                }
            }

            ThemeIcon {
                id: appIcon

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 12
                width: root.style.appGridIconSize
                height: width
                visible: !tile.modelData.symbol
                iconSource: visible ? ApplicationService.iconSource(tile.modelData.icon) : ""
                sourceSize.width: root.style.appGridIconSize * 2
                sourceSize.height: root.style.appGridIconSize * 2
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                scale: tileHover.hovered || tile.selected ? root.style.appGridHoverScale : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: root.style.panelDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.style.effectsCurve
                    }
                }
            }

            Item {
                id: appSymbol
                anchors.centerIn: appIcon
                width: root.style.appGridIconSize
                height: width
                visible: !!tile.modelData.symbol
                scale: appIcon.scale
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: tile.modelData.symbol || ""
                    iconSize: root.style.appGridIconSize
                    color: root.searchActive && tile.selected ? root.style.selectedContentColor :
                                                                tile.modelData.appObject?.dragOnly
                                                                ? Appearance.colors.colOnSurfaceVariant :
                                                                  Appearance.colors.colPrimary
                    transform: Scale {
                        origin.x: appSymbol.width / 2
                        xScale: tile.modelData.appObject?.id === ApplicationService.smallSpaceApplication.id
                                ? 0.5 : 1
                    }
                }
            }

            Text {
                id: appName

                anchors.top: appIcon.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: root.style.appGridLabelHeight
                text: tile.modelData.title
                textFormat: Text.PlainText
                font.family: Fonts.ui
                font.pixelSize: root.style.appGridLabelFontSize
                font.weight: Font.Medium
                color: root.searchActive && tile.selected ? root.style.selectedContentColor :
                                                            Appearance.colors.colOnSurface
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
            }

            MaterialSymbol {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                visible: tile.hiddenApp
                text: "visibility_off"
                iconSize: 18
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        HoverHandler {
            id: tileHover

            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered)
                    root.selectionRequested(tile.index);
            }
        }

        TapHandler {
            id: tileTap

            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.DragThreshold
            longPressThreshold: 0.45
            onPressedChanged: {
                if (pressed)
                    appDrag.resetGesture();
                else
                    Qt.callLater(root.disarmReorder);
            }
            onLongPressed: {
                if (appDrag.dragged)
                    return;
                root.armReorder(tile.index);
            }
            onTapped: {
                if (appDrag.dragged || root.reordering)
                    return;
                root.selectionRequested(tile.index);
                root.activationRequested(tile.index);
            }
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            gesturePolicy: TapHandler.DragThreshold
            onTapped: {
                root.selectionRequested(tile.index);
                root.contextRequested(tile.index, tile);
            }
        }

        SpotlightAppDrag {
            id: appDrag

            desktopId: tile.modelData.appObject ? String(tile.modelData.appObject.id) : ""
            iconItem: tile.modelData.symbol ? appSymbol : appIcon
            reorderArmed: root.reorderMode
            onReorderStarted: root.beginReorder(tile.index)
            onReorderMoved: (sceneX, sceneY) => root.updateReorder(sceneX, sceneY)
            onReorderFinished: root.finishReorder()
        }

        ToolTip.visible: tileHover.hovered && (appName.truncated || !!tile.modelData.appObject?.dragOnly) &&
                         !DockService.externalDragActive
        ToolTip.delay: 600
        ToolTip.text: tile.modelData.appObject?.dragOnly ? tile.modelData.subtitle : tile.modelData.title
    }
}
