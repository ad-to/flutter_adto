import 'dart:async';
import 'dart:io';

import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_adto/src/services/install_failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Why an install try failed, as the next try reports it in
/// `previous_error`. The server stores only `[a-z0-9_:.-]{1,64}`, so a
/// reason is a short word, never an error's text.
void main() {
  group('installFailureReason', () {
    test('a request that got no answer in time timed out', () {
      expect(
        installFailureReason(
          AdtoError.networkError(
            'Failed to log app install: request timed out',
          ),
        ),
        'timeout',
      );
      expect(installFailureReason(TimeoutException('no answer')), 'timeout');
    });

    test('a failed host lookup is dns: usually no connection at all', () {
      expect(
        installFailureReason(
          AdtoError.networkError(
            "Network error: ClientException with SocketException: Failed host lookup: 'api.adto.app' (OS Error: nodename nor servname provided, or not known, errno = 8), uri=https://api.adto.app/api/v1/app-installs",
          ),
        ),
        'dns',
      );
      expect(
        installFailureReason(
          const SocketException(
            "Failed host lookup: 'api.adto.app'",
            osError: OSError('No address associated with hostname', 7),
          ),
        ),
        'dns',
      );
    });

    test('a failed handshake or certificate is tls', () {
      expect(
        installFailureReason(
          AdtoError.networkError(
            'Network error: HandshakeException: Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate(handshake.cc:393))',
          ),
        ),
        'tls',
      );
    });

    test('any other transport failure is connection', () {
      expect(
        installFailureReason(
          AdtoError.networkError(
            'Network error: ClientException with SocketException: Connection refused (OS Error: Connection refused, errno = 61), address = api.adto.app, port = 443',
          ),
        ),
        'connection',
      );
      expect(
        installFailureReason(const SocketException('Connection reset by peer')),
        'connection',
      );
    });

    test("a server's refusal is its status and its error code", () {
      expect(
        installFailureReason(
          AdtoError.fromResponse(
            statusCode: 401,
            body:
                '{"error":{"code":"stale_timestamp","message":"SDK request timestamp is stale or invalid","request_id":"r1"}}',
            fallbackMessage: 'Failed to log app install (HTTP 401)',
          ),
        ),
        'http_401:stale_timestamp',
      );
      // A proxy's page has no code.
      expect(
        installFailureReason(
          AdtoError.fromResponse(
            statusCode: 503,
            body: '<html>Service Unavailable</html>',
            fallbackMessage: 'Failed to log app install (HTTP 503)',
          ),
        ),
        'http_503',
      );
      // A code that is not a plain word is left out, never sent.
      expect(
        installFailureReason(
          AdtoError.apiError(
            message: 'x',
            statusCode: 400,
            code: 'Bad Request!',
          ),
        ),
        'http_400',
      );
    });

    test('anything else is other', () {
      expect(installFailureReason(const FormatException('bad json')), 'other');
    });
  });

  group('previousErrorForWire', () {
    test('a reason this SDK stored goes as it is', () {
      for (final reason in [
        'timeout',
        'dns',
        'tls',
        'connection',
        'interrupted',
        'other',
        'http_503',
        'http_401:stale_timestamp',
      ]) {
        expect(previousErrorForWire(reason), reason);
      }
    });

    test('the error text an older SDK stored is read the same way', () {
      expect(
        previousErrorForWire(
          'AdtoError: Failed to log app install: request timed out',
        ),
        'timeout',
      );
      expect(
        previousErrorForWire(
          "AdtoError: Network error: ClientException with SocketException: Failed host lookup: 'api.adto.app' (OS Error: No address associated with hostname, errno = 7)",
        ),
        'dns',
      );
      expect(
        previousErrorForWire(
          'AdtoError: SDK request timestamp is stale or invalid (Status: 401, stale_timestamp) [request r1] Details: {code: stale_timestamp}',
        ),
        'http_401:stale_timestamp',
      );
      expect(
        previousErrorForWire('AdtoError: Bad gateway (Status: 502)'),
        'http_502',
      );
    });

    test('nothing stored sends nothing', () {
      expect(previousErrorForWire(null), isNull);
      expect(previousErrorForWire(''), isNull);
    });
  });

  group('isTransportFailure', () {
    test(
      'no connection, a timeout or a closed app: a working connection may fix it',
      () {
        for (final reason in [
          'timeout',
          'dns',
          'tls',
          'connection',
          'interrupted',
        ]) {
          expect(isTransportFailure(reason), isTrue, reason: reason);
        }
      },
    );

    test('a server that answered keeps its own back-off', () {
      for (final reason in ['http_503', 'http_429', 'http_408', 'other']) {
        expect(isTransportFailure(reason), isFalse, reason: reason);
      }
    });
  });

  group('isTransientInstallFailure', () {
    test('a try that may work in a minute is retried in the same session', () {
      for (final reason in [
        'timeout',
        'dns',
        'tls',
        'connection',
        'interrupted',
        'http_500',
        'http_503',
        'http_408',
        'http_429',
      ]) {
        expect(isTransientInstallFailure(reason), isTrue, reason: reason);
      }
    });

    test(
      'a refusal that the same request meets again waits for the next launch',
      () {
        for (final reason in [
          'http_400',
          'http_401:stale_timestamp',
          'http_403',
          'http_413',
          'other',
        ]) {
          expect(isTransientInstallFailure(reason), isFalse, reason: reason);
        }
      },
    );
  });
}
