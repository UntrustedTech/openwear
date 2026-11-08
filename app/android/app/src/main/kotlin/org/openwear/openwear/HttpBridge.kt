package org.openwear.openwear

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Cloud requests through Android's own HTTP stack (system DNS, proxy, VPN and
 * IPv4/IPv6 fallback). No redirects or cookies: the Dart client handles both.
 */
class HttpBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "openwear/http").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "send" -> send(call, result)
            "networkInfo" -> result.success(networkInfo())
            else -> result.notImplemented()
        }
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val method = call.argument<String>("method") ?: "GET"
        val url = call.argument<String>("url") ?: ""
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        val body = call.argument<String>("body")
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 20000
        if (!url.startsWith("https://")) {
            result.error("insecure", "Only HTTPS requests are allowed", null)
            return
        }
        io.execute {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    instanceFollowRedirects = false
                    useCaches = false
                    connectTimeout = timeoutMs
                    readTimeout = timeoutMs
                    headers.forEach { (k, v) -> setRequestProperty(k, v) }
                }
                if (body != null) {
                    val bytes = body.toByteArray(Charsets.UTF_8)
                    conn.doOutput = true
                    conn.setFixedLengthStreamingMode(bytes.size)
                    conn.outputStream.use { it.write(bytes) }
                }
                val status = conn.responseCode
                val stream = if (status >= 400) conn.errorStream else conn.inputStream
                val text = stream?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
                val cookies = conn.headerFields.entries
                    .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
                    .flatMap { it.value }
                val reply = mapOf(
                    "status" to status,
                    "body" to text,
                    "location" to conn.getHeaderField("Location"),
                    "cookies" to cookies,
                )
                main.post { result.success(reply) }
            } catch (e: IOException) {
                // The class name says what failed: UnknownHost, SocketTimeout, Connect, SSL…
                val kind = e.javaClass.simpleName.removeSuffix("Exception")
                main.post { result.error(kind, e.message ?: kind, null) }
            } finally {
                conn?.disconnect()
            }
        }
    }

    /** Active network type, VPN and Private DNS, for the network check. */
    private fun networkInfo(): Map<String, String> {
        val info = mutableMapOf<String, String>()
        val cm = context.getSystemService(ConnectivityManager::class.java)
        val caps = cm?.activeNetwork?.let { cm.getNetworkCapabilities(it) }
        info["network"] = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile data"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
        if (caps != null) {
            info["vpn"] = caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN).toString()
            info["internet validated"] =
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED).toString()
        }
        cm?.activeNetwork?.let { cm.getLinkProperties(it) }?.let { lp ->
            info["private DNS active"] = lp.isPrivateDnsActive.toString()
            lp.privateDnsServerName?.let { info["private DNS server"] = it }
            info["DNS servers"] = lp.dnsServers.joinToString { it.hostAddress ?: "?" }
        }
        try {
            Settings.Global.getString(context.contentResolver, "private_dns_mode")
                ?.let { info["private DNS mode"] = it }
            Settings.Global.getString(context.contentResolver, "private_dns_specifier")
                ?.takeIf { it.isNotEmpty() }?.let { info["private DNS setting"] = it }
        } catch (_: SecurityException) {
            // not readable on this Android version
        }
        return info
    }
}
