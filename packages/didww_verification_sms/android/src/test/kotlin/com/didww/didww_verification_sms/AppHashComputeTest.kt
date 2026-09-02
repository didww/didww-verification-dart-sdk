package com.didww.didww_verification_sms

import android.content.pm.Signature
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.security.MessageDigest

/// The half of AppHash that talks to the PackageManager.
///
/// `AppHashTest` pins the algorithm against a reference constant. This pins the
/// wiring around it: which certificate is read, and in what form it is handed to
/// the algorithm. Neither test catches the other's failure.
@RunWith(RobolectricTestRunner::class)
class AppHashComputeTest {

    private val context get() = RuntimeEnvironment.getApplication()

    private companion object {
        // Written as hex because that is the form the algorithm consumes:
        // Signature.toCharsString() is the lowercase hex of these bytes.
        val CERTIFICATE = hex("30820253308201bca00302010202")
        val OTHER_CERTIFICATE = hex("30820253308201bcff0302010202")

        fun hex(value: String) = ByteArray(value.length / 2) {
            value.substring(it * 2, it * 2 + 2).toInt(16).toByte()
        }
    }

    @Suppress("DEPRECATION")
    private fun install(vararg signatures: Signature) {
        shadowOf(context.packageManager)
            .getInternalMutablePackageInfo(context.packageName)
            .signatures = if (signatures.isEmpty()) null else arrayOf(*signatures)
    }

    @Test
    fun `hashes the package with the certificate installed on the device`() {
        val signature = Signature(CERTIFICATE)
        install(signature)

        assertEquals(
            AppHash.hash(context.packageName, signature.toCharsString()),
            AppHash.compute(context),
        )
    }

    @Test
    fun `hashes the certificate's hex form, not a digest of its bytes`() {
        val signature = Signature(CERTIFICATE)
        install(signature)

        // The wrong port that produces a plausible 11-character hash which never
        // matches, with silent non-firing as its only symptom.
        val digested = MessageDigest.getInstance("SHA-256")
            .digest(CERTIFICATE)
            .joinToString("") { "%02x".format(it) }

        assertNotEquals(AppHash.hash(context.packageName, digested), AppHash.compute(context))
    }

    @Test
    fun `is well formed, so the value is one the API will accept`() {
        install(Signature(CERTIFICATE))

        val hash = AppHash.compute(context)!!
        assert(AppHash.wellFormed(hash)) { hash }
    }

    @Test
    fun `is null when the package has no readable certificate`() {
        install()

        assertNull(AppHash.compute(context))
    }

    @Test
    fun `a re-signed package does not keep the old hash`() {
        install(Signature(CERTIFICATE))
        val before = AppHash.compute(context)

        install(Signature(OTHER_CERTIFICATE))

        assertNotEquals(before, AppHash.compute(context))
    }
}
