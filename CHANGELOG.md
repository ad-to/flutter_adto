# Changelog

All notable changes to flutter_adto are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-25

### Added

- **`AdtoClickParams.query`: data a share adds to a link, after the install too.** A link
  shared as `https://you.adto.app/shop?product=camera&ref=u_1` gives the app
  `{product: camera, ref: u_1}`. The server has returned these parameters on the install verdict
  and its `routing` (`click_params.query`) since adto #138; the SDK now reads them and keeps them
  in the cached verdict. On a warm open the SDK reads them from the opened URL with the server's
  rules (no `adto_*`, `utm_*` or AdTo's own markers; the first value of a repeated key; at most
  20 keys and 2 KB), so the app reads `clickParams?.query` the same way in both cases.

### Changed

- **`AdtoLinkClick.clickParams` (and `AdtoClickParams.fromUri`) is no longer `null` for a URL
  that carries only its own parameters**: `https://you.adto.app/shop?product=camera` now gives
  click params with only `query` set. A URL with neither `adto_*` values nor own parameters still
  gives `null`.

## [1.1.0] - 2026-11-22

### Added

- **`AdtoLink.forwardQuery` and `AdtoLink.createdVia`.** The server now returns whether a link
  copies a tap's own query parameters onto its web destinations, and where the link was made
  (`dashboard`, `api`, `sdk` or `mcp`; null for an older link whose origin is unknown). The wire
  fixtures are synced from the server.
- **`previous_error` on a retried install registration**
  (`AdtoAppInstallRequest.previousError`): why the try before it failed — `timeout`, `dns`,
  `tls`, `connection`, `http_<status>` with the server's error code (`http_401:stale_timestamp`),
  `interrupted` (the app was closed first) or `other`. A short word, never an error's text.

### Fixed

- **An app open on a later launch carries the device id.** The id was taken from a copy that only
  the first launch's install registration filled, so a link that opened the app after that sent
  the open with its install id but no device id. The open now reads the id the way the daily
  ping does, and still leaves it out when `AdtoConfig.collect` turns the device tier off.
- **An install that fails at the first launch is tried again in the same session.** It used to
  wait for the next launch while `identify` and events, which ride their own retrying queue, went
  through, so the dashboard showed customers with no install. A failed try is now retried in
  the same session after 30 seconds and then longer waits (the last, 10 minutes, repeats). After
  a failed connection (no network, a timeout) it is also tried at once when the app comes back to
  the foreground or a queued event goes through; a server that answered with a 5xx, 408 or 429
  keeps the waits, and a longer `Retry-After`, so waiting phones never hammer it. A refusal the
  same request would meet again (any other 4xx) still waits for the next launch.
- **An event batch with no install id waits for the install.** Before the install is
  registered, a batch first waits, at most 45 seconds, for an install try that is in flight or
  due, so `identify` carries the install id. `flush()`, `logout()` and `dispose()` can take that
  long in that case.
- **A relaunch soon after the app was closed mid-try no longer skips the install.** Another try's
  claim held for 5 minutes; it now holds for 90 seconds (the longest try ends within a minute),
  and the session checks again when it runs out.
- **The SDK no longer gives up after ten failed launches.** It keeps trying until the install is
  14 days old, however many tries that takes, and an install an earlier version gave up on is
  tried again while it is younger than that.
- **A retry in the same session reuses the first-launch pasteboard read** instead of reading
  again (on iOS, asking again).
- **iOS: the paste alert no longer freezes the app.** On iOS 16+ the first-launch pasteboard read
  waits for the user to answer "Allow Paste", and it held the main thread while it waited. Flutter
  runs Dart on that thread, so the app's UI and `initialize()` stopped until the user answered
  (about 20 seconds in a test). The read now runs on a background queue: the app keeps drawing,
  `initialize()` returns once the install is registered, and a late "Allow Paste" still upgrades
  the install through its claim.

## [1.0.1] - 2026-11-17

### Fixed

- **Slow Android phones no longer send an install without its device.** The device id and
  hardware reads had 1.5 s each; on a slow phone's first launch they timed out, and about 2 % of
  Android installs reached the server with no device id, model, manufacturer or CPU. They now
  get as long as the install referrer read beside them already waits
  (`installReferrerTimeout`, 5 s by default), so a normal launch is no slower.
- **Android never reports a build string as its OS version.** When the hardware read failed,
  `os_version` fell back to dart:io's value, which on Android is the build's display string
  (`M1AJQ.T585XXU7CUH1`). Android now sends no version in that case.

## [1.0.0] - 2026-11-12

First release of flutter_adto, the Flutter SDK for AdTo.

- **Package:** `flutter_adto` (`package:flutter_adto/flutter_adto.dart`), and
  `flutter_adto_adid` for the advertising identifier. iOS through Swift Package Manager or
  CocoaPods; the Android plugin is `app.adto.flutter_adto`.
- **Types:** `FlutterAdto`, `AdtoConfig`, `AdtoLink`, `AdtoLinkClick`, `AdtoError`,
  `AdtoPasteButton`, `AdtoNavigatorObserver` and the rest, all with the `Adto` prefix.
- **Hosts:** `AdtoConfig.defaultBaseUrl` is `https://api.adto.app` and
  `defaultLinkRootDomain` is `adto.app`.
- **Wire:** the `x-adto-*` request headers (`x-adto-sdk: flutter_adto/<version>`), the
  `AdtoSDK/` user-agent token, `adto_` keys and link parameters (`adto_click`, `adto_l`,
  `adto_deeplink`…) and `adto://` development links.
- **On the device:** the SDK keeps `.adto_*.json` files in its `adto` folder and its iOS
  Keychain items under the service `app.adto.sdk`.
