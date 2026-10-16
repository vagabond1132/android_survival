/**
 * @file PhotoCaptureActivity.java
 * @brief 拍照独立壳 Activity (不继承 QtActivity, 不影响 Qt 启动)
 *
 * 流程:
 *   1. onCreate 拉起 Intent.ACTION_IMAGE_CAPTURE, 输出到 FileProvider URI (cacheDir/capture.jpg)
 *   2. 拍完系统相机调 setResult + finish, 本 Activity 收到 RESULT_OK
 *   3. 通过 JNI 调 PhotoCaptureContract.notifyResult(file:// URI) 回灌到 C++ 端
 *
 * 2026-09-11: 新建 (Map 主页改版 P1, 3.26 拍照存图+GPS)
 */
package com.outdoor.survival;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.Log;

import androidx.core.content.FileProvider;

import java.io.File;

public class PhotoCaptureActivity extends Activity {
    private static final String TAG = "PhotoCapture";

    private static final int REQUEST_CAPTURE = 0xC41711;

    private Uri mOutputUri;
    private File mOutputFile;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 输出到 cacheDir/capture.jpg (每次覆盖)
        mOutputFile = new File(getCacheDir(), "capture.jpg");
        try {
            if (mOutputFile.exists()) mOutputFile.delete();
            mOutputFile.createNewFile();
        } catch (Exception e) {
            Log.e(TAG, "createNewFile failed: " + e.getMessage());
        }

        mOutputUri = FileProvider.getUriForFile(
            this,
            getPackageName() + ".fileprovider",
            mOutputFile
        );

        Intent takePicture = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        takePicture.putExtra(MediaStore.EXTRA_OUTPUT, mOutputUri);
        takePicture.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);

        try {
            startActivityForResult(takePicture, REQUEST_CAPTURE);
        } catch (Exception e) {
            Log.e(TAG, "startActivityForResult failed: " + e.getMessage());
            // 无相机应用, 直接 fail
            PhotoCaptureContract.notifyResult(null);
            finish();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_CAPTURE) {
            finish();
            return;
        }

        if (resultCode == Activity.RESULT_OK && mOutputFile != null && mOutputFile.exists() && mOutputFile.length() > 0) {
            // 成功: 通知 C++ 端
            String uriStr = "file://" + mOutputFile.getAbsolutePath();
            Log.i(TAG, "capture success: " + uriStr + " size=" + mOutputFile.length());
            PhotoCaptureContract.notifyResult(uriStr);
        } else {
            // 取消或失败
            Log.w(TAG, "capture cancelled or failed, resultCode=" + resultCode);
            PhotoCaptureContract.notifyResult(null);
        }
        finish();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 兜底: 若 startActivityForResult 之后用户没回到本 Activity (例如系统相机崩溃),
        // 这里 1.5s 后还没收到 result 主动 fail
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (!isFinishing()) {
                Log.w(TAG, "no result after 1.5s, fail");
                PhotoCaptureContract.notifyResult(null);
                finish();
            }
        }, 1500);
    }
}
