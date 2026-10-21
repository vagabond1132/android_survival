/**
 * @file ImageFetcherService.h
 * @brief 运行时图片获取 + 本地缓存 (2026-09-19)
 *
 * 设计:
 *  - JSON 存 photoSources (历史遗留: 曾是 Wikimedia 检索词; 现仅用作"期望图片数"提示)
 *  - 打开详情页时 QML 调 fetchImages(id, kingdom, sources)
 *  - 先查本地缓存; 未命中 → 从自建 CDN 直连下载:
 *      https://cdn.outdoor-survival.com/species/<kingdom>/<id>/<n>.jpg  (n=1,2,...)
 *    顺序探测, 首个缺失/失败即停止 (无 gap 填充), 上限 kMaxImagesPerSpecies.
 *  - 2026-10-16: 图源从 commons.wikimedia.org 切到自建 CDN. 根因: Wikimedia 在简中
 *      网络被墙, 实时检索请求永久挂起 → 图册永远"正在加载". 自建 CDN 已列入
 *      network_security_config 允许域名, 且契合 App 离线定位 (下过一次即缓存).
 *  - 缓存到 QStandardPaths::CacheLocation/species_images/<kingdom>/<id>/<nn>.jpg
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
        QStringList sources;     // 历史字段, 仅用于推断"期望图片数"上限提示
        QStringList cachePaths;  // 已有缓存 (跳过)
        int nextImgIdx = 1;      // 下一个要探测的 CDN 图片序号 (1-based)
        int maxImages = 0;       // 本次探测上限 (min(kMaxImagesPerSpecies, sources.size()...))
        int filledCount = 0;     // 已发出的 imageReady 数 (含缓存)
    };

    QString cacheRoot_() const;
    QString cacheDirFor_(const QString& kingdom, const QString& id) const;
    QString localPathFor_(const QString& kingdom, const QString& id, int n) const;
    /// 自建 CDN 上某物种第 n 张图 (1-based) 的 URL
    QString cdnUrlFor_(const QString& kingdom, const QString& id, int n) const;

    /// 走完缓存预填充, 然后启动第一张 CDN 图探测
    void startTask_(Task t);

    /// 直连下载 CDN 上第 nextImgIdx 张图; 成功则保存并继续下一张, 失败/缺失则收尾
    void kickImage_(Task task);

private slots:
    void onReplyFinished_();

private:
    QNetworkAccessManager* m_nam = nullptr;
    QHash<QNetworkReply*, Task> m_inflight;
    QHash<QString, Task> m_idIndex;  // id → 当前 task, 用于 download 阶段匹配
};

} // namespace outdoor