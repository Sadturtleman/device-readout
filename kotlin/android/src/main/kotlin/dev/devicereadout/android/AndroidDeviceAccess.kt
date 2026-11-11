package dev.devicereadout.android

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.system.Os
import android.system.OsConstants
import dev.devicereadout.*
import java.io.DataInputStream
import java.io.FileInputStream

/** Construction is inert. Collection runs on DeviceAccess's dedicated execution lane. */
object AndroidDeviceAccess {
    fun create(context: Context): DeviceAccess = DeviceAccess(AndroidCollector(context.applicationContext))
}

private class AndroidCollector(private val context: Context) : DeviceCollector {
    private val power = AndroidPower(context)
    private val sensors = AndroidSensors(context)
    private val regional = AndroidRegional(context)
    private val network = AndroidNetwork(context)
    private val interfaces = AndroidNetworkInterfaces(context)
    private val cpu = AndroidCpu()
    private val storage = AndroidStorage(context)
    private val wifi = AndroidWifi(context)
    private val cellular = AndroidCellular(context)
    private val telephonyIdentity = AndroidTelephonyIdentity(context)
    override fun read(entity: EntityAddress): DeviceSnapshot = when (entity.kind) {
        EntityKind.Ram -> readRam()
        EntityKind.DeviceInfo -> readDeviceInfo()
        EntityKind.Os -> readOs()
        EntityKind.Runtime -> readRuntime()
        EntityKind.Cpu -> cpu.summary()
        EntityKind.CpuCore -> cpu.read(entity.targetId)
        EntityKind.StorageVolume -> storage.read(entity.targetId)
        EntityKind.WifiConnection -> wifi.read(entity.targetId)
        EntityKind.CellularSubscription -> cellular.read(entity.targetId)
        EntityKind.AndroidBuild -> readBuild()
        EntityKind.AndroidIdentity -> readIdentity()
        EntityKind.HardwareSerial -> readHardwareSerial()
        EntityKind.TelephonyIdentity -> telephonyIdentity.read(entity.targetId)
        EntityKind.Power -> power.readPower()
        EntityKind.Battery -> power.readBattery(entity.targetId)
        EntityKind.Locale -> regional.readLocale()
        EntityKind.TimeZone -> regional.readTimeZone()
        EntityKind.NetworkPath, EntityKind.NetworkPerformance -> network.read(entity.kind)
        EntityKind.NetworkInterface -> interfaces.read(entity.targetId)
        else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "This Android entity has no collector yet.")
    }
    override fun capabilities(entity: EntityAddress): EntityCapabilities {
        if (sensors.supportsKind(entity.kind)) return sensors.capabilities(entity)
        if (entity.kind == EntityKind.TelephonyIdentity) return telephonyIdentity.capabilities(entity.targetId)
        val supported = entity.kind in setOf(EntityKind.Ram, EntityKind.DeviceInfo, EntityKind.Os, EntityKind.Runtime, EntityKind.Cpu, EntityKind.CpuCore, EntityKind.StorageVolume, EntityKind.WifiConnection, EntityKind.CellularSubscription, EntityKind.AndroidBuild, EntityKind.AndroidIdentity, EntityKind.HardwareSerial, EntityKind.Power, EntityKind.Battery, EntityKind.Locale, EntityKind.TimeZone, EntityKind.NetworkPath, EntityKind.NetworkPerformance, EntityKind.NetworkInterface)
        return EntityCapabilities(supported, supported)
    }
    override fun list(kind: EntityKind): List<String> = when (kind) {
        EntityKind.Battery -> power.listBatteries()
        EntityKind.NetworkInterface -> interfaces.list()
        EntityKind.CpuCore -> cpu.list()
        EntityKind.StorageVolume -> storage.list()
        EntityKind.WifiConnection -> wifi.list()
        EntityKind.CellularSubscription -> cellular.list()
        EntityKind.TelephonyIdentity -> telephonyIdentity.list()
        else -> if (sensors.supportsKind(kind)) sensors.list(kind) else super.list(kind)
    }
    override fun current(kind: EntityKind): String? = when (kind) {
        EntityKind.Battery -> power.currentBattery()
        EntityKind.NetworkInterface -> interfaces.current()
        EntityKind.StorageVolume -> storage.current()
        EntityKind.WifiConnection -> wifi.current()
        EntityKind.CellularSubscription -> cellular.current()
        else -> null
    }
    override fun describe(sensor: EntityAddress): SensorDescription = sensors.describe(sensor)
    override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription =
        sensors.observeInventory(changed, fail)
    override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? =
        if (sensors.supportsKind(entity.kind)) sensors.observe(entity, rate, emit, fail) else null
    override fun observeReads(entity: EntityAddress, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? = when (entity.kind) {
        EntityKind.Power, EntityKind.Battery -> power.observeChanges(entity, {emit {read(entity)}}, fail)
        EntityKind.Locale, EntityKind.TimeZone -> regional.observeChanges(entity.kind, {emit {read(entity)}}, fail)
        EntityKind.NetworkInterface -> interfaces.observeChanges(entity.targetId, {emit {read(entity)}}, fail)
        EntityKind.StorageVolume -> storage.observeChanges(entity.targetId, {emit {read(entity)}}, fail)
        EntityKind.WifiConnection -> wifi.observeReads(entity.targetId, emit, fail)
        EntityKind.CellularSubscription -> cellular.observeReads(entity.targetId, emit, fail)
        EntityKind.TelephonyIdentity -> telephonyIdentity.observeReads(entity.targetId, emit, fail)
        EntityKind.NetworkPath, EntityKind.NetworkPerformance -> network.observeReads(entity.kind, emit, fail)
        else -> null
    }
    private fun readRam(): RamSnapshot {
        val service = context.getSystemService(ActivityManager::class.java)
            ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "ActivityManager is unavailable.")
        val info = ActivityManager.MemoryInfo().also(service::getMemoryInfo)
        return RamSnapshot(
            kernelAccessibleBytes = info.totalMem.nonnegativeBytes(),
            advertisedBytes = if (Build.VERSION.SDK_INT >= 34) info.advertisedMem.nonnegativeBytes() else null,
            availableBytes = info.availMem.nonnegativeBytes(),
            lowMemory = info.lowMemory,
            lowMemoryThresholdBytes = info.threshold.nonnegativeBytes(),
        )
    }
    private fun readDeviceInfo(): DeviceInfoSnapshot = DeviceInfoSnapshot(
        manufacturer = Build.MANUFACTURER.knownBuildValue(),
        brand = Build.BRAND.knownBuildValue(),
        modelCode = Build.DEVICE.knownBuildValue(),
        modelName = Build.MODEL.knownBuildValue(),
        deviceName = optional {Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)},
        formFactor = optional {
            val pm = context.packageManager
            listOf(
                PackageManager.FEATURE_WATCH to FormFactor.Watch,
                PackageManager.FEATURE_AUTOMOTIVE to FormFactor.Automotive,
                PackageManager.FEATURE_LEANBACK to FormFactor.Television,
            ).filter {pm.hasSystemFeature(it.first)}.singleOrNull()?.second
        },
        product = Build.PRODUCT.knownBuildValue(),
        board = Build.BOARD.knownBuildValue(),
    )
    private fun readOs(): OsSnapshot {
        val kernel = optional {Os.uname()}
        return OsSnapshot(family = OsFamily.Android, name = "Android", version = Build.VERSION.RELEASE.knownBuildValue(),
            build = Build.ID.knownBuildValue(), kernelName = kernel?.sysname, kernelVersion = kernel?.release)
    }
    private fun readRuntime(): RuntimeSnapshot {
        val abiValues = Build.SUPPORTED_ABIS.map {when (it) {
            "armeabi-v7a" -> Abi.ArmeabiV7a; "arm64-v8a" -> Abi.Arm64V8a
            "x86" -> Abi.X86; "x86_64" -> Abi.X86_64; else -> null
        }}
        return RuntimeSnapshot(
            hostArchitecture = optional {architecture(Os.uname().machine)},
            processArchitecture = optional {processArchitecture()},
            processBitness = if (android.os.Process.is64Bit()) 64 else 32,
            supportedAbis = if (abiValues.any {it == null}) null else abiValues.filterNotNull().toSet(),
        )
    }
    private fun readBuild(): AndroidBuildSnapshot = AndroidBuildSnapshot(
        apiLevel = Build.VERSION.SDK_INT,
        securityPatch = Build.VERSION.SECURITY_PATCH.knownBuildValue(),
        buildId = Build.ID.knownBuildValue(),
        buildDisplay = Build.DISPLAY.knownBuildValue(),
        buildFingerprint = Build.FINGERPRINT.knownBuildValue(),
        buildType = Build.TYPE.knownBuildValue(),
        buildTags = Build.TAGS.knownBuildValue()?.split(',')?.map(String::trim),
        bootloaderVersion = Build.BOOTLOADER.knownBuildValue(),
    )
    // This explicitly requested entity exposes the OS identifier; the SDK neither stores nor sends it.
    @SuppressLint("HardwareIds")
    private fun readIdentity() = AndroidIdentitySnapshot(androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID))
    // Android enforces privileged/owner/carrier/role access itself; denial propagates as PermissionDenied.
    @SuppressLint("HardwareIds", "MissingPermission")
    private fun readHardwareSerial() = HardwareSerialSnapshot(serial = Build.getSerial().takeUnless {it.isNullOrBlank() || it == Build.UNKNOWN})
}

private fun Long.nonnegativeBytes(): ULong? = takeIf {it >= 0}?.toULong()
private fun String?.knownBuildValue(): String? = takeUnless {it.isNullOrEmpty() || it == Build.UNKNOWN}
private inline fun <T> optional(read: () -> T): T? = try {read()} catch (_: Exception) {null}
private fun architecture(machine: String): Architecture? = when (machine) {
    "x86_64", "amd64" -> Architecture.X64
    "i386", "i486", "i586", "i686", "x86" -> Architecture.X86
    "aarch64", "arm64" -> Architecture.Arm64
    "arm", "armv7l", "armv8l" -> Architecture.Arm32
    "riscv32" -> Architecture.RiscV32
    "riscv64" -> Architecture.RiscV64
    else -> null
}
/** Read the running executable's ELF machine; supported ABI order is not a process architecture. */
private fun processArchitecture(): Architecture? {
    val header = ByteArray(20)
    DataInputStream(FileInputStream("/proc/self/exe")).use {it.readFully(header)}
    if (header[0] != 0x7f.toByte() || header[1] != 'E'.code.toByte() || header[2] != 'L'.code.toByte() || header[3] != 'F'.code.toByte()) return null
    val first = header[18].toInt() and 0xff; val second = header[19].toInt() and 0xff
    val machine = when (header[5].toInt()) {1 -> first or (second shl 8);2 -> (first shl 8) or second;else -> return null}
    val elfClass = header[4].toInt()
    return when {
        machine == 3 && elfClass == 1 -> Architecture.X86
        machine == 62 && elfClass == 2 -> Architecture.X64
        machine == 40 && elfClass == 1 -> Architecture.Arm32
        machine == 183 && elfClass == 2 -> Architecture.Arm64
        machine == 243 && elfClass == 1 -> Architecture.RiscV32
        machine == 243 && elfClass == 2 -> Architecture.RiscV64
        else -> null
    }
}
