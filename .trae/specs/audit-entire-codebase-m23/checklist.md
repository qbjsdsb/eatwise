# M23 全面细致审查 Checklist

## 审查准备
- [x] `docs/audit/m23-comprehensive-audit-report.md` 报告骨架已创建
- [x] 报告元信息含：审查日期 / 基线 commit (13701c5) / 版本 (v0.21.0+33) / 测试基线 (1010 passed)
- [x] web-design-guidelines 最新规则已拉取（WebFetch from raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md）

## 维度 1：UI 界面规范
- [x] 14 个 feature 页面全部走查（dashboard / today_meals / food_library / insight / manual_entry / me / profile / recognize / calibration / multi_dish / records / settings / update / weight / backup）
- [x] 间距一致性检查（padding/margin 是否 4/8/16/24 基础单位倍数）
- [x] 视觉层级检查（title/body/label 字号字重 / Card elevation 一致性）
- [x] 颜色对比度检查（TextOnSurface/OnPrimary 满足 WCAG AA 4.5:1）
- [x] 加载态检查（每个异步操作有 loading 指示）
- [x] 空态检查（无数据时有 EmptyState 引导）
- [x] 错误态检查（异常有友好提示 + 重试入口）
- [x] 无障碍检查（SemanticLabel / 大字体 / 屏幕阅读器可读性）
- [x] 触控目标检查（按钮/列表项 ≥48×48dp）
- [x] 动效检查（M22 进度卡片 + 其他页面是否还有突兀切换）
- [x] 跨页面视觉一致性检查（AppBar / Card / FAB / NavigationBar 风格统一）

## 维度 2：功能完整性
- [x] 识别主流程走查（选图→压缩→AI→查库→校准→写库→跳转）
- [x] AI 兜底三路径一致性审查（recognize_page / multi_dish_page / offline_queue_controller）
- [x] foodItemId=0 哨兵替换逻辑三处一致（硬约束 3）
- [x] 离线队列流程审查（入队 → 回补 → 重试 → 死信）
- [x] 备份/恢复流程审查（导出 → 导入 → 图片处理 → 跨设备）
- [x] 应用内更新流程审查（检查 → 下载 → 安装 → 回退）
- [x] 洞察生成 + 推荐系统流程审查（M19 去重 + 反馈）
- [x] 体重记录 + 食物库 + 设置页流程审查
- [x] 每个流程的边界条件 / 异常态 / 死路已列清单

## 维度 3：代码质量
- [x] 跨层依赖检查（feature 不直接 import data/database）
- [x] 超长文件清单（>500 行）已列 + 拆分建议
- [x] 三路径重复代码已识别（recognize/multi_dish/offline 哨兵替换 + 包装 OCR 优先）
- [x] TODO/FIXME/HACK 全代码库 grep 清单
- [x] async gap 检查（await 后检查 mounted，项目规则强制）
- [x] 写库按钮防重入检查（_busy/_isRecording + try-catch-finally，项目规则强制）
- [x] Riverpod Provider 生命周期 / dispose / 泄漏检查
- [x] 错误处理检查（try-catch 不吞错 / Sentry 上报 / 用户友好提示）
- [x] 硬编码检查（颜色/字符串/数字常量是否抽取）
- [x] 命名一致性检查（变量/方法/类跨文件风格统一）

## 维度 4：安全
- [x] SecureConfigStore 用法正确（无 instance 静态属性，硬约束 5）
- [x] Sentry 脱敏覆盖完整性（API key / 用户图片 / 食物名等敏感字段）
- [x] AndroidManifest 权限最小必要（相机/网络/存储）
- [x] 网络层全 HTTPS + 证书校验（无信任所有证书）
- [x] drift 查询全参数化（无 SQL 注入）
- [x] 备份文件安全（导出含敏感数据评估 / 导入校验恶意数据）
- [x] print/debugPrint 无敏感信息泄露
- [x] pubspec.yaml 依赖版本锁定 + 已知 CVE 检查

## 6 条硬约束（审查中若发现违反标 P0）
- [x] `android/app/build.gradle.kts` 保持 `isMinifyEnabled=false` + `isShrinkResources=false`
- [x] `meal_log.food_item_id` 非空外键（PRAGMA foreign_keys=ON），foodItemId=0 哨兵写库前必须替换
- [x] AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller）
- [x] per100g 反算基于 `estimatedWeightGMid`（不能用 `servingG`）
- [x] `SecureConfigStore` 无 `instance` 静态属性
- [x] `initSentryAndRunApp` 参数是命名参数 `container:` + `app:`

## 报告完整性
- [x] 报告含 4 维度独立章节
- [x] 每个发现含：位置（file:line）/ 现状 / 影响 / 建议修复 / 工作量估算
- [x] 报告末尾含优先级清单汇总表（P0/P1/P2 数量 + 代表问题）
- [x] 报告末尾含后续建议（M24 修 P1 / M25+ 修 P2）
- [x] 报告整体评价段落（一段话总结代码健康度）

## 审查纪律
- [x] 审查过程不改任何 lib/ 或 test/ 代码
- [x] 所有发现只记录在报告里，不直接修
- [x] 修复由 M24+ spec 处理（用户审阅报告后决策）
