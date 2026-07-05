# Tasks

## Phase 1：审查准备

- [x] Task 1: 创建审查报告骨架 `docs/audit/m23-comprehensive-audit-report.md`
  - [x] SubTask 1.1: 新建 `docs/audit/` 目录
  - [x] SubTask 1.2: 写报告元信息（审查日期 / 基线 commit / 测试数 / 4 维度章节标题）
  - [x] SubTask 1.3: 用 WebFetch 拉取 web-design-guidelines 最新规则作为维度 1 审查依据

## Phase 2：4 维度并行审查

- [x] Task 2: 维度 1 — UI 界面规范审查（Material 3 + 视觉一致性）
  - [x] SubTask 2.1: grep 所有 feature 页面的 padding/margin/spacing 用法，找不一致
  - [x] SubTask 2.2: 检查每个页面的加载态/空态/错误态是否完整
  - [x] SubTask 2.3: 检查无障碍（SemanticLabel / 触控目标 ≥48dp / 大字体支持）
  - [x] SubTask 2.4: 检查 AppBar / Card / FAB / NavigationBar 跨页面视觉一致性
  - [x] SubTask 2.5: 检查 M22 进度卡片动画 + 其他页面是否还有突兀切换
  - [x] SubTask 2.6: 把发现按 P0/P1/P2 分级写入报告维度 1 章节

- [x] Task 3: 维度 2 — 功能完整性审查（每个 feature 功能流）
  - [x] SubTask 3.1: 识别主流程走查（recognize_page → calibration_page → 写库 → 跳转）
  - [x] SubTask 3.2: AI 兜底三路径一致性审查（recognize_page / multi_dish_page / offline_queue_controller）
  - [x] SubTask 3.3: 离线队列流程审查（入队 → 回补 → 重试 → 死信）
  - [x] SubTask 3.4: 备份/恢复流程审查（导出 → 导入 → 图片处理 → 跨设备）
  - [x] SubTask 3.5: 应用内更新流程审查（检查 → 下载 → 安装 → 回退）
  - [x] SubTask 3.6: 洞察生成 + 推荐系统流程审查（M19 去重 + 反馈）
  - [x] SubTask 3.7: 体重记录 + 食物库 + 设置页流程审查
  - [x] SubTask 3.8: 把发现按 P0/P1/P2 分级写入报告维度 2 章节

- [x] Task 4: 维度 3 — 代码质量审查（架构/重复/复杂度）
  - [x] SubTask 4.1: grep 跨层依赖（feature 直接 import data/database）
  - [x] SubTask 4.2: 列超长文件清单（>500 行）+ 评估拆分建议
  - [x] SubTask 4.3: 识别三路径重复代码（recognize/multi_dish/offline 的哨兵替换 + 包装 OCR 优先）
  - [x] SubTask 4.4: grep TODO/FIXME/HACK 全代码库
  - [x] SubTask 4.5: 检查 async gap（await 后是否检查 mounted）+ 写库按钮防重入（_busy/_isRecording）
  - [x] SubTask 4.6: 检查 Riverpod Provider 生命周期 / 错误处理 / Sentry 上报
  - [x] SubTask 4.7: 把发现按 P0/P1/P2 分级写入报告维度 3 章节

- [x] Task 5: 维度 4 — 安全审查（密钥/脱敏/权限）
  - [x] SubTask 5.1: 检查 SecureConfigStore 用法（项目规则：无 instance 静态属性）
  - [x] SubTask 5.2: 检查 sentry_scrub 覆盖完整性（API key / 用户图片 / 食物名）
  - [x] SubTask 5.3: 检查 AndroidManifest 权限最小必要（相机/网络/存储）
  - [x] SubTask 5.4: 检查网络层（HTTPS / 证书校验 / 信任所有证书风险）
  - [x] SubTask 5.5: 检查 drift 查询是否全参数化（无 SQL 注入）
  - [x] SubTask 5.6: 检查备份文件安全（导出含敏感数据 / 导入校验）
  - [x] SubTask 5.7: 检查 print/debugPrint 是否泄露敏感信息
  - [x] SubTask 5.8: 检查 pubspec.yaml 依赖版本锁定 + 已知 CVE
  - [x] SubTask 5.9: 把发现按 P0/P1/P2 分级写入报告维度 4 章节

## Phase 3：综合报告 + 优先级清单

- [x] Task 6: 汇总 4 维度发现，生成优先级清单
  - [x] SubTask 6.1: 统计 P0/P1/P2 数量分布（0 / 13 / 54 = 67）
  - [x] SubTask 6.2: 写报告"摘要"章节（整体评价一段话）
  - [x] SubTask 6.3: 写报告"优先级清单汇总"章节（表格 + 代表问题）
  - [x] SubTask 6.4: 写报告"后续建议"章节（M24 修 P1 / M25+ 修 P2）

## Phase 4：用户审阅 + 转修复 spec

- [x] Task 7: 提交报告给用户审阅
  - [x] SubTask 7.1: 综合报告交付（路径 `/workspace/docs/audit/m23-comprehensive-audit-report.md`）
  - [ ] SubTask 7.2: 等用户确认修哪些 P0/P1，再创建 M24 修复 spec（待用户决策）

# Task Dependencies

- Task 1 → Task 2/3/4/5（先建报告骨架，4 维度并行写入）
- Task 2/3/4/5 → Task 6（4 维度审查完才能汇总优先级）
- Task 6 → Task 7（汇总完才能通知用户审阅）
- Task 2/3/4/5 之间无依赖，可并行执行
