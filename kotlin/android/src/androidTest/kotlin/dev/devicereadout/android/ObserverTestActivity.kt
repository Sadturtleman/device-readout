package dev.devicereadout.android

import android.app.Activity

/** Test application code owns Android lifecycle callbacks; the SDK never inspects an Activity. */
class ObserverTestActivity : Activity() {
    companion object { @Volatile var observeActivity: ((Boolean) -> Unit)? = null }
    override fun onResume() {super.onResume();observeActivity?.invoke(true)}
    override fun onPause() {observeActivity?.invoke(false);super.onPause()}
}
