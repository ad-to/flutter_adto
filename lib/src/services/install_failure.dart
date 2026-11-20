import 'dart:async';

import '../models/adto_error.dart';

/// Why an install registration try failed, as the next try reports it in
/// `previous_error` (the server's API_CONTRACT.md):
///
/// - `timeout`: no answer within the deadline
/// - `dns`: the host name lookup failed, usually no connection at all
/// - `tls`: the secure connection (handshake or certificate) failed
/// - `connection`: any other connection error (refused, reset, unreachable)
/// - `http_<status>` or `http_<status>:<code>`: the server refused it, with
///   the error envelope's code when there was one
/// - `interrupted`: the try never finished; the app was closed first
///   (InstallStateStore sets it)
/// - `other`: anything else
///
/// A reason is a short word the server can store, never an error's text.
String installFailureReason(Object error) {
  if (error is AdtoError) {
    final status = error.statusCode;
    if (status != null) return _httpReason(status, error.code);
    return _reasonFromText(error.message);
  }
  if (error is TimeoutException) return 'timeout';
  return _reasonFromText(error.toString());
}

/// The reason to send for a stored [lastError]. This SDK stores the reason
/// itself; an older one stored the error's text, which reads the same way.
/// Null when nothing was stored.
String? previousErrorForWire(String? lastError) {
  if (lastError == null || lastError.isEmpty) return null;
  if (_reasons.contains(lastError) || _httpReasonRe.hasMatch(lastError)) {
    return lastError;
  }
  final status = _storedStatusRe.firstMatch(lastError);
  if (status != null) {
    return _httpReason(int.parse(status.group(1)!), status.group(2));
  }
  return _reasonFromText(lastError);
}

/// Whether a try that failed for [reason] may work in a minute, so the
/// same session tries again. A refusal the same request would meet again
/// (a 4xx other than 408 and 429) waits for the next launch, so a refused
/// device does not hammer the server.
bool isTransientInstallFailure(String reason) {
  final http = _httpReasonRe.firstMatch(reason);
  if (http != null) {
    final status = int.parse(http.group(1)!);
    return status >= 500 || status == 408 || status == 429;
  }
  return reason != 'other';
}

/// Whether [reason] is a failure a working connection may fix (no
/// connection, a timeout, an app closed mid-try), as opposed to a server
/// that answered. The app coming back, or an event batch that went through,
/// starts the first kind again at once; a server's refusal keeps its own
/// back-off, or every waiting phone would retry a failing server.
bool isTransportFailure(String reason) => _transportReasons.contains(reason);

const _transportReasons = {
  'timeout',
  'dns',
  'tls',
  'connection',
  'interrupted',
};

const _reasons = {
  'timeout',
  'dns',
  'tls',
  'connection',
  'interrupted',
  'other',
};

final _httpReasonRe = RegExp(r'^http_(\d{3})(?::[a-z0-9_.-]{1,40})?$');
final _codeRe = RegExp(r'^[a-z0-9_.-]{1,40}$');

/// `AdtoError.toString()`'s "(Status: 401, stale_timestamp)".
final _storedStatusRe = RegExp(r'\(Status: (\d{3})(?:, ([^)\s]+))?\)');

String _httpReason(int status, String? code) =>
    code != null && _codeRe.hasMatch(code)
        ? 'http_$status:$code'
        : 'http_$status';

/// A transport failure, from the text dart:io and package:http give it.
String _reasonFromText(String text) {
  if (text.contains('timed out') || text.contains('TimeoutException')) {
    return 'timeout';
  }
  if (text.contains('Failed host lookup') ||
      text.contains('No address associated with hostname') ||
      text.contains('nodename nor servname')) {
    return 'dns';
  }
  if (text.contains('HandshakeException') ||
      text.contains('TlsException') ||
      text.contains('CertificateException') ||
      text.contains('CERTIFICATE_VERIFY_FAILED')) {
    return 'tls';
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('HttpException') ||
      text.contains('Network error')) {
    return 'connection';
  }
  return 'other';
}
