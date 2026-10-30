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
import android.content.Context;
import android.location.LocationManager;
import android.util.Log;

import java.lang.reflect.Method;

public class OutdoorSurvivalApp extends Application {
    private static final String TAG = "OutdoorSurvival";

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "App started: " + getPackageName());

        // 不提前 load Qt 库 (会导致 JNI_OnLoad 失败, 见文件头注释).
        // QtLoader.loadQtLibraries 会按 libs.xml qt_libs 顺序 load 所有库.
        Log.i(TAG, "Waiting for QtLoader to load libraries");

        initQtPositioning(this);
    }

    /**
     * 补 Qt 6.7.2 Android 定位插件漏掉的那一次初始化.
     *
     * 为什么必须 app 自己补: 插件的 Java 侧 org.qtproject.qt.android.positioning.QtPositioning
     * 里, 静态字段 locationManager 只有一个赋值入口 —— public static void setContext(Context);
     * 而 libplugins_position_qtposition_android.so 的 JNI 调用面只有 providerList /
     * startUpdates / requestUpdate / lastKnownPosition / stopUpdates, 没有 setContext
     * (javap 与 strings 都核对过, Qt6Android.jar 里也没有任何类引用 QtPositioning).
     * 于是 locationManager 恒为 null, 真机 logcat 原文:
     *   W/qt.positioning.android: No locationManager available in QtPositioning
     *   W/System.err: java.lang.NullPointerException: ... requestLocationUpdates(...) on a null object
     *       at ...QtPositioning.addActiveListener(QtPositioning.java:165)
     *       at ...QtPositioning.startUpdates(QtPositioning.java:208)
     * C++ 侧只收到 QGeoPositionInfoSource::UnknownSourceError(2), 一条 positionUpdated
     * 都没有 → ①营地/⑤求助 的经纬度、精度、海拔整片 "--" (2026-10-22 #98 的根因).
     *
     * 用反射而不 import: 这个类来自 Qt 的 QtAndroidPositioning.jar, 不在本模块的编译
     * classpath 上, 直接引用会让 javac 找不到符号. 类名/方法名一旦被 Qt 改掉, 反射只会
     * 拿到 NoSuchMethod 并把日志打出来 —— 比静默没定位好查得多.
     */
    private static void initQtPositioning(Context context) {
        try {
            Class<?> cls = Class.forName("org.qtproject.qt.android.positioning.QtPositioning");
            Method setContext = cls.getMethod("setContext", Context.class);
            setContext.invoke(null, context);
            LocationManager lm = (LocationManager)
                    context.getSystemService(Context.LOCATION_SERVICE);
            Log.i(TAG, "QtPositioning.setContext OK, enabled providers = "
                    + (lm == null ? "no LocationManager" : lm.getProviders(true)));
        } catch (Throwable t) {
            // NoClassDefFound / NoSuchMethod / 反射被禁用都在这里
            Log.e(TAG, "QtPositioning.setContext failed: " + t, t);
        }
    }
}
