# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-07-03

### 新增
- **AI 估热兜底**：库未命中的单品不再直接失败转手动录入，改用 AI 整菜营养估算兜底
  - prompt v1.0 → v1.1，schema 加 `estimated_calories/protein_g/fat_g/carbs_g`（按 mid 份量，含烹饪用油与调味糖）
  - "AI 主估 + 本地库校验"两层架构：库命中用库值（金标准），库未命中透传 AI 估算值
  - 校准页菜名下显示数据来源徽章（库匹配 / AI 估算）
  - foodItemId=0 哨兵机制：AI 兜底结果经 `upsertAiRecognized` 创建 food_item 替换哨兵，满足 FK 约束
- **主题色自选**：12 色预设色板（莫奈《睡莲》青绿等），设置页即时换肤 + 持久化
- **darkTheme 支持**：跟随系统深色模式
- **Material 自适应图标**：矢量 drawable 前景+背景+monochrome，Pillow 4x 超采样 PNG fallback
- 应用名改"慢慢吃"（AndroidManifest + MaterialApp title + 关于页）

### 优化
- 全局主题基线：CardTheme 12dp 圆角、InputDecoration OutlineInputBorder、FilledButton 20dp 圆角
- 全局硬编码颜色清理：insight/weight/today_meals/food_library/settings/calibration 图表与文案改用 colorScheme
- dashboard 主题色联动：环形图/宏量条/Drawer header 去硬编码 green/red/grey
- insight ToggleButtons → SegmentedButton（M3 规范组件）
- 防重复点击：profile/weight/settings/food_edit/manual_entry/backup 6 页 7 个保存方法加 _busy 保护
- 补全 IconButton tooltip

### 兼容性
- 旧 prompt(v1.0) 返回无营养字段 → AI 字段 null → 未命中仍走弹窗（向后兼容）
- 离线队列存 promptVersion，重放旧结果按旧 schema 解析

## [0.1.0] - 2026-06-30

### 首版
- 拍照识别食物热量（Qwen-VL / GLM-4V 双模型容灾）
- 营养记录 + 三宏量看板 + 体重趋势
- AI 周报（GLM-4-Flash）+ 数据备份 + 离线队列
- 本地食物库（中国食物成分表 ~300 条）
