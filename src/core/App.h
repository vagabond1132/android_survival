/**
 * @file App.h
 * @brief 应用程序主类
 * @details 全局单例，管理应用生命周期、初始化、关闭
 */

#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <memory>

namespace outdoor {

class Config;
class Database;
class ServiceRegistry;  // 2026-09-10: forward decl only, ServiceRegistry.h 不能在 App.h include
                       // 因为它链上触发 Qt 6.7 qobject.h 内 QDate/QUrl/QLocale type trait
                       // incomplete 错误. 14 个 service getter 移到 .cpp 实现.
class FirstAidService;
class EmergencyService;
class SpeciesService;
class PlantService;
class AnimalService;
class InsectService;
class MushroomService;
class FieldGuideHistory;
class SurvivalService;
class KnotService;
class TravelService;
class RouteService;
class ChecklistService;
class EquipmentService;
class MapService;
class PlatformInterface;

/**
 * @class App
 * @brief 应用程序主类（单例）
 * @details 2026-09-10: 14 个业务 service 所有权移交给 ServiceRegistry,
 *   App 保留 14 个 getter 委托给 m_services, 保持外部 API 兼容
 */
class App : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ isReady NOTIFY readyChanged)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString dataPath READ dataPath CONSTANT)

public:
    static App& instance();

    // 生命周期
    bool initialize();
    void shutdown();

    bool isReady() const { return m_ready; }
    QString version() const { return QString::fromLatin1(APP_VERSION); }
    QString dataPath() const;

    // 服务访问 (委托给 ServiceRegistry, .cpp 实现以避免 include 链)
    Config* config() const;
    Database* database() const { return m_database.get(); }
    ServiceRegistry* services() const { return m_services.get(); }
    FirstAidService* firstAid() const;
    EmergencyService* emergency() const;
    SpeciesService* species() const;
    PlantService* plants() const;
    AnimalService* animals() const;
    InsectService* insects() const;
    MushroomService* mushrooms() const;
    FieldGuideHistory* fieldGuideHistory() const;
    SurvivalService* survival() const;
    KnotService* knots() const;
    TravelService* travel() const;
    RouteService* routes() const;
    ChecklistService* checklist() const;
    EquipmentService* equipment() const;
    MapService* mapService() const;
    PlatformInterface* platform() const { return m_platform.get(); }

signals:
    void readyChanged();
    void initialized();
    void aboutToShutdown();

private:
    explicit App(QObject* parent = nullptr);
    ~App() override;

    bool initLogger();
    bool initConfig();
    bool initDatabase();
    bool initServices();
    bool initPlatform();
    bool initData();

    std::unique_ptr<Config> m_config;
    std::unique_ptr<Database> m_database;
    std::unique_ptr<ServiceRegistry> m_services;  // 2026-09-10: 接管 14 个 service 所有权
    std::unique_ptr<PlatformInterface> m_platform;
    bool m_ready = false;
};

} // namespace outdoor
