import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'install response parses click_params and deep_link, and round-trips',
    () {
      final response = AdtoAppInstallResponse.fromJson({
        'matched': true,
        'type': 'non-organic',
        'slug': 'promo',
        'deep_link': 'voucher?code=ABC',
        'click_params': {
          'deep_link': 'voucher?code=ABC',
          'label': '2323',
          'campaign': 'refer_a_friend',
          'adgroup': null,
          'creative': null,
          'tracker': null,
        },
      });
      expect(response.deepLink, 'voucher?code=ABC');
      expect(response.clickParams?.label, '2323');
      expect(response.clickParams?.campaign, 'refer_a_friend');
      expect(response.clickParams?.adgroup, isNull);

      final again = AdtoAppInstallResponse.fromJson(response.toJson());
      expect(again.deepLink, 'voucher?code=ABC');
      expect(again.clickParams?.label, '2323');
    },
  );

  test('older payloads have no click params', () {
    final response = AdtoAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
    });
    expect(response.clickParams, isNull);
    expect(response.deepLink, isNull);
  });

  test('fromUri reads the adto_* keys and the URL\'s own parameters', () {
    final params = AdtoClickParams.fromUri(
      Uri.parse(
        'https://demo.adto.app/promo?adto_label=2323&adto_deeplink=myapp%3A%2F%2Fvoucher&label=x&adj_campaign=y&adto_tracker=t1',
      ),
    );
    expect(params?.label, '2323');
    expect(params?.deepLink, 'myapp://voucher');
    expect(params?.tracker, 't1');
    expect(params?.campaign, isNull);
    expect(params?.query, {'label': 'x', 'adj_campaign': 'y'});
  });

  test('fromUri: no adto_* and no own parameters means null', () {
    expect(
      AdtoClickParams.fromUri(
        Uri.parse('https://demo.adto.app/promo?utm_source=x&_ch=1&_ref=y'),
      ),
      isNull,
    );
    expect(
      AdtoClickParams.fromUri(Uri.parse('https://demo.adto.app/promo')),
      isNull,
    );
  });

  test('fromUri: the URL\'s own parameters alone make click params', () {
    final params = AdtoClickParams.fromUri(
      Uri.parse('https://demo.adto.app/shop?product=camera&color=red'),
    );
    expect(params?.deepLink, isNull);
    expect(params?.query, {'product': 'camera', 'color': 'red'});
    expect(params?.isEmpty, isFalse);
  });

  test('fromUri keeps the query within the server\'s limits', () {
    final many = [for (var i = 0; i < 25; i++) 'k$i=v$i'].join('&');
    final params = AdtoClickParams.fromUri(
      Uri.parse(
        'https://demo.adto.app/shop?$many&${'x' * 65}=long_key&big=${'v' * 257}&a=1&a=2',
      ),
    );
    expect(params!.query!.length, 20);
    expect(params.query!.keys.first, 'k0');
    expect(params.query!.containsKey('x' * 65), isFalse);
    expect(params.query!.containsKey('big'), isFalse);

    final repeated = AdtoClickParams.fromUri(
      Uri.parse('https://demo.adto.app/shop?a=1&a=2&empty='),
    );
    expect(repeated?.query, {'a': '1', 'empty': ''});
  });

  test(
    'fromUri: a repeated key takes its first valid value, as the server does',
    () {
      final params = AdtoClickParams.fromUri(
        Uri.parse(
          'https://demo.adto.app/shop?ref=${'v' * 257}&ref=good&tab=%01&tab=ok',
        ),
      );
      expect(params?.query, {'ref': 'good', 'tab': 'ok'});
    },
  );

  test('fromUri applies the key limit in URL order', () {
    // The server walks the pairs as written: a key whose first value was
    // invalid takes the place of its later, valid one.
    final middle = [for (var i = 0; i < 19; i++) 'k$i=v$i'].join('&');
    final params = AdtoClickParams.fromUri(
      Uri.parse(
        'https://demo.adto.app/shop?a=${'v' * 257}&$middle&a=ok&last=1&7=x',
      ),
    );
    expect(params!.query!.keys.length, 20);
    expect(params.query!.keys.first, 'k0');
    expect(params.query!.keys.last, 'a');
    expect(params.query!['a'], 'ok');
    expect(params.query!.containsKey('last'), isFalse);
    expect(params.query!.containsKey('7'), isFalse);
  });

  test(
    'fromUri decodes like the server: plus is a space, a bad escape stays',
    () {
      final params = AdtoClickParams.fromUri(
        Uri.parse(
          'https://demo.adto.app/shop?q=a+b%20c&flag&&pct=100%25&raw=%zz',
        ),
      );
      expect(params?.query, {
        'q': 'a b c',
        'flag': '',
        'pct': '100%',
        'raw': '%zz',
      });
    },
  );

  test('install response reads click_params.query and caches it', () {
    final response = AdtoAppInstallResponse.fromJson({
      'matched': true,
      'type': 'non-organic',
      'slug': 'shop',
      'click_params': {
        'deep_link': 'products/camera',
        'label': null,
        'campaign': null,
        'adgroup': null,
        'creative': null,
        'tracker': null,
        'query': {'product': 'camera', 'color': 'red', 'n': 3},
      },
      'routing': {
        'username': 'demo',
        'slug': 'shop',
        'deep_link': 'products/camera',
        'click_params': {
          'deep_link': 'products/camera',
          'query': {'product': 'camera'},
        },
        'confidence': 'high',
        'clicked_at': '2026-11-20T09:00:00.000Z',
      },
    });
    // A value that is not a string is not one the server sends; it is dropped.
    expect(response.clickParams?.query, {'product': 'camera', 'color': 'red'});
    expect(response.routing?.clickParams?.query, {'product': 'camera'});

    final again = AdtoAppInstallResponse.fromJson(response.toJson());
    expect(again.clickParams?.query, {'product': 'camera', 'color': 'red'});
    expect(again.routing?.clickParams?.query, {'product': 'camera'});
  });

  test('click_params without query (an older server) has a null query', () {
    final params = AdtoClickParams.fromJson({'deep_link': 'x', 'query': null});
    expect(params.query, isNull);
    expect(AdtoClickParams.fromJson({'deep_link': 'x'}).query, isNull);
    expect(AdtoClickParams.fromJson({'query': {}}).isEmpty, isTrue);
  });

  test('AdtoLinkClick exposes the opened URL click params', () {
    final click = AdtoLinkClick(
      originalUrl: 'https://demo.adto.app/promo?adto_campaign=spring',
      slug: 'promo',
      username: 'demo',
      receivedAt: DateTime(2026, 10, 11),
    );
    expect(click.clickParams?.campaign, 'spring');
  });

  test('AdtoLinkClick exposes the opened URL\'s own parameters as query', () {
    final click = AdtoLinkClick(
      originalUrl: 'https://demo.adto.app/shop?product=camera&adto_campaign=x',
      slug: 'shop',
      username: 'demo',
      receivedAt: DateTime(2026, 11, 25),
    );
    expect(click.clickParams?.query, {'product': 'camera'});
  });
}
