/**
 * @file Config.cpp
 */

#include "Config.h"
#include "Logger.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QDir>

namespace outdoor {

Config& Config::instance() {
    static Config s_instance;
    return s_instance;
}

bool Config::load(const QString& filePath) {
    m_filePath = filePath;
    QFile file(filePath);

    if (!file.exists()) {
        // 首次启动:加载默认值并落盘
        Logger::info("Config not found, loading defaults and saving");
        setDefaults();
        save();
        return true;
    }

    if (!file.open(QIODevice::ReadOnly)) {
        Logger::error("Failed to open config, falling back to defaults: " + filePath);
        setDefaults();
        return true;  // 修复:不再返回 false,改用默认值
    }

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (doc.isNull() || !doc.isObject()) {
        Logger::error("Invalid config format, falling back to defaults");
        setDefaults();
        return true;  // 修复:不再返回 false
    }

    m_data = doc.object();
    // 即使成功加载,也要补齐缺失的 key(向后兼容)
    setDefaults();
    Logger::info(QString("Config loaded: %1 keys").arg(m_data.size()));
    return true;
}

void Config::setDefaults() {
    // 应用级默认值(可在用户首次保存时被覆盖)
    if (!m_data.contains("theme")) m_data["theme"] = "dark";
    if (!m_data.contains("language")) m_data["language"] = "zh-CN";
    if (!m_data.contains("unit_distance")) m_data["unit_distance"] = "km";
    if (!m_data.contains("unit_elevation")) m_data["unit_elevation"] = "m";
    if (!m_data.contains("unit_temperature")) m_data["unit_temperature"] = "C";
    if (!m_data.contains("map_provider")) m_data["map_provider"] = "tianditu";
    if (!m_data.contains("map_default_type")) m_data["map_default_type"] = "terrain";
    if (!m_data.contains("map_offline_path")) m_data["map_offline_path"] = "";
    if (!m_data.contains("track_frequency_sec")) m_data["track_frequency_sec"] = 5;
    if (!m_data.contains("field_guide_history_default_month")) m_data["field_guide_history_default_month"] = -1;
    if (!m_data.contains("equipment_default_level")) m_data["equipment_default_level"] = "L2";
    if (!m_data.contains("checklist_checked_optional")) m_data["checklist_checked_optional"] = false;
    if (!m_data.contains("sos_hold_seconds")) m_data["sos_hold_seconds"] = 3;
    if (!m_data.contains("route_favorites_only")) m_data["route_favorites_only"] = false;
    if (!m_data.contains("travel_favorites_only")) m_data["travel_favorites_only"] = false;
    if (!m_data.contains("route_difficulty_min")) m_data["route_difficulty_min"] = 1;
    if (!m_data.contains("route_difficulty_max")) m_data["route_difficulty_max"] = 5;
    if (!m_data.contains("route_score_min")) m_data["route_score_min"] = 60;
    if (!m_data.contains("log_level")) m_data["log_level"] = "Info";
    if (!m_data.contains("map_default_zoom")) m_data["map_default_zoom"] = 8;
    if (!m_data.contains("equipment_min_grade")) m_data["equipment_min_grade"] = "recommended";
}

bool Config::save() const {
    if (m_filePath.isEmpty()) return false;

    QDir().mkpath(QFileInfo(m_filePath).absolutePath());

    QFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        Logger::error("Failed to save config: " + m_filePath);
        return false;
    }

    QJsonDocument doc(m_data);
    file.write(doc.toJson(QJsonDocument::Indented));
    file.close();
    return true;
}

QVariant Config::get(const QString& key, const QVariant& def) const {
    if (!m_data.contains(key)) return def;
    QJsonValue v = m_data.value(key);
    if (v.isNull() || v.isUndefined()) return def;
    return v.toVariant();
}

QString Config::getString(const QString& key, const QString& def) const {
    return m_data.value(key).toString(def);
}

int Config::getInt(const QString& key, int def) const {
    return m_data.value(key).toInt(def);
}

bool Config::getBool(const QString& key, bool def) const {
    return m_data.value(key).toBool(def);
}

double Config::getDouble(const QString& key, double def) const {
    return m_data.value(key).toDouble(def);
}

void Config::set(const QString& key, const QVariant& value) {
    m_data.insert(key, QJsonValue::fromVariant(value));
}

void Config::remove(const QString& key) {
    m_data.remove(key);
}

bool Config::contains(const QString& key) const {
    return m_data.contains(key);
}

void Config::sync() {
    save();
}

} // namespace outdoor
