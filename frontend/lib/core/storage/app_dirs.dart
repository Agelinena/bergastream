import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Onde o app guarda o banco e os downloads.
///
/// - **Android:** a pasta de documentos do app, que é privada.
/// - **Windows e Linux:** a pasta de dados do app (Linux:
///   `~/.local/share/com.bergastream.app`; Windows:
///   `%APPDATA%\com.bergastream\Bergastream`). Até a 0.8.3 o app usava a
///   pasta Documentos do usuário; [prepare] traz o que ficou lá.
class AppDirs {
  AppDirs._();

  /// Nome do banco (`bergastream.sqlite`) e da pasta dos downloads.
  static const name = 'bergastream';

  static String? _data;
  static String? _legacy;

  /// Pasta dos dados. Antes de [prepare] (nos testes), a de documentos.
  static Future<String> dataDirectory() async =>
      _data ?? (await getApplicationDocumentsDirectory()).path;

  /// Pasta dos downloads (áudio e capas) dentro de [dataDirectory].
  static Future<String> downloadsBase() async =>
      '${await dataDirectory()}/$name';

  /// Troca, num caminho guardado (banco, playlists locais), a pasta antiga
  /// dos downloads (Documentos) pela nova. Nulo se não houver o que trocar.
  static String? remap(String? path) {
    final from = _legacy;
    final data = _data;
    if (path == null || from == null || data == null) return null;
    if (!path.startsWith('$from/')) return null;
    return '$data/$name${path.substring(from.length)}';
  }

  /// Prefixos para a troca feita direto no banco ([remap] em SQL).
  static ({String from, String to})? get remapPrefixes {
    final from = _legacy;
    final data = _data;
    if (from == null || data == null) return null;
    return (from: from, to: '$data/$name');
  }

  /// Escolhe as pastas e, no desktop, traz do Documentos o banco e os
  /// downloads de versões antigas. Roda uma vez, no início do app.
  static Future<void> prepare() async {
    if (kIsWeb) return;
    if (!Platform.isLinux && !Platform.isWindows) return;
    await prepareIn(
      documents: (await getApplicationDocumentsDirectory()).path,
      data: await _desktopDataDirectory(),
    );
  }

  /// Linux: `$XDG_DATA_HOME/com.bergastream.app`, escrito aqui e não pelo
  /// `getApplicationSupportDirectory`, que às vezes usa o nome do executável
  /// (`~/.local/share/bergastream`): a pasta onde o script instala o app, que
  /// a atualização troca inteira. Windows: `%APPDATA%\com.bergastream\
  /// Bergastream`, longe da pasta do app (`%LOCALAPPDATA%\Programs`).
  static Future<String> _desktopDataDirectory() async {
    if (!Platform.isLinux) return (await getApplicationSupportDirectory()).path;
    final env = Platform.environment;
    final xdg = env['XDG_DATA_HOME'];
    final base = xdg != null && xdg.startsWith('/')
        ? xdg
        : '${env['HOME']}/.local/share';
    return '$base/$linuxDataFolder';
  }

  /// Nome da pasta de dados no Linux (o id do app, `APPLICATION_ID`).
  static const linuxDataFolder = 'com.bergastream.app';

  /// [prepare] com as pastas dadas (os testes usam pastas temporárias).
  ///
  /// Se o banco não puder sair de [documents], tudo continua lá, como
  /// antes. Se só os downloads não puderem, os caminhos guardados continuam
  /// apontando para [documents], onde os arquivos ficaram.
  @visibleForTesting
  static Future<void> prepareIn({
    required String documents,
    required String data,
  }) async {
    await Directory(data).create(recursive: true);
    try {
      await _moveDatabase(documents, data);
    } on Object catch (e) {
      debugPrint('Banco não saiu da pasta Documentos: $e');
    }
    final dbLeft =
        await File('$documents/$name.sqlite').exists() &&
        !await File('$data/$name.sqlite').exists();
    if (dbLeft) return;
    _data = data;

    final old = Directory('$documents/$name');
    try {
      if (await old.exists() && !await Directory('$data/$name').exists()) {
        await _moveDirectory(old, '$data/$name');
      }
    } on Object catch (e) {
      debugPrint('Downloads não saíram da pasta Documentos: $e');
    }
    if (!await old.exists()) _legacy = old.path;
  }

  /// O banco e os arquivos do diário (`-wal`, `-shm`, `-journal`), sem
  /// sobrescrever um banco que já esteja em [to]. Se algum arquivo do diário
  /// não passar, devolve tudo para [from]: o banco nunca fica separado dele.
  static Future<void> _moveDatabase(String from, String to) async {
    final db = File('$from/$name.sqlite');
    if (!await db.exists()) return;
    if (await File('$to/$name.sqlite').exists()) return;
    const journal = ['-wal', '-shm', '-journal'];
    await _moveFile(db, '$to/$name.sqlite');
    try {
      for (final suffix in journal) {
        final f = File('$from/$name.sqlite$suffix');
        if (await f.exists()) await _moveFile(f, '$to/$name.sqlite$suffix');
      }
    } on Object {
      for (final suffix in [...journal, '']) {
        final f = File('$to/$name.sqlite$suffix');
        if (await f.exists()) await _moveFile(f, '$from/$name.sqlite$suffix');
      }
      rethrow;
    }
  }

  /// `rename` não atravessa discos (Documentos no OneDrive ou noutra
  /// partição): aí copia e apaga.
  static Future<void> _moveFile(File file, String to) async {
    try {
      await file.rename(to);
    } on FileSystemException {
      await file.copy(to);
      await file.delete();
    }
  }

  static Future<void> _moveDirectory(Directory dir, String to) async {
    try {
      await dir.rename(to);
      return;
    } on FileSystemException {
      // Outro disco: copia tudo e só então apaga a original.
    }
    final partial = Directory('$to.parcial');
    if (await partial.exists()) await partial.delete(recursive: true);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(dir.path.length);
      if (entity is Directory) {
        await Directory('${partial.path}$relative').create(recursive: true);
      } else if (entity is File) {
        await File('${partial.path}$relative').parent.create(recursive: true);
        await entity.copy('${partial.path}$relative');
      }
    }
    await partial.rename(to);
    await dir.delete(recursive: true);
  }

  /// Só nos testes: volta ao estado antes de [prepare].
  @visibleForTesting
  static void configureForTest({String? data, String? legacy}) {
    _data = data;
    _legacy = legacy;
  }
}
