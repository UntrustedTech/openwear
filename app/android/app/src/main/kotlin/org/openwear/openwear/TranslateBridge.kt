package org.openwear.openwear

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * On-device Chinese → phone-language translation of watch-face names with
 * ML Kit. Text never leaves the phone; only the language model is
 * downloaded once from Google. No account or API key.
 */
class TranslateBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val translators = HashMap<String, Translator>()

    init {
        MethodChannel(messenger, "openwear/translate").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "translate") {
            result.notImplemented()
            return
        }
        val text = call.argument<String>("text")
        val target = call.argument<String>("language")?.let(TranslateLanguage::fromLanguageTag)
        if (text.isNullOrBlank() || target == null || target == TranslateLanguage.CHINESE) {
            result.success(null)
            return
        }
        val translator = translators.getOrPut(target) {
            Translation.getClient(
                TranslatorOptions.Builder()
                    .setSourceLanguage(TranslateLanguage.CHINESE)
                    .setTargetLanguage(target)
                    .build()
            )
        }
        translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
            .onSuccessTask { translator.translate(text) }
            .addOnSuccessListener { result.success(it) }
            .addOnFailureListener { result.error("translate", it.message, null) }
    }

    fun dispose() {
        translators.values.forEach { it.close() }
        translators.clear()
    }
}
