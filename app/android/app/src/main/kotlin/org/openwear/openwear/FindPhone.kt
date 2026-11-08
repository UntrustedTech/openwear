package org.openwear.openwear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.content.ContextCompat

/**
 * Find phone: alarm sound, vibration and a flashing full-screen page that
 * shows over the lock screen, for up to [RING_MS]. It stops when the user
 * taps "Found it", unlocks the phone, or the band says stop.
 */
object FindPhone {
    private const val RING_MS = 30_000L
    private const val CHANNEL = "find_phone"
    private const val NOTIFICATION_ID = 7

    /** Sent by the page's and the notification's "Found it". */
    const val ACTION_FOUND = "org.openwear.openwear.FIND_PHONE_FOUND"

    private val main = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null

    /** The Vibrator that started the buzzing: Android only lets that same
     *  instance cancel it, so it is kept until stop. */
    private var buzzer: Vibrator? = null
    private var unlockReceiver: BroadcastReceiver? = null
    private lateinit var app: Context
    private val timeout = Runnable { stop(app, byPhone = true) }

    /** The open flashing page, closed when ringing stops. */
    var page: FindPhoneActivity? = null

    val ringing get() = ringtone != null

    fun start(context: Context) {
        app = context.applicationContext
        stop(app, byPhone = false)
        ringtone = RingtoneManager.getRingtone(app, alarmUri())?.apply {
            audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= 28) isLooping = true
            play()
        }
        buzzer = vibrator(app)?.apply {
            vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0))
        }
        main.postDelayed(timeout, RING_MS)
        // Unlocking means the phone was found. (Not SCREEN_ON: the page
        // itself turns the screen on.)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) = stop(app, byPhone = true)
        }
        ContextCompat.registerReceiver(
            app, receiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(ACTION_FOUND)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        unlockReceiver = receiver
        showPage()
    }

    /** [byPhone]: stopped on the phone, so the band is told to stop too. */
    fun stop(context: Context, byPhone: Boolean) {
        main.removeCallbacks(timeout)
        unlockReceiver?.let { runCatching { context.applicationContext.unregisterReceiver(it) } }
        unlockReceiver = null
        val wasRinging = ringtone != null
        ringtone?.stop()
        ringtone = null
        buzzer?.cancel()
        buzzer = null
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        page?.finish()
        page = null
        if (wasRinging && byPhone) PhoneBridge.emit(mapOf("kind" to "findPhoneStopped"))
    }

    /**
     * A full-screen-intent notification opens the page even from the
     * background and over the lock screen; without that permission
     * (Android 14+ may withhold it) it is a heads-up with "Found it".
     */
    private fun showPage() {
        val nm = app.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Find phone", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Rings and flashes when your band looks for this phone"
                setSound(null, null) // the alarm sound is played directly
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        )
        val open = PendingIntent.getActivity(
            app, 1,
            Intent(app, FindPhoneActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val found = PendingIntent.getBroadcast(
            app, 2,
            Intent(ACTION_FOUND).setPackage(app.packageName),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(app, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_openwear)
            .setContentTitle("Your band is looking for this phone")
            .setContentText("Tap Found it to stop")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setFullScreenIntent(open, true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Found it", found).build())
            .build()
        nm.notify(NOTIFICATION_ID, notification)
    }

    private fun alarmUri() =
        RingtoneManager.getActualDefaultRingtoneUri(app, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    /** Android 14+ lets users withhold full-screen pages; true when allowed. */
    fun canShowOverLockScreen(context: Context): Boolean =
        Build.VERSION.SDK_INT < 34 ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
}
