/**
 * @file CommonOptions.h
 * @brief 通用颜色 token + 下拉选项 (2026-09-11 一次性)
 *
 * 之前用 QML pragma Singleton + import "components/CommonOptions.qml",
 * qmlcachegen 静态编译下不工作 (run.txt 18:23-18:26 报 "no such directory").
 * 改用 C++ 单例 + qmlRegisterSingletonInstance, 与 App 同样的注册方式.
 */
#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QColor>

class CommonOptions : public QObject {
    Q_OBJECT
    // === 颜色 token ===
    Q_PROPERTY(QColor colorBg       READ colorBg       CONSTANT)
    Q_PROPERTY(QColor colorSurface  READ colorSurface  CONSTANT)
    Q_PROPERTY(QColor colorText     READ colorText     CONSTANT)
    Q_PROPERTY(QColor colorTextMuted READ colorTextMuted CONSTANT)
    Q_PROPERTY(QColor colorAccent   READ colorAccent   CONSTANT)
    Q_PROPERTY(QColor colorWarn     READ colorWarn     CONSTANT)
    Q_PROPERTY(QColor colorDanger   READ colorDanger   CONSTANT)
    Q_PROPERTY(QColor colorSuccess  READ colorSuccess  CONSTANT)
public:
    explicit CommonOptions(QObject* parent = nullptr) : QObject(parent) {}

    QColor colorBg()       const { return QColor("#1E272E"); }
    QColor colorSurface()  const { return QColor("#263238"); }
    QColor colorText()     const { return QColor("#ECEFF1"); }
    QColor colorTextMuted() const { return QColor("#B0BEC5"); }
    QColor colorAccent()   const { return QColor("#1976D2"); }
    QColor colorWarn()     const { return QColor("#F57C00"); }
    QColor colorDanger()   const { return QColor("#D32F2F"); }
    QColor colorSuccess()  const { return QColor("#4CAF50"); }

    // === 下拉选项 (QVariantList of QVariantMap) ===
    Q_INVOKABLE QVariantList difficultyOptions() const;
    Q_INVOKABLE QVariantList daysOptions() const;
    Q_INVOKABLE QVariantList distanceOptions() const;
    Q_INVOKABLE QVariantList monthOptions() const;
    Q_INVOKABLE QVariantList kingdomOptions() const;
    Q_INVOKABLE QVariantList routeNatureOptions() const;

    // === 格式化 ===
    Q_INVOKABLE QString formatDistance(double km) const;
    Q_INVOKABLE QString formatElevation(double m) const;
    Q_INVOKABLE QString formatDuration(qint64 sec) const;

    // === 标签数组 ===
    Q_INVOKABLE QString difficultyLabel(int level) const;
    Q_INVOKABLE QString routeNatureLabel(const QString& key) const;
};
