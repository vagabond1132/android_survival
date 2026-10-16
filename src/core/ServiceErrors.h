/**
 * @file ServiceErrors.h
 * @brief 统一错误码 + ServiceError 结构 (5 阶段架构重构 Phase 2)
 *
 * 设计原则 (2026-09-20):
 *   - 错误码枚举统一,所有 Service 共享一套
 *   - ServiceError 含 code/message/context/details,支持链式调试
 *   - 通过 QmlResultBridge 转 QVariantMap 给 QML
 *
 * 使用:
 *   - C++ 侧: Result<T> 包装 (见 Result.h)
 *   - QML 侧: {ok, value, error} 三元组
 */
#pragma once

#include <QString>
#include <QVariantMap>
#include <QMetaType>

namespace outdoor {

enum class ServiceErrorCode {
    Ok = 0,
    NotFound,            // 数据未找到 (查询结果空)
    InvalidArgument,     // 参数不合法 (id 空/坐标越界等)
    PermissionDenied,    // 系统权限未授予 (位置/相机/存储)
    AlreadyExists,       // 唯一键冲突 (创建已存在的记录)
    DbError,             // SQLite DDL/DML 失败
    IoError,             // 文件读写失败 (导入 GPX 找不到/写权限)
    NetworkError,        // 网络请求失败
    ParseError,          // 解析 JSON/GPX/KML 失败
    Cancelled,           // 用户主动取消
    InternalError,       // 未预期的内部错误
    Unknown              // 未分类
};

struct ServiceError {
    ServiceErrorCode code = ServiceErrorCode::Ok;
    QString message;              // 简短用户可见消息
    QString context;              // 哪个 service::method 报错,例如 "RouteService::saveRoute"
    QVariantMap extra;             // 扩展: SQL lastError / errno / filepath 等

    bool isOk() const { return code == ServiceErrorCode::Ok; }

    QString toString() const {
        return QStringLiteral("ServiceError(%1, msg=%2, ctx=%3)")
            .arg(codeToString(code), message, context);
    }

    static QString codeToString(ServiceErrorCode c) {
        switch (c) {
            case ServiceErrorCode::Ok:               return QStringLiteral("Ok");
            case ServiceErrorCode::NotFound:         return QStringLiteral("NotFound");
            case ServiceErrorCode::InvalidArgument:  return QStringLiteral("InvalidArgument");
            case ServiceErrorCode::PermissionDenied: return QStringLiteral("PermissionDenied");
            case ServiceErrorCode::AlreadyExists:    return QStringLiteral("AlreadyExists");
            case ServiceErrorCode::DbError:          return QStringLiteral("DbError");
            case ServiceErrorCode::IoError:          return QStringLiteral("IoError");
            case ServiceErrorCode::NetworkError:     return QStringLiteral("NetworkError");
            case ServiceErrorCode::ParseError:       return QStringLiteral("ParseError");
            case ServiceErrorCode::Cancelled:        return QStringLiteral("Cancelled");
            case ServiceErrorCode::InternalError:    return QStringLiteral("InternalError");
            case ServiceErrorCode::Unknown:          return QStringLiteral("Unknown");
        }
        return QStringLiteral("Unknown");
    }
};

} // namespace outdoor

Q_DECLARE_METATYPE(outdoor::ServiceError)
Q_DECLARE_METATYPE(outdoor::ServiceErrorCode)