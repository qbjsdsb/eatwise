import 'package:flutter/material.dart';

import 'recognize_controller.dart';

/// 识别进度卡片（M20：把"识别中…"升级为 4 阶段逐步打勾 + 顶部进度条）
///
/// 监听 [RecognizeState]，展示 4 阶段进度：
/// 1. 选图（pickingImage）
/// 2. 压缩（preprocessing）
/// 3. AI 推理（recognizing）
/// 4. 查库回填（lookupNutrition）
///
/// 特殊状态：
/// - done：4 阶段全 done，进度 4/4（瞬间消失，跳转校准页）
/// - error：显示"识别失败"特殊文案，不展示 4 阶段
/// - queued：显示"已加入离线队列"特殊文案，不展示 4 阶段
/// - idle：4 阶段全 pending（不应出现，loading 不显示）
class RecognizeProgressCard extends StatelessWidget {
  final RecognizeState currentState;

  const RecognizeProgressCard({super.key, required this.currentState});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 特殊状态：error / queued 不展示 4 阶段，只展示特殊文案
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

    // 正常进度态：4 阶段列表 + 顶部进度条
    final stages = _stageConfig(currentState);
    final completedCount =
        stages.where((s) => s.status == _StageStatus.done).length;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部进度条（value = completedCount / 4）
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: completedCount / 4,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
            const SizedBox(height: 20),
            // 4 阶段竖向列表
            for (final stage in stages) _StageRow(stage: stage),
          ],
        ),
      ),
    );
  }

  /// 状态判定：根据 current 状态返回 4 阶段的状态列表
  static List<_Stage> _stageConfig(RecognizeState current) {
    const order = [
      RecognizeState.pickingImage,
      RecognizeState.preprocessing,
      RecognizeState.recognizing,
      RecognizeState.lookupNutrition,
    ];

    // done 态：4 阶段全 done
    if (current == RecognizeState.done) {
      return order
          .map((s) => _Stage(state: s, status: _StageStatus.done))
          .toList();
    }

    // idle 态：4 阶段全 pending
    if (current == RecognizeState.idle) {
      return order
          .map((s) => _Stage(state: s, status: _StageStatus.pending))
          .toList();
    }

    // 正常态：按 order 顺序判定
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

/// 单行阶段（状态圆圈 + 文案 + 阶段图标）
class _StageRow extends StatelessWidget {
  final _Stage stage;

  const _StageRow({required this.stage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = stage.status == _StageStatus.active;
    final isDone = stage.status == _StageStatus.done;
    // 当前 + 已完成阶段文案加粗，未到阶段默认字重
    final fontWeight =
        (isActive || isDone) ? FontWeight.bold : FontWeight.normal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // 状态圆圈（28×28）
          _StatusCircle(status: stage.status, colorScheme: cs),
          const SizedBox(width: 12),
          // 文案
          Text(
            stage.text,
            style: TextStyle(fontWeight: fontWeight),
          ),
          const Spacer(),
          // 阶段图标（灰色，仅装饰）
          Icon(stage.icon, size: 18, color: cs.outline),
        ],
      ),
    );
  }
}

/// 状态圆圈：未到灰色描边，当前紫色+转圈，已完成绿色+勾
class _StatusCircle extends StatelessWidget {
  final _StageStatus status;
  final ColorScheme colorScheme;

  const _StatusCircle({required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    const iconSize = 18.0;

    switch (status) {
      case _StageStatus.pending:
        // 灰色圆圈描边
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.outline, width: 2),
          ),
        );
      case _StageStatus.active:
        // 紫色圆圈 + 内部白色转圈
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary,
          ),
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        );
      case _StageStatus.done:
        // 紫色圆圈 + 内部白色勾（用 primary 而非 green，保持主题统一）
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary,
          ),
          child: const Icon(Icons.check, size: iconSize, color: Colors.white),
        );
    }
  }
}

/// 特殊状态卡片（error / queued）
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
      elevation: 3,
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

/// 阶段状态枚举
enum _StageStatus { pending, active, done }

/// 阶段配置：状态 + 文案 + 图标
class _Stage {
  final RecognizeState state;
  final _StageStatus status;

  const _Stage({required this.state, required this.status});

  /// 阶段文案
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

  /// 阶段图标（右侧装饰）
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
