#pragma once
#include "window_capture_probe.h"
#include <QHash>
#include <QSet>

// Own sessions independently of QML delegates. Multiple popup consumers share
// one capture for a window; removing the last consumer releases it immediately.
class WindowPreviewManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool supported READ supported NOTIFY statusChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY statusChanged)
    Q_PROPERTY(QString error READ error NOTIFY statusChanged)
    Q_PROPERTY(int captureCount READ captureCount NOTIFY capturesChanged)
  public:
    explicit WindowPreviewManager(QObject *parent = nullptr);
    ~WindowPreviewManager() override;
    bool supported() const;
    bool ready() const { return m_catalog.ready(); }
    QString error() const { return m_catalog.error(); }
    int captureCount() const { return m_captures.size(); }
    Q_INVOKABLE void open(const QString &displayName);
    Q_INVOKABLE void close();
    Q_INVOKABLE void setTargets(const QString &consumer, const QStringList &identifiers);
    Q_INVOKABLE void release(const QString &consumer);
    Q_INVOKABLE WindowCaptureProbe *captureFor(const QString &identifier) const;
  signals:
    void statusChanged();
    void capturesChanged();

  private:
    void reconcile();
    void clearCaptures();
    WindowCaptureProbe m_catalog;
    QString m_display;
    bool m_open = false;
    bool m_reconciling = false;
    QHash<QString, QStringList> m_targets;
    QHash<QString, WindowCaptureProbe *> m_captures;
};
