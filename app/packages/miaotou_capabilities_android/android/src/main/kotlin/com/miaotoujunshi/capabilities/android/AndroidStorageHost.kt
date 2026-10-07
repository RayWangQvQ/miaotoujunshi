package com.miaotoujunshi.capabilities.android

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The device half of the storage seam: assets, the Android Keystore and
 * app-private files, none of which has a Dart API.
 *
 * The four `preferences.*` members used to be here, forwarding this app's settings
 * to `SharedPreferences`, which meant the record shape of the settings document was
 * decided twice — once in Kotlin here and once in the two desktop ports — and had
 * drifted. That document belongs to the shared Dart module now and travels over
 * `document.read` / `document.write` like the knowledge base and the memory store.
 *
 * The `SharedPreferences` left in this file belongs to [KeystoreSecretStore], where
 * a store keyed by name is exactly the right primitive and the values are opaque
 * encrypted envelopes rather than a record format.
 */
internal class AndroidStorageHost(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private val secrets = KeystoreSecretStore(context)
    private val documents = File(context.filesDir, DOCUMENT_DIRECTORY)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val arguments = call.arguments.asArguments()
            when (call.method) {
                "payload.read" -> result.success(readPayload(arguments.string("path")))
                "payload.list" -> result.success(listPayload(arguments.string("path")))
                "secret.read" -> result.success(secrets.read(arguments.string("key")))
                "secret.write" -> {
                    secrets.write(
                        arguments.string("key"),
                        arguments.string("value"),
                    )
                    result.success(null)
                }
                "secret.delete" -> {
                    secrets.delete(arguments.string("key"))
                    result.success(null)
                }
                "secret.keys" -> result.success(secrets.keys())
                "document.read" -> result.success(readDocument(arguments.string("name")))
                "document.write" -> {
                    writeDocument(
                        arguments.string("name"),
                        arguments.string("contents"),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "android_storage_${call.method.replace('.', '_')}_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    /**
     * The bytes at a packaged payload path, or null when there is no file there.
     *
     * Null rather than a refusal because on this port the payload is inside the APK:
     * an absent key *is* an incomplete package, and the Dart above this seam is the
     * one that says so, in the words all three ports share.
     */
    private fun readPayload(path: String): ByteArray? {
        validatePayloadPath(path)
        return try {
            context.assets.open(path).use { it.readBytes() }
        } catch (_: FileNotFoundException) {
            null
        }
    }

    /** The names directly inside a packaged payload directory, or null if there is none. */
    private fun listPayload(path: String): List<String>? {
        validatePayloadPath(path)
        val children = context.assets.list(path).orEmpty()
        val files = children.filter { child ->
            try {
                context.assets.open("$path/$child").use { Unit }
                true
            } catch (_: FileNotFoundException) {
                false
            }
        }.sorted()
        return files.ifEmpty { null }
    }

    private fun readDocument(name: String): String? {
        val file = document(name)
        return if (file.isFile) file.readText(StandardCharsets.UTF_8) else null
    }

    private fun writeDocument(name: String, contents: String) {
        if (!documents.exists() && !documents.mkdirs()) {
            throw IllegalStateException("could not create app-private storage directory")
        }
        val target = AtomicFile(document(name))
        val stream = target.startWrite()
        try {
            stream.write(contents.toByteArray(StandardCharsets.UTF_8))
            stream.fd.sync()
            target.finishWrite(stream)
        } catch (error: Throwable) {
            target.failWrite(stream)
            throw error
        }
    }

    private fun document(name: String): File {
        require(DOCUMENT_NAME.matches(name)) {
            "document name must be a single safe file name"
        }
        return File(documents, name)
    }

    private fun validatePayloadPath(path: String) {
        require(
            path.isNotEmpty() &&
                !path.startsWith("/") &&
                !path.startsWith("\\") &&
                path.split('/').none { it.isEmpty() || it == ".." || '\\' in it },
        ) {
            "payload path must remain inside the packaged tree"
        }
    }

    private fun Any?.asArguments(): Map<*, *> =
        this as? Map<*, *> ?: emptyMap<Any, Any>()

    private fun Map<*, *>.string(key: String): String =
        this[key] as? String ?: throw IllegalArgumentException("$key must be a string")

    private companion object {
        const val DOCUMENT_DIRECTORY = "storage"
        val DOCUMENT_NAME = Regex("[A-Za-z0-9_.-]+")
    }
}

private class KeystoreSecretStore(context: Context) {
    private val encrypted: SharedPreferences =
        context.getSharedPreferences(SECRETS_NAME, Context.MODE_PRIVATE)

    fun read(key: String): String? {
        val encoded = encrypted.getString(key, null) ?: return null
        val parts = encoded.split(':', limit = 2)
        require(parts.size == 2) { "encrypted secret has an invalid envelope" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(GCM_TAG_BITS, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        cipher.updateAAD(key.toByteArray(StandardCharsets.UTF_8))
        return String(
            cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)),
            StandardCharsets.UTF_8,
        )
    }

    fun write(key: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(key.toByteArray(StandardCharsets.UTF_8))
        val envelope = listOf(
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            Base64.encodeToString(
                cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)),
                Base64.NO_WRAP,
            ),
        ).joinToString(":")
        check(encrypted.edit().putString(key, envelope).commit()) {
            "could not persist encrypted secret"
        }
    }

    fun delete(key: String) {
        check(encrypted.edit().remove(key).commit()) {
            "could not delete encrypted secret"
        }
    }

    fun keys(): List<String> = encrypted.all.keys.sorted()

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    private companion object {
        const val SECRETS_NAME = "miaotou_secrets_encrypted"
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "miaotoujunshi.storage.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
    }
}
