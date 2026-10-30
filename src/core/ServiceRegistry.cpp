/**
 * @file ServiceRegistry.cpp
 * @brief ServiceRegistry 实现
 */

#include "ServiceRegistry.h"
#include "Database.h"
#include "Logger.h"
#include "PathService.h"
#include "../platform/PlatformInterface.h"

// 2026-09-10: 实现需要完整 QQmlContext 定义 (调 setContextProperty).
// 在 .h 里只能 forward decl (避免 QUrl/QString/QVariant forward decl 引发 incomplete type).
// .cpp 是实现, 可以 include 完整头.
#include <QQmlContext>

#include "../lifesaver/FirstAidService.h"
#include "../lifesaver/EmergencyService.h"
#include "../species/SpeciesService.h"
#include "../species/PlantService.h"
#include "../species/AnimalService.h"
#include "../species/InsectService.h"
#include "../species/MushroomService.h"
#include "../species/FieldGuideHistory.h"
#include "../survival/SurvivalService.h"
#include "../knots/KnotService.h"
#include "../travel/TravelService.h"
#include "../routes/RouteService.h"
#include "../preparation/ChecklistService.h"
#include "../equipment/EquipmentService.h"
#include "../map/MapService.h"
#include "ImageFetcherService.h"  // 2026-09-19
#include "WeatherForecastService.h"  // 2026-10-28 (#154)
#include "CompassSensor.h"        // 2026-10-20: 丁骨架朝向来源

namespace outdoor {

ServiceRegistry::ServiceRegistry(QObject* parent) : QObject(parent) {}

ServiceRegistry::~ServiceRegistry() = default;

void ServiceRegistry::setDatabase(Database* db) { m_database = db; }
void ServiceRegistry::setPlatform(PlatformInterface* platform) { m_platform = platform; }

bool ServiceRegistry::initializeAll() {
    if (!m_database) {
        Logger::error("ServiceRegistry: database not set");
        return false;
    }

    // 救命链路 (P0): FirstAid + EmergencyService
    m_firstAid  = std::make_unique<FirstAidService>(m_database);
    m_emergency = std::make_unique<EmergencyService>(m_database, m_platform);

    // 危险物种 (P0)
    m_species     = std::make_unique<SpeciesService>(m_database);
    m_plants      = std::make_unique<PlantService>(m_database);
    m_animals     = std::make_unique<AnimalService>(m_database);
    m_insects     = std::make_unique<InsectService>(m_database);
    m_mushrooms   = std::make_unique<MushroomService>(m_database);

    // 生存技能 (P1)
    m_survival    = std::make_unique<SurvivalService>(m_database);
    m_knots       = std::make_unique<KnotService>(m_database);

    // 自驾游 (P2) - 不接 db
    m_travel      = std::make_unique<TravelService>();

    // V2 功能 (P2)
    m_fieldGuideHistory = std::make_unique<FieldGuideHistory>(m_database);
    m_routes     = std::make_unique<RouteService>(m_database);
    m_checklist  = std::make_unique<ChecklistService>(m_database);
    m_equipment  = std::make_unique<EquipmentService>();
    m_map        = std::make_unique<MapService>();

    // 2026-09-19: 运行时图册 (无 db 依赖)
    m_imageFetcher = std::make_unique<ImageFetcherService>();

    // 2026-10-28 (#154): 当前天气预报。必须在 m_equipment 之后构造并立刻喂基线 ——
    //   直减率/紫外线增量的真身在 climate_normals.json, 由装备侧解析, 预报服务不抄常量。
    //   基线没接上时预报只做"格点原样读数", 不做海拔修正 (宁可少修, 不可瞎修)。
    m_weather = std::make_unique<WeatherForecastService>();
    m_weather->setClimateBaseline(m_equipment.get());

    // 2026-10-20: 罗盘 (丁骨架 ①营地/⑤求助 的朝向来源). parent = this, 随本对象析构.
    m_compass = new CompassSensor(this);

    Logger::info("ServiceRegistry: 17 services + 1 compass constructed");
    return true;
}

bool ServiceRegistry::loadDataAll() {
    // 替代 App::initData: 各 service 独立加载, 失败不致命
    int failed = 0;
    auto tryLoad = [&failed](const char* name, bool ok) {
        if (!ok) {
            ++failed;
            Logger::warn(QString("loadData: %1 failed (continuing)").arg(name));
        }
    };
    tryLoad("species",   m_species->loadInitialData());
    tryLoad("plants",    m_plants->loadInitialData());
    tryLoad("animals",   m_animals->loadInitialData());
    tryLoad("insects",   m_insects->loadInitialData());
    tryLoad("mushrooms", m_mushrooms->loadInitialData());
    tryLoad("firstaid",  m_firstAid->loadInitialData());
    tryLoad("survival",  m_survival->loadInitialData());
    tryLoad("knots",     m_knots->loadInitialData());
    tryLoad("travel",    m_travel->loadInitialData());
    tryLoad("routes",    m_routes->loadInitialData());
    tryLoad("checklist", m_checklist->loadInitialData());
    // MapService 不需要 loadInitialData (地图数据来自用户)

    Logger::info(QString("ServiceRegistry::loadDataAll done, %1 failures").arg(failed));
    return true;  // 永远不阻塞启动, 跟之前 App::initData 行为一致
}

void ServiceRegistry::registerToQmlContext(QQmlContext* ctx) {
    if (!ctx) return;
    // 2026-09-11: 回滚到 setContextProperty. 之前改用 qmlRegisterSingletonInstance
    // 实测在 Qt 6.7.2 + qmlcachegen 静态编译模式下不工作, QML 端报
    // "ReferenceError: firstAidService is not defined" (app_log.txt 17:01-17:04).
    // 根因: qmlRegisterSingletonInstance 模板版本要求 QML 端 import 对应 module,
    // 但本项目 QML 文件用 import OutdoorSurvival 1.0 之后, 类型名查找走
    // qmldir 静态表, 不走 qmlRegisterSingletonInstance 运行时注册.
    // setContextProperty 是 setContextProperty 是老 API, 跨 Qt 版本稳定.
    // 显式 cast QObject* 避免 setContextProperty 重载歧义
    ctx->setContextProperty("firstAidService",      static_cast<QObject*>(m_firstAid.get()));
    ctx->setContextProperty("emergencyService",     static_cast<QObject*>(m_emergency.get()));
    ctx->setContextProperty("speciesService",       static_cast<QObject*>(m_species.get()));
    ctx->setContextProperty("plantService",         static_cast<QObject*>(m_plants.get()));
    ctx->setContextProperty("animalService",        static_cast<QObject*>(m_animals.get()));
    ctx->setContextProperty("insectService",        static_cast<QObject*>(m_insects.get()));
    ctx->setContextProperty("mushroomService",      static_cast<QObject*>(m_mushrooms.get()));
    ctx->setContextProperty("fieldGuideHistory",    static_cast<QObject*>(m_fieldGuideHistory.get()));
    ctx->setContextProperty("survivalService",      static_cast<QObject*>(m_survival.get()));
    ctx->setContextProperty("knotService",          static_cast<QObject*>(m_knots.get()));
    ctx->setContextProperty("travelService",        static_cast<QObject*>(m_travel.get()));
    ctx->setContextProperty("routeService",         static_cast<QObject*>(m_routes.get()));
    ctx->setContextProperty("checklistService",     static_cast<QObject*>(m_checklist.get()));
    ctx->setContextProperty("equipmentService",      static_cast<QObject*>(m_equipment.get()));
    ctx->setContextProperty("mapService",           static_cast<QObject*>(m_map.get()));
    // 2026-09-19: 图册获取 (QML 端用 imageFetcher.fetchImages / cachedImages)
    ctx->setContextProperty("imageFetcher",         static_cast<QObject*>(m_imageFetcher.get()));
    // 2026-10-28 (#154): 当前天气预报 (QML 端用 weatherService.refresh / forecastFor)
    ctx->setContextProperty("weatherService",       static_cast<QObject*>(m_weather.get()));
    // 2026-09-11: 注册 androidPlatform, 让 QML 端能调 takePhoto (P1 地图改版 3.26).
    ctx->setContextProperty("androidPlatform",      static_cast<QObject*>(m_platform));
    // 2026-10-20: 罗盘. ①营地方位盘 / ⑤求助读数 / 地图方向指针读同一个 heading.
    ctx->setContextProperty("compassSensor",        static_cast<QObject*>(m_compass));
    Logger::info("ServiceRegistry: 17 services + 1 platform + 1 compass registered to QML context");
}

} // namespace outdoor
