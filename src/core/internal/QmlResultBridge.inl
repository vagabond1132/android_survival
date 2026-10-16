/**
 * @file QmlResultBridge.inl
 * @brief QmlResultBridge 模板/内联实现
 *
 * 注: .inl 文件被 QmlResultBridge.h 末尾 #include,不要单独 include
 *
 * 2026-09-21: 从 class + static 改为 namespace + free function,
 *   让 service 里 `using namespace outdoor::internal;` 直接带入 toQVariant 等
 */
#pragma once

#include "QmlResultBridge.h"

#include "../Logger.h"  // 2026-09-21: dbErr 需要 Logger::error

#include <QMetaType>

namespace outdoor::internal {

template <typename T>
QVariantMap toQVariant(const Result<T>& r) {
    QVariantMap m;
    m.insert(QStringLiteral("ok"), r.isOk());
    if (r.isOk()) {
        m.insert(QStringLiteral("value"), QVariant::fromValue(r.value));
        m.insert(QStringLiteral("error"), QVariant::fromValue(ServiceError{}));
    } else {
        // 失败时 value 用 T 的默认值,避免 QML 拿到未初始化的字段
        m.insert(QStringLiteral("value"), QVariant::fromValue(T{}));
        m.insert(QStringLiteral("error"), QVariant::fromValue(r.error));
    }
    return m;
}

inline QVariantMap toQVariant(const Result<std::monostate>& r) {
    QVariantMap m;
    m.insert(QStringLiteral("ok"), r.isOk());
    m.insert(QStringLiteral("value"), QVariant{});
    m.insert(QStringLiteral("error"), r.isOk()
                                        ? QVariant::fromValue(ServiceError{})
                                        : QVariant::fromValue(r.error));
    return m;
}

inline QVariantMap toQVariant(const ServiceError& err) {
    QVariantMap m;
    m.insert(QStringLiteral("ok"), err.isOk());
    m.insert(QStringLiteral("value"), QVariant{});
    m.insert(QStringLiteral("error"), QVariant::fromValue(err));
    return m;
}

template <typename T>
QVariantMap ok(const T& value) {
    QVariantMap m;
    m.insert(QStringLiteral("ok"), true);
    m.insert(QStringLiteral("value"), QVariant::fromValue(value));
    m.insert(QStringLiteral("error"), QVariant::fromValue(ServiceError{}));
    return m;
}

inline bool isOk(const QVariantMap& m) {
    return m.value(QStringLiteral("ok"), false).toBool();
}

inline QString errorMessage(const QVariantMap& m) {
    const QVariant errVar = m.value(QStringLiteral("error"));
    if (!errVar.canConvert<ServiceError>()) return QString();
    const ServiceError err = errVar.value<ServiceError>();
    return err.message;
}

// ===== 写操作快捷 helper =====

/**
 * @brief Err<monostate>(code, msg, ctx) 的快捷封装, 避免每个写操作重复 4 行.
 *        等价于: toQVariant(Err<std::monostate>(code, msg, ctx))
 * @note  默认参数只在 .h 声明处写, .inl 不写 (避免重定义警告)
 */
inline QVariantMap fail(ServiceErrorCode code,
                        const QString& message,
                        const QString& context) {
    return toQVariant(Err<std::monostate>(code, message, context));
}

/**
 * @brief Ok(monostate{}) 的快捷封装. 写操作成功后返回.
 *        等价于: toQVariant(Ok(std::monostate{}))
 */
inline QVariantMap okVoid() {
    return toQVariant(Ok(std::monostate{}));
}

/**
 * @brief 将 Result<monostate> (e.g. SettingsStore::sync) 转 QVariantMap, 失败自动映射 IoError.
 *        成功 → okVoid(); 失败 → fail(IoError, err.message, ctx).
 *
 * 用法替代:
 *   auto syncRes = SettingsStore::sync();
 *   if (!syncRes.isOk()) {
 *       return toQVariant(Err<std::monostate>(IoError, syncRes.error.message, ctx));
 *   }
 *   return toQVariant(Ok(std::monostate{}));
 *
 * 改为:
 *   return syncToQVariant(SettingsStore::sync(), ctx);
 *
 * @note  默认参数只在 .h 声明处写, .inl 不写 (避免重定义警告)
 */
inline QVariantMap syncToQVariant(const Result<std::monostate>& syncRes,
                                    const QString& context) {
    if (syncRes.isOk()) return okVoid();
    return fail(ServiceErrorCode::IoError, syncRes.error.message, context);
}

/**
 * @brief DbHelper DML 失败 → 自动读 lastError + log + 包成 QVariantMap 错误
 * @note  默认参数只在 .h 声明处写, .inl 不写 (避免重定义警告)
 */
inline QVariantMap dbErr(DmlResult rc, const QSqlDatabase& db, const QString& context) {
    if (rc == DmlResult::Ok) return okVoid();
    const QString err = db.lastError().text();
    Logger::error(QString("%1: %2").arg(context, err));
    return fail(ServiceErrorCode::DbError, err, context);
}

/**
 * @brief 高阶 DML 包装: dbOpenCheck + get db + q + execFn + dbErr 模板
 *
 * 替代 4 行模板 (6 个 FieldGuideHistory 写方法 + 类似写操作 service):
 *   if (auto e = dbOpenCheck(db, name, ctx)) return *e;
 *   QSqlDatabase sqlDb = db->get(name);
 *   QSqlQuery q(sqlDb);
 *   auto rc = DbHelper::execDmlPositional(q, sql, binds, ctx);
 *   if (rc != DmlResult::Ok) return dbErr(rc, sqlDb, ctx);
 *
 * 用法:
 *   auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
 *       [id, ctx](QSqlQuery& q) {
 *           return DbHelper::execDmlPositional(q,
 *               "DELETE FROM t WHERE id = ?", {id}, ctx);
 *       });
 *   if (!isOk(err)) return err;
 *   // ...后续: refresh / emit / return toQVariant(Ok(...))
 *
 * @tparam ExecFn  std::function<DmlResult(QSqlQuery&)>
 * @return 成功 → okVoid() (Ok(true)); 失败 → dbErr 返回的错误 (应直接 return *err)
 *
 * @note  需要 lastInsertId 或自定义 Ok(value) 的 (e.g. FieldGuideHistory::addRecord),
 *        仍用 dbOpenCheck + execDmlPositional 直接模板 (本 helper 不够用).
 * @note  默认参数只在 .h 声明处写, .inl 不写
 */
template<typename ExecFn>
inline QVariantMap execDmlReturning(Database* db, Database::Name name,
                                     const QString& context,
                                     ExecFn&& execFn) {
    if (auto e = dbOpenCheck(db, name, context)) return *e;
    QSqlDatabase sqlDb = db->get(name);
    QSqlQuery q(sqlDb);
    auto rc = execFn(q);
    if (rc != DmlResult::Ok) return dbErr(rc, sqlDb, context);
    return okVoid();
}

/**
 * @brief 检查 db 是否打开
 * @note  默认参数只在 .h 声明处写, .inl 不写 (避免重定义警告)
 */
inline std::optional<QVariantMap> dbOpenCheck(const Database* db, Database::Name name,
                                                const QString& context) {
    if (db && db->isOpen(name)) return std::nullopt;
    return fail(ServiceErrorCode::DbError, QStringLiteral("DB 未打开"), context);
}

/**
 * @brief 透传子调用错误
 * @note  默认参数只在 .h 声明处写, .inl 不写 (避免重定义警告)
 */
template <typename T>
inline std::optional<QVariantMap> propagateError(const QVariantMap& sub,
                                                    const QString& context) {
    if (isOk(sub)) return std::nullopt;
    // 抽取子调用的 error.message, 包装为本函数的 Err<T>
    return toQVariant(Err<T>(ServiceErrorCode::DbError, errorMessage(sub), context));
}

inline std::optional<QVariantMap> requireNonEmpty(const QString& value,
                                                    const QString& name,
                                                    const QString& context) {
    if (!value.isEmpty()) return std::nullopt;
    return fail(ServiceErrorCode::InvalidArgument,
                QStringLiteral("%1 不能为空").arg(name), context);
}

inline std::optional<QVariantMap> requireNonBlank(const QString& value,
                                                    const QString& name,
                                                    const QString& context) {
    if (!value.trimmed().isEmpty()) return std::nullopt;
    return fail(ServiceErrorCode::InvalidArgument,
                QStringLiteral("%1 不能为空").arg(name), context);
}

} // namespace outdoor::internal