package com.didww.didww_verification_sms

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Wires the app-hash method channel and the message event channel to their Dart facade. */
class DidwwVerificationSmsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {

    private var methods: MethodChannel? = null
    private var messages: EventChannel? = null
    private var bridge: SmsRetrieverBridge? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        bridge = SmsRetrieverBridge(binding.applicationContext)

        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@DidwwVerificationSmsPlugin)
        }
        messages = EventChannel(binding.binaryMessenger, MESSAGE_CHANNEL).apply {
            setStreamHandler(bridge)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = this.context
        when {
            call.method != METHOD_APP_HASH -> result.notImplemented()
            context == null -> result.success(null)
            else -> result.success(AppHash.compute(context))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        messages?.setStreamHandler(null)
        // setStreamHandler does not cancel the handler it replaces, so without this the
        // receiver stays registered after the engine is gone.
        bridge?.onCancel(null)

        methods = null
        messages = null
        bridge = null
        context = null
    }

    internal companion object {
        const val METHOD_CHANNEL = "didww_verification_sms"
        const val MESSAGE_CHANNEL = "didww_verification_sms/messages"
        const val METHOD_APP_HASH = "getAppHash"
    }
}
