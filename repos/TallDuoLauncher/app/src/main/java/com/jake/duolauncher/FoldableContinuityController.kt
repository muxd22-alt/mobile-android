package com.jake.duolauncher

import android.content.Context
import android.content.res.Configuration
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Handles seamless fold/unfold state continuity for foldable devices.
 * Maintains a single WorkspacePage grid model based on 3 x N.
 * Uses onConfigurationChanged to recalculate icon scaling while preserving
 * grid cell indices (cellX, cellY).
 */
class FoldableContinuityController(
    private val context: Context,
    private val onFoldStateChanged: (Boolean) -> Unit
) : DefaultLifecycleObserver {

    private var wasUnfolded = isUnfolded(context)

    override fun onStart(owner: LifecycleOwner) {
        wasUnfolded = isUnfolded(context)
    }

    override fun onResume(owner: LifecycleOwner) {
        val isUnfolded = isUnfolded(context)
        if (isUnfolded != wasUnfolded) {
            wasUnfolded = isUnfolded
            onFoldStateChanged(isUnfolded)
        }
    }

    companion object {
        fun isUnfolded(context: Context): Boolean {
            val config = context.resources.configuration
            return config.smallestScreenWidthDp >= 600
        }
    }
}

/**
 * Usage in MainActivity:
 * override fun onConfigurationChanged(newConfig: Configuration) {
 *     super.onConfigurationChanged(newConfig)
 *     val isUnfolded = newConfig.smallestScreenWidthDp >= 600
 *     foldableController.onFoldStateChanged(isUnfolded)
 *     
 *     // Relayout workspace without destroying item positions
 *     workspace.requestLayout()
 *     hotseat.requestLayout()
 * }
 */