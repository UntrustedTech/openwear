package org.openwear.openwear

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var healthConnect: HealthConnectBridge? = null
    private var translate: TranslateBridge? = null
    private var spp: SppBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        spp = SppBridge(applicationContext, messenger)
        PhoneBridge(applicationContext, messenger)
        HttpBridge(applicationContext, messenger)
        MediaBridge(applicationContext, messenger)
        FileBridge(applicationContext, messenger)
        translate = TranslateBridge(messenger)
        healthConnect = HealthConnectBridge(applicationContext, messenger).also { it.activity = this }
        // Back on the main screen sends the app to the background (see
        // home_screen.dart): closing would end the band connection.
        io.flutter.plugin.common.MethodChannel(messenger, "openwear/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToBackground") {
                    moveTaskToBack(true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    @Deprecated("Health Connect's permission screen reports back here")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == HealthConnectBridge.REQUEST_CODE) {
            healthConnect?.onRuntimePermissionResult()
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == HealthConnectBridge.REQUEST_CODE) {
            healthConnect?.onPermissionResult(resultCode, data)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        // A screen that is gone cannot use the link; free the band for the next one.
        spp?.close()
        healthConnect?.activity = null
        healthConnect?.dispose()
        translate?.dispose()
        super.onDestroy()
    }
}
