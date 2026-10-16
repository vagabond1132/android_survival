/**
 * @file Config.h
 * @brief 应用配置管理
 */

#pragma once

#include <QObject>
#include <QVariant>
#include <QJsonObject>

namespace outdoor {

/**
 * @class Config
 * @brief 配置管理（单例）
 */
class Config {
public:
    static Config& instance();
    bool load(const QString& filePath);
    bool save() const;

    // 取值
    QVariant get(const QString& key, const QVariant& defaultValue = {}) const;
    QString getString(const QString& key, const QString& defaultValue = "") const;
    int getInt(const QString& key, int defaultValue = 0) const;
    bool getBool(const QString& key, bool defaultValue = false) const;
    double getDouble(const QString& key, double defaultValue = 0.0) const;

    // 写入
    void set(const QString& key, const QVariant& value);
    void remove(const QString& key);
    bool contains(const QString& key) const;

    // 同步
    void sync();

    // 默认配置(首次启动或加载失败时调用,避免 m_data 为空)
    void setDefaults();

    Config() = default;

private:
    QString m_filePath;
    QJsonObject m_data;
};

} // namespace outdoor
