import 'dart:io';

import 'package:bergastream/core/storage/app_dirs.dart';
import 'package:bergastream/data/local/database.dart';
import 'package:bergastream/features/update/desktop_updater.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String documents;
  late String data;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('appdirs-');
    documents = '${root.path}/Documentos';
    data = '${root.path}/dados';
    await Directory(documents).create();
  });

  tearDown(() async {
    AppDirs.configureForTest();
    await root.delete(recursive: true);
  });

  group('AppDirs.prepareIn', () {
    test('traz o banco (com o diário) e os downloads do Documentos', () async {
      await File('$documents/bergastream.sqlite').writeAsString('banco');
      await File('$documents/bergastream.sqlite-wal').writeAsString('wal');
      await File('$documents/bergastream/audio/a.flac').create(recursive: true);
      await File('$documents/outro.txt').writeAsString('do usuário');

      await AppDirs.prepareIn(documents: documents, data: data);

      expect(await File('$data/bergastream.sqlite').readAsString(), 'banco');
      expect(await File('$data/bergastream.sqlite-wal').readAsString(), 'wal');
      expect(await File('$data/bergastream/audio/a.flac').exists(), isTrue);
      expect(await File('$documents/bergastream.sqlite').exists(), isFalse);
      expect(await Directory('$documents/bergastream').exists(), isFalse);
      expect(await File('$documents/outro.txt').exists(), isTrue);
      expect(await AppDirs.dataDirectory(), data);
      expect(
        AppDirs.remap('$documents/bergastream/audio/a.flac'),
        '$data/bergastream/audio/a.flac',
      );
      expect(AppDirs.remap('$data/bergastream/audio/a.flac'), isNull);
      expect(AppDirs.remap('$documents/bergastreamX/a'), isNull);
    });

    test('não sobrescreve um banco que já esteja na pasta nova', () async {
      await Directory(data).create();
      await File('$data/bergastream.sqlite').writeAsString('novo');
      await File('$documents/bergastream.sqlite').writeAsString('antigo');

      await AppDirs.prepareIn(documents: documents, data: data);

      expect(await File('$data/bergastream.sqlite').readAsString(), 'novo');
      expect(await File('$documents/bergastream.sqlite').exists(), isTrue);
      expect(await AppDirs.dataDirectory(), data);
    });

    test('instalação nova: só usa a pasta de dados', () async {
      await AppDirs.prepareIn(documents: documents, data: data);
      expect(await AppDirs.dataDirectory(), data);
      expect(await AppDirs.downloadsBase(), '$data/bergastream');
      expect(AppDirs.remapPrefixes, isNotNull);
    });
  });

  test('banco: caminhos dos downloads trocam para a pasta nova', () async {
    AppDirs.configureForTest(data: data, legacy: '$documents/bergastream');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      'INSERT INTO local_tracks (id, provider, external_id, title, artist, '
      'audio_path, cover_path, download_state) VALUES '
      "('t1', 'p', 'e', 'T', 'A', '$documents/bergastream/audio/t1.flac', "
      "'/outro/lugar/c.jpg', 0)",
    );
    await db.remapDownloadPathsForTest();
    final row = await db
        .customSelect(
          "SELECT audio_path, cover_path FROM local_tracks WHERE id = 't1'",
        )
        .getSingle();
    expect(row.read<String>('audio_path'), '$data/bergastream/audio/t1.flac');
    expect(row.read<String>('cover_path'), '/outro/lugar/c.jpg');
  });

  group('DesktopUpdater.swapBundle', () {
    Future<String> makeArchive(String content) async {
      final src = Directory('${root.path}/src/bergastream');
      await Directory(
        '${src.path}/data/flutter_assets',
      ).create(recursive: true);
      await File('${src.path}/bergastream').writeAsString(content);
      final archive = '${root.path}/pacote.tar.gz';
      final r = await Process.run('tar', [
        '-czf',
        archive,
        '-C',
        '${root.path}/src',
        'bergastream',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return archive;
    }

    test('troca a pasta do app e guarda a antiga em .old', () async {
      final dir = '${root.path}/app/bergastream';
      await Directory('$dir/data/flutter_assets').create(recursive: true);
      await File('$dir/bergastream').writeAsString('versão velha');
      expect(await DesktopUpdater.canSwapBundle(dir), isTrue);

      final exe = await DesktopUpdater.swapBundle(
        archive: await makeArchive('versão nova'),
        dir: dir,
        executable: 'bergastream',
      );

      expect(exe, '$dir/bergastream');
      expect(await File(exe).readAsString(), 'versão nova');
      expect(await File('$dir.old/bergastream').readAsString(), 'versão velha');
      expect(
        await Directory('${root.path}/app/.bergastream-atualizacao').exists(),
        isFalse,
      );
    });

    test('pacote estragado: a pasta atual fica como estava', () async {
      final dir = '${root.path}/app/bergastream';
      await Directory(dir).create(recursive: true);
      await File('$dir/bergastream').writeAsString('versão velha');
      final bad = '${root.path}/ruim.tar.gz';
      await File(bad).writeAsString('isto não é um tar');

      await expectLater(
        DesktopUpdater.swapBundle(
          archive: bad,
          dir: dir,
          executable: 'bergastream',
        ),
        throwsA(isA<ProcessException>()),
      );
      expect(await File('$dir/bergastream').readAsString(), 'versão velha');
      expect(await Directory('$dir.old').exists(), isFalse);
    });

    test('pasta com o banco dentro não é trocada', () async {
      final dir = '${root.path}/app/bergastream';
      await Directory('$dir/data/flutter_assets').create(recursive: true);
      await File('$dir/bergastream.sqlite').writeAsString('dados');
      expect(await DesktopUpdater.canSwapBundle(dir), isFalse);
    });

    test('pasta que não é de um app do Flutter não é trocada', () async {
      final dir = '${root.path}/qualquer';
      await Directory(dir).create();
      expect(await DesktopUpdater.canSwapBundle(dir), isFalse);
    });
  });
}
