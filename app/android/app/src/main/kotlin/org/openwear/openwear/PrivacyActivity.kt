package org.openwear.openwear

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

/**
 * Shown by Health Connect when the user asks why OpenWear wants access
 * (required for apps that request health permissions).
 */
class PrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (24 * resources.displayMetrics.density).toInt()
        val text = TextView(this).apply {
            setPadding(pad, pad, pad, pad)
            textSize = 16f
            text = """
                OpenWear and your health data

                OpenWear writes heart-rate readings measured by your band to Health Connect so that other apps you choose can use them.

                • Data stays on your phone. OpenWear has no server and sends no health data anywhere.
                • OpenWear only writes; it does not read other apps' health data.
                • You can turn access off at any time in Health Connect settings, and delete the data there.
            """.trimIndent()
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
