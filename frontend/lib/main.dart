import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app/app.dart';
import 'core/platform/app_platform.dart';
import 'core/storage/app_dirs.dart';
import 'core/storage/key_value_store.dart';
import 'features/auth/session.dart';
import 'features/downloads/file_fetcher.dart';
import 'features/player/car_library.dart';
import 'features/player/media_notification.dart';
import 'features/update/desktop_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: o botão direito abre o menu do app (⋮), não o do navegador.
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  // Windows/Linux: o just_audio toca pelo media_kit (libmpv). No Android e
  // na web não faz nada.
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  final platform = AppPlatform.detect();
  // Windows/Linux: banco e downloads fora da pasta Documentos (até a 0.8.3
  // ficavam lá) e a limpeza depois de uma atualização. Uma falha aqui não
  // impede o app de abrir.
  try {
    await AppDirs.prepare();
    await DesktopUpdater.cleanUpAfterUpdate();
  } on Object catch (e) {
    debugPrint('Preparar as pastas do app: $e');
  }
  final store = SecureKeyValueStore();
  final storage = SessionStorage(
    store,
    prefix: SessionStorage.prefixFor(platform),
  );
  final session = await storage.load(
    defaultServer: platform.isWeb ? webServerAddress() : null,
  );

  final mediaNotification = await initMediaNotification();
  configureDownloadNotifications();

  final container = ProviderContainer(
    overrides: [
      appPlatformProvider.overrideWithValue(platform),
      keyValueStoreProvider.overrideWithValue(store),
      sessionStorageProvider.overrideWithValue(storage),
      initialSessionProvider.overrideWithValue(session),
      mediaNotificationProvider.overrideWithValue(mediaNotification),
    ],
  );
  // Android Auto: a biblioteca do carro fica pronta antes da tela. O carro
  // pode abrir o app em segundo plano, sem a interface do celular.
  container.read(carLibraryProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const BergastreamApp(),
    ),
  );
}
