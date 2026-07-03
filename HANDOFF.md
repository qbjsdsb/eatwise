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

**工作区状态**：clean（识别智能化批次 1-3 已提交，未发布 release，等用户确认）
**最近 commit**：
- `feat: 识别智能化——图片预检+字段校验+营养素自洽+包装容量优先+反馈闭环` （批次 1-3）
- `50d4cac` fix: 第四轮深度审查修复——主题色绿/常用食物无名/原图丢失/复合菜滑块/防重入
- `baba3e1` feat: 项目分析与建议（prompt v1.5 + 反馈卡死修复 + 转手动入口）
- `c015953` fix: 第三轮深度审查修复 + release 构建失败根因

**已发布**：
- v0.10.0 已发布（2026-07-03，第二次 release 成功，APK 已上传）
- 识别智能化批次 1-3 **未发布**（用户要求先告知，不发布 release）

**识别智能化批次 1-3 修复清单**（本次 commit，用户选择"全部融入"）：
- 批次 1 图片预检 + 字段校验：
  - 新建 `lib/core/util/recognition_validator.dart`——字段合理性校验（dishName/confidence/weight/区间）+ 营养素自洽校验（4p+9f+4c≈cal，±10%）
  - recognize_controller 集成校验：字段不合理→重试 1 次；营养素不自洽→自动用宏量营养素反推修正 calories
  - 修复 image_quality_checker.dart 类型错误（laplacianValues num→double）
  - 20 个校验器单元测试全过
- 批次 2 prompt v1.6 + 包装容量优先：
  - prompt v1.6：包装食品必须读取包装标签净含量（weight_source=package_label），不靠视觉估算
  - 营养素自洽约束：要求 AI 用 4p+9f+4c 反算 calories，偏差<5%
  - VisionRecognitionResult 新增 weightSource 字段 + fromJson 解析（向后兼容旧 prompt）
  - 示例 1-3 加 weight_source 字段 + 自洽性标注
- 批次 3 反馈闭环回流 aliasesJson：
  - FoodItemRepository 新增 addAlias 方法（事务包裹 + 归一化去重）
  - today_meals_page._showFeedbackDialog 加别名回流：用户纠正菜名后，把 AI 错误名作为正确菜的别名
  - 下次 AI 识别返回错误名时，findByNameOrAlias 命中别名，直接返回正确菜营养数据
  - 6 个 addAlias 单元测试全过

**验证**：flutter analyze No issues + flutter test 268 passed/3 skipped/0 failed

**未完成/待办**（按优先级）：
1. ⬜ 用户验收测试（真机装 APK 验证识别智能化效果，等用户确认后发布 release）
2. 🔧 批次 4（暂跳过，不在用户明确选择范围）：低置信度双模型验证 + 多候选选择 UI（成本高、延迟大，待用户确认是否需要）
3. 🔧 重构性优化（风险较高，不阻塞当前版本）：
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
