import 'package:flutter_adto/src/services/install_device_reads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aux = Duration(milliseconds: 1500);

  group('how long the device reads may take', () {
    test('Android: as long as the install referrer is waited for', () {
      expect(
        deviceReadTimeout(
          isAndroid: true,
          aux: aux,
          referrerTimeout: const Duration(seconds: 5),
        ),
        const Duration(seconds: 5),
      );
    });

    test('Android: never less than the usual budget', () {
      expect(
        deviceReadTimeout(
          isAndroid: true,
          aux: aux,
          referrerTimeout: const Duration(milliseconds: 500),
        ),
        aux,
      );
    });

    test('iOS has no referrer to wait for and keeps the usual budget', () {
      expect(
        deviceReadTimeout(
          isAndroid: false,
          aux: aux,
          referrerTimeout: const Duration(seconds: 5),
        ),
        aux,
      );
    });
  });

  group('the OS version an install reports', () {
    test('the hardware read wins on both platforms', () {
      expect(
        installOsVersion(
          isAndroid: true,
          hardwareVersion: '15',
          platformVersion: 'BP2A.250605.031.A3',
        ),
        '15',
      );
      expect(
        installOsVersion(
          isAndroid: false,
          hardwareVersion: '18.5',
          platformVersion: 'Version 18.5 (Build 22F76)',
        ),
        '18.5',
      );
    });

    test('Android sends nothing when the hardware read failed: '
        'the fallback is a build string, not a version', () {
      expect(
        installOsVersion(
          isAndroid: true,
          hardwareVersion: null,
          platformVersion: 'M1AJQ.T585XXU7CUH1',
        ),
        isNull,
      );
    });

    test('iOS falls back to dart:io, which carries the version', () {
      expect(
        installOsVersion(
          isAndroid: false,
          hardwareVersion: null,
          platformVersion: 'Version 18.5 (Build 22F76)',
        ),
        'Version 18.5 (Build 22F76)',
      );
    });
  });
}
