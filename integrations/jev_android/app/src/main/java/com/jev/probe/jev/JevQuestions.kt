package com.jev.probe.jev

import com.jev.probe.core.ChatSnapshot
import com.jev.probe.core.SharedMaterial
import com.jev.probe.core.kb.LogEntry
import org.json.JSONArray
import org.json.JSONObject

/**
 * The fixed Jev question set, read from
 * `miaotoujunshi/references/data/judge-questions.json` — the same calibrated
 * wording Windows and macOS send (docs/adr/0005). Nothing
 * is retyped here; this object shapes it for the wire. Instructions/criteria are
 * English, chat text stays Chinese, and the state `from` field uses "me"/"other"
 * (the instructions already refer to "the other person" throughout).
 */
object JevQuestions {

    /**
     * Appended to every question so the D-stage `background` field (relationship,
     * contact notes, knowledge-base hits) reads as given context rather than as
     * an off-topic digression that should be penalized. Android-only: the other
     * ports send no `background`, so the note stays here.
     */
    const val BACKGROUND_NOTE =
        " Facts given in background are provided context, not off-topic."

    private fun shared(): JSONObject = SharedMaterial.data("judge-questions.json")

    /** A copy of one shared question, with Android's context note appended. */
    private fun noted(question: JSONObject): JSONObject =
        JSONObject(question.toString())
            .put("instructions", question.getString("instructions") + BACKGROUND_NOTE)

    /** The 7 judgment questions, in the shared order. Returns a fresh JSONObject each call. */
    fun judge(): JSONObject = JSONObject().also { out ->
        val source = shared().getJSONObject("questions")
        source.keys().forEach { name -> out.put(name, noted(source.getJSONObject(name))) }
    }

    /**
     * Build Jev state from a snapshot (last 10 messages), optionally carrying
     * the D-stage knowledge context.
     *
     * @param background relationship + contact notes + matched knowledge notes.
     * @param history older messages for this contact, already de-duplicated
     *        against what is on screen.
     *
     * Both extra fields are omitted when empty, so a user with no knowledge base
     * sends exactly the same body v1.2 did.
     */
    fun buildState(
        snapshot: ChatSnapshot,
        relationship: String,
        background: String = "",
        history: List<LogEntry> = emptyList()
    ): JSONObject {
        val msgs = JSONArray()
        val last10 = snapshot.messages.takeLast(10)
        for (m in last10) {
            msgs.put(JSONObject().put("from", m.side).put("text", m.text))
        }
        val chat = JSONObject()
            .put("relationship", relationship)
            .put("messages", msgs)
            .put("latest_from", last10.lastOrNull()?.side ?: "other")
        val state = JSONObject().put("chat", chat)
        if (background.isNotBlank()) state.put("background", background)
        if (history.isNotEmpty()) {
            val h = JSONArray()
            history.forEach { h.put(JSONObject().put("from", it.side).put("text", it.text)) }
            state.put("history", h)
        }
        return state
    }

    /** The best_reply ranking question over exactly 3 candidates (Chinese text kept). */
    fun rankQuestion(candidates: List<String>): JSONObject {
        require(candidates.size == 3) { "rankQuestion expects exactly 3 candidates" }
        val keys = listOf("reply_a", "reply_b", "reply_c")
        val criteria = JSONObject()
        keys.forEachIndexed { i, k -> criteria.put(k, candidates[i]) }
        val q = JSONObject().apply {
            put("type", "choice")
            put("instructions", shared().getString("rank_instructions") + BACKGROUND_NOTE)
            put("criteria", criteria)
        }
        return JSONObject().put("best_reply", q)
    }
}
