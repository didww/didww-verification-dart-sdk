import 'dart:convert';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/src/wire.dart';
import 'package:test/test.dart';

String _verificationJson({
  String status = 'pending',
  String deliveryMethod = 'sms',
  String? fee = '0.06',
  String? errorCode,
  String? errorDetail,
  Object? sms = const {
    'template': 'Your code is {{CODE}}',
    'language': 'en-US',
    'interception_timeout': 120
  },
  Object? callout,
}) {
  final data = <String, dynamic>{
    'id': '0f9c8b7a-1111-7222-8333-444455556666',
    'destination': '4915112345678',
    'delivery_method': deliveryMethod,
    'fee': fee,
    'status': status,
    'error_code': errorCode,
    'error_detail': errorDetail,
    'expires_at': '2026-08-25T12:00:00Z',
    if (sms != null) 'sms': sms,
    if (callout != null) 'callout': callout,
  };
  return jsonEncode({'data': data});
}

/// Typed access to a nested map, so the tests do not call into `dynamic`.
Map<String, dynamic> _data(Map<String, dynamic> body) =>
    body['data'] as Map<String, dynamic>;

Map<String, dynamic> _sms(Map<String, dynamic> body) =>
    _data(body)['sms'] as Map<String, dynamic>;

void main() {
  _languageTags();
  group('decoding a verification', () {
    test('an sms create', () {
      final v = decodeVerification(_verificationJson());
      expect(v.id, '0f9c8b7a-1111-7222-8333-444455556666');
      expect(v.knownDeliveryMethod, DeliveryMethod.sms);
      expect(v.knownStatus, VerificationStatus.pending);
      expect(v.isFinished, isFalse);
      expect(v.sms?.template, 'Your code is {{CODE}}');
      expect(v.sms?.interceptionTimeoutSeconds, 120);
      expect(v.expiresAt.isUtc, isTrue);
    });

    test('a create can arrive already denied', () {
      final v = decodeVerification(
        _verificationJson(
          status: 'denied',
          errorCode: 'denied_by_callback',
          errorDetail: 'your callback denied the request',
        ),
      );
      expect(v.knownStatus, VerificationStatus.denied);
      expect(v.isFinished, isTrue);
      expect(v.knownErrorCode, ApiErrorCode.deniedByCallback);
      expect(v.outcome?.known, ApiErrorCode.deniedByCallback);
    });

    test('an unknown status decodes and is never reported as finished', () {
      final v = decodeVerification(_verificationJson(status: 'pondering'));
      expect(v.status, 'pondering');
      expect(v.knownStatus, isNull);
      // A sixth status must not strand a caller by looking terminal.
      expect(v.isFinished, isFalse);
    });

    test('an unknown delivery method decodes', () {
      final v =
          decodeVerification(_verificationJson(deliveryMethod: 'telepathy'));
      expect(v.deliveryMethod, 'telepathy');
      expect(v.knownDeliveryMethod, isNull);
    });

    test('a null template is kept, because the key is always present', () {
      final v = decodeVerification(
        _verificationJson(
            sms: const {'template': null, 'interception_timeout': 120}),
      );
      expect(v.sms, isNotNull);
      expect(v.sms!.template, isNull);
    });

    test('app_hash is absent unless one was stored', () {
      final without = decodeVerification(
        _verificationJson(
            sms: const {'template': 't', 'interception_timeout': 120}),
      );
      expect(without.sms!.appHash, isNull);

      final with_ = decodeVerification(
        _verificationJson(
          sms: const {
            'template': 't',
            'interception_timeout': 120,
            'app_hash': 'A1b2C3d4E5f',
          },
        ),
      );
      expect(with_.sms!.appHash, 'A1b2C3d4E5f');
    });

    test('the chosen sms language is read', () {
      final v = decodeVerification(
        _verificationJson(
          sms: const {'template': 't', 'language': 'de-DE'},
        ),
      );
      expect(v.sms!.language, 'de-DE');
    });

    test('the callout block is read, and only on that channel', () {
      final v = decodeVerification(
        _verificationJson(
          deliveryMethod: 'callout',
          sms: null,
          callout: const {'language': 'pt-BR'},
        ),
      );
      expect(v.callout!.language, 'pt-BR');
      expect(v.sms, isNull);

      expect(decodeVerification(_verificationJson()).callout, isNull);
    });

    test('a missing interception timeout degrades rather than failing', () {
      final v = decodeVerification(
        _verificationJson(sms: const {'template': 't'}),
      );
      expect(v.sms!.interceptionTimeoutSeconds, isNull);
    });

    test('fee survives as a string and is never parsed', () {
      final v = decodeVerification(_verificationJson(fee: '0.0345'));
      expect(v.fee, '0.0345');
      expect(v.fee, isA<String>());
    });

    test('a null fee decodes rather than failing', () {
      expect(decodeVerification(_verificationJson(fee: null)).fee, isNull);
    });

    test('a structural violation throws, unlike an unknown value', () {
      expect(
        () => decodeVerification('not json at all'),
        throwsA(isA<DecodingException>()),
      );
      expect(
        () => decodeVerification(jsonEncode({'nope': 1})),
        throwsA(isA<DecodingException>()),
      );
      expect(
        () => decodeVerification(jsonEncode({
          'data': {'id': 'x'},
        })),
        throwsA(isA<DecodingException>()),
      );
    });
  });

  group('decoding an error envelope', () {
    test('resolves known codes', () {
      final items = decodeErrors(
        jsonEncode({
          'errors': [
            {'code': 'destination_invalid', 'detail': 'destination is invalid'},
          ],
        }),
      );
      expect(items, hasLength(1));
      expect(items.single.known, ApiErrorCode.destinationInvalid);
      expect(items.single.detail, 'destination is invalid');
    });

    test('an unknown code does not poison the rest of the array', () {
      final items = decodeErrors(
        jsonEncode({
          'errors': [
            {'code': 'a_code_from_the_future', 'detail': 'who knows'},
            {'code': 'code_blank', 'detail': "code can't be blank"},
          ],
        }),
      );
      expect(items, hasLength(2));
      expect(items[0].code, 'a_code_from_the_future');
      expect(items[0].known, isNull);
      expect(items[1].known, ApiErrorCode.codeBlank);
    });

    test('a multi-field failure yields one element per error', () {
      final items = decodeErrors(
        jsonEncode({
          'errors': [
            {
              'code': 'destination_blank',
              'detail': "destination can't be blank"
            },
            {
              'code': 'delivery_method_blank',
              'detail': "delivery method can't be blank"
            },
          ],
        }),
      );
      expect(items.map((e) => e.known), [
        ApiErrorCode.destinationBlank,
        ApiErrorCode.deliveryMethodBlank,
      ]);
    });

    test('a malformed envelope yields no elements rather than throwing', () {
      expect(decodeErrors('not json'), isEmpty);
      expect(decodeErrors(jsonEncode({'errors': 'nope'})), isEmpty);
      expect(
        decodeErrors(jsonEncode({
          'errors': [1, 'two'],
        })),
        isEmpty,
      );
    });
  });

  group('building a start body', () {
    test('normalises the destination to digits', () {
      final body = startBody(
        destination: '+49 (151) 1234-567',
        method: DeliveryMethod.sms,
      );
      expect(_data(body)['destination'], '491511234567');
    });

    test('rejects a destination with no digits before any request', () {
      expect(
        () => startBody(destination: '+-- ()', method: DeliveryMethod.sms),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('omits the sms block when there is nothing to put in it', () {
      final body =
          startBody(destination: '491511234567', method: DeliveryMethod.sms);
      expect(_data(body).containsKey('sms'), isFalse);
    });

    test('carries languages when given', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
        sms: const SmsOptions(languages: ['en-US', 'pl-PL']),
      );
      expect(_sms(body)['languages'], ['en-US', 'pl-PL']);
    });

    test('carries callout languages when given', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.callout,
        callout: const CalloutOptions(languages: ['pt-BR', 'pt-PT']),
      );
      expect(
        (_data(body)['callout'] as Map<String, dynamic>)['languages'],
        ['pt-BR', 'pt-PT'],
      );
    });

    test('omits the callout block when there is nothing to put in it', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.callout,
        callout: const CalloutOptions(),
      );
      expect(_data(body).containsKey('callout'), isFalse);
    });

    // Sending the other channel's options is harmless server-side, but sending
    // them is still a bug: only the block matching delivery_method is read.
    test('sends only the block matching the channel', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.callout,
        sms: const SmsOptions(languages: ['de-DE']),
        callout: const CalloutOptions(languages: ['pt-BR']),
        appHash: 'A1b2C3d4E5f',
      );
      expect(_data(body).keys.toSet(), {
        'destination',
        'delivery_method',
        'callout',
      });
    });

    test('sends a well-formed app hash', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
        appHash: 'A1b2C3d4E5f',
      );
      expect(_sms(body)['app_hash'], 'A1b2C3d4E5f');
    });

    test('drops a malformed app hash and sends the request anyway', () {
      // The API rejects a malformed hash and fails the whole verification, so a
      // bug in an optional convenience must not reach the wire — and must not
      // fail the paid operation either.
      for (final bad in [
        'tooshort',
        'twelvechars0',
        'has-a-dash!',
        'A1b2C3d4E5='
      ]) {
        final body = startBody(
          destination: '491511234567',
          method: DeliveryMethod.sms,
          appHash: bad,
        );
        expect(_data(body).containsKey('sms'), isFalse, reason: 'for "$bad"');
      }
    });

    test('a dropped hash produces a request identical to having none', () {
      final dropped = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
        appHash: 'bad',
      );
      final never = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
      );
      expect(jsonEncode(dropped), jsonEncode(never));
    });
  });

  group('building a report body', () {
    test('a code goes in the code field', () {
      expect(
        reportBody(
            deliveryMethod: 'sms', value: const ReportValue.code('123456')),
        {
          'data': {'delivery_method': 'sms', 'code': '123456'},
        },
      );
    });

    test('echoes an unmodelled channel verbatim', () {
      final body = reportBody(
        deliveryMethod: 'telepathy',
        value: const ReportValue.code('123456'),
      );
      expect(_data(body)['delivery_method'], 'telepathy');
    });
  });
}

void _languageTags() {
  group('language tags the API cannot accept are dropped, not sent', () {
    test('a well-formed tag is sent unchanged', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
        sms: const SmsOptions(languages: ['pt-BR', 'de-DE']),
      );
      expect(_sms(body)['languages'], ['pt-BR', 'de-DE']);
    });

    test('a tag with a script subtag is dropped rather than failing the start',
        () {
      // What Flutter's own Locale.toLanguageTag() produces for Chinese. Sent,
      // it returns 422 languages_invalid and no verification is created.
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
        sms: const SmsOptions(languages: ['zh-Hans-CN', 'en-US']),
      );
      expect(_sms(body)['languages'], ['en-US']);
    });

    test('the block is omitted when no requested tag survives', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.callout,
        callout: const CalloutOptions(languages: ['zh-Hant-TW', 'sr-Latn-RS']),
      );
      expect(_data(body).containsKey('callout'), isFalse);
    });

    test('the same rule applies on the callout channel', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.callout,
        callout: const CalloutOptions(languages: ['az-Latn-AZ', 'pt-PT']),
      );
      expect((_data(body)['callout']! as Map<String, dynamic>)['languages'],
          ['pt-PT']);
    });

    test('every tag the API accepts is recognised, and no more', () {
      const accepted = ['en', 'en-US', 'pt-BR', 'es-419', 'fil-PH', 'ka-GE'];
      const rejected = [
        'zh-Hans-CN',
        'zh-Hant-TW',
        'sr-Latn-RS',
        'az-Latn-AZ',
        'uz-Latn-UZ',
        'e',
        'toolong-US',
      ];
      for (final tag in accepted) {
        expect(languageTagFormat.hasMatch(tag), isTrue, reason: tag);
      }
      for (final tag in rejected) {
        expect(languageTagFormat.hasMatch(tag), isFalse, reason: tag);
      }
    });

    // The gate that used to wrap the whole block. An app hash has to survive a
    // start that requested no languages at all.
    test('an app hash is still sent when no languages were asked for', () {
      final body = startBody(
        destination: '491511234567',
        method: DeliveryMethod.sms,
        appHash: 'A1b2C3d4E5f',
      );
      expect(_sms(body), {'app_hash': 'A1b2C3d4E5f'});
    });
  });
}
