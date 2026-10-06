package com.jev.probe.core

import android.content.Context

/**
 * Naming for the chat apps this build knows how to work with.
 *
 * Extracted from KnowledgeActivity so the overlay header and the knowledge-base
 * contact list agree on one spelling for the same package.
 */
object ChatApps {

    /**
     * A display name for a package, resolved in this order (ADR-0026):
     *
     * 1. the [NAMES] whitelist — the apps this build has an adapter for;
     * 2. the system's own label via [android.content.pm.PackageManager], so an
     *    app we have no adapter for (Douyin, …) still shows its real name;
     * 3. the bare package name, so the user still sees *something*;
     * 4. null — only when even the package is unknown (no window in front).
     *
     * Null is a real answer, not a failure. The knowledge-base list wants to
     * show the raw package regardless (it is telling the user which app a
     * contact was seen in), while the overlay header resolves to the best
     * available name and never guesses one.
     */
    fun displayName(pkg: String?, context: Context?): String? {
        if (pkg.isNullOrBlank()) return null
        NAMES[pkg]?.let { return it }
        val label = context?.let { ctx ->
            runCatching {
                val info = ctx.packageManager.getApplicationInfo(pkg, 0)
                ctx.packageManager.getApplicationLabel(info)?.toString()
            }.getOrNull()
        }
        return label?.takeIf { it.isNotBlank() } ?: pkg
    }

    private val NAMES = mapOf(
        "com.tencent.mm" to "微信",
        "com.tencent.mobileqq" to "QQ",
        "com.ss.android.lark" to "飞书",
        "com.twitter.android" to "X"
    )
}
