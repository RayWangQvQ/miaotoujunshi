package com.jev.probe.core

import org.json.JSONObject
import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.time.LocalDateTime

/** Message-direction balance: other +1, me -1. It is not a relationship score. */
data class TrendCandle(val date: String, val open: Int, val high: Int, val low: Int, val close: Int)

object TrendData {
    /** CSV contract and limits, shared with the other two ports (docs/adr/0005). */
    private val rules: JSONObject get() = SharedMaterial.data("trend-rules.json")

    /** (case id, display title), from the manifest in the shared demo case bundle. */
    fun cases(): List<Pair<String, String>> {
        val rows = SharedMaterial.caseManifest().getJSONArray("cases")
        return (0 until rows.length()).map {
            val row = rows.getJSONObject(it)
            row.getString("id") to row.getString("title")
        }
    }

    /** Illustrative candles for one case id; they live beside the manifest, not here. */
    fun example(caseId: String): List<TrendCandle> {
        val rows = SharedMaterial.demoCandles().optJSONArray(caseId) ?: error("没有这个示例走势")
        return (0 until rows.length()).map { i ->
            val row = rows.getJSONArray(i)
            TrendCandle(row.getString(0), row.getInt(1), row.getInt(2), row.getInt(3), row.getInt(4))
        }
    }

    fun fromCsv(input: InputStream): List<TrendCandle> {
        val limits = rules
        val maxBytes = limits.getInt("max_bytes")
        val maxMessages = limits.getInt("max_messages")
        val columns = limits.getJSONArray("columns").let { a -> (0 until a.length()).map { a.getString(it) } }
        val senders = limits.getJSONArray("senders").let { a -> (0 until a.length()).map { a.getString(it) } }
        val bytes = input.use { source ->
            val out = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            while (out.size() <= maxBytes) {
                val n = source.read(chunk)
                if (n < 0) break
                out.write(chunk, 0, n)
            }
            out.toByteArray()
        }
        require(bytes.size <= maxBytes) { "CSV 超过 4 MB，请缩小范围" }
        val text = bytes.toString(Charsets.UTF_8).removePrefix("\uFEFF")
        val records = parseCsv(text)
        require(records.isNotEmpty()) { "CSV 没有内容" }
        val header = records.first().map { it.trim() }
        val t = header.indexOf(columns[0]); val s = header.indexOf(columns[1]); val m = header.indexOf(columns[2])
        require(t >= 0 && s >= 0 && m >= 0) { "CSV 需要 ${columns.joinToString(",")} 三列" }
        require(records.size in 2..maxMessages + 1) { "聊天记录须为 1 到 $maxMessages 条" }
        val candles = ArrayList<TrendCandle>()
        var balance = 0
        var previous: LocalDateTime? = null
        for (record in records.drop(1)) {
            require(record.size > maxOf(t, s, m)) { "CSV 行列不完整" }
            val at = try { LocalDateTime.parse(record[t].trim().replace(' ', 'T')) }
                     catch (_: Exception) { throw IllegalArgumentException("timestamp 需要 YYYY-MM-DD HH:MM:SS") }
            require(previous == null || !at.isBefore(previous)) { "聊天时间须按升序排列" }
            previous = at
            val sender = record[s].trim()
            require(sender in senders) { "sender 只接受 ${senders.joinToString("／")}" }
            require(record[m].isNotBlank()) { "存在空消息，请核对 CSV" }
            val date = at.toLocalDate().toString()
            if (candles.isEmpty() || candles.last().date != date)
                candles.add(TrendCandle(date, balance, balance, balance, balance))
            balance += if (sender == "other") 1 else -1
            val old = candles.last()
            candles[candles.lastIndex] = old.copy(high = maxOf(old.high, balance),
                low = minOf(old.low, balance), close = balance)
        }
        return candles
    }

    /** RFC-style quoted commas, escaped quotes and quoted newlines. */
    private fun parseCsv(text: String): List<List<String>> {
        val records = ArrayList<List<String>>()
        var row = ArrayList<String>()
        val cell = StringBuilder()
        var quoted = false
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                c == '"' && quoted && i + 1 < text.length && text[i + 1] == '"' -> {
                    cell.append('"'); i++
                }
                c == '"' -> quoted = !quoted
                c == ',' && !quoted -> { row.add(cell.toString()); cell.setLength(0) }
                (c == '\n' || c == '\r') && !quoted -> {
                    if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++
                    row.add(cell.toString()); cell.setLength(0)
                    if (row.any { it.isNotBlank() }) records.add(row)
                    row = ArrayList()
                }
                else -> cell.append(c)
            }
            i++
        }
        require(!quoted) { "CSV 引号没有闭合" }
        if (cell.isNotEmpty() || row.isNotEmpty()) {
            row.add(cell.toString())
            if (row.any { it.isNotBlank() }) records.add(row)
        }
        return records
    }
}
