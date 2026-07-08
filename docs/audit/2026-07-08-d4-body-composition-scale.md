# P0-D4: 体脂秤 v2 + 体脂率 + BMR 业务正确性审查

## 检查日期 / HEAD commit

- 检查日期：2026-07-08
- HEAD commit：`bb308735`（fix(build): 修复 build_runner 失败——sqlparser 0.44.5 override + 重新生成 database.g.dart）
- 审查范围：v0.32.0 M27 v2 小米体脂秤2（XMTZC05HM）+ 体脂率 + BMR 自动升级
- 相关 commit：`c55eaf6` / `8225d86` / `3e30314` / `795a447` / `4546134` / `1fbe9b6` / `4fdbdc9`

## v2 协议解析审查（含 v1 vs v2 对比表）

### 文件
- `lib/data/bluetooth/mi_scale_parser.dart`
- `test/mi_scale_parser_test.dart`

### v1 vs v2 协议对比

| 维度 | v1（XMTZC04HM 体重秤2） | v2（XMTZC05HM 体脂秤2 / XMTZC02HM 体脂秤1代） |
|---|---|---|
| Service UUID | 0x181D（Weight Scale） | 0x181B（Body Composition Service） |
| payload 长度 | 10 字节 | 13 字节 |
| control byte 数 | 1（byte0） | 2（byte0 + byte1） |
| weight raw 偏移 | byte[1-2]（LE uint16） | byte[11-12]（LE uint16） |
| impedance | 无 | byte[9-10]（LE uint16，仅 measurementComplete 时有效） |
| lbs flag | byte0 bit0 | byte0 bit0（不变） |
| jin flag | byte0 bit4 | **byte1 bit6**（位移） |
| stabilized flag | byte0 bit5 | **byte1 bit5**（位移） |
| removed flag | byte0 bit7 | **byte1 bit7**（位移） |
| measurementComplete | 无 | byte1 bit1（阻抗测量完成） |
| 单位换算 kg | raw / 200.0 | raw / 200.0（一致） |
| 单位换算 jin | raw / 100.0 × 0.5 | raw / 100.0 × 0.5（一致） |
| 单位换算 lbs | raw / 100.0 × 0.453592 | raw / 100.0 × 0.453592（一致） |
| packetId | 全 10 字节 hex（含时间戳） | 6 字节 hex（剔除时间戳 bytes 2-8） |
| isEffective | stabilized && !removed | stabilized && !removed（一致） |

### 解析正确性验证

1. **byte 偏移**：v2 weight raw 在 `payload[11] | (payload[12] << 8)` ✓；impedance 在 `payload[9] | (payload[10] << 8)` ✓
2. **control bit 解析**：v2 `isLbs = c0 & 0x01`、`isJin = c1 & 0x40`、`isStabilized = c1 & 0x20`、`weightRemoved = c1 & 0x80`、`measurementComplete = c1 & 0x02` ✓ 与文档位移一致
3. **单位判定顺序**：v2 先判 jin 再判 lbs（v1 先 lbs 再 jin）。两者均用 bitmask 而非枚举匹配，不会漏 0x62 等包 ✓。注意：v1/v2 单位判定顺序不同，但因 jin/lbs bit 不可能同时置位，顺序差异无实际影响
4. **measurementComplete 守卫 impedance**：仅 `measurementComplete=true` 时才读 impedance，且额外校验 `imp > 0 && imp < 3000`（ESPHome 有效范围）✓ 双重保护
5. **isEffective 双重保护**：`isStabilized && !weightRemoved` ✓ 学 ble_monitor，防抖动值与下秤包误存
6. **packetId 去重**：
   - v2 剔除时间戳字节（bytes 2-8），保留 control + impedance + weight ✓ 合理，避免每秒帧被当新包
   - v1 全 payload hex（含时间戳 bytes 3-9）⚠️ 见 P2-3

### v1/v2 差异合理性
- v2 新增 impedance + measurementComplete 字段，`MiScaleMeasurement` 类用 nullable + 默认值兼容 v1（v1 impedance=null, measurementComplete=false）✓
- v2 jin flag 位移到 byte1 bit6 已正确实现，测试样本 F（c1=0x60）验证通过 ✓
- 单位换算系数 v1/v2 一致（kg /200, jin ×0.5, lbs ×0.453592），修复了 ESPHome 的 0.6 斤系数 bug ✓

## BodyFatCalculator 公式验证（含边界 case）

### 文件
- `lib/nutrition/body_fat_calculator.dart`
- `test/nutrition/body_fat_calculator_test.dart`

### 公式逐步验证（手工复核 3 个 openScale 夹具）

**夹具1：男 30 180cm 80kg 500Ω → 期望 23.32%**
```
lbmCoeff = 0.0009058×180² + 0.32×80 + 12.226 − 0.0068×500 − 0.0542×30
         = 29.348 + 25.6 + 12.226 − 3.4 − 1.626 = 62.148
lbmSub（男）= 0.8
coeff（男<61kg? 80>61 否）= 1.0
bodyFat = (1 − ((62.148 − 0.8) × 1.0) / 80) × 100
        = (1 − 0.76685) × 100 = 23.315% ✓（误差 <0.01）
```

**夹具2：女 28 165cm 60kg 520Ω → 期望 30.36%**
```
lbmCoeff = 24.665 + 19.2 + 12.226 − 3.536 − 1.518 = 51.037
lbmSub（女≤49）= 9.25
coeff（女>60? 60不>60 否；女<50? 60不<50 否）= 1.0
bodyFat = (1 − (51.037 − 9.25) / 60) × 100 = 30.355% ✓
```

**夹具3：男 45 175cm 95kg 430Ω → 期望 32.42%**
```
lbmCoeff = 27.740 + 30.4 + 12.226 − 2.924 − 2.439 = 65.003
lbmSub（男）= 0.8
coeff（男<61? 95>61 否）= 1.0
bodyFat = (1 − (65.003 − 0.8) / 95) × 100 = 32.418% ✓
```

三个夹具全部通过，公式实现与 openScale MiScaleLib 逆向一致 ✓

### lbmCoeff 展开验证
代码：`(heightCm * 9.058 / 100.0) * (heightCm / 100.0)`
= `9.058 × heightCm² / 10000` = `0.0009058 × heightCm²` ✓ 与文档系数一致

### coeff 分支覆盖
- 男 <61kg → 0.98 ✓（测试样本"男性 weight<61"覆盖）
- 女 >60kg + h>160 → 0.96 × 1.03 = 0.9888 ✓（测试样本覆盖）
- 女 <50kg + h>160 → 1.02 × 1.03 = 1.0506 ✓（测试样本覆盖）
- 男 ≥61kg / 女 50-60kg → 1.0（默认）✓

### 边界 case 验证
| 边界 | 代码处理 | 测试覆盖 |
|---|---|---|
| impedance=null | 返回 null ✓ | ✓ |
| impedance=0 | 返回 null（`<=0` 守卫）✓ | ✓ |
| impedance<0 | 返回 null ✓ | ✓ |
| weightKg=0 | 返回 null（除零保护）✓ | ✓ |
| heightCm=0 | 返回 null（`<=0` 守卫）✓ | ✗ 未测 |
| age=0 | 公式合法（`- 0.0542×0`），不报错 | ✗ 未测（但 0 岁无生理意义，BodyFatCalculator 不校验 age 合理性，由调用方 profile 保证） |
| impedance=2999（上界）| 合法传入，公式计算 | ✓（clamp 测试用） |
| bodyFat>63 | clamp → 75（哨兵）| ⚠️ 测试未真正触发（见 P2-4） |
| bodyFat<5 | clamp → 5 | ⚠️ 测试未真正触发 |

### clamp >63→75 合理性评估
- **openScale 原实现**：`if bodyFat > 63 return 75`（哨兵值标记"无效但保留"）
- **本实现**：`if (bodyFat > 63.0) bodyFat = 75.0; if (<5) =5; if (>75) =75;` ✓ 与 openScale 一致
- **合理性**：>63% 体脂率在生理上极不可能（男性必需脂肪 2-5%，女性 10-13%，临床肥胖阈值男性 25%+ / 女性 32%+；已知最高记录约 50%+）。openScale 用 75 作为"测量异常但保留数据"的哨兵，让 UI 能显示而非崩溃/null
- **争议点（P2-2）**：63.01 → 75 产生 12 个百分点的突兀跳变，UI 显示 75% 会让用户困惑。更友好做法是返回 null + UI 提示"体脂率异常请重测"，但会偏离 openScale 行为。当前实现可接受，建议加注释说明哨兵语义

## BMR 自动升级审查

### 文件
- `lib/features/profile/nutrition_calculator.dart`（bmrMifflin / bmrKatch 纯函数）
- `lib/nutrition/tdee_calibrator.dart`（runAndApply 读 profile.formula 分支）
- `lib/features/profile/profile_page.dart`（_save 主路径）
- `lib/features/weight/weight_page.dart`（_save 蓝牙路径）
- `test/features/profile_save_formula_switch_test.dart`
- `test/nutrition/tdee_calibrator_formula_branch_test.dart`

### 公式实现验证
- **Mifflin-St Jeor**：`10×w + 6.25×h - 5×age + (男5/女-161)` ✓ AND 官方推荐
- **Katch-McArdle**：`370 + 21.6 × leanMass`，`leanMass = w × (1 - bodyFat/100)` ✓ 标准公式
- 测试验证：男 70kg 15% → Katch=1655.2；同参数 Mifflin=1648.75 ✓ Katch 对精瘦人群略高

### formula 切换逻辑（profile_page 主路径）
```
hasBodyFat = bodyFat != null && bodyFat > 0
formula = hasBodyFat ? 'katch' : 'mifflin'
oldFormula = existing.formula
formulaChanged = oldFormula != formula
update(..., formula, tdeeAdjustmentKcal: formulaChanged ? 0 : existing.tdeeAdjustmentKcal)
if (bodyFat == null) clearBodyFatPct()
```
- 有 bodyFatPct → Katch + formula='katch' ✓
- 无 bodyFatPct → Mifflin + formula='mifflin' ✓
- formula 切换时重置 tdeeAdjustmentKcal=0 ✓ 防跨公式污染（Katch/Mifflin BMR 基线不同，旧 adjustment 不适用）
- profile_page 重算 dailyCalorieTarget 并写入 ✓

### formula 切换逻辑（weight_page 蓝牙路径）
```
hasBodyFat = _pendingBodyFat != null && _pendingBodyFat! > 0
newFormula = hasBodyFat ? 'katch' : 'mifflin'
formulaChanged = oldFormula != newFormula
update(weightKg, bodyFatPct: _pendingBodyFat, formula: newFormula,
       tdeeAdjustmentKcal: formulaChanged ? 0 : null)
if (_pendingBodyFat == null) clearBodyFatPct()
```
- formula 切换重置 tdeeAdjustmentKcal ✓
- ⚠️ **见 P1-2**：weight_page 不重算 dailyCalorieTarget

### tdee_calibrator.runAndApply 分支
```
bmr = (profile.formula == 'katch' && profile.bodyFatPct != null && profile.bodyFatPct! > 0)
    ? bmrKatch(...) : bmrMifflin(...)
```
- formula=katch + bodyFatPct>0 → Katch ✓
- formula=mifflin → Mifflin（即使有体脂率）✓ 老用户回归
- formula=katch 但 bodyFatPct=null → 兜底 Mifflin ✓ 防御性

### 切换时机覆盖
| 时机 | 触发 | 处理 |
|---|---|---|
| profile update（手动编辑档案）| profile_page._save | 重算 target + formula + 重置 adjustment ✓ |
| weight_log 写入（蓝牙秤）| weight_page._save | 更新 formula + 重置 adjustment，**不重算 target** ⚠️ P1-2 |
| 手动清除体脂率 | profile_page._save（bodyFat=null → clearBodyFatPct）| formula 降级 mifflin ✓ |
| 蓝牙 v1 秤录体重（无阻抗）| weight_page._save（_pendingBodyFat=null → clearBodyFatPct）| ⚠️ 见 P2-1 |

## ProfileRepository clearBodyFatPct 正确性

### 文件
- `lib/data/repositories/profile_repository.dart`

### 验证
- `clearBodyFatPct()` 用 `ProfilesCompanion(bodyFatPct: Value(null))` 显式置空 ✓
- 解决了 `update()` 的 `null=Value.absent`（不更新）语义无法置空 nullable 字段的限制 ✓
- 调用方负责同步 formula：clearBodyFatPct 后 formula 必须设为 'mifflin'（否则 tdee_calibrator 的 `formula=='katch' && bodyFatPct!=null` 兜底 Mifflin，功能正确但 DB 状态语义不一致）
- profile_page._save：clearBodyFatPct 同时 update(formula: 'mifflin') ✓
- weight_page._save：clearBodyFatPct 同时 update(formula: 'mifflin') ✓

### BMR 自动降级验证
显式置空 bodyFatPct 后：
1. profile_page 路径：formula='mifflin' + clearBodyFatPct → 下次 tdee_calibrator 读 formula=mifflin → Mifflin BMR ✓
2. weight_page 路径：同上 ✓

## weight_page v2 接入审查

### 文件
- `lib/features/weight/weight_page.dart`

### impedance 捕获时机
`_onMeasurement` 逻辑：
```dart
final isV2WithImpedance = m.measurementComplete || m.impedance != null;
if (!isV2WithImpedance && m.isStabilized) {
  _pendingStabilized = m;  // 暂存，等 impedance
  return;
}
_handleCapture(m);
```
- v2 正常流程：stabilized（暂存）→ measurementComplete（impedance 就绪）→ 立即 _handleCapture ✓
- v2 阻抗失败/提前下秤：stabilized 暂存 → 15s 超时 → _startBleScan 末尾用 _pendingStabilized 兜底（无 impedance，bodyFat=null）✓ 设计合理
- ⚠️ **v1 秤（P1-1）**：v1 measurementComplete 恒 false + impedance 恒 null → isV2WithImpedance=false → v1 stabilized 帧也被暂存，需等 15s 超时才预填。注释"v1 协议 measurementComplete 恒 false，直接用 stabilized"与代码矛盾。根因：MiScaleMeasurement 无 protocol 字段，无法区分"v1 stabilized（应立即捕获）"和"v2 stabilized-but-no-impedance（应等）"

### startScan 时序
1. `_enableBleSync`：批量请求权限（bluetoothScan + bluetoothConnect + location）→ 永久拒绝引导设置 → 普通拒绝 error → 系统定位开关检查（华为系依赖）→ `_startBleScan` ✓
2. `_startBleScan`：扫描冷却检查 → 蓝牙适配器状态检查（Android 主动 turnOn）→ 懒初始化 scanner → 订阅 measurementStream → startScan(timeout 15s) → `await FlutterBluePlus.isScanning.where((v) => v == false).first` 显式等扫描结束 ✓ 修复了"未找到"toast 误弹
3. 扫描结束未捕获 → 检查 _pendingStabilized 兜底 → 否则提示"未找到体重秤"✓

### 系统定位
- `Permission.location.serviceStatus` 检查 ✓ 国产 ROM（华为 HarmonyOS/EMUI）BLE 扫描强依赖系统定位开关
- 未开启时 toast 提示 + openAppSettings ✓
- 注意：didChangeAppLifecycleState resumed → _startBleScan 不重新检查定位（若用户后台关定位，resumed 时 startScan 会失败，catch 设 error）。可接受

### 30s 冷却
- 5 分钟窗口：`>=3 次`拒绝（MIUI 熔断阈值）✓
- 30 秒短窗：`>=4 次`拒绝（注释说 AOSP 5次/30秒，代码用 >=4 即允许 3 次，比 AOSP 更保守）✓

### 体脂率 UI 显示
- 捕获 toast：`已捕获 X kg，体脂 Y%` / `已捕获 X kg，请确认`（impedance 无效只显示体重）✓
- 折线图 tooltip：有 bodyFatPct 加显 `体脂 Y%` ✓
- 体重记录 ListTile title：有 bodyFatPct 加显 `· 体脂 Y%` ✓

### _save 同步 profile
```
1. 写 weight_log（含 impedance + bodyFatPct）
2. update(weightKg, bodyFatPct, formula, tdeeAdjustmentKcal: formulaChanged ? 0 : null)
3. if (_pendingBodyFat == null) clearBodyFatPct()
4. TdeeCalibrator.runAndApply（tdeeAutoCalib 开启时）
5. _load + RefreshBus.notify
```
- ✓ 写 weight_log + 同步 profile.weightKg（dashboard 宏量随体重更新）
- ✓ formula 切换重置 tdeeAdjustmentKcal
- ⚠️ **P1-2**：不重算 dailyCalorieTarget（设计注释说"BMR 重算只在用户主动编辑档案时做"），但 formula 切换是重大变化，理应重算
- ⚠️ **P2-1**：_pendingBodyFat==null 时 clearBodyFatPct 会清除用户已有的体脂率

## MiScaleScanner 双 UUID 路由

### 文件
- `lib/data/bluetooth/mi_scale_scanner.dart`

### 验证
- 双 UUID 常量：`_v1Uuid = Guid('181D')` + `_v2Uuid = Guid('181B')` ✓
- 路由逻辑：
  ```
  if (v1Payload != null && v1Payload.length == 10) → parseV1
  else if (v2Payload != null && v2Payload.length == 13) → parseV2
  ```
  - length 硬过滤防误判 ✓
  - v1 优先（理论上不会同时广播两 UUID）✓
- `isClosed` 守卫：`if (_controller.isClosed) return;` 防 dispose 竞态崩溃 ✓
- `onError` 日志：`debugPrint('MiScaleScanner onScanResults error: $e')` ✓ 医疗场景不留静默
- `_lastPacketId` 去重 ✓（v2 有效，v1 因 packetId 含时间戳失效，见 P2-3）
- `isEffective` 过滤：stabilized && !removed ✓
- 无过滤扫描 + Dart 软过滤 + AndroidScanMode.lowLatency ✓

## 数据层 + 迁移审查

### 文件
- `lib/data/database/tables/weight_log_table.dart`
- `lib/data/database/tables/profile_table.dart`
- `lib/data/database/database.dart`（schema v5 迁移）
- `lib/data/repositories/weight_log_repository.dart`

### weight_log 表扩展
```dart
RealColumn get impedance => real().nullable()();   // 原始阻抗值 Ω
RealColumn get bodyFatPct => real().nullable()();  // 体脂率 %
```
- nullable ✓ 向后兼容 v1 秤无此数据
- WeightLogRepository.insert / update 支持 impedance + bodyFatPercent ✓

### profile 表
- `bodyFatPct` nullable ✓（schema 早期已有，M27 v2 启用）
- `formula` text（'mifflin' / 'katch'）✓
- `tdeeAdjustmentKcal` integer withDefault(0) ✓

### schema v5 迁移
```dart
if (from < 5) {
  await m.addColumn(weightLogs, weightLogs.impedance);
  await m.addColumn(weightLogs, weightLogs.bodyFatPct);
}
```
- addColumn nullable ✓ 旧数据自动 NULL
- 迁移幂等（from<5 守卫）✓
- onCreate（beforeOpen wasCreated）创建全表含新字段 ✓
- 无数据回填需求（新字段 nullable）✓

## 测试覆盖评估

### parser 测试（mi_scale_parser_test.dart）
- v1：8 个测试（7 hex 样本 + 长度错误 + 去重）✓ 覆盖 kg/jin/lbs × stabilized/removed 组合
- v2：8 个测试（A-F 样本 + 长度错误 + 去重）✓ 覆盖 measurementComplete/impedance/jin/lbs/stabilized
- v2 样本 A（0xA6 removed+complete）验证下秤包 isEffective=false ✓
- v2 样本 B（0x20 stabilized 无阻抗）验证 impedance=null ✓
- v2 样本 C（0x22 stabilized+complete）验证理想帧 impedance=480 ✓
- 缺失：impedance 边界值（0 / 2999 / 3000）未在 parser 层测试（calculator 层有 imp=0 测试）

### BodyFatCalculator 测试（body_fat_calculator_test.dart）
- 14 个测试 ✓：3 openScale 夹具 + 5 边界（imp null/0/负/weight=0）+ 2 clamp + 4 性别年龄体重分支
- ⚠️ **P2-4**：clamp 测试用"软断言"（`<=75` / `>=5`），实际输入算出的 bodyFat 在 32-45% 范围未越界，未真正触发 >63→75 和 <5→5 分支
- 缺失：heightCm=0 边界、age=0 边界

### BMR formula 切换测试
- `profile_save_formula_switch_test.dart`：5 个测试 ✓ 覆盖 Katch/Mifflin 选择 + formula 变化检测 + tdeeAdjustmentKcal 重置
- `tdee_calibrator_formula_branch_test.dart`：3 个测试 ✓ 覆盖 formula=katch+mifflin+兜底分支
- ⚠️ **P2-7**：均为纯逻辑测试（字符串比较 + 直接调 NutritionCalculator），未集成测试 ProfileRepository.update + clearBodyFatPct 实际写库 + tdee_calibrator 读取的端到端流程

### weight_page 测试（weight_page_test.dart）
- 仅 4 个 M14 PopScope 测试 ✓（输入后返回弹确认 / 未输入放行 / 放弃退出 / 继续编辑保留）
- ⚠️ **P2-6**：未覆盖 v1/v2 捕获时序、_onMeasurement 暂存逻辑、formula 切换、_save 同步 profile、clearBodyFatPct 等关键路径

## 发现的问题（P0/P1/P2 分级）

### P0（阻断级）：无

### P1（高优先级）

#### P1-1：weight_page v1 秤 stabilized 帧被暂存，需等 15s 才预填（v0.31.0 行为回归）
- **文件**：`lib/features/weight/weight_page.dart` 第 254-268 行 `_onMeasurement`
- **现象**：v1 秤（XMTZC04HM）stabilized 帧到来时，因 `measurementComplete=false` 且 `impedance=null`，`isV2WithImpedance=false`，进入 `_pendingStabilized = m; return;` 暂存分支，不会立即 `_handleCapture`。需等 15s startScan 超时后由 `_startBleScan` 末尾兜底 `_handleCapture(_pendingStabilized!)`
- **注释矛盾**：代码注释写"v1 协议 measurementComplete 恒 false，直接用 stabilized"，但实际逻辑把 v1 stabilized 也暂存了
- **影响**：v1 秤用户体验回归——v0.31.0 stabilized 立即预填，v0.32.0 需等 15s
- **根因**：`MiScaleMeasurement` 无 protocol 字段（v1/v2 标记），无法区分"v1 stabilized（应立即捕获）"和"v2 stabilized-but-no-impedance（应等 impedance）"
- **修复建议**：`MiScaleMeasurement` 增加 `final bool isV2` 字段，parseV1 设 false / parseV2 设 true；`_onMeasurement` 改为：v1 stabilized 立即捕获，v2 stabilized-but-no-impedance 暂存等 impedance

#### P1-2：weight_page._save formula 切换时不重算 dailyCalorieTarget，导致 target 与 formula 不一致
- **文件**：`lib/features/weight/weight_page.dart` 第 734-744 行 `_save`
- **现象**：蓝牙秤录入体脂率后 formula 从 mifflin 切到 katch，tdeeAdjustmentKcal 重置为 0，但 `dailyCalorieTarget` 未重算（保留旧 mifflin 公式 + 旧 adjustment 算出的值）
- **对比**：`profile_page._save` 会重算 target（第 468-475 行），weight_page 不会
- **设计注释**："BMR 重算只在用户主动编辑档案时做，日常体重波动通过 TDEE 校准 adjustmentKcal 微调"——但 formula 切换不是"日常体重波动"，是 BMR 公式基线的根本变化
- **影响**：profile 状态不一致（formula=katch 但 dailyCalorieTarget 仍是 mifflin 基线值）。dashboard 显示的 target 与实际 formula 不匹配，直到下次 TDEE 校准且 `adjustmentKcal != 0` 才重算。若校准返回 0（数据不足 / 在阈值内），target 永远不重算
- **修复建议**：weight_page._save 中 formula 切换时，用新 formula + 新 weightKg + 新 bodyFatPct 重算 BMR/TDEE/dailyCalorieTarget 并写入

### P2（中优先级）

#### P2-1：v1 秤录体重会清除用户已有的体脂率（设计争议）
- **文件**：`lib/features/weight/weight_page.dart` 第 742-744 行
- **现象**：`if (_pendingBodyFat == null) await profileRepo.clearBodyFatPct();`——v1 秤无阻抗，`_pendingBodyFat=null`，会清除用户之前手动录入或 v2 秤录入的体脂率，formula 随之降级 mifflin
- **场景**：用户昨天用体脂秤2录入体脂率 23%（formula=katch），今天用体重秤2（v1）称体重 → 体脂率被清空 → formula 降级 mifflin
- **争议**：设计上"每次录体重是当前体成分快照"则合理（v1 无体脂率数据视为"不再有"）；但用户预期可能是"v1 只更新体重，不动体脂率"
- **建议**：明确产品意图。若 v1 不应清除体脂率，改为仅在 `_pendingBodyFat != null` 时更新 bodyFatPct，不调 clearBodyFatPct

#### P2-2：BodyFatCalculator clamp >63→75 产生突兀跳变
- **文件**：`lib/nutrition/body_fat_calculator.dart` 第 67 行
- **现象**：`if (bodyFat > 63.0) bodyFat = 75.0;`——63.01% 直接跳到 75%（跳变 12 个百分点）
- **合理性**：与 openScale 原实现一致（哨兵值标记"无效但保留"），生理上 >63% 不可能
- **建议**：加注释说明哨兵语义；或改为返回 null + UI 提示"体脂率异常请重测"（更友好但偏离 openScale）

#### P2-3：v1 packetId 含时间戳字节，scanner 去重失效
- **文件**：`lib/data/bluetooth/mi_scale_parser.dart` 第 53-55 行（v1 packetId = 全 10 字节 hex）
- **现象**：v1 秤每秒发的 stabilized 帧时间戳不同 → packetId 不同 → scanner `_lastPacketId` 去重无效，每帧都推送
- **影响**：功能无影响（_pendingStabilized 覆盖 + isEffective 过滤 + 最终 _handleCapture 一次），但 _lastPacketId 去重对 v1 形同虚设
- **对比**：v2 packetId 剔除时间戳（bytes 2-8），去重有效 ✓
- **建议**：v1 packetId 也剔除时间戳字节（bytes 3-9），保留 control + weight raw

#### P2-4：clamp >63→75 和 <5→5 分支无真正触发测试
- **文件**：`test/nutrition/body_fat_calculator_test.dart` 第 68-84 行
- **现象**：clamp 测试用"软断言"（`<=75` / `>=5`），实际输入算出的 bodyFat 在 32-45% 范围，未越界
  - "体脂率超 75"测试输入（男 80岁 150cm 30kg 2999Ω）算出约 45.5%，不触发 >63
  - "体脂率低于 5"测试输入（男 20岁 190cm 120kg 1Ω）算出约 32.1%，不触发 <5
- **建议**：构造真正触发越界的输入（如女 80岁 140cm 40kg 2999Ω 算出约 72.5% 触发 >63→75）

#### P2-5：profile_page._save bodyFat=0.0 时 DB 存 0.0 而非 null
- **文件**：`lib/features/profile/profile_page.dart` 第 438-439、550-552 行
- **现象**：用户在体脂率输入框填 0，`bodyFat = 0.0`（非 null）→ `hasBodyFat = 0.0 > 0 = false` → formula=mifflin，但 `update(bodyFatPct: 0.0)` 写入 0.0，`if (bodyFat == null)` 不成立 → 不调 clearBodyFatPct → DB 存 bodyFatPct=0.0
- **影响**：功能正确（hasBodyFat 和 tdee_calibrator 都用 `>0` 判断，0.0 走 mifflin），但 DB 状态语义不干净（应为 null 表示"无体脂率"）
- **建议**：`bodyFat == 0.0` 时也调 clearBodyFatPct，或输入框校验禁止 0

#### P2-6：weight_page_test 未覆盖 v2 关键路径
- **文件**：`test/features/weight_page_test.dart`
- **现象**：仅 4 个 M14 PopScope 测试，未覆盖：_onMeasurement v1/v2 捕获时序、_pendingStabilized 暂存兜底、formula 切换、_save 同步 profile、clearBodyFatPct、impedance 捕获、体脂率 UI 显示
- **建议**：补充 widget 测试或集成测试覆盖上述路径

#### P2-7：BMR formula 切换测试为纯逻辑测试，无端到端集成
- **文件**：`test/features/profile_save_formula_switch_test.dart`、`test/nutrition/tdee_calibrator_formula_branch_test.dart`
- **现象**：测试直接用字符串字面量模拟 formula 切换（`const oldFormula = 'mifflin'`），直接调 NutritionCalculator，未走 ProfileRepository.update + clearBodyFatPct 实际写库 + tdee_calibrator 读取的真实流程
- **建议**：补充集成测试，用真实 drift memory DB 验证 formula 切换 → DB 状态 → tdee_calibrator 读取的端到端一致性

## 结论

v0.32.0 M27 v2 体脂秤 + 体脂率 + BMR 自动升级的核心业务逻辑**总体正确**：
- ✓ v2 协议解析（byte 偏移 / bitmask / impedance 守卫 / packetId 去重）与 openScale/ble_monitor 双源一致
- ✓ BodyFatCalculator 公式经 3 个 openScale 夹具手工复核，误差 <0.01%
- ✓ BMR 自动升级（Katch/Mifflin 切换 + tdeeAdjustmentKcal 重置）在 profile_page 主路径正确
- ✓ clearBodyFatPct 解决了 drift nullable 字段置空语义
- ✓ MiScaleScanner 双 UUID 路由 + isClosed 守卫 + onError 日志
- ✓ schema v5 迁移幂等 + nullable 向后兼容

**无 P0 阻断问题**。

**2 个 P1 需修复**：
- P1-1：v1 秤 stabilized 帧被暂存导致 15s 预填延迟（v0.31.0 行为回归，根因缺 protocol 字段）
- P1-2：weight_page formula 切换时不重算 dailyCalorieTarget，导致 target 与 formula 不一致

**7 个 P2 建议改进**：v1 录体重清除体脂率的设计争议、clamp 跳变体验、v1 packetId 去重失效、clamp 测试未真正触发、bodyFat=0 DB 语义、weight_page 测试覆盖不足、formula 切换缺端到端集成测试。

**建议优先级**：P1-1（v1 用户体验回归，影响 v0.31.0 已有用户）> P1-2（数据一致性，影响 dashboard 显示）> P2-1（设计争议需产品决策）> P2-4/P2-6/P2-7（测试覆盖补强）> P2-2/P2-3/P2-5（小优化）。
