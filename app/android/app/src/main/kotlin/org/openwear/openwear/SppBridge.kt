package org.openwear.openwear

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Classic Bluetooth serial link to the band (RFCOMM over the standard SPP UUID, as
 * Mi Fitness does). Dart sees: methods on `openwear/spp`, received bytes on
 * `openwear/spp/incoming`.
 */
class SppBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var socket: BluetoothSocket? = null
    private var sink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, "openwear/spp").setMethodCallHandler(this)
        EventChannel(messenger, "openwear/spp/incoming").setStreamHandler(this)
    }

    private val adapter get() =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bondedDevices" -> result.success(bondedDevices())
            "connect" -> connect(call.argument<String>("address") ?: "", result)
            "write" -> write(call.arguments as ByteArray, result)
            "close" -> { close(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission") // Dart requests BLUETOOTH_CONNECT before calling
    private fun bondedDevices(): List<Map<String, String>> =
        adapter?.bondedDevices.orEmpty().map { mapOf("name" to (it.name ?: ""), "address" to it.address) }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        io.execute {
            try {
                close()
                val device = adapter?.getRemoteDevice(address)
                    ?: throw IOException("Bluetooth is not available")
                adapter?.cancelDiscovery()
                val s = device.createRfcommSocketToServiceRecord(SPP_UUID)
                s.connect()
                socket = s
                Thread({ readLoop(s) }, "spp-reader").start()
                main.post { result.success(null) }
            } catch (e: IOException) {
                val bond = try {
                    when (adapter?.getRemoteDevice(address)?.bondState) {
                        BluetoothDevice.BOND_BONDED -> "bonded"
                        BluetoothDevice.BOND_BONDING -> "bonding"
                        else -> "not bonded"
                    }
                } catch (_: RuntimeException) { "unknown" }
                val on = if (adapter?.isEnabled == true) "on" else "off"
                main.post {
                    result.error("connect_failed", "${e.message} (Bluetooth $on, band $bond)", null)
                }
            } catch (e: IllegalArgumentException) {
                main.post { result.error("bad_address", e.message, null) }
            }
        }
    }

    private fun readLoop(s: BluetoothSocket) {
        val buf = ByteArray(4096)
        try {
            val input = s.inputStream
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                val chunk = buf.copyOf(n)
                main.post { sink?.success(chunk) }
            }
        } catch (e: IOException) {
            // Closed by us (socket replaced or null) or dropped by the band: report the latter.
            main.post { if (socket === s) sink?.error("read_failed", e.message ?: "socket closed", null) }
        }
        main.post { if (socket === s) sink?.endOfStream() }
    }

    private fun write(data: ByteArray, result: MethodChannel.Result) {
        io.execute {
            try {
                val s = socket ?: throw IOException("not connected")
                s.outputStream.write(data)
                s.outputStream.flush()
                main.post { result.success(null) }
            } catch (e: IOException) {
                main.post { result.error("write_failed", e.message, null) }
            }
        }
    }

    fun close() {
        try {
            socket?.close()
        } catch (e: IOException) {
            // already closed
        }
        socket = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    companion object {
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
