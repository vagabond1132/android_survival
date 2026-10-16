/**
 * @file Result.h
 * @brief 统一 Result<T> 包装 (5 阶段架构重构 Phase 2)
 *
 * 设计:
 *   - C++ 内部用 Result<T> + ServiceError (类型安全)
 *   - 通过 QmlResultBridge 转 QVariantMap 给 QML 端 {ok, value, error}
 *
 * 使用示例:
 *   Result<QString> saveRoute(const Route& r) {
 *       if (!isValid(r)) return Err(ServiceErrorCode::InvalidArgument, "id 空", "saveRoute");
 *       // ... do save ...
 *       return Ok(r.id);
 *   }
 *
 *   Result<void> deleteRoute(const QString& id) {
 *       if (id.isEmpty()) return Err(ServiceErrorCode::InvalidArgument, "id 空", "deleteRoute");
 *       // ... do delete ...
 *       return Ok();
 *   }
 */
#pragma once

#include "ServiceErrors.h"

#include <QVariant>
#include <utility>

namespace outdoor {

// ===== Result<T> =====
template <typename T>
struct Result {
    T value{};
    ServiceError error;

    bool isOk() const  { return error.isOk(); }
    bool isErr() const { return !error.isOk(); }

    // 成功才允许解引用 (调用方必须先 isOk)
    const T& operator*() const&  { return value; }
    T&       operator*() &        { return value; }
    T&&      operator*() &&       { return std::move(value); }
    const T* operator->() const  { return &value; }
    T*       operator->()        { return &value; }
};

// ===== 工厂函数 =====

// Ok(T) — 成功带值
template <typename T>
inline Result<T> Ok(T value) {
    Result<T> r;
    r.value = std::move(value);
    return r;
}

// Ok() — 成功无值 (void 语义)
inline Result<std::monostate> Ok() {
    return Ok(std::monostate{});
}

// Err — 失败 (隐式推断 T)
template <typename T = std::monostate>
inline Result<T> Err(ServiceErrorCode code,
                     const QString& message,
                     const QString& context = {},
                     const QVariantMap& extra = {}) {
    Result<T> r;
    r.error.code    = code;
    r.error.message = message;
    r.error.context = context;
    r.error.extra   = extra;
    return r;
}

// ===== 类型别名 =====

// 显式 void 语义
using ResultVoid = Result<std::monostate>;

} // namespace outdoor