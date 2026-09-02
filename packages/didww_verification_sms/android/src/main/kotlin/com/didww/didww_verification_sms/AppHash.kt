package com.didww.didww_verification_sms

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.util.Base64
import android.util.Log
import java.security.MessageDigest

/**
 * Computes the 11-character app hash the SMS Retriever API requires at the end of a
 * message before it will hand that message to this app.
 *
 * Google's `AppSignatureHelper`: `SHA-256(packageName + " " + signature)`, truncated to
 * the first nine bytes, base64 with no padding and no wrapping, then the first eleven
 * characters.
 *
 * `signature` is `Signature.toCharsString()` — the lowercase hex of the certificate's DER
 * bytes, **not** a digest of them. Getting that wrong produces a plausible-looking hash
 * that never matches, and the only symptom is that capture silently never fires.
 */
internal object AppHash {

    private const val HASHED_BYTES = 9
    private const val BASE64_CHARS = 11
    private const val LOG_TAG = "DidwwVerification"

    /** The alphabet and length the API accepts. Base64 without padding yields exactly these. */
    private val FORMAT = Regex("[A-Za-z0-9+/]{$BASE64_CHARS}")

    /** `null` when the signing certificate cannot be read at all. */
    fun compute(context: Context): String? {
        val packageName = context.packageName
        val signature = currentSigner(context, packageName) ?: run {
            Log.w(LOG_TAG, "no signing certificate for $packageName; SMS capture unavailable")
            return null
        }

        val hash = hash(packageName, signature.toCharsString())
        if (!wellFormed(hash)) {
            Log.w(LOG_TAG, "computed app hash is malformed; SMS capture unavailable")
            return null
        }

        // Retriever failure is completely silent: a wrong hash means the broadcast simply
        // never arrives, with no error anywhere. Logging the computed value is the only way
        // a mismatch is diagnosable on a device the implementer does not have.
        Log.d(LOG_TAG, "app hash for $packageName: $hash")
        return hash
    }

    /**
     * The API validates this value and rejects a malformed one, so sending a bad hash fails
     * the whole verification rather than only capture. Omitting it costs capture alone.
     */
    fun wellFormed(hash: String): Boolean = FORMAT.matches(hash)

    /**
     * The computation itself, with no `PackageManager` in the way, so it can be asserted
     * against a reference constant rather than against a second copy of itself.
     *
     * @param signatureHex `Signature.toCharsString()` — lowercase hex of the certificate's
     *   DER bytes.
     */
    fun hash(packageName: String, signatureHex: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$packageName $signatureHex".toByteArray(Charsets.UTF_8))
        return Base64
            .encodeToString(digest.copyOf(HASHED_BYTES), Base64.NO_PADDING or Base64.NO_WRAP)
            .take(BASE64_CHARS)
    }

    /**
     * The certificate the APK is *currently* signed with, which is what Play Services
     * matches against. After a rotation `signingCertificateHistory` holds the original first
     * and the current one last, so its first entry would hash a certificate that no longer
     * signs anything.
     */
    @Suppress("DEPRECATION")
    private fun currentSigner(context: Context, packageName: String): Signature? = runCatching {
        val pm = context.packageManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo
            val current = info?.apkContentsSigners?.firstOrNull()
                ?: info?.signingCertificateHistory?.lastOrNull()
            if (current != null) return@runCatching current
        }

        // `PackageInfo.signingInfo` is documented as nullable and really is null in practice,
        // so the deprecated array is the fallback at every API level, not only below 28.
        pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures?.firstOrNull()
    }.getOrNull()
}
