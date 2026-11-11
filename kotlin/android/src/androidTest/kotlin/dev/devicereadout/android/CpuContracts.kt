package dev.devicereadout.android

import android.content.Context
import android.os.Bundle
import dev.devicereadout.*
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlin.time.Duration.Companion.milliseconds

internal object CpuContracts {
    suspend fun reads(context: Context, results: Bundle) {
        AndroidDeviceAccess.create(context).use {access ->
            val targets = access.cpuCores.list()
            // Both dedicated AVD configurations explicitly have hw.cpu.ncore=2.
            check(targets.size == 2) {"Expected two configured virtual CPUs, found ${targets.size}."}
            val values = targets.map {access.get(it)}
            check(values.map {it.logicalIndex}.toSet() == setOf(0, 1))
            check(values.all {it.online == true})
            check(access.cpuCores.current() == null) {"A multithreaded process has no single current core target."}
            val cpu = access.get(CpuEntity)
            check(cpu.logicalProcessorCount == 2)
            check(cpu.physicalCoreCount == null || cpu.physicalCoreCount!! in 1..2)
            check(cpu.processorPackageCount == null || cpu.processorPackageCount!! in 1..2)
            val first = targets.first()
            val pair = withTimeout(3000) {access.withPollInterval(30.milliseconds).watch(first).take(2).toList()}
            check(pair[0].logicalIndex == pair[1].logicalIndex)
            check(pair[0].collectedAt <= pair[1].collectedAt)
            results.putInt("logicalCpuTargets", targets.size)
            results.putString("firstCpuCore", serializeSnapshot(values.first()))
            results.putString("cpuTopology", serializeSnapshot(cpu))
            results.putBoolean("cpuCorePollingAndTypedTargets", true)
        }
    }
}
