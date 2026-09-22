#pragma once
#include "window_capture_probe.h"
#include <QPointer>
#include <QQuickPaintedItem>

class CaptureImage : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(WindowCaptureProbe *capture READ capture WRITE setCapture NOTIFY captureChanged)
  public:
    explicit CaptureImage(QQuickItem *parent = nullptr);
    WindowCaptureProbe *capture() const { return m_capture; }
    void setCapture(WindowCaptureProbe *capture);
    void paint(QPainter *painter) override;
  signals:
    void captureChanged();

  private:
    QPointer<WindowCaptureProbe> m_capture;
    QImage m_image;
};
