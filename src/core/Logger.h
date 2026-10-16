/**
 * @file Logger.h
 * @brief 统一日志服务 - 滚动+清理
 *
 * 约束:
 *  - 单个文件最大 1 MB(超出即轮转)
 *  - 整个 logs 目录总大小 ≤ 5 MB(超出按 mtime 删除最老的)
 *  - 备份数最多 5 个(app.log.1 ~ app.log.5)
 *  - 启动时主动清理(防历史遗留超大文件)
 */

#pragma once

#include <QObject>
#include <QString>
#include <QFile>
#include <QMutex>
#include <memory>

namespace outdoor {

class Logger {
public:
    enum class Level {
        Trace = 0,
        Debug = 1,
        Info  = 2,
        Warn  = 3,
        Error = 4,
        Fatal = 5
    };

    static Logger& instance();
    bool initialize(const QString& logDir);
    void shutdown();

    // 写日志
    void log(Level level, const QString& message, const QString& tag = QString());

    // 便捷方法
    static void trace(const QString& msg, const QString& tag = QString());
    static void debug(const QString& msg, const QString& tag = QString());
    static void info(const QString& msg, const QString& tag = QString());
    static void warn(const QString& msg, const QString& tag = QString());
    static void error(const QString& msg, const QString& tag = QString());
    static void fatal(const QString& msg, const QString& tag = QString());

    // 工具
    static QString levelToString(Level level);
    static QString formatMessage(Level level, const QString& msg, const QString& tag);

    // 配置(可在 initialize 前调整)
    void setMaxFileSize(qint64 bytes) { m_maxFileSize = bytes; }
    void setMaxTotalSize(qint64 bytes) { m_maxTotalSize = bytes; }
    void setMaxBackupFiles(int n) { m_maxBackupFiles = n; }
    qint64 currentLogSize() const { return m_logFile.size(); }
    qint64 currentTotalSize() const;

    Logger() = default;
    ~Logger() = default;

private:
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;

    // 轮转 + 清理
    void rotate();                       // 触发新文件 + 移走旧文件
    void enforceTotalSize();             // 删除最老的备份直到总大小 ≤ 限制
    void writeToFile(const QString& line);

    QFile m_logFile;
    QMutex m_mutex;
    QString m_logPath;                   // 当前主文件路径
    QString m_logDir;                    // 日志目录
    Level m_minLevel = Level::Debug;
    qint64 m_maxFileSize = 1 * 1024 * 1024;   // 1MB 单文件
    qint64 m_maxTotalSize = 5 * 1024 * 1024;  // 5MB 目录总大小
    int m_maxBackupFiles = 5;                  // app.log.1 ~ 5
};

} // namespace outdoor
