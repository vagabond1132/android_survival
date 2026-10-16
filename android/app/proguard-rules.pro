# 荒野手册 ProGuard 规则
# 保留 Qt 类
-keep class org.qtproject.** { *; }
-keep class org.qtproject.qt.android.** { *; }

# 保留应用类
-keep class com.outdoor.survival.** { *; }

# 保留 JNI 调用
# 关键: 必须用 -keepclasseswithmembernames 而不是 -keep, 否则 dlsym 找不到
# JNI 符号 (类名被混淆后 Java_com_outdoor_survival_EmergencyService_... 失效
# → UnsatisfiedLinkError → 启动期 ClassNotFoundException, 与 tombstone 同模式)
-keepclasseswithmembernames class * {
    native <methods>;
}

# 关键: 显式保留 OutdoorSurvivalApp 整个类 (R8 可能裁剪未直接引用的 Application)
# 因为 AndroidManifest 用字符串引用 ".OutdoorSurvivalApp", R8 默认 -keep 不抓 manifest 引用
-keep public class com.outdoor.survival.OutdoorSurvivalApp {
    public <init>();
    public *;
}
-keep public class com.outdoor.survival.EmergencyService {
    public <init>();
    public *;
}

# 保留 Android 四大组件 (manifest 字符串引用, R8 默认不抓)
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.app.Activity

# 保留 QML 反射调用
-keepclassmembers class * {
    @Q_PROPERTY *;
    @Q_INVOKABLE *;
    @Q_SLOT *;
}

# 关键: 保留 QML 反射需要的所有 QObject 子类成员
# 原因: main.cpp 用 setContextProperty("firstAidService", theApp.firstAid()) 注册
# 14 个 outdoor.* C++ service. QML 调 service.method() 通过 Qt metaobject 反射,
# R8 默认会裁剪未被 Java 代码直接引用的 C++ service 类对应的 Java 反射元数据.
#
# 注意: C++ namespace `outdoor::*` 在编译时**不**生成对应的 Java 类. R8 看的是
# Java 包. 但 Qt 的 QtQml 内部生成的 qmltyperegistrar 会创建 Java 反射元数据
# (含 QObject 子类信息), 这些必须保留.
#
# 策略: 用反射保留 Qt 自身的 QML 反射元数据 + Qt 内部生成的类.
# 注: Qt 6.7 的 Java 绑定 (Qt6Android.jar) 没有 QtCore.QObject / QtQml.QObject
# Java 类 (这些是 C++ 名字), 只保留 java.lang.Object 子类即可.
-keep class * extends java.lang.Object { *; }
# Qt metaobject 反射必备: 保留 QObject 子类的所有 public 成员
# (含 Q_INVOKABLE/Q_PROPERTY/Q_SIGNAL), 避免 R8 重命名导致 QML 反射失败
# 注: 这里保的是 com.outdoor.survival.* 命名空间下由 Qt 自动生成的 Java
# 桥接类 (C++ QObject 子类的 Java 反射), 不是 Qt 自身.
-keepclassmembers class com.outdoor.survival.** extends java.lang.Object {
    public <init>(...);
    public <methods>;
    public <fields>;
}

# 保留 QML metaobject 反射需要的元数据
-keepattributes QtSignal, QtSlot, QtProperty, QML*

# 保留 R 类
-keep class **.R$* { *; }
-keepclassmembers class **.R$* {
    public static <fields>;
}

# 保留枚举
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 警告抑制
-dontwarn org.qtproject.qt.android.**
-dontwarn org.qtproject.qt.**
