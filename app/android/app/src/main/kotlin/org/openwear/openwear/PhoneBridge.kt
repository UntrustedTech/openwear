package org.openwear.openwear

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.location.Geocoder
import android.location.LocationManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.TimeZone

/**
 * Phone-side facts the band needs: notifications (from [NotificationForwarder]), call
 * state, app icons, time zone, and the call actions pressed on the band.
 * Methods on `openwear/phone`; events on `openwear/phone/events`.
 */
class PhoneBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var callReceiver: BroadcastReceiver? = null

    init {
        MethodChannel(messenger, "openwear/phone").setMethodCallHandler(this)
        EventChannel(messenger, "openwear/phone/events").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "timeZone" -> result.success(timeZone())
            "deviceInfo" -> result.success(deviceInfo())
            "lastLocation" -> currentLocation(result)
            "appIcon" -> result.success(
                appIcon(call.argument<String>("package") ?: "", call.argument<Int>("size") ?: 0)
            )
            "notificationAccessGranted" -> result.success(notificationAccessGranted())
            "openNotificationAccessSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "openBluetoothSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "findPhoneOverLockScreen" -> result.success(FindPhone.canShowOverLockScreen(context))
            "openFindPhoneOverLockScreenSettings" -> {
                val intent = if (android.os.Build.VERSION.SDK_INT >= 34) {
                    Intent(
                        Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                        Uri.parse("package:${context.packageName}"),
                    )
                } else {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                }
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "findPhone" -> {
                if (call.argument<Boolean>("ring") == true) startRinging() else stopRinging()
                result.success(null)
            }
            "replyNotification" -> result.success(
                NotificationForwarder.reply(
                    context,
                    call.argument<String>("key") ?: "",
                    call.argument<String>("text") ?: "",
                )
            )
            "endCall" -> result.success(endCall())
            "silenceRinger" -> result.success(silenceRinger())
            "startService" -> {
                ContextCompat.startForegroundService(context, Intent(context, CompanionService::class.java))
                result.success(null)
            }
            "stopService" -> {
                context.stopService(Intent(context, CompanionService::class.java))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startRinging() = FindPhone.start(context)

    private fun stopRinging() = FindPhone.stop(context, byPhone = false)

    /**
     * Approximate location for weather: a recent last-known fix if there is one,
     * otherwise a fresh network/fused fix (up to 15 s). Errors: "permission",
     * "disabled" (location off), "noFix".
     */
    @SuppressLint("MissingPermission") // checked just below
    private fun currentLocation(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) {
            return result.error("permission", "Approximate location is not allowed for OpenWear", null)
        }
        val lm = context.getSystemService(LocationManager::class.java)
            ?: return result.error("noFix", "No location service", null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !lm.isLocationEnabled) {
            return result.error("disabled", "Location is turned off on the phone", null)
        }
        val recent = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER,
            LocationManager.GPS_PROVIDER, "fused")
            .mapNotNull { p -> try { lm.getLastKnownLocation(p) } catch (_: Exception) { null } }
            .maxByOrNull { it.time }
        val maxAgeMs = 3 * 60 * 60 * 1000L
        if (recent != null && System.currentTimeMillis() - recent.time < maxAgeMs) {
            return reply(result, recent)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return if (recent != null) reply(result, recent)
            else result.error("noFix", "The phone has no location yet", null)
        }
        val provider = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && lm.hasProvider(LocationManager.FUSED_PROVIDER) ->
                LocationManager.FUSED_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> LocationManager.GPS_PROVIDER
        }
        val cancel = android.os.CancellationSignal()
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        var answered = false
        val timeout = Runnable {
            if (answered) return@Runnable
            answered = true
            cancel.cancel()
            if (recent != null) reply(result, recent)
            else result.error("noFix", "No location fix within 15 s", null)
        }
        main.postDelayed(timeout, 15_000)
        lm.getCurrentLocation(provider, cancel, context.mainExecutor) { loc ->
            if (answered) return@getCurrentLocation
            answered = true
            main.removeCallbacks(timeout)
            val best = loc ?: recent
            if (best == null) result.error("noFix", "The phone could not get a location", null)
            else reply(result, best)
        }
    }

    /** Adds the town name (on a background thread: Geocoder can block). */
    private fun reply(result: MethodChannel.Result, loc: android.location.Location) {
        Thread {
            val place = try {
                @Suppress("DEPRECATION")
                Geocoder(context).getFromLocation(loc.latitude, loc.longitude, 1)?.firstOrNull()
                    ?.let { it.locality ?: it.subAdminArea ?: it.adminArea }
            } catch (_: Exception) { null }
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(mapOf("lat" to loc.latitude, "lon" to loc.longitude,
                    "timeMs" to loc.time, "place" to (place ?: "")))
            }
        }.start()
    }

    private fun deviceInfo(): Map<String, String> {
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "?"
        } catch (_: PackageManager.NameNotFoundException) { "?" }
        return mapOf(
            "app" to "OpenWear $version",
            "phone" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "android" to "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
        )
    }

    private fun timeZone(): Map<String, Any> {
        val tz = TimeZone.getDefault()
        val now = System.currentTimeMillis()
        val dst = if (tz.inDaylightTime(java.util.Date(now))) tz.dstSavings else 0
        return mapOf("id" to tz.id, "standardOffsetMs" to tz.rawOffset, "dstOffsetMs" to dst)
    }

    /** The launcher icon of [pkg] scaled to [size]², as RGBA rows, or null. */
    private fun appIcon(pkg: String, size: Int): ByteArray? {
        if (size <= 0) return null
        val drawable = try {
            context.packageManager.getApplicationIcon(pkg)
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        val buffer = ByteBuffer.allocate(bitmap.byteCount)
        bitmap.copyPixelsToBuffer(buffer) // ARGB_8888 is stored as R,G,B,A bytes
        bitmap.recycle()
        return buffer.array()
    }

    private fun notificationAccessGranted(): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
        val me = ComponentName(context, NotificationForwarder::class.java).flattenToString()
        return enabled.split(':').any { it == me }
    }

    @SuppressLint("MissingPermission") // ANSWER_PHONE_CALLS is requested from Dart
    private fun endCall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        return try {
            @Suppress("DEPRECATION") telecom.endCall()
        } catch (e: SecurityException) {
            false
        }
    }

    private fun silenceRinger(): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return try {
            audio.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_MUTE, 0)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    // --- events -------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        listenForCalls()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stopListeningForCalls()
    }

    /** Phone-state broadcasts carry the caller's number when READ_CALL_LOG is granted. */
    private fun listenForCalls() {
        if (callReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                @Suppress("DEPRECATION")
                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
                val state = when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
                    TelephonyManager.EXTRA_STATE_RINGING -> "ringing"
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> "offhook"
                    else -> "idle"
                }
                emit(mapOf("kind" to "call", "state" to state, "number" to number,
                    "name" to contactName(number)))
            }
        }
        ContextCompat.registerReceiver(context, receiver,
            IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED), ContextCompat.RECEIVER_EXPORTED)
        callReceiver = receiver
    }

    private fun stopListeningForCalls() {
        callReceiver?.let { context.unregisterReceiver(it) }
        callReceiver = null
    }

    private fun contactName(number: String): String {
        if (number.isEmpty() || ContextCompat.checkSelfPermission(context,
                android.Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return ""
        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
        context.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
            null, null, null)?.use { c -> if (c.moveToFirst()) return c.getString(0) ?: "" }
        return ""
    }

    companion object {
        @Volatile
        private var sink: EventChannel.EventSink? = null
        private val handler = Handler(Looper.getMainLooper())

        /** Delivers an event to Dart from any thread (also used by [NotificationForwarder]). */
        fun emit(event: Map<String, Any?>) {
            handler.post { sink?.success(event) }
        }
    }
}
