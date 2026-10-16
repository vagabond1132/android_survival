/**
 * @file ImageColorExtractor.h
 * @brief 图片主色提取 (P0: 图鉴拍照匹配修复, 2026-09-14)
 *
 * 之前 FieldGuideImagePickPage 硬编码 HSV {h:90,s:60,v:80} 调 matchByColor,
 * 跟用户选/拍的图完全无关 (假匹配). 本类用 Qt QImage 网格采样 (默认 8x8),
 * 算 RGB 平均 → 转 HSV, 作为真实主色.
 *
 * 性能: 8x8=64 像素采样, 任何图片 < 1ms, 不阻塞 UI.
 * 不依赖 OpenCV.
 */
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QImage>

class ImageColorExtractor : public QObject {
    Q_OBJECT
public:
    explicit ImageColorExtractor(QObject* parent = nullptr);

    /**
     * @brief 从图片文件提取主色 HSV
     * @param filePath 本地文件路径 (如 /sdcard/Pictures/xxx.jpg)
     * @return {h: 0-359, s: 0-100, v: 0-100, r: 0-255, g: 0-255, b: 0-255, ok: bool, error: ""}
     *         失败时 ok=false, error 含原因.
     */
    Q_INVOKABLE QVariantMap extractFromFile(const QString& filePath, int gridSize = 8);

    /**
     * @brief 从 QImage 提取主色 HSV (QML Image 元素 source 可用)
     * @param image 已加载的 QImage
     */
    Q_INVOKABLE QVariantMap extractFromImage(const QImage& image, int gridSize = 8);

    /**
     * @brief 2026-09-14: 多区域颜色分析 (按 4 象限)
     * 解决单点主色被背景或单色物体主导, 匹配不相关的问题.
     * 4 区域: 左上/右上/左下/右下, 每个区域独立网格采样,
     * 排除接近灰色的背景像素 (饱和度 < 15%).
     * @return {ok, error, regions: [{x, y, h, s, v, r, g, b, weight}, ...]}
     *   weight: 0.0-1.0, 该区域在主色判定中的权重 (按饱和度/与全局色差异)
     */
    Q_INVOKABLE QVariantMap extractRegionsFromFile(const QString& filePath, int gridSize = 4);

private:
    // RGB → HSV (H: 0-359, S: 0-100, V: 0-100)
    static void rgbToHsv(int r, int g, int b, int& h, int& s, int& v);
};
