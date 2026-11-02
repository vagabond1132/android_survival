cmake_minimum_required(VERSION 3.22)
project(OutdoorSurvival
    VERSION 0.0.4
    DESCRIPTION "荒野手册 - 中国户外生存离线助手"
    LANGUAGES CXX
)

# ============================================================================
# 文件编码规范 (2026-09-10)
#   - 所有源文件 (.cpp/.h/.qml/.xml/.json/.gradle/.java) 必须 UTF-8 (no BOM)
#   - Windows 工具 (Qt Creator / VS) 默认会按系统区域 (GBK) 存盘, 改项目前
#     先在 IDE 里设 "File Encoding = UTF-8"
#   - 验证脚本: scripts/check_utf8.sh (无 GBK 文件时全 pass)
#   - 转码命令 (GBK → UTF-8): iconv -f GBK -t UTF-8 input > output
#   - Qt 6.7 在 Android 上对 .qml 编码宽容 (GBK/UTF-8 都能跑), 但 QML 编译器
#     (qmlcachegen) 在 release 模式只接受 UTF-8, 混 GBK 可能在 qmlcache 阶段
#     报 "expected token" 而非 "Encoding error" (run.txt 启动卡死很难定位)
# ============================================================================

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# ccache: 加速 C++ 增量编译, 重配置时仍能命中缓存
# 仅在找到 ccache 时启用, 不影响其他环境
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" CACHE STRING "C++ compiler launcher")
    message(STATUS "ccache enabled: ${CCACHE_PROGRAM}")
endif()

# ============================================================================
# 全局编译选项
# ============================================================================
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic -Wno-gnu-zero-variadic-macro-arguments -fvisibility=hidden")
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -ffunction-sections -fdata-sections")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} -Wl,--gc-sections -Wl,--strip-all")

if(ANDROID)
    add_definitions(-DOS_PLATFORM_ANDROID=1)
    # 注:暂不开启 QT_NO_CAST_FROM_ASCII,等所有代码迁移到 QStringLiteral 后再开
    # add_definitions(-DQT_NO_CAST_FROM_ASCII)
    add_definitions(-DANDROID)
endif()

# ============================================================================
# 应用元数据
# ============================================================================
set(APP_NAME "OutdoorSurvival")
set(APP_DISPLAY_NAME "荒野手册")
set(APP_PACKAGE_NAME "com.outdoor.survival")
set(APP_VERSION "${PROJECT_VERSION}")
set(APP_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
set(APP_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
set(APP_VERSION_PATCH "${PROJECT_VERSION_PATCH}")
set(APP_VERSION_CODE 4)  # 用于商店版本号（每次发版递增）
                         # 2026-10-26: 这里以前停在 1, 而真正装到机器上的 versionCode 由
                         # android/app/build.gradle 决定 (build_apk.sh 会用仓库里那份覆盖
                         # android-build/app/build.gradle), gradle 已经是 2。两边不同值不会
                         # 让包出错, 但从模板 manifest 走的那条路会出 1 —— 对齐掉, 别留两份。
set(APP_MIN_SDK_VERSION 24)
set(APP_TARGET_SDK_VERSION 34)

# ============================================================================
# Qt 模块
# ============================================================================
find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Multimedia
    Location
    Positioning
    Sensors
    Sql
    Network
    Concurrent
    Xml
)
# 2026-10-26 任务 #121 A25: 删除 Charts.
#   它只被 TrackDetailPage 的两条曲线用, 而 QtCharts 创建 QChart 时要建图内标题
#   (widgets 栈里的 QGraphicsTextItem), 本工程 main.cpp 只跑 QGuiApplication, 没有
#   widget style → 真机一进轨迹分析页必崩 (8 份 dump 同一栈, 见 LineProfile.qml 头).
#   曲线改 Canvas 自绘, 本目标也不再链 libQt6Charts / libQt6Widgets
#   (2026-10-26 核过 build/release_arm64-v8a/.../link.txt: 两者都没了).
#   ⚠ 但 APK 体积没因此变小: build_apk.sh 会把整个 Qt kit 的 libQt6*.so 无差别
#   cp 进 jniLibs (见其 1059 行起, 当初是为了堵"缺 .so → 启动二次崩溃"), 所以
#   libQt6Charts/Widgets 还躺在包里, 只是没人 dlopen 它. 要真删得单独改打包白名单
#   并在真机验启动, 别顺手在这里加裁剪. 以后要图表请继续走自绘, 不要引回 Charts.

qt_standard_project_setup(REQUIRES 6.5)

# ============================================================================
# 第三方库
# ============================================================================
# 2026-09-10: 删 THIRD_PARTY_DIR, 上一节 SQLCipher/spdlog/json 三段死代码已清.
# OpenCV 用 find_package QUIET 走系统包, 不需 third_party 目录.


# OpenCV（图像处理）
# find_package QUIET 允许开发机装了 OpenCV 时自动开启, 装不上就 OFF (默认).
# 已删除: SQLCipher / spdlog / nlohmann/json 三段 (2026-09-10)
#   原因: third_party/ 目录不存在, 三个 if(USE_*) 分支永远不命中, 是死代码.
#   如未来需要, 重新添加并补上 third_party/ 目录.
set(USE_OPENCV OFF)
find_package(OpenCV 4.5 QUIET COMPONENTS core imgproc imgcodecs)
if(OpenCV_FOUND)
    set(USE_OPENCV ON)
endif()

# ============================================================================
# 源文件 (阶段 I-2: group 变量化拆分, 各业务目录独立维护)
# ============================================================================
set(ENTRY_SOURCES
    # 主入口
    src/main.cpp
)

set(CORE_SOURCES
    # 核心
    src/core/App.cpp
    src/core/AssetLoader.cpp
    src/core/Config.cpp
    src/core/Database.cpp
    src/core/Logger.cpp
    src/core/PathService.cpp
    src/core/ServiceRegistry.cpp
    # 2026-09-14: P0 图鉴拍照真匹配 - Qt 网格采样提取主色 HSV
    src/core/ImageColorExtractor.cpp
    # CommonOptions: 颜色 token + 下拉选项 + 格式化. 2026-09-11 漏加导致 vtable 缺失
    src/core/CommonOptions.cpp
    # 2026-09-19: 运行时图册获取 (Wikimedia Commons + 本地缓存)
    src/core/ImageFetcherService.cpp
    # 2026-10-20: 电子罗盘 (丁骨架 ①营地/⑤求助 的朝向来源, QtSensors QCompass)
    src/core/CompassSensor.cpp
    # 2026-10-28 (#154): 当前天气预报 (open-meteo 日预报 → 装备引擎的天气键).
    #   2026-09-11 那种"漏加 .cpp 导致 vtable 缺失"的事故就出在头里有 Q_OBJECT 而实现没进
    #   CORE_SOURCES, 这里一次把 .cpp 列上。
    src/core/WeatherForecastService.cpp
)

set(COMMON_SOURCES
    # 2026-09-20: 5 阶段架构重构 Phase 2 - 统一 SQL DDL/DML/SELECT 工具
    src/common/DbHelper.cpp
    # 2026-09-21: 阶段 L5.1 - QSettings 封装
    src/common/SettingsStore.cpp
    # 2026-10-29 (#168 A44): 轨迹统计唯一定口径 (stopTrack 与 getTrackStats 共用)
    src/common/TrackMetrics.cpp
)

set(LIFESAVER_SOURCES
    # 救命链路 (P0): SOS 拨号 + 紧急联系人 + 急救条目 (决策树由 FirstAidService 提供)
    src/lifesaver/FirstAidService.cpp
    src/lifesaver/EmergencyService.cpp
)

set(SPECIES_SOURCES
    # 危险物种 (P0)
    src/species/SpeciesService.cpp
    src/species/FieldGuideIndex.cpp
    src/species/PlantService.cpp
    src/species/AnimalService.cpp
    src/species/InsectService.cpp
    src/species/MushroomService.cpp
    src/species/SpeciesLocationRepository.cpp  # 2026-09-21 阶段 L4.2: 从 LocationStorageHelper 改名
    src/species/SpeciesLocationOps.cpp        # 2026-09-21 阶段 L4.2: 协调层, 4 service 复用
    src/species/FieldGuideHistory.cpp
)

set(SURVIVAL_SOURCES
    # 避险 (P1): 生存技能 (SurvivalService) + 绳结 (KnotService)
    #   阶段 I-5: 两个单文件目录, 各自独立业务边界清晰, 不合并
    src/survival/SurvivalService.cpp
    src/knots/KnotService.cpp
)

set(ROUTES_SOURCES
    # 路线 (P2): 自驾路线 (RouteService)
    #   阶段 I-5: 单文件目录, 与 travel/ 各自独立
    src/routes/RouteService.cpp
)

set(PREPARATION_SOURCES
    # 应急储备 (P2)
    src/preparation/ChecklistService.cpp
)

set(EQUIPMENT_SOURCES
    # 智能装备 (P0+P1) - 阶段 I-3: EquipmentEngine → EquipmentService 改名
    src/equipment/EquipmentService.cpp
    # 2026-09-20: 5 阶段架构重构 Phase 3 - 装备规则策略模式 (RuleConditionStrategy + Factory)
    src/equipment/RuleConditionFactory.cpp
)

set(MAP_SOURCES
    # 地图服务 (P2)
    # 2026-09-21 阶段 L5.4: 1803 行拆 4 文件, 仍同 class, 0 QML 改动
    src/map/MapService.cpp            # core: ctor/dtor/init/base map/altitude/format helper
    src/map/MapService_photos.cpp     # extractExif + 照片 CRUD
    src/map/MapService_tracks.cpp     # 轨迹 CRUD + GPX/KML/CSV 导入导出
    src/map/MapService_species.cpp    # 物种位置 + 通用 stats + 轨迹分析 (getTrackStats/Profile)
)

set(TRAVEL_SOURCES
    # 自驾游 (P2): 自驾游攻略 (TravelService)
    #   阶段 I-5: 单文件目录, 与 routes/ 各自独立
    src/travel/TravelService.cpp
)

set(PLATFORM_SOURCES
    # 平台适配
    src/platform/PlatformInterface.cpp
    src/platform/AndroidPlatform.cpp
    # 2026-10-28 (#148): 本机轨迹文件扫描 (纯 Qt, 桌面单测同源直编)
    src/platform/FileScanner.cpp
)

# 合并到 APP_SOURCES (保持原有 set 变量供下游引用, 不破坏调用方)
set(APP_SOURCES
    ${ENTRY_SOURCES}
    ${CORE_SOURCES}
    ${COMMON_SOURCES}
    ${LIFESAVER_SOURCES}
    ${SPECIES_SOURCES}
    ${SURVIVAL_SOURCES}
    ${ROUTES_SOURCES}
    ${PREPARATION_SOURCES}
    ${EQUIPMENT_SOURCES}
    ${MAP_SOURCES}
    ${TRAVEL_SOURCES}
    ${PLATFORM_SOURCES}
)

set(APP_HEADERS
    # 核心
    src/core/App.h
    src/core/AssetLoader.h
    src/core/Config.h
    src/core/Logger.h
    src/core/Database.h
    src/core/PathService.h
    src/core/ServiceRegistry.h
    src/core/ImageColorExtractor.h
    src/core/ImageFetcherService.h
    # 2026-10-20: 罗盘封装 (QCompass)
    src/core/CompassSensor.h
    # 2026-10-28 (#154): 天气预报服务头 (有 Q_OBJECT, 漏进本列表 AUTOMOC 不生成 moc → 链接期 vtable 缺失)
    src/core/WeatherForecastService.h
    # 2026-09-21 阶段 L2: Service 基类 (12 service 继承)
    src/common/ServiceBase.h
    # 2026-09-21 阶段 L4.2: Repository 接口
    src/common/Repository.h
    # 2026-09-21 阶段 L5.1: QSettings 封装
    src/common/SettingsStore.h
    # 2026-09-21 阶段 L5.2: CRUD 模板
    src/common/QueryTemplate.h
    # 2026-10-21 (#18 C3): 海拔段位唯一定义 (原先 MapService 5 段 / EquipmentService 7 段两份)
    src/common/AltitudeLevel.h

    # 救命链路 (P0)
    src/lifesaver/FirstAidService.h
    src/lifesaver/EmergencyService.h

    # 危险物种 (P0)
    src/species/SpeciesService.h
    src/species/FieldGuideIndex.h
    src/species/PlantService.h
    src/species/AnimalService.h
    src/species/InsectService.h
    src/species/MushroomService.h
    src/species/SpeciesLocationRepository.h  # 2026-09-21 阶段 L4.2: 从 LocationStorageHelper 改名
    src/species/SpeciesLocationOps.h          # 2026-09-21 阶段 L4.2: 协调层
    src/species/FieldGuideHistory.h

    # 避险 (P1)
    src/survival/SurvivalService.h
    src/knots/KnotService.h

    # 路线 (P2)
    src/routes/RouteService.h

    # 应急储备 (P2)
    src/preparation/ChecklistService.h

    # 智能装备 (P0+P1) - 阶段 I-3: EquipmentEngine → EquipmentService 改名
    src/equipment/EquipmentService.h

    # 地图服务 (P2)
    src/map/MapService.h

    # 自驾游 (P2)
    src/travel/TravelService.h

    # 平台适配
    src/platform/PlatformInterface.h
    src/platform/AndroidPlatform.h
    src/platform/FileScanner.h
)

# ============================================================================
# 可执行目标
# ============================================================================
qt_add_executable(${APP_NAME}
    ${APP_SOURCES}
    ${APP_HEADERS}
)

# 关键: Qt 6.7 必须在 qt_add_executable 之后立即设包名, 否则 deployment template
# 会硬编码 org.qtproject.example.<URI>, 导致 APK 包名错配 → 资源/QML/so 加载失败
# ANDROID_PACKAGE_SOURCE_DIR 必须设置, 否则 android/res/values/strings.xml 等资源
# 不会被编译进 APK, 导致 app_name 等字符串为空
set_target_properties(${APP_NAME} PROPERTIES
    QT_ANDROID_PACKAGE_NAME "${APP_PACKAGE_NAME}"
    QT_ANDROID_VERSION_NAME "${APP_VERSION}"
    QT_ANDROID_VERSION_CODE ${APP_VERSION_CODE}
    QT_ANDROID_MIN_SDK_VERSION ${APP_MIN_SDK_VERSION}
    QT_ANDROID_TARGET_SDK_VERSION ${APP_TARGET_SDK_VERSION}
    ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android"
    # 关键: MANUAL_FINALIZATION 模式下, 必须显式给目标设 ANDROID_ABIS,
    # 否则 qt_finalize_target() 报 "The list of Android ABIs is empty"
    # (Qt 6.7 默认 qt_add_executable 会自动从工具链推导 ABIs, 但 MANUAL_FINALIZATION
    # 关掉了自动 finalize, 也连带跳过了 ABI 推导, 需手动 set)
    ANDROID_ABIS "arm64-v8a;armeabi-v7a;x86_64"
)

# QML 模块
# 关键: 不要加 NO_RESOURCE_TARGET_PATH, 否则 qmldir 找不到 → QML 静默失败
# 默认 qml 走 qrc:/qt/qml/OutdoorSurvival/ 路径, Qt 6 期望的路径
qt_add_qml_module(${APP_NAME}
    URI OutdoorSurvival
    VERSION 1.0
    QML_FILES
        # 入口
        qml/Main.qml

        # 页面 (主目录 qml/pages/)
        qml/pages/HomePage.qml
        qml/pages/FirstAidPage.qml
        qml/pages/FirstAidDetailPage.qml
        qml/pages/FirstAidDecisionPage.qml
        qml/pages/SOSPage.qml
        qml/pages/EmergencyContactsPage.qml
        qml/pages/DangerSpeciesPage.qml
        qml/pages/FieldGuidePage.qml
        qml/pages/FieldGuideDetailPage.qml
        qml/pages/FieldGuideImagePickPage.qml
        # 2026-10-20 #60: SpeciesDetailPage.qml 已删, danger_species 库的详情走
        #   FieldGuideDetailPage (同一 ③ 版式, speciesId 入参).
        qml/pages/SurvivalPage.qml
        qml/pages/SurvivalDetailPage.qml
        qml/pages/KnotPage.qml
        qml/pages/KnotDetailPage.qml
        qml/pages/RouteListPage.qml
        qml/pages/RouteDetailPage.qml
        # 2026-09-30: 路线详情「查看装备」改为进本页 (按所选时节生成可勾选清单),
        #   不再直接跳 EquipmentPage 表单. 未注册则 qmldir 不含 → push 时 module not found 崩.
        qml/pages/RouteGearRecommendPage.qml
        qml/pages/ChecklistPage.qml
        qml/pages/TravelListPage.qml
        qml/pages/TravelDetailPage.qml
        # 之前缺漏 (6 个): MapPage / ResultPage / EquipmentPage / EquipmentDetailPage /
        # CategorySection / MapToolButton. 缺则 qmlcache 跳过, qmldir 不含, 运行时
        # import 报 "module not found" → 跳到这些页直接崩
        # 2026-09-20: ResultPage 是僵尸 (Main.qml 用 inline searchResults ListView,
        #   全 qml 无引用), 删除避免误导新人
        # 2026-10-21 #65 全站孤儿清扫: 上面那批里 CategorySection / MapToolButton 与
        #   下面这些也都已无任何引用方, 一并删除 ——
        #   ChecklistDetailPage (④ 勾选动作面早就并到 ChecklistPage),
        #   CameraPage (占位页, 拍照实际走 RecordTab 的 requestTakePhoto),
        #   HomePageComponents/HomeEntry, FieldGuidePageComponents/SpeciesServiceRegistry
        #   (②③ 改版后各自在页内自己列 service),
        #   components/base/{FunctionEntry,InfoItem,PageHeader,ServiceListModel,Hero}
        #   (图版头 150px + 读数带取代 hero/pageheader; 列表行就地画;
        #    四个列表页都改成一次拉全库本地分桶, 不再要 notifier 注入).
        #   判据与复查脚本见 doc/08-索引与概览/全代码索引.md 的 QML 可达性一节.
        qml/pages/MapPage.qml
        qml/pages/EquipmentPage.qml
        qml/pages/EquipmentDetailPage.qml
        # 2026-09-14: P1 轨迹分析详情页 (海拔/速度曲线 + 8 项统计 + 分段 + 卡路里 + 休息点)
        qml/pages/TrackDetailPage.qml

        # 通用组件 (qml/components/base/) - 阶段 I-1 拆分
        # 纯通用, 无业务字段, 任何 page 复用
        qml/components/base/Section.qml
        # 2026-10-16 整体改版: 章节标题行 (IconLabel + 文字), 替代 "图标+中文" 混写
        qml/components/base/SectionTitle.qml
        # 2026-09-28: StatCard.qml 已删 (问题4 删首页「关键统计」行后无使用方, 成孤儿组件)
        # 2026-10-16: CategoryChip / DifficultyChip / DetailLoader 已删
        #   (重构 Phase 3 建的通用组件, 全站 0 引用, 各页一直自己画 chip)
        qml/components/base/DangerChip.qml
        # 2026-09-14: Material Icons 字体图标组件 (依赖 assets/fonts/MaterialIcons-Regular.ttf)
        qml/components/base/IconLabel.qml
        qml/components/base/FilterRow.qml
        # 2026-10-19 整体改版: 页面骨架组件 (截图 1-6.jpg 里各页手抄 hero/卡片/
        #   列表行导致高度档位混乱、副标题溢出屏幕、按钮文案被截断).
        #   2026-10-21: Hero 随 TrackDetailPage 上 v9 图版头后 0 引用, 已删;
        #   二级页的头部现在一律是页内 150px colorSurfaceDim 图版头 + 四格读数带.
        qml/components/base/Card.qml
        qml/components/base/ListRow.qml
        qml/components/base/Chip.qml
        qml/components/base/StatTile.qml
        qml/components/base/PrimaryButton.qml
        qml/components/base/EmptyState.qml
        # 2026-09-20: 5 阶段架构重构 Phase 3 - 设计模式 + QML 公共组件
        # - Toast.qml 通用 (2026-10-21: ServiceListModel 0 引用已删, 列表页改为
        #   一次 getFiltered 拉全库再本地分桶)
        # - Styles.qml 间距/字号/圆角 设计 token (Singleton)
        qml/components/base/Toast.qml
        qml/components/base/Styles.qml
        # 2026-10-20 「地物图例」丁骨架共用件 (底色方案 A 已锁定)
        #   DuoRule 双线 / Plate 图鉴编号角标
        #   BearingCell 50px 方位列 / PositionReadout 墨底仪表 (①营地与⑤求助共用)
        #   Dial 野外方位盘 / NavBands 底部 5 方位带导航
        # 2026-10-21: RegMarks (套准角标) 移出构建 —— 全站 0 处实例化, 已评审的
        #   v8/v9 mock 里也没有四角墨线. 纯装饰且没有设计出处 → 不留死文件.
        #   文件搬到 _scratch_debug/qml_quarantine/RegMarks.qml.unused-20261021 (它从未入过 git, 删了就找不回).
        qml/components/base/DuoRule.qml
        qml/components/base/Plate.qml
        qml/components/base/BearingCell.qml
        qml/components/base/PositionReadout.qml
        qml/components/base/Dial.qml
        qml/components/base/NavBands.qml
        # ②图鉴的类目占比环 (Canvas 弧段, 与 Dial 同一条画法)
        qml/components/base/CategoryRing.qml
        # ③详情的方位条 (0-360 横向刻度带, 与类目环同一套 Canvas 自绘)
        qml/components/base/BearingBar.qml
        # ⑤求助的号码/SOS 入口: 长按 2 秒进度条确认, 顶掉原来的 tap-to-dial
        qml/components/base/HoldConfirmRow.qml
        # 直角空心次级按钮 (32px 高), 与场卡同一套角; 主按钮仍是 PrimaryButton
        qml/components/base/OutlineButton.qml
        # 2026-10-26 按钮体系定稿: ActionButton 是母版 (色口 + 文案 + 附注 + 按压态),
        #   PrimaryButton / OutlineButton 已改成它的两个默认档; DialogFooter 是弹层
        #   按钮排 (自带顶线与内距, 修掉 footer 不吃 Dialog.padding 的老根因).
        qml/components/base/ActionButton.qml
        qml/components/base/DialogFooter.qml
        # 行内小方块动作 (分析/摘线/删除): 原来是 MapPage 的裸 Button、NavigationTab 的
        # Rectangle+MouseArea、FieldGuideDetailPage 的 Rectangle+TapHandler 三份写法.
        qml/components/base/IconActionCell.qml
        # 危险提示卡的 6px 斜纹边记 (③绳结详情的"常见错误" / 装备清单的"缺 N 项必备")
        qml/components/base/HazardBand.qml
        # 清单行的 15px 方角勾选块 (整行可点, 不用 Controls CheckBox)
        qml/components/base/CheckTick.qml
        # 档位梯 (绳结难度 3 格 / 野外生活难度 5 格 / 急救紧急度 5 格)
        qml/components/base/Ladder.qml
        # 距离-数值 折线剖面 (轨迹分析的海拔/速度两条曲线) —— 取代 QtCharts, 见 #121 A25
        qml/components/base/LineProfile.qml
        # 第 5 格「我」的根页 (装备/标注/收藏/轨迹/联系人/设置 入口)
        qml/pages/MePage.qml

        # 业务组件 (qml/pages/<XxxPageComponents>/) - 阶段 I-1 下放
        # 业务专属, 引用具体 context property (equipmentService 等)
        # 2026-10-20: qml/pages/SOSPageComponents/ (SOSButton + QuickCallButton) 已删.
        #   QuickCallButton 是 tap-to-dial, ⑤改版后全站拨号统一走 HoldConfirmRow 长按门;
        #   SOSButton 早在 Main.qml 移除顶层 SOS 圆盘时就没人引用了. 号码入口现在共用
        #   qml/components/base/HoldConfirmRow.qml (上面已列).
        # 2026-10-21 #65: HomePageComponents/HomeEntry, MapPageComponents/MapToolButton,
        #   EquipmentPageComponents/CategorySection, FieldGuidePageComponents/
        #   SpeciesServiceRegistry 四个业务组件 0 引用, 已删 (①营地与④地图改版后
        #   行与按钮都在页内就地画; service 调度也收进各自页面). 本目录剩下的组件
        #   都还在 MapPageComponents/ 里被 MapPage 直接实例化.

        # 地图跨页组件 (qml/components/MapOverlay/) - 保留, 跨页复用
        # 2026-10-20 #61: DirectionCompassOverlay / MapRightButtonColumn 随 ④地图 改版
        #   删除 (迷你盘叠在图上 + 浮卡取代了两块旧浮层), 新增 MapInstrumentOverlay.
        qml/components/MapOverlay/MapInstrumentOverlay.qml
        qml/components/MapOverlay/MapBottomSheet.qml
        qml/components/MapOverlay/RouteSummaryPanel.qml  # 2026-09-15: 概览面板
        # 2026-10-28 #156: 工作台两档改版共用件 —— 面板头 (标题+读数+搜索+收起) 与
        #   底部动作带. 四个 Tab 各画一遍正是 pass6 收口点过的"同一形状五处"的坑.
        qml/components/MapOverlay/SheetPanelHead.qml
        qml/components/MapOverlay/SheetActionBand.qml

        # MapPage 专属组件
        qml/pages/MapPageComponents/RecordTab.qml
        qml/pages/MapPageComponents/NavigationTab.qml
        qml/pages/MapPageComponents/NearbyTab.qml
        qml/pages/MapPageComponents/SearchTab.qml

    RESOURCES
        assets/data/firstaid_entries.json
        assets/data/field_guide_plants.json
        assets/data/field_guide_animals.json
        assets/data/field_guide_insects.json
        assets/data/field_guide_mushrooms.json
        assets/data/danger_species.json
        assets/data/survival_items.json
        assets/data/knots.json
        assets/data/routes.json
        assets/data/checklists.json
        assets/data/travel.json
        # equipment_* 被 EquipmentService 通过 :// 路径读取, 缺则模块全空
        assets/data/equipment_base.json
        assets/data/equipment_rules.json
        # 2026-10-22: 省×月往年天气 (装备清单"按路线自动填天气")
        assets/data/climate_normals.json
        # 2026-09-14: Material Icons 字体 (Google 官方, ~228KB)
        assets/fonts/MaterialIcons-Regular.ttf
)

# ============================================================================
# 链接库
# ============================================================================
set(APP_LIBRARIES
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    Qt6::Location
    Qt6::Positioning
    Qt6::Sensors
    Qt6::Sql
    Qt6::Network
    Qt6::Concurrent
    Qt6::Xml
)

if(USE_OPENCV)
    list(APPEND APP_LIBRARIES
        opencv_core
        opencv_imgproc
        opencv_imgcodecs)
endif()

# 已删除: USE_SQLCIPHER / USE_SPDLOG / USE_JSON 三个 if 块 (2026-09-10)
#   原因: 上面 find_package/EXISTS 检测段已删除, 对应链接逻辑也应删除.
#   上方 set(THIRD_PARTY_DIR ...) 也已删 (没人用了).

target_link_libraries(${APP_NAME} PRIVATE ${APP_LIBRARIES})

# 注: 不再手动调 qt_finalize_target, 因为 qt_add_executable 已默认 finalize
# (Qt 6.5+). 手动调会触发 'Tried to call qt6_finalize_target twice' 警告.
# MANUAL_FINALIZATION 关掉自动 finalize 后, 会连带导致 Android Java 模板
# (QtActivity / QtApplication / QtService 等) 不被生成, 启动时 ClassNotFoundException.
# 解决: 让 qt_add_executable 默认 finalize, 自动生成 java 模板.

# 关键: Qt 6.5+ 必须调用 qt_finalize_target() 让 target properties (包名, SDK 版本等) 真正生效
# 否则 androiddeployqt 用的还是模板硬编码值.
# 注意: 默认 qt_add_executable 会自动 finalize, 重复调用会触发 Qt 6.7 警告:
#   "Tried to call qt6_finalize_target twice"
# 解决: 改用 MANUAL_FINALIZATION, 让下面的 qt_finalize_target 唯一生效.
# qt_finalize_target(${APP_NAME})

# ============================================================================
# Android 特定配置
# ============================================================================
if(ANDROID)
    target_link_libraries(${APP_NAME} PRIVATE
        android
        log
    )
    # Android 元数据已经在 qt_add_executable 之后立即设置过了 (避免 Qt 6.7
    # 模板硬编码 org.qtproject.example.<URI>), 这里不再重复, 避免覆盖

    # -----------------------------------------------------------------------
    # OpenSSL 3.x for Android
    # -----------------------------------------------------------------------
    # 问题: 地图白底 / 所有 Qt HTTPS 请求静默失败.
    #
    # 根因 (证据来自本项目的 CMakeCache + 插件二进制):
    #   - CMakeCache: QT_FEATURE_openssl_linked=OFF, QT_FEATURE_opensslv30=ON
    #     → Qt 自身**不**链接 OpenSSL, 而是由 libplugins_tls_qopensslbackend_<abi>.so
    #       在运行期用 QLibrary(dlopen) 按 glob "libssl.*" / "libcrypto.*" 去找
    #       一个 3.x 版 OpenSSL.
    #   - 之前 APK 的 lib/<abi>/ 下没有 libcrypto/libssl
    #     → dlopen 必失败 → QSslSocket 无法初始化 → HTTPS 全灭
    #       (MapPage 地图瓦片 + src/core/ImageFetcherService.cpp 的 https 请求).
    #
    # 依赖: 随仓库携带 third_party/android_openssl/ssl_3/<abi>/
    #   已用 ELF 校验 (arm64-v8a): AArch64 + "OpenSSL 3.1.8" +
    #   OSSL_PROVIDER_load / EVP_MD_fetch (3.x 专属符号).
    #   文件名 libcrypto_3.so / libssl_3.so 中的后缀 _3 是 Qt 6.x Android 官方
    #   约定 (ANDROID_OPENSSL_SUFFIX), **不可改名**, 否则 glob 匹配不到.
    #
    # 注入方式: QT_ANDROID_EXTRA_LIBS (Qt 6 target property)
    #   → 写进 android-<target>-deployment-settings.json 的 "extraLibs"
    #   → androiddeployqt 复制到 android-build/libs/<abi>/
    #   → build_apk.sh 的 androiddeployqt 输出段已全量 cp *.so 到 jniLibs/<abi>/
    #   → 最终进 APK 的 lib/<abi>/, 供运行期 dlopen.
    #
    # 注意: 必须给**绝对路径**. androiddeployqt 解析相对路径时以构建目录为基准,
    #       会找不到. 这里用 CMAKE_CURRENT_SOURCE_DIR 拼绝对路径.
    # -----------------------------------------------------------------------
    set(_ossl_dir "${CMAKE_CURRENT_SOURCE_DIR}/third_party/android_openssl/ssl_3/${ANDROID_ABI}")
    if(EXISTS "${_ossl_dir}/libcrypto_3.so" AND EXISTS "${_ossl_dir}/libssl_3.so")
        # 只登记部署, 不 target_link_libraries 到 app 上.
        # 原因: 插件是运行期 dlopen, app 不需要 DT_NEEDED 依赖; 若硬链进去,
        #       万一部署环节出岔, app 启动就会 UnsatisfiedLinkError 崩溃,
        #       比"只是 HTTPS 不可用"后果更重. 保持最小耦合.
        set_target_properties(${APP_NAME} PROPERTIES
            QT_ANDROID_EXTRA_LIBS "${_ossl_dir}/libcrypto_3.so;${_ossl_dir}/libssl_3.so")
        message(STATUS "[OpenSSL3] ${ANDROID_ABI}: 注入 ${_ossl_dir}")
    else()
        message(WARNING
            "[OpenSSL3] 未找到 ${_ossl_dir}/libcrypto_3.so, Qt HTTPS 将不可用 "
            "(地图会白底). 请确认 third_party/android_openssl/ssl_3/${ANDROID_ABI}/ 存在.")
    endif()

    # -----------------------------------------------------------------------
    # 关键修复: 注入 qtAndroidSourceDir 到 deployment-settings.json
    # -----------------------------------------------------------------------
    # 背景: Qt 6.7 的 qt_add_executable + ANDROID_PACKAGE_SOURCE_DIR 并不会自动
    #       把 source dir 写入 deployment-settings.json. androiddeployqt 在
    #       --gradle 模式下需要这个字段定位项目 android/ 目录, 没它会用 Qt 模板
    #       默认 (applicationId = org.qtproject.example.outdoorsurvival), 与我们
    #       的 AndroidManifest.xml (com.outdoor.survival) 不匹配 → 启动闪退.
    # 时机: 必须在 qt_finalize_target() 之后, 否则 deployment json 还没生成.
    #       qt_add_executable 默认会 finalize, 所以这里加就行 (不加 qt_finalize_target).
    # 重复执行安全: 用 add_custom_command POST_BUILD 只在最终构建后跑一次;
    #              configure 阶段用 execute_process 立即注入 (因为 configure 时
    #              deployment json 已生成, 后续 build 不需要再注入).
    # -----------------------------------------------------------------------
    if(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/android-${APP_NAME}-deployment-settings.json")
        file(READ "${CMAKE_CURRENT_BINARY_DIR}/android-${APP_NAME}-deployment-settings.json" _deploy_json)
        string(JSON _deploy_json_new SET "${_deploy_json}" "qtAndroidSourceDir" "\"${CMAKE_CURRENT_SOURCE_DIR}/android\"")
        file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/android-${APP_NAME}-deployment-settings.json" "${_deploy_json_new}")
        message(STATUS "[qtAndroidSourceDir] 注入: ${CMAKE_CURRENT_SOURCE_DIR}/android")
    elseif(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/lib${APP_NAME}_${TARGET_ABI}-deployment.json")
        # 兼容 Qt 6.7 旧版命名 (lib<target>_<abi>-deployment.json)
        file(READ "${CMAKE_CURRENT_BINARY_DIR}/lib${APP_NAME}_${TARGET_ABI}-deployment.json" _deploy_json)
        string(JSON _deploy_json_new SET "${_deploy_json}" "qtAndroidSourceDir" "\"${CMAKE_CURRENT_SOURCE_DIR}/android\"")
        file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/lib${APP_NAME}_${TARGET_ABI}-deployment.json" "${_deploy_json_new}")
        message(STATUS "[qtAndroidSourceDir] 注入 (旧命名): ${CMAKE_CURRENT_SOURCE_DIR}/android")
    else()
        message(WARNING "[qtAndroidSourceDir] deployment-settings.json 不存在, 跳过注入. 后续 build_apk.sh 兜底.")
    endif()
endif()

# ============================================================================
# 安装
# ============================================================================
# 关键: 必须保留 install() 段, androiddeployqt 依赖此路径找 application binary
# ----------------------------------------------------------------------------
# 背景: androiddeployqt 期望 binary 在
#       <build>/android-build//libs/<abi>/lib<target>_<abi>.so
#       来源是 CMake install(TARGETS ... LIBRARY DESTINATION lib) 段
#       + Android 工具链的 CMAKE_INSTALL_PREFIX = android-build/
#
# 与 AGP 8 jniLibs 的关系 (不冲突):
#   - install 路径: <build>/android-build//libs/<abi>/lib*.so
#     (CMake 装出来的副本, androiddeployqt 读这找 binary)
#   - jniLibs 路径: app/src/main/jniLibs/<abi>/lib*.so
#     (AGP 8 实际打包来源, sourceSets.jniLibs.srcDirs = ['src/main/jniLibs'])
#   - jniLibs.srcDirs 显式限定只读 jniLibs/, AGP 不会从 install 路径找
#   - 不再有 llvm-readobj 'No such file' 错 (因为 install 路径现在存在)
# ----------------------------------------------------------------------------
# 关键: 在 Android 工具链下, CMAKE_INSTALL_LIBDIR 默认是 'lib', 但 androiddeployqt
#       期望 binary 在 'libs/<abi>/'. 这里显式重设, 让 install 直接装到正确路径,
#       避免 build_apk.sh 再手动 cp 一次 (更稳, 长期可维护).
# 路径映射:
#   默认:    <build>/android-build/lib/lib<target>_<abi>.so
#   期望:    <build>/android-build/libs/<abi>/lib<target>_<abi>.so
# ----------------------------------------------------------------------------
if(ANDROID)
    set(CMAKE_INSTALL_LIBDIR "libs/${ANDROID_ABI}")
    message(STATUS "[install] CMAKE_INSTALL_LIBDIR = ${CMAKE_INSTALL_LIBDIR}")
endif()
include(GNUInstallDirs)
install(TARGETS ${APP_NAME}
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_qml_app_script(
    TARGET ${APP_NAME}
    OUTPUT_SCRIPT deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${deploy_script})

# ============================================================================
# 应用版本定义
# ============================================================================
target_compile_definitions(${APP_NAME} PRIVATE
    APP_VERSION="${APP_VERSION}"
    APP_VERSION_MAJOR=${APP_VERSION_MAJOR}
    APP_VERSION_MINOR=${APP_VERSION_MINOR}
    APP_VERSION_PATCH=${APP_VERSION_PATCH}
    APP_VERSION_CODE=${APP_VERSION_CODE}
    APP_PACKAGE_NAME="${APP_PACKAGE_NAME}"
    # 2026-10-21 (#18 C1): 原来这里还有一行 APP_NAME="${APP_DISPLAY_NAME}" —— 和上面
    #   set(APP_NAME "OutdoorSurvival") 同名两义 (一个是 CMake 目标名, 一个是 C++ 里的
    #   显示名"荒野手册"). src/ 全仓 grep 该宏 0 处引用, 显示名走 manifest 的
    #   android:label / QT_ANDROID_X 那一套, 所以直接删宏, 而不是改名保留.
    #   APP_PACKAGE_NAME 则是真在用: main.cpp 拿它拼 stage0.log 的沙盒路径.
)

# 输出配置摘要
message(STATUS "========================================")
message(STATUS "Building ${APP_DISPLAY_NAME} v${APP_VERSION}")
message(STATUS "Package: ${APP_PACKAGE_NAME}")
message(STATUS "Version code: ${APP_VERSION_CODE}")
message(STATUS "Min SDK: ${APP_MIN_SDK_VERSION}, Target SDK: ${APP_TARGET_SDK_VERSION}")
message(STATUS "OpenCV: ${USE_OPENCV}")
# 2026-09-10: 删 SQLCipher 状态行 (第三方库 find_package 已删)
message(STATUS "========================================")
