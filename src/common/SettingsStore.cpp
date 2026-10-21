/**
 * @file SettingsStore.cpp
 * @brief QSettings 封装实现 (阶段 L5.1)
 */
#include "SettingsStore.h"

#include <QSettings>

namespace outdoor {

namespace {

QSettings& settings() {
    // QSettings 自身是延迟初始化单例,组织名 + 应用名沿用现有默认。
    static QSettings s;
    return s;
}

Result<std::monostate> fromStatus(const QSettings& s, const char* ctx) {
    if (s.status() == QSettings::NoError) {
        return Ok(std::monostate{});
    }
    return Err<std::monostate>(ServiceErrorCode::IoError,
                                QStringLiteral("QSettings 持久化失败: status=%1")
                                    .arg(int(s.status())),
                                ctx);
}

} // anonymous

QVariant SettingsStore::getValue(const QString& key, const QVariant& defaultValue) {
    return settings().value(key, defaultValue);
}

QString SettingsStore::getString(const QString& key, const QString& defaultValue) {
    return settings().value(key, defaultValue).toString();
}

int SettingsStore::getInt(const QString& key, int defaultValue) {
    // 2026-10-16 修: value(key, default).toInt() 遇到非数字字符串返回 0, 调用方给的
    // 兜底默认值被吃掉 (如 getInt("retry", 3) 读到脏数据 -> 0 次重试).
    const QVariant v = settings().value(key);
    bool ok = false;
    const int parsed = v.toInt(&ok);
    return (!v.isValid() || !ok) ? defaultValue : parsed;
}

double SettingsStore::getDouble(const QString& key, double defaultValue) {
    const QVariant v = settings().value(key);
    bool ok = false;
    const double parsed = v.toDouble(&ok);
    return (!v.isValid() || !ok) ? defaultValue : parsed;
}

bool SettingsStore::getBool(const QString& key, bool defaultValue) {
    return settings().value(key, defaultValue).toBool();
}

Result<std::monostate> SettingsStore::setValue(const QString& key, const QVariant& value) {
    const char* ctx = "SettingsStore::setValue";
    settings().setValue(key, value);
    return fromStatus(settings(), ctx);
}

Result<std::monostate> SettingsStore::remove(const QString& key) {
    const char* ctx = "SettingsStore::remove";
    settings().remove(key);
    return fromStatus(settings(), ctx);
}

Result<std::monostate> SettingsStore::sync() {
    const char* ctx = "SettingsStore::sync";
    settings().sync();
    return fromStatus(settings(), ctx);
}

Result<std::monostate> SettingsStore::beginWriteArray(const QString& key, int size) {
    const char* ctx = "SettingsStore::beginWriteArray";
    settings().beginWriteArray(key, size);
    return fromStatus(settings(), ctx);
}

void SettingsStore::setArrayIndex(int i) {
    settings().setArrayIndex(i);
}

void SettingsStore::endArray() {
    settings().endArray();
}

int SettingsStore::beginReadArray(const QString& key) {
    return settings().beginReadArray(key);
}

void SettingsStore::beginGroup(const QString& prefix) {
    settings().beginGroup(prefix);
}

void SettingsStore::endGroup() {
    settings().endGroup();
}

QStringList SettingsStore::childGroups() {
    return settings().childGroups();
}

Result<std::monostate> SettingsStore::clear() {
    const char* ctx = "SettingsStore::clear";
    settings().clear();
    return fromStatus(settings(), ctx);
}

} // namespace outdoor