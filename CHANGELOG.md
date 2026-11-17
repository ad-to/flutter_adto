# Changelog

All notable changes to flutter_adto are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

flutter_adto is the SDK of AdTo, a new service. It starts from flutter_dectog 1.0.x, the DecTog
service's SDK, with every name made AdTo's; it shares no names or device data with it. See
"Moving from flutter_dectog" in the README.

- **Package:** `flutter_adto` (`package:flutter_adto/flutter_adto.dart`), and
  `flutter_adto_adid` for the advertising identifier. The iOS Swift package and pod, the Android
  plugin (`app.adto.flutter_adto`) and the method channels are renamed too, so the two plugins
  never clash in one app.
- **Types:** every `Dectog` prefix becomes `Adto`: `FlutterAdto`, `AdtoConfig`, `AdtoLink`,
  `AdtoLinkClick`, `AdtoError`, `AdtoPasteButton`, `AdtoNavigatorObserver` and the rest.
- **Hosts:** `AdtoConfig.defaultBaseUrl` is `https://api.adto.app` and
  `defaultLinkRootDomain` is `adto.app`.
- **Wire:** the `x-adto-*` request headers (`x-adto-sdk: flutter_adto/<version>`), the
  `AdtoSDK/` user-agent token, `adto_` keys and link parameters (`adto_click`, `adto_l`,
  `adto_deeplink`…) and `adto://` development links.
- **On the device:** the SDK keeps `.adto_*.json` files in its `adto` folder and its iOS
  Keychain items under the service `app.adto.sdk`.
