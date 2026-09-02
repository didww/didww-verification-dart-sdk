package com.didww.didww_verification_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/// The registration that actually reaches the framework.
///
/// `SmsRetrieverBridgeTest` drives a recording seam, which proves what the bridge
/// asks for and not what the system was told. This asserts the arguments on the
/// far side of `ContextCompat.registerReceiver` — the only place the difference
/// between its 4-argument and 6-argument overloads is observable.
@RunWith(RobolectricTestRunner::class)
class SystemReceiverRegistrarTest {

    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = Unit
    }

    private fun register() = SystemReceiverRegistrar(context).also {
        it.register(
            receiver,
            IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
            SmsRetriever.SEND_PERMISSION,
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    private fun registration() = shadowOf(RuntimeEnvironment.getApplication())
        .registeredReceivers
        .single { it.broadcastReceiver === receiver }

    @Test
    fun `the framework is told the sender permission`() {
        register()

        // The 4-argument overload compiles cleanly and arrives here with null.
        assertEquals(SmsRetriever.SEND_PERMISSION, registration().broadcastPermission)
    }

    @Test
    fun `the framework is told the receiver is exported`() {
        register()

        assertEquals(ContextCompat.RECEIVER_EXPORTED, registration().flags)
    }

    @Test
    fun `the filter carries the action the Retriever broadcasts`() {
        register()

        assertTrue(
            registration().intentFilter.hasAction(SmsRetriever.SMS_RETRIEVED_ACTION),
        )
    }

    @Test
    fun `unregistering removes it from the framework`() {
        val registrar = register()

        registrar.unregister(receiver)

        assertTrue(
            shadowOf(RuntimeEnvironment.getApplication())
                .registeredReceivers
                .none { it.broadcastReceiver === receiver },
        )
    }
}
