package org.openwear.openwear

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Percentage
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/**
 * Writes the band's readings to Android Health Connect so other apps can use
 * them. Records carry a client id per minute so a resend replaces, not doubles.
 */
class HealthConnectBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val REQUEST_CODE = 7301
        private const val PROVIDER = "com.google.android.apps.healthdata"
        /** Write permission per kind name shared with the Dart side. */
        val KINDS = linkedMapOf(
            "heartRate" to HeartRateRecord::class,
            "steps" to StepsRecord::class,
            "activeKcal" to ActiveCaloriesBurnedRecord::class,
            "totalKcal" to TotalCaloriesBurnedRecord::class,
            "spo2" to OxygenSaturationRecord::class,
            "restingHr" to RestingHeartRateRecord::class,
            "sleep" to SleepSessionRecord::class,
        ).mapValues { HealthPermission.getWritePermission(it.value) }
        val PERMISSIONS = KINDS.values.toSet()

        private val STAGES = mapOf(
            "awake" to SleepSessionRecord.STAGE_TYPE_AWAKE,
            "inBed" to SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED,
            "sleeping" to SleepSessionRecord.STAGE_TYPE_SLEEPING,
            "light" to SleepSessionRecord.STAGE_TYPE_LIGHT,
            "deep" to SleepSessionRecord.STAGE_TYPE_DEEP,
            "rem" to SleepSessionRecord.STAGE_TYPE_REM,
        )
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val contract = PermissionController.createRequestPermissionResultContract()
    private var pendingRequest: MethodChannel.Result? = null
    var activity: Activity? = null

    init {
        MethodChannel(messenger, "openwear/health_connect").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> status(result)
            "requestPermissions" -> requestPermissions(result)
            "writeHeartRate" -> writeHeartRate(call, result)
            "writeRecords" -> writeRecords(call, result)
            "openSettings" -> openSettings(result)
            else -> result.notImplemented()
        }
    }

    /** "unavailable", "needsUpdate", or "missing:" + the kinds not allowed (comma separated). */
    private fun status(result: MethodChannel.Result) {
        when (HealthConnectClient.getSdkStatus(context, PROVIDER)) {
            HealthConnectClient.SDK_UNAVAILABLE -> return result.success("unavailable")
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                return result.success("needsUpdate")
        }
        scope.launch {
            try {
                val granted = client().permissionController.getGrantedPermissions()
                val missing = KINDS.filterValues { it !in granted }.keys
                result.success("missing:" + missing.joinToString(","))
            } catch (e: Exception) {
                result.error("status", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val act = activity ?: return result.error("noActivity", "App is not in the foreground", null)
        if (pendingRequest != null) return result.error("busy", "A request is already open", null)
        pendingRequest = result
        try {
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                // Health permissions are ordinary runtime permissions here;
                // the contract's intent only works via registerForActivityResult.
                act.requestPermissions(PERMISSIONS.toTypedArray(), REQUEST_CODE)
                return
            }
            act.startActivityForResult(contract.createIntent(act, PERMISSIONS), REQUEST_CODE)
        } catch (e: Exception) {
            pendingRequest = null
            result.error("request", e.message ?: e.javaClass.simpleName, null)
        }
    }

    /** Called from MainActivity.onRequestPermissionsResult (Android 14+). */
    fun onRuntimePermissionResult() {
        val pending = pendingRequest ?: return
        pendingRequest = null
        scope.launch {
            val granted = try {
                client().permissionController.getGrantedPermissions()
            } catch (e: Exception) {
                emptySet()
            }
            pending.success(granted.containsAll(PERMISSIONS))
        }
    }

    /** Called from MainActivity.onActivityResult. */
    fun onPermissionResult(resultCode: Int, data: Intent?) {
        val pending = pendingRequest ?: return
        pendingRequest = null
        val granted = contract.parseResult(resultCode, data)
        pending.success(granted.containsAll(PERMISSIONS))
    }

    /**
     * Arguments: list of {id, version, samples: [[epochMs, bpm], ...]}; each
     * becomes one HeartRateRecord spanning its samples. Returns how many were written.
     */
    private fun writeHeartRate(call: MethodCall, result: MethodChannel.Result) {
        val buckets = call.argument<List<Map<String, Any>>>("records") ?: emptyList()
        val zone = ZoneId.systemDefault()
        val device = Device(type = Device.TYPE_WATCH)
        val records = buckets.mapNotNull { bucket ->
            @Suppress("UNCHECKED_CAST")
            val raw = bucket["samples"] as? List<List<Number>> ?: return@mapNotNull null
            if (raw.isEmpty()) return@mapNotNull null
            val samples = raw.map {
                HeartRateRecord.Sample(Instant.ofEpochMilli(it[0].toLong()), it[1].toLong())
            }.sortedBy { it.time }
            val start = samples.first().time
            val end = samples.last().time.plusSeconds(1)
            HeartRateRecord(
                startTime = start,
                startZoneOffset = zone.rules.getOffset(start),
                endTime = end,
                endZoneOffset = zone.rules.getOffset(end),
                samples = samples,
                metadata = Metadata.autoRecorded(
                    device = device,
                    clientRecordId = bucket["id"] as String,
                    clientRecordVersion = (bucket["version"] as Number).toLong(),
                ),
            )
        }
        if (records.isEmpty()) return result.success(0)
        scope.launch {
            try {
                client().insertRecords(records)
                result.success(records.size)
            } catch (e: SecurityException) {
                result.error("permission", "Health Connect access was not granted", null)
            } catch (e: Exception) {
                result.error("write", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    /**
     * Arguments: list of {kind, id, version, start, end (epoch ms), value,
     * stages?: [[startMs, endMs, name]]}. Kinds: steps, activeKcal,
     * totalKcal, spo2, restingHr, sleep. Returns how many were written.
     */
    private fun writeRecords(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<List<Map<String, Any>>>("records") ?: emptyList()
        val records = try {
            raw.mapNotNull(::toRecord)
        } catch (e: Exception) {
            return result.error("write", "Bad record: ${e.message}", null)
        }
        if (records.isEmpty()) return result.success(0)
        scope.launch {
            try {
                client().insertRecords(records)
                result.success(records.size)
            } catch (e: SecurityException) {
                result.error("permission", "Health Connect access was not granted", null)
            } catch (e: Exception) {
                result.error("write", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun toRecord(r: Map<String, Any>): Record? {
        val zone = ZoneId.systemDefault()
        val start = Instant.ofEpochMilli((r["start"] as Number).toLong())
        val end = Instant.ofEpochMilli((r["end"] as Number).toLong())
        val so = zone.rules.getOffset(start)
        val eo = zone.rules.getOffset(end)
        val value = (r["value"] as? Number)?.toDouble() ?: 0.0
        val meta = Metadata.autoRecorded(
            device = Device(type = Device.TYPE_WATCH),
            clientRecordId = r["id"] as String,
            clientRecordVersion = (r["version"] as Number).toLong(),
        )
        return when (r["kind"]) {
            "steps" -> StepsRecord(start, so, end, eo, value.toLong(), meta)
            "activeKcal" -> ActiveCaloriesBurnedRecord(
                start, so, end, eo, Energy.kilocalories(value), meta,
            )
            "totalKcal" -> TotalCaloriesBurnedRecord(
                start, so, end, eo, Energy.kilocalories(value), meta,
            )
            "spo2" -> OxygenSaturationRecord(start, so, Percentage(value), meta)
            "restingHr" -> RestingHeartRateRecord(start, so, value.toLong(), meta)
            "sleep" -> {
                @Suppress("UNCHECKED_CAST")
                val stages = (r["stages"] as? List<List<Any>> ?: emptyList()).mapNotNull {
                    val type = STAGES[it[2] as String] ?: return@mapNotNull null
                    SleepSessionRecord.Stage(
                        Instant.ofEpochMilli((it[0] as Number).toLong()),
                        Instant.ofEpochMilli((it[1] as Number).toLong()),
                        type,
                    )
                }
                SleepSessionRecord(
                    startTime = start, startZoneOffset = so,
                    endTime = end, endZoneOffset = eo,
                    metadata = meta, title = r["title"] as? String, stages = stages,
                )
            }
            else -> null
        }
    }

    /** Opens OpenWear's page in Health Connect, or Health Connect itself. */
    private fun openSettings(result: MethodChannel.Result) {
        val own = Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
            .putExtra(Intent.EXTRA_PACKAGE_NAME, context.packageName)
        val general = Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
        for (intent in listOf(own, general)) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return result.success(true)
            } catch (e: Exception) {
                // Try the next one.
            }
        }
        result.success(false)
    }

    private fun client() = HealthConnectClient.getOrCreate(context)

    fun dispose() = scope.cancel()
}
