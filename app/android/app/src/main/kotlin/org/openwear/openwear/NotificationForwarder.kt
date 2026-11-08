package org.openwear.openwear

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Forwards posted/removed phone notifications to Dart, which sends them to the band. */
class NotificationForwarder : NotificationListenerService() {

    /** What was last forwarded per notification key, so reposts with the same text are skipped. */
    private val sent = LinkedHashMap<String, String>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification
        if (!worthForwarding(sbn, n)) return
        val extras = n.extras
        val title = (extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString()?.trim() ?: ""
        val text = (latestMessage(n)
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim() ?: ""
        if (title.isEmpty() && text.isEmpty()) return
        val content = "$title\u0000$text"
        synchronized(sent) {
            if (sent[sbn.key] == content) return // same notification posted again
            sent[sbn.key] = content
            if (sent.size > MAX_TRACKED) sent.remove(sent.keys.first())
        }
        val reply = replyAction(n)
        synchronized(replies) {
            if (reply != null) replies[sbn.key] = reply else replies.remove(sbn.key)
            if (replies.size > MAX_TRACKED) replies.remove(replies.keys.first())
        }
        PhoneBridge.emit(
            mapOf(
                "kind" to "notification",
                "canReply" to (reply != null),
                "package" to sbn.packageName,
                "appName" to appName(sbn.packageName),
                "title" to clip(title, Limits.MAX_TITLE),
                "text" to clip(text, Limits.MAX_TEXT),
                "id" to sbn.id,
                "key" to sbn.key,
                "postTime" to sbn.postTime,
            )
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        synchronized(replies) { replies.remove(sbn.key) }
        val wasSent = synchronized(sent) { sent.remove(sbn.key) != null }
        if (!wasSent) return
        PhoneBridge.emit(
            mapOf(
                "kind" to "notificationRemoved",
                "package" to sbn.packageName,
                "id" to sbn.id,
                "key" to sbn.key,
            )
        )
    }

    /** Only notifications a person would want on the wrist. */
    private fun worthForwarding(sbn: StatusBarNotification, n: Notification): Boolean {
        if (sbn.packageName == packageName) return false // our own "connected" notification
        val flags = n.flags
        if (flags and Notification.FLAG_ONGOING_EVENT != 0) return false // media, downloads, calls
        if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
        if (flags and Notification.FLAG_NO_CLEAR != 0) return false
        if (flags and Notification.FLAG_LOCAL_ONLY != 0) return false // apps ask not to bridge these
        val extras = n.extras
        if (extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0 ||
            extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE, false)
        ) return false
        if (extras.containsKey(Notification.EXTRA_MEDIA_SESSION)) return false
        when (n.category) {
            Notification.CATEGORY_TRANSPORT,
            Notification.CATEGORY_PROGRESS,
            Notification.CATEGORY_SERVICE -> return false
        }
        return !isSilent(sbn)
    }

    /** Low-importance (silent) channels do not pop up on the phone either. */
    private fun isSilent(sbn: StatusBarNotification): Boolean {
        val ranking = NotificationListenerService.Ranking()
        val map = currentRanking ?: return false
        if (!map.getRanking(sbn.key, ranking)) return false
        val importance = ranking.importance
        return importance != NotificationManager.IMPORTANCE_UNSPECIFIED &&
            importance < NotificationManager.IMPORTANCE_DEFAULT
    }

    /** The newest message of a chat notification ("Name: text" in group chats). */
    private fun latestMessage(n: Notification): CharSequence? {
        val messages: Array<out Parcelable> = (if (Build.VERSION.SDK_INT >= 33) {
            n.extras.getParcelableArray(Notification.EXTRA_MESSAGES, Parcelable::class.java)
        } else {
            @Suppress("DEPRECATION")
            n.extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        }) ?: return null
        val last = messages.lastOrNull() as? Bundle ?: return null
        val text = last.getCharSequence("text") ?: return null
        val isGroup = n.extras.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION, false)
        val sender = last.getCharSequence("sender")
        return if (isGroup && !sender.isNullOrEmpty()) "$sender: $text" else text
    }

    private fun appName(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    /** Shortens [s] to at most [max] chars without splitting an emoji. */
    private fun clip(s: String, max: Int): String {
        if (s.length <= max) return s
        val end = if (Character.isHighSurrogate(s[max - 1])) max - 1 else max
        return s.substring(0, end) + "…"
    }

    /** The notification's "Reply" action: one that takes free text. */
    private fun replyAction(n: Notification): Notification.Action? =
        n.actions?.firstOrNull { a ->
            a.actionIntent != null &&
                a.remoteInputs?.any { it.allowFreeFormInput } == true
        }

    companion object {
        private const val MAX_TRACKED = 200
        private val replies = LinkedHashMap<String, Notification.Action>()

        /** Answers notification [key] through its own reply action. */
        fun reply(context: Context, key: String, text: String): Boolean {
            val action = synchronized(replies) { replies[key] } ?: return false
            val inputs = action.remoteInputs ?: return false
            val intent = Intent()
            val results = android.os.Bundle()
            for (input in inputs) {
                if (input.allowFreeFormInput) results.putCharSequence(input.resultKey, text)
            }
            RemoteInput.addResultsToIntent(inputs, intent, results)
            return try {
                action.actionIntent.send(context, 0, intent)
                true
            } catch (e: PendingIntent.CanceledException) {
                synchronized(replies) { replies.remove(key) }
                false
            }
        }
    }

    private object Limits {
        const val MAX_TITLE = 64
        const val MAX_TEXT = 512
    }
}
