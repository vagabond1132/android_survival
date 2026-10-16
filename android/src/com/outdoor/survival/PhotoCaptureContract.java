/**
 * @file PhotoCaptureContract.java
 * @brief 拍照桥接常量 + JNI 入口
 *
 * C++ 端通过 JNI 调 Java_com_outdoor_survival_PhotoCaptureContract_notifyResult
 * 把 file:// URI 回灌到 C++ 端 pending 队列.
 */
package com.outdoor.survival;

public class PhotoCaptureContract {
    public static final String ACTION_CAPTURE_PHOTO = "com.outdoor.survival.action.CAPTURE_PHOTO";

    static {
        // 加载主 so, 让 native 方法符号可解析.
        // 这里假设主 so 名为 "OutdoorSurvival" (与 AndroidManifest android.app.lib_name 一致).
        try {
            System.loadLibrary("OutdoorSurvival");
        } catch (Throwable t) {
            android.util.Log.e("PhotoCaptureContract", "loadLibrary failed: " + t.getMessage());
        }
    }

    /**
     * Java 反向调 C++ 入口: 由 C++ 端在 AndroidPlatform.cpp 的 extern "C" 接收.
     * 参数 uri 允许为 null (失败/取消).
     */
    public static native void notifyResult(String uri);
}
