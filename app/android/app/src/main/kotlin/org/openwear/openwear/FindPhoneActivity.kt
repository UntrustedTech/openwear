package org.openwear.openwear

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The page shown while Find phone rings: over the lock screen, screen on at
 * full brightness, fading between the brand orange and white so the phone
 * is easy to spot. The fade is about one cycle per second, well below
 * photosensitive-flash rates.
 */
class FindPhoneActivity : Activity() {

    private var flash: ValueAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!FindPhone.ringing) {
            finish()
            return
        }
        FindPhone.page = this
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.attributes = window.attributes.apply {
            screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
        }

        val title = TextView(this).apply {
            text = "Here I am"
            setTextColor(Color.parseColor("#0C0C0E"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 44f)
            gravity = Gravity.CENTER
        }
        val detail = TextView(this).apply {
            text = "Your band is looking for this phone"
            setTextColor(Color.parseColor("#0C0C0E"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(48))
        }
        val found = Button(this).apply {
            text = "Found it"
            isAllCaps = false
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#0C0C0E"))
                cornerRadius = dp(32).toFloat()
            }
            setPadding(dp(48), dp(18), dp(48), dp(18))
            setOnClickListener { foundIt() }
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            addView(title)
            addView(detail)
            addView(found)
        }
        setContentView(root)

        flash = ValueAnimator.ofObject(
            ArgbEvaluator(),
            Color.parseColor("#FF5B1F"),
            Color.WHITE,
        ).apply {
            duration = 500
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { root.setBackgroundColor(it.animatedValue as Int) }
            start()
        }
    }

    /**
     * Stops ringing and closes the page. The lock screen is left exactly as
     * it was: this page never dismisses or bypasses the keyguard, so the
     * phone still needs its PIN, pattern or biometrics to open.
     */
    private fun foundIt() {
        FindPhone.stop(this, byPhone = true)
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (!FindPhone.ringing) finish()
    }

    override fun onDestroy() {
        flash?.cancel()
        if (FindPhone.page === this) FindPhone.page = null
        super.onDestroy()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
