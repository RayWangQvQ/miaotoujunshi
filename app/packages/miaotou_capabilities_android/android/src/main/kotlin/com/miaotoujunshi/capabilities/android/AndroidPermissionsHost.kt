package com.miaotoujunshi.capabilities.android

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android side of the `Permissions` contract (ADR-0021).
 *
 * Two operations and no third: read the state, open the system page. There is
 * deliberately no "request and report back", because an Android system page
 * reports nothing — the user may grant, grant and return, or leaf through and
 * return unchanged, and this side learns none of it.
 *
 * **The component name stays in here.** Dart receives `off` / `inactive` /
 * `ready` and never learns a package or a class name; the comparison against
 * `ENABLED_ACCESSIBILITY_SERVICES` is this file's business, and it is the one
 * place that knows what this build's service is called.
 *
 * It lives beside the plugin rather than in `onControlCall` because the control
 * channel answers "read the chat", and this answers "is the app allowed to".
 * Those are two different questions and the second one has to be askable when
 * the first cannot be: it is the question the user has when the first fails.
 */
internal class AndroidPermissionsHost(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "read" -> result.success(
                    mapOf(
                        "accessibility" to accessibility(),
                        // No middle state exists here: the system either lets
                        // this application draw over others or it does not, and
                        // a port that answered `inactive` would be inventing it.
                        "overlay" to if (Settings.canDrawOverlays(context)) READY else OFF,
                    ),
                )

                "open" -> open(call.argument<String>("kind"), result)
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "android_permissions_${call.method}_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    /**
     * Granted in the system, and actually in effect, told apart.
     *
     * The switch and the binding are two different facts and this device is the
     * evidence: it has carried several retired builds whose accessibility
     * services are still switched on, which looks exactly like a configured
     * device while the build under test has nothing. Reporting 「勾了但没起来」 as
     * `off` is what made ADR-0018's first device run unreadable — the user had
     * just ticked the box and the panel said nothing was on.
     */
    private fun accessibility(): String {
        if (!declaredEnabled()) {
            return OFF
        }
        return if (RetainedAndroidBridge.service() != null) READY else INACTIVE
    }

    /**
     * Whether the user moved the switch, whatever the service is doing now.
     *
     * Compared against the whole flattened component rather than by
     * `contains`, which the retired port used and which would also match a
     * different application whose service class happens to start with the same
     * characters.
     */
    private fun declaredEnabled(): Boolean {
        val declared = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val ours = ComponentName(context, RetainedCaptureService::class.java)
        val full = ours.flattenToString()
        val short = ours.flattenToShortString()
        return declared.split(':').any { entry ->
            entry.equals(full, ignoreCase = true) || entry.equals(short, ignoreCase = true)
        }
    }

    /**
     * Opens the system page for one permission.
     *
     * `FLAG_ACTIVITY_NEW_TASK` because this is the application context rather
     * than an Activity: the settings surface has to be reachable even when no
     * Activity is attached, which is exactly the moment a user wants it. The
     * overlay page is asked for by package, so it lands on this application's
     * own switch instead of a list.
     */
    private fun open(kind: String?, result: MethodChannel.Result) {
        val intent = when (kind) {
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "overlay" -> Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            )
            else -> {
                result.error(
                    "unknown_permission_kind",
                    "Unknown permission kind $kind.",
                    null,
                )
                return
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        result.success(null)
    }

    private companion object {
        const val OFF = "off"
        const val INACTIVE = "inactive"
        const val READY = "ready"
    }
}
