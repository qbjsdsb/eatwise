/// 小米体脂秤体脂率计算（openScale MiScaleLib 逆向公式）
///
/// 基于 openScale MiScaleLib.kt + prototux MIBCS 逆向工程，
/// 双源交叉验证（openScale Kotlin + miscale Python 逐字节一致），
/// 3 个回归夹具验证（误差 <1e-5）。
///
/// 公式输入：性别 + 年龄 + 身高 + 体重 + 阻抗（Ω）
/// 公式输出：体脂率百分比（如 23.32 表示 23.32%）
class BodyFatCalculator {
  BodyFatCalculator._();

  /// 计算体脂率百分比。
  ///
  /// [isMale] true=男 false=女
  /// [age] 年龄（岁）
  /// [heightCm] 身高（cm）
  /// [weightKg] 体重（kg）
  /// [impedance] 阻抗（Ω，1-2999），null 或 <=0 表示未测/无效（提前下秤）
  ///
  /// 返回体脂率百分比（5-75），impedance 无效时返回 null。
  static double? calcBodyFat({
    required bool isMale,
    required int age,
    required double heightCm,
    required double weightKg,
    required double? impedance,
  }) {
    // 边界：impedance 无效（提前下秤/未测）→ 返回 null
    if (impedance == null || impedance <= 0) return null;
    if (weightKg <= 0 || heightCm <= 0) return null;

    // 第一步：LBM 系数
    // lbmCoeff = 0.0009058×h² + 0.32×w + 12.226 − 0.0068×imp − 0.0542×age
    double lbmCoeff = (heightCm * 9.058 / 100.0) * (heightCm / 100.0);
    lbmCoeff += weightKg * 0.32 + 12.226;
    lbmCoeff -= impedance * 0.0068;
    lbmCoeff -= age * 0.0542;

    // 第二步：lbmSub（性别 + 年龄扣除常数）
    double lbmSub;
    if (!isMale && age <= 49) {
      lbmSub = 9.25;
    } else if (!isMale && age > 49) {
      lbmSub = 7.25;
    } else {
      lbmSub = 0.8;
    }

    // 第三步：coeff（性别 + 体重 + 身高校正）
    double coeff = 1.0;
    if (isMale && weightKg < 61.0) {
      coeff = 0.98;
    } else if (!isMale && weightKg > 60.0) {
      coeff = 0.96;
      if (heightCm > 160.0) coeff *= 1.03;
    } else if (!isMale && weightKg < 50.0) {
      coeff = 1.02;
      if (heightCm > 160.0) coeff *= 1.03;
    }

    // 第四步：体脂率
    // bodyFat% = (1 − ((lbmCoeff − lbmSub) × coeff) / weight) × 100
    double bodyFat =
        (1.0 - (((lbmCoeff - lbmSub) * coeff) / weightKg)) * 100.0;

    // 第五步：clamp（openScale >63→75 哨兵 + miscale [5,75] 上下限）
    if (bodyFat > 63.0) bodyFat = 75.0;
    if (bodyFat < 5.0) bodyFat = 5.0;
    if (bodyFat > 75.0) bodyFat = 75.0;
    return bodyFat;
  }
}
