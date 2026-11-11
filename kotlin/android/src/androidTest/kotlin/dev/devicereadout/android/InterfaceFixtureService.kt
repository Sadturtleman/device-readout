package dev.devicereadout.android

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import kotlinx.coroutines.CompletableDeferred

/** Test APK only: creates a local TUN with no remote server or default route. */
class InterfaceFixtureService : VpnService() {
    companion object {var ready = CompletableDeferred<InterfaceFixtureService>()}
    override fun onCreate() {super.onCreate();ready.complete(this)}
    fun createInterface(): ParcelFileDescriptor = Builder().setSession("DeviceReadout interface fixture")
        .addAllowedApplication(packageName).addAddress("192.0.2.1", 24).addRoute("192.0.2.0", 24)
        .allowFamily(OsConstants.AF_INET6).setMtu(1400).establish()
        ?: error("The project test APK must be authorized for its local VPN fixture.")
}
