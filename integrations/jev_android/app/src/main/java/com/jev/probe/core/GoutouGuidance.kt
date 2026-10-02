package com.jev.probe.core

/**
 * Evidence-first rules shared by the Android draft prompt and overlay.
 *
 * The wording itself belongs to all three ports and is read from this
 * repository's own payload at runtime (docs/adr/0006); this object only applies
 * it, so no rule text is retyped here.
 */
object GoutouGuidance {

    fun explicitBoundary(snapshot: ChatSnapshot): Boolean {
        val latest = snapshot.messages.lastOrNull() ?: return false
        if (latest.side != "other") return false
        val terms = SharedMaterial.data("boundaries.json").getJSONArray("no_contact_terms")
        return (0 until terms.length()).any { latest.text.contains(terms.getString(it)) }
    }

    fun nextStep(action: String?): String {
        val judge = SharedMaterial.data("judge-questions.json")
        val table = judge.getJSONObject("next_step")
        return if (action != null && table.has(action)) table.getString(action)
               else judge.getString("next_step_fallback")
    }

    val stopCondition: String
        get() = SharedMaterial.data("boundaries.json").getString("stop_condition")

    /** The app layer's shared tone and trade-off rules, for the draft prompt. */
    fun toneRules(): String = SharedMaterial.toneRules()

    /** The skill payload's entry document, for the draft prompt. */
    fun skillDocument(): String = SharedMaterial.skillDocument()

    /** Shared candidate length tier, in characters. */
    fun lengthCap(tier: String): Int =
        SharedMaterial.data("reply-preferences.json").getJSONObject("lengths").getInt(tier)
}
