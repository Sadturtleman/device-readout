package dev.devicereadout.android

import android.content.Context
import android.os.Bundle
import android.os.StatFs
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

internal object StorageContracts {
    suspend fun reads(context: Context, results: Bundle) {
        AndroidDeviceAccess.create(context).use {access ->
            val current = access.storageVolumes.current() ?: error("The app's private data volume must have a current target.")
            val native = StatFs(context.applicationInfo.dataDir)
            val value = access.get(current)
            check(value.totalBytes == native.totalBytes.toULong())
            check(value.freeBytes != null && value.availableToCallerBytes != null)
            check(value.availableToCallerBytes!! <= value.freeBytes!! && value.freeBytes!! <= value.totalBytes!!)
            check(value.readOnly == false)
            check(value.totalBytesForCaller == null) {"Filesystem total is not an app quota."}
            check(value.availableForImportantUsageBytes == null && value.availableForOpportunisticUsageBytes == null)
            check(value.allocatableBytes != null)
            val targets = access.storageVolumes.list()
            check(targets.size >= 2) {"The project AVD exposes private data and primary shared storage views."}
            for (target in targets) {
                val snapshot = access.get(target)
                check(snapshot.totalBytes == null || snapshot.totalBytes!! > 0uL)
            }
            val pair = withTimeout(5000) {access.withPollInterval(50.milliseconds).watch(current).take(2).toList()}
            check(pair[0].totalBytes == pair[1].totalBytes)
            results.putInt("storageVolumeTargets", targets.size)
            results.putString("appStorage", serializeSnapshot(value))
            results.putBoolean("storageCurrentAndPolling", true)
        }
    }
    suspend fun hotplug(context: Context, results: Bundle, ready: (String) -> Unit) {
        AndroidDeviceAccess.create(context).use {access ->
            suspend fun removable(): Entity<StorageVolumeSnapshot> = withTimeout(10000) {
                var target: Entity<StorageVolumeSnapshot>? = null
                while (target == null) {
                    target = access.storageVolumes.list().singleOrNull {access.get(it).removable == true}
                    if (target == null) delay(50)
                }
                target
            }
            val original = removable()
            val initial = access.get(original)
            check(initial.readOnly == false)
            results.putString("removableStorage", serializeSnapshot(initial))
            var signalled = false
            val error = withTimeout(10000) {
                runCatching {
                    access.withPollInterval(30.seconds).watch(original).onEach {
                        if (!signalled) {signalled = true;ready("storageUnmount")}
                    }.collect {}
                }.exceptionOrNull()
            }
            check(error is DeviceReadoutException && error.code == ErrorCode.EntityRemoved) {"Volume removal must terminate the original watch: $error"}
            val appVolume = access.storageVolumes.current() ?: error("Unmounting the fixture must not remove private app storage.")
            check(access.get(appVolume).totalBytes != null)
            ready("storageRemount")
            val replacement = removable()
            check(access.get(replacement).readOnly == false)
            val oldError = runCatching {access.get(original)}.exceptionOrNull()
            check(oldError is DeviceReadoutException && oldError.code == ErrorCode.EntityRemoved)
            results.putBoolean("storageNativeRemovalAndRemount", true)
        }
    }
}
