import 'dart:io';

import 'package:flutter/foundation.dart';

/// Instala no próprio PC a versão baixada, sem o usuário trocar arquivos.
///
/// - **Windows:** o pacote é o instalador (Inno Setup). Ele roda em modo
///   silencioso, fecha o app, troca os arquivos e abre o app de novo.
/// - **Linux:** o pacote é o `.tar.gz` da pasta do app. Ele é extraído ao lado
///   da pasta atual, as duas trocam de nome e o app abre de novo. No Linux dá
///   para trocar a pasta com o app aberto; a antiga (`<pasta>.old`) é apagada
///   na abertura seguinte ([cleanUpAfterUpdate]).
class DesktopUpdater {
  DesktopUpdater._();

  /// Argumentos do instalador do Windows para atualizar sem perguntar nada.
  /// O próprio instalador abre o app no fim (`[Run]` do `bergastream.iss`).
  static const windowsInstallerArgs = [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
  ];

  /// Pasta do app em uso (a do executável).
  static String get bundleDir => File(Platform.resolvedExecutable).parent.path;

  /// Linux: a pasta do app pode ser trocada? Só num build de release (não no
  /// `flutter run`), numa pasta com cara de app do Flutter e com permissão
  /// de escrita ao lado dela.
  static Future<bool> canSwapLinuxBundle([String? dir]) async {
    if (!kReleaseMode || kIsWeb || !Platform.isLinux) return false;
    return canSwapBundle(dir ?? bundleDir);
  }

  /// [canSwapLinuxBundle] sem conferir o sistema (os testes usam).
  @visibleForTesting
  static Future<bool> canSwapBundle(String dir) async {
    if (!await Directory('$dir/data/flutter_assets').exists()) return false;
    // Trava: dados do app dentro da pasta seriam apagados com a troca.
    if (await File('$dir/bergastream.sqlite').exists()) return false;
    final probe = Directory(
      '${Directory(dir).parent.path}/.bergastream-teste-escrita',
    );
    try {
      await probe.create();
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Windows: abre o instalador em silêncio. Depois disso o app deve fechar.
  static Future<void> runWindowsInstaller(String setup) => Process.start(
    setup,
    windowsInstallerArgs,
    mode: ProcessStartMode.detached,
  );

  /// Troca a pasta [dir] do app pela do pacote [archive] (`.tar.gz` com a
  /// pasta `bergastream/` dentro). Devolve o executável novo. Se algo der
  /// errado antes da troca, a pasta atual fica intacta.
  static Future<String> swapBundle({
    required String archive,
    required String dir,
    required String executable,
  }) async {
    final target = Directory(dir);
    final staging = Directory(
      '${target.parent.path}/.${target.uri.pathSegments.where((s) => s.isNotEmpty).last}-atualizacao',
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create();
    try {
      final tar = await Process.run('tar', [
        '-xzf',
        archive,
        '-C',
        staging.path,
      ]);
      if (tar.exitCode != 0) {
        throw ProcessException(
          'tar',
          ['-xzf', archive],
          '${tar.stderr}',
          tar.exitCode,
        );
      }
      final fresh = Directory('${staging.path}/bergastream');
      if (!await File('${fresh.path}/$executable').exists()) {
        throw const FormatException('O pacote não tem o executável do app.');
      }
      final old = Directory('$dir.old');
      if (await old.exists()) await old.delete(recursive: true);
      await target.rename(old.path);
      try {
        await fresh.rename(dir);
      } on Object {
        await old.rename(dir);
        rethrow;
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    return '$dir/$executable';
  }

  /// Linux: abre o app novo um segundo depois, para este já ter fechado.
  static Future<void> relaunch(String executable) => Process.start('sh', [
    '-c',
    r'sleep 1; exec "$0"',
    executable,
  ], mode: ProcessStartMode.detached);

  /// Abertura seguinte a uma atualização no Linux: apaga a pasta antiga.
  static Future<void> cleanUpAfterUpdate() async {
    if (kIsWeb || !Platform.isLinux || !kReleaseMode) return;
    final old = Directory('$bundleDir.old');
    if (await old.exists()) await old.delete(recursive: true);
  }
}
