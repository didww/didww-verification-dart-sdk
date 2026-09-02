# mock_api

A local stand-in for the verification API, for driving the SDK and the example app
without spending anything or waiting for a real message.

```bash
dart run tool/mock_api/bin/mock_api.dart          # http://127.0.0.1:8787
dart run tool/mock_api/bin/mock_api.dart --help
tool/mock_api/drive.sh                            # exercises every route with curl
```

`dart:io` only, no dependencies, no pubspec — it is a script, not a package, which is
why `src/` is not called `lib/`.

## Reaching it from a device

| From | Base URL |
|---|---|
| The host | `http://127.0.0.1:8787` |
| The Android emulator | `http://10.0.2.2:8787`, with `--host 0.0.0.0` |
| The iOS simulator | `http://localhost:8787` |

## Seeded applications

Each works as `Application <key>` or as `Basic <base64(key:secret)>`.

| Key | Secret | A start ends up |
|---|---|---|
| `demo-key` | `demo-secret` | `pending` |
| `deny-key` | `deny-secret` | `denied` / `denied_by_callback` |
| `broken-key` | `broken-secret` | `denied` / `denied_invalid_callback_response` |
| `no-callback-key` | `no-callback-secret` | `denied` / `denied_missing_callback_url` |

The accepted code is `123456` and the accepted caller ID is `+46700000000`; both are
options. Three wrong values end the verification with `too_many_attempts`.

## What it models

Everything comes from `contract/wire_contract.json` — routes, channels, statuses, error
codes and their prose. The mock holds no vocabulary of its own, so it cannot drift from
the client without the parity test going red.

- The five routes, on both `PUT` and `PATCH` for a report.
- The three auth dispatch rules, including the trap: the first colon **anywhere** after
  the `Application ` prefix selects request signing, so `Application key:anything` is a
  different scheme rather than a key with a bad suffix.
- Multi-element error envelopes — one element per failing field.
- Supersede on a second start for the same destination.
- `expired` synthesised on read for an unfinished verification past its deadline.
- An outbound **signed, bodyless GET** to the customer's callback, which decides whether
  the verification may start. The signature covers the URL's path only; the query is
  excluded and a bare origin signs the empty string.

The mock answers its own callbacks at `/_callback/{allow,deny,invalid}`, so a full run
needs no second process. Point an application at your own URL to test a real receiver.

## What it does not model

**It is not a reference implementation, and a green run against it is not evidence about
the real API.** Both halves are written from one reading of the same snapshot, so it
catches the SDK disagreeing with the mock — never the snapshot disagreeing with the API.
One manual run against the sandbox per release is what covers that.

Specifically:

- The callback signature is representative, not byte-compatible. Do not build a callback
  receiver against it.
- The callback is asked on every authentication scheme. The real API's rule for when
  authorization is delegated to a callback is not modelled.
- No rate limits, no delivery, no billing, no persistence — state lives for the life of
  the process.

## The bundled hash

`src/hmac_sha256.dart` is a hand-written SHA-256 and HMAC-SHA256, because the mock takes
no dependency and `dart:convert` ships no hash. It is checked against the published
vectors:

```bash
dart run tool/mock_api/bin/mock_api.dart --self-test
```

It exists to sign a mock callback. Do not use it for anything else.
