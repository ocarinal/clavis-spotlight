import QtQuick
import qs.Services

Item {
    id: root

    required property string desktopId
    readonly property string dockKind: desktopId === ApplicationService.smallSpaceApplication.id
                                       ? "small-spacer" : desktopId
                                         === ApplicationService.spaceApplication.id ? "spacer" : "app"
    required property Item iconItem
    property bool dragged: false
    property bool preparing: false
    property bool nativeDragActive: false
    property bool holdsDrag: false
    // Set while a long press has lifted this tile for hand-arranging: the same
    // drag gesture then reorders the launcher instead of handing off to the
    // Dock.
    property bool reorderArmed: false
    property bool reorderActive: false
    property var capturedImage: null
    property QtObject dockHandoffTarget: null
    property int dockHandoffSerial: 0

    signal reorderStarted
    signal reorderMoved(real sceneX, real sceneY)
    signal reorderFinished

    function registerDockHandoff(target, serial) {
        dockHandoffTarget = target;
        dockHandoffSerial = serial;
    }

    anchors.fill: parent
    enabled: desktopId !== "" && DockService.enabled

    function resetGesture() {
        dragged = false;
    }

    function finish() {
        preparing = false;
        nativeDragActive = false;
        // A provider refresh can destroy this delegate. Release the source only
        // after Qt's platform drag has returned from its nested event loop.
        Qt.callLater(root.releaseDrag);
    }

    function releaseDrag() {
        // Reveal the Dock entry only after QDrag has returned.
        // Its model refresh may destroy this source as soon as we release it.
        if (dockHandoffTarget) {
            dockHandoffTarget.finishExternalHandoff(dockHandoffSerial);
            dockHandoffTarget = null;
        }
        capturedImage = null;
        holdsDrag = false;
        DockService.externalDragActive = false;
    }

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: ({
                        "application/x-clavis-dock": JSON.stringify({
                                                                        schemaVersion: 1,
                                                                        kind: root.dockKind,
                                                                        desktopId: root.desktopId
                                                                    })
                    })
    Drag.hotSpot.x: root.iconItem.width / 2
    Drag.hotSpot.y: root.iconItem.height / 2
    Drag.onDragStarted: root.nativeDragActive = true
    Drag.onDragFinished: root.finish()

    DragHandler {
        id: gesture

        target: null
        acceptedButtons: Qt.LeftButton
        onActiveChanged: {
            if (active) {
                if (root.reorderArmed) {
                    root.reorderActive = true;
                    root.dragged = true;
                    root.reorderStarted();
                    return;
                }
                root.dragged = true;
                root.preparing = true;
                root.holdsDrag = true;
                DockService.externalDragActive = true;
                const captured = root.iconItem.grabToImage(result => {
                    if (!gesture.active || !root.preparing)
                        return;
                    root.preparing = false;
                    root.capturedImage = result;
                    root.Drag.imageSource = result.url;
                    root.Drag.active = true;
                });
                if (!captured)
                    root.finish();
            } else if (root.reorderActive) {
                root.reorderActive = false;
                root.dragged = false;
                root.reorderFinished();
            } else if (!root.nativeDragActive) {
                root.preparing = false;
                root.Drag.active = false;
                root.finish();
            }
        }
        onActiveTranslationChanged: {
            if (!root.reorderActive)
                return;
            const centre = root.mapToItem(null, root.width / 2 + gesture.activeTranslation.x, root.height / 2
                                          + gesture.activeTranslation.y);
            root.reorderMoved(centre.x, centre.y);
        }
    }

    Component.onDestruction: {
        if (root.dockHandoffTarget)
            root.dockHandoffTarget.cancelExternalHandoff(root.dockHandoffSerial);
        if (root.holdsDrag)
            DockService.externalDragActive = false;
    }
}
