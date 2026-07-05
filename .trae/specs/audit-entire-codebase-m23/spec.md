# M23 项目全面细致审查 Spec

## Why

M21（2026-07-05）已做过一次"全面审查"，但那次主要目标是验证 M19/M20 无回归 + 补 P0/P1 测试缺口，未对**每个 feature 的功能流、UI 视觉一致性、代码质量、安全细节**做细致走查。用户反馈"想做一遍细致的检查，包括所有方面，功能界面啥的"，需要一次更深入、更系统的全维度审查，产出一份综合报告 + 优先级清单，作为后续修复迭代（M24+）的依据。

## What Changes

**本次 spec 不改代码**，产出物为：
1. **综合审查报告** `docs/audit/m23-comprehensive-audit-report.md`，按 4 维度分章节列所有发现的问题
2. **优先级清单**（嵌入报告末尾），按 P0/P1/P2 分级，每项含：位置 / 现状 / 影响 / 建议修复方案 / 工作量估算
3. **后续修复 spec**（M24，待用户审阅报告后决定修哪些再创建）

**审查不修改任何 lib/ 或 test/ 代码**。发现的 P0/P1/P2 问题只记录在报告里，等用户确认后才转入修复 spec。

## Impact

- **Affected code**: 全部 `lib/`（14 features + ai/nutrition/data/core/background 支撑层）+ `test/`（约 1010 测试）+ `android/app/src/main/`（Manifest/权限/图标/splash）
- **Affected docs**: 新增 `docs/audit/m23-comprehensive-audit-report.md`
- **Affected specs**: 不影响现有 spec；M24 修复 spec 待本审查完成后由用户决策创建
- **影响范围**: 不改代码，零运行时风险；审查结论将指导 M24+ 修复迭代

## ADDED Requirements

### Requirement: 4 维度全覆盖细致审查

系统 SHALL 对整个 EatWise 代码库做 4 维度细致审查，每维度产出独立章节，所有发现按 P0/P1/P2 分级。

#### 维度 1：UI 界面规范审查（Material 3 + 视觉一致性）

**审查方法**：用 `web-design-guidelines` skill 拉取最新 Web Interface Guidelines，逐个 feature 页面对照检查；同时对照 Material 3 Expressive 规范。

**审查清单**：
- 间距（padding/margin 是否 4/8/16/24 等基础单位倍数，跨页面一致）
- 视觉层级（title/body/label 字号字重，Card elevation 一致性）
- 颜色对比度（TextOnSurface/OnPrimary 等是否满足 WCAG AA 4.5:1）
- 加载态（每个异步操作是否有 loading 指示，避免"卡住无反馈"）
- 空态（无数据时是否有 EmptyState 引导，而非空白屏）
- 错误态（异常是否有友好提示 + 重试入口，而非红屏/崩溃）
- 无障碍（SemanticLabel / 大字体支持 / 屏幕阅读器可读性）
- 触控目标（按钮/列表项是否 ≥48×48dp）
- 动效（M22 已修进度卡片，其他页面是否还有突兀切换）
- 跨页面视觉一致性（导航栏 / AppBar / FAB 风格统一）

**覆盖页面**（14 features）：
dashboard / today_meals / meal_edit_dialog / food_library / food_edit / insight / manual_entry / me / profile / recognize / calibration / multi_dish / records / settings / update / weight / backup

#### 维度 2：功能完整性审查（每个页面功能流）

**审查方法**：逐个 feature 走查"主路径 + 异常路径 + 边界条件"，列死路/未覆盖异常/不一致行为。

**审查清单**：
- 识别主流程：选图 → 压缩 → AI 推理 → 查库回填 → 校准 → 写库 → 入库后跳转（recognize_page / multi_dish_page / calibration_page）
- AI 兜底三路径一致性：recognize_page（单品）/ multi_dish_page（主菜+附加菜）/ offline_queue_controller（后台回补）—— foodItemId=0 哨兵替换逻辑是否三处一致
- 离线队列：网络异常入队 → 恢复后回补 → 失败重试 → 死信处理
- 备份/恢复：JSON 导出 → 导入 → 图片处理 → 跨设备恢复
- 应用内更新：检查更新 → 下载 APK → 安装 → 版本回退
- 洞察生成：触发条件 → AI 调用 → 失败兜底 → 重新生成
- 推荐系统：用户偏好学习 → 推荐 → 反馈 → 去重（M19）
- 体重记录：录入 → 趋势图 → TDEE 校准
- 食物库：增删改查 / 别名 / 品类 / 种子数据
- 设置页：所有开关 / 跳转 / 配置项是否生效

#### 维度 3：代码质量审查（架构/重复/复杂度）

**审查方法**：静态分析 + 人工读关键文件。

**审查清单**：
- 架构层次：feature → nutrition/data → core 是否清晰，有无跨层依赖（如 feature 直接读 DB）
- 命名一致性：变量/方法/类命名是否表达准确、跨文件风格统一
- 重复代码：识别→校准→写库 三路径是否有可抽取的共用逻辑
- 圈复杂度：超长方法（>50 行）/ 深嵌套（>3 层）/ 大量 if-else 链
- 超长文件：>500 行的文件列清单，评估是否需要拆分
- Riverpod 用法：Provider/StateNotifier 生命周期 / dispose / 是否有泄漏
- 错误处理：try-catch 是否吞错 / 异常是否上报 Sentry / 用户提示是否友好
- async gap：await 后是否检查 mounted（项目规则强制）
- 写库按钮防重入：是否都有 _busy/_isRecording（项目规则强制）
- 硬编码：颜色/字符串/数字常量是否抽取
- TODO/FIXME/HACK 清单：grep 全代码库列清单

#### 维度 4：安全审查（密钥/脱敏/权限）

**审查方法**：grep 敏感关键词 + 读关键文件 + 对照 Android 权限声明。

**审查清单**：
- 密钥存储：SecureConfigStore 用法是否正确（项目规则：无 instance 静态属性）
- Sentry 脱敏：sentry_scrub 是否覆盖所有敏感字段（API key / 用户图片 / 食物名等）
- AndroidManifest 权限：相机/网络/存储等权限是否最小必要
- 网络层：HTTP 是否全 HTTPS / 是否有证书校验 / 是否信任所有证书
- SQL 注入：drift 查询是否全用参数化（不拼字符串）
- 备份文件安全：JSON 导出是否含敏感数据 / 导入是否校验恶意数据
- 日志脱敏：print/debugPrint 是否泄露敏感信息
- 第三方依赖：pubspec.yaml 依赖是否有已知 CVE / 是否锁定版本

### Requirement: 优先级清单分级标准

P0/P1/P2 分级标准（写入报告末尾）：

- **P0（阻塞，必须立即修）**：崩溃 / 数据丢失 / 安全漏洞 / 6 条硬约束违反 / 功能完全不可用
- **P1（重要，下一迭代修）**：功能异常但有 workaround / 重要 UX 缺陷 / 测试缺口（关键路径无测试）/ 文档严重不同步
- **P2（改进，长期迭代修）**：代码质量问题 / 视觉小瑕疵 / 性能优化 / 命名改进 / 可读性提升

### Requirement: 审查报告结构

报告 `docs/audit/m23-comprehensive-audit-report.md` 结构：

```
# M23 项目全面细致审查报告

## 元信息
- 审查日期 / 审查范围 / 测试基线（commit / version / 测试数）

## 摘要
- 总问题数 / P0 / P1 / P2 分布
- 整体评价（一段话）

## 维度 1：UI 界面规范
### 1.1 间距与视觉层级
- [P1] dashboard_page.dart:L45 主卡片 padding=12，应为 16（与其他页面不一致）
- ...

## 维度 2：功能完整性
### 2.1 识别主流程
- [P0] multi_dish_page.dart:L475 附加菜 foodItemId=0 未替换（违反硬约束 3）
- ...

## 维度 3：代码质量
### 3.1 超长文件清单
| 文件 | 行数 | 建议 |
|------|------|------|
| recognize_page.dart | 734 | 拆分 _pickAndRecognize / _persistImage / _navigate 子方法 |
| ...

## 维度 4：安全
### 4.1 密钥存储
- [P0] xxx.dart:L12 API key 硬编码在源码（应走 SecureConfigStore）
- ...

## 优先级清单汇总
| 优先级 | 数量 | 代表问题 |
|--------|------|----------|
| P0 | x | ... |
| P1 | x | ... |
| P2 | x | ... |

## 后续建议
- 建议立即修 P0（x 项，预计 y 小时）
- M24 修 P1（x 项）
- M25+ 长期修 P2
```

## Assumptions & Decisions

1. **不改代码**：本次 spec 只产出审查报告，所有发现只记录不修复。修复由 M24+ spec 处理。
2. **审查基线**：M22 完成后的代码库（commit 13701c5, v0.21.0+33, 1010 测试全过）。
3. **不跑真机**：沙箱无真机/模拟器，UI 审查基于代码读 + 静态分析，无法做交互验证。真机验证由用户侧完成。
4. **web-design-guidelines skill 用法**：用 WebFetch 拉取最新 guidelines，对照每个 feature 页面检查。该 skill 主要面向 web，部分规则（如 touch target ≥48dp / 对比度）同样适用 Flutter，不适用的规则（如 HTML 语义化）跳过。
5. **6 条硬约束不变**：本次审查若发现硬约束违反，标记 P0。
6. **Seedream 不参与**：本次审查不生成参考图，纯代码静态审查。
7. **报告位置**：`docs/audit/m23-comprehensive-audit-report.md`（新建 docs/audit/ 目录）。
