/**
 * @file SpeciesServiceRegistry.qml
 * @brief 物种 4 路 service 调度 (5 阶段架构重构 Phase 3)
 *
 * 注意: 不用 `pragma Singleton`. 原因 - qmlcachegen 静态编译 + import OutdoorSurvival
 *       路径下,pragma Singleton 不会被解析,运行时报
 *       "Property 'serviceOf' of object [object Object] is not a function"
 *       (app_log.txt 2026-09-20). 改用普通 QObject,Main.qml 实例化 1 次 (id: speciesServiceRegistry),
 *       各页面通过动态作用域调用.
 */
import QtQuick
import OutdoorSurvival 1.0

QtObject {
    id: root

    readonly property var _services: [plantService, animalService,
                                      insectService, mushroomService]
    readonly property var _kingdoms: ["plantae", "animalia", "insecta", "fungi"]
    readonly property var _icons:    ["\ue406", "\ue91a", "\ue1b9", "\ue239"]
    readonly property var _labels:   ["植物", "动物", "昆虫", "蘑菇"]

    function serviceOf(idx) {
        return (idx >= 0 && idx < _services.length) ? _services[idx] : null
    }

    function kingdomOf(idx) {
        return (idx >= 0 && idx < _kingdoms.length) ? _kingdoms[idx] : ""
    }

    function labelOf(idx) {
        return (idx >= 0 && idx < _labels.length) ? _labels[idx] : ""
    }

    function iconOf(idx) {
        return (idx >= 0 && idx < _icons.length) ? _icons[idx] : ""
    }

    // === 公共 method 代理 ===
    function getById(idx, id) {
        var svc = serviceOf(idx)
        return svc ? svc.getById(id) : {}
    }

    function getAll(idx) {
        var svc = serviceOf(idx)
        return svc ? svc.getAll() : []
    }

    function search(idx, kw) {
        var svc = serviceOf(idx)
        return svc ? svc.search(kw) : []
    }

    function recordLocation(idx, entityId, lat, lon, note) {
        var svc = serviceOf(idx)
        if (!svc) return ""
        return svc.recordLocation(entityId, lat, lon, note)
    }

    function getLocationsByEntity(idx, entityId) {
        var svc = serviceOf(idx)
        return svc ? svc.getLocationsByEntity(entityId) : []
    }

    function matchByColor(idx, color, topK) {
        var svc = serviceOf(idx)
        return svc ? svc.matchByColor(color, topK || 5) : []
    }

    function incrementVisitCount(idx, id) {
        var svc = serviceOf(idx)
        if (svc && svc.incrementVisitCount) svc.incrementVisitCount(id)
    }
}