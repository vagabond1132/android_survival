/**
 * @file ServiceRegistry.h
 * @brief 统一管理 14 个业务 service + Database + Platform
 *
 * 设计要点 (2026-09-10 抽取):
 * 1. 替代 App god object: App 不再持有 14 个 unique_ptr<Service>, 改持 1 个 ServiceRegistry
 * 2. 加新 service 改 ServiceRegistry 一处, App.h 不动
 * 3. QML 注册统一遍历, 不再 main.cpp 写 14 行 setContextProperty
 * 4. initializeAll() 控制启动顺序, loadDataAll() 替代 App::initData
 */

#pragma once

#include <QObject>
#include <QString>
#include <QVariant>
#include <QUrl>
#include <QDateTime>
#include <QDate>
#include <QTime>
#include <QLocale>
#include <memory>

// 2026-09-10: forward decl QQmlContext (函数参数 ::QQmlContext* 用).
// 不能 #include <QQmlContext>, 会触发 Qt 6.7 QUrl/QLocale/QDate incomplete type
// (qobject.h 内部 type_traits 表达式依赖这些完整定义). pointer 参数 forward decl 够.
class QQmlContext;

// 2026-09-10: 必须 #include 完整头, 因为 m_xxx.get() 等 member access 需要完整类型
// (forward decl 不够, 之前 App.h 因此编不过)
#include "Database.h"
#include "../platform/PlatformInterface.h"

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
#include "ImageFetcherService.h"  // 2026-09-19: 运行时图册获取
#include "WeatherForecastService.h"  // 2026-10-28 (#154): 当前天气预报 (环境条件第 2 源)

// 2026-09-10: 不能 #include <QQmlContext>, 会强制引入 QUrl/QString/QVariant
// 的 forward decl 在 namespace 内, 触发 "incomplete type" 错误.
// 这里只需要前向声明, pointer 参数足够.
// 函数参数用 ::QQmlContext* 全局限定, 避开 outdoor namespace.

namespace outdoor {

// 2026-10-20: 罗盘只在前向声明 + 裸指针 (QObject parent 归本 registry 管),
// 因为 CompassSensor.h 要带 <QCompass>, 塞进这个被 QML 模块全域包含的头会引入
// QtSensors 的 incomplete-type 连锁 (同上面 QQmlContext 那条坑).
class CompassSensor;

class ServiceRegistry : public QObject {
    Q_OBJECT
public:
    explicit ServiceRegistry(QObject* parent = nullptr);
    ~ServiceRegistry();

    /** 注入 Database + Platform (由 App::initDatabase / initPlatform 调用) */
    void setDatabase(Database* db);
    void setPlatform(PlatformInterface* platform);

    /** 构造所有 service (按依赖顺序, 必须先 setDatabase + setPlatform) */
    bool initializeAll();

    /** 触发各 service 的 loadInitialData (替代 App::initData) */
    bool loadDataAll();

    /** 注册到 QML 上下文 (替代 main.cpp 14 行 setContextProperty) */
    void registerToQmlContext(::QQmlContext* ctx);

    // 类型安全 getter
    FirstAidService*    firstAid()    const { return m_firstAid.get(); }
    EmergencyService*   emergency()   const { return m_emergency.get(); }
    SpeciesService*     species()     const { return m_species.get(); }
    PlantService*       plants()      const { return m_plants.get(); }
    AnimalService*      animals()     const { return m_animals.get(); }
    InsectService*      insects()     const { return m_insects.get(); }
    MushroomService*    mushrooms()   const { return m_mushrooms.get(); }
    FieldGuideHistory*  fieldGuideHistory() const { return m_fieldGuideHistory.get(); }
    SurvivalService*    survival()    const { return m_survival.get(); }
    KnotService*        knots()       const { return m_knots.get(); }
    TravelService*      travel()      const { return m_travel.get(); }
    RouteService*       routes()      const { return m_routes.get(); }
    ChecklistService*   checklist()   const { return m_checklist.get(); }
    EquipmentService*    equipment()   const { return m_equipment.get(); }
    MapService*         mapService()  const { return m_map.get(); }
    ImageFetcherService* imageFetcher() const { return m_imageFetcher.get(); }  // 2026-09-19
    WeatherForecastService* weather() const { return m_weather.get(); }         // 2026-10-28 (#154)
    CompassSensor*       compass()      const { return m_compass; }             // 2026-10-20

private:
    Database* m_database = nullptr;
    PlatformInterface* m_platform = nullptr;

    std::unique_ptr<FirstAidService>   m_firstAid;
    std::unique_ptr<EmergencyService>  m_emergency;
    std::unique_ptr<SpeciesService>    m_species;
    std::unique_ptr<PlantService>      m_plants;
    std::unique_ptr<AnimalService>     m_animals;
    std::unique_ptr<InsectService>     m_insects;
    std::unique_ptr<MushroomService>   m_mushrooms;
    std::unique_ptr<FieldGuideHistory> m_fieldGuideHistory;
    std::unique_ptr<SurvivalService>   m_survival;
    std::unique_ptr<KnotService>       m_knots;
    std::unique_ptr<TravelService>     m_travel;
    std::unique_ptr<RouteService>      m_routes;
    std::unique_ptr<ChecklistService>  m_checklist;
    std::unique_ptr<EquipmentService>   m_equipment;
    std::unique_ptr<MapService>        m_map;
    std::unique_ptr<ImageFetcherService> m_imageFetcher;  // 2026-09-19
    std::unique_ptr<WeatherForecastService> m_weather;    // 2026-10-28 (#154)
    CompassSensor* m_compass = nullptr;  // 2026-10-20: QObject parent = this, 不 manual delete
};

} // namespace outdoor
