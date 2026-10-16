/**
 * @file OutdoorSurvivalApp.java
 * @brief Application 入口
 *
 * 修复历史:
 *   - 旧逻辑 (已废弃): 在 onCreate 提前 load libQt6Core/Gui/Qml/Quick, 规避 AAPT2
 *     重排 qt_libs 顺序导致 JNI_OnLoad 失败.
 *   - 新问题 (run.txt: 18:01:23.351): libQt6Quick 在 Application.onCreate 提前 load
 *     时, JNI_OnLoad 返回 JNI_ERR. 原因是提前 load 顺序 (Core→Gui→Qml→Quick) 缺少
 *     libQt6Quick 的 split 依赖 (libQt6QuickTemplates2, libQt6QuickControls2 等),
 *     那些 split 是在 QtLoader.loadLibraries 才按 qt_libs 列表 load 的.
 *   - 新逻辑: 不提前 load 任何 Qt 库, 让 QtLoader 完整接管 load 流程. libs.xml 的
 *     qt_libs 字符串顺序由 build_apk.sh 按依赖顺序生成 (项目主 lib → Qt6Core →
 *     Qt6Gui → Qt6Qml → split 模块 → Qt6Quick → 其他), QtLoader 内部用
 *     loadLibraries() 按这个顺序 System.loadLibrary, 依赖会自动满足.
 *
 * 触发条件: 旧逻辑只在 AAPT2 出现 qt_libs 重排 bug 时才必要; Qt 6.7.2 + AGP 8.4
 *   组合下, aapt2 不再重排 <string> 内的分号分隔列表, 旧 workaround 失去意义.
 *   保留 Application 类 (不删除) 是为了满足 AndroidManifest android:name 引用,
 *   以及维持 static_init_classes 字符串资源的兼容性.
 */

package com.outdoor.survival;

import android.app.Application;
import android.util.Log;

public class OutdoorSurvivalApp extends Application {
    private static final String TAG = "OutdoorSurvival";

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "App started: " + getPackageName());

        // 不提前 load Qt 库 (会导致 JNI_OnLoad 失败, 见文件头注释).
        // QtLoader.loadQtLibraries 会按 libs.xml qt_libs 顺序 load 所有库.
        Log.i(TAG, "Waiting for QtLoader to load libraries");
    }
}
