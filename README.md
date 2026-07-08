# EatWise 慢慢吃

> 拍照识别食物热量 + 营养记录 + AI 周/月汇总建议 — Flutter Android App（个人自用）

![Version](https://img.shields.io/badge/version-v0.33.1-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.44.4-blue)
![Dart](https://img.shields.io/badge/Dart-3.x-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Android-green)
![Tests](https://img.shields.io/badge/tests-1172%20passed-brightgreen)

## 核心特性

- 📸 **AI 拍照识别**：拍一张食物照片，Qwen-VL / GLM-4V 自动识别菜名 + 估算份量
- 🥗 **本地食物库回填**：从《中国食物成分表》第6版查库回填营养素，单品误差 ±3-5%
- 📊 **AI 周/月汇总**：GLM-4-Flash 生成长期饮食建议，洞察趋势
- ⚖️ **蓝牙体脂秤同步**：支持小米体脂秤 v1/v2 协议（XMTZC04HM / XMTZC05HM），自动捕获体重 + 体脂 + 阻抗
- 🔒 **本地优先 + 隐私保护**：数据存本地 SQLite，无后端，EXIF 剥离，API key 不入库

## 截图

> 截图待补（真机采集后放 `docs/screenshots/`）

| 识别 | Dashboard | Insight |
|---|---|---|
| _待补_ | _待补_ | _待补_ |

## 功能矩阵

| 模块 | 功能 |
|---|---|
| 识别 | 单品识别 + 多菜识别 + 离线队列回补（三路径一致性） |
| 营养 | 查库回填 + 品类校准 + 包装 OCR 优先 + AI 估算兜底 |
| 汇总 | 周报 + 月报（GLM-4-Flash）+ 满意度反馈 + 去重 + 多样性 |
| 体重 | 体重记录 + 趋势图 + 蓝牙体脂秤同步（v1/v2 协议） |
| 备份 | JSON 导出/导入 + 图片清理 + 自动备份 |
| 更新 | 应用内自更新（GitHub API + APK 下载 + 系统安装器） |
| 隐私 | EXIF 剥离 / API key 不入库 / Sentry 脱敏（默认关闭） |

## 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| 框架 | Flutter 3.44.4 | 跨平台一套代码（实际仅 Android） |
| 本地数据库 | drift + sqlite3 build hooks | 类型安全 ORM；后台 isolate 执行不阻塞 UI |
| 密钥存储 | flutter_secure_storage | Keychain / Keystore 平台原生 |
| 拍照 | image_picker | flutter.dev 一方包 |
| 图片预处理 | flutter_image_compress | 默认剥离 EXIF + 压缩 |
| 图表 | fl_chart | Material 风格图表 |
| 状态管理 | flutter_riverpod | 类型安全 + 可测 |
| 路由 | go_router | 声明式路由 |
| 视觉大模型 | Qwen-VL（首选）/ GLM-4V-Plus（备选） | 多模态识别 |
| 文本大模型 | GLM-4-Flash | 免费，周/月汇总 |
| 错误监控 | sentry_flutter | 脱敏后上报，默认关闭 |
| 蓝牙 | flutter_blue_plus | BLE 被动扫描体脂秤 |
| 中文食物库 | 《中国食物成分表》第6版（Sanotsu/china-food-composition-data） | 权威数据源 |
| 视觉规范 | Material 3 Expressive + dynamic_color | 动态取色（Android 12+） |

## 目录结构

```
lib/
  main.dart
  app.dart
  core/                 # 通用工具、主题、错误处理、Sentry 脱敏
  data/
    database/           # drift 定义 + migrations/
    repositories/       # 仓储层
    backup/             # JSON 导出导入
    bluetooth/          # BLE 体脂秤协议解析
  features/
    profile/            # 个人档案 + 热量目标
    recognize/          # 拍照识别（含 multi_dish/ + offline_queue_controller）
    dashboard/          # 今日额度看板（含 dashboard/ 子目录）
    food_library/       # 食物库
    manual_entry/       # 手动录入兜底
    weight/             # 体重记录 + 蓝牙同步
    insight/            # 长期趋势 + AI 周/月汇总
    backup/             # 备份导入导出
    update/             # 应用内自更新
    me/                 # 个人中心
  ai/                   # vision_provider + nutrition_lookup + prompts
  nutrition/            # BMR/TDEE/体脂率计算
.trae/
  specs/                # 设计文档（按里程碑组织）
  design/               # 设计稿 + 图标候选
test/                   # 单测 + widget 测试
HANDOFF.md              # 项目交接文档（跨会话记忆）
CHANGELOG.md            # 版本变更记录
```

## 安装

### 下载 APK

前往 [Releases](https://github.com/qbjsdsb/eatwise/releases) 下载最新版 APK（优先 `app-release.apk`，闪退改装 `app-debug.apk`）。

### 系统要求

- Android 12.0+（minSdk 31，动态取色 Material You 需 Android 12+）
- 约 42 MB 存储空间

### 真机安装步骤

1. 下载 `app-release.apk` 传到手机
2. 手机设置开启"允许安装未知来源应用"
3. **直接覆盖安装即可**（v0.18.0 起用固定 keystore 签名；v0.17.0 及之前需先卸载一次以切换签名）
4. 首次启动在「设置」页填入你的 Qwen API Key（视觉识别用）
5. 在「设置 → 检查更新」可一键升级到下一版

### 闪退排查

如果 `app-release.apk` 闪退，请改装 `app-debug.apk`：debug 版崩溃时会显示红色错误页 + 完整堆栈，截图发给开发者即可定位根因。

## 版本演进

| 版本 | 日期 | 核心改动 |
|---|---|---|
| v0.33.1 | 2026-07-08 | 全项目 14 维度审计 + P0/P1 修复（事务原子化/体脂秤 v1 回归/formula 重算/README 修正/CI 质量门禁） |
| v0.33.0 | 2026-07-08 | M27 蓝牙体脂秤同步（v1/v2 协议）+ 图标重设计 |
| v0.32.0 | 2026-07-07 | M26 AI 推荐满意度反馈 + 菜名归一化 |
| v0.31.0 | 2026-07-07 | M25 主题动态取色（Material You）+ 方案 D 废弃品类校准 |
| v0.24.0 | 2026-07-06 | M25 主题动态取色 + 图标精修重设计 |
| v0.22.0 | 2026-07-05 | M24 P1 清零（13 项 P1 修复 + 5 项架构重构） |
| v0.21.0 | 2026-07-05 | M22 图标精修 + 识别等待动画重构 |
| v0.20.0 | 2026-07-05 | M20 Google Lens 风图标 + 识别思考流程 UI |
| v0.18.0 | 2026-07-04 | M16 应用内自更新（13 Task TDD） |

完整变更见 [CHANGELOG.md](CHANGELOG.md)。

## 状态

✅ **v0.33.1 已发布**（2026-07-08）— [Release v0.33.1](https://github.com/qbjsdsb/eatwise/releases/tag/v0.33.1)

## 文档

- [HANDOFF.md](HANDOFF.md) — 项目交接文档（跨会话记忆载体，每个会话开始必读）
- [CHANGELOG.md](CHANGELOG.md) — 完整版本变更记录
- [.trae/specs/](.trae/specs/) — 设计文档目录（按里程碑组织）
- [docs/audit/](docs/audit/) — 项目审计报告（14 维度检查）

## 安全与隐私

- **本地存储**：数据存本地 SQLite，无后端服务器
- **EXIF 剥离**：图片上传前自动剥离 EXIF 元数据（防 GPS 泄露）
- **API key 不入库**：API key 存 flutter_secure_storage，不入数据库
- **Sentry 脱敏**：默认关闭；启用时上报前脱敏 extra + tags
- **云端识别**：拍照图片发送到 Qwen/GLM 云端 API 做识别（本地不存原图）

## 开发

```bash
# 环境要求
Flutter 3.44.4 / Dart 3.x

# 静态分析
flutter analyze

# 测试（基线：1172 passed / 3 skipped / 0 failed）
flutter test
```

### 6+1 硬约束（开发时必须遵守）

1. `android/app/build.gradle.kts` 必须保持 `isMinifyEnabled = false` + `isShrinkResources = false`（否则 R8 剥掉反射类致启动崩溃）
2. `meal_log.food_item_id` 是非空外键，哨兵 `foodItemId=0` 写库前必须替换为真实 id
3. AI 兜底三路径必须全部覆盖：`recognize_page` + `multi_dish_page` + `offline_queue_controller`
4. `per100g` 反算必须基于 `estimatedWeightGMid`（不能用 `servingG`）
5. `SecureConfigStore` 没有 `instance` 静态属性，用 `SecureConfigStore()` 或 `container.read(secureConfigStoreProvider)`
6. `initSentryAndRunApp` 参数是命名参数 `container:` + `app:`
7. `minSdk = 31`（动态取色 Material You 需 Android 12+）

详见 [HANDOFF.md](HANDOFF.md)。

## 许可证

[MIT](LICENSE)
