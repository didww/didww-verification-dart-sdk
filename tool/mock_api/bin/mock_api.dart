// A local stand-in for the verification API. dart:io only, no dependencies.
//
//   dart run tool/mock_api/bin/mock_api.dart --help

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../src/contract.dart';
import '../src/hmac_sha256.dart';
import '../src/routes.dart';
import '../src/state.dart';

const String _usage = '''
Usage: dart run tool/mock_api/bin/mock_api.dart [options]

  --host <host>       interface to bind (default 127.0.0.1; use 0.0.0.0 to reach
                      it from the Android emulator at 10.0.2.2)
  --port <port>       port to bind (default 8787; 0 picks a free one)
  --contract <path>   wire snapshot (default contract/wire_contract.json)
  --code <value>      the code every sms and callout verification accepts
  --ttl <seconds>     how long a verification lives (default 300)
  --quiet             do not log requests
  --self-test         check the bundled SHA-256/HMAC against published vectors
  --help

Seeded applications, each usable as `Application <key>` or `Basic <key:secret>`:

  demo-key         / demo-secret          callback allows       -> pending
  deny-key         / deny-secret          callback refuses      -> denied_by_callback
  broken-key       / broken-secret        callback answers 500  -> denied_invalid_callback_response
  no-callback-key  / no-callback-secret   no callback url       -> denied_missing_callback_url
''';

Future<void> main(List<String> arguments) async {
  final options = _parse(arguments);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }
  if (options.containsKey('self-test')) {
    exitCode = _selfTest() ? 0 : 1;
    return;
  }

  final contract = WireContract.load(
    options['contract'] ?? _defaultContractPath(),
  );

  final host = options['host'] ?? '127.0.0.1';
  final server =
      await HttpServer.bind(host, int.parse(options['port'] ?? '8787'));
  final origin = 'http://$host:${server.port}';
  final quiet = options.containsKey('quiet');

  final state = MockState(
    applications: [
      MockApplication(
        key: 'demo-key',
        secret: 'demo-secret',
        callbackUrl: '$origin/_callback/allow',
      ),
      MockApplication(
        key: 'deny-key',
        secret: 'deny-secret',
        callbackUrl: '$origin/_callback/deny',
      ),
      MockApplication(
        key: 'broken-key',
        secret: 'broken-secret',
        callbackUrl: '$origin/_callback/invalid',
      ),
      const MockApplication(
        key: 'no-callback-key',
        secret: 'no-callback-secret',
        callbackUrl: null,
      ),
    ],
    code: options['code'] ?? '123456',
    ttl: Duration(seconds: int.parse(options['ttl'] ?? '300')),
  );

  final api = MockApi(
    contract: contract,
    state: state,
    log: quiet ? (_) {} : stdout.writeln,
  );

  stdout.writeln('mock api on $origin${contract.apiPrefix}');
  // Concurrently, not `await for`: a start awaits an outbound call to the
  // customer's callback, and a serial accept loop deadlocks against its own
  // receiver until that call times out.
  server.listen((request) => unawaited(api.handle(request)));
}

/// `--flag` and `--key value`, in a program that must not take an argument parser.
Map<String, String>? _parse(List<String> arguments) {
  const flags = {'help', 'quiet', 'self-test'};
  const valued = {'host', 'port', 'contract', 'code', 'ttl'};

  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (!argument.startsWith('--')) return null;
    final name = argument.substring(2);

    if (flags.contains(name)) {
      options[name] = '';
    } else if (valued.contains(name)) {
      if (i + 1 >= arguments.length) return null;
      options[name] = arguments[++i];
    } else {
      return null;
    }
  }
  return options;
}

/// `contract/wire_contract.json`, relative to this script rather than to the
/// working directory, so the mock runs from anywhere.
String _defaultContractPath() {
  final bin = File.fromUri(Platform.script).parent;
  return '${bin.parent.parent.parent.path}/contract/wire_contract.json';
}

/// The published SHA-256 and HMAC-SHA256 vectors, checked against the bundled
/// implementation. A hand-written hash that has never been compared to a reference
/// is not a hash.
bool _selfTest() {
  var passed = true;
  void check(String label, String actual, String expected) {
    final ok = actual == expected;
    passed = passed && ok;
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $label');
    if (!ok) {
      stdout.writeln('       expected $expected\n       actual   $actual');
    }
  }

  check(
    'sha256("")',
    hex(sha256(const [])),
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  );
  check(
    'sha256("abc")',
    hex(sha256(utf8.encode('abc'))),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  );
  check(
    'sha256(448-bit)',
    hex(sha256(utf8
        .encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
  );
  check(
    'sha256(1e6 x "a")',
    hex(sha256(List<int>.filled(1000000, 0x61))),
    'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
  );
  check(
    'hmac rfc4231 case 1',
    hex(hmacSha256(List<int>.filled(20, 0x0b), utf8.encode('Hi There'))),
    'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
  );
  check(
    'hmac rfc4231 case 2',
    signHex('Jefe', 'what do ya want for nothing?'),
    '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
  );
  check(
    'hmac rfc4231 case 3 (key longer than the block)',
    hex(hmacSha256(List<int>.filled(131, 0xaa),
        utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'))),
    '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
  );

  return passed;
}
