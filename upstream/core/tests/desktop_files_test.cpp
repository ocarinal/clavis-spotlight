#include "desktop_files.h"
#include "file_metadata.h"
#include "folder_sort_model.h"
#include <QFile>
#include <QFileInfo>
#include <QQmlComponent>
#include <QSignalSpy>
#include <QStandardItemModel>
#include <QTemporaryDir>
#include <QTest>

class DesktopFilesTest : public QObject {
    Q_OBJECT
  private slots:
    void referencesPreserveNamesAndSymlinks()
    {
        QTemporaryDir dir;
        const QString name = dir.filePath(QStringLiteral("中文 # 100%.txt"));
        QFile file(name);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("target");
        file.close();
        const auto url = QUrl::fromLocalFile(name);
        const auto info = FileMetadata::read(url);
        QCOMPARE(QUrl(info.value("url").toString()).toLocalFile(), name);
        QVERIFY(info.value("available").toBool());
        const auto link = dir.filePath("link.txt");
        QVERIFY(QFile::link(name, link));
        QCOMPARE(FileMetadata::localUrl(QUrl::fromLocalFile(link)).toLocalFile(), link);
        QVERIFY(FileMetadata::read(QUrl::fromLocalFile(link)).value("isLink").toBool());
        QVERIFY(FileMetadata::localUrl(QUrl("https://example.com/file")).isEmpty());
        QVERIFY(FileMetadata::localUrl(QUrl("file://server/share/file")).isEmpty());
        QVERIFY(FileMetadata::localUrl(QUrl("file:///tmp/file?query")).isEmpty());
        QVERIFY(FileMetadata::localUrl(QUrl("file:///tmp/a%00b")).isEmpty());
        const auto missing = FileMetadata::read(QUrl::fromLocalFile(dir.filePath("unmounted")));
        QVERIFY(!missing.value("available").toBool());
        QVERIFY(!missing.value("url").toString().isEmpty());
    }
    void nativeSortAndUpdates()
    {
        QTemporaryDir dir;
        QStandardItemModel source;
        source.setItemRoleNames({{Qt::UserRole, "fileUrl"}});
        for (const auto &name : {"file10.txt", "file2.txt", "image.png"}) {
            QFile file(dir.filePath(name));
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(name);
            file.close();
            auto *item = new QStandardItem;
            item->setData(QUrl::fromLocalFile(file.fileName()), Qt::UserRole);
            source.appendRow(item);
        }
        FolderSortModel model;
        model.setSourceModel(&source);
        QCOMPARE(model.rowCount(), 3);
        QCOMPARE(model.get(0).value("name").toString(), "file2.txt");
        QCOMPARE(model.get(1).value("name").toString(), "file10.txt");
        model.setOrder("size");
        QCOMPARE(model.get(0).value("name").toString(), "file10.txt");
        model.setOrder("kind");
        const auto firstType = model.get(0).value("mimeType").toString();
        QVERIFY(!firstType.isEmpty());
        source.removeRow(0);
        QCOMPARE(model.rowCount(), 2);
        model.setOrder("created");
        QCOMPARE(model.get(-1), QVariantMap{});
        QCOMPARE(model.get(2), QVariantMap{});
    }
    void trashFailureNeverDeletesOtherFiles()
    {
        QTemporaryDir dir;
        QFile target(dir.filePath("keep.txt"));
        QVERIFY(target.open(QIODevice::WriteOnly));
        target.write("keep");
        target.close();
        DesktopFiles files;
        QSignalSpy results(&files, &DesktopFiles::finished);
        QVERIFY(!files.moveToTrash({QUrl("https://example.com/file")}));
        QVERIFY(files.moveToTrash({QUrl::fromLocalFile(dir.filePath("missing"))}));
        QVERIFY(results.wait(5000));
        QCOMPARE(results.at(0).at(1).toInt(), 0);
        QVERIFY(!results.at(0).at(2).toStringList().isEmpty());
        QVERIFY(QFileInfo::exists(target.fileName()));
        QVERIFY(!files.canOpenWith("org.clavis.Settings"));
        QVERIFY(!files.openWith("org.clavis.Settings", {QUrl::fromLocalFile(target.fileName())}));
    }
    void liveDirectoryRefreshKeepsOneRowPerFile()
    {
        QTemporaryDir dir;
        QFile first(dir.filePath("first.txt"));
        QVERIFY(first.open(QIODevice::WriteOnly));
        first.close();
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import Qt.labs.folderlistmodel\nFolderListModel { "
                          "showDotAndDotDot: false; sortField: FolderListModel.Unsorted }",
                          QUrl());
        QScopedPointer<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        auto *source = qobject_cast<QAbstractItemModel *>(object.data());
        QVERIFY(source);
        object->setProperty("folder", QUrl::fromLocalFile(dir.path()));
        FolderSortModel model;
        model.setSourceModel(source);
        // Views read rows from change notifications while FolderListModel refreshes.
        connect(&model, &FolderSortModel::countChanged, &model, [&model] {
            for (int row = 0; row < model.rowCount(); ++row)
                model.get(row);
        });
        QTRY_COMPARE(source->rowCount(), 1);
        QTRY_COMPARE(model.rowCount(), 1);
        QFile second(dir.filePath("second.txt"));
        QVERIFY(second.open(QIODevice::WriteOnly));
        second.close();
        QTRY_COMPARE(source->rowCount(), 2);
        QTRY_COMPARE(model.rowCount(), 2);
        QCOMPARE(model.get(0).value("name").toString(), "first.txt");
        QCOMPARE(model.get(1).value("name").toString(), "second.txt");
        QVERIFY(first.remove());
        QTRY_COMPARE(source->rowCount(), 1);
        QTRY_COMPARE(model.rowCount(), 1);
        QCOMPARE(model.get(0).value("name").toString(), "second.txt");
    }
};
QTEST_GUILESS_MAIN(DesktopFilesTest)
#include "desktop_files_test.moc"
