package dev.devicereadout.android

import android.app.Activity
import android.app.ActivityManager
import android.app.Instrumentation
import android.os.Build
import android.os.Bundle
import android.os.BatteryManager
import android.os.PowerManager
import android.content.Intent
import android.content.IntentFilter
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/** Runs inside a project-owned emulator; assertion failures set an explicit failed result. */
class ContractInstrumentation : Instrumentation() {
    private var mode: String? = null
    override fun onCreate(arguments: Bundle?) {super.onCreate(arguments);mode = arguments?.getString("mode");start()}
    override fun onStart() {
        val results = Bundle()
        results.putInt("targetSdk", targetContext.applicationInfo.targetSdkVersion)
        var foreground: Activity? = null
        try {
            if (mode != "sensorLifecycle" && mode != "permissionState") foreground = startActivitySync(Intent(targetContext, ObserverTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            runBlocking {
                if (mode == "permissionState") {
                    for (permission in listOf(android.Manifest.permission.ACCESS_COARSE_LOCATION, android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.READ_PHONE_STATE)) {
                        results.putBoolean(permission, targetContext.checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED)
                    }
                    return@runBlocking
                }
                if (mode == "batteryEvents") {verifyBatteryEvents(results);return@runBlocking}
                if (mode == "sensorUnits") {verifySensorUnits(results);return@runBlocking}
                if (mode == "sensorAvailability") {SensorAvailabilityContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "identityContracts") {IdentityContracts.reads(targetContext, results, granted = true);return@runBlocking}
                if (mode == "identityDenied") {IdentityContracts.reads(targetContext, results, granted = false);return@runBlocking}
                if (mode == "hingeContracts") {
                    HingeContracts.readsAndEvents(targetContext, results) {stage ->
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", stage)})
                    }
                    return@runBlocking
                }
                if (mode == "sensorLifecycle") {verifySensorLifecycle(results);return@runBlocking}
                if (mode == "orientationFrame") {verifyOrientationFrame(results);return@runBlocking}
                if (mode == "regionalContracts") {RegionalContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "localeEvents") {RegionalContracts.localeEvents(targetContext, results);return@runBlocking}
                if (mode == "networkContracts") {NetworkContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "cpuContracts") {CpuContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "storageContracts") {StorageContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "wifiContracts") {WifiContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "wifiEvents") {
                    WifiContracts.events(targetContext, results) {stage ->
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", stage)})
                    }
                    return@runBlocking
                }
                if (mode == "wifiRestore") {
                    check(Build.VERSION.SDK_INT < 29)
                    @Suppress("DEPRECATION")
                    check(targetContext.getSystemService(android.net.wifi.WifiManager::class.java).setWifiEnabled(true))
                    return@runBlocking
                }
                if (mode == "wifiAuthorized") {
                    WifiContracts.reads(targetContext, results)
                    check(results.getBoolean("wifiSsidVisible") && results.getBoolean("wifiBssidVisible"))
                    return@runBlocking
                }
                if (mode == "cellularContracts") {CellularContracts.reads(targetContext, results);return@runBlocking}
                if (mode == "cellularDenied") {CellularContracts.denied(targetContext, results);return@runBlocking}
                if (mode == "cellularRestricted") {CellularContracts.denied(targetContext, results, runtimePermissionGranted = true);return@runBlocking}
                if (mode == "cellularEvents") {
                    CellularContracts.events(targetContext, results) {stage ->
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", stage)})
                    }
                    return@runBlocking
                }
                if (mode == "storageHotplug") {
                    StorageContracts.hotplug(targetContext, results) {stage ->
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", stage)})
                    }
                    return@runBlocking
                }
                if (mode == "interfaceHotplug") {NetworkContracts.interfaceHotplug(targetContext, results);return@runBlocking}
                if (mode == "networkEvents") {
                    NetworkContracts.events(targetContext, results) {
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", "networkEvents")})
                    }
                    return@runBlocking
                }
                if (mode == "timeZoneEvents") {
                    RegionalContracts.timeZoneEvents(targetContext, results) {
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", "timeZoneEvents")})
                    }
                    return@runBlocking
                }
                AndroidDeviceAccess.create(targetContext).use { access ->
                    val memory = access.get(RamEntity)
                    val native = ActivityManager.MemoryInfo().also {targetContext.getSystemService(ActivityManager::class.java).getMemoryInfo(it)}
                    check(memory.kernelAccessibleBytes == native.totalMem.toULong()) {"RAM kernel total does not match Android."}
                    check(memory.physicalBytes == null) {"Kernel-accessible memory must not be labeled physical memory."}
                    check(memory.availableBytes != null && memory.availableBytes!! <= memory.kernelAccessibleBytes!!) {"Available memory is missing or invalid."}
                    check(memory.lowMemory != null && memory.lowMemoryThresholdBytes == native.threshold.toULong())
                    if (Build.VERSION.SDK_INT >= 34) check(memory.advertisedBytes == native.advertisedMem.toULong())
                    else check(memory.advertisedBytes == null)
                    check(memory.collectedAt.toEpochMilli() > 0)
                    results.putString("ram", serializeSnapshot(memory))

                    val os = access.get(OsEntity)
                    check(os.family == OsFamily.Android && os.name == "Android" && os.version == Build.VERSION.RELEASE)
                    check(os.kernelName == "Linux" && !os.kernelVersion.isNullOrBlank())
                    val build = access.get(AndroidBuildEntity)
                    check(build.apiLevel == Build.VERSION.SDK_INT && build.buildFingerprint == Build.FINGERPRINT)
                    val device = access.get(DeviceInfoEntity)
                    if (Build.MODEL == Build.UNKNOWN) check(device.modelName == null) else check(device.modelName == Build.MODEL)
                    if (Build.MANUFACTURER == Build.UNKNOWN) check(device.manufacturer == null) else check(device.manufacturer == Build.MANUFACTURER)
                    val runtime = access.get(RuntimeEntity)
                    check(runtime.hostArchitecture == Architecture.X64) {"This dedicated emulator uses an x86_64 system image."}
                    check(runtime.processArchitecture == Architecture.X64 && runtime.processBitness == 64)
                    check(runtime.supportedAbis?.contains(Abi.X86_64) == true)
                    val cpu = access.get(CpuEntity)
                    check(cpu.availableLogicalProcessorCount != null && cpu.availableLogicalProcessorCount!! > 0)
                    check(cpu.logicalProcessorCount != null && cpu.logicalProcessorCount!! >= cpu.availableLogicalProcessorCount!!)
                    results.putString("os", serializeSnapshot(os))
                    results.putString("runtime", serializeSnapshot(runtime))

                    val identity = access.get(AndroidIdentityEntity)
                    check(!identity.androidId.isNullOrBlank())
                    check(identity.androidId == access.get(AndroidIdentityEntity).androidId)
                    // Keep actual identifiers out of the test report.
                    results.putBoolean("scopedAndroidIdentityRead", true)

                    val power = access.get(PowerEntity)
                    check(power.powerSaveMode == targetContext.getSystemService(PowerManager::class.java).isPowerSaveMode)
                    check(if (Build.VERSION.SDK_INT >= 29) power.thermalState is AndroidThermalState else power.thermalState == null)
                    val battery = access.batteries.current() ?: error("The emulator has an aggregate battery.")
                    check(access.batteries.list().size == 1)
                    val charge = access.get(battery)
                    val batteryIntent = targetContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))!!
                    check(charge.present == batteryIntent.getBooleanExtra(BatteryManager.EXTRA_PRESENT, false))
                    check(charge.level != null && charge.level!! in 0.0..1.0)
                    check(charge.state != null && charge.charging != null)
                    results.putString("power", serializeSnapshot(power))
                    results.putString("battery", serializeSnapshot(charge))

                    val acceleration = access.sensors.list(AccelerometerEntity).firstOrNull() ?: error("The emulator provides an accelerometer.")
                    val description = access.describe(acceleration)
                    check(description.kind == SensorKind.Accelerometer && !description.name.isNullOrBlank())
                    check(description.reportingMode == SensorReportingMode.Continuous)
                    val sample = access.get(acceleration)
                    check(sample.value != null)
                    val samples = withTimeout(3000) {access.withSensorSamplingRate(30.hertz).watch(acceleration).take(3).toList()}
                    check(samples.all {it.value != null})
                    results.putString("accelerometer", serializeSnapshot(sample))
                    results.putString("accelerometerDescription", serializeSnapshot(description))

                    // The application supplies display state. SDK creation/reads must not obtain a Window.
                    val screen = access.observers.target(DisplayEntity, "test-window")
                    access.observers.publish(screen, DisplaySnapshot(pixelSize = Size(800, 600)))
                    access.observers.current(DisplayEntity, screen)
                    check(access.get(access.displays.current()!!).pixelSize == Size(800, 600))
                }
                withContext(Dispatchers.Main) {
                    var ticks = 0
                    val heartbeat = launch {while (isActive) {ticks++;delay(5)}}
                    try {
                        DeviceAccess(object : DeviceCollector {
                            override fun read(entity: EntityAddress): DeviceSnapshot {
                                val until = System.nanoTime() + 500_000_000
                                while (System.nanoTime() < until) { /* Deliberately ignore cancellation. */ }
                                return RamSnapshot()
                            }
                        }).use { access ->
                            val start = System.nanoTime()
                            val error = runCatching {access.withReadTimeout(100.milliseconds).get(RamEntity)}.exceptionOrNull()
                            check(error is DeviceReadoutException && error.code == ErrorCode.ReadTimeout)
                            check((System.nanoTime() - start) < 450_000_000) {"UI coroutine timeout was blocked by collection."}
                            check(ticks >= 3) {"The main Looper did not remain responsive."}
                            results.putInt("mainLooperTicks", ticks)
                        }
                    } finally {heartbeat.cancelAndJoin()}
                }
            }
            results.putString("deviceReadoutStatus", "passed")
            results.putInt("apiLevel", Build.VERSION.SDK_INT)
            runOnMainSync {foreground?.finish()};foreground = null
            finish(Activity.RESULT_OK, results)
        } catch (error: Throwable) {
            results.putString("deviceReadoutStatus", "failed")
            results.putString("failure", error.stackTraceToString())
            runOnMainSync {foreground?.finish()}
            finish(Activity.RESULT_CANCELED, results)
        }
    }
    private suspend fun verifyBatteryEvents(results: Bundle) = coroutineScope {
        AndroidDeviceAccess.create(targetContext).use { access ->
            val battery = access.batteries.current() ?: error("Expected an aggregate battery.")
            check(access.get(battery).level == 0.4)
            val observed = access.withPollInterval(30.seconds)
            val batteryReady = CompletableDeferred<Unit>()
            val powerReady = CompletableDeferred<Unit>()
            val thermalReady = CompletableDeferred<Unit>()
            val charge = async {observed.watch(battery).onEach {batteryReady.complete(Unit)}.first {it.level == 0.7}}
            val power = async {observed.watch(PowerEntity).onEach {powerReady.complete(Unit)}.first {it.powerSource == PowerSource.Battery}}
            val thermal = if (Build.VERSION.SDK_INT >= 29) async {observed.watch(PowerEntity).onEach {thermalReady.complete(Unit)}.first {it.thermalState == AndroidThermalState.Severe}} else null
            withTimeout(5000) {
                batteryReady.await();powerReady.await()
                if (thermal != null) thermalReady.await()
                sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", "batteryEvents")})
                check(charge.await().level == 0.7)
                check(power.await().powerSource == PowerSource.Battery)
                if (thermal != null) check(thermal.await().thermalState == AndroidThermalState.Severe)
            }
            results.putBoolean("batteryAndPowerNativeEvents", true)
            if (thermal != null) results.putBoolean("androidThermalNativeEvent", true)
        }
    }
    private suspend fun verifySensorUnits(results: Bundle) {
        AndroidDeviceAccess.create(targetContext).use { access ->
            suspend fun <S : DeviceSnapshot> read(kind: Entity<S>): S = access.get(access.sensors.list(kind).firstOrNull() ?: error("Missing emulator sensor ${kind.kind}."))
            fun near(actual: Double?, expected: Double) {check(actual != null && kotlin.math.abs(actual - expected) < 0.01) {"Expected $expected, received $actual."}}
            val acceleration = read(AccelerometerEntity).value!!
            near(acceleration.x, 1.0);near(acceleration.y, 2.0);near(acceleration.z, 9.0)
            val gyro = read(GyroscopeEntity).value!!
            near(gyro.x, 0.1);near(gyro.y, 0.2);near(gyro.z, 0.3)
            val magnetic = read(MagnetometerEntity).value!!
            near(magnetic.x, 10.0);near(magnetic.y, 20.0);near(magnetic.z, 30.0)
            near(read(PressureEntity).value, 101325.0)
            near(read(RelativeHumidityEntity).value, 0.5)
            val temperature = access.sensors.list(AmbientTemperatureEntity).first()
            val initialTemperature = access.get(temperature).value
            check(initialTemperature == null || initialTemperature >= -273.15)
            if (initialTemperature == null) {
                val measuredTemperature = withTimeout(5000) {
                    access.watch(temperature).onEach {
                        sendStatus(1, Bundle().apply {putString("deviceReadoutAwaiting", "temperatureSample")})
                    }.first {it.value == 24.0}
                }
                near(measuredTemperature.value, 24.0)
                results.putBoolean("invalidTemperatureThenValidEvent", true)
            } else near(initialTemperature, 24.0)
            near(read(IlluminanceEntity).value, 123.0)
            near(read(ProximityDistanceEntity).value, 0.005)
            check(read(ProximityNearEntity).value == true)
            check(read(GravityEntity).value != null && read(LinearAccelerationEntity).value != null)
            for (rotation in listOf(read(AbsoluteOrientationEntity).value, read(RelativeOrientationEntity).value)) {
                check(rotation != null)
                near(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z + rotation.w * rotation.w, 1.0)
            }
            val pressure = access.sensors.list(PressureEntity).first()
            check(access.describe(pressure).maximumRange!! > 10000.0) {"Pressure metadata must use Pa too."}
            results.putBoolean("sensorUnitsAndCoordinates", true)
        }
    }
    private suspend fun verifySensorLifecycle(results: Bundle) = coroutineScope {
        AndroidDeviceAccess.create(targetContext).use { access ->
            access.observers.sensorActivity(false)
            val activityEvents = kotlinx.coroutines.channels.Channel<Boolean>(8)
            ObserverTestActivity.observeActivity = {active -> access.observers.sensorActivity(active);activityEvents.trySend(active)}
            val foreground = startActivitySync(Intent(targetContext, ObserverTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            var stream: Job? = null
            try {
                withTimeout(5000) {check(activityEvents.receive())}
                val sensor = access.sensors.list(AccelerometerEntity).first()
                var received = 0
                val first = CompletableDeferred<Unit>()
                stream = launch {
                    access.withReadTimeout(300.milliseconds).watch(sensor).collect {
                        check(it.value != null);received++;first.complete(Unit)
                    }
                }
                withTimeout(3000) {first.await()}
                runOnMainSync {check(foreground.moveTaskToBack(true))}
                withTimeout(5000) {check(!activityEvents.receive())}
                delay(100)
                val pausedCount = received
                delay(600)
                check(received == pausedCount) {"Sensor snapshots arrived after the application's pause observer."}
                runOnMainSync {targetContext.startActivity(Intent(targetContext, ObserverTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))}
                withTimeout(5000) {check(activityEvents.receive())}
                withTimeout(3000) {while (received == pausedCount) delay(10)}
                stream.cancelAndJoin();stream = null
                access.get(RamEntity)
                results.putBoolean("realActivitySensorPauseResume", true)
            } finally {
                stream?.cancelAndJoin()
                runOnMainSync {ObserverTestActivity.observeActivity = null;foreground.finish()}
                activityEvents.cancel()
            }
        }
    }
    private suspend fun verifyOrientationFrame(results: Bundle) {
        AndroidDeviceAccess.create(targetContext).use { access ->
            val orientations = access.sensors.list(AbsoluteOrientationEntity)
            check(orientations.isNotEmpty())
            for (sensor in orientations) {
                val values = withTimeout(6000) {access.withSensorSamplingRate(30.hertz).watch(sensor).take(10).toList()}
                val q = values.last().value ?: error("Expected an absolute rotation quaternion.")
                // Fixture: device Z points up and device X points to magnetic north.
                // Applying q to device +X must produce reference +Y (north), not -Y.
                val worldX = 1 - 2 * (q.y * q.y + q.z * q.z)
                val worldY = 2 * (q.x * q.y + q.w * q.z)
                val worldZ = 2 * (q.x * q.z - q.w * q.y)
                check(kotlin.math.abs(worldX) < 0.08 && kotlin.math.abs(worldY - 1) < 0.08 && kotlin.math.abs(worldZ) < 0.08) {
                    "Device-to-reference direction mismatch: [$worldX, $worldY, $worldZ]."
                }
            }
            results.putInt("absoluteOrientationTargetsVerified", orientations.size)
        }
    }
}
