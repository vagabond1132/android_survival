/**
 * @file Logger.cpp
 * @brief 日志实现:单文件 1MB + 目录总 1MB + 最多 3 个备份
 *
 * 核心规则:
 *   1. 单个 app.log > 1MB 时,触发 rotate
 *      rotate 流程:app.log.3 删 → app.log.2 → app.log.3 → app.log.1 → app.log.2 → app.log → app.log.1
 *   2. 写日志前 + 启动时,enforceTotalSize 检查目录所有 *.log / *.log.N 总和
 *      超过 1MB 就从最老的备份开始删
 *   3. 启动时主动清:若目录里残留的旧 app.log 超过 1MB,直接 truncate 0 字节
 */

#include "Logger.h"
#include <QDir>
#include <QDateTime>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDebug>
#include <QFileInfoList>

namespace outdoor {

Logger& Logger::instance() {
    static Logger s_instance;
    return s_instance;
}

bool Logger::initialize(const QString& logDir) {
    QMutexLocker locker(&m_mutex);
    m_logDir = logDir;
    QDir().mkpath(m_logDir);

    // 文件名格式: app_YYYYMMDD.log (按日期,1 天 1 个文件,跨天自然轮转)
    QString dateStr = QDateTime::currentDateTime().toString("yyyyMMdd");
    m_logPath = m_logDir + "/app_" + dateStr + ".log";

    // === 1. 启动时主动清理(目录总大小 ≤ 1MB) ===
    //     防止历史残留超 1MB 的旧文件
    enforceTotalSize();

    // === 2. 如果今日主文件 > 1MB,启动时也立即清掉(避免一启动就 rotate 失败) ===
    QFileInfo fi(m_logPath);
    if (fi.exists() && fi.size() > m_maxFileSize) {
        QFile f(m_logPath);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.close();
        }
    }

    // === 3. 打开主文件(append) ===
    m_logFile.setFileName(m_logPath);
    if (!m_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        qCritical() << "Failed to open log file:" << m_logPath;
        return false;
    }

    // 写一条启动日志
    QString startup = formatMessage(Level::Info,
        QString("Logger initialized, dir=%1, maxFile=%2KB, maxTotal=%3KB, backups=%4")
            .arg(m_logDir)
            .arg(m_maxFileSize / 1024)
            .arg(m_maxTotalSize / 1024)
            .arg(m_maxBackupFiles),
        "logger");
    m_logFile.write(startup.toUtf8());
    m_logFile.write("\n");
    m_logFile.flush();
    return true;
}

void Logger::shutdown() {
    QMutexLocker locker(&m_mutex);
    if (m_logFile.isOpen()) {
        // 最后一次清理,保证总大小约束
        m_logFile.close();
        enforceTotalSize();
    }
}

void Logger::log(Level level, const QString& message, const QString& tag) {
    if (level < m_minLevel) return;
    QString line = formatMessage(level, message, tag);

    // 控制台输出
    if (level >= Level::Warn) {
        qWarning().noquote() << line;
    } else {
        qDebug().noquote() << line;
    }

    // 文件输出
    writeToFile(line);
}

void Logger::writeToFile(const QString& line) {
    QMutexLocker locker(&m_mutex);
    if (!m_logFile.isOpen()) return;

    // 写之前检查:单文件超 1MB 即轮转
    // 2026-10-16: 之前用 m_logFile.size(), QFile 会缓存 open 时的大小, 追加写不会
    //   刷新它, 结果轮转永远不触发 (test_rotate_on_size / test_max_backup_files
    //   只能看到 0-1 个备份). 改用 pos() 拿当前写入位置.
    if (m_logFile.pos() > m_maxFileSize) {
        m_logFile.close();
        rotate();
        m_logFile.setFileName(m_logPath);
        m_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    }

    m_logFile.write(line.toUtf8());
    m_logFile.write("\n");
    m_logFile.flush();

    // 写之后检查:目录总大小超 1MB 立即清理
    // (轻量检查,O(1) stat,不会卡顿)
    enforceTotalSize();
}

void Logger::rotate() {
    // 轮转: app.log.N -> app.log.N+1 (从大到小)
    // 例(3 个备份):
    //   app.log.2 删(如果超过 maxBackupFiles)
    //   app.log.1 → app.log.2
    //   app.log   → app.log.1
    QString base = m_logPath;
    QString ext = ".log";

    // 删最老的
    if (m_maxBackupFiles > 0) {
        QString oldest = QString("%1.%2%3").arg(base).arg(m_maxBackupFiles).arg(ext == ".log" ? "" : "");
        // 兼容:base 已含 ".log",所以 oldest 应是 base + "." + n
        oldest = base + "." + QString::number(m_maxBackupFiles);
        if (QFile::exists(oldest)) {
            QFile::remove(oldest);
        }
    }

    // 中间备份依次后移
    for (int i = m_maxBackupFiles - 1; i >= 1; --i) {
        QString src = base + "." + QString::number(i);
        QString dst = base + "." + QString::number(i + 1);
        if (QFile::exists(src)) {
            QFile::rename(src, dst);
        }
    }

    // 主文件 → .1
    if (QFile::exists(base)) {
        QFile::rename(base, base + ".1");
    }

    // 清理超出备份数的旧文件
    for (int i = m_maxBackupFiles + 1; i <= m_maxBackupFiles + 5; ++i) {
        QString old = base + "." + QString::number(i);
        if (QFile::exists(old)) QFile::remove(old);
    }
}

void Logger::enforceTotalSize() {
    if (m_logDir.isEmpty()) return;
    QDir dir(m_logDir);
    if (!dir.exists()) return;

    // 收集所有 .log 与 .log.N 文件大小
    // 按 mtime 升序排(最老的在前),删到 ≤ m_maxTotalSize
    QFileInfoList allFiles = dir.entryInfoList(
        QStringList() << "*.log" << "*.log.*",
        QDir::Files,
        QDir::Time);  // 升序,最老的在前

    // 计算当前总大小
    auto totalSize = [&]() -> qint64 {
        qint64 t = 0;
        for (const auto& fi : allFiles) t += fi.size();
        return t;
    };

    // 主文件 + 所有 backup
    // 从最老的开始删,直到 ≤ 1MB
    for (const auto& fi : allFiles) {
        if (totalSize() <= m_maxTotalSize) break;
        // 跳过当前正在写入的主文件(若 m_logPath 在列表中,跳过它)
        if (fi.absoluteFilePath() == m_logPath) continue;
        QFile::remove(fi.absoluteFilePath());
    }

    // 进一步防御:即使这样,主文件还可能 > 1MB(没及时轮转)
    // 如果主文件已超 1MB,直接 truncate 0 字节
    QFileInfo mainFi(m_logPath);
    if (mainFi.exists() && mainFi.size() > m_maxFileSize) {
        // 必须先关闭再 truncate(如果当前还打开着)
        bool wasOpen = m_logFile.isOpen();
        if (wasOpen) m_logFile.close();

        QFile f(m_logPath);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.close();
        }
        if (wasOpen) {
            m_logFile.setFileName(m_logPath);
            m_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
        }
    }
}

qint64 Logger::currentTotalSize() const {
    if (m_logDir.isEmpty()) return 0;
    QDir dir(m_logDir);
    if (!dir.exists()) return 0;
    QFileInfoList list = dir.entryInfoList(
        QStringList() << "*.log" << "*.log.*",
        QDir::Files);
    qint64 total = 0;
    for (const auto& fi : list) total += fi.size();
    return total;
}

QString Logger::levelToString(Level level) {
    switch (level) {
        case Level::Trace: return "TRACE";
        case Level::Debug: return "DEBUG";
        case Level::Info:  return "INFO";
        case Level::Warn:  return "WARN";
        case Level::Error: return "ERROR";
        case Level::Fatal: return "FATAL";
    }
    return "UNKNOWN";
}

QString Logger::formatMessage(Level level, const QString& msg, const QString& tag) {
    QString timestamp = QDateTime::currentDateTime()
                            .toString("yyyy-MM-dd HH:mm:ss.zzz");
    QString tagStr = tag.isEmpty() ? "" : QString("[%1]").arg(tag);
    return QString("%1 %2 %3 %4")
        .arg(timestamp)
        .arg(levelToString(level))
        .arg(tagStr)
        .arg(msg);
}

// 静态便捷方法
void Logger::trace(const QString& msg, const QString& tag) {
    instance().log(Level::Trace, msg, tag);
}
void Logger::debug(const QString& msg, const QString& tag) {
    instance().log(Level::Debug, msg, tag);
}
void Logger::info(const QString& msg, const QString& tag) {
    instance().log(Level::Info, msg, tag);
}
void Logger::warn(const QString& msg, const QString& tag) {
    instance().log(Level::Warn, msg, tag);
}
void Logger::error(const QString& msg, const QString& tag) {
    instance().log(Level::Error, msg, tag);
}
void Logger::fatal(const QString& msg, const QString& tag) {
    instance().log(Level::Fatal, msg, tag);
}

} // namespace outdoor
