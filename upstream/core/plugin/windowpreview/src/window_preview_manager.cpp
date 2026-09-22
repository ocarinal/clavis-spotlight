#include "window_preview_manager.h"
#include <QScopedValueRollback>
#include <QTimer>
#include <memory>

WindowPreviewManager::WindowPreviewManager(QObject *parent) : QObject(parent)
{
    connect(&m_catalog, &WindowCaptureProbe::changed, this, [this] {
        reconcile();
        emit statusChanged();
    });
    connect(&m_catalog, &WindowCaptureProbe::windowsChanged, this, &WindowPreviewManager::reconcile);
}
WindowPreviewManager::~WindowPreviewManager()
{
    disconnect(&m_catalog, nullptr, this, nullptr);
    close();
}
bool WindowPreviewManager::supported() const { return m_open && m_catalog.ready() && m_catalog.supported(); }
void WindowPreviewManager::open(const QString &displayName)
{
    close();
    m_display = displayName;
    m_open = true;
    m_catalog.open(displayName);
}
void WindowPreviewManager::close()
{
    m_open = false;
    clearCaptures();
    m_catalog.close();
}
void WindowPreviewManager::setTargets(const QString &consumer, const QStringList &identifiers)
{
    if (consumer.isEmpty())
        return;
    if (identifiers.isEmpty())
        m_targets.remove(consumer);
    else
        m_targets.insert(consumer, identifiers);
    reconcile();
}
void WindowPreviewManager::release(const QString &consumer)
{
    m_targets.remove(consumer);
    reconcile();
}
WindowCaptureProbe *WindowPreviewManager::captureFor(const QString &identifier) const
{
    return m_captures.value(identifier, nullptr);
}
void WindowPreviewManager::clearCaptures()
{
    if (m_captures.isEmpty())
        return;
    const auto previous = m_captures;
    m_captures.clear();
    for (auto *capture : previous) {
        disconnect(capture, nullptr, this, nullptr);
        capture->close();
        capture->deleteLater();
    }
    emit capturesChanged();
}
void WindowPreviewManager::reconcile()
{
    if (m_reconciling)
        return;
    QScopedValueRollback guard(m_reconciling, true);
    if (!supported()) {
        clearCaptures();
        return;
    }
    QSet<QString> available, wanted;
    for (const auto &window : m_catalog.windows())
        available.insert(window.toMap().value("identifier").toString());
    for (const auto &identifiers : m_targets)
        for (const auto &id : identifiers)
            if (available.contains(id))
                wanted.insert(id);
    bool changed = false;
    for (const auto &id : m_captures.keys()) {
        if (wanted.contains(id))
            continue;
        auto *capture = m_captures.take(id);
        disconnect(capture, nullptr, this, nullptr);
        capture->close();
        capture->deleteLater();
        changed = true;
    }
    for (const auto &id : wanted) {
        if (m_captures.contains(id))
            continue;
        auto *capture = new WindowCaptureProbe(this);
        capture->setMaximumDimension(512);
        capture->setFrameInterval(66);
        m_captures.insert(id, capture);
        // The registry handshake is asynchronous. Latch before starting because
        // start() emits changed itself; errors wait for a new hover request.
        auto started = std::make_shared<bool>(false);
        connect(capture, &WindowCaptureProbe::changed, this, [this, capture, id, started] {
            if (*started || !capture->ready() || !capture->supported() || m_captures.value(id) != capture)
                return;
            *started = true;
            QTimer::singleShot(0, capture, [this, capture, id] {
                if (m_captures.value(id) == capture)
                    capture->start(id);
            });
        });
        capture->open(m_display);
        changed = true;
    }
    if (changed)
        emit capturesChanged();
}
