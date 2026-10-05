package com.miaotoujunshi.capabilities.android

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.jev.probe.capture.ChatAppAdapter
import com.jev.probe.capture.FeishuAdapter
import com.jev.probe.capture.QQAdapter
import com.jev.probe.capture.XAdapter
import com.jev.probe.capture.ocr.MlKitOcr
import com.jev.probe.capture.ocr.ScreenCapture
import com.jev.probe.core.ChatSnapshot
import com.jev.probe.core.ConversationRef
import java.io.ByteArrayOutputStream

/**
 * The system-bound Android layer. Accessibility wake-ups, node paths, capture
 * pacing, OCR and verified draft injection stay here; Dart receives values and
 * never polls the service.
 */
class RetainedCaptureService : AccessibilityService() {
    private val main = Handler(Looper.getMainLooper())
    private val adapters: Map<String, ChatAppAdapter> =
        listOf(QQAdapter(), XAdapter(), FeishuAdapter()).associateBy { it.pkg }
    private val ocr = MlKitOcr()
    private val screenCapture by lazy {
        ScreenCapture(
            this,
            hideOverlay = { RetainedAndroidBridge.hideForCapture() },
            restoreOverlay = { RetainedAndroidBridge.restoreAfterCapture() },
        )
    }

    private var currentTreeSnapshot: ChatSnapshot? = null
    private var currentSnapshot: ChatSnapshot? = null
    private var currentConversation = ConversationRef.NONE
    private var boundConversation: ConversationRef? = null
    private var lastConversationEvent: Map<String, Any?>? = null
    private var ocrBusy = false
    private var lastOcrSignature = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        RetainedAndroidBridge.attach(this)
        Thread { MlKitOcr.warmUp() }.start()
        inspectActiveWindow()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        when (event?.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> inspectActiveWindow()
        }
    }

    private fun inspectActiveWindow() {
        val root = rootInActiveWindow
        val packageName = root?.packageName?.toString().orEmpty()
        val snapshot = if (root == null) null else adapters[packageName]?.extract(root, resources)
        val previousConversation = currentConversation
        currentConversation = ConversationRef(packageName, snapshot?.title)
        currentTreeSnapshot = snapshot
        when {
            snapshot == null -> currentSnapshot = null
            snapshot.messages.isNotEmpty() -> currentSnapshot = snapshot
            currentConversation != previousConversation -> currentSnapshot = null
        }
        emitConversation()
        if (snapshot != null) {
            if (snapshot.messages.isEmpty()) {
                captureAndRecognize(snapshot, packageName)
            } else {
                emitSnapshot(snapshot, packageName)
            }
        }
    }

    internal fun readActiveChat(): Map<String, Any?>? =
        currentSnapshot?.toWire(currentConversation.pkg)

    internal fun publishCurrent() {
        emitConversation(force = true)
        currentSnapshot?.takeIf { it.messages.isNotEmpty() }?.let { snapshot ->
            emitSnapshot(snapshot, currentConversation.pkg)
        }
    }

    internal fun bindConversation(arguments: Map<*, *>) {
        boundConversation = arguments.toConversation()
        emitConversation(force = true)
    }

    private fun emitConversation(force: Boolean = false) {
        val shown = boundConversation ?: currentConversation
        val event = mapOf(
            "kind" to "conversation",
            "current" to currentConversation.toWire(),
            "bound" to boundConversation?.toWire(),
            "displayLabel" to shown.displayLabel(),
            "readOnly" to (boundConversation != null && boundConversation != currentConversation),
        )
        if (force || event != lastConversationEvent) {
            lastConversationEvent = event
            RetainedAndroidBridge.emit(event)
        }
    }

    internal fun findTargetWindow(): String? =
        rootInActiveWindow?.windowId?.takeIf { it != -1 }?.toString()

    internal fun capture(targetWindowId: String?, answer: (Map<String, Any?>) -> Unit) {
        val liveWindow = findTargetWindow()
        if (targetWindowId != null && targetWindowId != liveWindow) {
            answer(captureFailure(-3, "目标窗口已经切换"))
            return
        }
        screenCapture.capture { result ->
            when (result) {
                is ScreenCapture.Result.Failed -> {
                    val failure = captureFailure(result.code, result.humanMessage)
                    RetainedAndroidBridge.emit(
                        mapOf(
                            "kind" to "captureError",
                            "code" to result.code,
                            "message" to result.humanMessage,
                        ),
                    )
                    answer(failure)
                }
                is ScreenCapture.Result.Ok -> {
                    val bytes = ByteArrayOutputStream().use { output ->
                        result.bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                        output.toByteArray()
                    }
                    val response = mapOf(
                        "ok" to true,
                        "pixels" to bytes,
                        "width" to result.bitmap.width,
                        "height" to result.bitmap.height,
                        "scaleX" to result.scaleX.toDouble(),
                        "scaleY" to result.scaleY.toDouble(),
                        "originX" to result.originX.toDouble(),
                        "originY" to result.originY.toDouble(),
                    )
                    result.bitmap.recycle()
                    answer(response)
                }
            }
        }
    }

    internal fun recognize(
        arguments: Map<*, *>,
        answer: (List<Map<String, Any?>>) -> Unit,
        fail: (String) -> Unit,
    ) {
        val bytes = arguments["pixels"] as? ByteArray
        val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (bitmap == null) {
            fail("Capture pixels could not be decoded as an image.")
            return
        }
        val scaleX = arguments.number("scaleX", 1.0).toFloat()
        val scaleY = arguments.number("scaleY", 1.0).toFloat()
        val originX = arguments.number("originX", 0.0).toInt()
        val originY = arguments.number("originY", 0.0).toInt()
        ocr.scaleX = scaleX
        ocr.scaleY = scaleY
        ocr.originX = originX
        ocr.originY = originY
        ocr.recognize(bitmap, null) { lines ->
            bitmap.recycle()
            answer(lines.map { line ->
                mapOf(
                    "text" to line.text,
                    "bounds" to mapOf(
                        "left" to ((line.bounds.left - originX) * scaleX).toDouble(),
                        "top" to ((line.bounds.top - originY) * scaleY).toDouble(),
                        "right" to ((line.bounds.right - originX) * scaleX).toDouble(),
                        "bottom" to ((line.bounds.bottom - originY) * scaleY).toDouble(),
                    ),
                    // ML Kit's Android text API does not expose per-line confidence.
                    "confidence" to 1.0,
                )
            })
        }
    }

    private fun captureAndRecognize(treeSnapshot: ChatSnapshot, packageName: String) {
        val signature = treeSnapshot.ocrSignature(packageName)
        if (ocrBusy || signature == lastOcrSignature) {
            return
        }
        ocrBusy = true
        lastOcrSignature = signature
        screenCapture.capture { result ->
            when (result) {
                is ScreenCapture.Result.Failed -> {
                    ocrBusy = false
                    lastOcrSignature = ""
                    RetainedAndroidBridge.emit(
                        mapOf(
                            "kind" to "captureError",
                            "code" to result.code,
                            "message" to result.humanMessage,
                        ),
                    )
                }
                is ScreenCapture.Result.Ok -> {
                    if (!isOcrRequestCurrent(treeSnapshot, packageName, signature)) {
                        result.bitmap.recycle()
                        ocrBusy = false
                        inspectActiveWindow()
                        return@capture
                    }
                    ocr.scaleX = result.scaleX
                    ocr.scaleY = result.scaleY
                    ocr.originX = result.originX
                    ocr.originY = result.originY
                    if (treeSnapshot.bubbleRects.isEmpty()) {
                        recognizeWholeFrame(result.bitmap, treeSnapshot, packageName)
                    } else {
                        recognizeBubbles(result.bitmap, treeSnapshot, packageName)
                    }
                }
            }
        }
    }

    private fun recognizeWholeFrame(
        bitmap: Bitmap,
        treeSnapshot: ChatSnapshot,
        packageName: String,
    ) {
        val region = Rect(
            0,
            (bitmap.height * TOP_CROP).toInt(),
            bitmap.width,
            (bitmap.height * BOTTOM_CROP).toInt(),
        )
        val signature = treeSnapshot.ocrSignature(packageName)
        ocr.recognize(bitmap, region) { lines ->
            bitmap.recycle()
            ocrBusy = false
            if (!isOcrRequestCurrent(treeSnapshot, packageName, signature)) {
                inspectActiveWindow()
                return@recognize
            }
            val snapshot = treeSnapshot.copy(
                messages = groupOcrLines(lines),
                note = "OCR 未分边，把全部消息当作对方所说",
            )
            if (snapshot.messages.isNotEmpty()) {
                currentSnapshot = snapshot
                emitSnapshot(snapshot, packageName)
            }
        }
    }

    private fun recognizeBubbles(
        bitmap: Bitmap,
        treeSnapshot: ChatSnapshot,
        packageName: String,
    ) {
        val bubbles = treeSnapshot.bubbleRects
        val signature = treeSnapshot.ocrSignature(packageName)
        val output = arrayOfNulls<com.jev.probe.core.Msg>(bubbles.size)
        var remaining = bubbles.size
        bubbles.forEachIndexed { index, bubble ->
            val bounds = bubble.rect
            val region = Rect(
                ((bounds.left - ocr.originX) * ocr.scaleX).toInt(),
                ((bounds.top - ocr.originY) * ocr.scaleY).toInt(),
                ((bounds.right - ocr.originX) * ocr.scaleX).toInt(),
                ((bounds.bottom - ocr.originY) * ocr.scaleY).toInt(),
            )
            ocr.recognize(bitmap, region) { lines ->
                val text = lines.joinToString(" ") { it.text.trim() }.trim()
                if (text.isNotEmpty()) {
                    output[index] = com.jev.probe.core.Msg(bubble.side, text)
                }
                remaining--
                if (remaining == 0) {
                    bitmap.recycle()
                    ocrBusy = false
                    if (!isOcrRequestCurrent(treeSnapshot, packageName, signature)) {
                        inspectActiveWindow()
                        return@recognize
                    }
                    val snapshot = treeSnapshot.copy(messages = output.filterNotNull())
                    if (snapshot.messages.isNotEmpty()) {
                        currentSnapshot = snapshot
                        emitSnapshot(snapshot, packageName)
                    }
                }
            }
        }
    }

    private fun isOcrRequestCurrent(
        treeSnapshot: ChatSnapshot,
        packageName: String,
        signature: String,
    ): Boolean =
        currentConversation == ConversationRef(packageName, treeSnapshot.title) &&
            currentTreeSnapshot?.ocrSignature(packageName) == signature

    private fun groupOcrLines(
        lines: List<com.jev.probe.capture.ocr.OcrLine>,
    ): List<com.jev.probe.core.Msg> {
        val usable = lines
            .filter { it.text.isNotBlank() && !PURE_TIME.matches(it.text.trim()) }
            .sortedBy { it.bounds.top }
        val messages = ArrayList<com.jev.probe.core.Msg>()
        val text = StringBuilder()
        var previous: com.jev.probe.capture.ocr.OcrLine? = null
        for (line in usable) {
            previous?.let { prior ->
                val gap = line.bounds.top - prior.bounds.bottom
                if (gap > maxOf(prior.bounds.height(), 1) * 1.2f && text.isNotEmpty()) {
                    messages.add(com.jev.probe.core.Msg("other", text.toString()))
                    text.setLength(0)
                }
            }
            if (text.isNotEmpty()) {
                text.append(' ')
            }
            text.append(line.text.trim())
            previous = line
        }
        if (text.isNotEmpty()) {
            messages.add(com.jev.probe.core.Msg("other", text.toString()))
        }
        return messages
    }

    private fun emitSnapshot(snapshot: ChatSnapshot, packageName: String) {
        RetainedAndroidBridge.emit(
            mapOf(
                "kind" to "snapshot",
                "snapshot" to snapshot.toWire(packageName),
            ),
        )
    }

    internal fun inject(arguments: Map<*, *>, answer: (Map<String, Any?>) -> Unit) {
        val text = arguments["text"] as? String
        val targetWindowId = arguments["targetWindowId"] as? String
        val root = rootInActiveWindow
        if (text == null || targetWindowId == null || root?.windowId?.toString() != targetWindowId) {
            answer(unverified("目标窗口已经切换"))
            return
        }
        if (boundConversation == null || boundConversation != currentConversation) {
            answer(unverified("当前会话与已绑定会话不一致"))
            return
        }
        val edit = findEditable(root)
        val before = edit?.text?.toString()
        if (edit == null || before == null || before.isNotEmpty()) {
            answer(unverified("输入框不可用或已有草稿"))
            return
        }
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val wrote = edit.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        main.postDelayed({
            val observed = rootInActiveWindow?.let(::findEditable)?.text?.toString()
            answer(
                if (wrote && observed == text) {
                    mapOf(
                        "verifiedLanding" to true,
                        "observedText" to observed,
                        "reason" to null,
                    )
                } else {
                    unverified("写入后无法从输入框读回")
                },
            )
        }, INJECT_READ_BACK_MS)
    }

    private fun findEditable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.addLast(root)
        var visited = 0
        var best: AccessibilityNodeInfo? = null
        var bestBottom = -1
        val bounds = Rect()
        val minY = resources.displayMetrics.heightPixels * 0.35f
        while (stack.isNotEmpty() && visited < MAX_NODES) {
            visited++
            val node = stack.removeLast()
            if (node.isEditable && node.isVisibleToUser) {
                node.getBoundsInScreen(bounds)
                if (
                    bounds.width() >= 80 &&
                    bounds.height() >= 24 &&
                    bounds.centerY() >= minY &&
                    bounds.bottom > bestBottom
                ) {
                    best = node
                    bestBottom = bounds.bottom
                }
            }
            for (index in node.childCount - 1 downTo 0) {
                node.getChild(index)?.let(stack::addLast)
            }
        }
        return best
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        RetainedAndroidBridge.detach(this)
        super.onDestroy()
    }

    private companion object {
        const val INJECT_READ_BACK_MS = 150L
        const val MAX_NODES = 5000
        const val TOP_CROP = 0.12f
        const val BOTTOM_CROP = 0.84f

        /**
         * A line that is nothing but a time stamp, dropped before grouping.
         *
         * Anchored, and deliberately identical to the Dart expression that the
         * manual path uses (`manual_recognition.dart`): an unanchored version
         * also swallowed lines that merely contained a time ("会议改到 8:11"),
         * and the two whole-frame paths must read one screen the same way.
         */
        val PURE_TIME = Regex(
            """^\s*(上午|下午|AM|PM|am|pm)?\s*\d{1,2}[:：]\d{2}\s*(上午|下午|AM|PM|am|pm)?\s*$"""
        )
    }
}

internal object RetainedAndroidBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var service: RetainedCaptureService? = null
    private var eventSink: ((Any?) -> Unit)? = null
    private var hideOverlay: (() -> Unit)? = null
    private var restoreOverlay: (() -> Unit)? = null

    fun attach(service: RetainedCaptureService) {
        this.service = service
    }

    fun detach(service: RetainedCaptureService) {
        if (this.service === service) {
            this.service = null
        }
    }

    fun service(): RetainedCaptureService? = service

    fun listen(sink: ((Any?) -> Unit)?) {
        eventSink = sink
        if (sink != null) {
            service?.publishCurrent()
        }
    }

    fun overlay(hide: (() -> Unit)?, restore: (() -> Unit)?) {
        hideOverlay = hide
        restoreOverlay = restore
    }

    fun emit(event: Any?) {
        main.post { eventSink?.invoke(event) }
    }

    fun hideForCapture() {
        main.post { hideOverlay?.invoke() }
    }

    fun restoreAfterCapture() {
        main.post { restoreOverlay?.invoke() }
    }
}

private fun ChatSnapshot.toWire(packageName: String): Map<String, Any?> = mapOf(
    "conversation" to ConversationRef(packageName, title).toWire(),
    "lines" to messages.map { message ->
        mapOf(
            "speaker" to message.side,
            "text" to message.text,
            "bounds" to null,
        )
    },
    "unreadBubbles" to bubbleRects.map { bubble ->
        mapOf(
            "speaker" to bubble.side,
            "bounds" to bubble.rect.toWire(),
        )
    },
    "capturedAtMs" to System.currentTimeMillis(),
    "note" to note,
)

private fun ChatSnapshot.ocrSignature(packageName: String): String {
    if (bubbleRects.isEmpty()) {
        return "$packageName|${title.orEmpty()}"
    }
    return title.orEmpty() + "|" + bubbleRects.joinToString(";") { bubble ->
        val bounds = bubble.rect
        "${bounds.left},${bounds.top},${bounds.right},${bounds.bottom},${bubble.side}"
    }
}

private fun ConversationRef.toWire(): Map<String, Any?> = mapOf(
    "packageName" to pkg,
    "title" to title,
)

private fun Rect.toWire(): Map<String, Double> = mapOf(
    "left" to left.toDouble(),
    "top" to top.toDouble(),
    "right" to right.toDouble(),
    "bottom" to bottom.toDouble(),
)

private fun Map<*, *>.toConversation(): ConversationRef = ConversationRef(
    this["packageName"] as? String ?: "",
    this["title"] as? String,
)

private fun Map<*, *>.number(key: String, fallback: Double): Double =
    (this[key] as? Number)?.toDouble() ?: fallback

private fun captureFailure(code: Int, message: String): Map<String, Any?> = mapOf(
    "ok" to false,
    "code" to code,
    "message" to message,
)

private fun unverified(reason: String): Map<String, Any?> = mapOf(
    "verifiedLanding" to false,
    "observedText" to "",
    "reason" to reason,
)
