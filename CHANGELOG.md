# Changelog

本项目所有重要变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

- M25 图标设计精修（进行中）
- M25 GitHub 仓库主页同步完善

## [v0.22.0] - 2026-07-05

### M24：P1 清零（13 项 P1 修复 + 架构重构）
- **快速修复（8 项）**：Sentry tags 脱敏 / dashboard 触控目标 / update release notes 展开 / food_library 搜索 toast / backup 离线队列提示 / insight 周/月切换 loading / food_library + profile ErrorState
- **架构重构（5 项）**：跨层依赖 Provider 注入 / recognize_page _pickAndRecognize 190→23 行 / offline_queue_controller processPending 396→29 行 / multi_dish_page 986→542 行 / dashboard_page 940→304 行
- **验证**：flutter analyze No issues / flutter test 1032 passed / 6 硬约束满足 / 0 回归
- 代码健康度 B+ → A-

## [v0.21.0] - 2026-07-05

### M22：图标精修 + 识别等待动画重构
- 图标反转配色（紫底白前景 → 白底紫前景）+ 几何精修（描边 4→2.5dp / square→round cap / 范围 50→36dp / 碗剪影替代苹果圆 / 移除扫描线）
- 识别进度卡片 TweenAnimationBuilder 平滑插值 + AnimatedSwitcher 图标 morph + done 态弹性 scale-in
- 查库阶段最小展示 300ms + done 态成功停留 400ms

## [v0.20.1] - 2026-07-05

### M21：项目全面审查 + P0/P1 修复
- P0 修复：HANDOFF.md 第 1/2 节严重不同步
- P1 修复：补 glm_4v_provider + qwen_vl_provider isRefusalForTest 单测共 16 个
- 987 测试全过 + 6 硬约束全部通过 + M19/M20 无回归

## [v0.20.0] - 2026-07-05

### M20：Google Lens 风图标 + 识别思考流程 UI
- 图标重设计：紫橙渐变 + 圆角取景框 + 苹果剪影 + 扫描线
- 识别思考流程 UI：识别中显示 AI 思考步骤卡片
- 新增 10 个 widget 测试 + 更新 6 个图标测试

## [v0.19.1] - 2026-07-05

### M19：AI 推荐去重 + 菜名归一化 + 多样性
- AI 推荐结果去重（避免重复推荐同一菜品）
- 菜名归一化（统一不同写法）
- 推荐多样性增强
- 新增 35 个 TDD 测试

## [v0.19.0] - 2026-07-05

### M18：多菜场景 AI 推理可见性 + 三路径一致性
- 多菜场景展示 AI 推理过程
- 三路径（recognize_page / multi_dish_page / offline_queue_controller）行为一致性

## [v0.18.9] - 2026-07-05

### M17：App 图标重设计——M3 抽象几何
- M3 抽象几何图标（同心圆环 + 中心圆点）
- 紫橙双色渐变背景

## [v0.18.8] - 2026-07-05

### M16.9：减小库值重要性——AI 绝对优先
- 查库命中分支重写（AI 与库偏差 > 50% 用 AI 反算 per100g + 更新库）
- 复合菜残留路径修复

## [v0.18.6] - 2026-07-05

### M16.7：Web Interface Guidelines 全 UI 审查修复
- 17 文件 195 问题修复（按 Web Interface Guidelines 规范）

## [v0.18.5] - 2026-07-05

### M16.6：营养数值一致性修复
- 三路径 actualCalories 计算统一（recognize_page / multi_dish_page / offline_queue_controller）
- meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致

## [v0.18.4] - 2026-07-05

### M16.5：bump + HANDOFF 回填

## [v0.18.3] - 2026-07-05

### M16.4：bump + HANDOFF 回填 + spec 文档归档

## [v0.18.1] - 2026-07-05

### M16.2：识别流程修复 6 个 P0/P1 问题
- 用户反馈"相册内识别经常出错"

## [v0.18.0] - 2026-07-04

### M16：应用内自更新
- MainActivity.kt 修复 call.arguments 类型转换（CI build failed）
- 严格 TDD 实现 13 个 Task

## [v0.16.0] - 2026-07-04

### M15：v5 AI 推荐审计修复 + 满意度反馈按钮优化

## [v0.15.0] - 2026-07-04

### M15：UI 优化 + 图标重设计
- 暖橙纯色图标（餐叉餐刀）
