/**
 * @file SettingsStore.h
 * @brief QSettings 封装 (阶段 L5.1)
 *
 * 目的:
 * - 统一组织名 / 应用名 (避免各处散写 QSettings)
 * - 提供 Result 风格的写接口 (与 Service 错误风格统一)
 * - 提供 RAII 数组 helper (beginArray/endArray) 防漏 endArray
 *
 * 用法:
 *   SettingsStore ss;
 *   QString name = ss.getString("user/name", "default");
 *   auto rc = ss.setString("user/name", "alice");
 *   if (!rc.ok) { Logger::error(rc.error); }
 *
 *   ss.beginArray("preferences");
 *   for (int i = 0; i < n; ++i) {
 *       ss.setArrayIndex(i);
 *       ss.setValue("id", ids[i]);
 *   }
 *   ss.endArray();
 *
 * 命名规范: 见 doc/05-工程规范/NamingSpec.md §1 (*Store 类名仅 SettingsStore)
 */

#pragma once

#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include "../core/Result.h"

namespace outdoor {

/**
 * @class SettingsStore
 * @brief 单例 QSettings 封装 (基于 QSettings 自身单例的薄包装)
 *
 * 不是新单例;只是给 QSettings 加语义糖。所有方法 static,无状态。
 */
class SettingsStore {
public:
    // === 单值读写 ===

    static QVariant getValue(const QString& key, const QVariant& defaultValue = {});
    static QString getString(const QString& key, const QString& defaultValue = QString());
    static int getInt(const QString& key, int defaultValue = 0);
    static double getDouble(const QString& key, double defaultValue = 0.0);
    static bool getBool(const QString& key, bool defaultValue = false);

    /**
     * @brief 写入单值
     * @return Ok 或 Err (status 字段含 QSettings::status)
     */
    static Result<std::monostate> setValue(const QString& key, const QVariant& value);

    /**
     * @brief 删除一个 key (或一个数组)
     */
    static Result<std::monostate> remove(const QString& key);

    /**
     * @brief 同步写入磁盘 (status != NoError 时返回 Err)
     */
    static Result<std::monostate> sync();

    // === 数组读写 (RAII 风格) ===

    /**
     * @brief 开始写数组
     * @param size 数组长度;若 <0 表示"追加到现有数组"
     */
    static Result<std::monostate> beginWriteArray(const QString& key, int size = -1);

    /**
     * @brief 设置当前数组索引 (在 begin/end 之间调用)
     */
    static void setArrayIndex(int i);

    /**
     * @brief 结束数组 (与 beginWriteArray 配对)
     */
    static void endArray();

    /**
     * @brief 读取数组长度
     */
    static int beginReadArray(const QString& key);

    /**
     * @brief 进入子组 (用于嵌套结构: user_items/<id>/...)
     */
    static void beginGroup(const QString& prefix);

    /**
     * @brief 离开子组 (与 beginGroup 配对)
     */
    static void endGroup();

    /**
     * @brief 列出当前组的直接子组名 (用于遍历 user_items)
     */
    static QStringList childGroups();

    /**
     * @brief 全部清除
     */
    static Result<std::monostate> clear();
};

} // namespace outdoor