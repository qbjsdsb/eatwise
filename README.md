# EatWise

> 拍照识别食物热量 + 营养记录 + AI 周/月汇总建议 — Flutter App（个人自用）

## 这是什么

一个用 Flutter 写的本地优先（local-first）营养记录 App：拍一张食物照片，AI 识别菜名并估算份量，自动从本地《中国食物成分表》数据库回填营养素，记入今日额度；长期记录摄入与体重趋势，由大模型生成阶段性饮食建议。

## 设计目标

- **个人自用、纯前端、无后端**：所有数据存本地加密 SQLite，不依赖云服务
- **准确度优先于便捷**：识别 + 份量估算与查库回填分离，单品误差 ±3-5%，复合菜 ±10-15%（纯图像估算 ±20%）
- **隐私优先**：上传前剥离图片 EXIF；数据库 AES 加密；API key 不入库
- **数据主权**：JSON 导出/导入，换机不丢数据

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter（iOS + Android 一套代码） |
| 本地数据库 | drift + sqlite3 build hooks (source: sqlite3mc, SQLite3MultipleCiphers)（AES 加密；sqlcipher_flutter_libs 已 EOL 故弃用） |
| 密钥存储 | flutter_secure_storage（Keychain / Keystore） |
| 拍照 | image_picker（flutter.dev 一方包） |
| 图片预处理 | flutter_image_compress（默认剥离 EXIF + 压缩） |
| 图表 | fl_chart |
| 状态管理 | flutter_riverpod |
| 路由 | go_router |
| 视觉大模型 | Qwen-VL（首选）/ GLM-4V-Plus（备选） |
| 文本大模型 | GLM-4-Flash（周/月汇总，免费） |
| 错误监控 | sentry_flutter |
| 中文食物库 | 《中国食物成分表》第6版（Sanotsu/china-food-composition-data） |
| 包装食品 | OpenFoodFacts（条码扫描，MVP 不接入，后续迭代） |

## 目录结构

```
lib/
  main.dart
  app.dart
  core/                 # 通用工具、主题、错误处理
    monitoring/         # Sentry 接入 + 脱敏钩子
  data/
    database/           # drift 定义
    database/migrations/ # drift step-by-step 迁移文件（make-migrations 产物）
    models/             # 数据模型
    repositories/       # 仓储层
  features/
    profile/            # 个人档案 + 热量目标计算
    recognize/          # 拍照识别流程
    diary/              # 今日记录（含识别反馈入口）
    dashboard/          # 今日额度看板
    food_library/       # 食物库
    manual_entry/       # 手动录入兜底
    weight/             # 体重记录
    insights/           # 长期趋势 + AI 周/月汇总
    backup/             # 图片清理 + 自动备份
    settings/           # 设置（API key、备份导出、隐私、Sentry 开关）
  ai/
    vision_provider.dart    # 视觉大模型抽象接口
    qwen_vl.dart
    glm_4v.dart
    nutrition_lookup.dart   # 识别→查库回填
    prompts.dart            # prompt 版本管理（文件头注释版本号）
docs/
  superpowers/
    specs/              # 设计文档
    plans/              # 实现计划
drift_schemas/          # drift schema 快照（make-migrations 产物，入库供迁移测试用）
test/
  data/                 # drift 迁移测试
  features/             # 业务逻辑测试
  ai/                   # 大模型 JSON 解析容错测试
  fixtures/             # 静态回归集：50-100 张真实食物图（不入库，gitignore）
                        # 动态回归集：从 recognition_feedback 表导出（入库随数据库）
```

## 文档

- 设计文档：[`docs/superpowers/specs/2026-07-01-eatwise-design.md`](docs/superpowers/specs/2026-07-01-eatwise-design.md)

## 状态

🚧 设计阶段 — 尚未开始编码

## 许可证

MIT
