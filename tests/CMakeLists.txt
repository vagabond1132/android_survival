# 测试 CMakeLists.txt
# 荒野手册单元测试套件(独立构建, 桌面 Qt6)
# 用法: cmake -S tests -B <build> -DCMAKE_PREFIX_PATH=<Qt>/gcc_64
#       cmake --build <build> -j && ctest --test-dir <build> --output-on-failure

cmake_minimum_required(VERSION 3.22)
project(OutdoorSurvivalTests VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_AUTOUIC ON)

# Positioning: QGeoCoordinate/QGeoPositionInfo (EmergencyService, MapService)
# Xml:         QXmlStreamReader (GPX 解析)
# Qml:         QQmlContext (PlatformInterface / AndroidPlatform 头文件)
find_package(Qt6 6.7 REQUIRED COMPONENTS Core Gui Sql Network Test Positioning Xml Qml)

set(APP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")

# 服务通过 AssetLoader 读 assets/data/*.json。测试进程不链接 qt_add_qml_module,
# 没有 qrc 资源, 因此由 CTest 注入 OUTDOOR_ASSET_ROOT 指向源目录 (见 AssetLoader.cpp)。
set(ASSET_DATA_DIR "${APP_ROOT}/assets/data")

include_directories(${APP_ROOT}/src ${APP_ROOT})

# 公共源: 必须与 CMakeLists.txt 的 APP_SOURCES 保持同源, 即线上真正打进 APK 的实现。
# 2026-10-16: 原文件写 src/firstaid + src/emergency (重构前旧副本), 且路径缺 ${APP_ROOT}
# 前缀导致 configure 失败; 现已切到 lifesaver/preparation。
set(COMMON_SRC
    ${APP_ROOT}/src/core/Database.cpp
    ${APP_ROOT}/src/core/Config.cpp
    ${APP_ROOT}/src/core/Logger.cpp
    ${APP_ROOT}/src/core/AssetLoader.cpp
    ${APP_ROOT}/src/core/PathService.cpp
    ${APP_ROOT}/src/common/DbHelper.cpp
    ${APP_ROOT}/src/common/SettingsStore.cpp
    # header-only 的 Q_OBJECT 类必须列进源文件列表, AUTOMOC 才会生成 moc_ServiceBase.cpp;
    # 否则链接报 "undefined reference to vtable for outdoor::ServiceBase"
    # (主 CMakeLists.txt:228 同样列了它)
    ${APP_ROOT}/src/common/ServiceBase.h
    ${APP_ROOT}/src/lifesaver/FirstAidService.cpp
    ${APP_ROOT}/src/lifesaver/EmergencyService.cpp
    ${APP_ROOT}/src/species/SpeciesService.cpp
    ${APP_ROOT}/src/species/FieldGuideIndex.cpp
    ${APP_ROOT}/src/species/PlantService.cpp
    ${APP_ROOT}/src/species/AnimalService.cpp
    ${APP_ROOT}/src/species/InsectService.cpp
    ${APP_ROOT}/src/species/MushroomService.cpp
    ${APP_ROOT}/src/species/SpeciesLocationRepository.cpp
    ${APP_ROOT}/src/species/SpeciesLocationOps.cpp
    ${APP_ROOT}/src/species/FieldGuideHistory.cpp
    ${APP_ROOT}/src/survival/SurvivalService.cpp
    ${APP_ROOT}/src/knots/KnotService.cpp
    ${APP_ROOT}/src/routes/RouteService.cpp
    ${APP_ROOT}/src/preparation/ChecklistService.cpp
    ${APP_ROOT}/src/travel/TravelService.cpp
    ${APP_ROOT}/src/equipment/EquipmentService.cpp
    ${APP_ROOT}/src/equipment/RuleConditionFactory.cpp
    ${APP_ROOT}/src/map/MapService.cpp
    ${APP_ROOT}/src/map/MapService_photos.cpp
    ${APP_ROOT}/src/map/MapService_tracks.cpp
    ${APP_ROOT}/src/map/MapService_species.cpp
    ${APP_ROOT}/src/platform/PlatformInterface.cpp
    ${APP_ROOT}/src/platform/AndroidPlatform.cpp
)

# 23 个用例进程共用同一份服务实现: 编成 OBJECT 库只编一次,
# 否则每个 target 重复编译 31 个 .cpp (首轮全量构建会慢到不可用)。
add_library(outdoor_test_objs OBJECT ${COMMON_SRC})
target_include_directories(outdoor_test_objs PUBLIC
    ${APP_ROOT}/src
    ${APP_ROOT}/src/core
    ${APP_ROOT}
)
target_link_libraries(outdoor_test_objs PUBLIC
    Qt6::Core Qt6::Gui Qt6::Sql Qt6::Network Qt6::Positioning Qt6::Xml Qt6::Qml
)
target_compile_definitions(outdoor_test_objs PUBLIC APP_VERSION="0.0.1")

function(add_unit_test name)
    qt_add_executable(${name}_test
        ${ARGN}
    )
    target_link_libraries(${name}_test PRIVATE outdoor_test_objs Qt6::Test)
    add_test(NAME ${name} COMMAND ${name}_test)
    set_tests_properties(${name} PROPERTIES
        ENVIRONMENT "OUTDOOR_ASSET_ROOT=${ASSET_DATA_DIR};QT_QPA_PLATFORM=offscreen"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
    )
endfunction()

enable_testing()

set(TESTS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/unit")

add_unit_test(test_database          ${TESTS_DIR}/test_database.cpp)
add_unit_test(test_logger            ${TESTS_DIR}/test_logger.cpp)
add_unit_test(test_result            ${TESTS_DIR}/test_result.cpp)
add_unit_test(test_db_helper         ${TESTS_DIR}/test_db_helper.cpp)
add_unit_test(test_asset_loader      ${TESTS_DIR}/test_asset_loader.cpp)
add_unit_test(test_settings_store    ${TESTS_DIR}/test_settings_store.cpp)
add_unit_test(test_rule_condition_strategy ${TESTS_DIR}/test_rule_condition_strategy.cpp)
add_unit_test(test_first_aid         ${TESTS_DIR}/test_first_aid.cpp)
add_unit_test(test_first_aid_service ${TESTS_DIR}/test_first_aid_service.cpp)
add_unit_test(test_emergency_service ${TESTS_DIR}/test_emergency_service.cpp)
add_unit_test(test_species_service   ${TESTS_DIR}/test_species_service.cpp)
add_unit_test(test_plant_service     ${TESTS_DIR}/test_plant_service.cpp)
add_unit_test(test_animal_service    ${TESTS_DIR}/test_animal_service.cpp)
add_unit_test(test_insect_service    ${TESTS_DIR}/test_insect_service.cpp)
add_unit_test(test_mushroom_service  ${TESTS_DIR}/test_mushroom_service.cpp)
add_unit_test(test_field_guide_history ${TESTS_DIR}/test_field_guide_history.cpp)
add_unit_test(test_knot_service      ${TESTS_DIR}/test_knot_service.cpp)
add_unit_test(test_survival_service  ${TESTS_DIR}/test_survival_service.cpp)
add_unit_test(test_route_service     ${TESTS_DIR}/test_route_service.cpp)
add_unit_test(test_travel_service    ${TESTS_DIR}/test_travel_service.cpp)
add_unit_test(test_checklist_service ${TESTS_DIR}/test_checklist_service.cpp)
add_unit_test(test_equipment_service ${TESTS_DIR}/test_equipment_service.cpp)
add_unit_test(test_map_service       ${TESTS_DIR}/test_map_service.cpp)
