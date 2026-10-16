/**
 * @file DbHelper.h
 * @brief 统一 SQL DDL/DML/SELECT 工具 (5 阶段架构重构 Phase 2)
 *
 * 设计目标:
 *   - 消除 5 个 service 的裸 `q.exec(...)` 后无条件 `return true`
 *   - 失败自动 log 到 Logger::error,带 tag 标识来源
 *   - SELECT 失败返回 false,DML 失败返回对应 DmlResult
 *
 * 使用示例:
 *   // DDL: ensureSchema
 *   int failed = 0;
 *   if (!DbHelper::execDdl(q, "CREATE TABLE ...", "RouteService::ensureSchema.routes")) ++failed;
 *   if (failed > 0) return false;
 *
 *   // DML: saveRoute
 *   auto rc = DbHelper::execDml(q, "INSERT INTO routes ...", binds, "RouteService::saveRoute");
 *   if (rc != DmlResult::Ok) return false;
 *
 *   // SELECT: 绑定参数 + 校验
 *   if (!DbHelper::execSelect(q, "SELECT ... WHERE id = :id", {{"id", id}}, "ctx")) return {};
 */
#pragma once

#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QSqlQuery>
#include <functional>

namespace outdoor {

enum class DmlResult {
    Ok,                  // 影响行数 ≥ 0
    NotFound,            // INSERT ... ON CONFLICT DO NOTHING 且无插入 (未启用时暂不区分)
    AlreadyExists,            // 唯一键冲突 (UNIQUE constraint failed)
    DbClosed,            // DB 未打开
    BindError,           // bindValue 失败
    ExecError            // exec() 失败 (含 SQL syntax)
};

class DbHelper {
public:
    /** DDL 执行 (CREATE/ALTER/DROP/CREATE INDEX)。失败自动 log。返回 success. */
    static bool execDdl(QSqlQuery& q, const QString& sql, const QString& tag = {});

    /**
     * DML 执行 (INSERT/UPDATE/DELETE)。失败自动 log + 返回 DmlResult。
     * @param binds  命名绑定 {":id", value}, 空 map 表示无参数
     */
    static DmlResult execDml(QSqlQuery& q, const QString& sql,
                             const QVariantMap& binds = {},
                             const QString& tag = {});

    /** SELECT 包装。绑定失败/exec 失败都 log, 返回 false. */
    static bool execSelect(QSqlQuery& q, const QString& sql,
                           const QVariantMap& binds = {},
                           const QString& tag = {});

    /**
     * DML 位置绑定变体 (用于 `?` 占位符).
     * @param positionalBinds  按顺序绑定的值列表, 对应 SQL 中 `?` 占位符
     * @note  e.g. DbHelper::execDmlPositional(q, "INSERT INTO t (a,b) VALUES (?,?)", {v1, v2}, "tag")
     */
    static DmlResult execDmlPositional(QSqlQuery& q, const QString& sql,
                                       const QList<QVariant>& positionalBinds = {},
                                       const QString& tag = {});

    /**
     * SELECT 位置绑定变体 (用于 `?` 占位符).
     * @param positionalBinds  按顺序绑定的值列表
     */
    static bool execSelectPositional(QSqlQuery& q, const QString& sql,
                                     const QList<QVariant>& positionalBinds = {},
                                     const QString& tag = {});

    /** 工具: DmlResult → 用户可见字符串 */
    static QString dmlResultToString(DmlResult r);

    /** 工具: SQL 失败原因 (lastError().text() 含 driver 提示) */
    static QString lastErrorText(const QSqlQuery& q);

    // ===== 高阶 helper: 包 execSelectPositional + while(q.next()) 模板 =====

    /**
     * @brief SELECT 多行, 自动循环映射到 QVariantList
     * @tparam RowMapper  std::function<QVariantMap(QSqlQuery&)>
     * @param q       已构造的 QSqlQuery (注意 q.driver() 必须 open)
     * @param sql     SQL (含 `?` 占位符)
     * @param binds   按顺序的 bind 值
     * @param tag     日志/错误 ctx
     * @param mapper  行 → QVariantMap 转换 (e.g. [](QSqlQuery& q) { return rowToMap(q); })
     * @return 成功 → 完整结果 (失败 → 空 list, 已 log)
     *
     * 替代 4 行模板:
     *   QVariantList list;
     *   if (!DbHelper::execSelectPositional(q, sql, binds, tag)) return list;
     *   while (q.next()) list.append(mapper(q));
     *   return list;
     */
    template<typename RowMapper>
    static QVariantList selectList(QSqlQuery& q, const QString& sql,
                                    const QList<QVariant>& binds,
                                    const QString& tag,
                                    RowMapper mapper) {
        QVariantList list;
        if (!execSelectPositional(q, sql, binds, tag)) return list;
        while (q.next()) list.append(mapper(q));
        return list;
    }

    /**
     * @brief SELECT 单行 (e.g. WHERE id = ? LIMIT 1), 映射到 QVariantMap
     * @return 找到 → filled map; 未找到 / 失败 → 空 map (已 log)
     *
     * 替代 3 行模板:
     *   if (!DbHelper::execSelectPositional(q, sql, binds, tag)) return {};
     *   if (!q.next()) return {};
     *   return rowToMap(q);
     */
    template<typename RowMapper>
    static QVariantMap selectOne(QSqlQuery& q, const QString& sql,
                                  const QList<QVariant>& binds,
                                  const QString& tag,
                                  RowMapper mapper) {
        if (!execSelectPositional(q, sql, binds, tag)) return {};
        if (!q.next()) return {};
        return mapper(q);
    }
};

} // namespace outdoor