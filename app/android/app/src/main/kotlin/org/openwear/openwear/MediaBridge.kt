package org.openwear.openwear

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's current media player, for the band's music screen. Reading other apps'
 * sessions is allowed because OpenWear is an enabled notification listener.
 */
class MediaBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(AudioManager::class.java)
    private val sessions = context.getSystemService(MediaSessionManager::class.java)
    private val listener = ComponentName(context, NotificationForwarder::class.java)
    private var sink: EventChannel.EventSink? = null
    private var current: MediaController? = null

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = emit()
        override fun onMetadataChanged(metadata: MediaMetadata?) = emit()
        override fun onSessionDestroyed() = pickController()
    }

    private val sessionsChanged =
        MediaSessionManager.OnActiveSessionsChangedListener { pickController() }

    init {
        MethodChannel(messenger, "openwear/media").setMethodCallHandler(this)
        EventChannel(messenger, "openwear/media/events").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> {
                pickController()
                result.success(state())
            }
            "control" -> result.success(control(call.argument<String>("action") ?: "", call.argument<Int>("volume")))
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        try {
            sessions?.addOnActiveSessionsChangedListener(sessionsChanged, listener, main)
        } catch (_: SecurityException) {
            // notification access not granted: state() reports it
        }
        pickController()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        sessions?.removeOnActiveSessionsChangedListener(sessionsChanged)
        current?.unregisterCallback(callback)
        current = null
    }

    /** Prefers a playing session, else the most recent one. */
    private fun pickController() {
        val list = try {
            sessions?.getActiveSessions(listener) ?: emptyList()
        } catch (_: SecurityException) {
            emptyList()
        }
        val best = list.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: list.firstOrNull()
        if (best?.sessionToken != current?.sessionToken) {
            current?.unregisterCallback(callback)
            current = best
            best?.registerCallback(callback, main)
        }
        emit()
    }

    private fun emit() {
        val s = state()
        main.post { sink?.success(s) }
    }

    private fun state(): Map<String, Any> {
        val max = audio?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
        val vol = audio?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
        val base = mutableMapOf<String, Any>("volume" to (vol * 100 / maxOf(max, 1)))
        val allowed = try {
            sessions?.getActiveSessions(listener); true
        } catch (_: SecurityException) { false }
        if (!allowed) return base + ("state" to "noPermission")
        val c = current ?: return base + ("state" to "none")
        val meta = c.metadata
        val playback = c.playbackState
        base["state"] = if (playback?.state == PlaybackState.STATE_PLAYING) "playing" else "paused"
        base["title"] = meta?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: meta?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: ""
        base["artist"] = meta?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
        base["durationMs"] = meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        base["positionMs"] = playback?.position ?: 0L
        base["app"] = c.packageName
        return base
    }

    private fun control(action: String, volume: Int?): Boolean {
        val controls = current?.transportControls
        when (action) {
            "play" -> controls?.play()
            "pause" -> controls?.pause()
            "next" -> controls?.skipToNext()
            "previous" -> controls?.skipToPrevious()
            "volume" -> {
                val max = audio?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: return false
                val target = ((volume ?: 0).coerceIn(0, 100) * max + 50) / 100
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
            }
            else -> return false
        }
        main.postDelayed({ emit() }, 300)
        return controls != null || action == "volume"
    }
}
