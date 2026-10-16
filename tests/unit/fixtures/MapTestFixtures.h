/**
 * @file MapTestFixtures.h
 * @brief test_map_service 用的 GPX/CSV 文本夹具
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

}  // namespace testfix

#endif  // OUTDOOR_TEST_MAP_FIXTURES_H
