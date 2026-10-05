package com.miaotoujunshi.capabilities.android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class MiaotouAndroidPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        const val PANEL_CHANNEL = "miaotoujunshi/android/panel"
        const val EVENT_CHANNEL = "miaotoujunshi/android/panel/events"
        const val BOOTSTRAP_CHANNEL = "miaotoujunshi/android/panel-bootstrap"
        const val PROTOCOL_CHANNEL = "miaotoujunshi/android/panel-protocol"
        const val CONTROL_CHANNEL = "miaotou/control"
        const val INGEST_CHANNEL = "miaotou/ingest"
        const val STORAGE_CHANNEL = "miaotoujunshi/android/storage"
        private const val OVERLAY_PERMISSION_REQUEST = 41021
    }

    private lateinit var panelChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var bootstrapChannel: MethodChannel
    private lateinit var mainProtocol: MethodChannel
    private lateinit var controlChannel: MethodChannel
    private lateinit var ingestChannel: EventChannel
    private lateinit var storageChannel: MethodChannel
    private lateinit var host: AndroidOverlayHost

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingShow: PendingShow? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mainProtocol = MethodChannel(binding.binaryMessenger, PROTOCOL_CHANNEL)
        host = AndroidOverlayHost(
            binding.applicationContext,
            onEvent = { event -> eventSink?.success(event) },
            forwardCommand = { arguments, result ->
                mainProtocol.invokeMethod(
                    "command",
                    arguments,
                    forwardingResult(result, "panel_command_failed"),
                )
            },
        )

        panelChannel = MethodChannel(binding.binaryMessenger, PANEL_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
        bootstrapChannel = MethodChannel(binding.binaryMessenger, BOOTSTRAP_CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "whichEngine" -> result.success("main")
                    else -> result.notImplemented()
                }
            }
        }
        mainProtocol.setMethodCallHandler { call, result ->
            when (call.method) {
                "frame" -> {
                    host.publishFrame(call.arguments)
                    result.success(null)
                }
                // The second down-stream, beside the frame. Relayed and cached
                // exactly like it, because the panel engine reaches Dart after
                // this call and would otherwise miss the value (ADR-0020).
                "appearance" -> {
                    host.publishAppearance(call.arguments)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        controlChannel = MethodChannel(binding.binaryMessenger, CONTROL_CHANNEL).also {
            it.setMethodCallHandler(::onControlCall)
        }
        ingestChannel = EventChannel(binding.binaryMessenger, INGEST_CHANNEL).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    RetainedAndroidBridge.listen(events::success)
                }

                override fun onCancel(arguments: Any?) {
                    RetainedAndroidBridge.listen(null)
                }
            })
        }
        RetainedAndroidBridge.overlay(
            hide = { host.hideForCapture() },
            restore = { host.restoreAfterCapture() },
        )
        storageChannel = MethodChannel(binding.binaryMessenger, STORAGE_CHANNEL).also {
            it.setMethodCallHandler(AndroidStorageHost(binding.applicationContext))
        }
    }

    private fun onControlCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "setOverlayFlag" -> setOverlayFlag(call.arguments.asArguments(), result)
                "hideForCapture" -> {
                    host.hideForCapture()
                    result.success(null)
                }
                "restore" -> {
                    host.restoreAfterCapture()
                    result.success(null)
                }
                else -> withCaptureService(result) { service ->
                    when (call.method) {
                        "readActiveChat" -> result.success(service.readActiveChat())
                        "bindConversation" -> {
                            service.bindConversation(call.arguments.asArguments())
                            result.success(null)
                        }
                        "findTargetWindow" -> result.success(service.findTargetWindow())
                        "capture" -> service.capture(
                            call.arguments.asArguments()["targetWindowId"] as? String,
                            result::success,
                        )
                        "recognize" -> service.recognize(
                            call.arguments.asArguments(),
                            result::success,
                            { message ->
                                result.error("android_ocr_decode_failed", message, null)
                            },
                        )
                        "inject" -> service.inject(
                            call.arguments.asArguments(),
                            result::success,
                        )
                        else -> result.notImplemented()
                    }
                }
            }
        } catch (error: Throwable) {
            result.error(
                "android_control_${call.method}_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun setOverlayFlag(arguments: Map<*, *>, result: MethodChannel.Result) {
        val enabled = arguments.boolean("value")
        when (arguments["flag"] as? String) {
            "visible" -> if (enabled) host.restore() else host.hide()
            "focusable" -> host.setFocusable(enabled)
            else -> {
                result.error(
                    "unknown_overlay_flag",
                    "Unknown overlay flag ${arguments["flag"]}.",
                    null,
                )
                return
            }
        }
        result.success(null)
    }

    private fun withCaptureService(
        result: MethodChannel.Result,
        action: (RetainedCaptureService) -> Unit,
    ) {
        val service = RetainedAndroidBridge.service()
        if (service == null) {
            result.error(
                "accessibility_service_unavailable",
                "Enable the Miaotou accessibility service before using Android capture.",
                null,
            )
            return
        }
        action(service)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "show" -> show(call.arguments.asArguments(), result)
                "hide" -> result.success(host.hide())
                "restore" -> {
                    host.restore()
                    result.success(null)
                }
                "focusable" -> {
                    host.setFocusable(call.arguments.asArguments().boolean("value"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "android_panel_${call.method}_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun show(arguments: Map<*, *>, result: MethodChannel.Result) {
        if (Settings.canDrawOverlays(host.context)) {
            host.show(arguments)
            result.success(null)
            return
        }

        val owner = activity
        if (owner == null) {
            result.error(
                "overlay_permission_unavailable",
                "Display-over-other-apps permission is required, but no Activity can request it.",
                null,
            )
            return
        }
        if (pendingShow != null) {
            result.error(
                "overlay_permission_pending",
                "A display-over-other-apps permission request is already open.",
                null,
            )
            return
        }

        pendingShow = PendingShow(arguments, result)
        owner.startActivityForResult(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${owner.packageName}"),
            ),
            OVERLAY_PERMISSION_REQUEST,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != OVERLAY_PERMISSION_REQUEST) {
            return false
        }
        val pending = pendingShow ?: return true
        pendingShow = null
        if (!Settings.canDrawOverlays(host.context)) {
            pending.result.error(
                "overlay_permission_denied",
                "Display over other apps was not granted, so the floating panel cannot be shown.",
                null,
            )
            return true
        }
        try {
            host.show(pending.arguments)
            pending.result.success(null)
        } catch (error: Throwable) {
            pending.result.error(
                "android_panel_show_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        host.activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        host.activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pendingShow?.result?.error(
            "overlay_host_detached",
            "The Android host stopped before the overlay permission request completed.",
            null,
        )
        pendingShow = null
        panelChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        bootstrapChannel.setMethodCallHandler(null)
        mainProtocol.setMethodCallHandler(null)
        controlChannel.setMethodCallHandler(null)
        ingestChannel.setStreamHandler(null)
        storageChannel.setMethodCallHandler(null)
        RetainedAndroidBridge.listen(null)
        RetainedAndroidBridge.overlay(null, null)
        host.destroy()
    }

    private fun forwardingResult(
        target: MethodChannel.Result,
        errorCode: String,
    ) = object : MethodChannel.Result {
        override fun success(result: Any?) {
            target.success(result)
        }

        override fun error(code: String, message: String?, details: Any?) {
            target.error(code, message, details)
        }

        override fun notImplemented() {
            target.error(errorCode, "The main engine did not handle the panel command.", null)
        }
    }

    private data class PendingShow(
        val arguments: Map<*, *>,
        val result: MethodChannel.Result,
    )
}

private fun Any?.asArguments(): Map<*, *> = this as? Map<*, *> ?: emptyMap<Any, Any>()

private fun Map<*, *>.boolean(key: String): Boolean = this[key] as? Boolean ?: false
