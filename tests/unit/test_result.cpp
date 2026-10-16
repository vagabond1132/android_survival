/**
 * @file test_result.cpp
 * @brief Result<T> + QmlResultBridge 单元测试 (5 阶段架构重构 Phase 2)
 *
 * 覆盖:
 *   - Ok / Err 工厂 + isOk/isErr
 *   - operator* / operator->
 *   - QmlResultBridge toQVariant / ok / isOk / errorMessage
 */
#include <QtTest>

#include "src/core/Result.h"
#include "src/core/ServiceErrors.h"
#include "src/core/internal/QmlResultBridge.h"

using namespace outdoor;
using namespace outdoor::internal;  // 2026-09-21: QmlResultBridge 改 namespace + free function

class TestResult : public QObject {
    Q_OBJECT

private slots:
    // ===== Ok =====
    void test_ok_with_value() {
        auto r = Ok(QString("hello"));
        QVERIFY(r.isOk());
        QVERIFY(!r.isErr());
        QCOMPARE(*r, QString("hello"));
    }

    void test_ok_int_value() {
        auto r = Ok(42);
        QVERIFY(r.isOk());
        QCOMPARE(*r, 42);
    }

    // ===== Err =====
    void test_err_with_code() {
        auto r = Err<QString>(ServiceErrorCode::InvalidArgument,
                              "id empty", "test_method");
        QVERIFY(r.isErr());
        QVERIFY(!r.isOk());
        QCOMPARE(r.error.code, ServiceErrorCode::InvalidArgument);
        QCOMPARE(r.error.message, QString("id empty"));
        QCOMPARE(r.error.context, QString("test_method"));
    }

    void test_err_void() {
        auto r = Err(ServiceErrorCode::DbError, "db closed", "test");
        QVERIFY(r.isErr());
        QVERIFY(r.error.code == ServiceErrorCode::DbError);
    }

    // ===== ResultVoid =====
    void test_ok_void() {
        ResultVoid r = Ok();
        QVERIFY(r.isOk());
    }

    // ===== operator* / operator-> =====
    void test_arrow_operator_on_struct() {
        struct Point { int x, y; };
        auto r = Ok(Point{3, 4});
        QVERIFY(r.isOk());
        QCOMPARE(r->x, 3);
        QCOMPARE(r->y, 4);
    }

    // ===== QmlResultBridge (2026-09-21 改 namespace, 不再需要 QmlResultBridge:: 前缀) =====
    void test_bridge_toQVariant_ok_value() {
        auto r = Ok(QString("track_123"));
        QVariantMap m = toQVariant(r);
        QCOMPARE(m.value("ok").toBool(), true);
        QCOMPARE(m.value("value").toString(), QString("track_123"));
    }

    void test_bridge_toQVariant_err() {
        auto r = Err<QString>(ServiceErrorCode::IoError,
                              "file not found", "saveRoute");
        QVariantMap m = toQVariant(r);
        QCOMPARE(m.value("ok").toBool(), false);
        QCOMPARE(errorMessage(m), QString("file not found"));
    }

    void test_bridge_toQVariant_void_err() {
        auto r = Err(ServiceErrorCode::DbError, "db closed", "saveRoute");
        QVariantMap m = toQVariant(r);
        QCOMPARE(m.value("ok").toBool(), false);
    }

    void test_bridge_ok_helper() {
        QVariantMap m = ok(123);
        QCOMPARE(m.value("ok").toBool(), true);
        QCOMPARE(m.value("value").toInt(), 123);
    }

    void test_bridge_toQVariant_service_error() {
        ServiceError err;
        err.code = ServiceErrorCode::NotFound;
        err.message = "no such route";
        err.context = "getById";
        QVariantMap m = toQVariant(err);
        QCOMPARE(m.value("ok").toBool(), false);
        QCOMPARE(errorMessage(m), QString("no such route"));
    }

    void test_bridge_isOk() {
        QVariantMap okMap = ok(QString("x"));
        QVariantMap errMap = toQVariant(
            Err<QString>(ServiceErrorCode::InternalError, "boom", "test"));
        QVERIFY(isOk(okMap));
        QVERIFY(!isOk(errMap));
    }

    // ===== ServiceError 自身 =====
    void test_service_error_toString() {
        ServiceError err;
        err.code = ServiceErrorCode::DbError;
        err.message = "constraint failed";
        err.context = "saveRoute";
        QString s = err.toString();
        QVERIFY(s.contains("DbError"));
        QVERIFY(s.contains("constraint failed"));
        QVERIFY(s.contains("saveRoute"));
    }

    void test_service_error_code_to_string() {
        QCOMPARE(ServiceError::codeToString(ServiceErrorCode::Ok), QString("Ok"));
        QCOMPARE(ServiceError::codeToString(ServiceErrorCode::NotFound), QString("NotFound"));
        QCOMPARE(ServiceError::codeToString(ServiceErrorCode::PermissionDenied),
                 QString("PermissionDenied"));
    }
};

QTEST_MAIN(TestResult)
#include "test_result.moc"