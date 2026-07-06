# 项目规则：慢慢吃（EatWise）

> 本文件由 Trae 自动加载到每个会话的上下文。保持简洁，只放"AI 必须知道的核心约定"。

## 会话开启必做

1. **先读 `/workspace/HANDOFF.md`** 了解项目当前状态、未完成项、已知陷阱
2. 跑 `git log --oneline -10` 和 `git status` 确认代码状态
3. 问用户今天要做什么，**不要主动改代码**

## 会话结束必做

1. 更新 `HANDOFF.md` 第 2 节"当前状态"
2. 确认 `git status` clean（或记录未提交原因）
3. 有新陷阱/决策就补到 HANDOFF.md

## 不可违背的硬约束

1. **`android/app/build.gradle.kts`** 必须保持 `isMinifyEnabled = false` + `isShrinkResources = false`（否则 R8 剥掉 sentry/workmanager 反射类致 APK 启动崩溃）
2. **`meal_log.food_item_id` 是非空外键**（PRAGMA foreign_keys=ON）。AI 兜底的 `foodItemId=0` 是哨兵，写 meal_log 前必须调 `upsertAiRecognized` 替换为真实 id，否则 SQLite 外键约束违规崩溃
3. **AI 兜底三条路径必须全部覆盖**：`recognize_page`（单品）、`multi_dish_page`（主菜+附加菜）、`offline_queue_controller`（后台回补）
4. **per100g 反算必须基于 `estimatedWeightGMid`**，不能用 `servingG`（用户校准份量），否则密度随用户调整反向偏差
5. **`SecureConfigStore` 没有 `instance` 静态属性**，用 `SecureConfigStore()` 构造函数或 `container.read(secureConfigStoreProvider)`
6. **`initSentryAndRunApp` 参数是命名参数** `container:` + `app:`，不是位置参数
7. **`minSdk = 31`**（动态取色 Material You 需 Android 12+，dynamic_color 包硬性要求；提升前 minSdk=24，提升后丢失 Android 7-11 用户，项目个人自用可接受）

## 沙箱环境注意

- Flutter 在 `/tmp/flutter/bin`，每次新会话需 `export PATH=/tmp/flutter/bin:$PATH`
- 测试可能因 sqlite3 native 库下载失败（沙箱网络问题），重试通常能过
- 不要主动 push 或打 tag，等用户明确指令

## 代码风格

- 注释用中文（与项目现有风格一致）
- 写库按钮必须有 `_busy`/`_isRecording` 防重入 + try-catch-finally
- async gap 后必须检查 `mounted`
- 重大改动后跑 `flutter analyze` + `flutter test` 验证
