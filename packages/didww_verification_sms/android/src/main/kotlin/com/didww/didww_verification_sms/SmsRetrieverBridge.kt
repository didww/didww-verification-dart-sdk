package com.didww.didww_verification_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.EventChannel

/**
 * Arms the SMS Retriever while Dart is listening and forwards the raw message bodies the
 * platform hands over. The code is extracted on the Dart side, from the template the API
 * returned with the verification.
 */
internal class SmsRetrieverBridge(
    context: Context,
    private val registrar: ReceiverRegistrar = SystemReceiverRegistrar(context),
    private val arm: (onFailure: (Throwable) -> Unit) -> Unit = { onFailure ->
        // startSmsRetriever returns a Task and fails ASYNCHRONOUSLY — on any device
        // without Play Services it completes with API_NOT_AVAILABLE and throws nothing.
        // Discarding the Task is why a failure used to reach neither Dart nor a log,
        // leaving isAutoCaptureArmed reporting true for capture that can never fire.
        SmsRetriever.getClient(context).startSmsRetriever()
            .addOnFailureListener(onFailure)
    },
) : EventChannel.StreamHandler {

    /**
     * The registration seam.
     *
     * Both a permission and flags are required here, and the only `ContextCompat` overload
     * taking both is the 6-argument one — the 4-argument form has no permission parameter at
     * all. So the compiler keeps the wrong overload out, not a convention.
     */
    internal interface ReceiverRegistrar {
        fun register(
            receiver: BroadcastReceiver,
            filter: IntentFilter,
            permission: String,
            flags: Int,
        )

        fun unregister(receiver: BroadcastReceiver)
    }

    private var sink: EventChannel.EventSink? = null

    /** Non-null exactly while a receiver is registered; nulled by the one call that runs it. */
    private var teardown: (() -> Unit)? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        tearDown()
        sink = events

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                handle(intent.extras)
            }
        }

        try {
            registrar.register(
                receiver,
                IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
                // Not optional. A runtime-exported receiver is reachable by every app on the
                // device and the Retriever's extras are trivially forgeable, so without this
                // guard a hostile app can inject a code the SDK then submits.
                SmsRetriever.SEND_PERMISSION,
                ContextCompat.RECEIVER_EXPORTED,
            )
            teardown = { registrar.unregister(receiver) }
            arm { t -> fail(events, t) }
        } catch (t: Throwable) {
            // If registration succeeded and arming then threw, an onCancel-only teardown never
            // runs and the receiver leaks for the whole process lifetime.
            fail(events, t)
        }
    }

    /**
     * The one way arming fails, whether it threw or the Task reported it.
     *
     * Hoisted so the synchronous and asynchronous paths cannot drift: both have to tear the
     * receiver down and tell Dart, or capture stays registered and silently dead.
     */
    private fun fail(events: EventChannel.EventSink, t: Throwable) {
        tearDown()
        sink = null
        events.error(ERROR_UNAVAILABLE, t.message, null)
    }

    override fun onCancel(arguments: Any?) {
        tearDown()
        sink = null
    }

    private fun tearDown() {
        val pending = teardown ?: return
        teardown = null
        runCatching(pending)
    }

    private fun handle(extras: Bundle?) {
        @Suppress("DEPRECATION")
        val status = extras?.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return

        when (status.statusCode) {
            CommonStatusCodes.SUCCESS -> {
                @Suppress("DEPRECATION")
                val body = extras.get(SmsRetriever.EXTRA_SMS_MESSAGE) as? String ?: return
                // onReceive runs on the main looper, which is the platform thread an EventSink
                // must be called from.
                sink?.success(body)
            }

            CommonStatusCodes.TIMEOUT -> {
                // Play Services' window is a hard five minutes, which may be shorter than the
                // server's deadline. Re-arming unconditionally is safe because the session
                // cancels this subscription when the verification ends or its deadline passes.
                //
                // A failure here has to reach Dart too: silently dropping it leaves capture
                // dead for the rest of a verification that is still live.
                val events = sink ?: return
                runCatching { arm { t -> fail(events, t) } }
                    .onFailure { t -> fail(events, t) }
            }
        }
    }

    internal companion object {
        const val ERROR_UNAVAILABLE = "sms_retriever_unavailable"
    }
}

/// Visible to the tests so the real registration is exercised rather than only the
/// seam that stands in for it.
internal class SystemReceiverRegistrar(
    private val context: Context,
) : SmsRetrieverBridge.ReceiverRegistrar {

    override fun register(
        receiver: BroadcastReceiver,
        filter: IntentFilter,
        permission: String,
        flags: Int,
    ) {
        ContextCompat.registerReceiver(context, receiver, filter, permission, null, flags)
    }

    override fun unregister(receiver: BroadcastReceiver) {
        context.unregisterReceiver(receiver)
    }
}
