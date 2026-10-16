cmake_minimum_required(VERSION 3.22)
project(OutdoorSurvival
    VERSION 0.0.1
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
set(APP_VERSION_CODE 1)  # 用于商店版本号（每次发版递增）
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
    Charts  # 2026-09-14: P1 轨迹分析 (海拔/速度曲线)
)

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
)

set(COMMON_SOURCES
    # 2026-09-20: 5 阶段架构重构 Phase 2 - 统一 SQL DDL/DML/SELECT 工具
    src/common/DbHelper.cpp
    # 2026-09-21: 阶段 L5.1 - QSettings 封装
    src/common/SettingsStore.cpp
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
    # 2026-09-21 阶段 L2: Service 基类 (12 service 继承)
    src/common/ServiceBase.h
    # 2026-09-21 阶段 L4.2: Repository 接口
    src/common/Repository.h
    # 2026-09-21 阶段 L5.1: QSettings 封装
    src/common/SettingsStore.h
    # 2026-09-21 阶段 L5.2: CRUD 模板
    src/common/QueryTemplate.h

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
        qml/pages/SpeciesDetailPage.qml
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
        qml/pages/ChecklistDetailPage.qml
        qml/pages/TravelListPage.qml
        qml/pages/TravelDetailPage.qml
        # 之前缺漏 (6 个): MapPage / ResultPage / EquipmentPage / EquipmentDetailPage /
        # CategorySection / MapToolButton. 缺则 qmlcache 跳过, qmldir 不含, 运行时
        # import 报 "module not found" → 跳到这些页直接崩
        # 2026-09-20: ResultPage 是僵尸 (Main.qml 用 inline searchResults ListView,
        #   全 qml 无引用), 删除避免误导新人
        qml/pages/MapPage.qml
        qml/pages/EquipmentPage.qml
        qml/pages/EquipmentDetailPage.qml
        qml/pages/CameraPage.qml
        # 2026-09-14: P1 轨迹分析详情页 (海拔/速度曲线 + 8 项统计 + 分段 + 卡路里 + 休息点)
        qml/pages/TrackDetailPage.qml

        # 通用组件 (qml/components/base/) - 阶段 I-1 拆分
        # 纯通用, 无业务字段, 任何 page 复用
        qml/components/base/Section.qml
        # 2026-09-28: StatCard.qml 已删 (问题4 删首页「关键统计」行后无使用方, 成孤儿组件)
        qml/components/base/FunctionEntry.qml
        qml/components/base/CategoryChip.qml
        qml/components/base/DifficultyChip.qml
        qml/components/base/DangerChip.qml
        qml/components/base/InfoItem.qml
        # 2026-09-14: Material Icons 字体图标组件 (依赖 assets/fonts/MaterialIcons-Regular.ttf)
        qml/components/base/IconLabel.qml
        # 2026-09-14: 通用页面顶部工具栏 (返回+标题), 统一各子页返回
        qml/components/base/PageHeader.qml
        qml/components/base/FilterRow.qml
        # 2026-09-20: 5 阶段架构重构 Phase 3 - 设计模式 + QML 公共组件
        # - Toast.qml / ServiceListModel.qml / DetailLoader.qml 通用
        # - Styles.qml 间距/字号/圆角 设计 token (Singleton)
        qml/components/base/Toast.qml
        qml/components/base/ServiceListModel.qml
        qml/components/base/DetailLoader.qml
        qml/components/base/Styles.qml

        # 业务组件 (qml/pages/<XxxPageComponents>/) - 阶段 I-1 下放
        # 业务专属, 引用具体 context property (equipmentService 等)
        qml/pages/HomePageComponents/HomeEntry.qml
        qml/pages/MapPageComponents/MapToolButton.qml
        qml/pages/SOSPageComponents/SOSButton.qml
        qml/pages/SOSPageComponents/QuickCallButton.qml
        qml/pages/EquipmentPageComponents/CategorySection.qml
        qml/pages/FieldGuidePageComponents/SpeciesServiceRegistry.qml

        # 地图跨页组件 (qml/components/MapOverlay/) - 保留, 跨页复用
        qml/components/MapOverlay/DirectionCompassOverlay.qml
        qml/components/MapOverlay/MapRightButtonColumn.qml
        qml/components/MapOverlay/MapBottomSheet.qml
        qml/components/MapOverlay/RouteSummaryPanel.qml  # 2026-09-15: 概览面板

        # MapPage 专属组件
        qml/pages/MapPageComponents/RecordTab.qml
        qml/pages/MapPageComponents/NavigationTab.qml
        qml/pages/MapPageComponents/NearbyTab.qml
        qml/pages/MapPageComponents/SearchTab.qml

        # SurvivalPage 专属组件
        qml/pages/SurvivalPageComponents/SurvivalList.qml

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
    Qt6::Charts  # 2026-09-14: P1
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
    APP_NAME="${APP_DISPLAY_NAME}"
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
