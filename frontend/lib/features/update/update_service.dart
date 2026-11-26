import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/app_platform.dart';
import '../../core/storage/key_value_store.dart';
import 'app_release.dart';
import 'desktop_updater.dart';

/// Plataformas que recebem atualização pelo GitHub.
enum UpdateTarget {
  android(AppRelease.androidAsset),
  linux(AppRelease.linuxAsset),
  windows(AppRelease.windowsSetupAsset);

  const UpdateTarget(this.asset);

  /// Nome do arquivo desta plataforma na release.
  final String asset;

  /// Plataforma atual; nulo na web, na simulação e em sistemas sem pacote.
  static UpdateTarget? of(AppPlatform platform) {
    if (kIsWeb || platform.isWeb || platform.simulated) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => UpdateTarget.android,
      TargetPlatform.linux => UpdateTarget.linux,
      TargetPlatform.windows => UpdateTarget.windows,
      _ => null,
    };
  }
}

/// Consulta e baixa versões publicadas.
abstract interface class UpdateRepository {
  /// Versão instalada.
  Future<AppVersion> currentVersion();

  /// Versão mais nova publicada; nulo se não houver nenhuma.
  Future<AppRelease?> latest();

  /// Baixa [url] para [path], informando o progresso (0 a 1).
  Future<void> download(
    String url,
    String path, {
    void Function(double progress)? onProgress,
  });
}

class GitHubUpdateRepository implements UpdateRepository {
  GitHubUpdateRepository([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/vnd.github+json'},
            ),
          );

  final Dio _dio;

  @override
  Future<AppVersion> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.tryParse(info.version) ?? const AppVersion(0, 0, 0);
  }

  /// A mais nova entre os repositórios ([AppRelease.repositories]). Um que
  /// não responda (privado, fora do ar) é pulado; erro só se nenhum responder.
  @override
  Future<AppRelease?> latest() async {
    AppRelease? best;
    Object? lastError;
    var answered = false;
    for (final repo in AppRelease.repositories) {
      try {
        final response = await _dio.get<List<dynamic>>(
          'https://api.github.com/repos/$repo/releases',
          queryParameters: {'per_page': 30},
        );
        answered = true;
        final found = AppRelease.latestOf(response.data ?? const []);
        if (found != null && (best == null || found.version > best.version)) {
          best = found;
        }
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (!answered && lastError != null) throw lastError;
    return best;
  }

  @override
  Future<void> download(
    String url,
    String path, {
    void Function(double progress)? onProgress,
  }) => _dio.download(
    url,
    path,
    // Pacotes grandes (~60 MB): sem limite para receber.
    options: Options(receiveTimeout: Duration.zero),
    onReceiveProgress: (received, total) {
      if (total > 0) onProgress?.call(received / total);
    },
  );
}

final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => GitHubUpdateRepository(),
);

/// Como terminou a instalação de uma versão baixada.
enum UpdateInstall {
  /// Android: o instalador do sistema abriu.
  opened,

  /// Windows/Linux: a versão nova está sendo instalada; o app deve fechar
  /// ([UpdateLauncher.quit]) e abre de novo sozinho.
  restarting,

  /// Não deu para instalar.
  failed,
}

/// Abre arquivos e links fora do app e instala as versões baixadas.
abstract interface class UpdateLauncher {
  /// Este aparelho instala a versão sozinho? Android e Windows sempre; o
  /// Linux quando a pasta do app pode ser trocada. Se não, o pacote vai para
  /// Downloads e a pasta é aberta.
  Future<bool> canInstall(UpdateTarget target);

  /// Pasta onde o pacote é salvo: a temporária, quando [direct] (o app
  /// instala), ou Downloads.
  Future<String> folderFor({required bool direct});

  /// Instala o pacote em [path].
  Future<UpdateInstall> install(UpdateTarget target, String path);

  /// Abre um arquivo ou pasta. Falso se não conseguiu.
  Future<bool> open(String path);

  Future<bool> openPage(String url);

  /// Fecha o app (depois de [UpdateInstall.restarting]).
  Future<void> quit();
}

class SystemUpdateLauncher implements UpdateLauncher {
  @override
  Future<bool> canInstall(UpdateTarget target) async => switch (target) {
    UpdateTarget.android || UpdateTarget.windows => true,
    UpdateTarget.linux => DesktopUpdater.canSwapLinuxBundle(),
  };

  @override
  Future<String> folderFor({required bool direct}) async {
    if (direct) return (await getTemporaryDirectory()).path;
    final downloads = await getDownloadsDirectory();
    return (downloads ?? await getTemporaryDirectory()).path;
  }

  @override
  Future<UpdateInstall> install(UpdateTarget target, String path) async {
    try {
      switch (target) {
        case UpdateTarget.android:
          return await open(path) ? UpdateInstall.opened : UpdateInstall.failed;
        case UpdateTarget.windows:
          await DesktopUpdater.runWindowsInstaller(path);
        case UpdateTarget.linux:
          final exe = await DesktopUpdater.swapBundle(
            archive: path,
            dir: DesktopUpdater.bundleDir,
            executable: File(Platform.resolvedExecutable).uri.pathSegments.last,
          );
          await File(path).delete();
          await DesktopUpdater.relaunch(exe);
      }
      return UpdateInstall.restarting;
    } on Object catch (e) {
      debugPrint('Atualização não instalada: $e');
      return UpdateInstall.failed;
    }
  }

  @override
  Future<bool> open(String path) async {
    final result = await OpenFilex.open(
      path,
      type: path.endsWith('.apk')
          ? 'application/vnd.android.package-archive'
          : null,
    );
    return result.type == ResultType.done;
  }

  @override
  Future<bool> openPage(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Future<void> quit() async => exit(0);
}

final updateLauncherProvider = Provider<UpdateLauncher>(
  (ref) => SystemUpdateLauncher(),
);

/// Plataforma que recebe atualizações (sobrescrita nos testes).
final updateTargetProvider = Provider<UpdateTarget?>(
  (ref) => UpdateTarget.of(ref.watch(appPlatformProvider)),
);

/// Resultado de uma verificação.
sealed class UpdateCheck {
  const UpdateCheck();
}

class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.current, this.release);
  final AppVersion current;
  final AppRelease release;
}

class UpToDate extends UpdateCheck {
  const UpToDate(this.current);
  final AppVersion current;
}

class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed();
}

/// Regras de quando perguntar: no máximo uma consulta automática por
/// [interval]; versão recusada ("Agora não") não é oferecida de novo sozinha.
class UpdateService {
  UpdateService(this._ref);

  final Ref _ref;

  static const interval = Duration(hours: 20);
  static const lastCheckKey = 'update.lastCheck';
  static const skippedKey = 'update.skipped';

  UpdateRepository get _repo => _ref.read(updateRepositoryProvider);
  KeyValueStore get _store => _ref.read(keyValueStoreProvider);

  bool get supported => _ref.read(updateTargetProvider) != null;

  /// [manual]: pedido em Ajustes — ignora o intervalo e a versão recusada.
  Future<UpdateCheck?> check({bool manual = false, DateTime? now}) async {
    if (!supported) return null;
    now ??= DateTime.now();
    if (!manual) {
      final last = DateTime.tryParse(await _store.read(lastCheckKey) ?? '');
      if (last != null && now.difference(last) < interval) return null;
    }
    try {
      final current = await _repo.currentVersion();
      final release = await _repo.latest();
      await _store.write(lastCheckKey, now.toIso8601String());
      final target = _ref.read(updateTargetProvider)!;
      if (release == null ||
          !(release.version > current) ||
          !release.assets.containsKey(target.asset)) {
        return UpToDate(current);
      }
      if (!manual &&
          await _store.read(skippedKey) == release.version.toString()) {
        return null;
      }
      return UpdateAvailable(current, release);
    } on Object {
      return const UpdateCheckFailed();
    }
  }

  Future<void> skip(AppRelease release) =>
      _store.write(skippedKey, release.version.toString());

  /// Baixa o pacote da plataforma. Devolve o caminho do arquivo. [direct]:
  /// o app vai instalar ([UpdateLauncher.folderFor]).
  Future<String> download(
    AppRelease release, {
    required bool direct,
    void Function(double progress)? onProgress,
  }) async {
    final target = _ref.read(updateTargetProvider)!;
    final folder = await _ref
        .read(updateLauncherProvider)
        .folderFor(direct: direct);
    final name = target.asset.replaceFirst(
      'bergastream-',
      'bergastream-${release.version}-',
    );
    final path = '$folder${Platform.pathSeparator}$name';
    await _repo.download(
      release.assets[target.asset]!,
      path,
      onProgress: onProgress,
    );
    return path;
  }
}

final updateServiceProvider = Provider<UpdateService>(UpdateService.new);
