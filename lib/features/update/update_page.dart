// lib/features/update/update_page.dart
//
// 应用内更新 UI 页。
//
// 状态机：
// - idle：初始态，显示"检查更新"按钮
// - checking：调 checkForUpdate 中
// - upToDate：已是最新
// - updateAvailable：有新版本，显示 release notes + "下载并安装"
// - downloading：下载中，显示进度条
// - readyToInstall：下载完成，显示"打开系统安装器"
// - error：检查/下载失败，显示错误 + 重试

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_models.dart';
import '../../core/widgets/m3_widgets.dart';
import '../recognize/providers.dart' as recognize;

class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});
  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

enum _UpdateState {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  error
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  _UpdateState _state = _UpdateState.idle;
  UpdateCheckResult? _result;
  DownloadProgress? _progress;
  String? _downloadedPath;
  String? _errorMsg;
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _state = _UpdateState.checking;
      _errorMsg = null;
    });
    try {
      final service = await ref.read(recognize.updateServiceProvider.future);
      final result = await service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _result = result;
        switch (result) {
          case UpToDate():
            _state = _UpdateState.upToDate;
          case UpdateAvailable():
            _state = _UpdateState.updateAvailable;
          case CheckFailed():
            _state = _UpdateState.error;
            _errorMsg = result.reason;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMsg = '检查失败：$e';
      });
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    final result = _result;
    if (result is! UpdateAvailable) return;
    setState(() {
      _busy = true;
      _state = _UpdateState.downloading;
      _progress = null;
    });
    try {
      final service = await ref.read(recognize.updateServiceProvider.future);
      final path = await service.downloadApk(
        url: result.release.apkDownloadUrl,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedPath = path;
        _state = _UpdateState.readyToInstall;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMsg = '下载失败：$e';
      });
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _install() async {
    // M16-F2：接入 ApkInstaller.triggerInstall(path) 触发系统安装器
    // 当前 E1 阶段仅 toast 提示，F2 完成后替换
    if (_downloadedPath == null) return;
    if (!mounted) return;
    showAppToast(context, '即将打开系统安装器（M16-F2 接入原生通道）');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('应用更新')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildContent(cs, tt),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(ColorScheme cs, TextTheme tt) {
    switch (_state) {
      case _UpdateState.idle:
        return [
          Icon(Icons.system_update_alt, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('点击下方按钮检查是否有新版本',
              textAlign: TextAlign.center, style: tt.bodyMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('检查更新'),
          ),
        ];
      case _UpdateState.checking:
        return [
          const LoadingState(label: '正在检查...'),
        ];
      case _UpdateState.upToDate:
        final r = _result as UpToDate;
        return [
          Icon(Icons.check_circle, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('已是最新版本', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text('当前版本：${r.currentVersion}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('重新检查'),
          ),
        ];
      case _UpdateState.updateAvailable:
        final r = _result as UpdateAvailable;
        return [
          Icon(Icons.system_update, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('发现新版本：${r.release.version}',
              textAlign: TextAlign.center, style: tt.titleMedium),
          const SizedBox(height: 8),
          Text('当前版本：${r.currentVersion}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (r.release.body.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Text(r.release.body,
                      style: tt.bodySmall,
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('大小：${(r.release.apkSize / 1024 / 1024).toStringAsFixed(1)} MB',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.download),
            label: const Text('下载并安装'),
          ),
        ];
      case _UpdateState.downloading:
        final p = _progress;
        final fraction = p?.fraction ?? 0;
        final receivedKb = (p?.received ?? 0) ~/ 1024;
        final totalKb = (p?.total ?? 0) ~/ 1024;
        return [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: fraction == 0 ? null : fraction),
          const SizedBox(height: 8),
          Text(
            fraction > 0
                ? '${(fraction * 100).toStringAsFixed(0)}%  ($receivedKb KB / $totalKb KB)'
                : '正在下载...',
            textAlign: TextAlign.center,
            style: tt.bodySmall,
          ),
        ];
      case _UpdateState.readyToInstall:
        return [
          Icon(Icons.download_done, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('下载完成', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text('点击下方按钮打开系统安装器完成升级',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _install,
            icon: const Icon(Icons.install_mobile),
            label: const Text('打开系统安装器'),
          ),
        ];
      case _UpdateState.error:
        return [
          Icon(Icons.error_outline, size: 64, color: cs.error),
          const SizedBox(height: 16),
          Text('出错了', style: tt.titleMedium?.copyWith(color: cs.error)),
          const SizedBox(height: 8),
          Text(_errorMsg ?? '未知错误',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ];
    }
  }
}
