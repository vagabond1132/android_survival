/**
 * @file ImageFetcherService.h
 * @brief 运行时图片获取 + 本地缓存 (2026-09-19)
 *
 * 设计:
 *  - JSON 存 photoSources (检索词列表, 非 URL)
 *  - 打开详情页时 QML 调 fetchImages(id, kingdom, sources)
 *  - 先查本地缓存; 未命中 → Wikimedia Commons API 搜 → 下首张缩略图
 *  - 缓存到 QStandardPaths::CacheLocation/species_images/<kingdom>/<id>/<n>.jpg
 *  - 通过 imageReady(id, index, localPath) / imagesAllReady(id, paths) 信号回报
 *  - 第二次打开秒开 (直接读缓存)
 *
 * 不依赖 Database (无业务数据, 纯 IO + 网络)
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QPointer>

class QNetworkAccessManager;
class QNetworkReply;

namespace outdoor {

class ImageFetcherService : public QObject {
    Q_OBJECT
public:
    explicit ImageFetcherService(QObject* parent = nullptr);
    ~ImageFetcherService() override;

    /// 已缓存的本地路径列表 (空 = 无缓存)
    Q_INVOKABLE QStringList cachedImages(const QString& id, const QString& kingdom) const;

    /// 异步取图. sources 是检索词列表 (按序尝试, 首个匹配即下).
    /// 立即返回, 结果通过信号回报.
    Q_INVOKABLE void fetchImages(const QString& id,
                                 const QString& kingdom,
                                 const QStringList& sources);

    /// 清缓存. id 空 = 清全部
    Q_INVOKABLE void clearCache(const QString& id = QString(),
                                const QString& kingdom = QString());

    /// 缓存根目录 (供调试/展示)
    Q_INVOKABLE QString cacheRootPath() const;

signals:
    /// 单张图就绪 (id 匹配 + 给出在缓存数组中的 index 0-based + 绝对路径)
    void imageReady(const QString& id, int index, const QString& localPath);

    /// 一批图全部尝试完毕 (paths 含实际缓存的, 可能 < sources 数)
    void imagesAllReady(const QString& id, const QStringList& localPaths);

    /// 全部 sources 都失败 (id, 人类可读原因)
    void imageFailed(const QString& id, const QString& reason);

private:
    struct Task {
        QString id;
        QString kingdom;
        QStringList sources;
        QStringList cachePaths;  // 已有缓存 (跳过)
        int nextSourceIdx = 0;   // 下次要试的 source
        int filledCount = 0;     // 已发出的 imageReady 数 (含缓存)
        enum class Phase { Search, Download } phase = Phase::Search;
        QString currentTitle;    // 当前在解析的 File: 标题
    };

    QString cacheRoot_() const;
    QString cacheDirFor_(const QString& kingdom, const QString& id) const;
    QString localPathFor_(const QString& kingdom, const QString& id, int n) const;

    /// 走完缓存预填充, 然后启动第一个 source 的 search
    void startTask_(Task t);

    /// Wikimedia Commons search API (srnamespace=6 = File)
    void kickSearch_(Task task);

    /// 已知 File 标题, 取 thumburl
    void kickDownload_(Task task, const QString& fileTitle);

    /// API 返回 JSON 解析 (公共, search + imageinfo 共用)
    static QString firstTitleFromSearch_(const QByteArray& body);
    static QString thumbUrlFromImageInfo_(const QByteArray& body);

private slots:
    void onReplyFinished_();

private:
    QNetworkAccessManager* m_nam = nullptr;
    QHash<QNetworkReply*, Task> m_inflight;
    QHash<QString, Task> m_idIndex;  // id → 当前 task, 用于 download 阶段匹配
};

} // namespace outdoor