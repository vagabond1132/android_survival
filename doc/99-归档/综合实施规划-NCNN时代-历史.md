# 户外生存离线 App - 综合实施规划

> 项目代号：**荒野手册**（建议）
> 目标平台：Android 7.0+（API 24+，覆盖 95%+ 国内 Android 设备）
> 目标用户：中国户外徒步 / 露营 / 登山 / 越野跑爱好者
> 技术栈：Qt 6.7+ for Android + C/C++ + NCNN + SQLite

---

## 目录

1. [项目总览](#一项目总览)
2. [产品需求清单（PRD）](#二产品需求清单prd)
3. [技术架构总览](#三技术架构总览)
4. [数据准备规划](#四数据准备规划)
5. [核心功能详细设计](#五核心功能详细设计)
6. [徒步路线难易度模块](#六徒步路线难易度模块)
7. [绳结模块专项](#七绳结模块专项)
8. [应急储备模块](#八应急储备模块)
9. [防虫防蛇模块](#九防虫防蛇模块)
10. [中国动植物识别体系](#十中国动植物识别体系)
11. [离线架构设计](#十一离线架构设计)
12. [UI / UX 规范](#十二ui--ux-规范)
13. [项目目录与代码结构](#十三项目目录与代码结构)
14. [实施阶段划分](#十四实施阶段划分)
15. [第一个月开发计划（详）](#十五第一个月开发计划详)
16. [关键里程碑与可交付物](#十六关键里程碑与可交付物)
17. [团队配置建议](#十七团队配置建议)
18. [风险清单与应对](#十八风险清单与应对)
19. [立即可启动的 5 件事](#十九立即可启动的-5-件事)

---

## 一、项目总览

### 1.1 一句话定位
> **中国户外爱好者的离线生存助手** —— 拍照识动植物，关键时刻救命。

### 1.2 解决的核心痛点
| 痛点 | 当前问题 | 我们的方案 |
|---|---|---|
| 户外无信号 | 现有 App 大多需联网 | **完全离线可用** |
| 急救不知道 | 突发情况慌乱 | **决策树 + 一键 120** |
| 取火 / 庇护所 | 记不清步骤 | **图文 + 视频 + 离线** |
| 绳结不会 | 教程分散 | **图解 + 视频，按用途分类** |
| 防虫防蛇 | 不知如何处理 | **中国常见毒蛇虫清单** |
| 路线难度 | 不知如何评估 | **科学评估体系** |
| 应急储备 | 不知带什么 | **场景化清单** |

### 1.3 差异化（相对国内已有 App）
1. **完全离线** —— 比花伴侣、形色更彻底
2. **急救专业** —— 决策树 + 医师审核
3. **避险深入** —— 取火、庇护所、工具、绳结全模块
4. **中国本土** —— 动植物 + 路线 + 法规 + 中文
5. **技术先进** —— NCNN 端侧 AI + 量化模型

---

## 二、产品需求清单（PRD）

### 2.1 功能模块总览

```
┌────────────────────────────────────────────────┐
│              荒野手册 主界面                      │
├────────────────────────────────────────────────┤
│                                                │
│  ① 拍照识别  ② 急救  ③ 避险  ④ 生活技巧          │
│                                                │
│  ⑤ 绳结  ⑥ 路线  ⑦ 防虫蛇  ⑧ 应急储备           │
│                                                │
│  [SOS 长按 3 秒求救]                             │
│                                                │
└────────────────────────────────────────────────┘
```

### 2.2 模块 1：拍照 AI 识别动植物

| 项 | 说明 |
|---|---|
| 入口 | 主界面"拍照识别" |
| 方式 | 拍照 / 相册 / 实时相机识别 |
| 覆盖 | 植物 / 动物 / 蛇类 / 蘑菇 / 昆虫 |
| 附加信息 | 学名、别名、毒性、可食性、分布、生境、季节 |
| 警告 | 剧毒物种红色警示，强制二次确认 |
| 历史 | 本地保存识别记录 |
| 收藏 | 可收藏便于复习 |

**MVP 覆盖**：
- 植物 500 种（中国常见）
- 动物 100 种
- 毒蛇 30 种（中国剧毒 / 常见）
- 蘑菇 50 种（重点：致命鹅膏系列）
- 昆虫 50 种（重点：毒蜂、蜱虫、蚂蟥）

### 2.3 模块 2：急救

| 子模块 | 内容 |
|---|---|
| **急症优先** | 心搏骤停 CPR、大出血、窒息、休克、昏迷 |
| **创伤处理** | 骨折、扭伤、切割伤、烧烫伤、头部伤 |
| **环境急症** | 失温、中暑、高原反应、溺水、冻伤 |
| **中毒急救** | 蛇咬伤、虫螫伤、食物中毒、植物中毒 |
| **特殊环境** | 雷击、雪崩、塌方、泥石流 |
| **急救包** | 配置清单 + 过期提醒 + 补购建议 |
| **决策树** | 交互式问答引导 |
| **一键求救** | 长按 3 秒拨打 120 + GPS 发送紧急联系人 |

### 2.4 模块 3：避险

| 子模块 | 内容 |
|---|---|
| **天气预判** | 云、动物、植被预判天气 |
| **迷路应对** | 定向方法、应急策略 |
| **避险选址** | 营地选择、危险地形识别 |
| **求救信号** | SOS、莫尔斯码、信号镜、烟雾、闪光 |
| **紧急庇护** | 30 分钟内可搭建的临时庇护 |
| **天气灾害** | 雷暴、洪水、雪崩、塌方应对 |
| **夜间生存** | 照明、保暖、防兽 |

### 2.5 模块 4：生活技巧

| 子模块 | 内容 |
|---|---|
| **取火** | 6 大类 12 种方法（详见下） |
| **庇护所** | 10+ 种搭建（快速 / 标准 / 极端） |
| **工具制作** | 刀具、容器、绳索、武器 |
| **净水** | 5 种方法（煮沸、过滤、消毒、太阳能等） |
| **食物获取** | 陷阱、捕鱼、采集、狩猎 |
| **烹饪** | 野炊食谱、可食野菜、蘑菇处理 |
| **结绳** | 单独模块（详见第 7 节） |
| **定向** | 无 GPS 导航（太阳、星星、地形） |

#### 取火方法 6 大类
1. **现代工具**：打火机、防风火柴、打火棒、镁棒
2. **摩擦**：钻木取火（手钻、弓钻、泵钻）、火犁
3. **聚光**：放大镜、冰块、玻璃瓶
4. **火石**：天然燧石 + 钢
5. **电池**：锡纸、钢丝球
6. **化学**：高锰酸钾 + 甘油

### 2.6 模块 5：绳结（专项）

详见 [第七节](#七绳结模块专项)

### 2.7 模块 6：徒步路线难易度（专项）

详见 [第六节](#六徒步路线难易度模块)

### 2.8 模块 7：防虫防蛇（专项）

详见 [第九节](#九防虫防蛇模块)

### 2.9 模块 8：应急储备（专项）

详见 [第八节](#八应急储备模块)

### 2.10 模块 9：生活技巧综合手册

- 出行前准备
- 装备清单（按季节 / 路线难度）
- 体能训练
- 衣物穿着（分层原则）
- 营地选择与建设
- 行走技巧
- 团队协作
- 摄影技巧

---

## 三、技术架构总览

### 3.1 总体架构

```
┌────────────────────────────────────────────────────┐
│                  QML / Qt Quick UI                  │
├────────────────────────────────────────────────────┤
│  C++ 业务层                                          │
│  ┌──────────┬──────────┬──────────┬──────────┐      │
│  │ 识别服务  │ 急救服务 │ 避险服务  │ 路线服务 │      │
│  └──────────┴──────────┴──────────┴──────────┘      │
│  ┌──────────┬──────────┬──────────┬──────────┐      │
│  │ 绳结服务  │ 防虫蛇   │ 应急储备  │ 手册服务 │      │
│  └──────────┴──────────┴──────────┴──────────┘      │
├────────────────────────────────────────────────────┤
│  AI 引擎层                                            │
│  ┌──────┬──────┬──────┬──────┐                      │
│  │NCNN  │OpenCV│SQLite│加密  │                      │
│  └──────┴──────┴──────┴──────┘                      │
├────────────────────────────────────────────────────┤
│  Android 平台适配 (JNI)                              │
│  ┌──────┬──────┬──────┬──────┬──────┐               │
│  │相机  │位置  │电话  │短信  │存储  │               │
│  └──────┴──────┴──────┴──────┴──────┘               │
└────────────────────────────────────────────────────┘
```

### 3.2 技术选型一览

| 层 | 技术 | 版本 |
|---|---|---|
| **UI** | Qt Quick / QML | Qt 6.7+ |
| **业务** | C++ 17/20 | GCC 12 / Clang 16 |
| **AI 推理** | NCNN（腾讯） | 20240102 |
| **图像处理** | OpenCV | 4.8 |
| **数据库** | SQLite + sqlcipher | 3.44 |
| **压缩** | zlib + brotli | latest |
| **JSON** | nlohmann/json | 3.11 |
| **日志** | spdlog | 1.12 |
| **构建** | CMake + Gradle | 3.22 + 8.4 |
| **Android** | NDK r26b | API 24-34 |

### 3.3 模块依赖关系

```
拍照识别
   ↓
中国动植物数据库 ←── 路线难易度（生境匹配）
   ↓
急救 ←── 防虫蛇（蛇咬 / 虫螫处理）
   ↓
避险 ←── 取火、庇护所、工具、绳结
   ↓
应急储备
   ↓
综合手册
```

---

## 四、数据准备规划

### 4.1 数据来源清单

#### A. 植物数据
| 来源 | 规模 | 协议 | 用途 |
|---|---|---|---|
| **iNaturalist 中国部分** | 50万+ | CC | 基础数据集 |
| **中国植物志** | 31276 种 | 公共 | 权威信息源 |
| **PPBC 中国植物图像库** | 千万+ | 学术 | 训练图片 |
| **CFH 中国真菌志** | 1万+ | 公共 | 蘑菇 |
| 花伴侣 / 形色 | 需授权 | 商业 | 补充 |

#### B. 动物数据
- 中国野生动物保护协会
- Macaulay Library（鸟类）
- Wikipedia 中文
- 中国两栖爬行动物数据库
- 两江中国兽类图库

#### C. 急救内容
- 中国红十字会公开教材
- 卫健委急救指南
- FM 21-76 美军战伤急救
- 执业医师审核

#### D. 生存技能
- 《怀斯曼生存手册》中文版
- 中国登山协会《登山基础》
- 《户外生存手册》中国林业出版社
- 国家应急管理部公开资料

#### E. 路线数据
- 各地文旅局公开路线
- 中国国家地理
- 8264 户外、绿野社区精华帖
- 当地救援队公开案例

### 4.2 数据采集策略

#### 阶段 1：自建精选数据集（MVP 必需）
```
植物 500 种 × 30 张图 / 种 = 15,000 张
动物 100 种 × 20 张图 / 种 = 2,000 张
毒蛇 30 种 × 50 张图 / 种 = 1,500 张（角度多）
蘑菇 50 种 × 30 张图 / 种 = 1,500 张
昆虫 50 种 × 20 张图 / 种 = 1,000 张
─────────────────────────────────
总计 22,000 张图
```

#### 阶段 2：扩展到完整数据集
```
植物 2000 种 + 动物 500 种 + 毒蛇 100 种 + 蘑菇 200 种
总计 100,000+ 张图
```

#### 标注规范
- 统一格式：COCO / Pascal VOC
- 工具：LabelImg / CVAT
- 多人审核 + 专家确认
- 难度标注：易 / 中 / 难

### 4.3 数据存储结构

```
assets/
├── data/                      # 数据库
│   ├── plants.db              # 植物 SQLite
│   ├── animals.db             # 动物
│   ├── snakes.db              # 毒蛇
│   ├── mushrooms.db           # 蘑菇
│   ├── firstaid.db            # 急救
│   ├── survival.db            # 避险
│   ├── routes.db              # 路线
│   ├── knots.db               # 绳结
│   └── emergency.db           # 应急储备
├── models/                    # AI 模型
│   ├── plant_v1_int8.param
│   ├── plant_v1_int8.bin
│   ├── animal_v1_int8.param
│   ├── animal_v1_int8.bin
│   ├── snake_v1_int8.param
│   ├── snake_v1_int8.bin
│   └── mushroom_v1_int8.param
├── media/                     # 媒体
│   ├── images/                # 物种图（按 ID 哈希）
│   ├── videos/                # 教程视频
│   └── animations/            # 3D 动画
├── i18n/                      # 多语言
│   ├── zh_CN.ts
│   └── en_US.ts
└── themes/                    # 主题
    ├── dark.qml
    └── outdoor_high_contrast.qml
```

### 4.4 数据规模估算

| 内容 | 数量 | 大小 |
|---|---|---|
| 物种（精选） | 730 种 | 200MB |
| 急救 | 200 条 | 10MB |
| 视频教程 | 50 个 | 500MB |
| 3D 动画 | 20 个 | 100MB |
| 基础包 | - | **50MB** |
| 完整离线包 | - | **1-2GB** |

---

## 五、核心功能详细设计

### 5.1 拍照识别

#### 5.1.1 识别流程

```
用户拍照
  ↓
图像预处理（缩放 224x224、归一化、增强）
  ↓
NCNN 推理（80-150ms）
  ↓
后处理（Top-5、置信度阈值）
  ↓
查询数据库（物种信息）
  ↓
UI 展示（详情页）
  ↓
记录历史（本地 SQLite）
```

#### 5.1.2 核心 C++ 类

```cpp
class RecognitionEngine : public QObject {
    Q_OBJECT
public:
    enum Category { Plant, Animal, Snake, Mushroom, Insect };
    Q_ENUM(Category)
    
    struct Result {
        QString speciesId;
        QString scientificName;
        QString commonName;
        float confidence;
        QList<QPair<QString, float>> alternatives;
        Category category;
    };
    
    Q_INVOKABLE Result recognize(const QString& imagePath, Category cat);
    Q_INVOKABLE Result recognizeFromImage(const QImage& image, Category cat);
    
signals:
    void recognitionCompleted(Result result);
    void recognitionFailed(QString error);
};
```

#### 5.1.3 UI 设计

```
┌─────────────────────────────┐
│  ← 识别结果                  │
├─────────────────────────────┤
│  [物种图片]                  │
│                             │
│  银环蛇                      │
│  Bungarus multicinctus       │
│  ⚠️ 剧毒                    │
│                             │
│  置信度: 95.3%               │
│  识别时间: 0.18s             │
├─────────────────────────────┤
│  简介:                       │
│  中国南方常见剧毒蛇...         │
├─────────────────────────────┤
│  毒性:                       │
│  ████████ 神经毒素           │
│                             │
│  分布: 长江以南              │
│  季节: 4-10 月               │
│  习性: 夜行、喜潮湿          │
├─────────────────────────────┤
│  ⚠️ 若被咬: 立即拨打 120     │
│  [急救决策] [相似种对比]      │
│                             │
│  [收藏] [记录]                │
└─────────────────────────────┘
```

### 5.2 急救

#### 5.2.1 决策树引擎

```cpp
class DecisionEngine : public QObject {
    Q_OBJECT
public:
    struct Node {
        QString id;
        QString question;
        QString text;
        QString videoUrl;
        QList<Node> options;
        QStringList donts;
        QString source;
    };
    
    Q_INVOKABLE Node getRootNode(const QString& entryId);
    Q_INVOKABLE Node getNextNode(const QString& nodeId, const QString& option);
    Q_INVOKABLE void triggerEmergencyCall(const QString& number);
    
signals:
    void nodeChanged(Node node);
    void terminalReached(QString action);
};
```

#### 5.2.2 急救数据示例（被五步蛇咬伤）

```json
{
  "id": "snake_agkistrodon",
  "title": "被五步蛇咬伤",
  "urgency": 5,
  "category": "中毒急救",
  "decision_tree": {
    "question": "是否被蛇咬伤？",
    "options": [
      {
        "label": "是",
        "next": {
          "question": "蛇是否还在附近？",
          "options": [
            {
              "label": "是",
              "action": "缓慢后退，至少 5 米外，远离蛇"
            },
            {
              "label": "否",
              "next": {
                "question": "能否看清蛇的样子？",
                "options": [
                  {
                    "label": "能",
                    "action": "立即拍照（不要追蛇），便于医生判断"
                  },
                  {
                    "label": "不能",
                    "action": "继续到下一步"
                  }
                ]
              }
            }
          ]
        }
      },
      {
        "label": "否",
        "action": "返回急救首页"
      }
    ]
  },
  "critical_actions": [
    "立即拨打 120",
    "让伤者保持静止，咬伤部位低于心脏",
    "脱下戒指、手表等，防止肿胀后缺血",
    "用夹板或木棍固定咬伤部位"
  ],
  "donts": [
    "✗ 切开伤口吸毒",
    "✗ 用口吸毒",
    "✗ 冰敷或冷敷",
    "✗ 跑动或剧烈活动",
    "✗ 喝酒或咖啡"
  ],
  "video_url": "snake_bite_firstaid.mp4",
  "source": "中国蛇伤学会、卫健委"
}
```

### 5.3 避险

详见 5.5 取火、5.6 庇护所、5.7 工具、第七节绳结。

### 5.4 一键求救

```cpp
class EmergencyService : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE void triggerSOS();
    Q_INVOKABLE void setEmergencyContacts(const QStringList& contacts);
    
private:
    void call120();
    void sendSmsToContacts(double lat, double lon, const QString& message);
    void startForegroundTracking();
};
```

---

## 六、徒步路线难易度模块

### 6.1 难易度评级体系

#### 6.1.1 综合评级（5 级）

```
★☆☆☆☆ 入门 / 休闲
  - 城市公园、低山郊野
  - 海拔 < 500m
  - 路程 < 5km
  - 累计爬升 < 100m
  - 路线清晰，标识完善
  - 4 小时内可完成
  - 适合：亲子、老人、新手

★★☆☆☆ 简单 / 入门级徒步
  - 郊野公园、低海拔山岭
  - 海拔 500-1500m
  - 路程 5-10km
  - 累计爬升 100-500m
  - 路线清晰，部分野路
  - 4-6 小时
  - 适合：有运动基础

★★★☆☆ 中等 / 进阶级
  - 中海拔山脉
  - 海拔 1500-3000m
  - 路程 10-20km
  - 累计爬升 500-1500m
  - 野路为主，部分陡坡
  - 6-10 小时
  - 适合：经验徒步者
  - ⚠️ 部分需重装

★★★★☆ 困难 / 高阶级
  - 高山、高海拔
  - 海拔 3000-4500m
  - 路程 20-40km
  - 累计爬升 1500-3000m
  - 险路、碎石坡、可能需攀爬
  - 1-2 天或多日
  - 适合：专业户外人士
  - ⚠️ 高反风险

★★★★★ 极难 / 探险级
  - 雪山、无人区
  - 海拔 4500m+
  - 路程 40km+
  - 累计爬升 3000m+
  - 需技术装备
  - 多日
  - 适合：登山家、专业团队
  - ⚠️ 重大风险，需备案
```

#### 6.1.2 评估维度（5 项加权）

| 维度 | 权重 | 评分项 |
|---|---|---|
| **地形** | 30% | 平地/缓坡/陡坡/碎石/冰雪/岩石 |
| **海拔** | 25% | <500 / 500-1500 / 1500-3000 / 3000-4500 / >4500 |
| **距离** | 15% | <5 / 5-10 / 10-20 / 20-40 / >40 km |
| **爬升** | 20% | <100 / 100-500 / 500-1500 / 1500-3000 / >3000m |
| **补给** | 10% | 沿途有 / 部分 / 极少 / 无 |

### 6.2 路线数据库设计

```sql
CREATE TABLE routes (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    province TEXT,
    city TEXT,
    difficulty INTEGER,          -- 1-5
    distance_km REAL,
    elevation_gain_m INTEGER,
    max_altitude_m INTEGER,
    duration_hours REAL,
    days_needed INTEGER,
    best_season TEXT,            -- 春夏秋冬
    terrain_types TEXT,          -- JSON: [山脊, 溪谷, 草甸, ...]
    water_sources TEXT,          -- JSON: [type, count]
    supply_points TEXT,          -- JSON
    dangers TEXT,                -- JSON: [毒蛇, 失温, 高反, ...]
    highlights TEXT,
    description TEXT,
    start_point TEXT,
    end_point TEXT,
    trailhead TEXT,
    permit_required BOOLEAN,
    rescue_phone TEXT,
    source TEXT,
    last_updated DATE
);
```

### 6.3 MVP 路线精选（中国境内 100 条）

#### 入门级 30 条
- 北京：香山、阳台山、凤凰岭
- 上海：佘山、崇明岛
- 广州：白云山、火炉山
- 深圳：梧桐山、马峦山
- 杭州：宝石山、九曜山
- 成都：青城山前山
- ...

#### 中等级 40 条
- 北京：海陀、灵山
- 四川：四姑娘山长坪沟
- 云南：哈巴雪山（接近路线）
- 西藏：纳木错徒步
- 青海：年宝玉则（关闭后）
- 甘肃：扎尕那
- 陕西：鳌太（部分）
- ...

#### 困难级 25 条
- 四川：贡嘎大环线、武功山
- 西藏：墨脱、珠峰东坡
- 新疆：博格达、狼塔 C 线
- 云南：梅里外转
- 甘肃：洛克线
- ...

#### 极难级 5 条
- 珠穆朗玛峰北坡
- 贡嘎主峰
- 慕士塔格
- 公格尔九别峰
- 念青唐古拉

### 6.4 路线数据来源

| 来源 | 类型 | 用途 |
|---|---|---|
| **各地文旅局** | 官方 | 基础信息 |
| **中国登山协会** | 官方 | 难度评级 |
| **两步路户外助手** | 商业 | 路线轨迹（需授权） |
| **六只脚** | 商业 | 路线轨迹（需授权） |
| **8264 论坛** | UGC | 攻略、危险提示 |
| **绿野社区** | UGC | 攻略 |
| **救援队公众号** | 案例 | 真实危险点 |

### 6.5 路线详情页

```
┌─────────────────────────────┐
│  ← 武功山徒步                │
├─────────────────────────────┤
│  ★★★★☆ 困难                  │
│  江西萍乡 / 2 天             │
│                             │
│  [轨迹图] [照片] [攻略]       │
├─────────────────────────────┤
│  基础信息                     │
│  距离: 35 km                │
│  累计爬升: 2100m            │
│  最高海拔: 1918m            │
│  最佳季节: 5-10 月           │
│  补给点: 3 个                │
├─────────────────────────────┤
│  ⚠️ 主要危险                 │
│  - 暴雨导致山洪              │
│  - 迷路（多岔路口）          │
│  - 失温（高山夜间低温）      │
│  - 雷击（高山草甸）          │
├─────────────────────────────┤
│  📋 必带装备                 │
│  [查看完整装备清单]           │
├─────────────────────────────┤
│  🆘 应急信息                 │
│  萍乡应急: 0799-XXX          │
│  救援队: 武功山景区救援       │
│  [一键拨打]                  │
└─────────────────────────────┘
```

### 6.6 路线推荐算法

```cpp
class RouteRecommender {
public:
    QList<Route> recommend(UserProfile profile) {
        // 1. 评估用户能力
        int userLevel = profile.experienceLevel;  // 1-5
        int fitnessLevel = profile.fitnessLevel;  // 1-5
        
        // 2. 季节匹配
        QString currentSeason = getCurrentSeason();
        
        // 3. 距离筛选
        int maxDistance = profile.maxDistance;  // 用户偏好
        
        // 4. 风险偏好
        bool riskTolerance = profile.riskTolerance;
        
        // 5. 推荐排序
        return filter([&](const Route& r) {
            return r.difficulty <= userLevel + 1  // 略高于能力
                && r.best_season.contains(currentSeason)
                && r.distance_km <= maxDistance
                && (riskTolerance || r.dangers.size() < 3);
        }).sortBy([&](const Route& r) {
            return matchScore(r, profile);  // 多维匹配
        });
    }
};
```

---

## 七、绳结模块专项

### 7.1 绳结分类

#### 7.1.1 按用途分类

```
基础固定
├── 单结
├── 双 8 字结
├── 双半结
└── 意大利半结

绳与绳相接
├── 平结（最常用）
├── 双渔人结
├── 三渔人结
├── 八字接绳结
└── 外科结

环形绳结
├── 布林结（Bowline）★
├── 双圈布林结
├── 葡萄牙结
├── 攀师结
└── 意大利布林结

固定 / 锚点
├── 圆材结
├── 双圆材结
├── 普鲁士抓结
├── 水结
└── 缆桩结

特殊用途
├── 缩绳结
├── 套索结
├── 鞭索结
├── 截结
└── 中间人结
```

### 7.1.2 核心绳结清单（户外 12 种必学）

| # | 名称 | 用途 | 难度 | 推荐场景 |
|---|---|---|---|---|
| 1 | **单结** | 防脱、临时 | ★ | 通用 |
| 2 | **8 字结** | 防脱、保险 | ★ | 通用 |
| 3 | **平结** | 接绳 | ★★ | 接等粗绳 |
| 4 | **双渔人结** | 接绳 | ★★ | 接不等粗绳 |
| 5 | **八字接绳** | 接绳 | ★★ | 登山、攀岩 |
| 6 | **布林结** | 固定环 | ★★★ | 救援、攀岩 |
| 7 | **双圆材结** | 锚定 | ★★ | 系在树/桩 |
| 8 | **普鲁士抓结** | 上升 | ★★★ | 攀爬、救援 |
| 9 | **水结** | 固定 | ★ | 帐篷、捆扎 |
| 10 | **外科结** | 缝合 | ★★★ | 急救 |
| 11 | **套索结** | 套捕 | ★★ | 捕猎、救援 |
| 12 | **截结** | 临时 | ★ | 应急 |

### 7.2 绳结内容设计

每个绳结包含：
- 3D 动画（多角度）
- 分步图解（6-8 步）
- 视频（1-2 分钟）
- 用途说明
- 适用场景
- 常见错误
- 练习方法
- 关联绳结（学习路径）

### 7.3 绳结学习路径

```
入门（必学 4 种）
├── 单结 → 8 字结 → 平结 → 水结
│
进阶（必学 4 种）
├── 双渔人结 → 八字接绳 → 双圆材结 → 套索结
│
高级（必学 4 种）
├── 布林结 → 双圈布林 → 普鲁士抓结 → 外科结
```

### 7.4 绳结数据库设计

```sql
CREATE TABLE knots (
    id TEXT PRIMARY KEY,
    name_cn TEXT NOT NULL,
    name_en TEXT,
    category TEXT,           -- 基础/接绳/环形/锚定/特殊
    difficulty INTEGER,      -- 1-3
    use_cases TEXT,          -- JSON
    steps TEXT,              -- JSON: [{step:1, text, image, video_frame}]
    common_mistakes TEXT,    -- JSON
    related_knots TEXT,      -- JSON
    prerequisites TEXT,      -- JSON
    video_url TEXT,
    animation_url TEXT,
    practice_tips TEXT,
    last_updated DATE
);
```

### 7.5 绳结数据 JSON 示例

```json
{
  "id": "bowline",
  "name_cn": "布林结",
  "name_en": "Bowline",
  "category": "环形",
  "difficulty": 3,
  "use_cases": [
    "救援套人",
    "固定绳圈",
    "系船",
    "攀岩保护",
    "拖拽重物"
  ],
  "steps": [
    {
      "step": 1,
      "text": "在主绳上形成一个圆环（小圈）",
      "image": "bowline_01.png",
      "video_time": "00:02"
    },
    {
      "step": 2,
      "text": "将绳头从小圈后方穿入",
      "image": "bowline_02.png",
      "video_time": "00:05"
    },
    {
      "step": 3,
      "text": "绳头从主绳下方绕过",
      "image": "bowline_03.png",
      "video_time": "00:08"
    },
    {
      "step": 4,
      "text": "绳头穿回小圈",
      "image": "bowline_04.png",
      "video_time": "00:12"
    },
    {
      "step": 5,
      "text": "拉紧主绳和绳头",
      "image": "bowline_05.png",
      "video_time": "00:15"
    }
  ],
  "common_mistakes": [
    "未形成完整小圈",
    "绳头穿错方向",
    "主绳和绳头未拉紧",
    "绳圈大小不合适"
  ],
  "related_knots": ["double_bowline", "portuguese_bowline"],
  "prerequisites": ["single_knot", "figure_eight"],
  "video_url": "bowline.mp4",
  "animation_url": "bowline.glb"
}
```

### 7.6 绳结学习 UI

```
┌─────────────────────────────┐
│  ← 绳结 / 布林结            │
├─────────────────────────────┤
│  [3D 动画展示]              │
│  ▶ 自动播放                  │
├─────────────────────────────┤
│  步骤 3 / 5                 │
│  绳头从主绳下方绕过          │
│  [图]                       │
│  ▶ 单步视频                  │
├─────────────────────────────┤
│  用途:                       │
│  救援套人 / 攀岩 / 拖拽      │
│                             │
│  常见错误:                   │
│  ⚠️ 绳头穿错方向会导致        │
│  打不紧或解开困难            │
├─────────────────────────────┤
│  [上一结] [下一结] [练习]    │
└─────────────────────────────┘
```

---

## 八、应急储备模块

### 8.1 应急储备分类

```
按场景分
├── 日常应急（家中 / 车内）
├── 徒步应急（轻量）
├── 露营应急（中量）
├── 重装探险（完整）
└── 极端环境（极简生存）

按用途分
├── 急救
├── 庇护
├── 取火
├── 净水
├── 求救
├── 照明
├── 工具
└── 食物
```

### 8.2 储备清单模板

#### 8.2.1 轻量徒步（1 日）

| 类别 | 物品 | 数量 | 重量 | 关键 |
|---|---|---|---|---|
| 急救 | 创可贴 | 10 片 | 30g | ✓ |
| 急救 | 消毒湿巾 | 5 片 | 50g | ✓ |
| 急救 | 弹性绷带 | 1 卷 | 30g | ✓ |
| 急救 | 蛇毒吸附器 | 1 个 | 30g | ✓（南方必带）|
| 取火 | 防风打火机 | 1 | 20g | ✓ |
| 取火 | 防水火柴 | 1 盒 | 30g | |
| 取火 | 打火棒 | 1 | 50g | |
| 求救 | 口哨 | 1 | 10g | ✓ |
| 求救 | 小型信号镜 | 1 | 30g | |
| 净水 | 净水片 | 5 片 | 10g | |
| 工具 | 折叠刀 | 1 | 100g | ✓ |
| 工具 | 5m 伞绳 | 1 | 25g | ✓ |
| 工具 | 铝箔胶带 | 1 卷 | 30g | |
| 其他 | 应急毯 | 1 | 60g | ✓ |
| 其他 | 高能棒 | 2 | 100g | |
| 其他 | 头灯 + 备用电池 | 1 | 80g | |

**总重量**：约 **700g**

#### 8.2.2 多日露营（3-5 日）

增加：
- 帐篷、地席
- 睡袋、防潮垫
- 炊具、燃料
- 多日食物
- 备用衣物
- 净水器

**总重量**：约 **8-15kg**（不含帐篷睡袋）

#### 8.2.3 家庭应急储备（地震 / 断水断电 3-7 日）

| 类别 | 物品 | 数量 |
|---|---|---|
| 水 | 瓶装水 | 每人 3L/日 |
| 食物 | 压缩饼干 / 罐头 | 每人 2000kcal/日 |
| 急救 | 完整急救包 | 1 套 |
| 照明 | 手电 + 备用电池 | 每房间 1 |
| 取暖 | 暖宝宝 / 应急毯 | 每人 3 |
| 工具 | 多功能刀 | 1 |
| 工具 | 扳手（关水阀） | 1 |
| 通讯 | 充电宝（满电） | 1+ |
| 证件 | 复印件 | 1 套 |
| 现金 | 小额现金 | 500-1000 |
| 其他 | 口哨 | 每人一 |

### 8.3 自定义清单功能

```cpp
class EmergencyChecklist : public QObject {
    Q_OBJECT
public:
    struct Item {
        QString id;
        QString name;
        QString category;
        int quantity;
        double weightG;
        bool required;
        bool checked;
        QString note;
    };
    
    Q_INVOKABLE void loadTemplate(const QString& templateName);
    Q_INVOKABLE void addItem(Item item);
    Q_INVOKABLE void updateItem(QString id, Item item);
    Q_INVOKABLE QList<Item> getById();   // 2026-09-20 Phase 4: rename from getChecklist
    Q_INVOKABLE double getTotalWeight();
    Q_INVOKABLE QJsonObject exportToJson();
    Q_INVOKABLE void importFromJson(QJsonObject json);
    
signals:
    void itemChanged();
};
```

### 8.4 应急 UI

```
┌─────────────────────────────┐
│  ← 应急储备 / 轻量徒步        │
├─────────────────────────────┤
│  模板: 1 日轻量徒步          │
│  重量: 720g                  │
│  必备: 11 项                 │
│  建议: 5 项                  │
├─────────────────────────────┤
│  急救 (4)                    │
│  ☑ 创可贴 ×10              │
│  ☑ 消毒湿巾 ×5              │
│  ☑ 弹性绷带 ×1              │
│  ☑ 蛇毒吸附器 ×1  ★         │
├─────────────────────────────┤
│  取火 (3)                    │
│  ☑ 防风打火机 ×1            │
│  ☐ 防水火柴 ×1              │
│  ☐ 打火棒 ×1                │
├─────────────────────────────┤
│  [+ 添加物品]                │
│                             │
│  [导出 PDF] [分享]           │
└─────────────────────────────┘
```

---

## 九、防虫防蛇模块

### 9.1 蛇类防治

#### 9.1.1 中国常见毒蛇清单（30 种）

**剧毒（10 种）**
1. 银环蛇
2. 眼镜王蛇
3. 舟山眼镜蛇
4. 尖吻蝮（五步蛇）
5. 短尾蝮
6. 中介蝮
7. 原矛头蝮（烙铁头）
8. 竹叶青
9. 白唇竹叶青
10. 圆斑蝰

**常见（20 种）**
11. 虎斑颈槽蛇
12. 赤链蛇
13. 乌梢蛇
14. 王锦蛇
15. 黑眉锦蛇
16. 滑鼠蛇
17. 灰鼠蛇
18. 玉斑丽蛇
19. 红纹滞卵蛇
20. ...

#### 9.1.2 蛇类识别要点

```
头部形状
├── 三角形 → 多为蝰蛇科（毒）
├── 椭圆形 → 多为游蛇科（多为无毒）
└── 需结合其他特征

体色花纹
├── 银环 → 银环蛇（剧毒）
├── 黑白相间 → 注意环带分布
├── 绿色 → 竹叶青（毒）
└── 警戒色：红、黄、黑

行为
├── 主动攻击 → 眼镜王蛇、眼镜蛇
├── 逃跑 → 多为无毒
└── 静止 → 警惕

地域
├── 南方 > 北方
├── 山区 > 平原
└── 雨季 > 旱季
```

#### 9.1.3 防蛇装备

- 高帮登山鞋
- 蛇裤（南方夏季必穿）
- 蛇毒吸附器
- 弹弓（驱蛇）
- 雄黄粉（效果有限）
- 蛇伤急救包

#### 9.1.4 蛇伤急救决策树

详见 5.2.2

### 9.2 虫类防治

#### 9.2.1 中国户外危险虫类（20 种）

**致命 / 高风险**
1. 蜱虫（传播森林脑炎、莱姆病）
2. 恙螨（恙虫病）
3. 毒隐翅虫（皮炎）
4. 蜂类（胡蜂、虎头蜂）
5. 蚂蚁（红火蚁）
6. 蜈蚣
7. 蝎子
8. 蜘蛛（黑寡妇）
9. 蚂蟥（南方山区）

**常见困扰**
10. 蚊子（疟疾、登革热）
11. 蠓（南方）
12. 跳蚤
13. 虱子
14. 螨虫
15. 牛虻
16. 毛毛虫（毒蛾）
17. ...

#### 9.2.2 防虫装备

- 驱虫剂（DEET / 派卡瑞丁）
- 蚊帐 / 防虫头网
- 长袖长裤
- 防蚤袜
- 防虫手套
- 蚊香、电蚊香
- 抗组胺药

#### 9.2.3 虫伤处理

| 虫类 | 处理 | 警示 |
|---|---|---|
| 蜂蛰 | 拔刺、冷敷、抗组胺 | 过敏者立即就医 |
| 蜱虫 | 镊子完整取出、消毒 | **不可硬拽** |
| 蚂蟥 | 盐/酒精/火烧脱落 | 不可硬拽 |
| 毒蜘蛛 | 冷敷、就医 | 神经毒立即就医 |
| 蜈蚣 | 冷敷、消毒、止痛 | 严重就医 |
| 恙螨 | 消毒、抗组胺 | 持续发热立即就医 |

### 9.3 防虫防蛇 UI

```
┌─────────────────────────────┐
│  ← 防虫防蛇                  │
├─────────────────────────────┤
│  [拍照识别] [按地区] [按季节] │
├─────────────────────────────┤
│  ⚠️ 重点关注                  │
│  📍 当前: 云南西双版纳        │
│  📅 季节: 夏季               │
│                             │
│  危险等级: ★★★★★           │
│  风险: 蛇、蜂、蚂蟥、蚊虫     │
├─────────────────────────────┤
│  蛇类 (8)                   │
│  [缩略图] 银环蛇 / 剧毒      │
│  [缩略图] 竹叶青 / 毒        │
│  ...                        │
├─────────────────────────────┤
│  虫类 (12)                  │
│  [缩略图] 蜱虫 / 严重        │
│  [缩略图] 蚂蟥 / 烦人        │
│  ...                        │
├─────────────────────────────┤
│  装备清单: [查看]            │
│  急救预案: [查看]            │
└─────────────────────────────┘
```

---

## 十、中国动植物识别体系

### 10.1 优先识别物种（MVP 精选 730 种）

#### A. 植物 500 种（按地区 / 场景）
- 城市公园 100 种
- 郊野 100 种
- 山区 200 种
- 高原 50 种
- 南方特有 50 种

#### B. 动物 100 种
- 哺乳类 30 种
- 鸟类 40 种
- 爬行类 20 种
- 两栖类 10 种

#### C. 蛇类 30 种（全部有毒）
- 剧毒 10 种
- 常见毒蛇 20 种

#### D. 蘑菇 50 种
- 致命 10 种（重点警示）
- 有毒 20 种
- 可食 20 种（慎重推荐）

#### E. 昆虫 50 种
- 危险 20 种
- 烦人 20 种
- 益虫 / 无害 10 种

### 10.2 模型训练策略

```
模型 1: 通用植物识别
- 训练数据: 50,000+ 张
- 类别: 500
- 基础架构: EfficientNet-B0
- 量化: INT8
- 大小: 20MB

模型 2: 蛇类识别（专项）
- 训练数据: 5,000+ 张（多角度）
- 类别: 30
- 基础架构: EfficientNet-B0
- 数据增强: 重（光、角度、距离）
- 量化: INT8
- 大小: 15MB

模型 3: 蘑菇识别
- 训练数据: 8,000+ 张
- 类别: 50
- 基础架构: EfficientNet-B0
- 重点: 致命物种的召回率
- 大小: 18MB

模型 4: 危险动物识别
- 训练数据: 6,000+ 张
- 类别: 100
- 大小: 20MB
```

### 10.3 识别准确性目标

| 类别 | Top-1 准确率 | Top-5 召回率 |
|---|---|---|
| 普通植物 | > 85% | > 95% |
| 蛇类 | > 90% | > 98% |
| 蘑菇 | > 80% | > 95% |
| 危险动物 | > 90% | > 98% |

⚠️ **关键策略**：高风险物种（剧毒蛇、致命蘑菇）必须高召回，宁可误报也要让用户警觉。

---

## 十一、离线架构设计

### 11.1 离线资源管理

```cpp
class OfflineManager : public QObject {
    Q_OBJECT
public:
    enum ResourceType {
        Models,        // AI 模型
        Data,          // 数据库
        Media,         // 图片 / 视频
        Maps           // 地图
    };
    
    struct Resource {
        QString id;
        ResourceType type;
        QString name;
        qint64 sizeBytes;
        QString version;
        bool downloaded;
        bool required;
    };
    
    Q_INVOKABLE QList<Resource> getResources();
    Q_INVOKABLE void downloadResource(QString id);
    Q_INVOKABLE void deleteResource(QString id);
    Q_INVOKABLE qint64 getTotalDownloadedSize();
    Q_INVOKABLE qint64 getTotalSize();
    Q_INVOKABLE bool isFullyOffline();
    
signals:
    void downloadProgress(QString id, qint64 received, qint64 total);
    void downloadComplete(QString id, bool success);
    void storageChanged();
};
```

### 11.2 离线包设计

#### 基础包（必下，30MB）
- 基础急救手册
- 基础避险内容
- 基础生存技巧
- 通用识别模型（占位）

#### 中国通用包（推荐 200MB）
- 500 种植物
- 100 种动物
- 30 种毒蛇
- 急救完整内容
- 视频教程精简版

#### 区域包（按需 100-500MB）
- 华东包
- 华南包
- 西南包
- 西北包
- 东北包
- 高原包

#### 完整包（1-2GB）
- 全物种
- 全部视频
- 高清 3D 动画
- 全国地图

### 11.3 离线策略

```
资源加载优先级
1. 启动时：仅加载基础包
2. 用户进入模块：按需加载该模块资源
3. 后台空闲：预加载下一个可能进入的模块
4. 智能预测：根据历史使用预测下载

缓存策略
- LRU 缓存最近 7 天访问内容
- 用户主动收藏的永久保留
- 自动清理未访问超过 30 天的资源
```

### 11.4 模型加载与卸载

```cpp
class ModelManager {
public:
    bool loadModel(const QString& modelId);
    void unloadModel(const QString& modelId);
    void unloadAllExcept(const QStringList& keep);
    
    // 智能加载
    void onModuleEntered(const QString& module);
    void onModuleExited(const QString& module);
    
    // 内存监控
    void onLowMemory();
    qint64 getCurrentMemoryUsage();
};
```

---

## 十二、UI / UX 规范

### 12.1 设计原则

1. **户外优先** —— 强光可读、戴手套可操作、单手可达
2. **清晰层级** —— 重要信息最显眼
3. **离线感知** —— 始终显示离线 / 在线状态
4. **快速操作** —— 核心功能 3 次点击内可达
5. **紧急通道** —— SOS 一键触发

### 12.2 主题方案

#### 普通主题（室内 / 弱光）
- Material Design 3
- 浅色 / 深色模式
- 强调色：橙红色

#### 户外主题（默认）
- 高对比度配色
- 大字体（默认 18sp）
- 黑底 + 高亮文字（黄/橙/红）
- 最小点击区域 56dp

```
┌─────────────────────────────┐
│ ▓▓▓▓▓ 顶栏 - 高对比度黑色背景 ▓▓▓ │
├─────────────────────────────┤
│                             │
│   [识别]  [急救]  [避险]      │
│   ────────────────────      │
│   [绳结]  [路线]  [防虫蛇]    │
│   ────────────────────      │
│   [应急储备]  [手册]          │
│                             │
│         [ SOS 长按 ]         │
│                             │
├─────────────────────────────┤
│ 状态栏：电量 | GPS | 离线     │
└─────────────────────────────┘
```

### 12.3 关键页面线框图

#### 拍照识别页
```
┌─────────────────────────────┐
│ ← 拍照识别       [相册] [⚙]  │
├─────────────────────────────┤
│                             │
│  [相机预览]                  │
│  ┌─ 识别框 ─┐               │
│  │          │               │
│  │          │               │
│  └──────────┘               │
│                             │
├─────────────────────────────┤
│ [植物] [动物] [蛇] [蘑菇]    │
│                             │
│        ⊙ 拍照按钮             │
└─────────────────────────────┘
```

#### 急救首页
```
┌─────────────────────────────┐
│ ← 急救                       │
├─────────────────────────────┤
│  🔍 搜索症状或急症           │
├─────────────────────────────┤
│  🚨 急症优先                 │
│  [心搏骤停 CPR]              │
│  [大出血] [窒息] [休克]      │
│                             │
│  💊 创伤处理                 │
│  [骨折] [烧烫伤] [切割伤]    │
│                             │
│  🌡️ 环境急症                │
│  [失温] [中暑] [高原反应]    │
│                             │
│  🐍 中毒急救                 │
│  [蛇咬伤] [食物中毒] [虫螫]  │
└─────────────────────────────┘
```

### 12.4 关键交互

- **SOS 长按 3 秒**：倒计时环 + 震动
- **拍照识别**：自动连拍 3 张选最佳
- **决策树**：左右滑切换 / 实体按钮
- **视频**：双击放大、画中画支持
- **搜索**：支持语音 + 文字
- **历史**：下拉刷新

### 12.5 无障碍

- 大字体模式
- 语音播报（户外不便看手机）
- 触觉反馈
- 夜间极简模式

---

## 十三、项目目录与代码结构

### 13.1 目录结构

```
outdoor_survival/
├── android/                    # Android 原生
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/com/outdoor/survival/
│   │   │   │   ├── MainActivity.java
│   │   │   │   ├── EmergencyService.java
│   │   │   │   ├── BootReceiver.java
│   │   │   │   └── PermissionHelper.java
│   │   │   ├── res/
│   │   │   └── AndroidManifest.xml
│   │   └── build.gradle
│   └── build.gradle
├── src/                        # C++ 业务
│   ├── core/
│   │   ├── App.{h,cpp}
│   │   ├── Config.{h,cpp}
│   │   ├── Logger.{h,cpp}
│   │   └── Database.{h,cpp}
│   ├── recognition/
│   │   ├── RecognitionEngine.{h,cpp}
│   │   ├── SpeciesInfo.{h,cpp}
│   │   └── RecognitionHistory.{h,cpp}
│   ├── firstaid/
│   │   ├── FirstAidService.{h,cpp}
│   │   └── DecisionEngine.{h,cpp}
│   ├── survival/
│   │   ├── SurvivalService.{h,cpp}
│   │   ├── FireMethods.{h,cpp}
│   │   ├── Shelters.{h,cpp}
│   │   └── Tools.{h,cpp}
│   ├── knots/
│   │   ├── KnotService.{h,cpp}
│   │   └── KnotTutorial.{h,cpp}
│   ├── routes/
│   │   ├── RouteService.{h,cpp}
│   │   └── RouteRecommender.{h,cpp}
│   ├── bugs/
│   │   ├── AntiBugService.{h,cpp}
│   │   ├── SnakeDB.{h,cpp}
│   │   └── InsectDB.{h,cpp}
│   ├── emergency/
│   │   ├── EmergencyService.{h,cpp}
│   │   ├── ChecklistService.{h,cpp}
│   │   └── LocationTracker.{h,cpp}
│   ├── ai/
│   │   ├── NCNNEngine.{h,cpp}
│   │   ├── ImagePreprocessor.{h,cpp}
│   │   └── ModelManager.{h,cpp}
│   ├── data/
│   │   ├── AssetLoader.{h,cpp}
│   │   ├── DataImporter.{h,cpp}
│   │   └── Encryption.{h,cpp}
│   ├── platform/
│   │   ├── PlatformInterface.h
│   │   ├── AndroidPlatform.{h,cpp}
│   │   └── PermissionManager.{h,cpp}
│   └── main.cpp
├── qml/                        # QML 界面
│   ├── Main.qml
│   ├── pages/
│   │   ├── HomePage.qml
│   │   ├── CameraPage.qml
│   │   ├── ResultPage.qml
│   │   ├── FirstAidPage.qml
│   │   ├── SurvivalPage.qml
│   │   ├── KnotPage.qml
│   │   ├── KnotDetailPage.qml
│   │   ├── RoutePage.qml
│   │   ├── RouteDetailPage.qml
│   │   ├── BugPage.qml
│   │   ├── ChecklistPage.qml
│   │   └── ManualPage.qml
│   ├── components/
│   │   ├── SpeciesCard.qml
│   │   ├── KnotStep.qml
│   │   ├── RouteCard.qml
│   │   ├── ChecklistItem.qml
│   │   ├── DecisionNode.qml
│   │   └── EmergencyButton.qml
│   ├── views/
│   │   ├── Knot3DView.qml
│   │   └── DecisionTreeView.qml
│   └── qmldir
├── assets/                     # 静态资源
│   ├── data/                   # 初始数据库
│   ├── models/                 # AI 模型
│   ├── media/                  # 图片 / 视频
│   ├── i18n/                   # 多语言
│   ├── fonts/
│   └── themes/
├── third_party/                # 第三方库
│   ├── ncnn/
│   ├── opencv/
│   ├── sqlcipher/
│   ├── spdlog/
│   └── nlohmann/
├── scripts/                    # 构建 / 数据脚本
│   ├── build/
│   ├── data_pipeline/
│   └── train/
├── tests/                      # 测试
│   ├── unit/
│   ├── integration/
│   ├── ui/
│   └── data/
├── docs/                       # 文档
│   ├── api/
│   ├── design/
│   └── content/
├── tools/                      # 工具
│   ├── data_validator/
│   ├── model_converter/
│   └── apk_builder/
├── CMakeLists.txt
├── README.md
├── LICENSE
└── .gitignore
```

### 13.2 关键文件模板

#### CMakeLists.txt
```cmake
cmake_minimum_required(VERSION 3.22)
project(OutdoorSurvival VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core Gui Qml Quick QuickControls2
    Multimedia MultimediaWidgets
    Location Positioning Sensors
    Sql Network
)

qt_standard_project_setup(REQUIRES 6.5)

# 第三方库
add_subdirectory(third_party/ncnn)
add_subdirectory(third_party/opencv)
# ...

qt_add_executable(OutdoorSurvival src/main.cpp)

qt_add_qml_module(OutdoorSurvival
    URI OutdoorSurvival
    VERSION 1.0
    QML_FILES qml/Main.qml qml/pages/*.qml qml/components/*.qml
    SOURCES
        src/core/*.cpp
        src/recognition/*.cpp
        src/firstaid/*.cpp
        src/survival/*.cpp
        src/knots/*.cpp
        src/routes/*.cpp
        src/bugs/*.cpp
        src/emergency/*.cpp
        src/ai/*.cpp
        src/data/*.cpp
        src/platform/*.cpp
)

target_link_libraries(OutdoorSurvival PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Multimedia
    ncnn opencv_core opencv_imgproc sqlcipher
    spdlog nlohmann_json
)
```

---

## 十四、实施阶段划分

### 阶段总览（12 个月）

```
月份  1   2   3   4   5   6   7   8   9   10  11  12
      ├───┴───┤
      P0 基础架构 + 植物识别 50 种 + 急救基础
              ├───┴───┤
              P1 扩展识别 + 急救完整 + 避险基础
                      ├───┴───┤
                      P2 绳结 + 路线 + 防虫蛇
                              ├───┴───┤
                              P3 应急储备 + 完整手册
                                      ├───┴───┤
                                      P4 内测 + 优化
                                              ├───┴───┤
                                              P5 公测 + 上架
```

### 14.1 P0：基础（1-2 月）
**目标**：跑通核心流程
- 项目脚手架
- Android 平台适配
- 拍照 + 植物识别（50 种）
- 基础急救 20 条
- 基础避险 5 项
- 离线基础包

### 14.2 P1：识别 + 急救扩展（3-4 月）
- 植物 500 种
- 动物 100 种
- 蛇 30 种
- 蘑菇 50 种
- 急救 200 条 + 决策树 50 个
- 视频教程 20 个

### 14.3 P2：避险深入（5-6 月）
- 取火 12 种方法
- 庇护所 10 种
- 工具制作 30 种
- 净水 5 种
- 求救信号
- 定向方法

### 14.4 P3：绳结 + 路线 + 防虫（7-8 月）
- 绳结 30 种 + 3D 动画
- 路线 100 条
- 防虫防蛇完整内容
- 应急储备 + 清单
- 完整手册

### 14.5 P4：内测 + 优化（9-10 月）
- 内测 500 用户
- 性能优化
- 国产 ROM 适配
- 商店资料准备
- 软著 + ICP

### 14.6 P5：公测 + 上架（11-12 月）
- 公测 5000 用户
- Bug 修复
- 国内 6 大商店上架
- Google Play 备选
- 运营启动

---

## 十五、第一个月开发计划（详）

### 第 1 周：项目脚手架
| 天 | 任务 |
|---|---|
| Day 1 | 项目初始化、CMakeLists、Qt 工程 |
| Day 2 | Android NDK 集成、Gradle 配置 |
| Day 3 | NCNN 集成（测试用例） |
| Day 4 | SQLite 集成、数据库 schema |
| Day 5 | 主框架 QML 页面 |
| Day 6-7 | 权限申请基础 |

**可交付**：可运行的空壳 App，拍照 → 存储 → 显示

### 第 2 周：拍照 + 模型加载
| 天 | 任务 |
|---|---|
| Day 8 | CameraX 集成 + Qt 桥接 |
| Day 9 | 图像预处理 OpenCV |
| Day 10 | 模型加载（用 ImageNet 预训练） |
| Day 11 | 端到端识别流程跑通 |
| Day 12 | 识别结果 UI 展示 |
| Day 13-14 | 性能优化（NCNN 量化） |

**可交付**：能识别 1000 类 ImageNet 的 Demo

### 第 3 周：植物识别（50 种）
| 天 | 任务 |
|---|---|
| Day 15 | 准备 50 种中国常见植物图 |
| Day 16 | LabelImg 标注 |
| Day 17 | 训练 EfficientNet-B0 |
| Day 18 | 模型导出 + NCNN 转换 |
| Day 19 | 集成到 App |
| Day 20-21 | 实地测试（公园、山区） |

**可交付**：能识别 50 种植物的 App

### 第 4 周：急救 + 基础避险
| 天 | 任务 |
|---|---|
| Day 22 | 急救 20 条内容编辑 |
| Day 23 | 急救 UI + 决策树基础 |
| Day 24 | 避险 5 项内容 |
| Day 25 | 取火、庇护所基础 |
| Day 26 | 一键 120 集成 |
| Day 27-28 | 整体测试 + Bug 修复 |

**可交付**：MVP 1.0 内测版（30MB）

### 第 1 个月产出
- 30MB App
- 50 种植物识别
- 20 条急救
- 5 项避险基础
- SOS 一键求救
- 可内部分发测试

---

## 十六、关键里程碑与可交付物

| 里程碑 | 时间 | 可交付物 | 验证标准 |
|---|---|---|---|
| **M0 脚手架** | 第 1 月底 | 可运行 Demo | 启动 < 3s，识别 < 1s |
| **M1 MVP 1.0** | 第 2 月底 | 50 植物 + 20 急救 | 内测 5 人反馈 |
| **M2 MVP 2.0** | 第 4 月底 | 730 物种 + 200 急救 | 内测 50 人 |
| **M3 Beta** | 第 6 月底 | 全部内容 + 绳结 + 路线 | 公开测试 500 人 |
| **M4 RC** | 第 8 月底 | 性能 / 兼容 / 合规 | 通过商店审核 |
| **M5 正式版** | 第 10 月底 | 6 大商店上架 | 累计下载 1 万 |
| **M6 运营期** | 第 12 月底 | 持续更新 + 数据驱动 | 累计下载 10 万 |

---

## 十七、团队配置建议

### 17.1 最小团队（4-5 人）
| 角色 | 人数 | 主要职责 |
|---|---|---|
| 全栈（Qt + AI） | 1 | 核心开发、模型集成 |
| Android 平台 | 1 | JNI / 商店 / 适配 |
| UI/UX + QML | 0.5 | 界面设计 |
| 内容编辑 | 1 | 急救 / 生存 / 绳结内容 |
| 医疗顾问 | 0.2 | 审核（外聘） |

**月成本**：约 8-12 万

### 17.2 推荐团队（8-10 人）
- 增：后端 / AI 训练 / 测试 / 运营
- **月成本**：约 25-35 万

### 17.3 关键岗位要求
| 岗位 | 核心能力 |
|---|---|
| Qt 主程 | Qt 6、Android、CMake、性能优化 |
| AI 工程师 | PyTorch、模型训练、量化、ONNX |
| 内容编辑 | 户外经验 + 写作 + 资料整合 |
| 医疗顾问 | 执业医师 + 户外急救经验 |
| 设计师 | Material 3 + 户外场景感 |

---

## 十八、风险清单与应对

| # | 风险 | 等级 | 应对 |
|---|---|---|---|
| 1 | **AI 识别准确率不达预期** | 高 | Top-5 候选 + 专家审核 + 用户反馈 |
| 2 | **急救内容医疗纠纷** | **极高** | 医师审核 + 免责声明 + 强制 120 |
| 3 | **国产 ROM 适配困难** | 高 | 重点机型 + 白名单引导 |
| 4 | **App 体积膨胀** | 中 | AAB + 模型延迟下载 + 区域化 |
| 5 | **电池续航问题** | 中 | 户外模式 + 电量优化 |
| 6 | **数据版权** | 中 | 优先公共领域 + 学术使用协议 |
| 7 | **商店审核** | 中 | 软著 + ICP + 医疗资质 |
| 8 | **iOS 延后** | 低 | 短期 Android 优先 |
| 9 | **鸿蒙 NEXT** | 中 | 短期兼容，长期单独适配 |
| 10 | **众包标注质量** | 中 | 多人审核 + 专家抽检 |

### 关键风险预警

> ⚠️ **医疗 / 急救内容是头号风险**
> - 任何医疗建议必须经执业医师审核
> - 必须有清晰的"仅供参考"和"立即拨打 120"提示
> - 出现误诊导致伤害，可能承担法律责任
> - 建议购买产品责任保险

> ⚠️ **蘑菇 / 毒蛇识别是次高风险**
> - 必须多重提示（"切勿仅凭识别结果食用"）
> - 强制二次确认
> - 严格免责声明

---

## 十九、立即可启动的 5 件事

### 第 1 件：环境搭建（1-2 天）
- 安装 Qt 6.7 + Android 模块
- 安装 Android Studio
- 安装 NDK r26b
- 测试 Hello World APK

### 第 2 件：准备数据（3-5 天）
- 列出 50 种中国常见植物（公园、山区常见）
- 从 PPBC / iNaturalist 下载图片
- 准备 30 条急救内容（与医师沟通）
- 编写 5 项避险基础内容

### 第 3 件：搭建项目（2-3 天）
- 创建工程结构
- 集成 NCNN
- 集成 SQLite
- 主框架 QML

### 第 4 件：训练模型（5-7 天）
- 标注 50 种植物
- 训练 EfficientNet-B0
- 量化 + NCNN 转换
- 集成到 App

### 第 5 件：跑通 Demo（3-5 天）
- 拍照 → 识别 → 显示结果
- 急救 20 条
- SOS 一键 120
- 内部分发

**2-3 周内可看到 Demo**

---

## 附录 A：开源工具与库

| 工具 | 用途 | 协议 |
|---|---|---|
| Qt 6.7+ | 主框架 | LGPL / 商业 |
| NCNN | AI 推理 | BSD |
| OpenCV 4 | 图像处理 | Apache 2 |
| SQLite | 数据库 | 公共 |
| sqlcipher | 加密数据库 | BSD |
| spdlog | 日志 | MIT |
| nlohmann/json | JSON | MIT |
| zlib | 压缩 | zlib |
| libjpeg-turbo | JPEG | BSD |

## 附录 B：参考资料

- 《怀斯曼生存手册》中文版
- 《户外生存手册》中国林业出版社
- 《登山基础》中国登山协会
- 《FM 21-76 美国陆军生存手册》
- 《中国植物志》公开
- 《中国急救指南》卫健委
- iNaturalist / PlantNet / PPBC 公开数据集
- 中国国家地理、8264、绿野精华帖
- 各种绳结教学网站

## 附录 C：联系资源

- 中国登山协会培训部
- 各地红十字会
- 各地户外救援队
- 户外品牌（凯乐石、探路者）合作
- 医学院校户外医学课程

---

## 文档维护

- **创建日期**：2026-08-24
- **配套文档**：
  - `outdoor_survival_apps.md`（市场调研）
  - `outdoor_survival_app_design.md`（通用方案）
  - `android_adaptation.md`（Android 适配）
- **版本**：v1.0
- **更新周期**：每月迭代
