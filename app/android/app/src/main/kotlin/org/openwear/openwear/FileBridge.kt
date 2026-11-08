package org.openwear.openwear

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Copies files the user should be able to reach (firmware packages) into
 * the phone's public Download folder. Methods on `openwear/files`.
 */
class FileBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val io = Executors.newSingleThreadExecutor()

    init {
        MethodChannel(messenger, "openwear/files").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveToDownloads" -> {
                val folder = call.argument<String>("folder") ?: ""
                val name = call.argument<String>("name") ?: ""
                val bytes = call.argument<ByteArray>("bytes")
                val replace = call.argument<Boolean>("replace") ?: true
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                if (!safeName(folder) || !safeName(name) || bytes == null) {
                    result.error("bad_args", "folder, name and bytes are required", null)
                    return
                }
                io.execute {
                    try {
                        val where = save(folder, name, bytes, replace, mime)
                        android.os.Handler(context.mainLooper).post { result.success(where) }
                    } catch (e: Exception) {
                        android.os.Handler(context.mainLooper).post {
                            result.error("save_failed", e.message ?: e.javaClass.simpleName, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Only plain path parts: no separators beyond '/', no "..". */
    private fun safeName(s: String) =
        s.isNotEmpty() && !s.contains("..") && !s.startsWith("/") &&
            s.all { it.isLetterOrDigit() || it in "._- /" }

    /**
     * Writes [bytes] as Download/[folder]/[name]. With [replace], every earlier
     * file this app put in that folder is removed first, so only the latest is
     * kept. Returns the path as the user sees it.
     */
    private fun save(
        folder: String,
        name: String,
        bytes: ByteArray,
        replace: Boolean,
        mime: String,
    ): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Without MediaStore downloads, the app's own external folder is
            // still reachable from a file manager (Android/data/…).
            val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), folder)
            dir.mkdirs()
            if (replace) dir.listFiles()?.forEach { it.delete() }
            File(dir, name).writeBytes(bytes)
            return File(dir, name).absolutePath
        }
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/$folder/"
        // Files this app inserted are visible to it without any permission.
        if (replace) resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(relative),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                resolver.delete(
                    android.content.ContentUris.withAppendedId(collection, c.getLong(0)),
                    null,
                    null,
                )
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("could not create the file")
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("could not open the file")
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return "$relative$name"
    }
}
