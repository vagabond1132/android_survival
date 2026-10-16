/**
 * @file AssetLoader.cpp
 * @brief 统一加载只读资源 (qrc://assets/data/.../<filename>)
 *
 * 路径说明:
 *   - 编译时 CMakeLists.txt qt_add_qml_module 把 assets/data/<name>.json 注册进
 *     qrc ://qt/qml/OutdoorSurvival/assets/data/<file>
 *   - 之前各 service 写死的路径是 "://qt/qml/OutdoorSurvival/assets/data/...",
 *     现在统一收敛到 AssetLoader, 未来要改 PREFIX 只改一处
 */

#include "AssetLoader.h"
#include <QFile>
#include <QJsonParseError>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcAsset, "outdoor.asset")

namespace outdoor {

QString AssetLoader::assetRoot() {
    // 单元测试进程不链接 qt_add_qml_module, qrc 资源不存在 → 用磁盘目录覆盖。
    // App 构建不设该变量, 走 qrc 原路径。
    const QString override = qEnvironmentVariable("OUTDOOR_ASSET_ROOT");
    if (!override.isEmpty()) {
        return override.endsWith(QLatin1Char('/')) ? override : override + QLatin1Char('/');
    }
    return QStringLiteral(":/qt/qml/OutdoorSurvival/assets/data/");
}

QByteArray AssetLoader::loadData(const QString& name) {
    const QString fullPath = assetRoot() + name;
    QFile file(fullPath);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcAsset) << "loadData failed to open:" << fullPath
                           << "err=" << file.errorString();
        return {};
    }
    const QByteArray data = file.readAll();
    file.close();
    if (data.isEmpty()) {
        qCWarning(lcAsset) << "loadData empty content:" << fullPath;
    }
    return data;
}

std::optional<QJsonDocument> AssetLoader::loadJson(const QString& name, QString* err) {
    const QByteArray data = loadData(name);
    if (data.isEmpty()) {
        if (err) *err = QStringLiteral("file empty or not found: %1").arg(name);
        return std::nullopt;
    }
    QJsonParseError perr;
    const auto doc = QJsonDocument::fromJson(data, &perr);
    if (perr.error != QJsonParseError::NoError) {
        const QString msg = QStringLiteral("JSON parse error in %1 at offset %2: %3")
                                .arg(name).arg(perr.offset).arg(perr.errorString());
        if (err) *err = msg;
        qCWarning(lcAsset) << msg;
        return std::nullopt;
    }
    if (!doc.isArray() && !doc.isObject()) {
        const QString msg = QStringLiteral("JSON root is not array/object in %1").arg(name);
        if (err) *err = msg;
        qCWarning(lcAsset) << msg;
        return std::nullopt;
    }
    return doc;
}

} // namespace outdoor
