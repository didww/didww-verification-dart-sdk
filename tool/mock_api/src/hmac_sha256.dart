/// SHA-256 and HMAC-SHA256.
///
/// Hand-written because the mock takes no third-party dependency and `dart:convert`
/// ships no hash. Verified against the RFC 6234 and RFC 4231 vectors by
/// `mock_api.dart --self-test`.
library;

import 'dart:convert';
import 'dart:typed_data';

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const int _mask = 0xffffffff;
const int _blockBytes = 64;

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask;

/// The SHA-256 digest of [message], as 32 bytes.
Uint8List sha256(List<int> message) {
  final h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  final block = _padded(message);
  final w = Uint32List(64);

  for (var offset = 0; offset < block.length; offset += _blockBytes) {
    for (var t = 0; t < 16; t++) {
      final i = offset + t * 4;
      w[t] = (block[i] << 24) |
          (block[i + 1] << 16) |
          (block[i + 2] << 8) |
          block[i + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 = _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
      final s1 = _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask;
    }

    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];

    for (var t = 0; t < 64; t++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & _mask & g);
      final temp1 = (hh + s1 + ch + _k[t] + w[t]) & _mask;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & _mask;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) & _mask;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & _mask;
    }

    h[0] = (h[0] + a) & _mask;
    h[1] = (h[1] + b) & _mask;
    h[2] = (h[2] + c) & _mask;
    h[3] = (h[3] + d) & _mask;
    h[4] = (h[4] + e) & _mask;
    h[5] = (h[5] + f) & _mask;
    h[6] = (h[6] + g) & _mask;
    h[7] = (h[7] + hh) & _mask;
  }

  final digest = Uint8List(32);
  for (var i = 0; i < 8; i++) {
    digest[i * 4] = (h[i] >> 24) & 0xff;
    digest[i * 4 + 1] = (h[i] >> 16) & 0xff;
    digest[i * 4 + 2] = (h[i] >> 8) & 0xff;
    digest[i * 4 + 3] = h[i] & 0xff;
  }
  return digest;
}

Uint8List _padded(List<int> message) {
  final bitLength = message.length * 8;
  final total = ((message.length + 9 + 63) ~/ 64) * 64;
  final out = Uint8List(total)..setRange(0, message.length, message);
  out[message.length] = 0x80;
  for (var i = 0; i < 8; i++) {
    out[total - 1 - i] = (bitLength >> (8 * i)) & 0xff;
  }
  return out;
}

/// The HMAC-SHA256 of [message] under [key], as 32 bytes.
Uint8List hmacSha256(List<int> key, List<int> message) {
  final normalised = Uint8List(_blockBytes);
  final source = key.length > _blockBytes ? sha256(key) : key;
  normalised.setRange(0, source.length, source);

  final inner = Uint8List(_blockBytes + message.length);
  final outer = Uint8List(_blockBytes + 32);
  for (var i = 0; i < _blockBytes; i++) {
    inner[i] = normalised[i] ^ 0x36;
    outer[i] = normalised[i] ^ 0x5c;
  }
  inner.setRange(_blockBytes, inner.length, message);
  outer.setRange(_blockBytes, outer.length, sha256(inner));

  return sha256(outer);
}

/// The hex form of [bytes], lower case.
String hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// The HMAC-SHA256 of [message] under [key], both UTF-8, as lower-case hex.
String signHex(String key, String message) =>
    hex(hmacSha256(utf8.encode(key), utf8.encode(message)));
