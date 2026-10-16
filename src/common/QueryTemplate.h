/**
 * @file QueryTemplate.h
 * @brief CRUD 模板 (阶段 L5.2)
 *
 * 目的:
 * - 把"按 ID 查 / 查全部 / 按字段查"通用 SQL 抽出来,减少 while(q.next()) 模板代码
 * - 业务层 (Service) 仍直接用 DbHelper::execSelect;这里仅用于"形状高度相似"的简单查询
 *
 * 用法示例:
 *   auto list = QueryTemplate::findAll<FieldGuideEntity>(
 *       db, "plants", [](QSqlQuery& q) { return rowToEntity(q); });
 *
 * 注:
 * - 模板仅覆盖"无 join / 无聚合"的简单查询
 * - 复杂查询仍用 DbHelper::execSelect + 手动 while(q.next())
 * - T 必须 default-constructible
 *
 * 命名规范: 见 doc/05-工程规范/NamingSpec.md §3 (template<typename T>)
 */

#pragma once

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QVariant>
#include <QString>
#include <QList>
#include <optional>
#include <functional>

#include "DbHelper.h"

namespace outdoor {

/**
 * @class QueryTemplate
 * @brief 通用 CRUD 模板 (无状态, 仅 namespace-like 静态方法)
 */
template<typename T>
class QueryTemplate {
public:
    using RowMapper = std::function<T(QSqlQuery&)>;

    /**
     * @brief SELECT * FROM table WHERE pk = ?
     * @return 找到返回 filled, 否则 std::nullopt
     */
    static std::optional<T> findById(QSqlDatabase& db,
                                      const QString& table,
                                      const QString& pkColumn,
                                      const QVariant& pkValue,
                                      RowMapper mapper,
                                      const char* ctxTag = nullptr) {
        QSqlQuery q(db);
        if (!DbHelper::execSelectPositional(q,
                QString("SELECT * FROM %1 WHERE %2 = ? LIMIT 1")
                    .arg(table, pkColumn),
                {pkValue},
                ctxTag ? ctxTag : "QueryTemplate::findById")) {
            return std::nullopt;
        }
        if (!q.next()) return std::nullopt;
        return mapper(q);
    }

    /**
     * @brief SELECT * FROM table (无 WHERE)
     */
    static QList<T> findAll(QSqlDatabase& db,
                              const QString& table,
                              RowMapper mapper,
                              const char* ctxTag = nullptr) {
        QList<T> out;
        QSqlQuery q(db);
        if (!DbHelper::execSelectPositional(q,
                QString("SELECT * FROM %1").arg(table),
                {},
                ctxTag ? ctxTag : "QueryTemplate::findAll")) {
            return out;
        }
        while (q.next()) out.append(mapper(q));
        return out;
    }

    /**
     * @brief SELECT * FROM table WHERE field = ?
     */
    static QList<T> findByField(QSqlDatabase& db,
                                  const QString& table,
                                  const QString& field,
                                  const QVariant& value,
                                  RowMapper mapper,
                                  const char* ctxTag = nullptr) {
        QList<T> out;
        QSqlQuery q(db);
        if (!DbHelper::execSelectPositional(q,
                QString("SELECT * FROM %1 WHERE %2 = ?").arg(table, field),
                {value},
                ctxTag ? ctxTag : "QueryTemplate::findByField")) {
            return out;
        }
        while (q.next()) out.append(mapper(q));
        return out;
    }

    /**
     * @brief DELETE FROM table WHERE field = ?
     * @return 成功 DmlResult::Ok / 否则错误码
     */
    static DmlResult removeByField(QSqlDatabase& db,
                                    const QString& table,
                                    const QString& field,
                                    const QVariant& value,
                                    const char* ctxTag = nullptr) {
        QSqlQuery q(db);
        return DbHelper::execDmlPositional(q,
            QString("DELETE FROM %1 WHERE %2 = ?").arg(table, field),
            {value},
            ctxTag ? ctxTag : "QueryTemplate::removeByField");
    }
};

} // namespace outdoor