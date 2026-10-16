/**
 * @file ServiceListModel.qml
 * @brief ListModel 通用工厂 (5 阶段架构重构 Phase 3)
 *
 * 背景: 9 处 `model.clear() → for(var i ...) model.append()` 模板代码,散在
 *       RouteListPage / TravelListPage / EquipmentPage / Main.qml 等。
 *
 * 用法:
 *   ServiceListModel {
 *       service: routeService
 *       method: "getAll"
 *       args: []           // 可选,传给 method 的额外参数
 *       idRole: "id"
 *   }
 *
 *   // 然后 delegate 里直接用 modelData.id / modelData.name 等
 *   ListView {
 *       model: serviceListModel
 *       delegate: ...
 *   }
 *
 * 2026-09-21 扩展: Phase 5 批次 3 - 支持 Result {ok, value, error} 自动解包.
 *   - 检测返回值是 Result 包装 (ok + value 字段), 自动取 value
 *   - 失败时 console.warn + Toast.error (如有 toast)
 *   - 向后兼容: 仍然支持直接返回数组的方法 (Phase 5 批次 3 前的方法)
 */
import QtQuick

ListModel {
    id: root

    property var service: null
    property string method: "getAll"
    property var args: []
    property string idRole: "id"   // 用于 refresh 后保留选中
    property bool autoRefresh: true
    // 2026-09-21: 失败时是否 toast.error (默认 true; toast 是 Main.qml 顶层 id)
    property bool showErrorToast: true

    // 2026-09-21: 工具 - 检测一个 QVariantMap 是否是 Result 包装
    //   Result = {ok: bool, value: any, error: {code, message, context}}
    //   普通 dict = 有自己的业务字段 (id, name 等),没有 ok 字段
    function _isResult(obj) {
        return obj !== null && typeof obj === "object"
                && !Array.isArray(obj)
                && Object.prototype.hasOwnProperty.call(obj, "ok")
                && Object.prototype.hasOwnProperty.call(obj, "value")
    }

    // 2026-09-21: 工具 - 报告 Result 错误
    function _reportError(methodName, r) {
        var msg = (r.error && r.error.message) || "查询失败"
        console.warn("ServiceListModel: " + methodName + " failed:", msg)
        if (showErrorToast && typeof toast !== "undefined" && toast) {
            toast.error(msg)
        }
    }

    function refresh() {
        root.clear()
        if (!service) {
            console.warn("ServiceListModel: service is null")
            return
        }
        if (typeof service[method] !== "function") {
            console.warn("ServiceListModel: method not found:", method,
                         "on", service)
            return
        }
        // 调用 service.method(...args)
        var results = service[method].apply(service, args || [])

        // 2026-09-21: Result 适配 - 如果返回 QVariantMap 且有 ok/value, 解包 value
        if (_isResult(results)) {
            if (!results.ok) {
                _reportError(method, results)
                return
            }
            results = results.value
        }

        // 2026-09-21: 数组里如果单个元素是 Result (罕见场景), 也尝试解包
        //   - 当前没有这种用法, 但为安全起见加了 try/catch
        // 2026-09-23: 修 - 之前仅 `Array.isArray(results)` 检测. 但 Qt 6.7
        //   qmlcachegen 静态编译下, QVariantList<QVariantMap> 经常被包成 generic
        //   QVariantMap (而非 JS Array), app_log 多次报 "method returned
        //   non-array: getAll type: object", 导致动植物图鉴/徒步/自驾游 3 个
        //   page 列表全空. 加 length-in 检测识别 QQmlListModel/QVariantList-like.
        var isArrLike = Array.isArray(results)
        if (!isArrLike && typeof results === "object" && results !== null
                && typeof results.length === "number"
                && !_isResult(results)) {
            // 把类数组转成真数组
            var arr = []
            for (var j = 0; j < results.length; ++j) arr.push(results[j])
            results = arr
            isArrLike = true
        }
        if (!isArrLike) {
            console.warn("ServiceListModel: method returned non-array:", method,
                         "type:", typeof results)
            return
        }
        for (var i = 0; i < results.length; i++) {
            var item = results[i]
            // 如果 item 是 Result, 解包它的 value (防御性)
            if (_isResult(item)) {
                item = item.value
            }
            root.append(item)
        }
    }

    Component.onCompleted: {
        if (autoRefresh) {
            // 延后一帧, 让 page 端先 Component.onCompleted 设好 args
            Qt.callLater(refresh)
        }
    }
}
