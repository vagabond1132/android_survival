/**
 * @file EmergencyService.java
 * @brief SOS 前台服务
 */

package com.outdoor.survival;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;

import androidx.core.app.NotificationCompat;

public class EmergencyService extends Service {
    private static final String TAG = "EmergencyService";
    private static final int NOTIFICATION_ID = 1001;
    private static final String CHANNEL_ID = "emergency_channel";

    private LocationManager mLocationManager;
    private final LocationListener mLocationListener = new LocationListener() {
        @Override
        public void onLocationChanged(Location location) {
            // 通过 JNI 桥接把位置传给 Qt
            double lat = location.getLatitude();
            double lon = location.getLongitude();
            double accuracy = location.getAccuracy();
            long time = location.getTime();

            Log.d(TAG, "Location: " + lat + ", " + lon + " (accuracy: " + accuracy + "m)");

            // 调用 Qt 端的 native slot
            // C++ 端用 EmergencyService::instance() 静态指针找 service, 不需要 callback 句柄.
            // 仍保留 nativeUpdateLocation 形参兼容 (jlong 0 占位), 不传实际句柄.
            nativeUpdateLocation(0L, lat, lon, accuracy, time);
        }

        @Override
        public void onStatusChanged(String provider, int status, Bundle extras) {}

        @Override
        public void onProviderEnabled(String provider) {}

        @Override
        public void onProviderDisabled(String provider) {}
    };

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "EmergencyService created");
        createNotificationChannel();
        startInForeground();
        startLocationUpdates();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String action = intent.getAction();
            if ("STOP_SERVICE".equals(action)) {
                stopSelf();
                return START_NOT_STICKY;
            }
            // qtCallback Intent extra 之前用于 JNI 句柄传递, 已废弃 (C++ 端用
            // EmergencyService.instance() 静态指针找 service, 不再需要 callback).
            // 保留 startId 等标准参数, 忽略 extra.
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        stopLocationUpdates();
        Log.i(TAG, "EmergencyService destroyed");
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "紧急服务",
                    NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("SOS 紧急求救服务");
            channel.setShowBadge(true);

            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    private void startInForeground() {
        // 用 getLaunchIntentForPackage 启动主 Activity, 不直接引用 QtActivity 类.
        // 原因: EmergencyService.java 是项目自己写的 Java 源, app/build.gradle 没声明
        //       对 Qt jar (qt-android-bridge) 的依赖, 编译时 classpath 找不到
        //       org.qtproject.qt.android.bindings.QtActivity 类. 用 Intent 字符串
        //       方式启动则不需要 import, 也避免硬编码包名 (Qt 6 改名风险).
        Intent notificationIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (notificationIntent == null) {
            Log.e(TAG, "getLaunchIntentForPackage returned null");
            return;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent,
                PendingIntent.FLAG_IMMUTABLE);

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("🆘 SOS 紧急模式")
                .setContentText("紧急服务已启动，长按底部按钮触发求救")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .build();

        // Android 14+ 需要指定前台服务类型
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                    | android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private void startLocationUpdates() {
        mLocationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        if (mLocationManager == null) {
            Log.e(TAG, "Failed to get LocationManager");
            return;
        }

        try {
            if (mLocationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                mLocationManager.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        5000,   // 5 秒
                        10,     // 10 米
                        mLocationListener);
            }
            if (mLocationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                mLocationManager.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        10000,
                        20,
                        mLocationListener);
            }
        } catch (SecurityException e) {
            Log.e(TAG, "Location permission denied", e);
        }
    }

    private void stopLocationUpdates() {
        if (mLocationManager != null) {
            mLocationManager.removeUpdates(mLocationListener);
        }
    }

    /**
     * JNI: 通过 QAndroidJniObject 回调到 Qt
     */
    private static native void nativeUpdateLocation(long callback,
                                                       double lat, double lon,
                                                       double accuracy, long time);
}
