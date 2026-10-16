/**
 * @file DetailLoader.qml
 * @brief 详情页加载模板 (5 阶段架构重构 Phase 3)
 *
 * 背景: 3 处详情页 (RouteDetailPage / TravelDetailPage / FieldGuideDetailPage)
 *       都是同构的"getById(id) + 选调 incrementVisitCount"模式,各写一份。
 *
 * 用法 (以 RouteDetailPage 为例):
 *   DetailLoader {
 *       id: loader
 *       service: routeService
 *       entityId: routeId
 *       onLoaded: function(entity) { page.route = entity }
 *   }
 *
 * 当前状态: 新建文件,还未替换 3 处详情页 (留 Phase 5 接入)
 */
import QtQuick

QtObject {
    id: root

    property var service: null
    property string entityId: ""
    property bool autoIncrement: true   // 详情页默认调 +1 访问计数
    property var entity: ({})            // 最新实体

    signal loaded(var entity)
    signal loadFailed(string reason)

    function _doIncrement() {
        if (!service || !autoIncrement) return
        if (typeof service.incrementVisitCount !== "function") return
        try {
            service.incrementVisitCount(entityId)
        } catch (e) {
            // 不阻塞主流程
            console.warn("DetailLoader.incrementVisitCount:", e)
        }
    }

    function load() {
        if (!service) {
            loadFailed("service is null")
            return
        }
        if (!entityId) {
            loadFailed("entityId is empty")
            return
        }
        if (typeof service.getById !== "function") {
            loadFailed("getById not implemented")
            return
        }
        try {
            var data = service.getById(entityId)
            entity = data || {}
            if (!entity.id) {
                loadFailed("entity not found: " + entityId)
            } else {
                loaded(entity)
                _doIncrement()
            }
        } catch (e) {
            loadFailed(String(e))
        }
    }

    onEntityIdChanged: {
        if (entityId) load()
    }
}