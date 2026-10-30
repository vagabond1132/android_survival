/**
 * @file test_rule_condition_strategy.cpp
 * @brief RuleConditionStrategy + Factory 单元测试 (5 阶段架构重构 Phase 3)
 *
 * 覆盖:
 *   - 17 个内置策略各 1-2 case (匹配成功 + 失败)
 *   - Factory 注册 / 创建 / clear / 默认初始化
 *   - 2026-09-23 回归: altitude `cond.mid(12,1)` 下标错位 → 全灭; `in [...]` 语法
 *   - 2026-10-22: 温度 (temp_min / temp_avg) 与背负 (load) 三个新前缀
 */
#include <QtTest>

#include "src/equipment/RuleConditionStrategy.h"
#include "src/equipment/RuleConditionFactory.h"

using namespace outdoor;

class TestRuleConditionStrategy : public QObject {
    Q_OBJECT

private:
    TripParameters makeParams() {
        TripParameters p;
        p.altitudeMax = 3000;       // L3 (EquipmentAltitudeLevel: <3500 是 L3, 3500 起算 L4)
        p.days = 3;
        p.difficulty = 3;
        p.season = Season::Summer;
        p.precipitation = Precipitation::Moderate;
        p.windSpeed = 5.0;

        // 2026-09-23: 地区气候维度 (8 个新策略依赖这些取值)
        p.diurnalRange = 15;
        p.humidity = HumidityType::Humid;
        p.uvLevel = UVLevel::Extreme;
        p.windLevel = WindLevel::Gale;
        p.isRainySeason = true;
        p.isCoastal = true;
        p.isDesert = false;
        p.isPlateau = false;

        // 2026-10-22: 温度与背负维度 (temp_* / load 三个新策略依赖)
        p.tempMin = -5.0f;
        p.tempAvg = 8.0f;
        p.load = LoadStyle::Overnight;
        return p;
    }

private slots:
    void init() {
        RuleConditionFactory::initializeDefaults();
    }

    void cleanup() {
        RuleConditionFactory::clear();
    }

    // ===== Altitude =====
    void test_altitude_match() {
        AltitudeCondition s;
        QVERIFY(s.prefix() == "altitude");
        auto p = makeParams();   // altitudeMax 3500 → L3
        QVERIFY(s.matches("altitude >= L3", p));   // 3 >= 3 ✓
        QVERIFY(s.matches("altitude >= L2", p));   // 3 >= 2 ✓
        QVERIFY(!s.matches("altitude >= L4", p));  // 3 < 4 ✗
    }

    void test_altitude_invalid_level() {
        AltitudeCondition s;
        auto p = makeParams();
        QVERIFY(!s.matches("altitude >= L9", p));   // 越界
        QVERIFY(!s.matches("altitude >= LX", p));   // 非数字
    }

    // ===== Precipitation =====
    void test_precipitation_match() {
        PrecipitationCondition s;
        QCOMPARE(s.prefix(), QString("precipitation"));
        auto p = makeParams();   // moderate
        QVERIFY(s.matches("precipitation == 'moderate'", p));
        QVERIFY(!s.matches("precipitation == 'heavy'", p));
        QVERIFY(!s.matches("foo == 'moderate'", p));   // prefix 不匹配
    }

    // ===== Season =====
    void test_season_match() {
        SeasonCondition s;
        auto p = makeParams();   // Summer
        QVERIFY(s.matches("season == 'summer'", p));
        QVERIFY(!s.matches("season == 'winter'", p));
    }

    // ===== WindSpeed =====
    void test_windspeed_match() {
        WindSpeedCondition s;
        auto p = makeParams();   // 5.0
        QVERIFY(s.matches("wind_speed >= 3.0", p));   // 5 >= 3 ✓
        QVERIFY(s.matches("wind_speed >= 5.0", p));   // 5 >= 5 ✓
        QVERIFY(!s.matches("wind_speed >= 10.0", p)); // 5 < 10 ✗
        // 2026-10-22: <= 从"语法不支持"变成"按数值判定" (5 <= 3 假, 5 <= 10 真)
        QVERIFY(!s.matches("wind_speed <= 3.0", p));
        QVERIFY(s.matches("wind_speed <= 10.0", p));
    }

    // ===== 2026-10-22 新增策略: 温度 =====
    void test_temp_min_match() {
        TempMinCondition s;
        QCOMPARE(s.prefix(), QString("temp_min"));
        auto p = makeParams();   // tempMin = -5
        QVERIFY(s.matches("temp_min <= -10", p) == false);  // -5 比 -10 暖, 不触发重保暖
        QVERIFY(s.matches("temp_min <= -5", p));            // 边界含等号
        QVERIFY(s.matches("temp_min <= 0", p));
        QVERIFY(s.matches("temp_min < 0", p));
        QVERIFY(!s.matches("temp_min > 0", p));
        QVERIFY(!s.matches("temp_min abc", p));             // 非数值
    }

    void test_temp_avg_match() {
        TempAvgCondition s;
        QCOMPARE(s.prefix(), QString("temp_avg"));
        auto p = makeParams();   // tempAvg = 8
        QVERIFY(s.matches("temp_avg >= 0", p));
        QVERIFY(!s.matches("temp_avg >= 25", p));
        QVERIFY(s.matches("temp_avg <= 25", p));            // 防暑规则用 >=, 防寒用 <=
    }

    // ===== 2026-10-22 新增策略: 背负方式 =====
    void test_load_match() {
        LoadCondition s;
        QCOMPARE(s.prefix(), QString("load"));
        auto p = makeParams();   // Overnight (=2)
        QVERIFY(s.matches("load >= day_hike", p));
        QVERIFY(s.matches("load >= overnight", p));         // 过夜重装: 帐篷睡袋进清单
        QVERIFY(!s.matches("load >= expedition", p));       // 多日重装才要的东西不提前给
        QVERIFY(s.matches("load in [overnight, expedition]", p));
        QVERIFY(!s.matches("load in [day_hike, fast_pack]", p));
        QVERIFY(s.matches("load == 'overnight'", p));
        QVERIFY(!s.matches("load >= bogus", p));            // 认不出的 token 不命中
    }

    // ===== Days =====
    void test_days_match() {
        DaysCondition s;
        auto p = makeParams();   // days=3
        QVERIFY(s.matches("days >= 2", p));
        QVERIFY(s.matches("days >= 3", p));
        QVERIFY(!s.matches("days >= 4", p));
    }

    // ===== Difficulty =====
    void test_difficulty_match() {
        DifficultyCondition s;
        auto p = makeParams();   // difficulty=3
        QVERIFY(s.matches("difficulty >= 3", p));
        QVERIFY(!s.matches("difficulty >= 5", p));
        QVERIFY(!s.matches("difficulty >= 99", p));   // 越界
        QVERIFY(!s.matches("difficulty >= abc", p));  // 非数字
    }

    // ===== 2026-09-23 回归: altitude 下标错位 (mid(12,1) 读到 'L') =====
    void test_altitude_level_digit_parsing() {
        AltitudeCondition s;
        auto p = makeParams();   // altitudeMax=3000 → L3
        // 旧实现把所有 altitude 规则都判 false; 新实现必须能解析出段位数字
        QVERIFY(s.matches("altitude >= L0", p));
        QVERIFY(s.matches("altitude >= L1", p));
        QVERIFY(s.matches("altitude >= L2", p));
        QVERIFY(s.matches("altitude >= L3", p));
        QVERIFY(!s.matches("altitude >= L4", p));
        QVERIFY(!s.matches("altitude >= L5", p));
        QVERIFY(!s.matches("altitude >= L6", p));
    }

    // ===== 2026-09-23 新增策略: 数值 =====
    void test_diurnal_range_match() {
        DiurnalRangeCondition s;
        QCOMPARE(s.prefix(), QString("diurnal_range"));
        auto p = makeParams();   // diurnalRange=15
        QVERIFY(s.matches("diurnal_range >= 10", p));
        QVERIFY(s.matches("diurnal_range >= 15", p));
        QVERIFY(!s.matches("diurnal_range >= 20", p));
        // json 实写形式 "diurnal_range >= 15"
        QVERIFY(!s.matches("diurnal_range >= 99", p));
    }

    // ===== 2026-09-23 新增策略: 枚举 (含 == 与 in [...] 两种写法) =====
    void test_humidity_match() {
        HumidityCondition s;
        QCOMPARE(s.prefix(), QString("humidity"));
        auto p = makeParams();   // Humid
        QVERIFY(s.matches("humidity == 'humid'", p));
        QVERIFY(!s.matches("humidity == 'dry'", p));
        QVERIFY(s.matches("humidity in [dry, humid]", p));
        QVERIFY(!s.matches("humidity in [dry, moderate]", p));
    }

    void test_uv_level_match() {
        UVLevelCondition s;
        QCOMPARE(s.prefix(), QString("uv_level"));
        auto p = makeParams();   // Extreme
        QVERIFY(s.matches("uv_level == 'extreme'", p));
        // json 实写形式 (带引号 + 空格)
        QVERIFY(s.matches("uv_level in ['strong', 'very_strong', 'extreme']", p));
        QVERIFY(!s.matches("uv_level in ['weak', 'moderate']", p));
    }

    void test_wind_level_match() {
        WindLevelCondition s;
        QCOMPARE(s.prefix(), QString("wind_level"));
        auto p = makeParams();   // Gale
        QVERIFY(s.matches("wind_level == 'gale'", p));
        // json 实写形式
        QVERIFY(s.matches("wind_level in ['strong', 'gale']", p));
        QVERIFY(!s.matches("wind_level in ['calm', 'light']", p));
    }

    // ===== 2026-09-23 新增策略: 布尔标记 =====
    void test_bool_flags_match() {
        auto p = makeParams();   // isRainySeason=true / isCoastal=true / isDesert=false / isPlateau=false

        RainySeasonCondition rainy;
        QCOMPARE(rainy.prefix(), QString("is_rainy_season"));
        QVERIFY(rainy.matches("is_rainy_season == true", p));
        QVERIFY(!rainy.matches("is_rainy_season == false", p));

        CoastalCondition coastal;
        QVERIFY(coastal.matches("is_coastal == true", p));
        QVERIFY(!coastal.matches("is_coastal == false", p));

        DesertCondition desert;
        QCOMPARE(desert.prefix(), QString("is_desert"));
        QVERIFY(desert.matches("is_desert == false", p));
        QVERIFY(!desert.matches("is_desert == true", p));

        PlateauCondition plateau;
        QCOMPARE(plateau.prefix(), QString("is_plateau"));
        QVERIFY(plateau.matches("is_plateau == false", p));
        QVERIFY(!plateau.matches("is_plateau == true", p));
    }

    void test_bool_flag_omitted_rhs_means_true() {
        // BoolFlagCondition 是抽象基类, 用具体子类验证省略 RHS 的语义
        RainySeasonCondition rainy;
        auto p = makeParams();   // true
        QVERIFY(rainy.matches("is_rainy_season", p));         // 省略 RHS 视为 true
        QVERIFY(!rainy.matches("is_rainy_season == 0", p));   // "0" 视为 false
    }

    // ===== in [...] 语法统一 (Precipitation/Season 之前只认 ==) =====
    void test_precipitation_in_syntax() {
        PrecipitationCondition s;
        auto p = makeParams();   // Moderate
        // json 实写形式 "precipitation in [heavy, storm]"
        QVERIFY(!s.matches("precipitation in [heavy, storm]", p));
        QVERIFY(s.matches("precipitation in [light, moderate, heavy]", p));

        SeasonCondition season;
        auto q = makeParams();   // Summer
        // json 实写形式 "season in [winter, spring, autumn]"
        QVERIFY(!season.matches("season in [winter, spring, autumn]", q));
        QVERIFY(season.matches("season in [summer, winter]", q));
    }

    // ===== 2026-10-21: 降雪四档 (snow_*) 与雨档互不误触发 =====
    void test_precipitation_snow_tokens() {
        PrecipitationCondition s;
        auto p = makeParams();
        p.precipitation = Precipitation::SnowHeavy;
        QVERIFY(s.matches("precipitation in [snow_light, snow_moderate, snow_heavy, snow_storm]", p));
        QVERIFY(s.matches("precipitation == 'snow_heavy'", p));
        // 大雪不能被"强降雨需防水"这类雨档规则命中
        QVERIFY(!s.matches("precipitation in [heavy, storm]", p));
        // 反向: 大雨也不该命中雪档
        auto r = makeParams();
        r.precipitation = Precipitation::Heavy;
        QVERIFY(!s.matches("precipitation in [snow_heavy, snow_storm]", r));
    }

    // ===== Factory =====
    void test_factory_create_known() {
        auto s = RuleConditionFactory::create("altitude");
        QVERIFY(s != nullptr);
        QCOMPARE(s->prefix(), QString("altitude"));
    }

    void test_factory_create_unknown_returns_null() {
        auto s = RuleConditionFactory::create("nonexistent_prefix");
        QVERIFY(s == nullptr);
    }

    void test_factory_registered_prefixes() {
        QStringList prefixes = RuleConditionFactory::registeredPrefixes();
        QVERIFY(prefixes.contains("altitude"));
        QVERIFY(prefixes.contains("precipitation"));
        QVERIFY(prefixes.contains("season"));
        QVERIFY(prefixes.contains("wind_speed"));
        QVERIFY(prefixes.contains("days"));
        QVERIFY(prefixes.contains("difficulty"));
        // 2026-09-23 补齐的 8 个 (equipment_rules.json 实际使用)
        QVERIFY(prefixes.contains("diurnal_range"));
        QVERIFY(prefixes.contains("humidity"));
        QVERIFY(prefixes.contains("uv_level"));
        QVERIFY(prefixes.contains("wind_level"));
        QVERIFY(prefixes.contains("is_rainy_season"));
        QVERIFY(prefixes.contains("is_plateau"));
        QVERIFY(prefixes.contains("is_desert"));
        QVERIFY(prefixes.contains("is_coastal"));
        // 2026-10-22 新增 3 个: 温度 + 背负
        QVERIFY(prefixes.contains("temp_min"));
        QVERIFY(prefixes.contains("temp_avg"));
        QVERIFY(prefixes.contains("load"));
        QCOMPARE(prefixes.size(), 17);
    }

    void test_factory_clear() {
        RuleConditionFactory::clear();
        QCOMPARE(RuleConditionFactory::registeredPrefixes().size(), 0);
        // 但 initializeDefaults 仍可重复调
        RuleConditionFactory::initializeDefaults();
        QCOMPARE(RuleConditionFactory::registeredPrefixes().size(), 17);
    }

    void test_factory_idempotent_init() {
        // initializeDefaults 调多次不应重复注册
        RuleConditionFactory::initializeDefaults();
        RuleConditionFactory::initializeDefaults();
        RuleConditionFactory::initializeDefaults();
        QCOMPARE(RuleConditionFactory::registeredPrefixes().size(), 17);
    }

    void test_end_to_end_via_factory() {
        auto s = RuleConditionFactory::create("altitude");
        QVERIFY(s != nullptr);
        auto p = makeParams();
        QVERIFY(s->matches("altitude >= L3", p));
    }

    // 2026-09-23: 回归 - json 里每条规则的前缀必须全部可创建, 否则 matchCondition
    // 打 "unknown prefix" 后返回 false → 规则永久失效. 这里枚举 json 实际前缀。
    // 2026-10-22: temp_min / temp_avg / load 加入 —— 规则重写 (#85) 会用到它们。
    void test_all_json_prefixes_have_strategy() {
        const QStringList jsonPrefixes = {
            "altitude", "uv_level", "humidity", "diurnal_range", "wind_level",
            "is_rainy_season", "is_plateau", "is_desert", "is_coastal",
            "precipitation", "season", "wind_speed", "days", "difficulty",
            "temp_min", "temp_avg", "load",
        };
        for (const QString& pfx : jsonPrefixes) {
            auto s = RuleConditionFactory::create(pfx);
            QVERIFY2(s != nullptr, qPrintable("missing strategy for prefix: " + pfx));
            QCOMPARE(s->prefix(), pfx);
        }
    }
};

QTEST_MAIN(TestRuleConditionStrategy)
#include "test_rule_condition_strategy.moc"