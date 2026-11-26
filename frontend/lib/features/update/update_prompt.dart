import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/theme/berga_colors.dart';
import '../../core/theme/berga_sizes.dart';
import '../../core/theme/berga_text.dart';
import '../../core/widgets/widgets.dart';
import 'update_service.dart';

/// Ao abrir o app (Android, Windows e Linux), confere se há versão nova no
/// GitHub e pergunta se quer baixar.
class UpdateWatcher extends ConsumerStatefulWidget {
  const UpdateWatcher({super.key, required this.child, this.delay});

  final Widget child;

  /// Espera antes de conferir (deixa o app abrir e o login navegar).
  final Duration? delay;

  @override
  ConsumerState<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends ConsumerState<UpdateWatcher> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_checkOnStart);
  }

  Future<void> _checkOnStart() async {
    final service = ref.read(updateServiceProvider);
    if (!service.supported) return;
    await Future<void>.delayed(widget.delay ?? const Duration(seconds: 3));
    final result = await service.check();
    if (result is! UpdateAvailable || !mounted) return;
    // Este widget fica acima do Navigator: o diálogo usa o do router.
    final context = ref
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.overlay
        ?.context;
    if (context != null && context.mounted) {
      await offerUpdate(context, ref, result);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Verificar atualizações" em Ajustes.
Future<void> checkForUpdatesManually(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await ref.read(updateServiceProvider).check(manual: true);
  if (!context.mounted) return;
  switch (result) {
    case UpdateAvailable():
      await offerUpdate(context, ref, result);
    case UpToDate(:final current):
      AppToast.show(context, 'Você já tem a versão mais recente ($current)');
    case UpdateCheckFailed() || null:
      AppToast.show(context, 'Não foi possível verificar agora');
  }
}

/// Pergunta "Agora não" / "Ver no GitHub" / "Atualizar agora" (ou
/// "Baixar", quando este aparelho não instala sozinho).
Future<void> offerUpdate(
  BuildContext context,
  WidgetRef ref,
  UpdateAvailable update,
) async {
  final service = ref.read(updateServiceProvider);
  final launcher = ref.read(updateLauncherProvider);
  final target = ref.read(updateTargetProvider)!;
  final release = update.release;
  final direct = await launcher.canInstall(target);
  if (!context.mounted) return;
  final choice = await showChoiceDialog(
    context,
    message:
        'Nova versão ${release.version} disponível '
        '(você tem a ${update.current}).',
    detail: release.notes,
    options: [
      'Agora não',
      'Ver no GitHub',
      switch ((target, direct)) {
        (UpdateTarget.android, _) => 'Baixar e instalar',
        (_, true) => 'Atualizar agora',
        (_, false) => 'Baixar',
      },
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 1:
      await launcher.openPage(release.pageUrl);
    case 2:
      await _downloadAndInstall(context, ref, update, direct: direct);
    default:
      await service.skip(release);
  }
}

Future<void> _downloadAndInstall(
  BuildContext context,
  WidgetRef ref,
  UpdateAvailable update, {
  required bool direct,
}) async {
  final service = ref.read(updateServiceProvider);
  final launcher = ref.read(updateLauncherProvider);
  final target = ref.read(updateTargetProvider)!;
  final progress = ValueNotifier<double?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: BergaColors.of(context).scrim,
    builder: (_) => _DownloadProgressDialog(progress: progress),
  );
  String? path;
  var result = UpdateInstall.failed;
  try {
    path = await service.download(
      update.release,
      direct: direct,
      onProgress: (p) => progress.value = p,
    );
    // Instala com o aviso "Baixando…" ainda na tela (no Linux, extrair
    // leva alguns segundos).
    if (direct) result = await launcher.install(target, path);
  } on Object {
    path = null;
  } finally {
    navigator.pop();
    await dialog;
    progress.dispose();
  }
  if (!context.mounted) return;
  if (path == null) {
    AppToast.show(context, 'Falha ao baixar. Tente pelo GitHub.');
    return;
  }
  if (!direct) {
    // Desktop sem permissão para se trocar: o pacote fica em Downloads.
    await launcher.open(File(path).parent.path);
    if (context.mounted) {
      AppToast.show(context, 'Atualização salva em Downloads');
    }
    return;
  }
  switch (result) {
    case UpdateInstall.opened:
      break;
    case UpdateInstall.restarting:
      AppToast.show(context, 'Atualizando… o Bergastream abre de novo sozinho');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await launcher.quit();
    case UpdateInstall.failed:
      AppToast.show(
        context,
        target == UpdateTarget.android
            ? 'Não foi possível abrir o instalador'
            : 'Não foi possível instalar. Tente pelo GitHub.',
      );
  }
}

class _DownloadProgressDialog extends StatelessWidget {
  const _DownloadProgressDialog({required this.progress});

  final ValueNotifier<double?> progress;

  @override
  Widget build(BuildContext context) {
    final c = BergaColors.of(context);
    return Dialog(
      backgroundColor: c.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BergaSizes.cardRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value == null
                      ? 'Baixando atualização…'
                      : 'Baixando atualização… ${(value * 100).round()}%',
                  style: BergaText.trackTitle.copyWith(color: c.tx),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: c.ac,
                    backgroundColor: c.bg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
