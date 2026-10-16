/**
 * @file ServiceBase.h
 * @brief Service 基类 (Phase L2: 2026-09-21)
 *
 * 设计目标:
 *   - 消除 12 个 service 重复的 `Database* m_db` + QObject 继承 + forward decl
 *   - 提供统一日志上下文 (`m_contextTag`) + Result<QVariantMap> 包装
 *   - 约束后续 service 必须继承本基类, 不再直接 `public QObject`
 *
 * 双形态:
 *   - ServiceBase(db, "KnotService", parent):   12 个 db-backed service 用
 *   - ServiceBase("MapService", parent):         4 个无 db service 用 (Travel/Map/Equipment/DecisionEngine)
 *
 * 子类约定:
 *   - 不再加 `Database* m_db` 字段, 用 `m_db` (本类 protected 字段)
 *   - 不再加 Q_OBJECT 行 (本类已加), 但子类仍需加自己的 signals/slots
 *   - 错误日志统一 `Logger::warn(QString("%1: %2").arg(m_contextTag).arg(msg))`
 */
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>

namespace outdoor {

class Database;

class ServiceBase : public QObject {
    Q_OBJECT
public:
    /**
     * @brief ctor (db-backed service)
     * @param db          数据库指针 (可为 nullptr, 表示无 db 需求)
     * @param contextTag  日志上下文 tag, e.g. "KnotService"
     * @param parent      QObject 父级
     */
    explicit ServiceBase(Database* db, const QString& contextTag, QObject* parent = nullptr)
        : QObject(parent), m_db(db), m_contextTag(contextTag) {}

    /**
     * @brief ctor (无 db service, e.g. TravelService / MapService / EquipmentService / DecisionEngine)
     */
    explicit ServiceBase(const QString& contextTag, QObject* parent = nullptr)
        : QObject(parent), m_db(nullptr), m_contextTag(contextTag) {}

    ~ServiceBase() override = default;

    /** 统一日志 tag, 子类 Logger 调用可用 */
    const QString& contextTag() const { return m_contextTag; }

protected:
    /** 数据库指针 (可为 nullptr). 12 个 db-backed service 通过本字段访问 db. */
    Database* m_db;

    /** 日志上下文 tag, e.g. "KnotService". 子类可在 Logger::warn/error 用. */
    QString m_contextTag;
};

} // namespace outdoor
