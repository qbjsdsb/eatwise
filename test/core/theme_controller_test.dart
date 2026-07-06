// test/core/theme_controller_test.dart
// useDynamicColorProvider 单测：默认值 + set 方法
import 'package:eatwise/core/theme/theme_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('useDynamicColorProvider', () {
    test('默认值 false（保守，不改变现有用户体验）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(useDynamicColorProvider), false);
    });

    test('set(true) 更新状态为 true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(useDynamicColorProvider.notifier).set(true);
      expect(container.read(useDynamicColorProvider), true);
    });

    test('set(false) 更新状态为 false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(useDynamicColorProvider.notifier).set(true);
      container.read(useDynamicColorProvider.notifier).set(false);
      expect(container.read(useDynamicColorProvider), false);
    });
  });

  group('themeSeedProvider（回归测试，确认未破坏）', () {
    test('默认值 0xFF6750A4（M3 基线紫）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeSeedProvider), 0xFF6750A4);
    });

    test('set(0xFF2E7D32) 更新状态为自然绿', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeSeedProvider.notifier).set(0xFF2E7D32);
      expect(container.read(themeSeedProvider), 0xFF2E7D32);
    });

    test('set 非法值（0/负数/alpha=0/超 32 位）忽略', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeSeedProvider.notifier).set(0xFF2E7D32);
      // 非法值不改变状态
      container.read(themeSeedProvider.notifier).set(0);
      container.read(themeSeedProvider.notifier).set(-1);
      container.read(themeSeedProvider.notifier).set(0x00FFFFFF); // alpha=0
      container.read(themeSeedProvider.notifier).set(0x1FFFFFFFF); // 超 32 位
      expect(container.read(themeSeedProvider), 0xFF2E7D32);
    });
  });
}
