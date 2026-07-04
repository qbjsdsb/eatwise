package com.eatwise.eatwise

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.eatwise.eatwise/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "triggerInstall" -> {
                        // 兼容两种传参方式：位置参数（String）或 named argument
                        val apkPath = call.argument<String>(0) ?: call.arguments as? String
                        if (apkPath == null) {
                            result.error("INVALID_ARGS", "缺少 apkPath 参数", null)
                            return@setMethodCallHandler
                        }
                        triggerInstall(apkPath, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 触发系统包安装器安装指定路径的 APK。
    /// Android 7+ 必须用 FileProvider 共享 file:// URI（已在 AndroidManifest 注册）
    private fun triggerInstall(
        apkPath: String,
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        try {
            val file = File(apkPath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK 文件不存在：$apkPath", null)
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", "触发安装器失败：${e.message}", null)
        }
    }
}
