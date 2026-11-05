# 路线推荐升级为多维评分 · 设计（2026-11-05）

> 需求库 **#2**（任务 #2）。需求行 `10-需求清单/需求清单与实现状态.md:159` 的 **5.8 路线推荐**，状态从
> `📝 设计中` 进到这里定义的落地口径。
>
> 本 spec 是**设计定稿**，不含实现。所有实测数字都标了取法；实现阶段以本文为唯一依据，改任何算式都要回头改本文。

---

## 一、要解决的问题

今天「路线推荐」这件事在代码里**不存在**，实测三条：

| 事实 | 位置 |
|---|---|
| `recommend(int limit = 10)` 的全部实现是 `return getMostVisited(limit)`，注释写「简单推荐：按访问次数」 | `src/routes/RouteService.cpp:1297-1300` |
| `getMostVisited` 的排序是 `ORDER BY visit_count DESC`，而 `visit_count` 由**打开详情页**时 `incrementVisitCount` 累加 | `RouteService.cpp:1087-1089`、`qml/pages/RouteDetailPage.qml:102` |
| `recommend()` 在全部 QML 里 **0 处调用** | grep `recommend(` 只命中 C++ 与 doc |

也就是说：库里有 755 条路线（`isRecommended` 闸门后页面实际拿到 **753** 条，见 §6.1），页面按**目录序**（`RouteListPage.qml:160` 组按省码位序、`:166` 组内按 plate 编号）列出全部，**没有任何一条"该走哪条"的判断**。

目标：给出一条能按「**我实际走过什么**」来排序的推荐，并且每条推荐都带着**为什么是它**的理由行。

---

## 二、决策记录（用户拍板项）

| # | 决策 | 来源 | 备注 |
|---|---|---|---|
| D1 | 档案锚 = **实际走过的路线**（打卡），不用浏览数、不用收藏 | 用户「应该按照实际走过的线路来推测」 | `visit_count` 是浏览数，用它推体能是骗人 |
| D2 | 需要**新增打卡入口**并真正建表写入 | 用户选「补上『我走过了』打卡」 | 现有 `track_records` 是死表，见 §4.2 |
| D3 | 呈现落点 = **RouteListPage 页头带下方一条「推荐带」**，目录序不动 | 用户选「路线页顶部加一条推荐带」 | |
| D4 | **推荐带跟随筛选**，且把目录列表的过滤口径统一到 C++（只留一套过滤实现） | 用户选「乙：吃筛选，过滤统一到 C++」 | 代价与前置动作见 §6.1 |
| D5 | 冷启动（0 条打卡）时**照显示入门档**，眉题明说是默认 | 用户选「推入门档，并明说是默认」 | |
| D6 | 打分实现 = **纯函数排序器 `RouteRanker`**，权重写死在代码里 | 用户选「走 A（纯函数排序器）」 | |
| D7 | `N < 3` 时只推同级或更低难度；季节不在窗口不踢出（降权） | Agent 推荐值，用户未否 | **可在真机跑两周后翻**，翻只动 `RouteRanker` 的两个常量 |

---

## 三、数据家底（2026-11-05 实测，取法都是 `node -e` 读 `assets/data/routes.json`）

**总量 755 条，覆盖 33 个省级单位。** 单省最多 四川 91、云南 58、西藏 47；**中位 23 条**；只有 3 个省不足 5 条。

可作为维度的字段填充率：

| 字段 | 有值 | 备注 |
|---|---|---|
| `difficulty`（1–5★） | **755/755** | 分布 1★159 / 2★304 / 3★174 / 4★75 / 5★43 |
| `distance_km` / `duration_hours` / `days_needed` | 755/755 | `days_needed`：1 天 **577**、2 天 103、3 天 36、≥4 天仅 39 → **区分力极低** |
| `elevation_gain_m` / `max_altitude_m` | 755/755 | |
| `best_season` | 755/755 | 是 `["4月","5月","9月","10月"]` 这种**月份 token 数组**；**全库 0 条写「全年」** |
| `score`（预烘综合分） | **727/755** | 值域 50–97；`scoreDetail` 11 分项之和 == score（727/727 成立） |
| `province` | 755/755 | |
| `trailhead` 坐标 | 755/755 有值 | 但见下面第 1 颗雷 |
| `associated_species`（危险物种关联） | **40/755** | 见第 2 颗雷 |
| `waypoints`（实测轨迹） | 6/755 | |

### 三颗雷（直接砍掉了原本想做的维）

1. **「离你多远」多数线说不出口。** 起点坐标 755/755 都有值，但 749 条是 `coord_source = "editorial_estimate"`（编校估计），只有 6 条是 `gps_track_2bulu`。按 `coord_precision_m` 分桶：**≤500 m 只有 10 条、≤2 km 311 条、≤5 km 364 条、≤10 km 656 条、>10 km 99 条**（最大 56 km）。
   → **打分用粗档（同省 / <100 km / <500 km / ≥500 km），不用精确公里**；文案只有精度 ≤2 km 的 311 条允许出现「离你 N km」。
2. **危险物种维不做。** `associated_species` 40/755 有值；`assets/data/danger_species.json`（33 条）与路线**没有任何关联键**；`dangers` 表在 `RouteService.cpp:193-205` 只建不写，`getDangers()`（`:1249-1268`）恒返回空。
   → **缺数据 ≠ 没有危险**。做了这条维，等于把 715 条线当「无危险」加分。
3. **天数维几乎无区分力**（577/755 都是 1 天）→ 权重只给 0.05，当次维。

---

## 四、架构

### 4.1 新增与改动清单

```
新增  src/routes/RouteRanker.h / RouteRanker.cpp     ← 纯函数，不 include QSqlDatabase，不碰网络
新增  tests/unit/test_route_ranker.cpp               ← 新 ctest 目标（27 → 28）
改    src/routes/RouteService.h / RouteService.cpp    ← 4 个新入口 + route_checkins 表
改    qml/pages/RouteListPage.qml                     ← 推荐带 + 删掉客户端过滤
改    qml/pages/RouteDetailPage.qml                   ← 「我走过了」/「取消走过」
新增  tools/qml_checks/recommend_reason_check.js      ← 第 28 道 pass/fail 门禁
```

依赖方向单向：`RouteService → RouteRanker`。`RouteRanker` 不认识数据库、不认识 QML。

### 4.2 打卡表：新建，不复用 `track_records`

`src/core/Database.cpp:169-174` 确实建了一张 `track_records(id, route_id, started_at, ended_at, distance_km, duration_hours, points_json)`，但：

- **全仓 0 处 INSERT、0 处 SELECT**（grep `track_records` 只命中那句 CREATE）—— 死表，与 `dangers` 同病；
- 它建在 **`Name::Settings`（settings.db）**，而那张库的注释写「6. Settings(加密) - 应用设置」（`Database.cpp:166`）—— 实测 grep `cipher|encrypt|AES` **全仓 0 处加密实现**，就是明文 SQLite；同库的 `app_settings` 表也 **0 处读写**。这张库真正的住户只有 `FieldGuideHistory` 一家。

**决定**：新建 `route_checkins` 落 **routes.db**，与 routes / route_favorites 同库同生命周期，推荐时一条 SQL 就能 join 出走过分布，不跨库。

```sql
CREATE TABLE IF NOT EXISTS route_checkins (
    route_id   TEXT PRIMARY KEY,
    checked_at TEXT
);
```

**故意只有两列。** 不写 `distance_km / duration_hours / points_json` —— 那些值只能从路线库抄，抄了就是「把库里的数冒充你走出来的」。这是本 spec 里最硬的一条口径。

重复打卡幂等：`INSERT OR REPLACE`，主键保证一行。取消 = `DELETE`。

建表走 `RouteService::ensureSchema()`（与 `RouteService.cpp:93` 那段同处），用 `CREATE TABLE IF NOT EXISTS`，**不涨 `Database::kCurrentSchemaVersion`（保持 3）**。
> 这里有一条文档与实况的矛盾要登记：`Database.h:44-47` 写「每次加表要递增版本并写 `migrate_X_to_Y()`」，但实况是 KnotService / FieldGuideHistory 都走服务侧 `ensureSchema()` 自建，`Database.h:38-41` 自己承认 `migrateToLatest()` 只管 `user_version` 计数。**按实况多数派走，不新造第三种做法。**

---

## 五、接口

### 5.1 `RouteRanker`（纯函数）

```cpp
namespace outdoor {

struct AbilityProfile {
    int    sampleCount = 0;        // 走过几条（route_checkins 行数）
    double difficultyP75 = 0;      // 走过线 difficulty 的上四分位
    int    difficultyAbility = 0;  // ceil(difficultyP75)
    double maxAltitudeSeen = 0;    // 走过线 max_altitude_m 最大值
    int    daysMode = 1;           // 走过线 days_needed 众数
    bool   valid = false;          // sampleCount >= 1
};

struct RankContext {
    QString  province;    // 筛选省份，未筛则取定位反查省份；都没有则空
    int      month = 0;   // 筛选月份，0 = 未筛（此时用系统当前月做加分，不设门槛）
    double   homeLat = 0, homeLon = 0;
    bool     hasHome = false;
    bool     hasProvinceContext = false;   // province 非空即为 true，决定 reach 维走哪条分支
};

struct RankInput {
    QString id, name, province;
    int     difficulty = 0;
    double  distanceKm = 0, elevationGainM = 0, maxAltitudeM = 0;
    int     daysNeeded = 1;
    QStringList bestSeasonMonths;         // ["4月","5月"...]
    int     score = -1;                   // -1 = 缺失（28 条）
    double  trailheadLat = 0, trailheadLon = 0;
    int     coordPrecisionM = 0;          // 0 = 无值
    bool    isWild = false, hasPermit = false;
};

struct RankOutput {
    double score = 0;                     // 0..1，展示为「匹配度 78%」
    double ability = 0, season = 0, reach = 0, quality = 0, duration = 0;  // 各维 0..1，测试断言用
    QStringList reasons;                  // 最多 2 条，中文，见 §5.3
    bool   kmPublishable = false;         // 精度 ≤ 2000 m 才允许在文案里出现公里数
    bool   seasonHit = false;
};

class RouteRanker {
public:
    static RankOutput rank(const RankInput& r, const AbilityProfile& p, const RankContext& c);
};

}
```

`RouteRanker.h` 只依赖 `QString/QStringList`（QtCore），**不进 QtWidgets/QtSql** —— 这样 `test_route_ranker.cpp` 不需要建库、不需要 assets，跑得快且不随数据变动而红。

### 5.2 `RouteService` 新增 4 个入口

```cpp
Q_INVOKABLE QVariantMap checkInRoute(const QString& id);
Q_INVOKABLE QVariantMap undoCheckIn(const QString& id);
Q_INVOKABLE QVariantList recommendRanked(const QString& province, int maxDiff, int month, int limit);
Q_INVOKABLE int checkinCount() const;

signals:
    void checkinChanged(const QString& id, bool checked);
```

- 前两个返回 `Result<bool>` 的 `{ok,value,error}` 包装（走现成的 `QmlResultBridge`），**每条错误短句必须中文、detail 进 `Logger`** —— 上一轮刚封的 L12 src 半（`error_text_check.js`）会逐条判这 4 个入口里的每个 `fail(` / `Err<T>(`。
- `recommendRanked` 内部流程：调**同一个** `getAdvanced` SQL（`RouteService.cpp:836-883`）取候选 → 查 `route_checkins` 组装 `AbilityProfile` → 逐条 `RouteRanker::rank()` → **排除已走过** → 排除 `difficulty > difficultyCeil` → 按 score 降序取 `limit`。
- `checkinChanged` 必须发（QML 靠它重算 profile 并刷新带）；参照 #55 `trackDeleted` 的形状用 `QSignalSpy` 钉「发一次、带的就是那条、布尔值对」。

### 5.3 理由行由 C++ 生成，不在 QML 拼

`reasons` 取**贡献 `sᵢ × wᵢ` 最大的两维**（**恒等不区分的维不参与选举**，判定口径见 §6.3 末尾那条注记），各套一句中文模板：

| 维 | 模板 | 约束 |
|---|---|---|
| ability | `你走过 12 条 · 难度到 3★` / 冷启动 `按入门默认推` | 不许出现 `p75`、`ability`、`本库` |
| season | `7月正处在窗口` | |
| reach | 同省 `同省 · 山东`。跨省时分三种：<br>① 有定位**且** `kmPublishable` → 给真实档位中值 `离你 42 km`（<100 档说「100 km 内」，<500 档说「约 300 km」，≥500 档说「500 km 以上」，**一律用档位词不用精确数**）<br>② 有定位但精度不达标 → 只说 `跨省 · 坐标精度不够，不报距离`（诚实优先，宁可少一句）<br>③ 无定位（分支②算分口径）→ `跨省`，不提距离 | 精度 > 2 km 的那 444 条（755 − 311）**禁止**出现「离你 N km」 |
| quality | `综合分 87`（仅 `score != -1`） | 28 条缺分的**不许**提「综合分」 |
| duration | `1 天可回` | |

理由行由 C++ 出这一点由**第 28 道门禁**钉住：`recommend_reason_check.js` 判 `RouteListPage.qml` 里出现分数字面量阈值比较（`>= 90` 之类）或 QML 自己拼「推荐」二字常量 → 命中。反证 fixture 必须有两棵：`bad_local_threshold` exit 1、`good_read_reasons` exit 0。

---

## 六、算式

### 6.1 前置动作：先量口径差，再删 QML 那半套过滤 —— **已执行，结论：可安全删**

`RouteListPage.qml:87` 一次取全库后在客户端 `rebuild()`（`:130-176`）过滤；而 `getAdvanced` 的 11 参数 SQL 过滤**今天就已存在**。同一页上并存两份过滤实现，D4 要删前者 —— 删之前必须先证明两者对**每一组可达的筛选组合**给出逐条相同的结果集，否则就是"搬完列表少了 30 条"这种只有真机才看得见的语义漂移。

**测法（2026-11-05 主机侧 `node -e`）**：把两份实现逐行照抄成 JS（SQL 侧含 `isRecommended` 闸门与 `province` 或 `province_code` 二选一；QML 侧含 `Number(difficulty) || 1` 与 `province || "未标注"` 两个兜底），跑 `{省} × {难度上限 0-5} × {月 0-12}` = **2652 组**，每组比较两个 id 集合。

**基线结果：2652 组，差异组 0。** 反证（防止探针空跑）：

| 注入 | 差异组 | 解读 |
|---|---|---|
| `province` 为空的记录 | **10** | 探针确实能抓到差异；「未标注」这个组名是 **QML 独有概念，SQL 侧没有对应物** |
| `difficulty = 0` 的记录 | 0 | 不是探针瞎 —— `loadLibrary` 那次固定调用 `getAdvanced("", 1, 5, …)` 已把难度限制在 [1,5]，脏值根本进不了 `library`。故 QML 那个「难度取不到就当 1 星」的兜底**是被那次调用的边界写死的死代码** |
| `best_season = ["七月"]` | 0 | 两侧都是精确 `=== "7月"` / `QStringList::contains`，**一致地排除**，不是分歧 |

四个候选分歧点的定性结论：

1. **省码**：`provinceChoices` 由 `library` 里的 `r.province`（中文名）建（`:95`），chip 只会传中文名 → SQL 侧 `r.provinceCode == province` 这半条件**永不为真**。
2. **难度兜底**：见上表，死代码。
3. **月份**：两侧语义相同。实测 `best_season` 无「非 N月」形 token。
4. **空省归组**：**真实分歧，但今天 755 条里 `province` 空的有 0 条**，所以没爆。

> **这条要落到实现里**：删掉 QML 过滤后，「未标注」这个分组名随之消失。推荐带和列表的分组头都不许再依赖它 —— 或者在 C++ 侧把空省显式映射成同一个字符串。本轮取**前者**（不引入新字符串）。

**对 D4 的判定**：口径差为 0，「过滤统一到 C++、删 QML 那半套」方向成立，§10 风险 2 不触发，接口签名不必改。

闸门本身的实测：`isRecommended`（`RouteService.cpp:41`，排除 `not_recommended` 与「≥6000m 且类型不是休闲徒步/休闲登山」）在 755 条上**排除 2 条**，`library` 实际 753 条。

### 6.2 能力档推导（从 `route_checkins`）

```
N = COUNT(route_checkins)
走过集合 difficulty 的上四分位 p75 → difficultyAbility = ceil(p75)
altitudeSeen   = MAX(max_altitude_m)
daysMode       = MODE(days_needed)

N == 0        → difficultyAbility = 2, difficultyCeil = 2     // 入门档：候选先按 difficulty ≤ 2 过滤
N == 1 或 2   → difficultyCeil = difficultyAbility             // D7：样本不足时不许"够一够"
N >= 3        → difficultyCeil = difficultyAbility + 1
```

> **自审改掉的一处真矛盾**：`N == 0` 时若不显式定义 `difficultyCeil`，它会等于 `ability + 0 = 0`，
> 于是 §6.5 的「排除 `difficulty > difficultyCeil`」会**把候选 753 条全排除**，推荐带冷启动直接空。
> 这属于"一装上去就是死功能"的级别，所以入门档必须有自己的一条上限分支。

`N == 0` → 走入门档（见 6.4）。

### 6.3 五维归一 + 权重（和为 1.00）

| 维 | 权重 | 算式 |
|---|---|---|
| ability | **0.35** | `N >= 1`：`1 − abs(difficulty − difficultyAbility) / 4`（差 4 档 = 0）<br>`N == 0`：**恒 0.9，不区分**（候选已被 `difficultyCeil = 2` 过滤过，再在 1★/2★ 之间比"能力匹配"是拿入门档冒充档案） |
| season | **0.25** | `month > 0`（筛了月）：候选已被 SQL 过滤，**恒 1.0**（此维不区分，这是 D4 的必然结果）<br>`month == 0`：命中真实月 `1.0`，否则 `0.55`（**降权不踢出**，D7） |
| reach | **0.20** | 三条分支，按上下文能力降级：<br>① `hasHome` → 同省 `1.0`；跨省按直线距离粗档 `<100 km → 0.7`、`<500 km → 0.4`、`≥500 km → 0.2`<br>② 无 `hasHome` 但 `hasProvinceContext` → 同省 `1.0`、跨省**固定 0.4**（算不出公里就不许分档，也不许说「远」）<br>③ 两者都无 → **恒 1.0 不区分**，且 reasons 不许含可达项 |
| quality | **0.15** | `(score − 50) / 47`，clamp 到 0..1；`score == −1` 取 `0.5`（727 条中位）且 reasons 不提分 |
| duration | **0.05** | `daysNeeded == daysMode → 1.0`，否则 `0.5`；`N == 0` 时恒 `1.0` 不区分 |

> **自审改掉的第二处矛盾（理由行选举）**：上表里有三种「恒等不区分」的维（`N==0` 的 ability、`month>0` 的 season、
> 分支③的 reach、`N==0` 的 duration）。§5.3 原本写「取 `sᵢ × wᵢ` 最大的两维」，而 season 权重 0.25 且恒 1.0 时
> **每一票都会被它占走**，用户筛了月份就会看到每条推荐都写「7月正处在窗口」—— 那是废话，不是理由。
> 口径改为：**恒等不区分的维不参与理由行选举**（判定：该维对当前候选集内所有条取值相同 → 不选举）。

`score_total = Σ wᵢ·sᵢ − penalty`，`penalty = (isWild && !hasPermit) ? 0.08 : 0`。
`not_recommended` 与 6000 m+ 非休闲由**已有的 `isRecommended` 闸门**（`RouteService.cpp:41-49`）在候选阶段挡掉，不在这里重复。

展示：`匹配度 = round(score_total × 100)`，**百分比，不是分数**。

### 6.4 冷启动与不足时的显示

| 情形 | 带怎么显示 |
|---|---|
| `N == 0` | 显示入门档：候选按 `difficulty ≤ 2` 过滤（= `difficultyCeil`），带内实际靠 **季节 / 可达 / 质量** 三维排（ability 与 duration 在此档恒等不区分，见 §6.3），眉题 `按入门默认推 · 走过第一条后改按你的能力` |
| 候选（过完筛选与排除后）`≥ 5` | 显示前 5 |
| 候选 `1–4` | 显示实际条数，**不补位、不放宽筛选** |
| 候选 `0` | 整条带不显示（目录区已有 `EmptyState` 负责空态，不重复造） |

实测校准（说明这几档不是空想）：`山东` 23 条 → `山东 + 难度≤3` 22 条 → `山东 + 难度≤3 + 7月` **只剩 1 条**；而 `全库 7月可走` 有 350 条。所以「候选 1–4 条」是**常见态**，不是边界态。

### 6.5 排除

- **已走过的不进带**（`route_checkins` 里有它的）。想再走，目录里点得到。
- `difficulty > difficultyCeil` 不进带。

---

## 七、QML 侧与布局义务

### 7.1 RouteListPage

三个 chip（难度上限 `:53`、省 `:54`、月 `:55`）的值是页面**唯一**的筛选状态来源。chip 的 `onClicked` → 写值 → `reload()`，`reload()` 里两个调用**用同一组参数**：

```qml
function reload() {
    listModel = routeService.getAdvanced(filterProvince, 1, filterMaxDiff, filterMonth,
                                         "", true, true, 0, 0, 0, 0);
    recModel  = routeService.recommendRanked(filterProvince, filterMaxDiff, filterMonth, 5);
}
```

**L14 硬约束**：`recommendRanked` 返回的 `QVariantList` 在 QML 里 `typeof === "object"`、`Array.isArray() === false`，只有 `.length` / `[i]` / `indexOf` 可用。判空**只能**写 `recModel.length === 0`，一处 `Array.isArray` 都不许出现（#48 那 6 个下拉全空白就是这条）。`combo_shape_check.js` 已在盯这类形状。

### 7.2 布局定律义务（逐条对着现有门禁）

| 定律 | 这条功能要守什么 | 验证 |
|---|---|---|
| **L3/L6** | 推荐带**不许**拿 `Layout.fillHeight` —— 剩余高度仍归现有列表的 ScrollView，否则页头被顶下去（就是紧急联系人页 454 那次） | `page_fill_check.js` 改后仍须 exit 0 |
| **L13 / 判据⑥** | 带里的行不是右上角方块族（无 `anchors.top + right` 且带 `IconLabel`），不误触⑥；但若「我走过了」画成贴角 26 见方，必须用 `styles.pageHeadBox` / `pageHeadTapPad`，**不许抄 30** | `page_head_check.js` exit 0 |
| **L15** | 每条理由行是 `wrapMode: WordWrap` 的 `Text`，宿主是 `ColumnLayout` → 必须写 `Layout.fillWidth: true` | 现有 `dialog_text_width_check.js` 只判 Dialog/Popup，**不扩**（判据一宽全是假命中）；宽度靠真机 + 下面的行形状约束 |
| **L16** | 「我走过了」`kind: "primary"`，**不标「不可撤」**（它真的可撤）；「取消走过」`kind: "plain"`。**打卡不许加确认框** —— 走过是可撤动作，加确认只会让人少点 | `confirm_code_check.js` exit 0 |
| **L11** | 三个 chip 值一处取、两调用同参；chip 改了必须触发重算 | `filter_rebuild_check.js` 改后仍须 exit 0（这次改动正落在它射程里） |
| **L12** | 4 个新入口每条错误短句中文；眉题/理由行不许出现 `p75`/`本库`/`决策树`/`读数` 这类内部记号 | `error_text_check.js` + `user_text_marks_check.js` |

行组件：优先复用 `components/base/ListRow`。**若其接口不合，退回 `Card` + `Text` 现形，但不许新造第三种行形状**（L13 的病根就是同类控件多种抄法）。实现时以实测决定，并在讨论记录里写明选了哪个。

### 7.3 RouteDetailPage

打卡键紧邻「收藏这条 / 取消收藏」（`RouteDetailPage.qml:1157-1158`）同一条动作带，同款按钮组件。点击即写，无确认框；已打卡时按钮文案切「取消走过」，并用现有高亮色（参照 `isFavorite` 的 `colorLegendAmber` 用法）。

### 7.4 一条已知冲突（登记，本轮不动）

`qml/components/MapOverlay/RouteSummaryPanel.qml:84-99` 有一份硬编码五档判词：`≥90「高度推荐」/ ≥80「推荐」/ ≥70「良好」/ ≥60「较难」/ 其余「高难」`，而**函数名叫 `_difficultyLabel`** —— 拿质量分当难度判词，两个语义在它身上已经混了。

推荐带上线后，全树会有两套「推荐」措辞。本 spec 的口径：**推荐带不许复制那套阈值判词**，只以「匹配度 78%」出现。那份旧判词归 #43 那族「同类控件一套几何」去收编，本轮不动，但登记在此以免下轮误判为抄错。

---

## 八、测试口径

1. **`tests/unit/test_route_ranker.cpp`（新 ctest 目标 27 → 28）**，合成路线逐维断言，**不用 755 条真数据**（改数据不会红）：
   - 能力单调性：`difficulty` 从 `ability` 走到 `ability+4`，score 严格递减；差 4 档时 ability 维 == 0。
   - `N=1` 时 `difficultyCeil == ability`（推不出进阶）；`N=3` 时 `== ability+1`。
   - **`N == 0` 时 `difficultyCeil == 2` 且候选非空** —— 这条是自审抓出的"一装上去就推空带"的反证，必须存在。
   - **恒等维不参与理由行选举**：`month > 0` 时（season 恒 1.0）reasons 里**不许**出现季节句；`N == 0` 时不许出现能力句。
   - 无定位但有省上下文（reach 分支②）：reach 维 == 0.4（跨省）且 reasons **不许**出现「离你」。
   - 季节：`month>0` 时全候选 season == 1.0；`month==0` 时命中真实月 1.0 / 不命中 0.55。
   - 可达：同省 > `<100km` > `<500km` > `≥500km`；上下文为空时恒 1.0 且 reasons 无可达项。
   - 质量：`score=-1` 时取 0.5 **且 reasons 不含「综合分」**。
   - `kmPublishable`：`coordPrecisionM=2000` 为真、`2001` 为假、`56000` 为假且 reasons 里**不许出现「离你」**。
   - 排除：已走过不进带；`isWild && !hasPermit` 扣分 0.08 可断言。
   - `reasons.size() <= 2`，且每条含汉字（对 L12 的镜像断言）。
2. **打卡测试**（进 `test_route_service.cpp`，`add_unit_test` 槽位 304 → 306）：`checkInRoute` 幂等（打两次仍一行）、`undoCheckIn` 后 `checkinCount()` 减一、`checkinChanged` 用 `QSignalSpy` 钉「发一次 + 带的就是那条 + 布尔对」。
3. **第 28 道门禁** `recommend_reason_check.js` + 反证 fixture（`tmp_reg/recommend_gate_fixture.js`，至少 `good_read_reasons` exit 0 与 `bad_local_threshold` exit 1，HIT 行号要钉）。
4. 主机侧全绿口径（逐个实跑贴 exit 码，不引用旧结论）：**28 道 pass/fail 门禁 + `qml_load_check` + `ctest` 28/28 + 全树 `qmllint` 0 `^Error`**。
   > 两个「28」是**巧合同号，不是同一件事**：pass/fail 门禁从 **27 → 28**（`tools/qml_checks` 脚本总数随之 30 → 31，
   > 另有 3 个只报数不判 fail 的诊断脚本）；ctest 测试**可执行目标**从 27 → 28（新增 `test_route_ranker`）。
   > 登记口径按 §13 既有定义：门禁道数只数带退出码结论的，不数脚本文件数。
5. 出包：版本自动 +1 → **0.0.11 arm64-v8a**，包侧照 0.0.10 那套复核（rcc 探针 needle + `.so` 双编码字节探针 + 独立 `aapt2`/`apksigner` 回验）。
6. 文档：新讨论记录 **17 号**，五份文档同步；需求行 **5.8** 从 `📝 设计中` 改成本轮实际状态；`check_doc_sync.mjs` 必须 PASS。

**全部为「代码侧完成，真机未验」起步** —— 推荐带的位置、行高、理由行折行、打卡键手感，都必须真机逐帧判（本项目 L15/L16 三条律全是真机抓出来的）。

---

## 九、非目标（明确不做）

- 权重可配置 / 用户调参 UI（唯一用户是自己，给未验证的公式套调参壳是 YAGNI）。
- 危险物种维（40/755 有值，做了等于把 715 条当无危险加分）。
- GPS 轨迹与路线自动关联（`track_records` 的 `points_json` 那条路）。
- 收藏 / `visit_count` 参与评分（D1 已排除：浏览数冒充能力是骗人）。
- `RouteSummaryPanel` 旧判词收编（#43 族）。
- 离线瓦片（#3，另排可行性 spike）。

---

## 十、风险与数据前提（写在明处）

1. **今天在手机上必然走冷启动分支** —— `route_checkins` 是空表。要看到真档案生效，得等走过几条并点过打卡。这与 #5/#6/#7 卡在「本机 0 条轨迹」是同一类数据前提，**不能拿主机侧跑通冒充功能生效**。
2. ~~**§6.1 的口径 diff 可能查出 QML 过滤与 SQL 过滤不一致**~~ —— **已于 2026-11-05 执行并闭合**：2652 组基线差异 0，反证能点亮探针，D4 方向成立、接口签名不改。残留的唯一语义损失是「未标注」分组（见 §6.1 第 4 点），实现时按「不再依赖它」处理。
3. 755 条里 749 条起点是编校估计 → 跨省推荐的实际距离可能差几十公里。当前用粗档 + 文案闸门兜，**不假装精确**。
4. D7 两个常数（`N>=3` 与 `0.55`）是主观值，测试只断言单调性与边界，不断言"这样推得准"。推得准不准只能靠真机用一段时间再翻。
