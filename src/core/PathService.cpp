/**
 * @file PathService.cpp
 * @brief PathService 实现
 */

#include "PathService.h"
#include "AssetLoader.h"
#include <QStandardPaths>
#include <QDir>
#include <QCoreApplication>

namespace outdoor {

QString PathService::dataDir() {
    static QString cached;
    if (cached.isEmpty()) {
        cached = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        QDir().mkpath(cached);
    }
    return cached;
}

QString PathService::subDir(const QString& sub) {
    const QString p = dataDir() + "/" + sub;
    QDir().mkpath(p);
    return p;
}

QString PathService::dbFileName(int nameEnum) {
    // 对应 Database::Name enum 值
    switch (nameEnum) {
    case 0: return "species.db";   // Species
    case 1: return "firstaid.db";  // FirstAid
    case 2: return "survival.db";  // Survival
    case 3: return "routes.db";    // Routes
    case 4: return "user.db";      // User
    case 5: return "settings.db";  // Settings
    default: return QString("db_%1.db").arg(nameEnum);
    }
}

QString PathService::dbPath(int nameEnum) {
    return dataDir() + "/" + dbFileName(nameEnum);
}

QString PathService::logsDir() { return subDir("logs"); }
QString PathService::configFile() { return dataDir() + "/config.json"; }
QString PathService::equipmentDir() { return subDir("equipment"); }
QString PathService::mapDir() { return subDir("map"); }
QString PathService::knotsDir() { return subDir("knots"); }
QString PathService::assetRoot() { return AssetLoader::assetRoot(); }

} // namespace outdoor
