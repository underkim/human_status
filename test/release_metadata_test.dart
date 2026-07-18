import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Deterministic checks over platform metadata files, catching regressions
/// like the Flutter template's placeholder title/description reappearing on
/// a user-visible surface. These files aren't reachable from Dart code (they
/// live under android/ios/macos/windows/linux/web), so `flutter test`
/// otherwise never looks at them.
///
/// Undecided internal identifiers (Android applicationId/namespace, iOS/
/// macOS bundle ids, the Linux APPLICATION_ID, the Windows/Linux/macOS
/// internal executable name) are explicitly release gates and are NOT
/// asserted here — only user-visible strings are.
void main() {
  final root = Directory.current.path;
  String read(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  group('사용자에게 보이는 이름 — "Human Status"로 통일', () {
    test('Android application label', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:label="Human Status"'));
      expect(manifest, isNot(contains('android:label="human_status"')));
    });

    test('iOS CFBundleName / CFBundleDisplayName', () {
      final plist = read('ios/Runner/Info.plist').replaceAll('\r\n', '\n');
      expect(
        plist,
        contains(
          '<key>CFBundleDisplayName</key>\n\t<string>Human Status</string>',
        ),
      );
      expect(
        plist,
        contains('<key>CFBundleName</key>\n\t<string>Human Status</string>'),
      );
    });

    test(
      'macOS CFBundleDisplayName is present, PRODUCT_NAME stays internal',
      () {
        final plist = read('macos/Runner/Info.plist');
        expect(plist, contains('<key>CFBundleDisplayName</key>'));
        expect(plist, contains('<string>Human Status</string>'));
        final appInfo = read('macos/Runner/Configs/AppInfo.xcconfig');
        // PRODUCT_NAME (internal build/scheme name) is intentionally unchanged.
        expect(appInfo, contains('PRODUCT_NAME = human_status'));
        expect(
          appInfo,
          contains(
            'PRODUCT_BUNDLE_IDENTIFIER = io.github.underkim.humanstatus',
          ),
        );
      },
    );

    test('Windows window title, FileDescription, ProductName', () {
      final mainCpp = read('windows/runner/main.cpp');
      expect(mainCpp, contains('window.Create(L"Human Status"'));
      final rc = read('windows/runner/Runner.rc');
      expect(rc, contains('VALUE "FileDescription", "Human Status"'));
      expect(rc, contains('VALUE "ProductName", "Human Status"'));
      // Internal executable/binary name stays human_status.exe.
      expect(rc, contains('VALUE "OriginalFilename", "human_status.exe"'));
      expect(rc, contains('VALUE "InternalName", "human_status"'));
    });

    test(
      'Linux GTK window/header title, BINARY_NAME and release APPLICATION_ID',
      () {
        final app = read('linux/runner/my_application.cc');
        expect(
          app,
          contains('gtk_header_bar_set_title(header_bar, "Human Status")'),
        );
        expect(app, contains('gtk_window_set_title(window, "Human Status")'));
        final cmake = read('linux/CMakeLists.txt');
        expect(cmake, contains('set(BINARY_NAME "human_status")'));
        expect(
          cmake,
          contains('set(APPLICATION_ID "io.github.underkim.humanstatus")'),
        );
      },
    );

    test(
      'Web manifest name/short_name, apple web app title, document title',
      () {
        final manifest =
            jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
        expect(manifest['name'], 'Human Status');
        expect(manifest['short_name'], 'Human Status');
        final index = read('web/index.html');
        expect(
          index,
          contains(
            '<meta name="apple-mobile-web-app-title" content="Human Status">',
          ),
        );
        expect(index, contains('<title>Human Status</title>'));
      },
    );
  });

  group('템플릿 설명 문구 제거', () {
    const templateDescription = 'A new Flutter project.';
    const productDescription =
        'Turn real-life actions into quests and grow every day.';

    test('pubspec.yaml', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, isNot(contains(templateDescription)));
      expect(pubspec, contains('description: "$productDescription"'));
    });

    test('web/manifest.json is valid JSON with the product description', () {
      final raw = read('web/manifest.json');
      final manifest = jsonDecode(raw) as Map<String, dynamic>;
      expect(manifest['description'], productDescription);
      expect(raw, isNot(contains(templateDescription)));
    });

    test('web/index.html meta description', () {
      final index = read('web/index.html');
      expect(index, isNot(contains(templateDescription)));
      expect(
        index,
        contains('<meta name="description" content="$productDescription">'),
      );
    });
  });

  group('웹 매니페스트 색상 — 앱 라이트 테마와 일치', () {
    test(
      'background_color / theme_color are the app palette, not Flutter blue',
      () {
        final manifest =
            jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
        expect(manifest['background_color'], '#F6F4EE');
        expect(manifest['theme_color'], '#2E6F5C');
        expect(manifest['background_color'], isNot('#0175C2'));
        expect(manifest['theme_color'], isNot('#0175C2'));
      },
    );
  });

  group('배포 메타데이터 플레이스홀더 제거', () {
    test('Windows CompanyName/LegalCopyright no longer say com.example', () {
      final rc = read('windows/runner/Runner.rc');
      expect(rc, contains('VALUE "CompanyName", "Human Status"'));
      expect(rc, contains('Human Status contributors'));
      expect(rc, isNot(contains('VALUE "CompanyName", "com.example"')));
    });

    test('macOS PRODUCT_COPYRIGHT no longer says com.example', () {
      final appInfo = read('macos/Runner/Configs/AppInfo.xcconfig');
      expect(appInfo, contains('Human Status contributors'));
      expect(
        appInfo,
        isNot(contains('PRODUCT_COPYRIGHT = Copyright © 2026 com.example.')),
      );
    });

    test('all platform release identifiers use the repository namespace', () {
      const releaseId = 'io.github.underkim.humanstatus';
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, contains('namespace = "$releaseId"'));
      expect(gradle, contains('applicationId = "$releaseId"'));
      expect(read('ios/Runner.xcodeproj/project.pbxproj'), contains(releaseId));
      expect(
        read('macos/Runner/Configs/AppInfo.xcconfig'),
        contains('PRODUCT_BUNDLE_IDENTIFIER = $releaseId'),
      );
      expect(
        read('linux/CMakeLists.txt'),
        contains('set(APPLICATION_ID "$releaseId")'),
      );
    });
  });

  group('macOS entitlements', () {
    test('Release build can write to user-selected files for backup export',
        () {
      final entitlements = Entitlements(read('macos/Runner/Release.entitlements'));
      expect(entitlements.isSet('com.apple.security.app-sandbox'), isTrue);
      expect(
        entitlements.isSet('com.apple.security.files.user-selected.read-write'),
        isTrue,
      );
      expect(
        entitlements.has('com.apple.security.files.user-selected.read-only'),
        isFalse,
      );
    });

    test('Debug and Profile builds retain read-only user-selected access', () {
      final entitlements =
          Entitlements(read('macos/Runner/DebugProfile.entitlements'));
      expect(entitlements.isSet('com.apple.security.app-sandbox'), isTrue);
      expect(entitlements.isSet('com.apple.security.network.client'), isTrue);
      expect(
        entitlements.has('com.apple.security.files.user-selected.read-write'),
        isFalse,
      );
      expect(
        entitlements.has('com.apple.security.files.user-selected.read-only'),
        isTrue,
      );
    });
  });
}

class Entitlements {
  final String content;
  Entitlements(this.content);

  bool has(String key) => content.contains('<key>$key</key>');
  bool? isSet(String key) {
    if (!has(key)) return null;
    final pattern = '<key>$key</key>\\s*<(\\w+)/>';
    final match = RegExp(pattern).firstMatch(content);
    if (match == null) return null;
    final value = match.group(1);
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }
}
