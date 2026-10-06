package com.jev.probe.core

import android.content.Context
import android.graphics.Rect

/** One captured chat bubble. side is "me" (right) or "other" (left). */
data class Msg(val side: String, val text: String)

/**
 * A bubble the node tree can locate but not read (Feishu draws its message text
 * itself). [rect] is in screen coordinates; [side] is what the tree could infer
 * around the bubble. The service OCRs each rect to get the words.
 */
data class BubbleRect(val rect: Rect, val side: String)

/**
 * A snapshot of the currently-open conversation in whichever chat app is
 * foreground (see ChatAppAdapter).
 *
 * Adapter contract: `extract` returning null means "not in a chat window".
 * Returning a snapshot whose [messages] is empty means "in a chat window, but
 * the tree holds no text" — that is the OCR fallback's cue, and the one case
 * where [bubbleRects] may be populated.
 *
 * [note] is a caveat about how this snapshot was produced, shown verbatim in
 * the analysis panel (OCR captures cannot tell who said what).
 */
data class ChatSnapshot(
    val title: String?,
    val messages: List<Msg>,
    val bubbleRects: List<BubbleRect> = emptyList(),
    val note: String? = null
) {
    val latestFrom: String? get() = messages.lastOrNull()?.side

    /** A stable signature of the last few messages, to detect real changes. */
    fun signature(): String =
        messages.takeLast(6).joinToString("|") { "${it.side}:${it.text}" }
}

/**
 * Which conversation something belongs to: the chat app's package plus the
 * thread title.
 *
 * Either field may be unknown, and unknown is a legitimate value rather than an
 * error: an OCR capture has no title to read, an app can be showing a transient
 * placeholder title, and there may be no chat window in front of the user at all
 * (see [NONE]). Never infer one field from the other, and never treat "unknown"
 * as "the same as last time" — [displayLabel] exists so the UI can say so out
 * loud instead of guessing.
 */
data class ConversationRef(val pkg: String, val title: String?) {

    /** Enough identity to name the thread to the user and to guard a fill with. */
    val isIdentified: Boolean get() = pkg.isNotBlank() && !title.isNullOrBlank()

    /**
     * Short label for the overlay header, e.g. `QQ · 张三`.
     *
     * Falls back through "we know the app but not the thread" to "we know
     * neither" without ever printing a raw package name *when a name is
     * resolvable*. The app half resolves through [ChatApps.displayName], which
     * ends at the bare package name only when the system has no label either
     * (ADR-0026).
     */
    fun displayLabel(context: Context?): String {
        val app = ChatApps.displayName(pkg, context)
        val thread = title?.takeIf { it.isNotBlank() }
        return when {
            app != null && thread != null -> "$app · $thread"
            thread != null -> thread
            app != null -> "$app · $UNKNOWN_LABEL"
            else -> UNKNOWN_LABEL
        }
    }

    companion object {
        /** No chat window is in front of the user. */
        val NONE = ConversationRef("", null)

        const val UNKNOWN_LABEL = "未知应用"
    }
}

/** Jev's judgment result for one snapshot, plus the ranked candidate replies. */
data class Analysis(
    val trueIntent: Choice?,
    val dangerLevel: Score?,
    val sheNeeds: Choice?,
    val shouldReplyNow: Double?,
    val bestAction: Choice?,
    val tensionResolved: Double?,
    val literalQuestion: Double?,
    val rankedReplies: List<RankedReply>,
    val latencyMs: Long,
    val error: String? = null,
    val strategy: String? = null,
    val strategyWeights: Map<String, Double> = emptyMap(),
    val strategyMethod: String? = null,
    val facts: List<String> = emptyList(),
    val unknowns: List<String> = emptyList()
)

data class Choice(val choice: String, val confidence: Double, val probabilities: Map<String, Double>)
data class Score(val score: Double, val confidence: Double, val maxLevel: Int)
data class RankedReply(val text: String, val prob: Double)
