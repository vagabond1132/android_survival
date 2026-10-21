/**
 * @file ImageFetcherService.cpp
 * @brief ImageFetcherService 实现
 */

#include "ImageFetcherService.h"
#include "Logger.h"

#include <QDebug>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>

namespace outdoor {

// 2026-10-16: 图源从 commons.wikimedia.org (简中被墙, 检索请求永久挂起) 切到自建 CDN.
//   约定: https://cdn.outdoor-survival.com/species/<kingdom>/<id>/<n>.jpg  (n=1,2,...)
//   服务端目录结构由运维按此约定铺图; 客户端顺序探测, 首个缺失即停 (不 gap-fill).
constexpr const char* kCdnBase = "https://cdn.outdoor-survival.com/species";
constexpr const char* kUserAgent = "OutdoorSurvivalApp/1.0 (image-fetcher; Qt)";
constexpr int kMaxImagesPerSpecies = 6;   // 单物种最多探测图片数
constexpr qint64 kMinImageBytes = 1024;   // 小于此字节视为无效 (占位/错误页)

namespace {

// 2026-10-19: 真机定位图册 bug 的根因 — CDN 源站尚未铺图, 对任意路径都回
//   HTTP 200 + text/html 占位页 ("We're getting things ready", 固定 39821 字节).
//   旧逻辑只看状态码 (<400) 和体积 (>1KB), 于是 HTML 被写成 00.jpg, Qt 解码报
//   "Unsupported image format", 且 cachedImages 之后一直把它当有效缓存, 刷新也救不回来.
//   只按文件头魔数判类型, 不引 QtGui — 本文件要进无 GUI 的 host 单测.
bool hasImageMagic(const QByteArray& head) {
    return head.startsWith("\xFF\xD8\xFF")            // JPEG
        || head.startsWith("\x89PNG\r\n\x1A\n")       // PNG
        || head.startsWith("GIF87a") || head.startsWith("GIF89a")
        || (head.startsWith("RIFF") && head.size() >= 12 && head.mid(8, 4) == "WEBP");
}

QByteArray readHead(const QString& path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.read(12) : QByteArray();
}

}  // namespace

ImageFetcherService::ImageFetcherService(QObject* parent)
    : QObject(parent), m_nam(new QNetworkAccessManager(this)) {
    // 2026-10-16: 修 3.jpg 图册永久"正在加载图片…"。根因: commons.wikimedia.org
    //   在简中网络被墙 (SYN 被静默丢弃), QNetworkAccessManager 默认无超时 → 请求
    //   永久挂起 → onReplyFinished_ 永不触发 → _photoLoading 永不清零 → 无限转圈。
    //   设 8s 传输超时, 超时即以错误完成 → 走失败分支 → 触发 imageFailed/imagesAllReady
    //   → UI 落到"暂无图片"+刷新按钮, 不再假死。
    m_nam->setTransferTimeout(8000);
}

ImageFetcherService::~ImageFetcherService() = default;

QString ImageFetcherService::cacheRoot_() const {
    const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    return base + "/species_images";
}

QString ImageFetcherService::cacheDirFor_(const QString& kingdom, const QString& id) const {
    return cacheRoot_() + "/" + (kingdom.isEmpty() ? "unknown" : kingdom) + "/" + id;
}

QString ImageFetcherService::localPathFor_(const QString& kingdom, const QString& id, int n) const {
    return cacheDirFor_(kingdom, id) + QString("/%1.jpg").arg(n, 2, 10, QChar('0'));
}

QString ImageFetcherService::cdnUrlFor_(const QString& kingdom, const QString& id, int n) const {
    // n 为 1-based 序号 → 00.jpg 对应 <id>/1.jpg
    return QString(kCdnBase) + "/" + (kingdom.isEmpty() ? "unknown" : kingdom)
           + "/" + id + "/" + QString::number(n) + ".jpg";
}

QString ImageFetcherService::cacheRootPath() const {
    return cacheRoot_();
}

QStringList ImageFetcherService::cachedImages(const QString& id, const QString& kingdom) const {
    QStringList out;
    const QDir d(cacheDirFor_(kingdom, id));
    if (!d.exists()) return out;
    const auto files = d.entryInfoList(
        QStringList() << "*.jpg" << "*.jpeg" << "*.png",
        QDir::Files, QDir::Name);
    for (const auto& fi : files) {
        if (fi.size() <= 1024) continue;
        if (!hasImageMagic(readHead(fi.absoluteFilePath()))) {
            Logger::warn(QString("img cache drop %1 (非图片内容, 已删除)").arg(fi.absoluteFilePath()));
            QFile::remove(fi.absoluteFilePath());
            continue;
        }
        out << fi.absoluteFilePath();
    }
    return out;
}

void ImageFetcherService::clearCache(const QString& id, const QString& kingdom) {
    if (id.isEmpty()) {
        QDir(cacheRoot_()).removeRecursively();
    } else {
        QDir(cacheDirFor_(kingdom, id)).removeRecursively();
    }
}

void ImageFetcherService::fetchImages(const QString& id,
                                       const QString& kingdom,
                                       const QStringList& sources) {
    // 2026-09-30 诊断: 入口埋点. 若日志里连这行都没有 → QML 根本没调 fetchImages;
    //   有这行但无后续 "img req[*]" → 走到了早退分支或 cachedImages 已满.
    Logger::info(QString("img fetch id=%1 kingdom=%2 sources=%3 [%4]")
                 .arg(id, kingdom)
                 .arg(sources.size())
                 .arg(sources.join(" | ")));
    if (id.isEmpty()) {
        emit imageFailed(id, "empty id");
        return;
    }
    Task t;
    t.id = id;
    t.kingdom = kingdom;
    t.sources = sources;
    // 期望图片数上限: 至少探测 1 张, 最多 kMaxImagesPerSpecies. sources 数量只作提示,
    // 实际以 CDN 上是否存在 <n>.jpg 为准 (顺序探测, 首个缺失即停).
    t.maxImages = qBound(1, sources.size(), kMaxImagesPerSpecies);

    // 先填充缓存
    t.cachePaths = cachedImages(id, kingdom);
    t.filledCount = t.cachePaths.size();
    Logger::info(QString("img fetch cache id=%1 cachedImg=%2 cacheRoot=%3")
                 .arg(id).arg(t.cachePaths.size()).arg(cacheRootPath()));

    // 把已有缓存作为 imageReady 立即发出 (QML 端收完即可显示)
    for (int i = 0; i < t.cachePaths.size(); ++i) {
        emit imageReady(id, i, t.cachePaths[i]);
    }

    // 缓存已达上限 → 全部就绪, 不再下载
    if (t.filledCount >= t.maxImages) {
        Logger::info(QString("img fetch allCached id=%1 → imagesAllReady").arg(id));
        emit imagesAllReady(id, t.cachePaths);
        return;
    }

    // 记录到 id 索引, 后续 CDN 下载阶段匹配
    m_idIndex[id] = t;
    startTask_(t);
}

void ImageFetcherService::startTask_(Task t) {
    if (t.filledCount >= t.maxImages) {
        emit imagesAllReady(t.id, t.cachePaths);
        m_idIndex.remove(t.id);
        return;
    }
    // 从缓存之后的下一张开始探测 (缓存 nn.jpg 对应 CDN <nn+1>.jpg)
    t.nextImgIdx = t.filledCount + 1;
    kickImage_(t);
}

void ImageFetcherService::kickImage_(Task task) {
    const QString urlStr = cdnUrlFor_(task.kingdom, task.id, task.nextImgIdx);
    QNetworkRequest req{QUrl(urlStr)};
    req.setHeader(QNetworkRequest::UserAgentHeader, kUserAgent);

    QNetworkReply* reply = m_nam->get(req);
    m_inflight.insert(reply, task);
    connect(reply, &QNetworkReply::finished, this, &ImageFetcherService::onReplyFinished_);
    // 诊断: 若停在 "img req[cdn]" 而永无 "img reply[cdn]" → CDN 连接挂起 (DNS/网络/证书).
    Logger::info(QString("img req[cdn] id=%1 n=%2 url=%3")
                 .arg(task.id).arg(task.nextImgIdx).arg(urlStr));
}

void ImageFetcherService::onReplyFinished_() {
    auto* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    Task task = m_inflight.take(reply);
    const bool ok = (reply->error() == QNetworkReply::NoError);
    const int httpStatus =
        reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray body = reply->readAll();
    Logger::info(QString("img reply[cdn] id=%1 n=%2 ok=%3 http=%4 err=%5 bytes=%6")
                 .arg(task.id).arg(task.nextImgIdx)
                 .arg(ok ? "1" : "0").arg(httpStatus)
                 .arg(reply->errorString()).arg(body.size()));

    // 收尾: 有图 → imagesAllReady; 一张都没有 → 追加 imageFailed (清 loading + 提示)
    auto finish = [this](Task& t) {
        emit imagesAllReady(t.id, t.cachePaths);
        if (t.cachePaths.isEmpty()) {
            emit imageFailed(t.id, QStringLiteral("CDN 无图片 (可能尚未铺图)"));
        }
        m_idIndex.remove(t.id);
    };

    // 顺序探测: 首个缺失/失败/过小即停止 (不做 gap 填充)
    if (!ok || httpStatus >= 400 || body.size() <= kMinImageBytes) {
        finish(task);
        return;
    }

    // 200 + HTML 占位页也走这里: 不落盘, 直接按"无图"收尾
    if (!hasImageMagic(body.left(12))) {
        Logger::warn(QString("img not-image id=%1 n=%2 http=%3 type=%4 bytes=%5 → 未缓存")
                     .arg(task.id).arg(task.nextImgIdx).arg(httpStatus)
                     .arg(reply->header(QNetworkRequest::ContentTypeHeader).toString())
                     .arg(body.size()));
        finish(task);
        return;
    }

    const QString localPath = localPathFor_(task.kingdom, task.id, task.nextImgIdx - 1);
    QDir().mkpath(QFileInfo(localPath).absolutePath());
    QFile f(localPath);
    bool saved = false;
    if (f.open(QIODevice::WriteOnly)) {
        f.write(body);
        f.close();
        saved = (QFileInfo(localPath).size() > kMinImageBytes);
    } else {
        Logger::warn(QString("img save fail %1: %2").arg(localPath, f.errorString()));
    }

    if (saved) {
        task.cachePaths.append(localPath);
        const int idx = task.filledCount;
        task.filledCount++;
        emit imageReady(task.id, idx, localPath);
        Logger::info(QString("img cached %1 [%2] %3").arg(task.id).arg(idx).arg(localPath));
        m_idIndex[task.id] = task;   // 更新进度 (刷新/重进时缓存可复用)
        if (task.filledCount < task.maxImages) {
            task.nextImgIdx++;
            kickImage_(task);        // 继续探测下一张
            return;
        }
    } else {
        Logger::warn(QString("img too small/invalid %1").arg(localPath));
    }
    finish(task);
}

} // namespace outdoor