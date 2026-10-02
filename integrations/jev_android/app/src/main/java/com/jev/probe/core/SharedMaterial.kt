package com.jev.probe.core

import android.content.Context
import org.json.JSONObject

/**
 * The single entry point for the material all three ports share
 * (see docs/adr/0006).
 *
 * The content lives in two payload directories at the repository root — this
 * repository's own `miaotoujunshi/` and the upstream skill payload's `SKILL.md`.
 * The build copies both into `assets/` under the same repository paths, and this
 * object reads them back at runtime. No copy is kept here: a missing file is a
 * hard error, because failing the first analysis beats silently falling back to
 * an inlined piece of text that goes stale.
 */
object SharedMaterial {
    private var reader: ((String) -> String)? = null
    private val cache = HashMap<String, String>()

    fun install(context: Context) = install { path ->
        context.applicationContext.assets.open(path)
            .use { it.readBytes().toString(Charsets.UTF_8) }
    }

    /** Binds the reader. Production uses [install] with assets; JVM tests bind the same files. */
    fun install(read: (String) -> String) {
        reader = read
        cache.clear()
    }

    fun raw(path: String): String {
        cache[path]?.let { return it }
        val read = reader ?: error("跨端公用材料尚未加载")
        val text = try {
            read(path)
        } catch (e: Exception) {
            throw IllegalStateException("读不到跨端公用材料 $path；确认它已随 APK 一起打包", e)
        }
        cache[path] = text
        return text
    }

    fun data(name: String): JSONObject = JSONObject(raw("miaotoujunshi/references/data/$name"))

    /** This repository's own shared tone and trade-off rules. */
    fun toneRules(): String = raw("miaotoujunshi/references/knowledge/口吻与取舍.md")

    /** The upstream skill payload's entry document. Read-only: it stays byte-identical. */
    fun skillDocument(): String = raw("goutoujunshi/SKILL.md")

    /** The demo case manifest: id, title and the CSV each case reads. */
    fun caseManifest(): JSONObject =
        JSONObject(raw("miaotoujunshi/examples/relationship_cases/manifest.json"))

    /** Illustrative candles per case id, from the same bundle as the manifest. */
    fun demoCandles(): JSONObject =
        JSONObject(raw("miaotoujunshi/examples/relationship_cases/demo_kline.json"))
            .getJSONObject("cases")
}
