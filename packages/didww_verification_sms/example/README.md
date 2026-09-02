# didww_verification_sms_example

Drives `didww_verification` and `didww_verification_sms` through a real verification:
enter an origin, an application key and a destination, pick a channel, then submit the
code. A second screen shows `getAppHash()` for the running build.

## Run it against the local mock

Start the mock from the repository root, then run the app from here:

```bash
dart run tool/mock_api/bin/mock_api.dart --host 0.0.0.0   # repository root
flutter run                                               # this directory
```

The origin field is prefilled with whichever loopback address reaches the host from the
current runtime — `10.0.2.2` on the Android emulator, `localhost` elsewhere. The key
field is prefilled with `demo-key`, whose default code is `123456`.

## Run it against the real API

Replace the origin with the sandbox or production base URL and the key with your own
application key. Nothing else changes.

## Tests

```bash
flutter test                                  # widget tests, no runtime needed
flutter test integration_test -d <device>     # the whole flow, mock running
```
