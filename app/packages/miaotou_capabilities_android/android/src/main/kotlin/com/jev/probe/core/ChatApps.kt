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
     *
     * **Step 2 only answers because the manifest asks to see other apps.**
     * Since Android 11 a package is invisible to `PackageManager` unless the
     * querying app declares it, so `getApplicationInfo` throws for Douyin and
     * every other unlisted app; `AndroidManifest.xml` therefore declares a
     * `MAIN`/`LAUNCHER` intent query, which covers every app with a launcher
     * icon without reaching for `QUERY_ALL_PACKAGES`. This is the one place in
     * the build that asks the system for a name — the result travels to the
     * panel on the conversation reference (ADR-0028) rather than being rendered
     * into a sentence here.
     */
    fun displayName(pkg: String?, context: Context?): String? {
        if (pkg.isNullOrBlank()) return null
        NAMES[pkg]?.let { return it }
        return systemName(pkg, context)
    }

    /**
     * The system's name for a package, asked once and remembered.
     *
     * **Remembered because this is on the hot path.** The conversation event is
     * built for every accessibility wake-up — a scroll through a chat produces
     * one per frame — and a `PackageManager` lookup is a binder call across
     * processes. The answer is a property of an installed package and does not
     * change while this process lives, so asking twice buys nothing.
     *
     * A null [context] is not cached: it means nobody could be asked, which is
     * not the same fact as "the system has no name for it".
     */
    private fun systemName(pkg: String, context: Context?): String {
        if (context == null) return pkg
        synchronized(systemNames) {
            systemNames[pkg]?.let { return it }
        }
        val label = runCatching {
            val info = context.packageManager.getApplicationInfo(pkg, 0)
            context.packageManager.getApplicationLabel(info).toString()
        }.getOrNull()
        val resolved = label?.takeIf { it.isNotBlank() } ?: pkg
        synchronized(systemNames) { systemNames[pkg] = resolved }
        return resolved
    }

    /** Package name to the name the system reports, or to the package itself. */
    private val systemNames = HashMap<String, String>()

    private val NAMES = mapOf(
        "com.tencent.mm" to "微信",
        "com.tencent.mobileqq" to "QQ",
        "com.ss.android.lark" to "飞书",
        "com.twitter.android" to "X"
    )
}
