package com.didww.didww_verification_sms

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class AppHashTest {

    private companion object {
        private const val PACKAGE = "com.didww.android.sdk.verification.sample"
        private const val SIGNATURE_HEX =
            "30820253308201bca003020102020450e3f1c9300d06092a864886f70d01010b0500"

        /**
         * **A committed constant, derived once, outside this codebase.**
         *
         * Produced by running Google's documented `AppSignatureHelper` algorithm against the
         * fixture above in an independent implementation:
         * `base64(SHA-256("<package> <signatureHex>")[0..8])[0..10]`.
         *
         * It is written down rather than recomputed here on purpose. A test that derives the
         * expected value with the same code it is testing asserts only that the code is
         * deterministic — it would pass just as happily on a wrong algorithm, and a wrong app
         * hash has no symptom at all: the Retriever broadcast simply never arrives.
         *
         * A second, independently written port asserts this same fixture and constant, so the
         * two ports are pinned to one externally derived value.
         */
        private const val REFERENCE_HASH = "cnXrLKACSkF"

        /**
         * A second fixture, derived the same way, whose hash uses both characters that
         * differ between standard and URL-safe base64.
         *
         * The fixture above happens to encode to letters and digits alone, so it passes
         * under either alphabet. This one does not, which is what makes the encoder's
         * alphabet an assertion rather than a coincidence.
         */
        private const val ALPHABET_PACKAGE = "com.example.app8"
        private const val ALPHABET_HASH = "O/Ov3WXdvQ+"
    }

    @Test
    fun `matches Google's reference implementation for a fixture certificate`() {
        assertEquals(REFERENCE_HASH, AppHash.hash(PACKAGE, SIGNATURE_HEX))
    }

    @Test
    fun `is exactly eleven characters, as the Retriever protocol requires`() {
        assertEquals(11, AppHash.hash(PACKAGE, SIGNATURE_HEX).length)
        assertEquals(11, AppHash.hash("a", "b").length)
    }

    @Test
    fun `changes when the package changes and when the certificate changes`() {
        val base = AppHash.hash(PACKAGE, SIGNATURE_HEX)
        assert(base != AppHash.hash("$PACKAGE.debug", SIGNATURE_HEX)) {
            "a debug-suffixed package must not share the release hash"
        }
        assert(base != AppHash.hash(PACKAGE, SIGNATURE_HEX.dropLast(2) + "ff")) {
            "a re-signed APK must not share the old hash"
        }
    }

    @Test
    fun `accepts what the algorithm produces and rejects what the API would refuse`() {
        // The API validates this key, so a malformed value fails the verification rather than
        // only capture. The check is asserted directly because the algorithm cannot be made to
        // produce a bad value — which is exactly why it is easy to leave unguarded.
        assert(AppHash.wellFormed(AppHash.hash(PACKAGE, SIGNATURE_HEX)))
        assert(AppHash.wellFormed("FA+9qCX9VSu"))
        assert(!AppHash.wellFormed("")) { "empty" }
        assert(!AppHash.wellFormed("cnXrLKACSk")) { "ten characters" }
        assert(!AppHash.wellFormed("cnXrLKACSkFF")) { "twelve characters" }
        assert(!AppHash.wellFormed("cnXrLKACSk=")) { "base64 padding is outside the alphabet" }
        assert(!AppHash.wellFormed("cnXrLKACSk-")) { "url-safe base64 is outside the alphabet" }
    }

    @Test
    fun `encodes with standard base64, not the URL-safe alphabet`() {
        assertEquals(ALPHABET_HASH, AppHash.hash(ALPHABET_PACKAGE, SIGNATURE_HEX))
    }

    @Test
    fun `carries no base64 padding and no line wrapping`() {
        // Documentation, not a live guard: nine bytes encode to exactly twelve base64
        // characters, so padding never occurs, and a trailing newline falls outside the
        // eleven characters taken. Switching the encoder to Base64.DEFAULT leaves this
        // green. What it does guard is the pair of constants — change HASHED_BYTES or
        // BASE64_CHARS and padding can land inside the truncation.
        val hash = AppHash.hash(PACKAGE, SIGNATURE_HEX)
        assert(!hash.contains("=")) { "padding would make the appended hash the wrong length" }
        assert(!hash.contains("\n")) { "a wrapped hash would break the message body" }
    }
}
