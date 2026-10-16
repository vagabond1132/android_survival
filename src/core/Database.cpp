/**
 * @file Database.cpp
 */

#include "Database.h"
#include "Logger.h"
#include "PathService.h"

#include <QDir>
#include <QStandardPaths>
#include <QSqlQuery>
#include <QSqlError>
#include <QFileInfo>

namespace outdoor {

Database::Database(QObject* parent) : QObject(parent) {}

Database::~Database() {
    close();
}

bool Database::open(const QString& dataPath) {
    m_dataPath = dataPath;
    QDir().mkpath(dataPath);

    // 2026-10-16: 文件名仍由 PathService::dbFileName 提供, 但目录使用调用方传入的
    //   dataPath (之前实现走 PathService::dbPath → AppDataLocation, 忽略 dataPath
    //   参数, 导致单测 QTemporaryDir 失效, 多个测试进程共享同一份真实 DB).
    //   生产环境 App::dataPath() 与 PathService::dataDir() 均解析到
    //   QStandardPaths::AppDataLocation, 行为保持不变.
    auto dbFile = [this](Name n) {
        return m_dataPath + "/" + PathService::dbFileName(static_cast<int>(n));
    };
    if (!openDatabase(Name::User, dbFile(Name::User))) return false;
    if (!openDatabase(Name::Settings, dbFile(Name::Settings))) return false;
    if (!openDatabase(Name::Species, dbFile(Name::Species))) return false;
    if (!openDatabase(Name::FirstAid, dbFile(Name::FirstAid))) return false;
    if (!openDatabase(Name::Survival, dbFile(Name::Survival))) return false;
    if (!openDatabase(Name::Routes, dbFile(Name::Routes))) return false;

    return migrate();
}

void Database::close() {
    // 2026-10-16: 之前只 removeDatabase(defaultConnection), 命名列 db_0..db_5 遗留在
    //   QSqlDatabase 全局池中, 下一次 open() 触发 "duplicate connection name" 警告,
    //   且旧的连接对象可能仍被引用, 使随后 SELECT 得到空结果 (test_database 曾因此挂).
    QStringList connNames;
    connNames.reserve(m_databases.size());
    for (auto it = m_databases.begin(); it != m_databases.end(); ++it) {
        connNames << it.value().connectionName();
        if (it.value().isOpen()) it.value().close();
    }
    m_databases.clear();
    for (const QString& n : connNames) {
        if (!n.isEmpty()) QSqlDatabase::removeDatabase(n);
    }
    QSqlDatabase::removeDatabase(QSqlDatabase::defaultConnection);
}

bool Database::openDatabase(Name name, const QString& filePath) {
    QString connName = QString("db_%1").arg(static_cast<int>(name));
    QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", connName);
    db.setDatabaseName(filePath);

    if (!db.open()) {
        Logger::error(QString("Failed to open DB %1: %2")
                          .arg(filePath)
                          .arg(db.lastError().text()));
        return false;
    }

    // 优化参数
    QSqlQuery q(db);
    q.exec("PRAGMA journal_mode = WAL");
    q.exec("PRAGMA synchronous = NORMAL");
    q.exec("PRAGMA foreign_keys = ON");
    q.exec("PRAGMA cache_size = 10000");

    m_databases[name] = db;
    Logger::info(QString("DB opened: %1").arg(filePath));
    return true;
}

QSqlDatabase Database::get(Name name) const {
    return m_databases.value(name);
}

bool Database::isOpen(Name name) const {
    return m_databases.contains(name) && m_databases.value(name).isOpen();
}

bool Database::migrate() {
    // 2026-09-21 阶段 J: PRAGMA user_version 机制完整化
    //   - 每个 db 文件存 PRAGMA user_version (SQLite 内置 64-bit 整数, 默认 0)
    //   - createSchema() 始终跑 (CREATE TABLE IF NOT EXISTS 幂等, 新 db 一上来 schema 完整)
    //   - migrateToLatest() 读 user_version, 跑 migrate_X_to_Y 链, 写新 user_version
    //   - 后续破坏性 schema 变更 (加表/加列/重命名) 加新私有方法 migrate_X_to_Y()
    //     并把 kCurrentSchemaVersion +1
    bool ok = true;
    for (auto it = m_databases.begin(); it != m_databases.end(); ++it) {
        if (it.value().isOpen()) {
            Name name = it.key();
            ok &= createSchema(name);
            ok &= migrateToLatest(name);
        }
    }
    Logger::info(QString("Database migrate %1 (target schema v%2)")
                     .arg(ok ? "OK" : "PARTIAL FAIL")
                     .arg(kCurrentSchemaVersion));
    return ok;
}

bool Database::createSchema(Name name) {
    if (!m_databases.contains(name) || !m_databases[name].isOpen()) {
        return false;
    }
    QSqlDatabase db = m_databases[name];
    QSqlQuery q(db);
    bool ok = true;

    auto exec = [&](const QString& sql) -> bool {
        if (!q.exec(sql)) {
            Logger::warn(QString("createSchema %1 fail: %2").arg((int)name).arg(q.lastError().text()));
            ok = false;
        }
        return true;
    };

    // 1. Species(明文) - 数据由 JSON 加载,这里不建表
    if (name == Name::Species) { return true; }
    // 2. FirstAid(明文) - 同上
    if (name == Name::FirstAid) { return true; }
    // 3. Survival(明文) - 同上
    if (name == Name::Survival) { return true; }
    // 4. Routes(明文) - 同上
    if (name == Name::Routes) { return true; }

    // 5. User(加密) - 紧急联系人 + 路线收藏 + 装备清单 + 装备检查进度
    if (name == Name::User) {
        exec("CREATE TABLE IF NOT EXISTS emergency_contacts ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "name TEXT NOT NULL, phone TEXT NOT NULL, "
             "relation TEXT, is_primary INTEGER DEFAULT 0, "
             "created_at TEXT)");
        exec("CREATE TABLE IF NOT EXISTS route_favorites ("
             "route_id TEXT NOT NULL, "
             "created_at TEXT, "
             "PRIMARY KEY(route_id))");
        // 2026-09-10 清理 4 死表:
        //   - travel_favorites / travel_visit_count: TravelService 不接 Database
        //   - equipment_lists / equipment_check_progress: EquipmentService 只用 QSettings
        // 删了. 未来要持久化时再加.
        exec("CREATE TABLE IF NOT EXISTS user_preferences ("
             "key TEXT PRIMARY KEY, value TEXT, updated_at TEXT)");
    }

    // 6. Settings(加密) - 应用设置
    if (name == Name::Settings) {
        exec("CREATE TABLE IF NOT EXISTS app_settings ("
             "key TEXT PRIMARY KEY, value TEXT, "
             "updated_at TEXT)");
        exec("CREATE TABLE IF NOT EXISTS track_records ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "route_id TEXT, started_at TEXT, ended_at TEXT, "
             "distance_km REAL, duration_hours REAL, "
             "points_json TEXT)");
        exec("CREATE TABLE IF NOT EXISTS recognition_history ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "image_path TEXT, result_json TEXT, "
             "category TEXT, confidence REAL, "
             "created_at TEXT)");
        // field_guide_history 表由 FieldGuideHistory::ensureSchema() 统一建 (字段更全),
        // 此处不再重复 CREATE (2026-09-10 清理)
        // 4 张物种位置表(地图联动)
        exec("CREATE TABLE IF NOT EXISTS plant_locations ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "plant_id TEXT NOT NULL, "
             "lat REAL, lon REAL, "
             "found_at TEXT, note TEXT, photo_path TEXT)");
        exec("CREATE INDEX IF NOT EXISTS idx_plant_loc_plant ON plant_locations(plant_id)");

        exec("CREATE TABLE IF NOT EXISTS animal_locations ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "animal_id TEXT NOT NULL, "
             "lat REAL, lon REAL, "
             "found_at TEXT, note TEXT, photo_path TEXT)");
        exec("CREATE INDEX IF NOT EXISTS idx_animal_loc_animal ON animal_locations(animal_id)");

        exec("CREATE TABLE IF NOT EXISTS insect_locations ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "insect_id TEXT NOT NULL, "
             "lat REAL, lon REAL, "
             "found_at TEXT, note TEXT, photo_path TEXT)");

        exec("CREATE TABLE IF NOT EXISTS mushroom_locations ("
             "id INTEGER PRIMARY KEY AUTOINCREMENT, "
             "mushroom_id TEXT NOT NULL, "
             "lat REAL, lon REAL, "
             "found_at TEXT, note TEXT, photo_path TEXT)");
        // 2026-09-21 阶段 J: knot_progress 表归 KnotService::ensureSchema() 拥有
        //   (它在 Survival db 建, 此处不再重复 — 之前 Settings db 里建了一份死表)
        exec("CREATE TABLE IF NOT EXISTS route_visit_count ("
             "route_id TEXT PRIMARY KEY, count INTEGER DEFAULT 0)");
        // 2026-09-10 清理: travel_visit_count 死表, 删
    }
    return ok;
}

int Database::currentVersion(Name name) const {
    if (!m_databases.contains(name) || !m_databases[name].isOpen()) return 0;
    QSqlQuery q(m_databases.value(name));
    if (!q.exec("PRAGMA user_version")) {
        // 新 db 读 user_version 偶尔会失败 (刚 open 没 schema), 视作 v0
        return 0;
    }
    if (q.next()) return q.value(0).toInt();
    return 0;
}

bool Database::setVersion(Name name, int version) {
    if (!m_databases.contains(name) || !m_databases[name].isOpen()) return false;
    QSqlQuery q(m_databases.value(name));
    // PRAGMA 不支持占位符, 直接拼整数 (version 是 int, 不是用户输入)
    if (!q.exec(QString("PRAGMA user_version = %1").arg(version))) {
        Logger::warn(QString("setVersion(%1, v%2) failed: %3")
                         .arg((int)name).arg(version).arg(q.lastError().text()));
        return false;
    }
    return true;
}

bool Database::migrateToLatest(Name name) {
    int v = currentVersion(name);
    if (v >= kCurrentSchemaVersion) {
        return true;  // 已是最新, 跳过
    }
    Logger::info(QString("DB %1 schema migrate: v%2 -> v%3")
                     .arg((int)name).arg(v).arg(kCurrentSchemaVersion));

    bool ok = true;
    // 按版本号顺序串行跑迁移. 每个 if (v < N) 分支只跑一次.
    if (v < 2) {
        ok &= migrate_1_to_2(name);
    }
    // v < 3 时加: if (v < 3) ok &= migrate_2_to_3(name);

    if (ok) ok &= setVersion(name, kCurrentSchemaVersion);
    return ok;
}

bool Database::migrate_1_to_2(Name name) {
    // v1 -> v2: 加 knot_progress 表 (KnotService V1→V2 数据迁移用)
    // 实际 schema 由 KnotService::ensureSchema() 在 Survival db 建, 幂等.
    // 这里仅记日志, 因为如果用户从 v1 升到 v2 但没启动过 KnotService,
    // 表还不存在, KnotService 第一次 loadInitialData() 会建好.
    Q_UNUSED(name);
    Logger::info("migrate_1_to_2: knot_progress table owned by KnotService::ensureSchema()");
    return true;
}

} // namespace outdoor
