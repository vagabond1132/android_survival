/**
 * @file QmlResultBridge.h
 * @brief Result<T> ↔ QVariantMap 桥接 + 写操作/DB 错误公共 helper
 *
 * 用途:
 *   - C++ Service 实现内部用 Result<T>,QML 调用端只能看到 QVariantMap
 *   - 通过 toQVariant / isOk / extractError 三个工具方法无缝衔接
 *
 * QML 端调用模式 (Phase 5 全量切换后):
 *   var result = routeService.saveRoute(route)
 *   if (!result.ok) {
 *       Toast.error(result.error.message)
 *   } else {
 *       var newId = result.value
 *   }
 *
 * 注意:
 *   - 内部模块,不在 src/core/PublicApi.h 暴露
 *   - 使用 namespace + free function 而非 class + static,
 *     这样 service 里 `using namespace outdoor::internal;` 就能直接调 toQVariant()
 *   - 模板实现放在 .inl,这里只声明
 *   - 默认参数只在 .h 声明处写, .inl 定义不写 (避免 C++ 重定义警告)
 */
#pragma once

#include "../Result.h"
#include "../ServiceErrors.h"
#include "../../common/DbHelper.h"  // 2026-09-21: dbErr 需要 DmlResult 类型
#include "../Database.h"            // 2026-09-21: dbOpenCheck 需要 Database::Name

#include <QVariant>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QSqlError>   // dbErr() 需要 QSqlError::text() 完整类型
#include <optional>

namespace outdoor::internal {

// === Result<T> → QVariantMap ===
template <typename T>
QVariantMap toQVariant(const Result<T>& r);

// === Result<void> 便捷 ===
QVariantMap toQVariant(const Result<std::monostate>& r);

// === 直接构造失败 (ServiceError → QVariantMap) ===
QVariantMap toQVariant(const ServiceError& err);

// === 直接构造成功 (T → QVariantMap,自动补 ok=true + error=Ok) ===
template <typename T>
QVariantMap ok(const T& value);

// === QVariantMap → 校验 (QML 端传来的 result 是否 ok) ===
bool isOk(const QVariantMap& m);

// === QVariantMap → 错误信息 (QML Toast 用) ===
QString errorMessage(const QVariantMap& m);

// === 写操作快捷 helper ===
// 替代 toQVariant(Err<std::monostate>(code, msg, ctx)) 模板,见 .inl
QVariantMap fail(ServiceErrorCode code, const QString& message,
                const QString& context = {});

// 替代 toQVariant(Ok(std::monostate{})),见 .inl
QVariantMap okVoid();

// 把 SettingsStore::sync() 等 Result<monostate> 转 QVariantMap,失败自动 IoError
QVariantMap syncToQVariant(const Result<std::monostate>& syncRes,
                            const QString& context = {});

/**
 * @brief DbHelper DML 失败 → 自动读 lastError + log + 包成 QVariantMap 错误
 *        替代 4 行模板:
 *          if (rc != DmlResult::Ok) {
 *              const QString err = m_db->get(Name).lastError().text();
 *              Logger::error(QString("%1: %2").arg(ctx, err));
 *              return fail(DbError, err, ctx);
 *          }
 *
 * 用法: if (rc != DmlResult::Ok) return dbErr(rc, db, ctx);
 *
 * @param rc       DbHelper 返回码 (DmlResult)
 * @param db       已取出的 QSqlDatabase (用于读 lastError)
 * @param context  日志/错误 ctx
 * @return         okVoid() (rc==Ok) 或 fail(DbError, ...) (rc!=Ok)
 */
QVariantMap dbErr(DmlResult rc, const QSqlDatabase& db, const QString& context = {});

/**
 * @brief 高阶 DML 包装: dbOpenCheck + get db + q + execFn + dbErr 模板.
 *        见 .inl 注释. 替代 4 行模板, 适合 "执行 SQL + 检查失败" 的写操作.
 */
template<typename ExecFn>
QVariantMap execDmlReturning(Database* db, Database::Name name,
                             const QString& context,
                             ExecFn&& execFn);

/**
 * @brief 检查 db 是否打开, 失败 → fail(DbError, "本机数据库没打开", ctx), 成功 → nullopt.
 *
 * 替代 4 行模板:
 *   if (!m_db || !m_db->isOpen(Database::Name::X)) {
 *       return fail(ServiceErrorCode::DbError, QStringLiteral("本机数据库没打开"), ctx);
 *   }
 *
 * 用法: if (auto e = dbOpenCheck(m_db, Database::Name::X, ctx)) return *e;
 *
 * @note  bool 上下文 (return false/list/...) 仍用 !m_db || !m_db->isOpen() 内联判断,
 *        本 helper 只用于 QVariantMap 上下文 (返回错误 Result).
 */
std::optional<QVariantMap> dbOpenCheck(const Database* db, Database::Name name,
                                        const QString& context = {});

/**
 * @brief 把子调用的 QVariantMap 错误透传给当前函数 (转码 + 包装为 Result<T>).
 *
 * 替代 5 行模板:
 *   auto res = subService.saveXxx(x);
 *   if (!res.value("ok").toBool()) {
 *       return toQVariant(Err<bool>(ServiceErrorCode::DbError,
 *                                    res.value("error").toMap()["message"].toString(), ctx));
 *   }
 *
 * 用法: auto err = propagateError<bool>(subRes, ctx); if (err) return *err;
 *       // 继续用 res.value("value")...
 *
 * @tparam T 当前函数返回值类型 (Err<T> 的 T)
 * @param  sub  子调用 QVariantMap (内部 toQVariant 包过的)
 * @param  context  当前函数 ctx (用于 Err 包装)
 * @return nullopt = sub 成功; QVariantMap = 应直接 return 的错误
 */
template <typename T>
std::optional<QVariantMap> propagateError(const QVariantMap& sub,
                                            const QString& context = {});

/**
 * @brief 入参校验: 字符串非空 (非 trimmed-empty). 失败 → fail(InvalidArgument, "<字段名> 不能为空", ctx)
 *
 * 替代 3 行模板:
 *   if (value.isEmpty()) {
 *       return fail(InvalidArgument, QStringLiteral("这条装备的编号不能为空"), ctx);
 *   }
 *
 * 用法: if (auto e = requireNonEmpty(value, "这条装备的编号", ctx)) return *e;
 *
 * @param value  待校验字符串
 * @param name   字段名 —— 会被拼进屏幕上那句「…不能为空」, 所以必须写给人读的中文
 * @param context  当前函数 ctx
 * @return nullopt = 通过; QVariantMap = 应直接 return 的错误
 */
std::optional<QVariantMap> requireNonEmpty(const QString& value,
                                            const QString& name,
                                            const QString& context = {});

/**
 * @brief 入参校验: 字符串非空白 (trimmed 后非空). 失败 → fail(InvalidArgument, "name 不能为空", ctx)
 *
 * 与 requireNonEmpty 的区别: 本 helper 用 value.trimmed().isEmpty(),
 * 适用于"用户输入的字符串, 纯空格也不算合法".
 *
 * 替代 3 行模板:
 *   if (name.trimmed().isEmpty()) {
 *       return fail(InvalidArgument, QStringLiteral("name 不能为空"), ctx);
 *   }
 *
 * 用法: if (auto e = requireNonBlank(name, "name", ctx)) return *e;
 */
std::optional<QVariantMap> requireNonBlank(const QString& value,
                                            const QString& name,
                                            const QString& context = {});

} // namespace outdoor::internal

#include "QmlResultBridge.inl"