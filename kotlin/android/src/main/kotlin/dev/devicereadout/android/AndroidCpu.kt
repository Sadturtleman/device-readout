package dev.devicereadout.android

import android.os.Build
import android.system.Os
import android.system.OsConstants
import dev.devicereadout.*
import java.io.File

/** Linux exposes topology through read-only sysfs. CPU online/offline is not target removal. */
internal class AndroidCpu {
    private data class Key(val index: Int, val device: Long, val inode: Long)
    private data class Target(val id: String, val key: Key, var removed: Boolean = false)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val byKey = HashMap<Key, Target>()
    private var sequence = 0L
    private val root = File("/sys/devices/system/cpu")

    private fun inventory(): List<Target> = synchronized(gate) {
        val indices = cpuList(File(root, "present").readText())
        val keys = indices.sorted().map {index ->
            val stat = Os.stat(File(root, "cpu$index").path)
            Key(index, stat.st_dev, stat.st_ino)
        }
        targets.values.filter {it.key !in keys}.forEach {it.removed = true}
        keys.map {key ->
            byKey[key]?.takeUnless {it.removed} ?: Target("cpu-${++sequence}", key).also {targets[it.id] = it;byKey[key] = it}
        }
    }
    fun list(): List<String> = inventory().map {it.id}
    fun read(id: String?): CpuCoreSnapshot {
        inventory()
        val target = synchronized(gate) {targets[id]?.takeUnless {it.removed}}
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The CPU target was removed.")
        return readCore(target.key.index)
    }
    private fun readCore(index: Int): CpuCoreSnapshot {
        val directory = File(root, "cpu$index")
        return CpuCoreSnapshot(
            logicalIndex = index,
            coreIndex = integer(File(directory, "topology/core_id")),
            packageIndex = integer(File(directory, "topology/physical_package_id")),
            online = optional {index in cpuList(File(root, "online").readText())},
            currentClockHz = frequency(File(directory, "cpufreq/cpuinfo_cur_freq")) ?: frequency(File(directory, "cpufreq/scaling_cur_freq")),
            maximumClockHz = frequency(File(directory, "cpufreq/cpuinfo_max_freq")),
        )
    }
    fun summary(): CpuSnapshot {
        val indices = optional {cpuList(File(root, "present").readText())}
        val topology = indices?.map {index ->
            val core = readCore(index)
            if (core.packageIndex == null || core.coreIndex == null) null
            else Triple(core.packageIndex, integer(File(root, "cpu$index/topology/die_id")), core.coreIndex)
        }?.takeIf {it.isNotEmpty() && it.all {entry -> entry != null}}?.filterNotNull()
        val info = optional {File("/proc/cpuinfo").useLines {lines ->
            lines.mapNotNull {line ->
                val separator = line.indexOf(':')
                if (separator < 0) null else line.substring(0, separator).trim() to line.substring(separator + 1).trim()
            }.filter {it.first == "model name" || it.first == "vendor_id"}.toList()
        }}
        fun uniform(key: String): String? = info?.filter {it.first == key}?.map {it.second}?.distinct()?.singleOrNull()?.takeIf {it.isNotBlank()}
        return CpuSnapshot(
            model = uniform("model name"), manufacturer = uniform("vendor_id"),
            socModel = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL.takeUnless {it == Build.UNKNOWN || it.isBlank()} else null,
            socManufacturer = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MANUFACTURER.takeUnless {it == Build.UNKNOWN || it.isBlank()} else null,
            logicalProcessorCount = optional {Os.sysconf(OsConstants._SC_NPROCESSORS_CONF).takeIf {it in 1..Int.MAX_VALUE.toLong()}?.toInt()},
            availableLogicalProcessorCount = Runtime.getRuntime().availableProcessors().takeIf {it > 0},
            physicalCoreCount = topology?.distinct()?.size,
            processorPackageCount = topology?.map {it.first}?.distinct()?.size,
        )
    }
    private fun integer(file: File): Int? = optional {file.readText().trim().toIntOrNull()?.takeIf {it >= 0}}
    private fun frequency(file: File): Double? = optional {file.readText().trim().toDoubleOrNull()?.takeIf {it.isFinite() && it >= 0}?.times(1000)}
}

private fun cpuList(text: String): Set<Int> {
    val indices = LinkedHashSet<Int>()
    for (part in text.trim().split(',')) {
        val bounds = part.split('-').map {it.toIntOrNull() ?: throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid native CPU list.")}
        val first = bounds.first()
        val last = bounds.last()
        if (bounds.size !in 1..2 || first < 0 || last < first || last.toLong() - first >= 65536 || indices.size.toLong() + last - first + 1 > 65536)
            throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid or excessive native CPU list.")
        indices.addAll(first..last)
    }
    return indices
}
private inline fun <T> optional(read: () -> T): T? = try {read()} catch (_: Exception) {null}
