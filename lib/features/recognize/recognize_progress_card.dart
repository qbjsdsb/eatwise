import 'package:flutter/material.dart';

import 'recognize_controller.dart';

/// 识别进度卡片（M20 创建，M22 动画重构）
///
/// M22 改进：
/// - 进度条 TweenAnimationBuilder 平滑插值（不再 25% 整数跳跃）
/// - 状态圆圈 AnimatedContainer 颜色过渡 + AnimatedSwitcher 图标 morph
/// - done 态新增成功反馈图标（check_circle scale-in 弹性动画）
/// - 卡片 elevation 0 + surfaceContainerHigh（M3 tonal，更现代）
///
/// 监听 [RecognizeState]，展示 4 阶段进度：
/// 1. 选图（pickingImage）2. 压缩（preprocessing）
/// 3. AI 推理（recognizing）4. 查库回填（lookupNutrition）
class RecognizeProgressCard extends StatelessWidget {
  final RecognizeState currentState;

  const RecognizeProgressCard({super.key, required this.currentState});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 特殊状态：error / queued 不展示 4 阶段
    if (currentState == RecognizeState.error) {
      return _SpecialCard(
        color: cs.error,
        icon: Icons.error_outline,
        text: '识别失败',
      );
    }
    if (currentState == RecognizeState.queued) {
      return _SpecialCard(
        color: cs.primary,
        icon: Icons.cloud_off_outlined,
        text: '已加入离线队列，将在网络恢复后识别',
      );
    }

    final stages = _stageConfig(currentState);
    final completedCount =
        stages.where((s) => s.status == _StageStatus.done).length;
    final isDone = currentState == RecognizeState.done;

    return Card(
      elevation: 0, // M22：M3 tonal，无阴影更现代
      color: cs.surfaceContainerHigh, // M22：tonal surface 替代 elevation
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // M22：TweenAnimationBuilder 平滑插值进度条
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: completedCount / 4),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 4 阶段竖向列表（_StageRow 内部用 AnimatedContainer + AnimatedSwitcher）
            for (final stage in stages) _StageRow(stage: stage),
            // M22：done 态成功反馈（弹性 scale-in check_circle）
            if (isDone) ...[
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.elasticOut,
                builder: (context, scale, _) => Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.check_circle,
                    color: cs.primary,
                    size: 32,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static List<_Stage> _stageConfig(RecognizeState current) {
    const order = [
      RecognizeState.pickingImage,
      RecognizeState.preprocessing,
      RecognizeState.recognizing,
      RecognizeState.lookupNutrition,
    ];
    if (current == RecognizeState.done) {
      return order
          .map((s) => _Stage(state: s, status: _StageStatus.done))
          .toList();
    }
    if (current == RecognizeState.idle) {
      return order
          .map((s) => _Stage(state: s, status: _StageStatus.pending))
          .toList();
    }
    final currentIdx = order.indexOf(current);
    return order.asMap().entries.map((e) {
      final idx = e.key;
      final state = e.value;
      final status = idx < currentIdx
          ? _StageStatus.done
          : idx == currentIdx
              ? _StageStatus.active
              : _StageStatus.pending;
      return _Stage(state: state, status: status);
    }).toList();
  }
}

/// 单行阶段（M22：状态圆圈用 AnimatedContainer + AnimatedSwitcher 平滑过渡）
class _StageRow extends StatelessWidget {
  final _Stage stage;

  const _StageRow({required this.stage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = stage.status == _StageStatus.active;
    final isDone = stage.status == _StageStatus.done;
    final fontWeight =
        (isActive || isDone) ? FontWeight.bold : FontWeight.normal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // M22：AnimatedContainer 颜色过渡 + AnimatedSwitcher 图标 morph
          _StatusCircle(status: stage.status, colorScheme: cs),
          const SizedBox(width: 12),
          Text(stage.text, style: TextStyle(fontWeight: fontWeight)),
          const Spacer(),
          Icon(stage.icon, size: 18, color: cs.outline),
        ],
      ),
    );
  }
}

/// 状态圆圈（M22：AnimatedContainer 颜色/描边过渡 + AnimatedSwitcher 图标 morph）
class _StatusCircle extends StatelessWidget {
  final _StageStatus status;
  final ColorScheme colorScheme;

  const _StatusCircle({required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    final isActive = status == _StageStatus.active;
    final isDone = status == _StageStatus.done;
    // pending: 透明填充 + 灰描边；active/done: 紫填充 + 紫描边
    final fillColor = (isActive || isDone)
        ? colorScheme.primary
        : Colors.transparent;
    final borderColor =
        (isActive || isDone) ? colorScheme.primary : colorScheme.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    switch (status) {
      case _StageStatus.pending:
        return const SizedBox.shrink(key: ValueKey('pending'));
      case _StageStatus.active:
        return const Padding(
          key: ValueKey('active'),
          padding: EdgeInsets.all(5),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        );
      case _StageStatus.done:
        return const Icon(
          key: ValueKey('done'),
          Icons.check,
          size: 18,
          color: Colors.white,
        );
    }
  }
}

/// 特殊状态卡片（error / queued）—— M20 既有，不变
class _SpecialCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _SpecialCard({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

enum _StageStatus { pending, active, done }

class _Stage {
  final RecognizeState state;
  final _StageStatus status;

  const _Stage({required this.state, required this.status});

  String get text {
    switch (state) {
      case RecognizeState.pickingImage:
        return '选图中…';
      case RecognizeState.preprocessing:
        return '压缩图中…';
      case RecognizeState.recognizing:
        return 'AI 推理中…';
      case RecognizeState.lookupNutrition:
        return '查库回填中…';
      default:
        return '';
    }
  }

  IconData get icon {
    switch (state) {
      case RecognizeState.pickingImage:
        return Icons.camera_alt_outlined;
      case RecognizeState.preprocessing:
        return Icons.compress_outlined;
      case RecognizeState.recognizing:
        return Icons.center_focus_strong_outlined;
      case RecognizeState.lookupNutrition:
        return Icons.storage_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}
