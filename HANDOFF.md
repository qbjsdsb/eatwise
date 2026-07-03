# 项目交接文档（Handoff）

> **用途**：沙箱会话不持久化，每天 AI 会"失忆"。
> 本文档是跨会话记忆载体，每个会话开始时 AI 必读，结束前 AI 必更新。
> **维护规则**：每次会话有实质进展就更新，保持"任何新 AI 读完此文档就能无缝接手"。

---

## 0. 新会话开启指令（给 AI 看的）

```
你是接手这个项目的新 AI。请按以下顺序操作：
1. 读本文件全文（HANDOFF.md）了解项目状态与约定
2. 读 .trae/rules/ 下的项目规则（若有）
3. 跑 `git log --oneline -20` 看最近提交
4. 跑 `git status` 看工作区状态
5. 问用户"今天要继续做什么"——不要主动改代码
```

---

## 1. 项目速览

- **项目名**：慢慢吃（EatWise）—— 拍照识别食物热量 + 营养记录 + AI 汇总建议
- **技术栈**：Flutter 3.44.4 / Dart / Riverpod / drift (SQLite) / Material 3 Expressive
- **当前版本**：0.10.0+10（pubspec.yaml）
- **当前分支**：v0.10.0-m3-merge（基于 v0.8.0，叠加 HEAD 的 AI 估热+主题色+Sentry）
- **关键约束**：
  - `meal_log.food_item_id` 是非空外键，PRAGMA foreign_keys=ON，foodItemId=0 哨兵写库前必须替换为真实 id
  - `android/app/build.gradle.kts` 必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`（否则 R8 剥掉 sentry/workmanager 反射类致启动崩溃）
  - AI 兜底（foodItemId=0）需在前台 recognize_page、multi_dish_page、后台 offline_queue_controller 三条路径全部覆盖

---

## 2. 当前状态（每次会话结束更新）

**最后更新**：2026-07-03

**工作区状态**：clean
**最近 commit**：
- `50d4cac` fix: 第四轮深度审查修复——主题色绿/常用食物无名/原图丢失/复合菜滑块/防重入
- `baba3e1` feat: 项目分析与建议（prompt v1.5 + 反馈卡死修复 + 转手动入口）
- `c015953` fix: 第三轮深度审查修复 + release 构建失败根因
- `cddc9ff` docs: 更新 HANDOFF 第2节——v0.10.0 发布完成
- `bd66ef3` docs: 添加跨会话交接文档 + Trae 项目规则
- `8e436cc` fix: 深度审查修复——数据丢失/污染 + 启动白屏 + 异常处理 + 一致性
- `79f4cfd` fix: v0.10.0 合并收尾——修复致命崩溃 + 数据正确性 + 防重入 + 一致性

**已发布**：
- v0.10.0 已发布（2026-07-03，第二次 release 成功，APK 已上传）
- 分支 v0.10.0-m3-merge 已同步到远程
- 四轮深度审查修复完成
- 发布前验证：flutter analyze No issues + flutter test 242 passed/3 skipped/0 failed

**第四轮审查修复清单**（commit 50d4cac，用户反馈驱动）：
- 主题色绿根因：expressive→tonalSpot + secondaryContainer→primaryContainer + 默认色绿→紫
- 常用食物无名根因：listFrequent 过滤0引用 + upsertAiRecognized 空串兜底 + Text兜底
- 原图丢失：recognize_page 识别成功后持久化原图（避免临时缓存被清理致 broken image）
- 复合菜主滑块无效：calibration_page 复合菜路径隐藏主份量 Slider
- today_meals _load 补 try-catch-finally + _showEditDialog 补 _busy 防重入
- multi_dish_page 转手动按钮补 _isRecording 防重入
- prompt v1.5 示例 3 雪碧/美年达热量修正

**第三轮审查修复清单**（commit c015953）：
- release 根因：colors.xml 空文件 → 补 <resources> 根元素
- 致命：offline_queue_controller cal==null 不再创建 0 卡 food_item（污染查库），改 markFailed
- 严重：multi_dish_page 复合菜 insertMealLog 补 componentsSnapshotJson + 事务包裹
- 严重：offline_queue_controller recordSuccess 包 try-catch + 复合菜全 miss+cal==null 不写 0 卡
- 严重：sentry_scrub 补 event.message 脱敏 + event.request 丢弃（防 API key 泄露）
- 严重：main.dart zone handler 补 Sentry.captureException
- 严重：weight_page _save 补 catch + food_library _doSearch/_loadFrequent 补 try-catch
- 警告：recognize_page 未命中弹窗条件补 componentHits.isEmpty
- 警告：insertMealLog 加 foodItemId<=0 哨兵防御
- 统一：multi_dish_page _encodeComponents 格式与 offline_queue_controller 一致

**未完成/待办**（按优先级）：
1. ⬜ 用户验收测试（真机装 APK 验证，等 release 构建完成下载）
2. 🔧 重构性优化（风险较高，不阻塞当前版本）：
   - 路由方式统一（GoRouter vs Navigator.push 混用）
   - 版本号从 PackageInfo 读取（替代硬编码）
   - dashboard/today_meals N+1 查询优化（getByIds）
   - 测试覆盖增强：AI 兜底、foodItemId=0 哨兵 FK 约束、getThemeSeed 单元测试
   - Sentry appRunner 标准化 + FlutterError.onError 链式调用
   - 后台回补补 fallback provider + circuitBreaker + incrementMonthlyCount

---

## 3. 关键架构决策（不要轻易改）

### 3.1 AI 估热 + 本地库校验两层架构
- 库命中 → 用库值（NutritionSource.database）
- 库未命中 + AI 有 estimatedCalories → AI 兜底（foodItemId=0 哨兵，source=aiEstimate）
- 库未命中 + AI 无估算 → 走未命中弹窗转手动录入
- 复合菜组分全 miss → 转 AI 兜底走单品路径（v0.10.0 新增）

### 3.2 foodItemId=0 哨兵机制
- AI 兜底 NutritionResult.foodItemId=0（recognize_controller._aiFallbackNutrition）
- 写 meal_log 前必须调 upsertAiRecognized 创建真实 food_item 替换哨兵
- 三条路径已全部覆盖：recognize_page 单品、multi_dish_page 主菜+附加菜、offline_queue_controller

### 3.3 复合菜存储
- per100g=0 占位（实际热量在 meal_log.componentsSnapshotJson）
- nutrition_lookup.lookupSingleItem 过滤 componentsJson!=null 的记录（防 0 卡污染）
- listAllForRecommendation 排除 source='ai_recognized'

### 3.4 prompt 版本 v1.4
- 合并 v1.3（多菜多份 quantity/unit/perUnitG）+ v1.1（营养字段 estimated_calories 等）
- schema 新增 estimated_calories/protein_g/fat_g/carbs_g

### 3.5 主题色
- themeSeedProvider（NotifierProvider<int>）+ secure_config_store 持久化
- 默认莫奈《睡莲》青绿 0xFF5B8C7B，12 色预设 kThemePresets
- main.dart runApp 前快速读，首帧即用正确主题色避免闪烁

### 3.6 启动流程（main.dart）
- runZonedGuarded 包整个 main
- 单一 ProviderContainer（UI 与初始化共用，不 dispose）
- themeSeed 快速读 → initSentryAndRunApp（appConfig 失败降级跳过 Sentry）→ runApp
- UI 起来后异步：appConfig / Workmanager / OfflineQueue（fire-and-forget）/ ImageCleanup（读用户保留期）

---

## 4. 已知陷阱（踩过的坑）

1. **APK 打不开**：build.gradle.kts 丢失 R8 禁用配置 → native 启动崩溃。必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`
2. **SecureConfigStore.instance 不存在**：v0.8.0 用 `SecureConfigStore()` 构造函数，没有静态 instance。main.dart 用 `container.read(secureConfigStoreProvider)`
3. **initSentryAndRunApp 参数名**：是 `container:` + `app:`（命名参数），不是位置参数
4. **multi_dish_page take(5) 截断**：附加菜超 5 道静默丢弃，当前未提示用户（待优化）
5. **滑块 max 与 perUnitG*20 边界**：perUnitG 极大/极小时滑块与步进器可能不同步（待优化）
6. **测试 mock 需补 getThemeSeed stub**：AppConfig.load() 新增了 getThemeSeed() 调用，mock SecureConfigStore 的测试必须 stub

---

## 5. 常用命令

```bash
# 环境（沙箱每次需重设 PATH）
export PATH=/tmp/flutter/bin:$PATH

# 验证
flutter analyze
flutter test
flutter test test/features/settings_backup_overdue_test.dart  # 单个测试

# 构建（fat APK 全架构）
flutter build apk --release --no-tree-shake-icons

# Git
git log --oneline -10
git status
git tag --list 'v*'
```

---

## 6. 文件地图（关键文件）

```
lib/
├── main.dart                          # 启动：zone+Sentry+themeSeed+异步初始化
├── app.dart                           # M3 主题 + 4-tab StatefulShellRoute 路由
├── main_shell.dart                    # 底部导航壳 + FAB
├── ai/
│   ├── prompts.dart                   # v1.4 prompt
│   ├── vision_provider.dart           # VisionRecognitionResult（含 copyWith）
│   ├── vision_service.dart            # 视觉服务
│   ├── nutrition_lookup.dart          # NutritionLookup + NutritionSource 枚举
│   └── off_provider.dart              # Open Food Facts 云查
├── core/
│   ├── config/
│   │   ├── app_config.dart            # AppConfig.load() + appConfigProvider
│   │   └── secure_config_store.dart   # secure_storage 封装（含 themeSeed）
│   ├── theme/theme_controller.dart    # themeSeedProvider + kThemePresets
│   └── error/
│       ├── sentry_init.dart           # initSentryAndRunApp（appConfig 失败降级）
│       └── sentry_scrub.dart          # Sentry 脱敏
├── data/
│   ├── database/database.dart         # drift，PRAGMA foreign_keys=ON
│   └── repositories/
│       ├── food_item_repository.dart  # upsertAiRecognized（更新含 componentsJson）
│       └── meal_log_repository.dart   # insertMealLog
└── features/
    ├── recognize/
    │   ├── recognize_controller.dart  # AI 兜底 + 复合菜全 miss 转 AI
    │   ├── recognize_page.dart        # 哨兵处理 + 改菜名 copyWith
    │   ├── calibration_page.dart      # 校准 + 数量步进器 + 徽章
    │   └── multi_dish_page.dart       # 多菜 _hitFlags 含 componentHits 判定
    ├── offline/offline_queue_controller.dart  # 离线回补 AI 兜底 + fire-and-forget
    ├── settings/settings_page.dart    # 主题色板 + _isSaving
    ├── profile/profile_page.dart      # _busy + try-catch
    ├── weight/weight_page.dart        # _busy + _load try-catch
    ├── food_library/                  # food_edit_page + food_library_page
    ├── manual_entry/manual_entry_page.dart
    ├── backup/backup_page.dart        # 导入二次确认
    ├── me/me_page.dart
    ├── records/records_tab_page.dart
    ├── dashboard/dashboard_page.dart
    └── insight/insight_page.dart
```

---

## 7. 会话结束前 AI 必做

1. 更新本文件第 2 节"当前状态"（日期、commit、工作区、未完成项）
2. 如有新陷阱，补到第 4 节
3. 如有新架构决策，补到第 3 节
4. 确认 `git status` clean（或明确记录未提交的改动原因）
