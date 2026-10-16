# 荒野手册 App - API 详细设计文档

> 本文档是 **App 手册（项目级）** 的核心组成部分，定义 App 软件中所有核心类的接口规范、调用方式、数据协议。

---

## 目录

1. [总则](#一总则)
2. [命名规范](#二命名规范)
3. [核心服务 API](#三核心服务-api)
4. [数据模型 API](#四数据模型-api)
5. [UI 层 API](#五ui-层-api)
6. [JNI 桥接 API](#六jni-桥接-api)
7. [错误码定义](#七错误码定义)
8. [版本兼容](#八版本兼容)

---

## 一、总则

### 1.1 文档目的
- 定义所有公共类的接口
- 统一命名规范
- 提供调用示例
- 约束兼容性

### 1.2 适用范围
- Qt 6.7+ for Android
- C++ 17/20
- QML 2.x

### 1.3 阅读对象
- C++ 业务开发者
- QML 界面开发者
- 测试工程师
- 内容编辑（数据接口部分）

---

## 二、命名规范

### 2.1 通用规则

| 类型 | 规则 | 示例 |
|---|---|---|
| 类名 | PascalCase | `RecognitionEngine` |
| 命名空间 | 小写 | `outdoor` |
| 函数 | camelCase | `recognizeImage()` |
| 槽函数 | 同函数 | `onImageCaptured()` |
| 成员变量 | m_xxx + camelCase | `m_recognitionEngine` |
| 局部变量 | camelCase | `imageBuffer` |
| 常量 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| 枚举 | PascalCase + 值 PascalCase | `enum class ErrorCode` |
| 信号 | camelCase（过去式） | `recognitionCompleted()` |
| 文件名 | 同类名 | `RecognitionEngine.h` |
| QML ID | camelCase | `recognitionView` |
| QML 文件 | PascalCase | `HomePage.qml` |
| Q_PROPERTY | 同成员变量 | `Q_PROPERTY(int count)` |

### 2.2 Qt 特定

- `Q_OBJECT` 宏的类必须使用 `Q_PROPERTY`、`Q_INVOKABLE`、`Q_SIGNALS`、`Q_SLOTS`
- 信号命名过去式：`imageLoaded`（已完成）、`loading`（进行中）
- QML 暴露的属性使用 `Q_PROPERTY`
- 暴露给 QML 的函数使用 `Q_INVOKABLE`

### 2.3 文件组织

```
src/
├── core/
│   ├── App.h / App.cpp
│   ├── Config.h / Config.cpp
│   ├── Logger.h / Logger.cpp
│   └── Database.h / Database.cpp
├── recognition/
│   ├── RecognitionEngine.h / .cpp
│   ├── SpeciesInfo.h / .cpp
│   └── RecognitionHistory.h / .cpp
└── ...
```

---

## 三、核心服务 API

### 3.1 识别模块

#### 3.1.1 RecognitionEngine

```cpp
namespace outdoor {

class RecognitionEngine : public QObject {
    Q_OBJECT
    
public:
    enum class Category {
        Plant = 0,
        Animal = 1,
        Snake = 2,
        Mushroom = 3,
        Insect = 4,
    };
    Q_ENUM(Category)
    
    enum class Status {
        Success,
        LowConfidence,
        ModelNotLoaded,
        InvalidImage,
        Timeout,
        UnknownError
    };
    Q_ENUM(Status)
    
    struct Alternative {
        QString speciesId;
        QString scientificName;
        QString commonName;
        float confidence;
        Category category;
    };
    
    struct Result {
        Status status;
        QString speciesId;            // 主结果 ID（status == Success 时）
        QString scientificName;
        QString commonName;
        Category category;
        float confidence;              // 0.0-1.0
        QList<Alternative> alternatives; // Top-5
        qint64 elapsedMs;
        QString errorMessage;          // 错误时
    };
    
    explicit RecognitionEngine(QObject* parent = nullptr);
    ~RecognitionEngine();
    
    // 初始化（必须先调用）
    Q_INVOKABLE bool initialize(const QString& modelsDir);
    Q_INVOKABLE void shutdown();
    
    // 同步识别（阻塞）
    Q_INVOKABLE Result recognize(const QString& imagePath, Category cat);
    Q_INVOKABLE Result recognizeFromImage(const QImage& image, Category cat);
    Q_INVOKABLE Result recognizeFromData(const QByteArray& jpegData, Category cat);
    
    // 异步识别
    Q_INVOKABLE void recognizeAsync(const QString& imagePath, Category cat);
    Q_INVOKABLE void recognizeAsync(const QImage& image, Category cat);
    
    // 取消
    Q_INVOKABLE void cancel();
    
    // 状态
    Q_INVOKABLE bool isReady() const;
    Q_INVOKABLE QStringList getLoadedModels() const;
    Q_INVOKABLE QString getModelVersion(Category cat) const;
    
    // 配置
    Q_INVOKABLE void setConfidenceThreshold(float threshold);
    Q_INVOKABLE void setMaxResults(int max);
    
signals:
    void recognitionStarted(Category category);
    void recognitionProgress(int percent);
    void recognitionCompleted(Result result);
    void recognitionFailed(QString error);
    void modelLoaded(Category category, QString version);
};

} // namespace outdoor
```

**调用示例**：

```cpp
// 同步调用
auto result = engine_->recognize("/sdcard/plant.jpg", RecognitionEngine::Plant);
if (result.status == RecognitionEngine::Status::Success) {
    qInfo() << "识别成功:" << result.commonName 
            << "置信度:" << result.confidence;
}

// 异步调用
connect(engine_, &RecognitionEngine::recognitionCompleted,
        this, &MyClass::onResult);
engine_->recognizeAsync("/sdcard/snake.jpg", RecognitionEngine::Snake);
```

```qml
// QML 调用
RecognitionEngine {
    id: recognizer
    onRecognitionCompleted: function(result) {
        console.log("识别结果：" + result.commonName)
    }
}

Button {
    text: "识别"
    onClicked: recognizer.recognizeAsync("/sdcard/test.jpg", 
                                          RecognitionEngine.Plant)
}
```

---

#### 3.1.2 SpeciesInfo

```cpp
class SpeciesInfo : public QObject {
    Q_OBJECT
    
public:
    struct Full {
        QString id;
        QString scientificName;
        QString commonName;
        QStringList alias;
        QString category;
        QString family;
        QString genus;
        
        // 分布
        QStringList provinces;
        int elevationMin;
        int elevationMax;
        QStringList habitats;
        
        // 物候
        QStringList activeMonths;
        QStringList floweringMonths;
        QStringList fruitingMonths;
        
        // 风险
        int dangerLevel;            // 0-5
        bool edible;
        QStringList edibleParts;
        QStringList toxicParts;
        
        // 应对
        QStringList protectiveGear;
        QString firstAidId;
        QStringList countermeasures;
        
        // 描述
        QString description;
        QStringList features;       // 识别特征
        QStringList photos;         // 照片路径
        QStringList sourceRefs;
        
        int commonality;            // 1-5
        QString source;
    };
    
    Q_INVOKABLE Full getById(const QString& id);
    Q_INVOKABLE QList<Full> searchByName(const QString& keyword);
    Q_INVOKABLE QList<Full> getByCategory(const QString& category);
    Q_INVOKABLE QList<Full> getByRoute(const QString& routeId);
    Q_INVOKABLE QString getLocalizedName(const QString& id, 
                                           const QString& lang = "zh_CN");
    Q_INVOKABLE QString getPhotoPath(const QString& id, int index = 0);
    
signals:
    void infoLoaded(Full info);
    void infoNotFound(QString id);
};
```

---

#### 3.1.3 RecognitionHistory

```cpp
class RecognitionHistory : public QObject {
    Q_OBJECT
    
public:
    struct Record {
        qint64 id;                 // 数据库 ID
        QString sessionId;         // 一次会话 ID
        QString imagePath;         // 照片路径
        QString imageThumbPath;    // 缩略图
        QString speciesId;
        QString scientificName;
        QString commonName;
        QString category;
        float confidence;
        QGeoCoordinate location;
        int elevation;
        double accuracy;
        QString routeId;           // 关联路线（可选）
        QString note;
        QDateTime createdAt;
        bool isFavorite;
    };
    
    Q_INVOKABLE qint64 addRecord(Record record);
    Q_INVOKABLE bool updateRecord(qint64 id, Record record);
    Q_INVOKABLE bool deleteRecord(qint64 id);
    Q_INVOKABLE bool deleteRecords(const QList<qint64>& ids);
    
    Q_INVOKABLE QList<Record> getRecent(int limit = 50);
    Q_INVOKABLE QList<Record> getByCategory(const QString& category, 
                                              int limit = 100);
    Q_INVOKABLE QList<Record> getByRoute(const QString& routeId);
    Q_INVOKABLE QList<Record> getFavorites();
    Q_INVOKABLE Record getById(qint64 id);
    
    Q_INVOKABLE bool setFavorite(qint64 id, bool favorite);
    Q_INVOKABLE bool addNote(qint64 id, const QString& note);
    
    Q_INVOKABLE int getTotalCount();
    Q_INVOKABLE qint64 getTotalSize();  // 图片占用
    
    Q_INVOKABLE bool clearAll();
    
signals:
    void recordAdded(qint64 id);
    void recordUpdated(qint64 id);
    void recordDeleted(qint64 id);
    void historyChanged();
};
```

---

### 3.2 急救模块

#### 3.2.1 FirstAidService

```cpp
class FirstAidService : public QObject {
    Q_OBJECT
    
public:
    enum class Urgency {
        Critical = 5,    // 立即
        High = 4,
        Medium = 3,
        Low = 2,
        Info = 1
    };
    Q_ENUM(Urgency)
    
    struct Entry {
        QString id;
        QString title;
        QString category;        // 急症/部位/环境/中毒
        Urgency urgency;
        QStringList symptoms;
        QString description;
        QStringList criticalActions;  // 关键步骤
        QStringList donts;            // 禁忌
        QString videoUrl;             // 视频路径
        QStringList relatedEntries;   // 关联条目
        QString source;               // 来源
        QString reviewer;             // 审核医师
        QDateTime lastReviewed;
    };
    
    struct DecisionNode {
        QString id;
        QString question;         // 问题
        QString text;             // 补充说明
        QStringList options;      // 选项
        QMap<QString, QString> nextNodes;  // option -> nextNodeId
        QString terminalAction;   // 终止动作
    };
    
    Q_INVOKABLE Entry getById(const QString& id);
    Q_INVOKABLE QList<Entry> getByCategory(const QString& category);
    Q_INVOKABLE QList<Entry> getByUrgency(Urgency urgency);
    Q_INVOKABLE QList<Entry> search(const QString& keyword);
    Q_INVOKABLE QList<Entry> getAll();
    
    Q_INVOKABLE DecisionNode getDecisionRoot(const QString& entryId);
    Q_INVOKABLE DecisionNode getDecisionNode(const QString& nodeId);
    Q_INVOKABLE QStringList getDecisionPath(const QString& entryId, 
                                              const QStringList& choices);
    
    Q_INVOKABLE QStringList getRelatedSpecies(const QString& entryId);
    
signals:
    void decisionPathUpdated(QString currentNodeId);
};
```

---

#### 3.2.2 EmergencyService

```cpp
class EmergencyService : public QObject {
    Q_OBJECT
    
public:
    struct Contact {
        QString name;
        QString phone;
        QString relation;        // 家人/朋友/救援
        bool isPrimary;
    };
    
    Q_INVOKABLE void setEmergencyContacts(const QList<Contact>& contacts);
    Q_INVOKABLE QList<Contact> getEmergencyContacts() const;
    Q_INVOKABLE void addContact(Contact contact);
    Q_INVOKABLE void deleteContact(int index);   // 2026-09-20 (Phase 4): rename from removeContact
    
    // 一键求救
    Q_INVOKABLE void triggerSOS();
    Q_INVOKABLE void cancelSOS();
    Q_INVOKABLE bool isSOSTriggering() const;
    
    // 拨打
    Q_INVOKABLE void call120();
    Q_INVOKABLE void call110();
    Q_INVOKABLE void call119();
    Q_INVOKABLE void callNumber(const QString& number);
    
    // 短信
    Q_INVOKABLE void sendSosSMSToAll(double lat, double lon);
    Q_INVOKABLE bool sendSMS(const QString& number, const QString& text);
    
    // 位置
    Q_INVOKABLE QGeoCoordinate getCurrentLocation();
    Q_INVOKABLE void startLocationUpdates();
    Q_INVOKABLE void stopLocationUpdates();
    Q_INVOKABLE bool isLocationAvailable() const;
    
    // 紧急信息
    Q_INVOKABLE QString getDeviceInfo() const;
    Q_INVOKABLE QString getBatteryLevel() const;
    
signals:
    void sosTriggered();
    void sosCancelled();
    void locationUpdated(QGeoCoordinate coord, double accuracy);
    void callInitiated(QString number);
    void smsSent(QString number, bool success);
    void errorOccurred(QString error);
};
```

---

### 3.3 避险 / 取火 / 庇护所模块

#### 3.3.1 SurvivalService

```cpp
class SurvivalService : public QObject {
    Q_OBJECT
    
public:
    enum class Topic {
        Fire,             // 取火
        Shelter,          // 庇护所
        Water,            // 净水
        Food,             // 食物
        Signaling,        // 求救信号
        Navigation,       // 导航定向
        Weather,          // 天气
        Tools,            // 工具
        Knots             // 绳结
    };
    Q_ENUM(Topic)
    
    struct Item {
        QString id;
        QString name;
        Topic topic;
        QString category;         // 子分类
        int difficulty;           // 1-5
        QStringList materials;    // 所需材料
        int estimatedTimeMin;     // 预计耗时
        QStringList applicableScenarios;  // 适用场景
        QStringList steps;        // 步骤（文字）
        QStringList stepsImages;  // 步骤图
        QStringList stepsVideos;  // 步骤视频
        QString description;
        QStringList warnings;     // 警告
        QStringList tips;         // 小贴士
    };
    
    Q_INVOKABLE QList<Item> getByTopic(Topic topic);
    Q_INVOKABLE QList<Item> getByCategory(Topic topic, const QString& category);
    Q_INVOKABLE Item getById(const QString& id);
    Q_INVOKABLE QList<Item> search(const QString& keyword);
    Q_INVOKABLE QList<Item> getByDifficulty(int min, int max);
    
    Q_INVOKABLE QStringList getCategories(Topic topic);
    Q_INVOKABLE QStringList getScenarios(Topic topic);
    
    Q_INVOKABLE QString getStepImage(const QString& itemId, int stepIndex);
    Q_INVOKABLE QString getStepVideo(const QString& itemId, int stepIndex);
};
```

---

#### 3.3.2 KnotService

```cpp
class KnotService : public QObject {
    Q_OBJECT
    
public:
    struct Knot {
        QString id;
        QString nameCn;
        QString nameEn;
        QString category;         // 基础/接绳/环形/锚定/特殊
        int difficulty;           // 1-3
        QStringList useCases;     // 用途
        struct Step {
            int index;
            QString text;
            QString imagePath;
            QString videoTime;    // 视频时间点
        };
        QList<Step> steps;
        QStringList commonMistakes;
        QStringList relatedKnots; // 关联
        QStringList prerequisites; // 前置
        QString videoUrl;
        QString animationUrl;     // 3D 动画
        QString practiceTip;
    };
    
    Q_INVOKABLE Knot getById(const QString& id);
    Q_INVOKABLE QList<Knot> getAll();
    Q_INVOKABLE QList<Knot> getByCategory(const QString& category);
    Q_INVOKABLE QList<Knot> getByDifficulty(int difficulty);
    Q_INVOKABLE QList<Knot> getLearningPath(const QString& startKnot = "");
    Q_INVOKABLE QList<Knot> search(const QString& keyword);
    
    // 学习进度
    Q_INVOKABLE bool markLearned(const QString& id);
    Q_INVOKABLE bool isLearned(const QString& id);
    Q_INVOKABLE int getLearnedCount();
    Q_INVOKABLE QStringList getLearnedIds();
    Q_INVOKABLE void resetProgress();
    
    // 练习提示
    Q_INVOKABLE QString getPracticeTip(const QString& id);
};
```

---

### 3.4 路线模块

#### 3.4.1 RouteService

```cpp
class RouteService : public QObject {
    Q_OBJECT
    
public:
    enum class Source {
        BuiltIn,        // 内置官方
        UserImported,   // 用户导入
        Shared          // 队友分享
    };
    Q_ENUM(Source)
    
    struct Route {
        QString id;
        QString name;
        QStringList alias;
        QString province;
        QString city;
        QString area;
        int difficulty;             // 1-5
        QString type;               // 休闲/徒步/重装/...
        double distanceKm;
        double durationHours;
        int daysNeeded;
        int elevationGainM;
        int elevationLossM;
        int maxAltitudeM;
        int minAltitudeM;
        QStringList bestSeason;
        QStringList terrain;
        QString highlights;
        QString description;
        Source source;
        QString sourceUrl;
        QString localTrackPath;
        bool permitRequired;
        QString permitInfo;
        QString rescuePhone;
        QGeoCoordinate trailhead;
        QGeoCoordinate trailend;
        QStringList tags;
        QDateTime createdAt;
        QDateTime updatedAt;
        QString author;
        int visitCount;
    };
    
    Q_INVOKABLE Route getById(const QString& id);
    Q_INVOKABLE QList<Route> getAll(Source source = Source::BuiltIn);
    Q_INVOKABLE QList<Route> getByDifficulty(int min, int max);
    Q_INVOKABLE QList<Route> getByProvince(const QString& province);
    Q_INVOKABLE QList<Route> search(const QString& keyword);
    Q_INVOKABLE QList<Route> getByLocation(double lat, double lon, 
                                             double radiusKm);
    Q_INVOKABLE QList<Route> getRecommended(QStringList preferences);
    
    // 增删改
    Q_INVOKABLE bool saveRoute(Route route);
    Q_INVOKABLE bool updateRoute(QString id, Route route);
    Q_INVOKABLE bool deleteRoute(QString id);
    
    // 路点
    Q_INVOKABLE QList<Waypoint> getWaypoints(const QString& routeId);
    Q_INVOKABLE QList<TrackPoint> getTrackPoints(const QString& routeId);
    Q_INVOKABLE QList<WaterSource> getWaterSources(const QString& routeId);
    Q_INVOKABLE QList<SupplyPoint> getSupplyPoints(const QString& routeId);
    Q_INVOKABLE QList<Danger> getDangers(const QString& routeId);
    
    // 收藏
    Q_INVOKABLE bool addFavorite(const QString& id);
    Q_INVOKABLE bool deleteFavorite(const QString& id);   // 2026-09-20 (Phase 4): rename from removeFavorite
    Q_INVOKABLE bool isFavorite(const QString& id);
    Q_INVOKABLE QList<Route> getFavorites();
    
    // 访问计数
    Q_INVOKABLE void incrementVisitCount(const QString& id);
    
signals:
    void routeAdded(QString id);
    void routeUpdated(QString id);
    void routeDeleted(QString id);
    void favoriteChanged(QString id, bool isFavorite);
};
```

---

#### 3.4.2 RouteRecommender

```cpp
class RouteRecommender : public QObject {
    Q_OBJECT
    
public:
    struct UserProfile {
        int experienceLevel;       // 1-5
        int fitnessLevel;          // 1-5
        double maxDistance;        // km
        int maxDays;
        QStringList preferredSeasons;
        QStringList preferredTerrain;
        double maxAltitude;
        bool riskTolerance;
        QStringList preferredAreas;
    };
    
    Q_INVOKABLE void setUserProfile(UserProfile profile);
    Q_INVOKABLE UserProfile getUserProfile() const;
    
    Q_INVOKABLE QList<Route> recommend(int limit = 10);
    Q_INVOKABLE QList<Route> recommendForSeason(int month, int limit = 10);
    Q_INVOKABLE QList<Route> recommendForBeginner(int limit = 10);
    Q_INVOKABLE QList<Route> recommendNearby(double lat, double lon, 
                                              double radiusKm,
                                              int limit = 10);
    
    Q_INVOKABLE double matchScore(Route route, UserProfile profile);
    
signals:
    void recommendationsChanged();
};
```

---

### 3.5 路线-物种匹配

#### 3.5.1 SpeciesRouteMatcher

```cpp
class SpeciesRouteMatcher : public QObject {
    Q_OBJECT
    
public:
    enum class Category {
        Plant,
        Animal,
        Snake,
        Mushroom,
        Insect
    };
    Q_ENUM(Category)
    
    struct MatchReason {
        QString type;              // 地理/海拔/生境/季节
        QString description;
        double weight;
    };
    
    struct MatchResult {
        QString speciesId;
        QString commonName;
        Category category;
        double matchScore;         // 0-100
        int dangerLevel;           // 0-5
        QList<MatchReason> reasons;
        QStringList protectiveGear;
        QString firstAidId;
    };
    
    Q_INVOKABLE QList<MatchResult> matchRoute(
        const QString& routeId, 
        const QDateTime& planDate = QDateTime());
    
    Q_INVOKABLE QList<MatchResult> matchLocation(
        double lat, double lon, int elevation, 
        const QDateTime& date = QDateTime());
    
    Q_INVOKABLE QList<MatchResult> getDangerous(
        const QString& routeId, 
        int minDangerLevel = 3);
    
    Q_INVOKABLE QList<MatchResult> getByCategory(
        const QString& routeId, Category category);
    
    Q_INVOKABLE QStringList getSafetyAdvice(const QString& routeId);
    Q_INVOKABLE QStringList getGearSuggestions(const QString& routeId);
    
    // 用户反馈
    Q_INVOKABLE void recordSeen(const QString& routeId, 
                                 const QString& speciesId);
    Q_INVOKABLE void recordNotSeen(const QString& routeId, 
                                    const QString& speciesId);
    
signals:
    void matchResultReady(QString routeId, QList<MatchResult> results);
};
```

---

### 3.6 应急储备模块

#### 3.6.1 ChecklistService

```cpp
class ChecklistService : public QObject {
    Q_OBJECT
    
public:
    struct Item {
        QString id;
        QString name;
        QString category;          // 急救/取火/求救/...
        int quantity;
        double weightG;            // 克
        bool required;             // 是否必备
        bool checked;
        QString note;
        QStringList alternatives;  // 替代品
    };
    
    struct Checklist {
        QString id;
        QString name;
        QString scenario;          // 场景标签
        QList<Item> items;
        double totalWeightG;
        int totalCount;
        int checkedCount;
        QDateTime updatedAt;
    };
    
    Q_INVOKABLE QList<Checklist> getTemplates();
    Q_INVOKABLE Checklist loadTemplate(const QString& id);
    Q_INVOKABLE Checklist createCustom(const QString& name);
    Q_INVOKABLE bool save(Checklist checklist);
    Q_INVOKABLE bool deleteChecklist(const QString& id);
    
    Q_INVOKABLE bool setItemChecked(const QString& checklistId, 
                                      const QString& itemId, 
                                      bool checked);
    Q_INVOKABLE bool setItemQuantity(const QString& checklistId, 
                                      const QString& itemId, 
                                      int quantity);
    Q_INVOKABLE bool setItemNote(const QString& checklistId, 
                                  const QString& itemId, 
                                  const QString& note);
    Q_INVOKABLE bool addItem(const QString& checklistId, Item item);
    Q_INVOKABLE bool deleteItem(const QString& checklistId,     // 2026-09-20 (Phase 4): rename from removeItem
                                 const QString& itemId);
    
    // 2026-09-20 (Phase 4): add getById - rename from getChecklist
    Q_INVOKABLE Checklist getById(const QString& id);
    
    Q_INVOKABLE QJsonObject exportToJson(const QString& checklistId);
    Q_INVOKABLE bool importFromJson(QJsonObject json);
    Q_INVOKABLE QString exportToText(const QString& checklistId);
    Q_INVOKABLE bool exportToPdf(const QString& checklistId, 
                                  const QString& filePath);
    
signals:
    void checklistChanged(QString id);
    void itemChanged(QString checklistId, QString itemId);
};
```

---

### 3.7 数据导入模块

#### 3.7.1 ImportManager

```cpp
class ImportManager : public QObject {
    Q_OBJECT
    
public:
    enum class Format {
        Unknown,
        GPX,
        KML,
        KMZ,
        TCX,
        FIT,
        GeoJSON,
        CSV,
        OutdoorJSON,
        ImageOCR,
        PDF,
        Url
    };
    Q_ENUM(Format)
    
    enum class Status {
        Success,
        PartialSuccess,
        Warning,
        Failed
    };
    Q_ENUM(Status)
    
    struct ImportReport {
        Status status;
        QString message;
        QStringList warnings;
        QStringList suggestions;
        QString importedRouteId;
        QDateTime timestamp;
    };
    
    Q_INVOKABLE Format detectFormat(const QString& filePath);
    Q_INVOKABLE Format detectFromUrl(const QString& url);
    
    // 同步导入（小文件）
    Q_INVOKABLE ImportReport importFile(const QString& filePath);
    Q_INVOKABLE ImportReport importText(const QString& text);
    Q_INVOKABLE ImportReport importUrl(const QString& url);
    Q_INVOKABLE ImportReport importImage(const QString& imagePath);
    
    // 异步导入（大文件 / 网络）
    Q_INVOKABLE void importFileAsync(const QString& filePath);
    Q_INVOKABLE void importUrlAsync(const QString& url);
    Q_INVOKABLE void cancel();
    
    // 分享
    Q_INVOKABLE QString generateShareCode(const QString& routeId);
    Q_INVOKABLE QString generateSharePackage(const QString& routeId, 
                                               const QString& filePath);
    Q_INVOKABLE ImportReport importShareCode(const QString& code);
    Q_INVOKABLE ImportReport importSharePackage(const QString& filePath);
    
    // 预览
    Q_INVOKABLE QVariant getPreview(const QString& filePath);
    Q_INVOKABLE bool confirmImport(const QString& previewId);
    Q_INVOKABLE void cancelPreview(const QString& previewId);
    
signals:
    void importProgress(QString taskId, int percent);
    void importParsed(QString taskId, QVariant preview, ImportReport report);
    void importCompleted(QString taskId, ImportReport report);
    void importFailed(QString taskId, QString error);
};
```

---

### 3.8 离线资源管理

#### 3.8.1 OfflineManager

```cpp
class OfflineManager : public QObject {
    Q_OBJECT
    
public:
    enum class ResourceType {
        Model,
        Data,
        Media,
        Map
    };
    Q_ENUM(ResourceType)
    
    struct Resource {
        QString id;
        ResourceType type;
        QString name;
        QString description;
        qint64 sizeBytes;
        QString version;
        QString checksum;
        bool downloaded;
        bool required;
        QString localPath;
        QDateTime downloadedAt;
    };
    
    Q_INVOKABLE QList<Resource> getAll();
    Q_INVOKABLE QList<Resource> getDownloaded();
    Q_INVOKABLE QList<Resource> getByType(ResourceType type);
    Q_INVOKABLE Resource getById(const QString& id);
    
    Q_INVOKABLE void download(const QString& id);
    Q_INVOKABLE void downloadAll();
    Q_INVOKABLE void cancelDownload(const QString& id);
    Q_INVOKABLE bool remove(const QString& id);
    
    Q_INVOKABLE qint64 getTotalSize();
    Q_INVOKABLE qint64 getDownloadedSize();
    Q_INVOKABLE double getDownloadProgress(const QString& id);
    
    Q_INVOKABLE bool isFullyOffline();
    Q_INVOKABLE QStringList getMissingRequired();
    
    // 模型加载
    Q_INVOKABLE bool loadModel(const QString& modelId);
    Q_INVOKABLE void unloadModel(const QString& modelId);
    Q_INVOKABLE void unloadAll();
    Q_INVOKABLE QStringList getLoadedModels();
    
signals:
    void downloadProgress(QString id, qint64 received, qint64 total);
    void downloadCompleted(QString id, bool success);
    void resourceRemoved(QString id);
    void storageChanged();
};
```

---

## 四、数据模型 API

### 4.1 完整数据结构

```cpp
// Waypoint - 路点
struct Waypoint {
    QString name;
    QString type;              // start/end/summit/pass/camp/view/water/danger
    QGeoCoordinate coord;
    int elevation;
    QString description;
    QStringList photos;
    int sequence;
};

// TrackPoint - 轨迹点
struct TrackPoint {
    QGeoCoordinate coord;
    int elevation;
    QDateTime time;
    double accuracy;
    double speed;              // m/s
    int sequence;
};

// WaterSource - 水源
struct WaterSource {
    QString name;
    QGeoCoordinate coord;
    QString type;              // 泉水/溪流/湖泊/水井
    QString reliability;       // 常年/季节性/雨季
    QString description;
};

// SupplyPoint - 补给点
struct SupplyPoint {
    QString name;
    QGeoCoordinate coord;
    QString type;              // 住宿/餐馆/商店/救援站
    bool hasFood;
    bool hasWater;
    bool canCamp;
    QString contact;
};

// Danger - 危险
struct Danger {
    QString type;              // 迷路/落石/洪水/毒蛇/...
    QString severity;          // 低/中/高
    QString description;
    QList<QGeoCoordinate> locations;
    QString season;
    QString countermeasure;
};
```

### 4.2 数据访问模式

```cpp
// 仓储模式
class SpeciesRepository {
public:
    // 单条
    Species getById(const QString& id);
    bool exists(const QString& id);
    
    // 列表
    QList<Species> getAll();
    QList<Species> getByCategory(const QString& category);
    QList<Species> getByDangerLevel(int minLevel);
    QList<Species> getByRegion(double minLat, double maxLat,
                                double minLon, double maxLon);
    QList<Species> getByElevation(int minEle, int maxEle);
    
    // 搜索
    QList<Species> search(const QString& keyword);
    
    // 写入
    bool insert(const Species& species);
    bool update(const Species& species);
    bool remove(const QString& id);
    
    // 统计
    int count();
    int countByCategory(const QString& category);
    
signals:
    void speciesAdded(QString id);
    void speciesUpdated(QString id);
    void speciesRemoved(QString id);
};
```

---

## 五、UI 层 API

### 5.1 QML 命名规范

| 元素 | 规范 | 示例 |
|---|---|---|
| 组件 ID | camelCase | `recognitionView` |
| 属性 | camelCase | `imagePath` |
| 信号处理器 | on + PascalCase | `onClicked`, `onCompleted` |
| 状态 | `xxx` 模式 | `loading`, `loaded`, `error` |
| 列表模型 | `xxxModel` | `speciesListModel` |

### 5.2 标准组件 API

```qml
// 物种卡片组件
SpeciesCard {
    id: card
    property var speciesData: null
    property bool highlighted: false
    property int maxLines: 3
    signal clicked()
    signal longPressed()
}

// 急救决策节点
DecisionNodeView {
    id: nodeView
    property var nodeData: null
    property bool isLast: false
    signal optionSelected(int index, string label)
}

// 路线地图视图
RouteMapView {
    id: mapView
    property var route: null
    property var overlays: []
    property int overlayLevel: 0     // 0:路线 1:危险 2:植物 3:动物
    signal pointClicked(var coord)
    signal routeCompleted()
}
```

### 5.3 页面间通信

```qml
// 方式 1: StackView
StackView.push("DetailPage.qml", { "id": xxx })

// 方式 2: 全局 Bus
EventBus {
    id: bus
}

// 方式 3: 共享 Store
AppStore {
    id: store
}

// 方式 4: 信号
signal navigateTo(var page, var params)
```

### 5.4 国际化

```qml
import OutdoorSurvival 1.0

Text {
    text: qsTr("识别")            // 简单翻译
    text: qsTr("识别 %1 种").arg(count)  // 带参数
}
```

---

## 六、JNI 桥接 API

### 6.1 AndroidPlatform

```cpp
class AndroidPlatform : public QObject {
    Q_OBJECT
    
public:
    // 权限
    Q_INVOKABLE bool checkPermission(const QString& permission);
    Q_INVOKABLE void requestPermission(const QString& permission, 
                                        std::function<void(bool)> callback);
    Q_INVOKABLE QStringList getGrantedPermissions();
    
    // 系统
    Q_INVOKABLE void makePhoneCall(const QString& number);
    Q_INVOKABLE void sendSMS(const QString& number, const QString& text);
    Q_INVOKABLE void openUrl(const QString& url);
    Q_INVOKABLE void openAppSettings();
    
    // 硬件
    Q_INVOKABLE void vibrate(int milliseconds);
    Q_INVOKABLE bool hasFlashlight();
    Q_INVOKABLE void setFlashlight(bool on);
    Q_INVOKABLE int getBatteryLevel();
    Q_INVOKABLE bool isCharging();
    
    // 屏幕
    Q_INVOKABLE void keepScreenOn(bool on);
    Q_INVOKABLE void setBrightness(double value);  // 0.0-1.0
    Q_INVOKABLE int getScreenWidth();
    Q_INVOKABLE int getScreenHeight();
    Q_INVOKABLE float getScreenDensity();
    
    // 存储
    Q_INVOKABLE QString getInternalStoragePath();
    Q_INVOKABLE QString getExternalStoragePath();
    Q_INVOKABLE QString getAppDataPath();
    Q_INVOKABLE QString getCachePath();
    Q_INVOKABLE qint64 getAvailableStorage();
    Q_INVOKABLE qint64 getTotalStorage();
    
    // 应用
    Q_INVOKABLE QString getVersionName();
    Q_INVOKABLE int getVersionCode();
    Q_INVOKABLE QString getPackageName();
    Q_INVOKABLE QString getDeviceModel();
    Q_INVOKABLE QString getAndroidVersion();
    Q_INVOKABLE int getSdkInt();
    
    // 网络
    Q_INVOKABLE bool isNetworkAvailable();
    Q_INVOKABLE QString getNetworkType();  // wifi/cellular/none
    
    // 厂商适配
    Q_INVOKABLE QString getManufacturer();  // huawei/xiaomi/oppo/...
    Q_INVOKABLE void openBatteryOptimizationSettings();
    Q_INVOKABLE void openAutoStartSettings();
    
    // 进程
    Q_INVOKABLE void acquireWakeLock();
    Q_INVOKABLE void releaseWakeLock();
    Q_INVOKABLE void startForegroundService(const QString& title, 
                                             const QString& text);
    Q_INVOKABLE void stopForegroundService();
    
signals:
    void permissionGranted(QString permission);
    void permissionDenied(QString permission);
    void batteryLevelChanged(int level);
    void flashlightStateChanged(bool on);
};
```

### 6.2 JNI 对应 Java 方法

| C++ 方法 | Java 方法 | 说明 |
|---|---|---|
| `makePhoneCall` | `MainActivity.makePhoneCall(String)` | ACTION_CALL 或 ACTION_DIAL |
| `sendSMS` | `MainActivity.sendSMS(String, String)` | SmsManager |
| `setFlashlight` | `MainActivity.setFlashlight(boolean)` | Camera2 API |
| `keepScreenOn` | `MainActivity.keepScreenOn(boolean)` | Window flag |
| `getBatteryLevel` | `BatteryManager` | 系统服务 |
| `requestPermission` | `ActivityCompat.requestPermissions` | Android 6+ |
| `getCurrentLocation` | `LocationManager` | GPS |

---

## 七、错误码定义

### 7.1 统一错误码

```cpp
namespace outdoor {

enum class ErrorCode {
    // 通用
    Success = 0,
    Unknown = 1,
    InvalidArgument = 2,
    NotFound = 3,
    PermissionDenied = 4,
    Timeout = 5,
    OutOfMemory = 6,
    IOError = 7,
    NetworkError = 8,
    
    // 数据库
    DatabaseNotOpen = 100,
    DatabaseCorrupted = 101,
    RecordExists = 102,
    RecordNotFound = 103,
    
    // 模型
    ModelNotFound = 200,
    ModelCorrupted = 201,
    ModelLoadFailed = 202,
    
    // 图像
    ImageLoadFailed = 300,
    ImageTooLarge = 301,
    ImageTooSmall = 302,
    ImageFormatUnsupported = 303,
    
    // 识别
    RecognitionFailed = 400,
    LowConfidence = 401,
    
    // 文件
    FileNotFound = 500,
    FileCorrupted = 501,
    FileFormatUnsupported = 502,
    FileTooLarge = 503,
    
    // 平台
    CameraNotAvailable = 600,
    GpsNotAvailable = 601,
    NetworkNotAvailable = 602,
    
    // 内容
    ContentNotFound = 700,
    ContentOutdated = 701,
};

class Error {
public:
    ErrorCode code;
    QString message;
    QString source;        // 错误来源类
    QDateTime timestamp;
    QVariantMap details;   // 附加信息
};

} // namespace outdoor
```

### 7.2 错误处理模式

```cpp
// 1. 返回 Result
auto result = engine_->recognize(image, category);
if (result.status == Status::Failed) {
    // 处理错误
    logError(result.errorMessage);
    return;
}

// 2. 抛出异常（仅在内部使用）
try {
    auto data = database_->query(sql);
} catch (const DatabaseException& e) {
    Logger::error("数据库错误", e);
    return ErrorCode::DatabaseCorrupted;
}

// 3. 错误信号
connect(service, &Service::errorOccurred, [](const Error& err) {
    showErrorDialog(err.message);
});
```

---

## 八、版本兼容

### 8.1 API 版本

```cpp
class ApiVersion {
public:
    static constexpr int MAJOR = 1;
    static constexpr int MINOR = 0;
    static constexpr int PATCH = 0;
    
    static QString getVersion() {
        return QString("%1.%2.%3").arg(MAJOR).arg(MINOR).arg(PATCH);
    }
};
```

### 8.2 兼容性原则

1. **新增字段**：不影响旧代码
2. **新增方法**：不影响旧代码
3. **修改方法签名**：仅在不兼容时
4. **废弃**：标记 `@deprecated`，保留 2 个版本
5. **删除**：仅在 major 版本升级

### 8.3 数据库迁移

```cpp
class DatabaseMigrator {
public:
    bool migrate(int fromVersion, int toVersion) {
        if (fromVersion < 2) {
            // 添加表 / 字段
            addColumn("routes", "tags", "TEXT");
        }
        if (fromVersion < 3) {
            createIndex("idx_routes_province");
        }
        // ...
        return true;
    }
};
```

---

## 附录：完整 API 索引

| 模块 | 类 | 主要功能 |
|---|---|---|
| **核心** | App, Config, Logger, Database | 全局 |
| **识别** | RecognitionEngine, SpeciesInfo, RecognitionHistory | 拍照识别 |
| **急救** | FirstAidService, EmergencyService | 急救决策、SOS |
| **避险** | SurvivalService, KnotService | 取火、庇护所、绳结 |
| **路线** | RouteService, RouteRecommender | 路线管理、推荐 |
| **匹配** | SpeciesRouteMatcher | 物种-路线匹配 |
| **应急** | ChecklistService | 应急储备清单 |
| **导入** | ImportManager | 数据导入 |
| **离线** | OfflineManager | 离线资源 |
| **平台** | AndroidPlatform | Android 桥接 |

---

## 文档维护

- **创建日期**：2026-08-24
- **版本**：v1.1
- **配套文档**：6 份项目级文档 + 1 份澄清文档
- **变更记录**：
  - v1.1 (2026-09-20): Phase 4 命名统一 — `removeContact` → `deleteContact` (EmergencyService), `removeFavorite` → `deleteFavorite` (RouteService/TravelService), `removeItem` → `deleteItem` (ChecklistService), 新增 `ChecklistService::getById` (rename from `getChecklist`)。详细对照表见 `doc/05-工程规范/命名规范.md` v0.2。
- **下次更新**：Phase 5 后追加 Result<T> 返回值规范
