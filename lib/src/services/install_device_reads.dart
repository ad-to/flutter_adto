/// Two rules for the device reads behind an install report.
///
/// Why they exist: on a slow Android phone the first launch is the busiest
/// moment the app has. With 1.5 s each, the device id and hardware reads
/// timed out on about 2 % of Android installs, which then reached the
/// server with no model, no device id, and the build's display string
/// where the Android version belongs.
library;

/// How long the device id and hardware reads may take.
///
/// On Android the install report already waits for the store's install
/// referrer, up to [referrerTimeout], and the reads run beside it: giving
/// them the same time costs a normal launch nothing and lets a slow one
/// finish. iOS has no referrer to wait for and keeps [aux].
Duration deviceReadTimeout({
  required bool isAndroid,
  required Duration aux,
  required Duration referrerTimeout,
}) => isAndroid && referrerTimeout > aux ? referrerTimeout : aux;

/// The OS version an install reports: the hardware read's, else dart:io's
/// on iOS only.
///
/// dart:io's `Platform.operatingSystemVersion` is "Version 17.5 (Build
/// 21F79)" on iOS, which carries the version, and the build's display
/// string on Android ("M1AJQ.T585XXU7CUH1"), which does not.
String? installOsVersion({
  required bool isAndroid,
  required String? hardwareVersion,
  required String? platformVersion,
}) => hardwareVersion ?? (isAndroid ? null : platformVersion);
