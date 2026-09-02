package com.didww.didww_verification_sms

import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.EventChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class SmsRetrieverBridgeTest {

    private val registrar = RecordingRegistrar()
    private val sink = RecordingSink()
    private var arms = 0
    private var armThrows: Throwable? = null
    private var armReportsFailure: Throwable? = null

    private fun bridge() = SmsRetrieverBridge(
        RuntimeEnvironment.getApplication(),
        registrar,
    ) { onFailure ->
        arms++
        armThrows?.let { throw it }
        // How the real one fails: startSmsRetriever returns a Task and reports through
        // it. A seam that can only throw models an API that does not exist, and green
        // tests over that model are what hid an unobserved failure.
        armReportsFailure?.let(onFailure)
    }

    private fun broadcast(vararg extras: Pair<String, Any?>) {
        val bundle = Bundle()
        for ((key, value) in extras) {
            when (value) {
                is Status -> bundle.putParcelable(key, value)
                is String -> bundle.putString(key, value)
            }
        }
        registrar.registered.last().onReceive(
            RuntimeEnvironment.getApplication(),
            Intent(SmsRetriever.SMS_RETRIEVED_ACTION).putExtras(bundle),
        )
    }

    private fun success(body: String) = broadcast(
        SmsRetriever.EXTRA_STATUS to Status(CommonStatusCodes.SUCCESS),
        SmsRetriever.EXTRA_SMS_MESSAGE to body,
    )

    @Test
    fun `arms behind the sender permission and an exported receiver`() {
        bridge().onListen(null, sink)

        assertEquals(1, registrar.registered.size)
        assertEquals(1, arms)
        // Without the permission the receiver is reachable by every app on the device and
        // the extras are forgeable, so a hostile app can inject a code the SDK submits.
        assertEquals(SmsRetriever.SEND_PERMISSION, registrar.permission)
        assertEquals(ContextCompat.RECEIVER_EXPORTED, registrar.flags)
        assertTrue(registrar.filter!!.hasAction(SmsRetriever.SMS_RETRIEVED_ACTION))
    }

    @Test
    fun `forwards the whole message body, leaving extraction to the Dart side`() {
        bridge().onListen(null, sink)

        success("Your code is 123456\nFA+9qCX9VSu")

        assertEquals(listOf("Your code is 123456\nFA+9qCX9VSu"), sink.events)
    }

    @Test
    fun `ignores a broadcast for another action`() {
        bridge().onListen(null, sink)

        registrar.registered.last().onReceive(
            RuntimeEnvironment.getApplication(),
            Intent("com.example.SOMETHING_ELSE"),
        )

        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun `ignores a broadcast carrying no status`() {
        bridge().onListen(null, sink)

        broadcast(SmsRetriever.EXTRA_SMS_MESSAGE to "Your code is 123456")

        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun `re-arms when the Play Services window elapses, and emits nothing`() {
        bridge().onListen(null, sink)

        broadcast(SmsRetriever.EXTRA_STATUS to Status(CommonStatusCodes.TIMEOUT))

        assertEquals(2, arms)
        assertTrue(sink.events.isEmpty())
        assertEquals(1, registrar.registered.size)
    }

    @Test
    fun `unregisters exactly once, however many times it is cancelled`() {
        val bridge = bridge()
        bridge.onListen(null, sink)

        bridge.onCancel(null)
        bridge.onCancel(null)

        assertEquals(registrar.registered, registrar.unregistered)
        assertEquals(1, registrar.unregistered.size)
    }

    @Test
    fun `unregisters when arming throws after the receiver was registered`() {
        armThrows = IllegalStateException("no play services")
        val bridge = bridge()

        bridge.onListen(null, sink)

        // An onCancel-only teardown never runs here — the listen never completed — and the
        // receiver would stay registered for the whole process lifetime.
        assertEquals(1, registrar.unregistered.size)
        assertEquals(SmsRetrieverBridge.ERROR_UNAVAILABLE, sink.errors.single())

        bridge.onCancel(null)
        assertEquals(1, registrar.unregistered.size)
    }

    @Test
    fun `unregisters when arming fails through its Task rather than throwing`() {
        armReportsFailure = IllegalStateException("no play services")
        val bridge = bridge()

        bridge.onListen(null, sink)

        // The reachable case on any device without Play Services. Nothing throws, so
        // without observing the Task the receiver stays registered, Dart is never told,
        // and isAutoCaptureArmed reports true for capture that can never fire.
        assertEquals(1, registrar.unregistered.size)
        assertEquals(SmsRetrieverBridge.ERROR_UNAVAILABLE, sink.errors.single())

        bridge.onCancel(null)
        assertEquals(1, registrar.unregistered.size)
    }

    @Test
    fun `a failed listen leaves no sink to emit through`() {
        armThrows = IllegalStateException("no play services")
        val bridge = bridge()
        bridge.onListen(null, sink)
        sink.errors.clear()

        success("Your code is 123456")

        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun `a second listen replaces the receiver rather than stacking one`() {
        val bridge = bridge()

        bridge.onListen(null, sink)
        bridge.onListen(null, sink)

        assertEquals(2, registrar.registered.size)
        assertEquals(listOf(registrar.registered.first()), registrar.unregistered)

        bridge.onCancel(null)
        assertEquals(registrar.registered, registrar.unregistered)
    }

    @Test
    fun `cancelling before any listen is a no-op`() {
        bridge().onCancel(null)

        assertTrue(registrar.unregistered.isEmpty())
        assertNull(registrar.permission)
    }
}

private class RecordingRegistrar : SmsRetrieverBridge.ReceiverRegistrar {
    val registered = mutableListOf<BroadcastReceiver>()
    val unregistered = mutableListOf<BroadcastReceiver>()
    var permission: String? = null
    var flags: Int? = null
    var filter: IntentFilter? = null

    override fun register(
        receiver: BroadcastReceiver,
        filter: IntentFilter,
        permission: String,
        flags: Int,
    ) {
        registered += receiver
        this.filter = filter
        this.permission = permission
        this.flags = flags
    }

    override fun unregister(receiver: BroadcastReceiver) {
        unregistered += receiver
    }
}

private class RecordingSink : EventChannel.EventSink {
    val events = mutableListOf<Any?>()
    val errors = mutableListOf<String>()
    var ended = false

    override fun success(event: Any?) {
        events += event
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        errors += errorCode
    }

    override fun endOfStream() {
        ended = true
    }
}
