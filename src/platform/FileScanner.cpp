/**
 * @file FileScanner.cpp
 */

#include "FileScanner.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QFileInfoList>
#include <QSet>
#include <QStorageInfo>
#include <QStandardPaths>
#include <QVector>

#include <algorithm>

namespace outdoor {

namespace {

struct WalkItem {
    QString path;
    int depth;
};

QString suffixOf(const QString& fileName)
{
    const int dot = fileName.lastIndexOf(QLatin1Char('.'));
    if (dot <= 0 || dot == fileName.size() - 1)
        return QString();
    return fileName.mid(dot + 1).toLower();
}

// 遍历时要整枝剪掉的目录: 进去只会吃掉条目配额, 不会有人把轨迹存那儿.
// "Android" 只在"不是本次根目录本身"时剪 —— 微信下载目录是调用方直接递给它的,
// 剪掉的是从卷根往下钻时顺路撞上的 Android/data/* 那几千个包目录.
bool pruneDir(const QString& absolutePath, const QString& rootPath)
{
    if (absolutePath == rootPath)
        return false;
    const QString name = QFileInfo(absolutePath).fileName();
    if (name.startsWith(QLatin1Char('.')))
        return true;
    static const QSet<QString> kSkip = {
       QStringLiteral("Android"), QStringLiteral("MIUI"), QStringLiteral("lost+found"),
        QStringLiteral("cache"), QStringLiteral("notifications"), QStringLiteral("ringtone"),
        QStringLiteral("ringtones"), QStringLiteral("alarms"), QStringLiteral("podcasts"),
        QStringLiteral("wmnewsapp"), QStringLiteral("DCIM")
    };
    return kSkip.contains(name);
}

} // namespace

QStringList FileScanner::trackSuffixes()
{
    // 与 MapService 的导入实现对齐: 只列真能导进来的.
    return {QStringLiteral("gpx"), QStringLiteral("kml"), QStringLiteral("csv")};
}

QStringList FileScanner::defaultAndroidRoots()
{
    QStringList roots;
    roots << QStringLiteral("/storage/emulated/0");

    for (const QStorageInfo& vol : QStorageInfo::mountedVolumes()) {
        const QString p = vol.rootPath();
        if (!p.startsWith(QStringLiteral("/storage/")) || p == QStringLiteral("/"))
            continue;
        if (!vol.isValid() || !vol.isReady())
            continue;
        roots << p;
    }

    // 微信各版本 / 各 ROM 的落盘位置 (用户说的"微信目录中的路径"就在这几条里).
    roots << QStringLiteral("/storage/emulated/0/Android/data/com.tencent.mm/MicroMsg/Download")
          << QStringLiteral("/storage/emulated/0/Android/media/com.tencent.mm/MicroMsg/Download")
          << QStringLiteral("/storage/emulated/0/tencent/MicroMsg/Download")
          << QStringLiteral("/storage/emulated/0/Download")
          << QStringLiteral("/storage/emulated/0/Documents");

    const QString appDownload = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!appDownload.isEmpty())
        roots << appDownload;

    // 同一目录可能有多个别名 (/sdcard 与 /storage/emulated/0); 按 canonical 去重.
    QStringList unique;
    QStringList seen;
    for (const QString& raw : roots) {
        const QFileInfo info(raw);
        QString canonical = info.canonicalFilePath();
        if (canonical.isEmpty())
            canonical = info.absoluteFilePath();
        if (canonical.isEmpty() || seen.contains(canonical))
            continue;
        seen << canonical;
        unique << canonical;
    }
    return unique;
}

QVariantList FileScanner::search(const QStringList& roots,
                                 const QString& keyword,
                                 const QStringList& suffixes,
                                 QVariantList* diagnostics,
                                 const Options& options)
{
    QVariantList hits;
    QStringList lowerSuffixes;
    for (const QString& s : suffixes) {
        QString one = s.toLower();
        while (one.startsWith(QLatin1Char('.')))
            one.remove(0, 1);
        if (!one.isEmpty())
            lowerSuffixes << one;
    }

    int budget = options.maxEntries;
    for (const QString& rawRoot : roots) {
        if (budget <= 0)
            break;
        const qint64 t0 = QDateTime::currentMSecsSinceEpoch();
        QFileInfo rootInfo(rawRoot);
        QVariantMap diag;
        diag.insert(QStringLiteral("root"), rawRoot);
        diag.insert(QStringLiteral("exists"), rootInfo.exists());
        diag.insert(QStringLiteral("isDir"), rootInfo.isDir());
        diag.insert(QStringLiteral("readable"), rootInfo.isReadable());
        int scanned = 0;
        int rootHits = 0;

        if (rootInfo.exists() && rootInfo.isDir()) {
            // 显式栈遍历, 不用 QDirIterator::Subdirectories:
            // 那样没法在"进错目录"时整枝剪掉, 也拿不到 depth.
            QVector<WalkItem> stack{{rawRoot, 0}};
            while (!stack.isEmpty() && budget > 0) {
                const WalkItem item = stack.takeLast();
                QDir dir(item.path);
                const QFileInfoList entries = dir.entryInfoList(
                    QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
                scanned += entries.size();
                budget -= entries.size();
                if (budget < 0)
                    budget = 0;
                for (const QFileInfo& fi : entries) {
                    if (fi.isDir()) {
                        if (item.depth + 1 >= options.maxDepth)
                            continue;
                        if (pruneDir(fi.absoluteFilePath(), rawRoot))
                            continue;
                        stack.append({fi.absoluteFilePath(), item.depth + 1});
                        continue;
                    }
                    const QString name = fi.fileName();
                    if (!lowerSuffixes.contains(suffixOf(name)))
                        continue;
                    if (!keyword.isEmpty() && !name.contains(keyword, Qt::CaseInsensitive))
                        continue;
                    if (!fi.isReadable())
                        continue;
                    QVariantMap hit;
                    hit.insert(QStringLiteral("path"), fi.absoluteFilePath());
                    hit.insert(QStringLiteral("name"), name);
                    hit.insert(QStringLiteral("dir"), fi.absolutePath());
                    hit.insert(QStringLiteral("suffix"), suffixOf(name));
                    hit.insert(QStringLiteral("sizeBytes"), fi.size());
                    hit.insert(QStringLiteral("mtimeMs"),
                               fi.lastModified().toMSecsSinceEpoch());
                    hit.insert(QStringLiteral("root"), rawRoot);
                    hits.append(hit);
                    ++rootHits;
                    ++scanned;
                }
            }
        }

        diag.insert(QStringLiteral("scanned"), scanned);
        diag.insert(QStringLiteral("hits"), rootHits);
        diag.insert(QStringLiteral("elapsedMs"), QDateTime::currentMSecsSinceEpoch() - t0);
        if (diagnostics)
            diagnostics->append(diag);
    }

    std::sort(hits.begin(), hits.end(), [](const QVariant& a, const QVariant& b) {
        const QVariantMap ma = a.toMap();
        const QVariantMap mb = b.toMap();
        return ma.value(QStringLiteral("mtimeMs")).toLongLong()
             > mb.value(QStringLiteral("mtimeMs")).toLongLong();
    });
    if (hits.size() > options.maxHits)
        hits = hits.mid(0, options.maxHits);
    return hits;
}

} // namespace outdoor
