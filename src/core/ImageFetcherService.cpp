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

constexpr const char* kApiBase = "https://commons.wikimedia.org/w/api.php";
constexpr const char* kUserAgent = "OutdoorSurvivalApp/1.0 (image-fetcher; Qt)";

ImageFetcherService::ImageFetcherService(QObject* parent)
    : QObject(parent), m_nam(new QNetworkAccessManager(this)) {}

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
        if (fi.size() > 1024) {
            out << fi.absoluteFilePath();
        }
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
    if (sources.isEmpty()) {
        emit imageFailed(id, "empty sources");
        return;
    }
    Task t;
    t.id = id;
    t.kingdom = kingdom;
    t.sources = sources;

    // 先填充缓存
    t.cachePaths = cachedImages(id, kingdom);
    t.filledCount = t.cachePaths.size();
    Logger::info(QString("img fetch cache id=%1 cachedImg=%2 cacheRoot=%3")
                 .arg(id).arg(t.cachePaths.size()).arg(cacheRootPath()));

    // 把已有缓存作为 imageReady 立即发出 (QML 端收完即可显示)
    for (int i = 0; i < t.cachePaths.size(); ++i) {
        emit imageReady(id, i, t.cachePaths[i]);
    }

    // 缓存已满 → 全部就绪, 不再下载
    if (t.filledCount >= t.sources.size()) {
        Logger::info(QString("img fetch allCached id=%1 → imagesAllReady").arg(id));
        emit imagesAllReady(id, t.cachePaths);
        return;
    }

    // 记录到 id 索引, 后续 imageinfo 下载阶段匹配
    m_idIndex[id] = t;
    startTask_(t);
}

void ImageFetcherService::startTask_(Task t) {
    if (t.filledCount >= t.sources.size()) {
        emit imagesAllReady(t.id, t.cachePaths);
        m_idIndex.remove(t.id);
        return;
    }
    kickSearch_(t);
}

void ImageFetcherService::kickSearch_(Task task) {
    const QString& q = task.sources[task.nextSourceIdx];
    QUrl url(QString(kApiBase) + "?action=query&format=json&list=search"
             "&srsearch=" + QUrl::toPercentEncoding(q)
             + "&srnamespace=6&srlimit=5");
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, kUserAgent);

    Task copy = task;
    copy.phase = Task::Phase::Search;
    QNetworkReply* reply = m_nam->get(req);
    m_inflight.insert(reply, copy);
    connect(reply, &QNetworkReply::finished, this, &ImageFetcherService::onReplyFinished_);
    // 2026-09-30 诊断: 埋点 (含完整 URL). 若日志停在 "img req[search]" 而永无
    //   "img reply[search]" → 请求挂起 (TLS 未就绪 / DNS 卡住 / 网络不可达).
    Logger::info(QString("img req[search] id=%1 url=%2").arg(task.id, url.toString()));
}

void ImageFetcherService::kickDownload_(Task task, const QString& fileTitle) {
    QUrl url(QString(kApiBase) + "?action=query&format=json&prop=imageinfo"
             "&titles=" + QUrl::toPercentEncoding(fileTitle)
             + "&iiprop=url&iiurlwidth=800");
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, kUserAgent);

    Task copy = task;
    copy.phase = Task::Phase::Download;
    copy.currentTitle = fileTitle;
    QNetworkReply* reply = m_nam->get(req);
    m_inflight.insert(reply, copy);
    connect(reply, &QNetworkReply::finished, this, &ImageFetcherService::onReplyFinished_);
    // 2026-09-30 诊断: 埋点. 若日志里无此行 → search 阶段就没拿到标题.
    Logger::info(QString("img req[imageinfo] id=%1 title=%2").arg(task.id, fileTitle));
}

QString ImageFetcherService::firstTitleFromSearch_(const QByteArray& body) {
    QJsonParseError err;
    auto doc = QJsonDocument::fromJson(body, &err);
    if (err.error != QJsonParseError::NoError) return {};
    auto arr = doc.object().value("query").toObject().value("search").toArray();
    // 粗筛: 排除非图 (map, logo, icon, diagram, distribution, schematic 等)
    static const QStringList bad = {
        "map", "logo", "icon", "diagram", "chart", "graph", "schematic",
        "sketch", "drawing", "range_map", "distribution", "habitat",
        "anatomy", "morphology", "cooking", "recipe", "plate", "illustration"
    };
    for (const auto& v : arr) {
        const QString title = v.toObject().value("title").toString();
        const QString low = title.toLower();
        if (!low.endsWith(".jpg") && !low.endsWith(".jpeg") && !low.endsWith(".png"))
            continue;
        bool skip = false;
        for (const auto& b : bad) {
            if (low.contains(b)) { skip = true; break; }
        }
        if (!skip) return title;
    }
    return {};
}

QString ImageFetcherService::thumbUrlFromImageInfo_(const QByteArray& body) {
    QJsonParseError err;
    auto doc = QJsonDocument::fromJson(body, &err);
    if (err.error != QJsonParseError::NoError) return {};
    auto pages = doc.object().value("query").toObject().value("pages").toObject();
    for (const auto& v : pages) {
        const auto infos = v.toObject().value("imageinfo").toArray();
        if (infos.isEmpty()) continue;
        const auto info = infos.first().toObject();
        return info.value("thumburl").toString(info.value("url").toString());
    }
    return {};
}

void ImageFetcherService::onReplyFinished_() {
    auto* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    Task task = m_inflight.take(reply);
    const bool ok = (reply->error() == QNetworkReply::NoError);
    const QByteArray body = reply->readAll();
    // 2026-09-30 诊断: 每次回包一行 (phase / HTTP 状态 / 错误 / 响应体大小).
    //   这是判定 "请求是否真的完成" 的关键埋点: 出现此行说明网络层有返回;
    //   只出现 "img req[*]" 而无此行 = 请求永久挂起.
    //   若 error 含 "SSL"/"ssl"/"handshake" → TLS 层问题 (OpenSSL 缺失/证书).
    const int httpStatus = reply->attribute(
        QNetworkRequest::HttpStatusCodeAttribute).toInt();
    Logger::info(QString("img reply[%1] id=%2 ok=%3 http=%4 err=%5 bytes=%6")
                 .arg(task.phase == Task::Phase::Search ? "search" : "imageinfo",
                      task.id,
                      ok ? "1" : "0")
                 .arg(httpStatus)
                 .arg(reply->errorString())
                 .arg(body.size()));

    if (!ok) {
        // 网络错误 → 跳到下一个 source, 最终才报失败
        task.nextSourceIdx++;
        if (task.nextSourceIdx < task.sources.size()) {
            kickSearch_(task);
        } else {
            emit imagesAllReady(task.id, task.cachePaths);
            if (task.cachePaths.isEmpty()) {
                emit imageFailed(task.id, reply->errorString());
            }
            m_idIndex.remove(task.id);
        }
        return;
    }

    if (task.phase == Task::Phase::Search) {
        const QString title = firstTitleFromSearch_(body);
        if (title.isEmpty()) {
            task.nextSourceIdx++;
            if (task.nextSourceIdx < task.sources.size()) {
                kickSearch_(task);
            } else {
                emit imagesAllReady(task.id, task.cachePaths);
                if (task.cachePaths.isEmpty()) {
                    emit imageFailed(task.id, "no file matched in " +
                                     QString::number(task.sources.size()) + " queries");
                }
                m_idIndex.remove(task.id);
            }
            return;
        }
        // 进入下载阶段
        kickDownload_(task, title);
        return;
    }

    // Phase::Download
    const QString thumbUrl = thumbUrlFromImageInfo_(body);
    if (thumbUrl.isEmpty()) {
        // 当前 source 失败, 尝试下一个
        task.nextSourceIdx++;
        if (task.nextSourceIdx < task.sources.size()) {
            kickSearch_(task);
        } else {
            emit imagesAllReady(task.id, task.cachePaths);
            m_idIndex.remove(task.id);
        }
        return;
    }

    // 下载真实缩略图
    // 2026-09-19: 用 brace init 避免 vexing parse (QNetworkRequest req(QUrl(...))
    //   被编译器解析为函数声明, req 变成返回 QNetworkRequest 的函数指针)
    QNetworkRequest req{QUrl(thumbUrl)};
    req.setHeader(QNetworkRequest::UserAgentHeader, kUserAgent);
    QNetworkReply* dl = m_nam->get(req);

    // 2026-09-30 诊断: 真实缩略图下载入口埋点 (第三段请求, 直接拉高德/Wikimedia 图床).
    //   与 "img reply[thumb]" 成对: 有 req 无 reply = 图片 CDN 连接挂起 (最可能的
    //   白底/转圈根因 —— 前两段 API 走 commons.wikimedia.org 通, 但图床域名不通).
    Logger::info(QString("img req[thumb] id=%1 url=%2").arg(task.id, thumbUrl));

    // 复用 reply mapping: 二次请求把 task.id 作为 key
    Task copy = task;
    copy.phase = Task::Phase::Download;
    m_inflight.insert(dl, copy);
    connect(dl, &QNetworkReply::finished, this, [this, dl]() {
        Task t = m_inflight.take(dl);
        // 2026-09-30 诊断: 图片下载回包. 注意 —— 这里用 header/contentLength 取大小,
        //   不能 readAll() (会消耗响应体, 导致下面 f.write(dl->readAll()) 为空).
        Logger::info(QString("img reply[thumb] id=%1 ok=%2 http=%3 err=%4 clen=%5")
                     .arg(t.id)
                     .arg(dl->error() == QNetworkReply::NoError ? "1" : "0")
                     .arg(dl->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt())
                     .arg(dl->errorString())
                     .arg(dl->header(QNetworkRequest::ContentLengthHeader).toInt()));
        dl->deleteLater();

        // 2026-09-19: QNetworkReply::NoError 是枚举值, 不是函数, 去掉 ()
        if (dl->error() != QNetworkReply::NoError) {
            Logger::warn(QString("img dl err %1: %2").arg(t.id, dl->errorString()));
            t.nextSourceIdx++;
            if (t.nextSourceIdx < t.sources.size()) {
                kickSearch_(t);
            } else {
                emit imagesAllReady(t.id, t.cachePaths);
                m_idIndex.remove(t.id);
            }
            return;
        }

        // 保存到缓存
        const QString localPath = localPathFor_(t.kingdom, t.id, t.filledCount);
        QDir().mkpath(QFileInfo(localPath).absolutePath());
        QFile f(localPath);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(dl->readAll());
            f.close();
            if (QFileInfo(localPath).size() > 1024) {
                t.cachePaths.append(localPath);
                const int idx = t.filledCount;
                t.filledCount++;
                emit imageReady(t.id, idx, localPath);
                Logger::info(QString("img cached %1 [%2] %3").arg(t.id).arg(idx).arg(localPath));
            } else {
                Logger::warn(QString("img too small %1 (%2 B)").arg(localPath)
                             .arg(QFileInfo(localPath).size()));
            }
        } else {
            Logger::warn(QString("img save fail %1: %2").arg(localPath, f.errorString()));
        }

        // 继续下一个 source / 完成
        t.nextSourceIdx++;
        if (t.filledCount < t.sources.size()) {
            if (t.nextSourceIdx < t.sources.size()) {
                kickSearch_(t);
            } else {
                emit imagesAllReady(t.id, t.cachePaths);
                m_idIndex.remove(t.id);
            }
        } else {
            emit imagesAllReady(t.id, t.cachePaths);
            m_idIndex.remove(t.id);
        }
    });
}

} // namespace outdoor