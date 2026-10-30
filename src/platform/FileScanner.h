/**
 * @file FileScanner.h
 * @brief 本机轨迹文件扫描 (纯 Qt, 桌面单测可直接跑)
 */

#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

namespace outdoor {

// 单次遍历的硬闸: 深度、总条目数、返回条数. 野外设备上不能因为搜索卡住 UI.
//
// 2026-10-28: 这个结构体必须留在类外. 原来它是 FileScanner 的内嵌 struct,
// search() 的默认实参写 `= Options()` —— 求值要展开 Options 的隐式默认构造,
// 而它的 NSDMI 此刻还在"外层类定义内", clang (NDK arm64) 直接报错:
//   default member initializer for 'maxDepth' needed within definition of
//   enclosing class 'FileScanner' outside of member functions
// g++ (桌面/单测) 却照单收下, 所以本地全绿、出包必挂.
struct FileScanOptions {
    int maxDepth = 6;
    int maxEntries = 8000;
    int maxHits = 200;
};

/**
 * @class FileScanner
 * @brief 在给定候选根目录里按后缀 + 文件名子串找轨迹文件
 *
 * 只负责"找", 不负责"读": 命中项的 path 是普通绝对路径, 直接交给
 * MapService::importGpx/importKml/importCsv (它们吃 QFile 路径, 不吃 URL).
 *
 * 2026-10-28 (#148): 微信等第三方 App 的下载目录是"路径猜不穷尽"的典型 ——
 * 所以这里把每个根的判定显式记进 diagnostics (存在/可读/扫了多少/命中多少),
 * 真机上一眼能看出"是没这个目录"还是"有目录但应用读不到".
 */
class FileScanner {
public:
    using Options = FileScanOptions;

    // suffixes 用小写不带点 (gpx/kml/csv); keyword 空 = 不按名字过滤.
    // 返回按 mtime 倒序的 QVariantList, 每项是
    //   {path, name, dir, suffix, sizeBytes, mtimeMs}
    // diagnostics 非空则逐根追加一行, 供日志/UI 如实说明扫了什么、哪里读不到.
    static QVariantList search(const QStringList& roots,
                               const QString& keyword,
                               const QStringList& suffixes,
                               QVariantList* diagnostics,
                               const Options& options = Options());

    // 默认后缀集合: 只列真正能导入的. KMZ/TCX 不在其中 —— 与其列出来点了报错,
    // 不如压根不列 (见"不给假读数"规则).
    static QStringList trackSuffixes();

    // Android 上的候选根: 公共 Download/Documents + 微信各版本下载目录
    // + 外部卷同名目录 + 应用自己的沙盒下载目录.
    static QStringList defaultAndroidRoots();
};

} // namespace outdoor
