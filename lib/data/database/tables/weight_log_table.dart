import 'package:drift/drift.dart';

/// 体重记录表
@TableIndex(name: 'idx_weight_logs_date', columns: {#date})
class WeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  RealColumn get weightKg => real()();
  // M27 v2：蓝牙体脂秤2 扩展字段（nullable，向后兼容 v1 秤无此数据）
  RealColumn get impedance => real().nullable()(); // 原始阻抗值 Ω
  RealColumn get bodyFatPct => real().nullable()(); // 体脂率 %
}
