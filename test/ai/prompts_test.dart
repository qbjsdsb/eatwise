import 'package:eatwise/ai/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

/// H5+H6 修复：prompt 规则 6 与 validator 容忍度一致性
/// - H5: prompt 规则 6 加酒精例外（啤酒/烈酒/葡萄酒热量来自酒精 7kcal/g 不在 Atwater 4/9/4 内）
/// - H6: prompt 规则 6 容忍度与 validator _calorieTolerance 一致（10%）
void main() {
  group('H5+H6 prompt 规则 6 与 validator 一致性', () {
    test('H6: prompt 规则 6 容忍度与 validator 一致（10%）', () {
      // validator _calorieTolerance = 0.10（10%）
      // prompt 规则 6 应说"误差<10%"，避免 AI 输出 6-9% 偏差时 prompt 违规但 validator 放行
      expect(Prompts.systemPrompt, contains('10%'),
          reason: 'prompt 规则 6 应说 10% 与 validator _calorieTolerance=0.10 一致');
      // 反向验证：不应再说 5%（避免残留旧文案）
      expect(Prompts.systemPrompt.contains('误差<5%'), false,
          reason: 'prompt 不应再说 误差<5%（与 validator 10% 不一致）');
    });

    test('H5: prompt 规则 6 包含酒精例外说明', () {
      // 啤酒/烈酒/葡萄酒热量主要来自酒精 7kcal/g，不在 Atwater 4/9/4 系数内
      // 规则 6 那一行应明确说明酒精例外，避免模型强行自洽致热量低估
      // （不能只埋在示例注里——模型遵循规则不遵循示例注）
      final rule6Line = Prompts.systemPrompt.split('\n').firstWhere(
            (line) => line.trimLeft().startsWith('6. 自洽校验'),
            orElse: () => '',
          );
      expect(rule6Line, contains('酒精'),
          reason: '规则 6 那一行应明确说明酒精例外（酒精 7kcal/g 不在 Atwater 4/9/4 内）');
    });
  });
}
