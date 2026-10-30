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
    // 2026-10-26「轨迹/标注点精度到 1 m」第一处改动: 采样频率与 provider 抢帧.
    //   ① GPS 原来 3 秒一帧 —— Android 的 GNSS 芯片本身是 1 Hz, 那 3 秒是把 2/3 的
    //      定帧直接丢掉 (C++ 侧想按精度择优/多帧平均都没有原料).
    //   ② GPS 与 NETWORK 注册的是同一个 listener: 网络定位是 10~100 m 级, 它和 GPS
    //      一起往同一路 native 入口灌, 于是"手里最好的一帧"经常是网络那条.
    //      现在 GPS 刚定上帧时, 30 秒窗口内的网络定位直接丢弃 (GPS 定不上时仍然放行,
    //      室内/峡谷不能因为"要精度"就没有位置).
    private long mLastGpsFixAtMs = 0L;
    private static final long GPS_PRIORITY_WINDOW_MS = 30000L;

    private final LocationListener mLocationListener = new LocationListener() {
        @Override
        public void onLocationChanged(Location location) {
            final boolean fromGps = LocationManager.GPS_PROVIDER.equals(location.getProvider());
            if (!fromGps && mLastGpsFixAtMs > 0
                    && System.currentTimeMillis() - mLastGpsFixAtMs < GPS_PRIORITY_WINDOW_MS) {
                Log.d(TAG, "Network fix dropped (GPS fix delivered within "
                        + (GPS_PRIORITY_WINDOW_MS / 1000) + "s): " + location.getAccuracy() + "m");
                return;
            }
            deliverLocation(location);
            if (fromGps) {
                mLastGpsFixAtMs = System.currentTimeMillis();
            }
        }

        @Override
        public void onStatusChanged(String provider, int status, Bundle extras) {}

        @Override
        public void onProviderEnabled(String provider) {}

        @Override
        public void onProviderDisabled(String provider) {}
    };

    /** 把一条 Location 送到 native (listener 与冷启动补帧共用同一条出口). */
    private void deliverLocation(Location location) {
        // 通过 JNI 桥接把位置传给 Qt
        double lat = location.getLatitude();
        double lon = location.getLongitude();
        double accuracy = location.getAccuracy();
        // 2026-10-22 #98: 高程以前根本没传 (native 签名里没这一项), 所以走 SOS
        // 前台服务这条路的"海拔"永远是空. hasAltitude() 为假时传 NaN, C++ 侧
        // 按"未知"处理 —— 传 0 会被读成"海平面 0 米".
        double altitude = location.hasAltitude() ? location.getAltitude() : Double.NaN;
        long time = location.getTime();

        Log.d(TAG, "Location: " + lat + ", " + lon + " (" + location.getProvider()
                + ", accuracy: " + accuracy + "m, altitude: " + altitude + "m)");

        // 调用 Qt 端的 native slot
        // C++ 端用 EmergencyService::instance() 静态指针找 service, 不需要 callback 句柄.
        // 仍保留 nativeUpdateLocation 形参兼容 (jlong 0 占位), 不传实际句柄.
        nativeUpdateLocation(0L, lat, lon, accuracy, altitude, time);
    }

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
            // 2026-10-22 #98: minDistance 从 10 米 / 20 米改成 0 —— SOS 场景里人往往
            // 就站在原地等, 按位移过滤会让这服务整个期间不出一次定位.
            // 2026-10-26「精度到 1 m」: GPS 间隔 3000 -> 1000 ms. Android GNSS 芯片本身
            // 1 Hz 出帧, 3 秒等于主动丢 2/3 的定帧 —— 下游想按精度择优、多帧平均都没有原料.
            // 多出来的电量代价换的是"手里能挑到最好的一帧", 前台服务本来就在耗电档位里.
            if (mLocationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                mLocationManager.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        1000,   // 1 秒 (芯片原生 1 Hz, 不再丢帧)
                        0,
                        mLocationListener);
            }
            // 网络定位只做 GPS 定不上时的兜底, 间隔从 10 s 放到 5 s 是配合上面那条:
            // 它进来的每一帧都要和 GPS 抢同一个 native 入口, 帧越少抢帧机会越少.
            if (mLocationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                mLocationManager.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        5000,
                        0,
                        mLocationListener);
            }
            seedFromLastKnown(mLocationManager);
        } catch (SecurityException e) {
            Log.e(TAG, "Location permission denied", e);
        }
    }

    /**
     * 服务刚起来时 requestLocationUpdates 的第一帧通常要几秒到几十秒, 先用系统缓存的
     * 上一次定位垫一帧, 仪表不至于整片 "--". 传的是这条缓存自己的 getTime(), 所以
     * C++ 侧 positionAgeNote 会说得出"这是几分钟前的", 不会把它当实时值 (不给假读数).
     * 只接受 30 分钟以内的缓存, 更老的没有参考价值.
     */
    private void seedFromLastKnown(LocationManager manager) {
        final long maxAgeMs = 30L * 60L * 1000L;
        final long now = System.currentTimeMillis();
        Location best = null;
        try {
            final String[] providers = {
                    LocationManager.GPS_PROVIDER,
                    LocationManager.NETWORK_PROVIDER,
                    LocationManager.PASSIVE_PROVIDER };
            for (String p : providers) {
                Location l = manager.getLastKnownLocation(p);
                if (l == null || now - l.getTime() > maxAgeMs) continue;
                if (best == null || l.getAccuracy() < best.getAccuracy()) {
                    best = l;
                }
            }
        } catch (SecurityException e) {
            Log.e(TAG, "Location permission denied for lastKnownLocation", e);
            return;
        }
        if (best == null) {
            Log.i(TAG, "No usable lastKnownLocation to seed from");
            return;
        }
        Log.i(TAG, "Seeding from cached " + best.getProvider() + " fix ("
                + ((now - best.getTime()) / 1000) + "s old)");
        // 走的是与 listener 同一条出口, 但不更新 mLastGpsFixAtMs —— 缓存帧不是实时帧,
        // 不该让一条几小时前的 GPS 缓存在头 30 秒里把实时网络定位全挡掉.
        deliverLocation(best);
    }

    private void stopLocationUpdates() {
        if (mLocationManager != null) {
            mLocationManager.removeUpdates(mLocationListener);
        }
    }

    /**
     * JNI: 通过 QAndroidJniObject 回调到 Qt
     * 签名必须与 C++ 侧 Java_com_outdoor_survival_EmergencyService_nativeUpdateLocation
     * 逐项对上 (含 altitude), 否则运行期 UnsatisfiedLinkError.
     */
    private static native void nativeUpdateLocation(long callback,
                                                       double lat, double lon,
                                                       double accuracy, double altitude,
                                                       long time);
}
