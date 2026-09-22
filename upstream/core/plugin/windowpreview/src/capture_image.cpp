#include "capture_image.h"
#include <QPainter>

CaptureImage::CaptureImage(QQuickItem *parent) : QQuickPaintedItem(parent) {}
void CaptureImage::setCapture(WindowCaptureProbe *capture)
{
    if (m_capture == capture)
        return;
    if (m_capture)
        disconnect(m_capture, nullptr, this, nullptr);
    m_capture = capture;
    m_image = capture ? capture->image() : QImage();
    if (capture) {
        connect(capture, &WindowCaptureProbe::imageChanged, this, [this] {
            m_image = m_capture ? m_capture->image() : QImage();
            update();
        });
        connect(capture, &QObject::destroyed, this, [this] {
            m_image = {};
            update();
            emit captureChanged();
        });
    }
    update();
    emit captureChanged();
}
void CaptureImage::paint(QPainter *painter)
{
    if (m_image.isNull())
        return;
    const auto size = m_image.size().scaled(boundingRect().size().toSize(), Qt::KeepAspectRatio);
    const QRectF target((width() - size.width()) / 2, (height() - size.height()) / 2, size.width(),
                        size.height());
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(target, m_image);
}
