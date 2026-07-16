// Regenerates every platform app icon from the approved master artwork.
//
// Usage: dart run tool/generate_app_icons.dart
//
// This is the single reproducible entry point for app icon generation --
// there is no separate manual/Python step. It:
//   1. Validates the committed master image.
//   2. Runs the pinned `flutter_launcher_icons` generator (Android, iOS,
//      macOS, Windows placeholder .ico, Web).
//   3. Repairs a known flutter_launcher_icons 0.14.4 regression that
//      corrupts the boolean Xcode build setting
//      ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS (turning
//      `YES` into the asset catalog name `AppIcon`), without touching the
//      separate (and correct) ASSETCATALOG_COMPILER_APPICON_NAME setting.
//   4. Rebuilds windows/runner/resources/app_icon.ico as a true multi-frame
//      ICO (16/32/48/64/128/256) directly from the master image, since
//      flutter_launcher_icons only ever emits a single-size Windows icon.
//
// Every step validates its inputs/outputs and exits non-zero (with a clear
// message) if the project doesn't look the way this script expects, rather
// than silently doing nothing or emitting a broken asset.
import 'dart:io';

import 'package:image/image.dart' as img;

const _masterImagePath = 'assets/branding/human_status_icon_master.png';
const _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const _windowsIcoPath = 'windows/runner/resources/app_icon.ico';
const _icoSizes = [16, 32, 48, 64, 128, 256];

const _swiftAssetSymbolKey =
    'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS';
const _appIconNameKey = 'ASSETCATALOG_COMPILER_APPICON_NAME';

void _fail(String message) {
  stderr.writeln('generate_app_icons: $message');
  exit(1);
}

img.Image _decodeMasterImage() {
  final file = File(_masterImagePath);
  if (!file.existsSync()) {
    _fail('master image not found at $_masterImagePath');
  }
  final bytes = file.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    _fail('could not decode $_masterImagePath as an image');
  }
  final image = decoded!;
  if (image.width != image.height) {
    _fail('master image must be square, got ${image.width}x${image.height}');
  }
  return image;
}

Future<void> _runFlutterLauncherIcons() async {
  stdout.writeln('generate_app_icons: running flutter_launcher_icons...');
  final result = await Process.run('dart', [
    'run',
    'flutter_launcher_icons',
  ], runInShell: Platform.isWindows);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    _fail('flutter_launcher_icons exited with code ${result.exitCode}');
  }
}

/// Restores `$_swiftAssetSymbolKey = YES;` wherever flutter_launcher_icons
/// clobbered it with the asset catalog name, and validates the file still
/// has the shape this script expects. Never touches `$_appIconNameKey`.
void _repairIosProjectSettings() {
  final file = File(_pbxprojPath);
  if (!file.existsSync()) {
    _fail('iOS project file not found at $_pbxprojPath');
  }
  final content = file.readAsStringSync();

  final assetSymbolPattern = RegExp(
    RegExp.escape(_swiftAssetSymbolKey) + r'\s*=\s*([^;]+);',
  );
  final matches = assetSymbolPattern.allMatches(content).toList();
  if (matches.isEmpty) {
    _fail(
      'no $_swiftAssetSymbolKey assignments found in $_pbxprojPath -- '
      'unexpected project shape, refusing to guess a fix',
    );
  }

  final badValues = matches
      .map((m) => m.group(1)!.trim())
      .where((value) => value != 'YES' && value != 'NO')
      .toSet();
  if (badValues.isNotEmpty) {
    stdout.writeln(
      'generate_app_icons: repairing $_swiftAssetSymbolKey corrupted to '
      '${badValues.join(', ')} -> YES',
    );
  }

  final repaired = content.replaceAllMapped(assetSymbolPattern, (m) {
    final value = m.group(1)!.trim();
    // This setting is boolean; any non-YES/NO value (e.g. an asset catalog
    // name like "AppIcon") is flutter_launcher_icons corruption.
    final fixedValue = (value == 'YES' || value == 'NO') ? value : 'YES';
    return '$_swiftAssetSymbolKey = $fixedValue;';
  });

  if (!repaired.contains('$_appIconNameKey = AppIcon;')) {
    _fail(
      'expected $_appIconNameKey = AppIcon; to be present and unchanged in '
      '$_pbxprojPath -- unexpected project shape',
    );
  }

  if (repaired != content) {
    file.writeAsStringSync(repaired);
  }
}

void _regenerateWindowsIco(img.Image master) {
  stdout.writeln(
    'generate_app_icons: rebuilding multi-frame Windows .ico from master...',
  );
  final frames = _icoSizes
      .map(
        (size) => img.copyResize(
          master,
          width: size,
          height: size,
          interpolation: img.Interpolation.cubic,
        ),
      )
      .toList();

  // An image.Image is itself frame 0 of its own animation; additional
  // frames are attached with addFrame. encodeIco() writes every frame of
  // an animated Image as a separate ICO directory entry (see
  // package:image's WinEncoder.encode), which is how a true multi-size
  // .ico is produced through the public API.
  final root = frames.first;
  for (final frame in frames.skip(1)) {
    root.addFrame(frame);
  }
  final icoBytes = img.encodeIco(root);

  final outFile = File(_windowsIcoPath);
  if (!outFile.parent.existsSync()) {
    _fail(
      'expected ${outFile.parent.path} to already exist -- unexpected '
      'project shape',
    );
  }
  outFile.writeAsBytesSync(icoBytes);
}

Future<void> main() async {
  final master = _decodeMasterImage();
  await _runFlutterLauncherIcons();
  _repairIosProjectSettings();
  _regenerateWindowsIco(master);
  stdout.writeln('generate_app_icons: done.');
}
