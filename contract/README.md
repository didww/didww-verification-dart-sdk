# Wire contract snapshot

`wire_contract.json` is a committed snapshot of the DIDWW Verification API's wire
vocabulary: routes, delivery methods, statuses, error codes, envelope shapes and the
constraints the SDK must respect.

It exists so the vocabulary has **one** source. `vocabulary.dart` is derived from this
file, and a test asserts the two agree — adding an error code to one and not the other
turns CI red rather than shipping a silent mismatch.

## What it is not

It is **not** generated, and it is not authoritative. It is a hand-made reading of the
API, reviewed against the API's own behaviour. Two consequences worth stating plainly:

- **It cannot detect drift.** Nothing here reaches a running API. If the API gains a
  status or renames a slug, this file keeps asserting the old vocabulary and every test
  built on it stays green. The only real detector is a request against the live API.
- **Authentication is only partly covered.** The published OpenAPI description documents
  the HTTP Basic scheme only, so the application-key scheme this SDK uses on device is
  recorded here from observed behaviour rather than from a machine-readable source. No
  automated check can cover that half.

## Refreshing it

Refresh when the API's published documentation or its behaviour changes:

1. Re-read the [API reference](https://doc.didww.com/otp-verification/index.html) and, for
   anything the reference does not pin down, confirm it against the sandbox environment.
2. Update `wire_contract.json` and `vocabulary.dart` **in the same commit** — the parity
   test is what keeps them honest, and splitting the change defeats it.
3. Bump the package minor version: a vocabulary change is a public API change.
4. Record who reviewed the change, and against what, on the tracking issue.

Anyone with access to the service implementation should review a refresh against it. That
review is recorded on the issue, not here — this repository is public.
