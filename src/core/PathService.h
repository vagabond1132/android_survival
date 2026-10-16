/**
 * @file PathService.h
 * @brief 统一解析 AppDataLocation + db 子目录 + 业务子目录
 *
 * 设计要点 (2026-09-10 抽取):
 * 1. 解决之前 6 个 service 各自 QStandardPaths::writableLocation(AppDataLocation)
 *    重复调用, 6 个 db 文件名硬编码在 Database.cpp 的问题
 * 2. 想加加密/备份/多账号, 改 PathService 一处
 * 3. 不依赖 Qt 信号槽, 纯工具类 (QObject 单例 + Q_GLOBAL_STATIC)
 * 4. 构造时一次性解析, 后续调用零开销
 */

#pragma once

#include <QString>
#include <QObject>
#include <QHash>

namespace outdoor {

class PathService {
public:
    /**
     * 数据库文件名 (Name enum -> 文件名)
     * 之前 6 个 db 文件名硬编码在 Database.cpp:27-48
     */
    static QString dbFileName(int nameEnum);

    /** 主数据目录 (AppDataLocation), 已 mkpath */
    static QString dataDir();

    /** 业务子目录 (dataDir/<sub>), 已 mkpath */
    static QString subDir(const QString& sub);

    /** 常用快捷方式 */
    static QString logsDir();         // dataDir/logs
    static QString configFile();      // dataDir/config.json
    static QString equipmentDir();    // dataDir/equipment
    static QString mapDir();          // dataDir/map
    static QString knotsDir();        // dataDir/knots (预留, 当前 KnotService 用 Survival db)

    /** db 文件完整路径: dataDir/<dbFileName(name)> */
    static QString dbPath(int nameEnum);

    /** 资源 (qrc) 路径: 由 AssetLoader 提供, 这里只做 alias */
    static QString assetRoot();
};

} // namespace outdoor
