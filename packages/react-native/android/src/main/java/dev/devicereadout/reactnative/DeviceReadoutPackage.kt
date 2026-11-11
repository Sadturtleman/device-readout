package dev.devicereadout.reactnative

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class DeviceReadoutPackage : BaseReactPackage() {
    override fun getModule(name: String, context: ReactApplicationContext): NativeModule? =
        if (name == NativeDeviceReadoutModule.NAME) NativeDeviceReadoutModule(context) else null
    override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
        mapOf(NativeDeviceReadoutModule.NAME to ReactModuleInfo(
            NativeDeviceReadoutModule.NAME, NativeDeviceReadoutModule.NAME, false, false, false, true
        ))
    }
}
