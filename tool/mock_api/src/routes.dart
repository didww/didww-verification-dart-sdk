import 'dart:convert';
import 'dart:io';

import 'auth.dart';
import 'callback.dart';
import 'contract.dart';
import 'state.dart';

final RegExp _destinationShape = RegExp(r'^\+?\d{8,15}$');
final RegExp _strippedBeforeMatch = RegExp(r'[\s\-()]');
final RegExp _languageTag = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$');

const String _fallbackLanguage = 'en-US';

/// A stand-in for the server's language tables, deliberately small.
///
/// The real sets are far larger, differ per channel and change without a client
/// release, so the mock reproduces the *behaviour* — an unservable tag falls
/// back to [_fallbackLanguage] instead of failing — rather than the data.
const Set<String> _servableLanguages = {_fallbackLanguage, 'de-DE', 'pt-BR'};

/// Canonicalises as the API does: primary subtag lowercased, region uppercased.
///
/// The echoed tag is the canonical one, so a client that compares its own
/// spelling against the response sees a difference the API did not intend.
String _canonicalLanguage(String tag) {
  final parts = tag.trim().split('-');
  if (parts.length < 2) return parts.first.toLowerCase();
  return '${parts.first.toLowerCase()}-${parts[1].toUpperCase()}';
}

String _resolveLanguage(List<String>? requested) => (requested ??
        const <String>[])
    .map(_canonicalLanguage)
    .firstWhere(_servableLanguages.contains, orElse: () => _fallbackLanguage);

/// The five verification routes, plus the callback receivers the mock serves for
/// itself so a full run needs no second process.
final class MockApi {
  MockApi({
    required this.contract,
    required this.state,
    required this.log,
  }) : _prefix = contract.apiPrefix
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .toList();

  final WireContract contract;
  final MockState state;
  final void Function(String line) log;

  final List<String> _prefix;

  /// Routes one request.
  Future<void> handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    try {
      await _route(request, segments);
    } on Object catch (e, s) {
      log('unhandled: $e\n$s');
      await _write(request, 500, _envelope(['internal_error']));
    }
    await request.response.close();
  }

  Future<void> _route(HttpRequest request, List<String> segments) async {
    final method = request.method.toUpperCase();

    if (segments.length == 2 && segments[0] == '_callback') {
      return _serveCallback(request, segments[1]);
    }
    if (segments.length == 1 && segments[0] == '_health') {
      return _write(request, 200, {'ok': true});
    }

    final rest = _underPrefix(segments);
    if (rest == null || rest.isEmpty || rest[0] != 'verifications') {
      return _write(request, 404, _envelope(['not_found']));
    }

    final auth = authenticate(
        request.headers.value('authorization'), state.applications);
    if (!auth.authenticated) {
      log('  auth rejected: scheme ${auth.scheme.name}');
      return _write(request, 401, _envelope(['unauthorized']));
    }
    final application = auth.application!;

    // by_number is checked first: without it a request for the id "by_number"
    // would take the id route and 404 on a live verification.
    final byNumber = rest.length == 3 && rest[1] == 'by_number';
    final byId = rest.length == 2;

    if (rest.length == 1 && method == 'POST') {
      return _start(request, application);
    }
    if (byNumber || byId) {
      final key = rest.last;
      final verification = byNumber ? state.byNumber(key) : state.byId(key);
      if (verification == null ||
          verification.applicationKey != application.key) {
        return _write(request, 404, _envelope(['not_found']));
      }
      if (method == 'GET') {
        return _write(
            request, 200, verification.toJson(contract.detail('expired')));
      }
      if (method == 'PUT' || method == 'PATCH') {
        return _report(request, verification);
      }
    }

    return _write(request, 404, _envelope(['not_found']));
  }

  List<String>? _underPrefix(List<String> segments) {
    if (segments.length < _prefix.length) return null;
    for (var i = 0; i < _prefix.length; i++) {
      if (segments[i] != _prefix[i]) return null;
    }
    return segments.sublist(_prefix.length);
  }

  Future<void> _start(HttpRequest request, MockApplication application) async {
    final data = await _dataObject(request);
    if (data == null) {
      return _write(request, 400, _envelope(['parameter_missing']));
    }

    final failures = <String>[];
    final destination = data['destination'];
    if (destination is! String || destination.isEmpty) {
      failures.add('destination_blank');
    } else if (!_destinationShape
        .hasMatch(destination.replaceAll(_strippedBeforeMatch, ''))) {
      failures.add('destination_invalid');
    }

    final deliveryMethod = data['delivery_method'];
    if (deliveryMethod is! String || deliveryMethod.isEmpty) {
      failures.add('delivery_method_blank');
    } else if (!contract.deliveryMethods.contains(deliveryMethod)) {
      failures.add('delivery_method_inclusion');
    }

    // Only the block named after the delivery method is read; the others are
    // ignored rather than rejected, so a malformed sms block on a callout
    // request is not an error.
    String? appHash;
    List<String>? languages;
    final block = deliveryMethod is String ? data[deliveryMethod] : null;
    if (block is Map) {
      final requested = block['languages'];
      if (requested != null) {
        if (requested is! List ||
            requested
                .any((tag) => tag is! String || !_languageTag.hasMatch(tag))) {
          failures.add('languages_invalid');
        } else {
          languages = requested.cast<String>();
        }
      }
      final hash = block['app_hash'];
      if (hash != null) {
        if (hash is! String || !contract.appHashFormat.hasMatch(hash)) {
          failures.add('app_hash_invalid');
        } else {
          appHash = hash;
        }
      }
    }

    if (failures.isNotEmpty) {
      return _write(request, 422, _envelope(failures));
    }

    final digits = (destination! as String).replaceAll(RegExp(r'\D'), '');
    state.supersede(digits, contract.detail('superseded'));

    final method = deliveryMethod! as String;
    final verification = state.add(
      MockVerification(
        id: state.newId(),
        applicationKey: application.key,
        destination: digits,
        deliveryMethod: method,
        fee: '0.0345',
        expiresAt: DateTime.now().toUtc().add(state.ttl),
        expectedValue: state.code,
        status: 'pending',
        template: method == 'sms' ? 'Your code is {{CODE}}' : null,
        language: _resolveLanguage(languages),
        interceptionTimeout: method == 'sms' ? 120 : null,
        appHash: appHash,
      ),
    );

    await _authorize(verification, application, method);
    return _write(
        request, 201, verification.toJson(contract.detail('expired')));
  }

  /// Runs the customer-callback authorization, which is the only path to the
  /// three `denied_*` outcomes.
  Future<void> _authorize(
    MockVerification verification,
    MockApplication application,
    String deliveryMethod,
  ) async {
    final callbackUrl = application.callbackUrl;
    if (callbackUrl == null) {
      log('  no callback url on ${application.key}');
      return verification.finish(
        'denied',
        code: 'denied_missing_callback_url',
        detail: contract.detail('denied_missing_callback_url'),
      );
    }

    final verdict = await askCallback(
      callbackUrl,
      signingSecret: application.secret,
      destination: verification.destination,
      deliveryMethod: deliveryMethod,
    );
    log('  callback $callbackUrl -> ${verdict.name}');

    switch (verdict) {
      case CallbackVerdict.allowed:
        return;
      case CallbackVerdict.denied:
        return verification.finish(
          'denied',
          code: 'denied_by_callback',
          detail: contract.detail('denied_by_callback'),
        );
      case CallbackVerdict.invalid:
        return verification.finish(
          'denied',
          code: 'denied_invalid_callback_response',
          detail: contract.detail('denied_invalid_callback_response'),
        );
    }
  }

  Future<void> _report(
      HttpRequest request, MockVerification verification) async {
    final data = await _dataObject(request);
    if (data == null) {
      return _write(request, 400, _envelope(['parameter_missing']));
    }

    if (data['delivery_method'] != verification.deliveryMethod) {
      return _write(request, 422, _envelope(['delivery_method_invalid']));
    }

    final code = data['code'];
    if (code is! String || code.isEmpty) {
      return _write(request, 422, _envelope(['code_blank']));
    }

    // Refreshing first is what turns a lapsed deadline into `expired` before the
    // attempt is counted.
    verification.refresh(contract.detail('expired'));
    if (verification.isFinished) {
      final blocked = verification.status == 'verified'
          ? 'already_verified'
          : 'not_ready_to_report';
      return _write(request, 422, _envelope([blocked]));
    }

    verification.attempts++;
    final supplied = code;
    if (supplied == verification.expectedValue) {
      verification.finish('verified');
      return _write(
          request, 200, verification.toJson(contract.detail('expired')));
    }

    if (verification.attempts >= contract.maxReportAttempts) {
      verification.finish(
        'failed',
        code: 'too_many_attempts',
        detail: contract.detail('too_many_attempts'),
      );
      return _write(request, 422, _envelope(['too_many_attempts']));
    }

    log('  attempt ${verification.attempts}/${contract.maxReportAttempts} rejected');
    return _write(request, 422, _envelope(['code_invalid']));
  }

  Future<void> _serveCallback(HttpRequest request, String verdict) async {
    final signature = request.headers.value('X-Signature');
    log('  callback receiver "$verdict" signature=${signature ?? 'none'} '
        'content-type=${request.headers.contentType?.value ?? 'none'}');

    switch (verdict) {
      case 'allow':
        return _write(request, 200, {'allowed': true});
      case 'deny':
        return _write(request, 200, {'allowed': false});
      case 'invalid':
        return _write(request, 500, {'oops': true});
      default:
        return _write(request, 404, {'allowed': false});
    }
  }

  Future<Map<String, dynamic>?> _dataObject(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (root is! Map) return null;
    final data = root['data'];
    return data is Map ? data.cast<String, dynamic>() : null;
  }

  Map<String, dynamic> _envelope(List<String> codes) => {
        'errors': [
          for (final code in codes)
            {'code': code, 'detail': contract.detail(code)},
        ],
      };

  Future<void> _write(
      HttpRequest request, int status, Map<String, dynamic> body) async {
    log('${request.method} ${request.uri.path} -> $status');
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }
}
