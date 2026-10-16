/**
 * @file PermissionHelper.java
 * @brief Android 运行时权限检查与异步申请 (Java 端)
 *
 * 设计要点:
 *   - init(activity) 由 MainActivity.onCreate 调用,缓存 Activity 引用
 *   - check(permission) 同步查 ContextCompat.checkSelfPermission
 *   - request(permission) 同步调 ActivityCompat.requestPermissions,
 *     结果通过 onRequestPermissionsResult → dispatchResult 反向调
 *     MainActivity.nativeHandlePermissionResult 回到 C++
 *   - 用 AtomicInteger 自增 requestCode 保证并发申请不冲突
 *   - 2026-09-19: 新建,替代 AndroidPlatform.cpp 里的 stub.
 *     旧逻辑直接 callback(true) 假装成功 → MapPage.PositionSource 因没 GPS
 *     权限永远 hasFix=false, 拍照也没弹系统权限框
 */
package com.outdoor.survival;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.util.Log;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.concurrent.atomic.AtomicInteger;

public final class PermissionHelper {
    private static final String TAG = "PermissionHelper";

    private static Activity sActivity;
    private static final AtomicInteger sNextCode = new AtomicInteger(0x4000);

    private PermissionHelper() {}

    /** MainActivity.onCreate 调用,缓存 Activity 引用 */
    public static void init(Activity activity) {
        sActivity = activity;
        Log.i(TAG, "init: activity=" + (activity == null ? "null" : activity.getClass().getSimpleName()));
    }

    /**
     * 窥探下一个 requestCode (不会真正消耗).
     * C++ 端在调 request() 之前先 peek 拿到 code, 存 callback;
     * 然后调 request(), Java 内部 incrementAndGet 拿到同样的 code.
     * 这样 callback 表的 key 跟 ActivityCompat.requestPermissions 的 requestCode 一致.
     */
    public static int peekNextCode() {
        return sNextCode.get() + 1;
    }

    /** 同步查权限状态 */
    public static boolean check(String permission) {
        if (sActivity == null) {
            Log.w(TAG, "check: activity not initialized");
            return false;
        }
        if (permission == null || permission.isEmpty()) return false;
        try {
            int granted = ContextCompat.checkSelfPermission(sActivity, permission);
            return granted == PackageManager.PERMISSION_GRANTED;
        } catch (Exception e) {
            Log.e(TAG, "check(" + permission + ") failed: " + e.getMessage());
            return false;
        }
    }

    /**
     * 同步申请权限. 已授权直接返回 true 不弹框;
     * 未授权调 ActivityCompat.requestPermissions,异步结果走
     * MainActivity.onRequestPermissionsResult → dispatchResult → C++ 回调.
     * @return true 表示已授权;false 表示已发起异步申请 (结果会异步到达)
     */
    public static boolean request(String permission) {
        if (sActivity == null) {
            Log.w(TAG, "request: activity not initialized");
            return false;
        }
        if (permission == null || permission.isEmpty()) return false;
        if (check(permission)) return true;

        int code = sNextCode.incrementAndGet();
        try {
            ActivityCompat.requestPermissions(sActivity, new String[]{permission}, code);
            Log.i(TAG, "request: " + permission + " code=" + code);
            return false;
        } catch (Exception e) {
            Log.e(TAG, "request(" + permission + ") failed: " + e.getMessage());
            return false;
        }
    }

    /**
     * MainActivity.onRequestPermissionsResult 转发入口.
     * 直接调用 MainActivity 的 native 静态方法把结果灌回 C++ 端.
     */
    public static void dispatchResult(int requestCode,
                                       String[] permissions,
                                       int[] grantResults) {
        Log.i(TAG, "dispatchResult: code=" + requestCode +
                   " perms=" + (permissions == null ? 0 : permissions.length) +
                   " results=" + (grantResults == null ? 0 : grantResults.length));
        MainActivity.nativeHandlePermissionResult(requestCode, permissions, grantResults);
    }
}