import 'dart:convert';
import 'dart:io';

import 'package:flutter_adto/src/services/install_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  final store = InstallStateStore();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('adto_install_state');
    await store.resetForTest(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await store.resetForTest();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> restart() => store.resetForTest(
    directoryProvider: () async => tempDir,
    keepFile: true,
  );

  test(
    'first launch starts attempt 1 with a fresh attempt id and a pending claim',
    () async {
      final d = await store.begin(packageFirstInstallTs: 1000);
      expect(d.kind, InstallDecisionKind.start);
      expect(d.state!.attempt, 1);
      expect(d.state!.status, InstallStatus.pending);
      expect(
        d.state!.installAttemptId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(d.state!.packageFirstInstallTs, 1000);
      final json = jsonDecode(
        await File(
          '${tempDir.path}/${InstallStateStore.fileName}',
        ).readAsString(),
      );
      expect(json['v'], 2);
      expect(json['status'], 'pending');
    },
  );

  test(
    'tracked installs are skipped on later launches and keep the install id',
    () async {
      await store.begin();
      await store.markTracked(
        installId: 'inst-1',
        referrerClaimed: true,
        referrerStatus: 'ok',
      );
      await restart();
      final d = await store.begin();
      expect(d.kind, InstallDecisionKind.alreadyTracked);
      expect(d.state!.installId, 'inst-1');
      expect(d.state!.referrerClaimed, isTrue);
    },
  );

  test(
    'a failed attempt retries on the next launch with the SAME attempt id (idempotency key)',
    () async {
      final first = await store.begin();
      await store.markFailed('HTTP 503');
      await restart();
      final second = await store.begin();
      expect(second.kind, InstallDecisionKind.start);
      expect(second.state!.attempt, 2);
      expect(second.state!.installAttemptId, first.state!.installAttemptId);
      expect(second.state!.lastError, 'HTTP 503');
      expect(
        second.state!.createdAt,
        first.state!.createdAt,
        reason: 'created_at_client is the FIRST attempt',
      );
    },
  );

  test(
    'a claim younger than the claim window is in flight; an older one never finished, and its retry says so',
    () async {
      final t0 = DateTime(2026, 10, 12, 10, 0);
      await store.begin(now: t0);
      await restart();
      expect(
        (await store.begin(now: t0.add(const Duration(seconds: 30)))).kind,
        InstallDecisionKind.inFlight,
      );
      await restart();
      // The longest try (reads, two posts, a back-off) ends within a
      // minute: a claim two minutes old belongs to an app that was closed.
      final retried = await store.begin(
        now: t0.add(const Duration(minutes: 2)),
      );
      expect(retried.kind, InstallDecisionKind.start);
      expect(retried.state!.attempt, 2);
      expect(retried.state!.lastError, 'interrupted');
    },
  );

  test(
    'failed tries are retried however many there are, until the install is 14 days old',
    () async {
      final t0 = DateTime(2026, 10, 12, 10, 0);
      await store.begin(now: t0);
      for (var i = 2; i <= 30; i++) {
        await store.markFailed('timeout', now: t0.add(Duration(hours: i)));
        await restart();
        final d = await store.begin(now: t0.add(Duration(hours: i)));
        expect(d.kind, InstallDecisionKind.start, reason: 'attempt $i');
        expect(d.state!.attempt, i);
      }
      await store.markFailed('timeout');
      await restart();
      final d = await store.begin(
        now: t0.add(InstallStateStore.maxAge + const Duration(minutes: 1)),
      );
      expect(d.kind, InstallDecisionKind.abandoned);
      await restart();
      expect(
        (await store.begin(
          now: t0.add(InstallStateStore.maxAge + const Duration(days: 1)),
        )).kind,
        InstallDecisionKind.abandoned,
      );
    },
  );

  /// What an older SDK left after ten failed launches.
  void writeAbandoned(DateTime createdAt) {
    File('${tempDir.path}/${InstallStateStore.fileName}').writeAsStringSync(
      jsonEncode({
        'v': 2,
        'status': 'abandoned',
        'install_attempt_id': '8b1e2b0a-7c1d-4f3e-9a2b-1c2d3e4f5a6b',
        'attempt': 10,
        'created_at': createdAt.toIso8601String(),
        'last_error': 'AdtoError: Failed to log app install: request timed out',
        'referrer_claimed': false,
        'referrer_launches': 0,
        'asa_claimed': false,
        'plugin_version': '1.0.1',
      }),
    );
  }

  test(
    'an install an older SDK gave up on after ten tries is retried while it is younger than 14 days',
    () async {
      final now = DateTime(2026, 11, 20, 9, 0);
      writeAbandoned(now.subtract(const Duration(days: 2)));
      await restart();
      final d = await store.begin(now: now);
      expect(d.kind, InstallDecisionKind.start);
      expect(d.state!.attempt, 11);
      expect(
        d.state!.installAttemptId,
        '8b1e2b0a-7c1d-4f3e-9a2b-1c2d3e4f5a6b',
        reason: 'the same idempotency key',
      );
      expect(
        d.state!.lastError,
        'AdtoError: Failed to log app install: request timed out',
      );
    },
  );

  test(
    'an install given up on more than 14 days after it began stays given up',
    () async {
      final now = DateTime(2026, 11, 20, 9, 0);
      writeAbandoned(now.subtract(const Duration(days: 20)));
      await restart();
      expect((await store.begin(now: now)).kind, InstallDecisionKind.abandoned);
    },
  );

  test(
    'a sentinel whose package first-install time changed is a stale restore and is discarded',
    () async {
      await store.begin(packageFirstInstallTs: 1000);
      await store.markTracked(installId: 'old', referrerClaimed: true);
      await restart();
      // Reinstalled app: PackageManager reports a new firstInstallTime.
      final d = await store.begin(packageFirstInstallTs: 2000);
      expect(d.kind, InstallDecisionKind.start);
      expect(d.state!.attempt, 1);
      expect(d.state!.installId, isNull);
      expect(d.state!.packageFirstInstallTs, 2000);
    },
  );

  test(
    'an unknown package time keeps the sentinel (no validation possible)',
    () async {
      await store.begin(packageFirstInstallTs: 1000);
      await store.markTracked(installId: 'old', referrerClaimed: true);
      await restart();
      expect((await store.begin()).kind, InstallDecisionKind.alreadyTracked);
    },
  );

  test('legacy or corrupt files are treated as absent', () async {
    final file = File('${tempDir.path}/${InstallStateStore.fileName}');
    await file.writeAsString(
      '{"status":"tracked","tracked_at":"2026-01-01T00:00:00Z"}',
    ); // v1 shape
    expect((await store.begin()).kind, InstallDecisionKind.start);
    await file.writeAsString('not json');
    await restart();
    expect((await store.begin()).kind, InstallDecisionKind.start);
  });

  test(
    'referrer bookkeeping: launches count up, claimed is sticky, asa flag persists',
    () async {
      await store.begin();
      await store.markTracked(
        installId: 'i',
        referrerClaimed: false,
        referrerStatus: 'service_unavailable',
      );
      await store.bumpReferrerLaunches();
      await store.bumpReferrerLaunches();
      await restart();
      var s = (await store.begin()).state!;
      expect(s.referrerLaunches, 2);
      expect(s.referrerClaimed, isFalse);
      await store.markReferrerClaimed('ok');
      await store.markAsaClaimed();
      await restart();
      s = (await store.begin()).state!;
      expect(s.referrerClaimed, isTrue);
      expect(s.referrerStatus, 'ok');
      expect(s.asaClaimed, isTrue);
    },
  );

  test('uuidV4 is version 4 / variant 1 and unique', () {
    final a = uuidV4();
    final b = uuidV4();
    expect(a, isNot(b));
    expect(a[14], '4');
    expect('89ab', contains(a[19]));
  });

  group('recovery after the server lost the install', () {
    test(
      'a tracked install restarts with a new attempt id, naming the lost id',
      () async {
        final first = await store.begin(packageFirstInstallTs: 1000);
        await store.markTracked(
          installId: 'lost-install',
          referrerClaimed: true,
          referrerStatus: 'ok',
        );
        expect(await store.beginRecovery('lost-install'), isTrue);

        await restart(); // survives a process kill
        final d = await store.begin(packageFirstInstallTs: 1000);
        expect(d.kind, InstallDecisionKind.start);
        expect(d.state!.recoveredFrom, 'lost-install');
        expect(d.state!.installAttemptId, isNot(first.state!.installAttemptId));
        expect(d.state!.attempt, 1);
        expect(
          d.state!.referrerClaimed,
          isTrue,
          reason: 'the referrer question stays settled',
        );
      },
    );

    test('a second signal for the same lost id changes nothing', () async {
      await store.begin(packageFirstInstallTs: 1000);
      await store.markTracked(
        installId: 'lost-install',
        referrerClaimed: false,
        referrerStatus: null,
      );
      expect(await store.beginRecovery('lost-install'), isTrue);
      final attemptId = (await store.load())!.installAttemptId;
      expect(await store.beginRecovery('lost-install'), isFalse);
      expect((await store.load())!.installAttemptId, attemptId);
    });
  });
}
