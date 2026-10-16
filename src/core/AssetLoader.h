/**
 * @file AssetLoader.h
 * @brief 统一加载只读资源 (qrc://assets/data/.../<filename>)
 *
 * 设计要点:
 * 1. 所有 service 通过 AssetLoader 加载 assets/data/<name>.json, 不再写各
 *    自的候选路径列表 (之前 11 个 service 用了 4 种不同 fallback 风格,
 *    其中 3 种在 Android APK 里是死代码).
 * 2. 路径前缀写死 ://qt/qml/OutdoorSurvival/assets/data/, 跟
 *    CMakeLists.txt qt_add_qml_module 的 RESOURCES + OUTPUT_DIRECTORY
 *    一致. 改前缀要同时改两边.
 * 3. 返回 std::optional<QJsonDocument> 强制 caller 处理"加载失败"分支
 *    (之前用 QStringList 候选 + QFile.open return, 调用方经常漏检).
 */

#pragma once

#include <QString>
#include <QByteArray>
#include <QJsonDocument>
#include <optional>

namespace outdoor {

class AssetLoader {
public:
    AssetLoader() = delete;

    /**
     * @brief 加载只读 assets/data/<name> 文件原始字节
     * @param name 纯文件名, 如 "knots.json" (不带目录前缀)
     * @return 成功返回字节, 失败返回空 QByteArray
     */
    static QByteArray loadData(const QString& name);

    /**
     * @brief 加载并解析为 QJsonDocument
     * @param name 纯文件名, 如 "knots.json"
     * @param err  (可选) 失败时填错误描述
     * @return 成功返回 QJsonDocument, 失败返回 std::nullopt
     */
    static std::optional<QJsonDocument> loadJson(const QString& name, QString* err = nullptr);

    /**
     * @brief 资源根路径常量 (供调试/日志使用)
     */
    static QString assetRoot();
};

} // namespace outdoor
