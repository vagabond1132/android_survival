/**
 * @file Database.h
 * @brief 数据库管理器
 */

#pragma once

#include <QObject>
#include <QSqlDatabase>
#include <QString>
#include <QHash>
#include <memory>

namespace outdoor {

/**
 * @class Database
 * @brief 多数据库管理
 */
class Database : public QObject {
    Q_OBJECT
public:
    enum class Name {
        Species,         // 物种
        FirstAid,        // 急救
        Survival,        // 避险
        Routes,          // 路线
        User,            // 用户
        Settings         // 设置
    };
    Q_ENUM(Name)

    explicit Database(QObject* parent = nullptr);
    ~Database();

    bool open(const QString& dataPath);
    void close();

    QSqlDatabase get(Name name) const;
    bool isOpen(Name name) const;

    /**
     * @brief 当前 schema 版本号 (PRAGMA user_version 写值)
     *
     * 版本演进 (2026-09-21 阶段 J 起):
     *   v1: 2026-09-03 之前初版 schema
     *   v2: 2026-09-10+ KnotService V1→V2 数据迁移, 加 knot_progress 表
     *        (schema 实际由 KnotService::ensureSchema() 在 Survival db 建,
     *         Database::migrateToLatest() 仅负责 user_version 计数)
     *   v3: 2026-10-16 emergency_contacts 补 created_at / updated_at / is_deleted
     *        (旧版这份 schema 漏列, 导致 EmergencyService 所有读取失败)
     *
     * 每次有破坏性 schema 变更 (加表/加列/重命名), 递增该常量并新增
     * migrate_X_to_Y() 方法.
     */
    static constexpr int kCurrentSchemaVersion = 3;

    // 迁移
    bool migrate();

private:
    bool openDatabase(Name name, const QString& filePath);
    bool createSchema(Name name);

    // 2026-09-21 阶段 J: PRAGMA user_version 迁移机制
    int currentVersion(Name name) const;
    bool setVersion(Name name, int version);
    bool migrateToLatest(Name name);
    bool migrate_1_to_2(Name name);  // 当前 no-op (knot_progress 由 KnotService::ensureSchema 建)
    bool migrate_2_to_3(Name name);  // User 库 emergency_contacts 补 updated_at / is_deleted

    QHash<Name, QSqlDatabase> m_databases;
    QString m_dataPath;

    // 加密: V2+ 接 SQLCipher 时启用. 当前所有 db 用明文 SQLite.
    // 详见 doc/01-方案设计/04-三方依赖与版本清单.md §5.1
};

} // namespace outdoor
