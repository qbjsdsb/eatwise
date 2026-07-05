# M23 维度 4：安全审查

## 审查方法
grep 敏感关键词（SecureConfigStore.instance / http:// / TrustManager / customSelect / print / Sentry / apiKey）+ 读关键文件（secure_config_store / sentry_scrub / sentry_init / AndroidManifest / build.gradle.kts / AI providers / json_exporter / json_importer / auto_backup / apk_downloader / pubspec.lock）+ 对照 Android 权限声明 + 验证 6 条硬约束中安全相关的 3 条（1/5/6）。

## 硬约束验证（安全相关）

| 硬约束 | 验证位置 | 结论 |
|--------|----------|------|
| 1. `android/app/build.gradle.kts` 保持 `isMinifyEnabled=false` + `isShrinkResources=false` | [build.gradle.kts:62-63](file:///workspace/android/app/build.gradle.kts#L62) | ✅ 满足 |
| 5. `SecureConfigStore` 无 `instance` 静态属性 | grep `SecureConfigStore.instance` 全 lib 无匹配 | ✅ 满足 |
| 6. `initSentryAndRunApp` 参数是命名参数 `container:` + `app:` | [sentry_init.dart:15-18](file:///workspace/lib/core/error/sentry_init.dart#L15) 声明 + [main.dart:69-74](file:///workspace/lib/main.dart#L69) 调用 | ✅ 满足 |

**3 条硬约束全部满足，无 P0 违反。**

## 发现清单

### 4.1 密钥存储（SecureConfigStore）

- 无 P0/P1 发现。
- ✅ [secure_config_store.dart:14-34](file:///workspace/lib/core/config/secure_config_store.dart#L14) 类定义为普通 class，无 `static SecureConfigStore get instance` 单例；构造函数配置 `iOptions: IOSOptions(first_unlock_this_device, synchronizable: false)` 防止 iCloud 备份泄露，Android 默认 RSA OAEP + AES-GCM，符合最佳实践。
- ✅ 所有调用点均使用 `SecureConfigStore()` 构造函数或 `container.read(secureConfigStoreProvider)`（[app_config.dart:81-82](file:///workspace/lib/core/config/app_config.dart#L81)、[background_dispatcher.dart:43,67](file:///workspace/lib/background/background_dispatcher.dart#L67)、[offline_queue_controller.dart:47,505](file:///workspace/lib/features/offline/offline_queue_controller.dart#L505)），无任何 `SecureConfigStore.instance` 误用。
- ✅ 全 lib grep `apiKey` 无硬编码：key 全程通过 SecureConfigStore → AppConfig → Provider 构造函数注入（[qwen_vl_provider.dart:22-31](file:///workspace/lib/ai/qwen_vl_provider.dart#L22)、[glm_flash_provider.dart:11-18](file:///workspace/lib/ai/glm_flash_provider.dart#L11)、[glm_4v_provider.dart:14-23](file:///workspace/lib/ai/glm_4v_provider.dart#L14)）。
- [P2] [app_config.dart:53-62](file:///workspace/lib/core/config/app_config.dart#L53) `String.fromEnvironment('QWEN_API_KEY'/'GLM_API_KEY'/'SENTRY_DSN')` 作为 secure_storage 为空时的 fallback
  - 现状：若用户用 `--dart-define=QWEN_API_KEY=xxx` 启动，key 会被编译进 APK 的 Dart snapshot，可被 `strings` / 逆向工具提取。
  - 影响：个人自用 app 风险低，但若用户误用此方式分发 APK 会泄露 key。
  - 建议：保留 fallback 兼容性但加 release 模式警告日志（kReleaseMode && dart-define 值非空 → 提示风险）；或在文档明确"仅 dev 环境用 dart-define"。
  - 工作量：30 分钟

### 4.2 Sentry 脱敏

- [P1] [sentry_scrub.dart:9-25](file:///workspace/lib/core/error/sentry_scrub.dart#L9) 文件头注释承诺"遍历 event.extra / event.tags，key 或 value 含敏感词的删除"，但实际代码（第 19-25 行）只处理了 `event.extra`，**未处理 `event.tags`**
  - 现状：`scrubBeforeSend` 处理了 server_name / extra / exceptions / breadcrumbs / message / request，唯独漏掉 `event.tags`。Sentry SDK 在 native 崩溃 / ANR / 自动面包屑场景下会自动填充 tags（device_id / os_version / build_id 等）。
  - 影响：当前项目未主动调用 `Sentry.setTag(...)`（grep 确认无 setTag 调用），所以实际泄露面有限；但注释与实现不一致，未来若开发者按注释假设信任"tags 已脱敏"而添加 setTag 调用，会直接泄露敏感字段。
  - 建议修复：在 `scrubBeforeSend` 第 25 行后补一段 tags 脱敏（与 extra 同模式），或修正注释删除"event.tags"承诺。
  - 工作量：15 分钟
- ✅ [sentry_scrub.dart:67-75](file:///workspace/lib/core/config/secure_config_store.dart#L67) `_isSensitiveKey` 覆盖食物 / 份量 / 体重 / 热量 / api_key / token / secret / password / dsn / image_path 等关键词，覆盖面充分。
- ✅ [sentry_scrub.dart:83-87](file:///workspace/lib/core/error/sentry_scrub.dart#L83) `_scrubString` 用正则替换文件路径（.jpg/.png/.webp）、32+ 位 hex（SHA256/UUID/JWT 签名）、`sk-` 开头 API key，正则策略合理。
- ✅ [sentry_scrub.dart:61](file:///workspace/lib/core/error/sentry_scrub.dart#L61) `event.request = null` 直接丢弃整个 HTTP request（url/headers/cookies/body），最安全策略。
- ✅ [sentry_init.dart:41-51](file:///workspace/lib/core/error/sentry_init.dart#L41) `beforeSend = scrubBeforeSend` 已注册，所有 captureException 事件都会经脱敏钩子。
- [P2] [sentry_scrub.dart](file:///workspace/lib/core/error/sentry_scrub.dart) 未处理 `event.modules` / `event.threads`（崩溃线程局部变量）
  - 现状：当前项目用纯 Dart，无 native 崩溃捕获需求，影响小。
  - 建议：若未来接入 sentry-native 补 native 崩溃捕获，需补这两个字段脱敏。
  - 工作量：10 分钟

### 4.3 AndroidManifest 权限

| 权限 | 必要性 | 评估 |
|------|--------|------|
| `android.permission.INTERNET` | 必要 | AI API 调用（Qwen-VL / GLM-4V / GLM-4-Flash）+ connectivity_plus 网络检测 + GitHub Releases 更新检查 + OFF 云查兜底，核心功能依赖 |
| `android.permission.ACCESS_NETWORK_STATE` | 必要 | connectivity_plus 检测 wifi/移动网络，离线队列触发回补必需 |
| `android.permission.READ_MEDIA_IMAGES` | 必要 | Android 13+ 细粒度照片访问，用户从相册选图识别食物必需 |
| `android.permission.CAMERA` | 必要 | 拍照识别食物核心功能 |
| `android.permission.READ_EXTERNAL_STORAGE` (maxSdkVersion=32) | 必要 | Android 12 及以下兼容（READ_MEDIA_IMAGES 在 13+ 才有），已用 maxSdkVersion 限定范围，符合最小必要原则 |
| `android.permission.REQUEST_INSTALL_PACKAGES` | 必要但高风险 | M16 应用内更新功能必需（调起系统包安装器安装下载的 APK）。属高风险权限：若 APK 下载源被劫持可安装恶意 APK。缓解因素：(1) 下载源固定 GitHub Releases HTTPS；(2) Android 系统包安装器会校验 APK 签名，签名不一致弹窗拒绝；(3) keystore 文件不进 repo（[build.gradle.kts:34-49](file:///workspace/android/app/build.gradle.kts#L34)） |

- ✅ [AndroidManifest.xml:18](file:///workspace/android/app/src/main/AndroidManifest.xml#L18) `android:allowBackup="false"` 正确关闭，防止 ADB 备份泄露 app 数据。
- [P2] [AndroidManifest.xml](file:///workspace/android/app/src/main/AndroidManifest.xml) 缺少 `<uses-feature android:name="android.hardware.camera" android:required="false"/>` 声明
  - 现状：仅声明 CAMERA 权限，未声明 camera feature。
  - 影响：本项目 `publish_to: 'none'` 不上架 Google Play，影响可忽略；但若日后上架，无相机设备会被 Play 过滤掉。
  - 建议：补 `<uses-feature android:name="android.hardware.camera" android:required="false"/>`（允许无相机设备安装，拍照按钮按需禁用）。
  - 工作量：5 分钟
- [P2] [AndroidManifest.xml](file:///workspace/android/app/src/main/AndroidManifest.xml) 缺少 `android:debuggable="false"` 显式声明 + 缺少 `android:networkSecurityConfig` 引用
  - 现状：依赖 AGP release 构建默认 `debuggable=false`；Android 9+ 默认禁明文流量，故无 network_security_config 也可。
  - 影响：当前安全，但显式声明更稳妥（防未来构建配置变更）。
  - 建议：在 `<application>` 加 `android:debuggable="false"` + `android:networkSecurityConfig="@xml/network_security_config"`，并在 res/xml/ 加一份只允许 HTTPS 的配置。
  - 工作量：20 分钟

### 4.4 网络层

- ✅ grep `http://` 全 lib 无匹配，所有外部请求默认 HTTPS。
- ✅ grep `TrustManager|X509|badCertificateCallback|allowAllSSL|onBadCertificate` 全 lib 无匹配，无证书校验绕过代码。
- ✅ [qwen_vl_provider.dart:26-31](file:///workspace/lib/ai/qwen_vl_provider.dart#L26) / [glm_4v_provider.dart:18-23](file:///workspace/lib/ai/glm_4v_provider.dart#L18) / [glm_flash_provider.dart:13-18](file:///workspace/lib/ai/glm_flash_provider.dart#L13) 用 openai_dart 7.0 的 `OpenAIClient`（内部用 dio/http，默认系统证书校验），未注入自定义 httpClient 绕过校验。
- ✅ [background_dispatcher.dart:80,90](file:///workspace/lib/background/background_dispatcher.dart#L80) 后台 isolate 默认 baseUrl 用 `https://dashscope.aliyuncs.com/compatible-mode/v1` 和 `https://open.bigmodel.cn/api/paas/v4`，HTTPS。
- ✅ [github_release_client.dart:31-32](file:///workspace/lib/core/update/github_release_client.dart#L31) GitHub API URL 固定 `https://api.github.com/...`，HTTPS。
- [P2] [settings_page.dart:140-148,159-167](file:///workspace/lib/features/settings/settings_page.dart#L140) Base URL 输入框（Qwen / GLM）无 https 校验
  - 现状：用户可在设置页填任意 URL，包括 `http://...`。若误填 http，所有 API 请求（含 API key header）会明文传输。
  - 影响：用户配置错误导致 API key 在网络中明文暴露，可被中间人嗅探。
  - 建议：保存时校验 URL scheme == 'https'，非 https 弹警告确认框；或在输入框加 `prefixIcon: Icon(Icons.https)` 提示。
  - 工作量：30 分钟
- [P2] [apk_downloader.dart:39-47](file:///workspace/lib/core/update/apk_downloader.dart#L39) `download(url:)` 接受任意 url 参数，未校验 scheme
  - 现状：URL 来自 [github_release_client.dart:99](file:///workspace/lib/core/update/github_release_client.dart#L99) 的 `browser_download_url`（GitHub 默认 HTTPS），但代码层无强制 https 校验。
  - 影响：若未来 GitHub release assets URL 被篡改为 http（理论极低概率），APK 下载可被中间人替换。
  - 建议：在 download() 入口加 `if (!url.startsWith('https://')) throw ApkDownloadException('仅支持 HTTPS 下载源')`。
  - 工作量：5 分钟

### 4.5 SQL 注入

- ✅ grep `customSelect|rawQuery|executeQuery|rawInsert|rawUpdate|rawDelete` 仅 3 处 customSelect，无 rawQuery 等危险 API。
- ✅ grep `SELECT.*\$|INSERT.*\$|WHERE.*\$|VALUES.*\$` 全 lib 无 SQL 字符串拼接。
- ✅ [meal_log_repository.dart:201-208](file:///workspace/lib/data/repositories/meal_log_repository.dart#L201) customSelect 用 `?` 占位符 + `variables: [Variable.withString(startDate), Variable.withString(endDate)]`，参数化查询。
- ✅ [meal_log_repository.dart:230-237](file:///workspace/lib/data/repositories/meal_log_repository.dart#L230) 同上，参数化。
- ✅ [food_item_repository.dart:412-417](file:///workspace/lib/data/repositories/food_item_repository.dart#L412) customSelect 无 variables，但 SQL 为静态字符串 `'SELECT food_item_id, COUNT(id) AS cnt FROM meal_logs GROUP BY food_item_id'`，无外部输入，安全。
- ✅ [json_importer.dart:37-44](file:///workspace/lib/data/backup/json_importer.dart#L37) 8 条 `customStatement('DELETE FROM xxx;')` 为静态字符串，无外部输入拼接，安全。
- 无发现 SQL 注入风险。

### 4.6 备份文件安全

- ✅ [json_exporter.dart:14-39](file:///workspace/lib/data/backup/json_exporter.dart#L14) 导出列表不含 API key / sentry_dsn / 用户图片 base64（仅 thumbnailPath / originalImagePath 字符串路径，非图片本身）。
- ✅ [json_importer.dart:25-28](file:///workspace/lib/data/backup/json_importer.dart#L25) 导入前校验 schemaVersion（仅拒绝高于当前的版本，向后兼容）。
- ✅ [json_importer.dart:33-104](file:///workspace/lib/data/backup/json_importer.dart#L33) 整个导入过程用 `_db.transaction(() async { ... })` 包裹，DELETE + INSERT 原子化，中途失败自动回滚避免半库状态。
- ✅ [json_importer.dart:121-153](file:///workspace/lib/data/backup/json_importer.dart#L121) 导入后检测 meal_log.original_image_path 与 food_item.thumbnail_path 文件是否存在，不存在则置空（换机场景图片路径失效的正确处理）。
- ✅ [json_importer.dart:267-273](file:///workspace/lib/data/backup/json_importer.dart#L267) `_asInt` 对 null / 非 num 类型抛 ArgumentError，给清晰错误信息。
- [P2] [json_exporter.dart:48-69](file:///workspace/lib/data/backup/json_exporter.dart#L48) 导出 JSON 含 profile 健康隐私数据（bodyFatPct / age / gender / healthCondition / dietPreference / specialCondition）+ meal_log 饮食记录（食物名 + 份量 + 热量 + 图片路径），明文未加密
  - 现状：[auto_backup.dart:14-38](file:///workspace/lib/data/backup/auto_backup.dart#L14) 自动备份文件保存到应用沙箱目录 `${applicationDocumentsDirectory}/backups/eatwise_backup_YYYYMMDD.json`，外部应用无法访问；`allowBackup="false"` 防 ADB 备份。
  - 影响：root 设备或物理获取手机的攻击者可读取明文健康隐私数据；用户主动导出分享时无加密保护。
  - 建议：导出/自动备份支持可选密码加密（AES-GCM 包装），或至少在导出文件头加 "本文件含健康隐私数据，请妥善保管" 提示。
  - 工作量：2 小时（加密方案）
- [P2] [json_importer.dart:14-117](file:///workspace/lib/data/backup/json_importer.dart#L14) 导入缺少文件大小限制 / 字段数量限制 / 数值范围校验
  - 现状：`importFromString(jsonStr)` 直接 `jsonDecode(jsonStr)`，无大小上限；`for (final p in (tables['profiles'] as List))` 循环插入无数量上限；`_asDouble(j['weightKg'])` 无范围校验（恶意填 -1000 或 1e308）。
  - 影响：恶意构造的超大 JSON（如百万条 meal_log）可致 OOM 或导入耗时数小时；恶意数值可污染统计。
  - 建议：(1) 导入前校验文件大小 ≤ 50MB；(2) 每表条数 ≤ 100000；(3) 数值字段加范围校验（weightKg ∈ [20, 500]、calories ∈ [0, 100000]）。
  - 工作量：1.5 小时
- [P2] [json_importer.dart:33-44](file:///workspace/lib/data/backup/json_importer.dart#L33) 导入前未自动备份当前数据
  - 现状：导入会先 DELETE 8 表再 INSERT 新数据。虽有 transaction 回滚保护，但若用户误导入错误文件后想恢复，无自动备份可回退。
  - 影响：用户误操作致数据丢失风险（transaction 内失败可回滚，但 transaction 成功后想撤销无备份）。
  - 建议：导入前自动调 `AutoBackup.run(db)` 生成一份 pre_import_backup_YYYYMMDD.json，保留 7 天后清理。
  - 工作量：30 分钟

### 4.7 日志脱敏

| 文件:行 | print 内容 | 风险评估 |
|---------|-----------|----------|
| [main.dart:83](file:///workspace/lib/main.dart#L83) | `debugPrint('appConfig 加载失败：$e')` | 低：$e 是 secure_storage / AppConfig.load() 抛的异常描述，不含 key 值本身（key 在 load() 内部局部变量） |
| [main.dart:95](file:///workspace/lib/main.dart#L95) | `debugPrint('Workmanager 失败：$e')` | 低：Workmanager 初始化异常，不含敏感数据 |
| [main.dart:104](file:///workspace/lib/main.dart#L104) | `debugPrint('OfflineQueue 失败：$e')` | 低：OfflineQueueController.start() 异常，可能含 pending_recognition 的 foodName（用户隐私），但 debugPrint release 模式被 Flutter 自动裁掉 |
| [main.dart:115](file:///workspace/lib/main.dart#L115) | `debugPrint('ImageCleanup 失败：$e')` | 低：图片清理异常，不含敏感数据 |
| [main.dart:118](file:///workspace/lib/main.dart#L118) | `debugPrint('ImageCleanup 初始化失败：$e')` | 低：同上 |
| [main.dart:125](file:///workspace/lib/main.dart#L125) | `debugPrint('Zone 未捕获错误: $error')` | 中：$error 是任意未捕获异常，理论可能含 API key（若某处异常消息拼接了 key），但实际罕见；release 模式裁掉 |
| [sentry_init.dart:23](file:///workspace/lib/core/error/sentry_init.dart#L23) | `debugPrint('appConfig 加载失败，跳过 Sentry：$e')` | 低：同 main.dart:83 |
| [sentry_init.dart:29](file:///workspace/lib/core/error/sentry_init.dart#L29) | `debugPrint('Sentry 未启用：dsn 空=${dsn.isEmpty}, enabled=${config.sentryEnabled}')` | 低：只打印 isEmpty bool 和 enabled bool，不打印 dsn 值，安全 |
| [sentry_init.dart:53](file:///workspace/lib/core/error/sentry_init.dart#L53) | `debugPrint('SentryFlutter.init 失败，跳过 Sentry：$e\n$st')` | 低：Sentry SDK 初始化异常，不含 dsn 值 |
| [recognition_post_processor.dart:143](file:///workspace/lib/core/util/recognition_post_processor.dart#L143) | `debugPrint('[DensityConversion] ${r.dishName}(${r.foodCategory}) perUnitG: ...')` | 中：含食物名 + 食物类别（用户隐私），但 debugPrint release 裁掉 |
| [recognition_post_processor.dart:175](file:///workspace/lib/core/util/recognition_post_processor.dart#L175) | `debugPrint('[RecognitionValidator] 附加菜「${dish.dishName}」校验: ${v.reasons}')` | 中：含附加菜食物名，同上 |
| [recognize_controller.dart:487](file:///workspace/lib/features/recognize/recognize_controller.dart#L487) | `debugPrint('[RecognitionValidator] 主菜校验: ${validation.reasons}')` | 中：reasons 可能含食物名，同上 |
| [recognize_controller.dart:497](file:///workspace/lib/features/recognize/recognize_controller.dart#L497) | `debugPrint('[RecognitionValidator] 重试后校验: ${retryValidation.reasons}')` | 中：同上 |
| [recognize_controller.dart:505](file:///workspace/lib/features/recognize/recognize_controller.dart#L505) | `debugPrint('[RecognitionValidator] 重试异常，用原结果: $e')` | 低：异常描述，可能含食物名 |
| [recognize_page.dart:95](file:///workspace/lib/features/recognize/recognize_page.dart#L95) | `debugPrint('[FoodCategoryDefaults] ${result.dishName}(${result.foodCategory}) AI per100g=...')` | 中：含食物名 + 类别，release 裁掉 |
| [recognize_page.dart:100](file:///workspace/lib/features/recognize/recognize_page.dart#L100) | `debugPrint('[PackageOCR] ${result.dishName} 使用包装营养表换算 ...')` | 中：含食物名，release 裁掉 |
| [background_dispatcher.dart:27](file:///workspace/lib/background/background_dispatcher.dart#L27) | `debugPrint('后台任务执行: $task')` | 低：任务名（offlineBackfill/autoBackup/imageCleanup），非敏感 |
| [background_dispatcher.dart:49](file:///workspace/lib/background/background_dispatcher.dart#L49) | `debugPrint('未知后台任务: $task')` | 低：任务名 |
| [background_dispatcher.dart:54](file:///workspace/lib/background/background_dispatcher.dart#L54) | `debugPrint('后台任务失败: $e\n$st')` | 中：后台异常可能含食物名，release 裁掉 |
| [background_dispatcher.dart:72](file:///workspace/lib/background/background_dispatcher.dart#L72) | `debugPrint('后台回补跳过：未配置 Qwen API key')` | 低：仅提示未配置，不含 key 值 |
| [background_tasks.dart:44](file:///workspace/lib/background/background_tasks.dart#L44) | `debugPrint('workmanager 周期任务已注册')` | 低：无敏感数据 |
| [ai_recommendation_service.dart:128](file:///workspace/lib/nutrition/ai_recommendation_service.dart#L128) | `debugPrint('AI 推荐失败（v4 兜底）：$e')` | 中：异常可能含食物名，release 裁掉 |
| [ai_recommendation_service.dart:283](file:///workspace/lib/nutrition/ai_recommendation_service.dart#L283) | `debugPrint('AI 调用失败，1s 后重试：$e')` | 中：同上 |
| [dashboard_page.dart:149](file:///workspace/lib/features/dashboard/dashboard_page.dart#L149) | `debugPrint('AI 推荐加载异常（v4 兜底）：$e')` | 中：同上 |
| [dashboard_page.dart:202](file:///workspace/lib/features/dashboard/dashboard_page.dart#L202) | `debugPrint('反馈写入失败：$e')` | 低：DB 写入异常 |
| [dashboard_page.dart:606](file:///workspace/lib/features/dashboard/dashboard_page.dart#L606) | `debugPrint('v4 推荐加载失败：${snap.error}')` | 中：同上 |
| [offline_queue_controller.dart:461](file:///workspace/lib/features/offline/offline_queue_controller.dart#L461) | `debugPrint('M11 incrementMonthlyCount 失败（不影响回补）：$e')` | 低：secure_storage 写入异常 |

- ✅ 全 lib 无 `print(` 直接调用，全部用 `debugPrint(`（Flutter 框架在 release 模式自动忽略 debugPrint 输出，不进日志cat / logcat）。
- ✅ 无一处 debugPrint 直接打印 API key / token / sentry_dsn 的值（grep 确认 `apiKey` / `dsn` 变量未出现在 debugPrint 参数中，仅打印 isEmpty bool 或异常对象 $e）。
- [P2] [main.dart:25-34](file:///workspace/lib/main.dart#L25) `_writeBootLog` 写启动期异常到 `boot_log.txt`
  - 现状：写入 `${applicationDocumentsDirectory}/boot_log.txt`，内容含 `exception + stack`，理论上若异常消息拼接了 key 值会落盘。
  - 影响：boot_log.txt 在应用沙箱目录，外部应用无法访问；root 设备可读取。实际异常消息一般不含 key 值。
  - 建议：boot_log.txt 写入前用 sentry_scrub._scrubString 同款正则脱敏；或限制 boot_log.txt 最大 100KB 滚动覆盖。
  - 工作量：20 分钟
- [P2] 多处 debugPrint 打印食物名 / 食物类别（用户隐私数据）
  - 现状：recognition_post_processor / recognize_controller / recognize_page / ai_recommendation_service / dashboard_page / background_dispatcher 等共 10+ 处打印 `dishName` / `foodCategory` / `validation.reasons`。
  - 影响：debugPrint 在 release 模式被 Flutter 框架自动裁掉（不输出到 logcat），实际不泄露；但 dev 模式 logcat 可见，若开发者截图分享日志可能泄露用户饮食记录。
  - 建议：保持现状（dev 调试需要），但文档化"分享 dev 日志前手动脱敏食物名"规范。
  - 工作量：0（文档规范）

### 4.8 第三方依赖

| 依赖 | yaml 声明 | lock 锁定 | 锁定方式 | CVE 风险 |
|------|-----------|-----------|----------|----------|
| drift | ^2.34.0 | 2.34.0 | sha256 + 版本 | 无已知 CVE |
| sqlite3 | ^3.3.2 | 3.3.4 | sha256 + 版本 | 无已知 CVE |
| flutter_secure_storage | ^10.3.1 | 10.3.1 | sha256 + 版本 | 无已知 CVE |
| flutter_riverpod | ^3.3.1 | 3.3.2 | sha256 + 版本 | 无已知 CVE |
| go_router | ^17.2.0 | 17.3.0 | sha256 + 版本 | 无已知 CVE |
| openai_dart | ^7.0.0 | 7.0.0 | sha256 + 版本 | 无已知 CVE |
| http | ^1.2.0 | 1.6.0 | sha256 + 版本 | 无已知 CVE |
| sentry_flutter | ^9.22.0 | 9.23.0 | sha256 + 版本 | 无已知 CVE |
| workmanager | ^0.9.0 | 0.9.0+3 | sha256 + 版本 | 无已知 CVE |
| image_picker | ^1.2.2 | 1.2.3 | sha256 + 版本 | 无已知 CVE |
| flutter_image_compress | ^2.4.0 | 2.4.0 | sha256 + 版本 | 无已知 CVE |
| connectivity_plus | ^6.1.0 | 6.1.5 | sha256 + 版本 | 无已知 CVE |
| package_info_plus | ^8.0.0 | 8.3.1 | sha256 + 版本 | 无已知 CVE |
| fl_chart | ^0.70.0 | 0.70.2 | sha256 + 版本 | 无已知 CVE |
| path_provider | ^2.1.0 | 2.1.6 | sha256 + 版本 | 无已知 CVE |
| uuid | ^4.5.0 | 4.5.3 | sha256 + 版本 | 无已知 CVE |
| image | ^4.5.3 | 4.9.1 | sha256 + 版本 | 无已知 CVE |
| mocktail (dev) | ^1.0.0 | 1.0.5 | sha256 + 版本 | 无已知 CVE |
| drift_dev (dev) | ^2.34.0 | 2.34.0 | sha256 + 版本 | 无已知 CVE |
| build_runner (dev) | ^2.15.0 | 2.15.0 | sha256 + 版本 | 无已知 CVE |
| flutter_lints (dev) | ^5.0.0 | 5.0.0 | sha256 + 版本 | 无已知 CVE |

- ✅ [pubspec.lock](file:///workspace/pubspec.lock) 存在且所有依赖锁定具体版本 + sha256 哈希校验，`pub get` 会校验完整性，防供应链篡改。
- ✅ 关键依赖（drift / flutter_riverpod / sentry_flutter / http / openai_dart / flutter_secure_storage / workmanager）版本均为 2025 年较新稳定版，截至知识截止日期无已知 CVE。
- [P2] [pubspec.yaml:23](file:///workspace/pubspec.yaml#L23) 注释 "flutter_riverpod 3.3.2 仅为 3.3.2-dev.2 prerelease，最新稳定版是 3.3.1" 过时
  - 现状：lock 文件实际锁定 3.3.2（[pubspec.lock:400](file:///workspace/pubspec.lock#L400)），3.3.2 已是 stable 版本。
  - 影响：注释与实际不符，误导后续维护者。
  - 建议：删除或更新注释为 "3.3.2 stable，lock 已锁定"。
  - 工作量：2 分钟
- [P2] [pubspec.yaml](file:///workspace/pubspec.yaml) 所有依赖用 `^x.x.x` 宽松版本约束
  - 现状：`^x.x.x` 允许同 major 内任意 minor/patch 升级，`pub get` 会取最新符合版本。
  - 影响：依赖 lock 文件保护，CI/构建可重现；但开发者手动 `pub upgrade` 时可能引入不兼容变更。
  - 建议：保持现状（Flutter 生态惯例），但 CI 加 `pub upgrade --no-major-versions` 校验或定期 `pub outdated` 审查。
  - 工作量：0（流程规范）

## 维度 4 汇总

- **P0: 0 项**
- **P1: 1 项**
  - sentry_scrub.dart 注释承诺脱敏 event.tags 但实际未处理（代码-注释不一致，潜在脱敏盲区）
- **P2: 11 项**
  - AppConfig.load() 用 String.fromEnvironment 作 fallback（dart-define key 进 APK）
  - sentry_scrub.dart 未处理 event.modules / event.threads
  - AndroidManifest 缺 `<uses-feature android.hardware.camera>` 声明
  - AndroidManifest 缺 `android:debuggable="false"` 显式声明 + networkSecurityConfig
  - settings_page.dart Base URL 输入框无 https 校验
  - apk_downloader.dart download(url:) 未校验 scheme == https
  - json_exporter 导出 JSON 明文未加密（含健康隐私数据）
  - json_importer 导入缺少文件大小 / 字段数量 / 数值范围校验
  - json_importer 导入前未自动备份当前数据
  - boot_log.txt 写入未脱敏
  - pubspec.yaml flutter_riverpod 注释过时

- **整体评价**：
  EatWise 在密钥存储（SecureConfigStore 设计规范，无 instance 静态属性误用）、网络层（全 HTTPS + 无证书校验绕过）、SQL 注入防护（drift customSelect 全参数化）、Android 权限最小化（6 个权限均有必要用途 + allowBackup=false）四方面做得**符合最佳实践**，3 条安全相关硬约束（1/5/6）全部满足，无 P0 级安全问题。最严重的 P1 是 sentry_scrub.dart 的 tags 脱敏承诺与实现不一致（注释说处理 tags 但代码漏了），但因项目未主动调用 setTag，实际泄露面有限，建议补 tags 脱敏或修正注释。其余 11 项 P2 集中在备份文件未加密、导入缺少恶意数据校验、URL https 校验缺失等加固空间，均不影响当前功能正确性，可按优先级排期修复。整体安全基线在个人自用 app 中属**良好水平**。
