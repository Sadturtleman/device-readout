package dev.devicereadout.verification

import android.app.Application
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.ReactNativeApplicationEntryPoint.loadReactNative
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import dev.devicereadout.reactnative.DeviceReadoutPackage

class MainApplication : Application(), ReactApplication {
    override val reactHost: ReactHost by lazy {
        val packages = PackageList(this).packages
        if (BuildConfig.ISOLATION_FIXTURE) {
            packages.removeAll {it is DeviceReadoutPackage}
            packages.add(IsolationPackage())
        }
        getDefaultReactHost(context = applicationContext, packageList = packages, useDevSupport = false)
    }
    override fun onCreate() {
        super.onCreate();loadReactNative(this)
        if (BuildConfig.ISOLATION_FIXTURE) IsolationFixture.startUiHeartbeat()
    }
}
