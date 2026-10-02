package com.jev.probe.core

/**
 * Naming for the chat apps this build knows how to work with.
 *
 * Extracted from KnowledgeActivity so the overlay header and the knowledge-base
 * contact list agree on one spelling for the same package.
 */
object ChatApps {

    /**
     * Chinese display name for a package, or null when this build has no name
     * for it.
     *
     * Null is a real answer, not a failure — the two callers want different
     * fallbacks. The knowledge-base list wants to show the raw package (it is
     * telling the user which app a contact was seen in), while the overlay
     * header must never echo a raw package name into the UI and falls back to a
     * neutral label instead.
     */
    fun displayName(pkg: String?): String? = pkg?.let { NAMES[it] }

    private val NAMES = mapOf(
        "com.tencent.mm" to "微信",
        "com.tencent.mobileqq" to "QQ",
        "com.ss.android.lark" to "飞书",
        "com.twitter.android" to "X"
    )
}
