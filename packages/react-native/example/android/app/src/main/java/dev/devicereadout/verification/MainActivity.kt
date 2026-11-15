package dev.devicereadout.verification

import android.os.Bundle
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

class MainActivity : ReactActivity() {
    override fun getMainComponentName() = "DeviceReadoutVerification"
    override fun createReactActivityDelegate(): ReactActivityDelegate = object : DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled) {
        override fun getLaunchOptions() = Bundle().apply {
            putBoolean("isolation", BuildConfig.ISOLATION_FIXTURE)
            putString("isolationCase", this@MainActivity.intent.getStringExtra("isolationCase") ?: "get")
        }
    }
}
