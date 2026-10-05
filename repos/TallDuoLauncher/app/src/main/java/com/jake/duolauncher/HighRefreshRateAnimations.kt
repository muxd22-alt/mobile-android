package com.jake.duolauncher

import android.app.Activity
import android.view.Display
import android.view.WindowManager
import android.animation.SpringAnimation
import android.animation.SpringForce
import android.view.View
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * High Refresh Rate (144Hz) Support for smooth animations.
 * Forces preferred display refresh rate and tunes spring physics.
 */
object HighRefreshRateManager {

    /**
     * Request maximum display refresh rate (144Hz if available).
     * Call in Activity.onCreate() before setContentView.
     */
    fun requestMaxRefreshRate(activity: Activity) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            val display = activity.display ?: return
            val modes = display.supportedModes
            val maxMode = modes.maxByOrNull { it.refreshRate }
            maxMode?.let { mode ->
                activity.window.attributes.preferredDisplayModeId = mode.modeId
            }
        }
    }

    /**
     * Get the highest available refresh rate for the current display.
     */
    fun getMaxRefreshRate(activity: Activity): Float {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            val display = activity.display ?: return 60f
            return display.supportedModes.maxByOrNull { it.refreshRate }?.refreshRate ?: 60f
        }
        return 60f
    }

    /**
     * Check if high refresh rate (90Hz+) is available.
     */
    fun isHighRefreshRateAvailable(activity: Activity): Boolean {
        return getMaxRefreshRate(activity) >= 90f
    }
}

/**
 * Custom Spring Configurations for high refresh rate displays.
 * Lower stiffness and damping for smoother, more responsive animations.
 */
object AnimationPhysics {

    // Standard spring configs
    val STANDARD_SPRING = SpringForce().apply {
        dampingRatio = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
        stiffness = SpringForce.STIFFNESS_MEDIUM
    }

    // High refresh rate optimized springs - lower stiffness for buttery smooth motion
    val HIGH_REFRESH_SPRING_CONFIG = SpringForce().apply {
        dampingRatio = SpringForce.DAMPING_RATIO_LOW_BOUNCY
        stiffness = SpringForce.STIFFNESS_LOW
    }

    // Ultra-smooth spring for 144Hz
    val ULTRA_SMOOTH_SPRING = SpringForce().apply {
        dampingRatio = 0.75f
        stiffness = 800f
    }

    // Quick response spring for touch interactions
    val QUICK_RESPONSE_SPRING = SpringForce().apply {
        dampingRatio = SpringForce.DAMPING_RATIO_HIGH_BOUNCY
        stiffness = SpringForce.STIFFNESS_HIGH
    }

    // Gentle settle spring for page transitions
    val GENTLE_SETTLE_SPRING = SpringForce().apply {
        dampingRatio = 0.9f
        stiffness = 500f
    }
}

/**
 * Compose Spring Specs for high refresh rate animations.
 */
object ComposeSprings {
    // Standard spring spec
    val standard = spring<Float>(dampingRatio = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY, stiffness = SpringForce.STIFFNESS_MEDIUM)

    // High refresh rate optimized
    val highRefresh = spring<Float>(dampingRatio = SpringForce.DAMPING_RATIO_LOW_BOUNCY, stiffness = SpringForce.STIFFNESS_LOW)

    // Ultra smooth for 144Hz
    val ultraSmooth = spring<Float>(dampingRatio = 0.75f, stiffness = 800f)

    // Quick response for drag/touch
    val quickResponse = spring<Float>(dampingRatio = SpringForce.DAMPING_RATIO_HIGH_BOUNCY, stiffness = SpringForce.STIFFNESS_HIGH)
}

/**
 * SpringAnimation wrapper for View-based animations with custom physics.
 */
class PhysicsSpringAnimation(
    view: View,
    property: android.util.Property<View, Float>,
    springForce: SpringForce = AnimationPhysics.HIGH_REFRESH_SPRING_CONFIG
) : SpringAnimation(view, property, springForce) {

    fun animateToValue(finalValue: Float, velocity: Float = 0f) {
        this.spring.springForce = springForce
        this.startVelocity = velocity
        this.animateToFinalPosition(finalValue)
    }

    companion object {
        fun createTranslationX(view: View, springForce: SpringForce = AnimationPhysics.HIGH_REFRESH_SPRING_CONFIG) =
            PhysicsSpringAnimation(view, View.TRANSLATION_X, springForce)
        
        fun createTranslationY(view: View, springForce: SpringForce = AnimationPhysics.HIGH_REFRESH_SPRING_CONFIG) =
            PhysicsSpringAnimation(view, View.TRANSLATION_Y, springForce)
        
        fun createScaleX(view: View, springForce: SpringForce = AnimationPhysics.HIGH_REFRESH_SPRING_CONFIG) =
            PhysicsSpringAnimation(view, View.SCALE_X, springForce)
        
        fun createScaleY(view: View, springForce: SpringForce = AnimationPhysics.HIGH_REFRESH_SPRING_CONFIG) =
            PhysicsSpringAnimation(view, View.SCALE_Y, springForce)
        
        fun createAlpha(view: View, springForce: SpringForce = AnimationPhysics.HIGH_REFRESH_SPRING_CONFIG) =
            PhysicsSpringAnimation(view, View.ALPHA, springForce)
    }
}

/**
 * Composable to apply high refresh rate settings.
 */
@Composable
fun HighRefreshRateConfig(activity: Activity = LocalContext.current as Activity) {
    android.util.Log.d("DuoLauncher", "Max refresh rate: ${HighRefreshRateManager.getMaxRefreshRate(activity)}")
}

/**
 * Velocity tracker for gesture-based spring animations.
 * Calculates release velocity for natural spring continuation.
 */
class GestureVelocityTracker {
    private var lastTime = 0L
    private var lastPosition = 0f
    private var velocity = 0f

    fun update(position: Float, time: Long = System.nanoTime()) {
        if (lastTime > 0) {
            val dt = (time - lastTime) / 1_000_000_000f // Convert to seconds
            if (dt > 0) {
                velocity = (position - lastPosition) / dt
            }
        }
        lastPosition = position
        lastTime = time
    }

    fun getVelocity(): Float = velocity

    fun reset() {
        lastTime = 0
        lastPosition = 0f
        velocity = 0f
    }
}