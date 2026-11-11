package dev.devicereadout.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.system.Os
import android.system.OsConstants
import dev.devicereadout.*
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** Lists mounted app-visible views; never creates directories, allocates space or opens storage UI. */
internal class AndroidStorage(private val context: Context) {
    private data class Mount(val id: String, val device: String, val root: String, val path: String, val fileSystem: String, val source: String)
    private data class Key(val appData: Boolean, val volume: StorageVolume?, val uuid: String?, val mount: Mount?)
    private data class Source(val key: Key, val directory: File?)
    private data class Target(val id: String, val key: Key, var source: Source, var removed: Boolean = false)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val byKey = HashMap<Key, Target>()
    private var sequence = 0L
    private fun manager(): StorageManager = context.getSystemService(StorageManager::class.java)
        ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "StorageManager is unavailable.")

    @Suppress("DEPRECATION") // API 26–29 has no public StorageVolume.directory; this getter does not create directories.
    private fun inventory(): List<Target> {
        val manager = manager()
        val mounts = optional {mounts()}
        fun source(appData: Boolean, volume: StorageVolume?, path: File?): Source {
            val directory = path?.let {optional {it.canonicalFile}}
            val mount = directory?.let {file -> mounts?.filter {contains(it.path, file.path)}?.maxByOrNull {it.path.length}}
            return Source(Key(appData, volume, volume?.uuid, mount), directory)
        }
        val available = mutableListOf(source(true, null, File(context.applicationInfo.dataDir)))
        for (volume in manager.storageVolumes.filter {mounted(it.state)}) {
            val directory = when {
                Build.VERSION.SDK_INT >= 30 -> volume.directory
                volume.isPrimary -> Environment.getExternalStorageDirectory()
                else -> mounts?.asSequence()?.map {File(it.path)}?.firstOrNull {optional {manager.getStorageVolume(it)} == volume}
            }
            available += source(false, volume, directory)
        }
        return synchronized(gate) {
            val keys = available.map {it.key}.toSet()
            targets.values.filter {it.key !in keys}.forEach {it.removed = true}
            available.map {source ->
                byKey[source.key]?.takeUnless {it.removed}?.also {it.source = source}
                    ?: Target("volume-${++sequence}", source.key, source).also {targets[it.id] = it;byKey[it.key] = it}
            }
        }
    }
    fun list(): List<String> = inventory().map {it.id}
    fun current(): String? = inventory().singleOrNull {it.key.appData}?.id
    private fun resolve(id: String?): Source {
        inventory()
        return synchronized(gate) {targets[id]?.takeUnless {it.removed}?.source}
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The storage volume target was removed.")
    }
    fun read(id: String?): StorageVolumeSnapshot {
        val source = resolve(id)
        val volume = source.key.volume
        val stats = source.directory?.let {optional {Os.statvfs(it.path)}}
        val manager = manager()
        val uuid = source.directory?.let {optional {manager.getUuidForPath(it)}}
        return StorageVolumeSnapshot(
            name = volume?.let {optional {it.getDescription(context)}},
            fileSystem = source.key.mount?.fileSystem,
            totalBytes = stats?.let {bytes(it.f_blocks, it.f_frsize)},
            freeBytes = stats?.let {bytes(it.f_bfree, it.f_frsize)},
            availableToCallerBytes = stats?.let {bytes(it.f_bavail, it.f_frsize)},
            readOnly = stats?.let {it.f_flag and OsConstants.ST_RDONLY.toLong() != 0L}
                ?: volume?.let {when (it.state) {Environment.MEDIA_MOUNTED -> false;Environment.MEDIA_MOUNTED_READ_ONLY -> true;else -> null}},
            removable = volume?.isRemovable,
            allocatableBytes = uuid?.let {optional {manager.getAllocatableBytes(it).takeIf {value -> value >= 0}?.toULong()}},
        )
    }
    fun observeChanges(id: String?, changed: () -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        resolve(id)
        val lane = CallbackLane("DeviceReadout storage", fail)
        val closed = AtomicBoolean()
        val receiver = object : BroadcastReceiver() {
            @Suppress("DEPRECATION")
            override fun onReceive(context: Context?, intent: Intent?) {
                if (closed.get() || intent == null) return
                lane.deliver {
                    val volume = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(StorageVolume.EXTRA_STORAGE_VOLUME, StorageVolume::class.java)
                        else intent.getParcelableExtra<StorageVolume>(StorageVolume.EXTRA_STORAGE_VOLUME)
                    if (intent.action in removalActions) synchronized(gate) {
                        // Retain the callback's removal even if the OS has already remounted by read time.
                        targets.values.filter {it.key.volume != null && it.key.volume == volume}.forEach {it.removed = true}
                    }
                    changed()
                }
            }
        }
        val filter = IntentFilter().apply {
            addDataScheme("file")
            (removalActions + Intent.ACTION_MEDIA_MOUNTED + Intent.ACTION_MEDIA_CHECKING).forEach(::addAction)
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, null, lane.handler, Context.RECEIVER_NOT_EXPORTED)
            else context.registerReceiver(receiver, filter, null, lane.handler)
        } catch (error: Throwable) {lane.close();throw error}
        return object : CollectorSubscription {
            override val pollingRequired = true // Capacity changes have no complete native event source.
            override fun close() {
                if (!closed.compareAndSet(false, true)) return
                try {context.unregisterReceiver(receiver)} finally {lane.close()}
            }
        }
    }
    private fun mounts(): List<Mount> = File("/proc/self/mountinfo").useLines {lines -> lines.map {line ->
        val separator = line.indexOf(" - ")
        if (separator < 0) throw IllegalArgumentException("Malformed native mount entry.")
        val fields = line.substring(0, separator).split(' ')
        val detail = line.substring(separator + 3).split(' ')
        if (fields.size < 6 || detail.size < 3) throw IllegalArgumentException("Incomplete native mount entry.")
        Mount(fields[0], fields[2], unescape(fields[3]), unescape(fields[4]), detail[0], unescape(detail[1]))
    }.toList()}
    private fun unescape(value: String): String = Regex("\\\\([0-7]{3})").replace(value) {it.groupValues[1].toInt(8).toChar().toString()}
    private fun contains(parent: String, child: String): Boolean = parent == "/" || child == parent || child.startsWith("$parent/")
    private fun mounted(state: String): Boolean = state == Environment.MEDIA_MOUNTED || state == Environment.MEDIA_MOUNTED_READ_ONLY
    private val removalActions = setOf(Intent.ACTION_MEDIA_UNMOUNTED, Intent.ACTION_MEDIA_REMOVED, Intent.ACTION_MEDIA_BAD_REMOVAL, Intent.ACTION_MEDIA_EJECT, Intent.ACTION_MEDIA_UNMOUNTABLE, Intent.ACTION_MEDIA_SHARED, Intent.ACTION_MEDIA_NOFS)
    private fun bytes(blocks: Long, unit: Long): ULong? {
        if (blocks < 0 || unit <= 0) return null
        val size = unit.toULong()
        val count = blocks.toULong()
        return if (count <= ULong.MAX_VALUE / size) count * size else null
    }
}
private inline fun <T> optional(read: () -> T): T? = try {read()} catch (_: Exception) {null}
