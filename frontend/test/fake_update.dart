import 'package:bergastream/features/update/app_release.dart';
import 'package:bergastream/features/update/update_service.dart';

AppRelease release(String version, {Map<String, String>? assets}) => AppRelease(
  version: AppVersion.tryParse(version)!,
  tag: 'bergastream-v$version',
  pageUrl: 'https://github.com/x/releases/tag/bergastream-v$version',
  notes: 'Novidades da $version',
  assets:
      assets ??
      {
        AppRelease.androidAsset: 'https://dl/android.apk',
        AppRelease.linuxAsset: 'https://dl/linux.tar.gz',
        AppRelease.windowsAsset: 'https://dl/windows.zip',
        AppRelease.windowsSetupAsset: 'https://dl/windows-setup.exe',
      },
);

class FakeUpdateRepository implements UpdateRepository {
  FakeUpdateRepository({this.current = '0.1.0', this.published, this.fail});

  final String current;
  AppRelease? published;
  Object? fail;
  int latestCalls = 0;
  final downloads = <(String url, String path)>[];

  @override
  Future<AppVersion> currentVersion() async => AppVersion.tryParse(current)!;

  @override
  Future<AppRelease?> latest() async {
    latestCalls++;
    if (fail case final error?) throw error;
    return published;
  }

  @override
  Future<void> download(
    String url,
    String path, {
    void Function(double progress)? onProgress,
  }) async {
    downloads.add((url, path));
    onProgress?.call(0.5);
    onProgress?.call(1);
  }
}

class FakeUpdateLauncher implements UpdateLauncher {
  FakeUpdateLauncher({
    this.desktopInstalls = false,
    this.result = UpdateInstall.restarting,
  });

  /// Linux/Windows: o app instala sozinho (Android sempre instala).
  final bool desktopInstalls;
  final UpdateInstall result;
  final opened = <String>[];
  final pages = <String>[];
  final installed = <(UpdateTarget, String)>[];
  var quits = 0;

  @override
  Future<bool> canInstall(UpdateTarget target) async =>
      target == UpdateTarget.android || desktopInstalls;

  @override
  Future<String> folderFor({required bool direct}) async =>
      direct ? '/tmp/cache' : '/home/u/Downloads';

  @override
  Future<UpdateInstall> install(UpdateTarget target, String path) async {
    installed.add((target, path));
    if (target == UpdateTarget.android) opened.add(path);
    return target == UpdateTarget.android ? UpdateInstall.opened : result;
  }

  @override
  Future<bool> open(String path) async {
    opened.add(path);
    return true;
  }

  @override
  Future<bool> openPage(String url) async {
    pages.add(url);
    return true;
  }

  @override
  Future<void> quit() async => quits++;
}
