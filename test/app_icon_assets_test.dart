import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 앱 아이콘 자산 회귀 테스트.
///
/// `assets/branding/human_status_icon_master.png`(승인된 마스터 아트워크)와
/// `dart run flutter_launcher_icons`가 각 플랫폼에 생성한 파일들이 실제로
/// 디스크에 존재하고, 올바른 포맷/크기를 갖고, 단색 placeholder가 아닌
/// 실제 콘텐츠를 담고 있는지 파일 바이트를 직접 읽어 검증한다.
/// pubspec.yaml 상수만 비교하는 테스트는 구현이 잘못돼도 항상 통과하므로
/// 의미가 없다 — 여기서는 매번 실제 PNG/ICO 헤더를 파싱한다.

class _PngInfo {
  final int width;
  final int height;
  final int colorType;
  final int byteLength;
  _PngInfo(this.width, this.height, this.colorType, this.byteLength);
}

_PngInfo _readPng(String path) {
  final bytes = File(path).readAsBytesSync();
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  expect(
    bytes.take(8).toList(),
    signature,
    reason: '$path 가 유효한 PNG 시그니처로 시작해야 한다',
  );
  expect(
    String.fromCharCodes(bytes.sublist(12, 16)),
    'IHDR',
    reason: '$path 의 첫 청크가 IHDR 이어야 한다',
  );
  final width = ByteData.sublistView(bytes, 16, 20).getUint32(0);
  final height = ByteData.sublistView(bytes, 20, 24).getUint32(0);
  final colorType = bytes[25];
  return _PngInfo(width, height, colorType, bytes.length);
}

/// 실제 콘텐츠가 있는 이미지인지 확인하는 최소 압축 크기 기준.
/// 단색 placeholder PNG는 이 크기의 1/10 이하로 압축되므로 안전한 여유를 둔다.
void _expectNonTrivial(String path, _PngInfo info) {
  final minBytes = (info.width * info.height * 0.05).clamp(250, 1 << 30);
  expect(
    info.byteLength,
    greaterThan(minBytes),
    reason: '$path 가 단색/placeholder 이미지처럼 너무 작게 압축되어 있다',
  );
}

void _expectPng(
  String path, {
  required int width,
  required int height,
  bool noAlpha = false,
}) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path 파일이 존재해야 한다');
  final info = _readPng(path);
  expect(info.width, width, reason: '$path 의 너비가 $width 이어야 한다');
  expect(info.height, height, reason: '$path 의 높이가 $height 이어야 한다');
  if (noAlpha) {
    expect(
      info.colorType,
      isNot(6),
      reason: '$path 는 알파 채널이 없는 색상 타입이어야 한다(iOS 아이콘 요구사항)',
    );
  }
  _expectNonTrivial(path, info);
}

void main() {
  const masterPath = 'assets/branding/human_status_icon_master.png';

  group('마스터 아이콘 원본', () {
    test('assets/branding 에 승인된 마스터 PNG가 커밋되어 있다', () {
      expect(File(masterPath).existsSync(), isTrue);
      final info = _readPng(masterPath);
      expect(info.width, info.height, reason: '마스터 아이콘은 정사각형이어야 한다');
      expect(info.width, greaterThanOrEqualTo(512));
      _expectNonTrivial(masterPath, info);
    });
  });

  group('pubspec.yaml 아이콘 생성 설정', () {
    // pubspec.yaml 을 yaml 패키지 없이(비-dev 의존성 추가 없이) 텍스트로 직접
    // 검증한다: dart_dependency 목록에 없는 패키지를 테스트에서만 import하면
    // flutter_launcher_icons 버전이 바뀔 때 조용히 깨질 수 있다.
    late String pubspecText;

    setUpAll(() {
      pubspecText = File('pubspec.yaml').readAsStringSync();
    });

    test('flutter_launcher_icons 가 고정 버전 dev_dependency 로 선언되어 있다', () {
      final match = RegExp(
        r'^\s*flutter_launcher_icons:\s*(\d+\.\d+\.\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspecText);
      expect(
        match,
        isNotNull,
        reason: 'flutter_launcher_icons 는 caret 범위가 아닌 정확한 버전으로 고정되어야 한다',
      );
    });

    test('flutter_launcher_icons 설정이 커밋된 마스터 이미지를 가리킨다', () {
      final configStart = pubspecText.indexOf('\nflutter_launcher_icons:');
      expect(configStart, greaterThan(0), reason: '최상위 설정 블록이 있어야 한다');
      final config = pubspecText.substring(configStart);

      final imagePathOccurrences = RegExp(
        r'image_path:\s*"' + RegExp.escape(masterPath) + r'"',
      ).allMatches(config).length;
      // android/ios 최상위 + macos/windows/web 섹션까지 최소 4곳에서 같은
      // 마스터 이미지를 참조해야 플랫폼별로 다른 아트워크가 섞이지 않는다.
      expect(imagePathOccurrences, greaterThanOrEqualTo(4));

      expect(config.contains('android: true'), isTrue);
      expect(config.contains('ios: true'), isTrue);
      expect(config.contains('remove_alpha_ios: true'), isTrue);
      for (final platform in ['macos', 'windows', 'web']) {
        expect(config.contains('$platform:'), isTrue);
      }
    });

    test('마스터 이미지가 flutter assets 목록에도 포함되어 있다', () {
      expect(pubspecText.contains('- $masterPath'), isTrue);
    });
  });

  group('Android 런처 아이콘', () {
    test('AndroidManifest 가 @mipmap/ic_launcher 를 계속 참조한다', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest.contains('android:icon="@mipmap/ic_launcher"'), isTrue);
    });

    final expectedSizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };

    for (final entry in expectedSizes.entries) {
      test('mipmap-${entry.key}/ic_launcher.png 가 ${entry.value}px 이다', () {
        _expectPng(
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
          width: entry.value,
          height: entry.value,
        );
      });
    }
  });

  group('iOS 앱 아이콘', () {
    late Map<String, dynamic> contents;
    const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

    setUpAll(() {
      contents =
          jsonDecode(File('$dir/Contents.json').readAsStringSync())
              as Map<String, dynamic>;
    });

    test('Contents.json 의 모든 이미지가 실제 파일로 존재하고 알파 채널이 없다', () {
      final images = contents['images'] as List;
      expect(images, isNotEmpty);
      for (final image in images) {
        final size = double.parse((image['size'] as String).split('x').first);
        final scale = double.parse(
          (image['scale'] as String).replaceAll('x', ''),
        );
        final pixels = (size * scale).round();
        final filename = image['filename'] as String;
        _expectPng(
          '$dir/$filename',
          width: pixels,
          height: pixels,
          noAlpha: true,
        );
      }
    });
  });

  group('macOS 앱 아이콘', () {
    late Map<String, dynamic> contents;
    const dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

    setUpAll(() {
      contents =
          jsonDecode(File('$dir/Contents.json').readAsStringSync())
              as Map<String, dynamic>;
    });

    test('Contents.json 의 모든 이미지가 실제 파일로 존재한다', () {
      final images = contents['images'] as List;
      expect(images, isNotEmpty);
      for (final image in images) {
        final size = double.parse((image['size'] as String).split('x').first);
        final scale = double.parse(
          (image['scale'] as String).replaceAll('x', ''),
        );
        final pixels = (size * scale).round();
        final filename = image['filename'] as String;
        _expectPng('$dir/$filename', width: pixels, height: pixels);
      }
    });
  });

  group('Windows 아이콘', () {
    test('app_icon.ico 가 다중 크기(4개 이상, 256px 포함)를 담은 유효한 ICO다', () {
      final path = 'windows/runner/resources/app_icon.ico';
      final bytes = File(path).readAsBytesSync();
      // ICONDIR 헤더: reserved(2)=0, type(2)=1, count(2)
      expect(bytes[0], 0);
      expect(bytes[1], 0);
      expect(bytes[2], 1);
      expect(bytes[3], 0);
      final count = bytes[4] | (bytes[5] << 8);
      expect(count, greaterThanOrEqualTo(4), reason: '단일 크기만 담으면 회귀다');

      final sizes = <int>{};
      for (var i = 0; i < count; i++) {
        final entryOffset = 6 + i * 16;
        var width = bytes[entryOffset];
        var height = bytes[entryOffset + 1];
        if (width == 0) width = 256;
        if (height == 0) height = 256;
        sizes.add(width);
        expect(width, height, reason: 'ICO 항목은 정사각형이어야 한다');
      }
      expect(sizes.contains(256), isTrue, reason: '256px 항목이 포함되어야 한다');
      expect(
        bytes.length,
        greaterThan(20000),
        reason: 'ico 전체가 여러 실제 이미지를 담기엔 너무 작다(placeholder 의심)',
      );
    });
  });

  group('Web 아이콘 & 매니페스트', () {
    test('manifest.json 의 이름/색상/설명 메타데이터가 유지되어 있다', () {
      final manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['name'], 'Human Status');
      expect(manifest['short_name'], 'Human Status');
      expect(manifest['background_color'], '#F6F4EE');
      expect(manifest['theme_color'], '#2E6F5C');
      expect(
        manifest['description'],
        'Turn real-life actions into quests and grow every day.',
      );

      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      expect(icons, isNotEmpty);
      for (final icon in icons) {
        final sizeStr = (icon['sizes'] as String).split('x').first;
        final size = int.parse(sizeStr);
        final path = 'web/${icon['src']}';
        _expectPng(path, width: size, height: size);
        if (icon['purpose'] == 'maskable') {
          expect(
            (icon['src'] as String).contains('maskable'),
            isTrue,
            reason: 'maskable 항목은 별도 파일을 참조해야 한다',
          );
        }
      }
    });

    test('index.html 이 favicon 과 apple-touch-icon 을 계속 참조한다', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html.contains('href="favicon.png"'), isTrue);
      expect(html.contains('href="icons/Icon-192.png"'), isTrue);
      expect(html.contains('Human Status'), isTrue);
    });

    test('favicon.png 이 존재하고 비어있지 않다', () {
      final info = _readPng('web/favicon.png');
      expect(info.width, info.height);
      expect(info.width, greaterThanOrEqualTo(16));
      _expectNonTrivial('web/favicon.png', info);
    });
  });
}
