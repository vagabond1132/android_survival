/**
 * @file MainActivity.java
 * @brief 自定义 Qt 主 Activity, 接管运行时权限申请回调
 *
 * 继承关系: MainActivity -> org.qtproject.qt.android.QtActivityBase
 *   继承 QtActivityBase 是为了让 AndroidManifest 里所有 Qt 启动配置
 *   (meta-data android.app.lib_name / intent-filter / launchMode / softInputMode
 *    / configChanges 等) 继续生效, 不需要逐项重写.
 *
 * 关键改动:
 *   - onCreate: super.onCreate 后调 PermissionHelper.init(this) 缓存 Activity
 *   - onRequestPermissionsResult: 把 Android 系统回调转发给 PermissionHelper.dispatchResult
 *     最终反向调到 C++ 的 Java_com_outdoor_survival_MainActivity_nativeHandlePermissionResult
 *
 * 2026-09-19: 新建. 之前 manifest 直接写 org.qtproject.qt.android.QtActivityBase,
 *   系统权限回调没地方接 → AndroidPlatform::requestPermission 是 stub 直接
 *   callback(true) 假装成功 → 首次装包没弹"允许使用位置/相机"系统框
 */
package com.outdoor.survival;

import android.os.Bundle;
import android.util.Log;

public class MainActivity extends org.qtproject.qt.android.QtActivityBase {
    private static final String TAG = "MainActivity";

    static {
        // 加载主 so 让 native 方法符号可解析. 与 AndroidManifest android.app.lib_name 一致.
        // 注意: 不在这里加载 Qt 库, QtLoader 会按 libs.xml qt_libs 顺序负责加载.
        // 详见 OutdoorSurvivalApp.java 文件头注释.
        Log.i(TAG, "static block: about to loadLibrary OutdoorSurvival");  // TEMP 2026-09-21
        try {
            System.loadLibrary("OutdoorSurvival");
            Log.i(TAG, "static block: loadLibrary OutdoorSurvival OK");  // TEMP 2026-09-21
        } catch (Throwable t) {
            Log.e(TAG, "loadLibrary failed: " + t.getMessage());
        }
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        Log.i(TAG, "onCreate: entered");  // TEMP 2026-09-21
        super.onCreate(savedInstanceState);
        Log.i(TAG, "onCreate: super.onCreate returned");  // TEMP 2026-09-21
        PermissionHelper.init(this);
        Log.i(TAG, "onCreate done, PermissionHelper ready");
    }

    @Override
    public void onResume() {
        super.onResume();
        Log.i(TAG, "onResume");  // TEMP 2026-09-21
    }

    @Override
    public void onPause() {
        super.onPause();
        Log.i(TAG, "onPause");  // TEMP 2026-09-21
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
                                            String[] permissions,
                                            int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        Log.d(TAG, "onRequestPermissionsResult: code=" + requestCode);
        // 转发给 PermissionHelper, 内部最终调用 nativeHandlePermissionResult
        // 把 (requestCode, permissions[], grantResults[]) 灌回 C++ 端.
        PermissionHelper.dispatchResult(requestCode, permissions, grantResults);
    }

    /**
     * C++ 端用 extern "C" 接收 (Java_com_outdoor_survival_MainActivity_nativeHandlePermissionResult).
     * 签名: (IILjava/lang/String;[I)V
     * 在主线程调用 (Android 系统回调本就在主线程), C++ 端用 QueuedConnection
     * 投递回 Qt 主事件循环, 避免线程问题.
     */
    public static native void nativeHandlePermissionResult(int requestCode,
                                                             String[] permissions,
                                                             int[] grantResults);
}