package dev.devicereadout.android

import android.os.Looper
import android.telephony.TelephonyManager
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowTelephonyManager
import java.util.concurrent.CopyOnWriteArrayList

/** Controls only Android's service replies; the public SDK is used without internal substitutions. */
@Implements(TelephonyManager::class)
class IdentityTelephonyService : ShadowTelephonyManager() {
    @Volatile var imeiFailure: RuntimeException? = null
    @Volatile var meidFailure: RuntimeException? = null
    @Volatile var onImeiRead: (() -> Unit)? = null
    val readsOnMain = CopyOnWriteArrayList<Boolean>()
    @Implementation
    override fun getImei(slotIndex: Int): String? {
        readsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        onImeiRead?.invoke()
        imeiFailure?.let {throw it}
        return super.getImei(slotIndex)
    }
    @Implementation
    override fun getMeid(slotIndex: Int): String? {
        readsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        meidFailure?.let {throw it}
        return super.getMeid(slotIndex)
    }
}
