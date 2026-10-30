/**
 * @file MapTestFixtures.h
 * @brief test_map_service 用的 GPX/KML/CSV 文本夹具
 *
 * 2026-10-16: 夹具原本写在 test_map_service.cpp 里, 结果整个测试链接失败
 *   "undefined reference to vtable for TestMapService"。原因是 moc 不认 raw
 *   string literal: 扫描器把内容里的 `//`(xmlns URL) 当行注释吃掉, 之后的
 *   `)"` 终止符再也对不上, moc 报 "No relevant classes found", 于是 .moc
 *   生成 0 字节。把含 URL 的夹具挪到头文件即可 — moc 不展开 #include,
 *   也不会处理不含 Q_OBJECT 的普通头文件。
 *
 * 规则: 测试 .cpp 里不要写带 `//` 的 raw string, 需要就放头文件。
 */
#ifndef OUTDOOR_TEST_MAP_FIXTURES_H
#define OUTDOOR_TEST_MAP_FIXTURES_H

namespace testfix {

inline const char* gpxFixture() { return R"XML(<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>泰山测试线</name>
    <trkseg>
      <trkpt lat="36.250" lon="117.100"><ele>150</ele><time>2026-10-01T08:00:00Z</time></trkpt>
      <trkpt lat="36.252" lon="117.102"><ele>650</ele><time>2026-10-01T09:00:00Z</time></trkpt>
      <trkpt lat="36.254" lon="117.104"><ele>1545</ele><time>2026-10-01T10:00:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>
)XML"; }

// 2026-10-27 #134: 一份没有任何 <time> 的 GPX (不少手持机和导出工具就是这么写的),
// 再压一个缺 <ele> 的点和一个 lat="0" lon="0" 的哨兵点.
// 钉的是"文件没给就整条留空": 老代码把 startTime 填成导入的这一刻、给每点编
// addSecs(i*5) 节拍、缺高程写 0 —— 三个假读数, 其中节拍那条会让 getTrackStats
// 把散步读成 8 km/h.
inline const char* gpxNoTimeFixture() { return R"XML(<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>无时刻测试线</name>
    <trkseg>
      <trkpt lat="36.300" lon="117.200"><ele>420</ele></trkpt>
      <trkpt lat="36.302" lon="117.202"></trkpt>
      <trkpt lat="0" lon="0"><ele>0</ele></trkpt>
      <trkpt lat="36.304" lon="117.204"><ele>980</ele></trkpt>
    </trkseg>
  </trk>
</gpx>
)XML"; }

// 2026-10-27 #134: 两步路 (2bulu) 导出格式的缩样, 前 6 个 <gx:coord> / 前 5 个
// <when> 与 3 个 Placemark 名字全部照抄真机文件
// "2025-10-26 空心山-拔槊泉-劈山-万粮峪村-响呼噜泉-1792749857842.kml" 的原值.
// 保留真结构里所有会让解析器踩坑的地方:
//   * 轨迹不在 <LineString> 里, 在 <gx:Track> 里, 而且 coord 与 when 是两个
//     先后排列的平行列表 (不是交织的) —— 老解析器因此一个点都读不到;
//   * when 比 coord 少一个, 用来钉死"缺时刻就缺着, 不许编 5 秒节拍";
//   * 标题在 <Document><name> 的 CDATA 里, 而 <Folder> 与轨迹 Placemark 各自
//     还有 <name> (标注点/轨迹/轨迹片段1), 标注点甚至也叫一个地名 —— 老解析器
//     是"最后一个 name 覆盖前一个", 于是轨迹名随机变成某个标注点;
//   * 标注点带 <TimeStamp><when> 与 <Point><coordinates>, 不能混进轨迹点;
//   * gx:Track 内部还挂了一份 GxTrackExtendedData (每点 speed,hr 的大串);
//   * <Document><ExtendedData> 里带着它 App 自己算的里程/爬升/下降 (数值照抄真文件),
//     用户是拿这几个数对账的 —— 导入要把升降抓下来存进 meta, 读数按
//     "文件自述优先, 没有才用平滑口径" 取舍 (2026-10-29 #168 A44).
inline const char* kmlTbuluFixture() { return R"XML(<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document id="TbuluKmlVersion2">
    <name><![CDATA[2025-10-26 空心山-拔槊泉-劈山-万粮峪村-响呼噜泉]]>
    </name>
    <ExtendedData>
      <Data name="TrackId"><value>63001874</value></Data>
      <Data name="BeginTime"><value>1761439194000</value></Data>
      <Data name="EndTime"><value>1761465301000</value></Data>
      <Data name="Distance"><value>15594.0</value></Data>
      <Data name="ElevationGain"><value>720.4700000000003</value></Data>
      <Data name="ElevationLoss"><value>719.3299999999999</value></Data>
    </ExtendedData>
    <Style id="TrackStyle_n">
      <LineStyle><color>ff1034e8</color><width>5</width></LineStyle>
    </Style>
    <Folder id="TbuluHisPointFolder">
      <name>标注点</name>
      <Placemark id="startPoint">
        <name>起点</name>
        <TimeStamp><when>2025-10-26T00:39:55Z</when></TimeStamp>
        <Point><coordinates>117.3067133,36.561245,304.7 </coordinates></Point>
      </Placemark>
      <Placemark id="realPoint">
        <name><![CDATA[村委会]]>
        </name>
        <styleUrl>#MarkerStylePicture</styleUrl>
        <TimeStamp><when>2025-10-26T00:39:55Z</when></TimeStamp>
        <Point><coordinates>117.3067133,36.561245,304.7 </coordinates></Point>
        <ExtendedData>
          <Data name="Accuracy"><value>1.7</value></Data>
          <Data name="Speed"><value>0.18941778</value></Data>
        </ExtendedData>
      </Placemark>
    </Folder>
    <Folder id="TbuluTrackFolder">
      <name>轨迹</name>
      <Placemark>
        <name><![CDATA[轨迹片段1]]>
        </name>
        <description>
          <div>轨迹点数:6</div>
          <div>本段里程:61.4米</div>
        </description>
        <gx:Track>
          <gx:coord>117.3067133 36.561245 304.7</gx:coord>
          <gx:coord>117.3066235 36.5612158 304.7</gx:coord>
          <gx:coord>117.3065509 36.5611419 306.46</gx:coord>
          <gx:coord>117.3064604 36.561055 308.11</gx:coord>
          <gx:coord>117.3063875 36.5609632 309.31</gx:coord>
          <gx:coord>117.3063109 36.56087 310.38</gx:coord>
          <when>2025-10-26T00:39:55Z</when>
          <when>2025-10-26T00:40:50Z</when>
          <when>2025-10-26T00:40:58Z</when>
          <when>2025-10-26T00:41:08Z</when>
          <when>2025-10-26T00:41:16Z</when>
          <ExtendedData>
            <Data name="GxTrackExtendedData"><value>0.18,0.0;0.21,0.0;0.19,0.0;0.2,0.0;0.22,0.0</value></Data>
            <Data name="PauseTimes"><value></value></Data>
          </ExtendedData>
        </gx:Track>
      </Placemark>
    </Folder>
  </Document>
</kml>
)XML"; }

// 2026-10-27 #134: Google Earth / 奥维交互式地图的 KML 是另一套写法 —— 线在
// <LineString><coordinates> 里, "lon,lat,alt" 用空白分隔, 一般没有逐点时刻.
// 旧代码只认这一种, 现在两种都要能导; 这里同时压一条越界坐标, 验它不进轨迹.
inline const char* kmlLineStringFixture() { return R"XML(<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>我的地点</name>
    <Placemark>
      <name>奥维测试线</name>
      <TimeSpan><begin>2026-10-01T08:00:00Z</begin><end>2026-10-01T10:00:00Z</end></TimeSpan>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>
          117.100,36.250,150
          117.102,36.252,650
          0,0,0
          117.104,36.254,1545
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
)XML"; }

}  // namespace testfix

#endif  // OUTDOOR_TEST_MAP_FIXTURES_H
