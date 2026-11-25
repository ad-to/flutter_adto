import 'dart:convert';

/// Per-click link overrides: the `adto_*` query params on an AdTo
/// short link, e.g.
/// `https://you.adto.app/promo?adto_label=2323&adto_campaign=spring&adto_deeplink=myapp%3A%2F%2Fvoucher%3Fcode%3DX`.
///
/// [query] holds the URL's other parameters, the data a share adds.
///
/// After a deferred install the server returns them on the attribution
/// ([AdtoAppInstallResponse.clickParams]); on a warm open they are read
/// straight from the opened URL ([AdtoLinkClick.clickParams]).
class AdtoClickParams {
  /// In-app route from `adto_deeplink`, in the same shape as a link's
  /// deep-link path (`voucher?code=X`, no scheme). On a warm open this is the
  /// raw `adto_deeplink` value as it appeared in the URL.
  final String? deepLink;

  /// `adto_label` — free-form value for your own reporting.
  final String? label;

  /// `adto_campaign`
  final String? campaign;

  /// `adto_adgroup`
  final String? adgroup;

  /// `adto_creative`
  final String? creative;

  /// `adto_tracker`
  final String? tracker;

  /// The tapped URL's own query parameters (`?product=camera&ref=u_1` gives
  /// `{product: camera, ref: u_1}`): data a share adds to a link, which
  /// survives the install.
  ///
  /// Without the `adto_*` and `utm_*` keys and AdTo's own markers (`_ch`,
  /// `_ipad`, `_ref`); the first value of a repeated key; at most 20 keys
  /// and 2 KB, a key over 64 or a value over 256 characters (or one with a
  /// control character) left out. `null` when none is left. On a warm open it
  /// is read from the opened URL with the same rules the server applies to a
  /// tap. Links should not carry personal data.
  final Map<String, String>? query;

  const AdtoClickParams({
    this.deepLink,
    this.label,
    this.campaign,
    this.adgroup,
    this.creative,
    this.tracker,
    this.query,
  });

  /// Whether no value is set at all.
  bool get isEmpty =>
      deepLink == null &&
      label == null &&
      campaign == null &&
      adgroup == null &&
      creative == null &&
      tracker == null &&
      query == null;

  /// Server shape (`click_params` on the install/attribution response).
  factory AdtoClickParams.fromJson(Map<String, dynamic> json) {
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return AdtoClickParams(
      deepLink: s('deep_link'),
      label: s('label'),
      campaign: s('campaign'),
      adgroup: s('adgroup'),
      creative: s('creative'),
      tracker: s('tracker'),
      query: _stringMap(json['query']),
    );
  }

  /// The `adto_*` params and the own query parameters ([query]) of an
  /// opened link; null when it has neither.
  static AdtoClickParams? fromUri(Uri uri) {
    String? q(String key) {
      final v = uri.queryParameters['adto_$key']?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final params = AdtoClickParams(
      deepLink: q('deeplink'),
      label: q('label'),
      campaign: q('campaign'),
      adgroup: q('adgroup'),
      creative: q('creative'),
      tracker: q('tracker'),
      query: _tapQuery(uri),
    );
    return params.isEmpty ? null : params;
  }

  static const _maxQueryKeys = 20;
  static const _maxQueryKey = 64;
  static const _maxQueryValue = 256;
  static const _maxQueryBytes = 2048;
  static const _engineQueryKeys = {'_ch', '_ipad', '_ref'};
  static final _control = RegExp(r'[\u0000-\u001f\u007f]');

  /// The server's reading of a tap's own parameters, so a warm open and a
  /// deferred install give the app the same map.
  static Map<String, String>? _tapQuery(Uri uri) {
    final Map<String, List<String>> all;
    try {
      all = uri.queryParametersAll;
    } on FormatException {
      return null;
    }
    final out = <String, String>{};
    var bytes = 2; // {}
    for (final MapEntry(:key, value: values) in all.entries) {
      if (out.length >= _maxQueryKeys) break;
      final k = key.toLowerCase();
      if (key.isEmpty ||
          k.startsWith('adto_') ||
          k.startsWith('utm_') ||
          _engineQueryKeys.contains(k)) {
        continue;
      }
      final value = values.first;
      if (key.length > _maxQueryKey ||
          value.length > _maxQueryValue ||
          _control.hasMatch(key) ||
          _control.hasMatch(value)) {
        continue;
      }
      final size =
          jsonEncode(key).length +
          jsonEncode(value).length +
          (out.isEmpty ? 1 : 2);
      if (bytes + size > _maxQueryBytes) break;
      out[key] = value;
      bytes += size;
    }
    return out.isEmpty ? null : out;
  }

  /// The string values of a JSON object; `null` when it has none.
  static Map<String, String>? _stringMap(Object? json) {
    if (json is! Map) return null;
    final out = <String, String>{
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is String) key: value,
    };
    return out.isEmpty ? null : out;
  }

  Map<String, dynamic> toJson() => {
    'deep_link': deepLink,
    'label': label,
    'campaign': campaign,
    'adgroup': adgroup,
    'creative': creative,
    'tracker': tracker,
    'query': query,
  };

  @override
  String toString() =>
      'AdtoClickParams{deepLink: $deepLink, label: $label, campaign: $campaign, adgroup: $adgroup, creative: $creative, tracker: $tracker, query: $query}';
}
