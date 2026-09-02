package com.didww.didww_verification_sms

import android.content.pm.Signature
import com.google.android.gms.auth.api.phone.SmsRetriever
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.nio.ByteBuffer

/// The plugin driven through its real channels.
///
/// The names are pinned against literals because the Dart side pins the same
/// three: renaming a channel in one place only produces a plugin that builds,
/// installs and answers nothing. Everything after that goes through the actual
/// binary messenger, so the registration and the teardown are exercised rather
/// than described.
@RunWith(RobolectricTestRunner::class)
class DidwwVerificationSmsPluginTest {

    private val context get() = RuntimeEnvironment.getApplication()
    private val messenger = RecordingMessenger()
    private val plugin = DidwwVerificationSmsPlugin()

    private fun binding() = FlutterPlugin.FlutterPluginBinding(
        context,
        unused(),
        messenger,
        unused(),
        unused(),
        unused(),
        null,
    )

    private fun attach() = plugin.onAttachedToEngine(binding())

    private fun detach() = plugin.onDetachedFromEngine(binding())

    @Suppress("DEPRECATION")
    private fun installCertificate() {
        shadowOf(context.packageManager)
            .getInternalMutablePackageInfo(context.packageName)
            .signatures = arrayOf(Signature("30820253308201bca003020102".hexToBytes()))
    }

    /// Sends [call] to [channel] and returns the decoded reply, or null when the
    /// plugin answered `notImplemented`.
    private fun invoke(channel: String, call: MethodCall): Any? {
        var reply: ByteBuffer? = null
        var replied = false
        messenger.handlers[channel]!!.onMessage(
            StandardMethodCodec.INSTANCE.encodeMethodCall(call).also { it.position(0) },
        ) { answer ->
            reply = answer
            replied = true
        }
        assertTrue("no reply for ${call.method}", replied)
        return reply?.let {
            it.position(0)
            StandardMethodCodec.INSTANCE.decodeEnvelope(it)
        }
    }

    private fun smsReceivers() = shadowOf(RuntimeEnvironment.getApplication())
        .registeredReceivers
        .filter { it.intentFilter.hasAction(SmsRetriever.SMS_RETRIEVED_ACTION) }

    @Test
    fun `channel names are the ones the Dart side addresses`() {
        assertEquals("didww_verification_sms", DidwwVerificationSmsPlugin.METHOD_CHANNEL)
        assertEquals(
            "didww_verification_sms/messages",
            DidwwVerificationSmsPlugin.MESSAGE_CHANNEL,
        )
        assertEquals("getAppHash", DidwwVerificationSmsPlugin.METHOD_APP_HASH)
    }

    @Test
    fun `attaching registers both channels and detaching releases them`() {
        attach()

        assertNotNull(messenger.handlers[DidwwVerificationSmsPlugin.METHOD_CHANNEL])
        assertNotNull(messenger.handlers[DidwwVerificationSmsPlugin.MESSAGE_CHANNEL])

        detach()

        assertNull(messenger.handlers[DidwwVerificationSmsPlugin.METHOD_CHANNEL])
        assertNull(messenger.handlers[DidwwVerificationSmsPlugin.MESSAGE_CHANNEL])
    }

    @Test
    fun `the method channel answers with this build's app hash`() {
        installCertificate()
        attach()

        val hash = invoke(
            DidwwVerificationSmsPlugin.METHOD_CHANNEL,
            MethodCall(DidwwVerificationSmsPlugin.METHOD_APP_HASH, null),
        )

        assertEquals(AppHash.compute(context), hash)
        assertTrue(AppHash.wellFormed(hash as String))
    }

    @Test
    fun `a build with no certificate answers null rather than failing`() {
        attach()

        assertNull(
            invoke(
                DidwwVerificationSmsPlugin.METHOD_CHANNEL,
                MethodCall(DidwwVerificationSmsPlugin.METHOD_APP_HASH, null),
            ),
        )
    }

    @Test
    fun `an unknown method is not implemented rather than an error`() {
        attach()

        // notImplemented replies with no envelope at all, which is what lets the
        // Dart side distinguish it from a platform error.
        assertNull(
            invoke(DidwwVerificationSmsPlugin.METHOD_CHANNEL, MethodCall("nope", null)),
        )
    }

    @Test
    fun `listening on the event channel registers the guarded receiver`() {
        attach()

        invoke(DidwwVerificationSmsPlugin.MESSAGE_CHANNEL, MethodCall("listen", null))

        val registered = smsReceivers().single()
        assertEquals(SmsRetriever.SEND_PERMISSION, registered.broadcastPermission)
    }

    @Test
    fun `detaching unregisters a receiver the engine left listening`() {
        attach()
        invoke(DidwwVerificationSmsPlugin.MESSAGE_CHANNEL, MethodCall("listen", null))
        assertEquals(1, smsReceivers().size)

        // setStreamHandler(null) does not cancel the handler it replaces, so
        // without the explicit cancel the receiver outlives the engine.
        detach()

        assertTrue(smsReceivers().isEmpty())
    }

    @Test
    fun `cancelling on the event channel unregisters the receiver`() {
        attach()
        invoke(DidwwVerificationSmsPlugin.MESSAGE_CHANNEL, MethodCall("listen", null))

        invoke(DidwwVerificationSmsPlugin.MESSAGE_CHANNEL, MethodCall("cancel", null))

        assertTrue(smsReceivers().isEmpty())
    }
}

/// The binding's constructor declares these non-null, and this plugin reads none
/// of them. Erasure lets a null through without the check a direct cast would get.
@Suppress("UNCHECKED_CAST")
private fun <T> unused(): T = null as T

private fun String.hexToBytes() = ByteArray(length / 2) {
    substring(it * 2, it * 2 + 2).toInt(16).toByte()
}

private class RecordingMessenger : BinaryMessenger {
    val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler?>()

    override fun send(channel: String, message: ByteBuffer?) = Unit

    override fun send(
        channel: String,
        message: ByteBuffer?,
        callback: BinaryMessenger.BinaryReply?,
    ) = Unit

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
    ) {
        if (handler == null) handlers.remove(channel) else handlers[channel] = handler
    }
}
