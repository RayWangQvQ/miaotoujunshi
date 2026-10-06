package com.miaotoujunshi.capabilities.android

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

internal class AndroidOverlayHost(
    val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit,
    private val forwardCommand: (Any?, MethodChannel.Result) -> Unit,
) {
    companion object {
        private const val COLLAPSED_SIZE_DP = 56
        private const val EXPANDED_WIDTH_DP = 300
        private const val EXPANDED_HEIGHT_DP = 320
        private const val DEFAULT_TOP_DP = 56
        private const val SAFE_EXPANDED_TOP_DP = 48
    }

    var activity: Activity? = null

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val engineGroup = FlutterEngineGroup(context)

    private var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var container: DragContainer? = null
    private var params: WindowManager.LayoutParams? = null
    private var panelProtocol: MethodChannel? = null
    private var latestFrame: Any? = null
    private var latestAppearance: Any? = null
    private var panelReady = false
    private var visible = false
    private var expanded = false
    private var focusable = false

    private var edge = "left"
    private var collapsedY = 0

    /** Whether the panel is currently drawn as nothing for a screenshot. */
    private var hiddenForCapture = false

    fun show(arguments: Map<*, *>) {
        ensurePanel()
        val window = params ?: createParams(arguments).also { params = it }
        place(window, arguments)
        if (visible) {
            windowManager.updateViewLayout(container, window)
            return
        }
        windowManager.addView(container, window)
        visible = true
    }

    fun hide(): Boolean {
        if (!visible) {
            return false
        }
        windowManager.removeView(container)
        visible = false
        return true
    }

    fun restore() {
        if (visible || container == null || params == null) {
            return
        }
        windowManager.addView(container, params)
        visible = true
    }

    /**
     * Take the panel off the screen for one screenshot, without giving up its
     * window.
     *
     * [hide] is the wrong tool here and was the cause of a device bug worth
     * recording. It removes the window, so for as long as the shot takes this
     * process owns no window at all — and a phone that freezes background
     * applications is entitled to freeze it, which suspends the very callback
     * the shot is waiting on. Measured on a Galaxy S21 (Android 15): `hide()`
     * during a manual capture, then Freecess `FZ ... reason: Bg` 264 ms later,
     * and the recogniser's result **16 s** after that instead of immediately.
     * Freecess reports `has floating or onScreen window, skip to freeze` every
     * six seconds whenever the ball is up, so the ball is what protects the
     * process — and the capture was destroying it on purpose.
     *
     * An alpha of zero with `FLAG_NOT_TOUCHABLE` draws nothing and takes no
     * touches while leaving the window registered, so the shot is as clean as it
     * was and the process stays out of the freezer.
     */
    fun hideForCapture() {
        val window = params ?: return
        if (!visible || hiddenForCapture) {
            return
        }
        hiddenForCapture = true
        window.alpha = 0f
        window.flags = window.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        windowManager.updateViewLayout(container, window)
    }

    /** Puts the panel back after [hideForCapture]. Never adds a window. */
    fun restoreAfterCapture() {
        val window = params ?: return
        if (!hiddenForCapture) {
            return
        }
        hiddenForCapture = false
        window.alpha = 1f
        window.flags =
            window.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        if (visible) {
            windowManager.updateViewLayout(container, window)
        }
    }

    fun setFocusable(value: Boolean) {
        focusable = value
        val window = params ?: return
        window.flags = if (value) {
            window.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        } else {
            window.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }
        if (visible) {
            windowManager.updateViewLayout(container, window)
        }
    }

    fun publishFrame(frame: Any?) {
        latestFrame = frame
        if (panelReady) {
            panelProtocol?.invokeMethod("frame", frame)
        }
    }

    /**
     * How the panel paints its fill, cached the same way the frame is.
     *
     * A second down-stream, beside the frame, and it needs the same treatment
     * for the same reason: the panel engine is started by [ensurePanel] and
     * reaches Dart after that, so a value pushed in between would otherwise be
     * lost and the panel would keep the default until something else changed it
     * (ADR-0020).
     */
    fun publishAppearance(appearance: Any?) {
        latestAppearance = appearance
        if (panelReady) {
            panelProtocol?.invokeMethod("appearance", appearance)
        }
    }

    fun destroy() {
        if (visible) {
            windowManager.removeViewImmediate(container)
            visible = false
        }
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        container = null
        panelProtocol?.setMethodCallHandler(null)
        panelProtocol = null
        engine?.destroy()
        engine = null
    }

    private fun ensurePanel() {
        if (engine != null) {
            return
        }
        val panelEngine = engineGroup.createAndRunEngine(
            FlutterEngineGroup.Options(context)
                .setDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
                .setAutomaticallyRegisterPlugins(false),
        )
        engine = panelEngine

        MethodChannel(
            panelEngine.dartExecutor.binaryMessenger,
            MiaotouAndroidPlugin.BOOTSTRAP_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "whichEngine" -> result.success("panel")
                "appResumed" -> {
                    panelEngine.lifecycleChannel.appIsResumed()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        panelProtocol = MethodChannel(
            panelEngine.dartExecutor.binaryMessenger,
            MiaotouAndroidPlugin.PROTOCOL_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "panelReady" -> {
                            panelReady = true
                            latestFrame?.let { channel.invokeMethod("frame", it) }
                            latestAppearance?.let {
                                channel.invokeMethod("appearance", it)
                            }
                            result.success(null)
                        }
                        "command" -> forwardCommand(call.arguments, result)
                        "setExpanded" -> {
                            setExpanded(call.arguments.argumentBoolean("value"))
                            result.success(null)
                        }
                        "startDragging" -> {
                            container?.startDragging()
                            result.success(null)
                        }
                        "setFocusable" -> {
                            setFocusable(call.arguments.argumentBoolean("value"))
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
        }

        val renderSurface = FlutterTextureView(activity ?: context).apply {
            isOpaque = false
        }
        val view = FlutterView(activity ?: context, renderSurface).apply {
            setBackgroundColor(Color.TRANSPARENT)
            attachToFlutterEngine(panelEngine)
        }
        val host = DragContainer(activity ?: context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            addView(
                view,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        flutterView = view
        container = host
    }

    private fun createParams(arguments: Map<*, *>): WindowManager.LayoutParams {
        val width = dp(arguments.number("width", COLLAPSED_SIZE_DP.toDouble()))
        val height = dp(arguments.number("height", COLLAPSED_SIZE_DP.toDouble()))
        expanded = width > dp(COLLAPSED_SIZE_DP) || height > dp(COLLAPSED_SIZE_DP)
        var flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        if (!focusable) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }
        return WindowManager.LayoutParams(
            width,
            height,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            alpha = 1.0f
        }
    }

    /**
     * Puts the window where the caller asked for it.
     *
     * **The caller supplies both coordinates, and this class stores neither.**
     * It used to keep `edge` and `y_dp` in its own `SharedPreferences` and read
     * them back on the next launch, which meant the same setting had a different
     * shape on this port than on the two desktop ones. The application keeps one
     * `PanelPlacement` now and sends it down; `edge` survives here only as
     * runtime state, because [setExpanded] and [clamp] need to know which side
     * the window is pinned to (ADR-0020 decision 4).
     *
     * `free` is the anchor a saved placement arrives with, and it means exactly
     * that: two numbers in logical pixels, neither of them relative to an edge.
     */
    private fun place(window: WindowManager.LayoutParams, arguments: Map<*, *>) {
        val screenWidth = context.resources.displayMetrics.widthPixels
        val screenHeight = context.resources.displayMetrics.heightPixels
        val requestedAnchor = arguments["anchor"] as? String ?: "topLeft"

        if (requestedAnchor == "free") {
            window.x = dp(arguments.number("dx", 0.0))
            edge = if (abs(window.x) <= abs(screenWidth - window.width - window.x)) {
                "left"
            } else {
                "right"
            }
        } else {
            edge = if (requestedAnchor.endsWith("Right")) "right" else "left"
            val inset = dp(arguments.number("dx", 0.0))
            window.x = if (edge == "right") screenWidth - window.width - inset else inset
        }
        window.x = window.x.coerceIn(0, (screenWidth - window.width).coerceAtLeast(0))

        window.y = dp(arguments.number("dy", DEFAULT_TOP_DP.toDouble())).coerceIn(
            0,
            (screenHeight - window.height).coerceAtLeast(0),
        )
        collapsedY = window.y
    }

    private fun setExpanded(value: Boolean) {
        if (expanded == value) {
            return
        }
        val window = params ?: return
        if (value) {
            collapsedY = window.y
        }
        expanded = value
        window.width = dp(if (value) EXPANDED_WIDTH_DP else COLLAPSED_SIZE_DP)
        window.height = if (value) expandedHeightPx() else dp(COLLAPSED_SIZE_DP)
        window.y = if (value) {
            window.y.coerceAtMost(dp(SAFE_EXPANDED_TOP_DP))
        } else {
            collapsedY
        }
        val screenWidth = context.resources.displayMetrics.widthPixels
        window.x = if (edge == "right") screenWidth - window.width else 0
        clamp(window)
        if (visible) {
            windowManager.updateViewLayout(container, window)
        }
    }

    /**
     * The height the expanded panel is drawn at: always [EXPANDED_HEIGHT_DP].
     *
     * The review state no longer grows the window (ADR-0025 amendment). The
     * panel used to ask for a taller window while the review was up, but the
     * growing window was the very thing the user fought: an overlay is not an
     * Activity, so the input method covers it no matter how tall it is made, and
     * a panel that changes height between states is a panel the user cannot aim
     * at. One fixed height for the expanded panel — collapsed ball aside — is
     * the whole story now.
     */
    private fun expandedHeightPx(): Int = dp(EXPANDED_HEIGHT_DP)

    private fun moveBy(dx: Float, dy: Float) {
        val window = params ?: return
        window.x += dx.roundToInt()
        window.y += dy.roundToInt()
        clamp(window)
        if (visible) {
            windowManager.updateViewLayout(container, window)
        }
    }

    /**
     * Snaps the window to the nearest edge and reports where it landed.
     *
     * The report is the whole of the persistence story now: the application
     * writes one `PanelPlacement` from this event and sends it back through
     * [show] on the next launch, so this class needs no store of its own.
     */
    private fun finishDrag() {
        val window = params ?: return
        val screenWidth = context.resources.displayMetrics.widthPixels
        edge = if (abs(window.x) <= abs(screenWidth - window.width - window.x)) {
            "left"
        } else {
            "right"
        }
        window.x = if (edge == "right") screenWidth - window.width else 0
        clamp(window)
        if (visible) {
            windowManager.updateViewLayout(container, window)
        }
        if (!expanded) {
            collapsedY = window.y
        }
        onEvent(
            mapOf(
                "kind" to "dragged",
                "x" to window.x / density,
                "y" to window.y / density,
            ),
        )
    }

    private fun clamp(window: WindowManager.LayoutParams) {
        val metrics = context.resources.displayMetrics
        window.x = window.x.coerceIn(0, (metrics.widthPixels - window.width).coerceAtLeast(0))
        val maximumY = if (expanded) {
            dp(SAFE_EXPANDED_TOP_DP)
        } else {
            (metrics.heightPixels - window.height).coerceAtLeast(0)
        }
        window.y = window.y.coerceIn(0, maximumY)
    }

    private val density: Float
        get() = context.resources.displayMetrics.density

    private fun dp(value: Int): Int = dp(value.toDouble())

    private fun dp(value: Double): Int = (value * density).roundToInt()

    private inner class DragContainer(context: Context) : FrameLayout(context) {
        private var dragging = false
        private var lastRawX = 0f
        private var lastRawY = 0f

        fun startDragging() {
            dragging = true
        }

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            val dx = event.rawX - lastRawX
            val dy = event.rawY - lastRawY
            lastRawX = event.rawX
            lastRawY = event.rawY

            if (dragging) {
                when (event.actionMasked) {
                    MotionEvent.ACTION_MOVE -> moveBy(dx, dy)
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        dragging = false
                        finishDrag()
                    }
                }
                if (event.actionMasked != MotionEvent.ACTION_DOWN) {
                    return true
                }
            }
            return super.dispatchTouchEvent(event)
        }
    }
}

private fun Any?.argumentBoolean(key: String): Boolean =
    (this as? Map<*, *>)?.get(key) as? Boolean ?: false

private fun Map<*, *>.number(key: String, fallback: Double): Double =
    (this[key] as? Number)?.toDouble() ?: fallback
