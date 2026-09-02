# Contributing

## Reporting an issue

Open it on [GitHub](https://github.com/didww/didww-verification-dart-sdk/issues), with the
package, the version and the channel involved. A failing test against this repository is the
most useful form. For a suspected vulnerability use private reporting instead — see
[`SECURITY.md`](SECURITY.md).

## What you need

- **Flutter 3.27 or newer** — the declared floor. CI builds the floor as well
  as the newest stable, so it is a tested claim.
- **A JDK 17** — the Gradle and Kotlin daemons run on it, whatever JVM
  `flutter doctor` reports for itself. The two are different.
- **The Android SDK** — only for the plugin's Kotlin tests, the manifest guard
  and the example's APK builds.

The Gradle wrapper is committed, so `./gradlew` works on a fresh clone; do not
delete it.

## Which platform can do what

Everything except iOS works on **Linux, macOS and Windows**: the client, the
plugin, the Kotlin tests, the guards, the mock API, and the integration tests on
an Android emulator. The plugin itself is Android-only, so that is the whole of
the delivery surface.

iOS needs macOS and Xcode, and covers exactly one claim — that an Android-only
plugin does not break an iOS build. Nothing you can write in this repository is
verified only there, so a Linux checkout is not a second-class one.

## Layout

A pub workspace. The root `pubspec.yaml` lists the members; each member declares
`resolution: workspace`. There is **one** `pubspec.lock`, at the root, and it is
committed. Run `flutter pub get` from the root, not from a package.

## Build and test

```bash
flutter pub get                                    # root
dart test                                          # packages/didww_verification
flutter test                                       # packages/didww_verification_sms
cd packages/didww_verification_sms/example/android
./gradlew :didww_verification_sms:testDebugUnitTest # plugin Kotlin unit tests
```

The plugin has no Gradle wrapper of its own; its unit tests run through the example
app's wrapper, which is why that one is committed.

## Adding a field to a response

**Add it optional and nullable, never `required`** — even when the wire guarantees it. Both
`Verification` and `VerificationAwaitingInput` are constructed by hand in consumer tests, because
the client and session are `final` and cannot be mocked, so a new `required` parameter breaks every
one of those call sites. The wire's guarantee is not the SDK's compatibility promise.



`SmsInfo`, `CalloutInfo` and `VerificationAwaitingInput` are rebuilt field by field by
the wire decoders, by `awaitingInputFor` and by `withError`. A field added to one of them
and forgotten in its copier compiles, passes every test, and is null at runtime forever —
so `tool/check_field_copies.dart` reads the source and fails when a field is not named by
the function that rebuilds it. Run it after touching any of those classes:

```bash
dart run tool/check_field_copies.dart
```

Deliberate omissions go in that file's `except` list with the reason. An entry that stops
being true is reported too, so the list cannot outlive it.

## The client package takes no dependency

`packages/didww_verification/pubspec.yaml` has no `dependencies:` key, and must not gain
one. It is a published guarantee, it is checked in CI, and it is the reason the package
runs on the plain Dart VM. `dev_dependencies` carry a test runner and a lint set; nothing
else belongs there either.

## Comments

Minimum comments; the code should describe itself. Names, types and small functions carry
the meaning.

A comment earns its place only when it records something the code cannot show:

- a wire invariant — a request with no body sends no `Content-Type`; the app hash is
  omitted when absent, so its presence reflects what was stored rather than what was asked
  for;
- a silent failure mode — the certificate rule behind the app hash; the four-argument
  `registerReceiver` overload that compiles cleanly and drops the permission;
- why an obvious alternative is wrong — never retry a report; `(\d+)` rather than `(.+)`.

When one survives, it is a sentence or two, never a rationale essay. Public members get a
one-line doc comment; internals usually get none.

## Nothing internal in this repository

This repository is public. It must not contain internal identifiers, internal reason
vocabulary, internal class, table or service names, or any other vendor's name. That
applies to commit messages and documentation as much as to source.

`tool/check_no_internal_refs.dart` enforces it. Its vocabulary is itself internal — a public
list of the terms to keep out publishes exactly what it protects — so the script reads the
list from a file that is not in this repository, and without it checks private hostnames
only. It says so on every run.

## Commits and releases

Releases are manual. Nothing is published from CI.
