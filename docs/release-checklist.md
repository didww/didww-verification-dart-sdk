# Release checklist

Manual. Nothing here is automated, and nothing publishes from CI.

1. Re-read `contract/wire_contract.json` against the current API documentation. If it has
   drifted, update it and `vocabulary.dart` in one commit and bump the minor version.
2. `dart analyze`, `dart format --set-exit-if-changed .`, `dart test`, `flutter test`.
3. Run the `native` workflow by hand (`target: both`). Neither platform toolchain runs on a
   push, so this is the only check that the Kotlin tests, the merged-manifest permission
   assertion and both platform builds still pass.
4. Run the `pub score` workflow, or `dart run pana` locally; every scored category at full
   marks **for the client**. The plugin cannot be scored until the client is on pub.dev —
   pana resolves a copy of the package in a temporary directory, where an unpublished
   dependency fails — so it is first scorable one release later.
5. `dart pub publish --dry-run` in each package. A missing `LICENSE` is a hard block, not
   a warning.
6. Confirm both package names are still available on pub.dev. There is no way to reserve
   one, so this is a re-check on the day, never a guarantee.
7. One manual run against the sandbox environment. Nothing in CI reaches a live API, so
   this is the only check that can catch a misreading of the wire contract.
8. Publish the client package first; the plugin depends on it by version constraint and
   cannot resolve until it is up.
9. Tag, and write the changelog by hand.
