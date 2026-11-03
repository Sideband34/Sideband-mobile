import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the public download contract: the landing page links to
/// /releases/latest/download/sideband-android.apk, which only works while the
/// release workflow publishes a NON-prerelease with that exact asset name.
void main() {
  final wf = File('.github/workflows/release.yml').readAsStringSync();

  test('release workflow publishes a fixed-name APK as the latest release', () {
    expect(wf, contains('out="sideband-android.apk"'));
    expect(wf, contains(r'${{ env.APK }}.sha256'));
    expect(wf, contains('prerelease: false'));
    expect(wf, contains('make_latest: true'));
    expect(wf, contains("tags: ['v*']"));
  });

  test('launcher icon and app name are the brand ones', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="Sideband"'));
    expect(manifest, contains('@mipmap/ic_launcher'));
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
          File('android/app/src/main/res/mipmap-$d/ic_launcher.png')
              .existsSync(),
          isTrue,
          reason: d);
    }
    expect(
        File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
        contains('#130B12'));
  });
}
