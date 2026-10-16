/**
 * @file DbHelper.cpp
 * @brief DbHelper 实现
 */
#include "DbHelper.h"
#include "../core/Logger.h"

#include <QSqlError>
#include <QSqlDriver>

namespace outdoor {

bool DbHelper::execDdl(QSqlQuery& q, const QString& sql, const QString& tag) {
    if (!q.driver() || !q.driver()->isOpen()) {
        Logger::warn(QStringLiteral("DbHelper::execDdl: db closed (%1)").arg(tag));
        return false;
    }
    if (!q.exec(sql)) {
        Logger::error(QStringLiteral("DbHelper::execDdl failed [%1]: %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return false;
    }
    return true;
}

DmlResult DbHelper::execDml(QSqlQuery& q, const QString& sql,
                            const QVariantMap& binds, const QString& tag) {
    if (!q.driver() || !q.driver()->isOpen()) {
        Logger::warn(QStringLiteral("DbHelper::execDml: db closed (%1)").arg(tag));
        return DmlResult::DbClosed;
    }

    // 0. 先 prepare (无参 exec(sql) 会 clearValues() 抹掉已绑值 -> Parameter count mismatch)
    if (!q.prepare(sql)) {
        Logger::error(QStringLiteral("DbHelper::execDml failed [%1]: prepare %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return DmlResult::ExecError;
    }

    // 1. 绑定参数
    for (auto it = binds.begin(); it != binds.end(); ++it) {
        q.bindValue(it.key(), it.value());
    }

    // 2. 执行
    if (!q.exec()) {
        const QString err = lastErrorText(q);
        Logger::error(QStringLiteral("DbHelper::execDml failed [%1]: %2 | sql=%3")
                          .arg(tag, err, sql.left(200)));
        // 唯一键冲突识别
        if (err.contains(QStringLiteral("UNIQUE constraint failed"), Qt::CaseInsensitive)
            || err.contains(QStringLiteral("PRIMARY KEY constraint failed"), Qt::CaseInsensitive)) {
            return DmlResult::AlreadyExists;
        }
        return DmlResult::ExecError;
    }

    // 3. 检查受影响行数 (-1 表示未知,SQLite DML 不一定返回)
    if (q.numRowsAffected() == 0 && binds.contains(QStringLiteral(":id"))) {
        // 可能是 UPDATE 不命中 — 不算失败,只是无变更
    }

    return DmlResult::Ok;
}

bool DbHelper::execSelect(QSqlQuery& q, const QString& sql,
                          const QVariantMap& binds, const QString& tag) {
    if (!q.driver() || !q.driver()->isOpen()) {
        Logger::warn(QStringLiteral("DbHelper::execSelect: db closed (%1)").arg(tag));
        return false;
    }

    // 先 prepare, 再绑定 (否则 exec(sql) 会 clearValues 抹掉已绑值)
    if (!q.prepare(sql)) {
        Logger::error(QStringLiteral("DbHelper::execSelect failed [%1]: prepare %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return false;
    }

    for (auto it = binds.begin(); it != binds.end(); ++it) {
        q.bindValue(it.key(), it.value());
    }

    if (!q.exec()) {
        Logger::error(QStringLiteral("DbHelper::execSelect failed [%1]: %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return false;
    }
    return true;
}

DmlResult DbHelper::execDmlPositional(QSqlQuery& q, const QString& sql,
                                      const QList<QVariant>& positionalBinds, const QString& tag) {
    if (!q.driver() || !q.driver()->isOpen()) {
        Logger::warn(QStringLiteral("DbHelper::execDmlPositional: db closed (%1)").arg(tag));
        return DmlResult::DbClosed;
    }

    // 0. 先 prepare (无参 exec(sql) 会 clearValues() 抹掉已绑值 -> Parameter count mismatch)
    if (!q.prepare(sql)) {
        Logger::error(QStringLiteral("DbHelper::execDmlPositional failed [%1]: prepare %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return DmlResult::ExecError;
    }

    // 1. 位置绑定 (按顺序对应 SQL 中 `?` 占位符)
    for (const auto& v : positionalBinds) {
        q.addBindValue(v);
    }

    // 2. 执行
    if (!q.exec()) {
        const QString err = lastErrorText(q);
        Logger::error(QStringLiteral("DbHelper::execDmlPositional failed [%1]: %2 | sql=%3")
                          .arg(tag, err, sql.left(200)));
        // 唯一键冲突识别
        if (err.contains(QStringLiteral("UNIQUE constraint failed"), Qt::CaseInsensitive)
            || err.contains(QStringLiteral("PRIMARY KEY constraint failed"), Qt::CaseInsensitive)) {
            return DmlResult::AlreadyExists;
        }
        return DmlResult::ExecError;
    }
    return DmlResult::Ok;
}

bool DbHelper::execSelectPositional(QSqlQuery& q, const QString& sql,
                                    const QList<QVariant>& positionalBinds, const QString& tag) {
    if (!q.driver() || !q.driver()->isOpen()) {
        Logger::warn(QStringLiteral("DbHelper::execSelectPositional: db closed (%1)").arg(tag));
        return false;
    }

    // 先 prepare, 再绑定 (否则 exec(sql) 会 clearValues 抹掉已绑值)
    if (!q.prepare(sql)) {
        Logger::error(QStringLiteral("DbHelper::execSelectPositional failed [%1]: prepare %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return false;
    }

    for (const auto& v : positionalBinds) {
        q.addBindValue(v);
    }

    if (!q.exec()) {
        Logger::error(QStringLiteral("DbHelper::execSelectPositional failed [%1]: %2 | sql=%3")
                          .arg(tag, lastErrorText(q), sql.left(200)));
        return false;
    }
    return true;
}

QString DbHelper::dmlResultToString(DmlResult r) {
    switch (r) {
        case DmlResult::Ok:            return QStringLiteral("Ok");
        case DmlResult::NotFound:      return QStringLiteral("NotFound");
        case DmlResult::AlreadyExists: return QStringLiteral("AlreadyExists");
        case DmlResult::DbClosed:      return QStringLiteral("DbClosed");
        case DmlResult::BindError:     return QStringLiteral("BindError");
        case DmlResult::ExecError:     return QStringLiteral("ExecError");
    }
    return QStringLiteral("Unknown");
}

QString DbHelper::lastErrorText(const QSqlQuery& q) {
    const QSqlError e = q.lastError();
    return e.isValid() ? e.text() : QString();
}

} // namespace outdoor