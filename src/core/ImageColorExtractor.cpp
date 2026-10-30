/**
 * @file ImageColorExtractor.cpp
 * @brief 见同名 header
 */

#include "ImageColorExtractor.h"
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QDebug>

ImageColorExtractor::ImageColorExtractor(QObject* parent) : QObject(parent) {}

// 2026-10-23 #115 (A19): `error` 是**给用户看的一句中文** —— FieldGuideImagePickPage
//   把它直接拼进页面上的 note, 原来这里是 "file not found: <绝对路径>" /
//   "image decode failed: <Qt 原文>", 用户在自己手机上看到的是一串英文加一串
//   /data/user/0/..., 只会以为是自己拍的照片坏了. 技术原文改放 `detail`, 只进
//   console.warn → release 包的真日志 (app 沙盒 stage0.log), 那里才是排查用的地方.
//   同一个包里的两条通道: error=中文原因(可见), detail=原文(只在日志).
QVariantMap ImageColorExtractor::extractFromFile(const QString& filePath, int gridSize) {
    QVariantMap result;
    result["ok"] = false;
    result["error"] = "";

    if (filePath.isEmpty()) {
        result["error"] = QStringLiteral("还没有可选的图片");
        result["detail"] = QStringLiteral("empty path");
        return result;
    }

    QString localPath = filePath;
    // 兼容 "file:///path" URI 形式
    if (localPath.startsWith("file://")) {
        localPath = localPath.mid(7);
    }

    if (!QFile::exists(localPath)) {
        // 最常见的一支: Android 11+ 的 content:// URI 没先复制进沙盒就当本地路径用.
        //   这句中文只说"读不到", 具体是 URI 还是路径丢了, 看 detail.
        result["error"] = QStringLiteral("这张图片读不到, 换一张试试");
        result["detail"] = QStringLiteral("file not found: ") + localPath;
        return result;
    }

    // 用 QImageReader 加载, 避免大图爆内存 (自动按 QImageReader 缩放)
    QImageReader reader(localPath);
    reader.setAutoTransform(true);  // 尊重 EXIF 旋转
    QImage img = reader.read();
    if (img.isNull()) {
        result["error"] = QStringLiteral("这张图片打不开 (格式不支持或已损坏)");
        result["detail"] = QStringLiteral("image decode failed: ") + reader.errorString();
        return result;
    }

    return extractFromImage(img, gridSize);
}

QVariantMap ImageColorExtractor::extractFromImage(const QImage& image, int gridSize) {
    QVariantMap result;
    result["ok"] = false;
    result["error"] = "";

    if (image.isNull()) {
        result["error"] = QStringLiteral("图片是空的");
        result["detail"] = QStringLiteral("null image");
        return result;
    }

    if (gridSize < 1) gridSize = 1;
    if (gridSize > 64) gridSize = 64;

    int w = image.width();
    int h = image.height();
    if (w == 0 || h == 0) {
        result["error"] = QStringLiteral("这张图片尺寸为 0, 读不出颜色");
        result["detail"] = QStringLiteral("zero-size image");
        return result;
    }

    // 网格采样: 步长 = w/gridSize, h/gridSize, 中心点采样
    long long sumR = 0, sumG = 0, sumB = 0;
    int count = 0;
    for (int gy = 0; gy < gridSize; ++gy) {
        int y = (gy * h + h / 2) / gridSize;
        if (y >= h) y = h - 1;
        for (int gx = 0; gx < gridSize; ++gx) {
            int x = (gx * w + w / 2) / gridSize;
            if (x >= w) x = w - 1;
            QColor c = image.pixelColor(x, y);
            sumR += c.red();
            sumG += c.green();
            sumB += c.blue();
            ++count;
        }
    }

    int avgR = int(sumR / count);
    int avgG = int(sumG / count);
    int avgB = int(sumB / count);

    int hh, ss, vv;
    rgbToHsv(avgR, avgG, avgB, hh, ss, vv);

    result["h"] = hh;
    result["s"] = ss;
    result["v"] = vv;
    result["r"] = avgR;
    result["g"] = avgG;
    result["b"] = avgB;
    result["ok"] = true;
    return result;
}

void ImageColorExtractor::rgbToHsv(int r, int g, int b, int& h, int& s, int& v) {
    double rf = r / 255.0;
    double gf = g / 255.0;
    double bf = b / 255.0;
    double maxC = qMax(rf, qMax(gf, bf));
    double minC = qMin(rf, qMin(gf, bf));
    double delta = maxC - minC;

    // V (0-100)
    v = int(maxC * 100.0 + 0.5);

    // S (0-100)
    if (maxC < 0.0001) {
        s = 0;
    } else {
        s = int((delta / maxC) * 100.0 + 0.5);
    }

    // H (0-359)
    if (delta < 0.0001) {
        h = 0;
    } else if (maxC == rf) {
        h = int(60.0 * ((gf - bf) / delta) + 0.5);
        if (h < 0) h += 360;
    } else if (maxC == gf) {
        h = int(60.0 * ((bf - rf) / delta) + 2.0) + 0.5;
    } else {
        h = int(60.0 * ((rf - gf) / delta) + 4.0) + 0.5;
    }
    if (h < 0) h += 360;
    if (h >= 360) h -= 360;
}

// 2026-09-15: 多区域颜色分析 (4 象限), 修复 ld.lld 链接错误
// 见 header 注释: 左上/右上/左下/右下, 每区域网格采样, 排除饱和度<15% 的背景像素.
QVariantMap ImageColorExtractor::extractRegionsFromFile(const QString& filePath, int gridSize) {
    QVariantMap result;
    result["ok"] = false;
    result["error"] = "";

    if (filePath.isEmpty()) {
        result["error"] = QStringLiteral("还没有可选的图片");
        result["detail"] = QStringLiteral("empty path");
        return result;
    }

    QString localPath = filePath;
    if (localPath.startsWith("file://")) {
        localPath = localPath.mid(7);
    }
    if (!QFile::exists(localPath)) {
        result["error"] = QStringLiteral("这张图片读不到, 换一张试试");
        result["detail"] = QStringLiteral("file not found: ") + localPath;
        return result;
    }

    QImageReader reader(localPath);
    reader.setAutoTransform(true);
    QImage img = reader.read();
    if (img.isNull()) {
        result["error"] = QStringLiteral("这张图片打不开 (格式不支持或已损坏)");
        result["detail"] = QStringLiteral("image decode failed: ") + reader.errorString();
        return result;
    }

    if (gridSize < 1) gridSize = 1;
    if (gridSize > 64) gridSize = 64;

    int w = img.width();
    int h = img.height();
    if (w == 0 || h == 0) {
        result["error"] = QStringLiteral("这张图片尺寸为 0, 读不出颜色");
        result["detail"] = QStringLiteral("zero-size image");
        return result;
    }

    // 4 象限: (x0, y0, x1, y1) 闭区间
    struct Quad { int x0, y0, x1, y1; const char* name; };
    Quad quads[4] = {
        { 0,     0,     w / 2, h / 2, "TL" },
        { w / 2, 0,     w,     h / 2, "TR" },
        { 0,     h / 2, w / 2, h,     "BL" },
        { w / 2, h / 2, w,     h,     "BR" }
    };

    // 先算一次全局主色, 后面用色差做 weight
    int gH = 0, gS = 0, gV = 0;
    {
        QVariantMap g = extractFromImage(img, gridSize);
        if (g.value("ok").toBool()) {
            gH = g.value("h").toInt();
            gS = g.value("s").toInt();
            gV = g.value("v").toInt();
        }
    }

    QVariantList regions;
    for (int q = 0; q < 4; ++q) {
        const Quad& qd = quads[q];
        int rw = qd.x1 - qd.x0;
        int rh = qd.y1 - qd.y0;
        if (rw < 1 || rh < 1) continue;

        long long sumR = 0, sumG = 0, sumB = 0;
        int count = 0;
        int bgSkip = 0;  // 被当作背景的像素数

        for (int gy = 0; gy < gridSize; ++gy) {
            int y = qd.y0 + (gy * rh + rh / 2) / gridSize;
            if (y >= img.height()) y = img.height() - 1;
            for (int gx = 0; gx < gridSize; ++gx) {
                int x = qd.x0 + (gx * rw + rw / 2) / gridSize;
                if (x >= img.width()) x = img.width() - 1;
                QColor c = img.pixelColor(x, y);
                int hh, ss, vv;
                rgbToHsv(c.red(), c.green(), c.blue(), hh, ss, vv);
                if (ss < 15) { ++bgSkip; continue; }  // 低饱和当作背景跳过
                sumR += c.red();
                sumG += c.green();
                sumB += c.blue();
                ++count;
            }
        }

        if (count == 0) {
            // 整区域都是背景, 跳过
            continue;
        }

        int avgR = int(sumR / count);
        int avgG = int(sumG / count);
        int avgB = int(sumB / count);
        int hh, ss, vv;
        rgbToHsv(avgR, avgG, avgB, hh, ss, vv);

        // weight: 饱和度 0-100 → 0.0-0.6, 与全局色 hue 差 (0-180) → 0.0-0.4
        double w1 = qBound(0.0, ss / 100.0 * 0.6, 0.6);
        int dh = qAbs(hh - gH);
        if (dh > 180) dh = 360 - dh;
        double w2 = qBound(0.0, dh / 180.0 * 0.4, 0.4);
        double weight = w1 + w2;

        QVariantMap r;
        r["name"] = QString(qd.name);
        r["x"] = qd.x0;
        r["y"] = qd.y0;
        r["regionW"] = rw;
        r["regionH"] = rh;
        r["h"] = hh;       // hue 0-359 (与 header doc 一致)
        r["s"] = ss;       // saturation 0-100
        r["v"] = vv;       // value 0-100
        r["r"] = avgR;
        r["g"] = avgG;
        r["b"] = avgB;
        r["weight"] = weight;
        r["sampleCount"] = count;
        r["bgSkipped"] = bgSkip;
        regions.append(r);
    }

    result["regions"] = regions;
    result["globalH"] = gH;
    result["globalS"] = gS;
    result["globalV"] = gV;
    result["ok"] = true;
    return result;
}
