import 'dart:math';

/// A customer application the mock will authenticate.
final class MockApplication {
  const MockApplication({
    required this.key,
    required this.secret,
    required this.callbackUrl,
  });

  /// The application key, sent as the public-mode credential.
  final String key;

  /// The secret half of the Basic credential.
  final String secret;

  /// Where the mock asks whether a verification may start.
  ///
  /// Null models an application that has none, which is the only way to reach
  /// `denied_missing_callback_url`.
  final String? callbackUrl;
}

/// One verification held in memory.
final class MockVerification {
  MockVerification({
    required this.id,
    required this.applicationKey,
    required this.destination,
    required this.deliveryMethod,
    required this.fee,
    required this.expiresAt,
    required this.expectedValue,
    required this.status,
    this.errorCode,
    this.errorDetail,
    this.template,
    this.language,
    this.interceptionTimeout,
    this.appHash,
  });

  final String id;
  final String applicationKey;
  final String destination;
  final String deliveryMethod;
  final String fee;
  final DateTime expiresAt;

  /// The code or caller ID that will be accepted.
  final String expectedValue;

  final String? template;

  /// The tag the mock chose, echoed back on the channel's block.
  final String? language;

  final int? interceptionTimeout;
  final String? appHash;

  String status;
  String? errorCode;
  String? errorDetail;
  int attempts = 0;

  bool get isFinished => status != 'pending';

  /// Moves this verification to a finished status.
  void finish(String status, {String? code, String? detail}) {
    this.status = status;
    errorCode = code;
    errorDetail = detail;
  }

  /// Synthesises `expired` for an unfinished row whose deadline has passed.
  ///
  /// The API does not rewrite rows on a schedule, so this happens on read and a
  /// read can report a status the last write did not.
  void refresh(String expiredDetail) {
    if (!isFinished && DateTime.now().toUtc().isAfter(expiresAt)) {
      finish('expired', code: 'expired', detail: expiredDetail);
    }
  }

  /// The response body.
  Map<String, dynamic> toJson(String expiredDetail) {
    refresh(expiredDetail);

    return {
      'data': {
        'id': id,
        'destination': destination,
        'delivery_method': deliveryMethod,
        'fee': fee,
        'status': status,
        'error_code': errorCode,
        'error_detail': errorDetail,
        'expires_at': expiresAt.toIso8601String(),
        if (deliveryMethod == 'sms')
          'sms': {
            'template': template,
            'language': language,
            'interception_timeout': interceptionTimeout,
            if (appHash != null) 'app_hash': appHash,
          },
        if (deliveryMethod == 'callout') 'callout': {'language': language},
      },
    };
  }
}

/// Everything the mock remembers, for the life of the process.
final class MockState {
  MockState({
    required this.applications,
    required this.code,
    required this.ttl,
  });

  /// The applications the mock will authenticate.
  final List<MockApplication> applications;

  /// The code every sms and callout verification accepts.
  final String code;

  /// How long a new verification lives.
  final Duration ttl;

  final List<MockVerification> _verifications = [];
  final Random _random = Random.secure();

  /// The verification with [id], or null.
  MockVerification? byId(String id) {
    for (final v in _verifications.reversed) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// The active verification for [destination], or the most recent finished one.
  MockVerification? byNumber(String destination) {
    MockVerification? finished;
    for (final v in _verifications.reversed) {
      if (v.destination != destination) continue;
      if (!v.isFinished) return v;
      finished ??= v;
    }
    return finished;
  }

  /// Ends every live verification for [destination], as a newer one replaces it.
  void supersede(String destination, String detail) {
    for (final v in _verifications) {
      if (v.destination == destination && !v.isFinished) {
        v.finish('failed', code: 'superseded', detail: detail);
      }
    }
  }

  /// Records [verification] and returns it.
  MockVerification add(MockVerification verification) {
    _verifications.add(verification);
    return verification;
  }

  /// A fresh identifier.
  String newId() {
    String group(int bytes) => [
          for (var i = 0; i < bytes; i++)
            _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ].join();
    return '${group(4)}-${group(2)}-${group(2)}-${group(2)}-${group(6)}';
  }
}
