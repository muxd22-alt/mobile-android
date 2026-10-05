package com.jake.duolauncher

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * Double-Tap to Lock Screen using Android Accessibility Service.
 * Uses GLOBAL_ACTION_LOCK_SCREEN for instant screen locking without 
 * triggering PIN/password requirement on resume.
 * 
 * Add to AndroidManifest.xml:
 * <service
 *     android:name=".LockGestureService"
 *     android:label="Duo Launcher Lock Gesture"
 *     android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
 *     <intent-filter>
 *         <action android:name="android.accessibilityservice.AccessibilityService" />
 *     </intent-filter>
 *     <meta-data
 *         android:name="android.accessibilityservice"
 *         android:resource="@xml/accessibility_service_config" />
 * </service>
 * 
 * Create res/xml/accessibility_service_config.xml:
 * <accessibility-service
 *     xmlns:android="http://schemas.android.com/apk/res/android"
 *     android:accessibilityEventTypes="typeWindowStateChanged"
 *     android:accessibilityFeedbackType="feedbackGeneric"
 *     android:accessibilityFlags="flagDefault"
 *     android:canRequestTouchExploration="false"
 *     android:description="@string/lock_gesture_service_desc" />
 */
class LockGestureService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used for this service
    }

    override fun onInterrupt() {
        // Not used for this service
    }

    companion object {
        private const val ACTION_LOCK_SCREEN = "com.jake.duolauncher.ACTION_LOCK_SCREEN"

        /**
         * Lock the device screen using AccessibilityService.
         * Requires the LockGestureService to be enabled in Accessibility settings.
         */
        fun lockDevice(context: Context): Boolean {
            val intent = Intent(context, LockGestureService::class.java).apply {
                action = ACTION_LOCK_SCREEN
            }
            return try {
                context.startService(intent) != null
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }

        /**
         * Check if accessibility service is enabled.
         */
        fun isAccessibilityEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            
            return enabledServices.contains("com.jake.duolauncher/.LockGestureService")
        }

        /**
         * Open accessibility settings to enable the service.
         */
        fun openAccessibilitySettings(context: Context) {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_LOCK_SCREEN) {
            // Android System Screen Lock - works without PIN/password on resume
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
            }
        }
        return START_NOT_STICKY
    }
}

/**
 * Double-tap gesture detector for home screen.
 * Add to HomePagePane or workspace to detect double-tap on empty space.
 */
object DoubleTapLockHelper {
    fun setupDoubleTapLock(
        context: Context,
        onDoubleTap: () -> Unit
    ): () -> Unit {
        var lastTapTime = 0L
        val DOUBLE_TAP_TIMEOUT = 300L // ms
        
        return {
            val now = System.currentTimeMillis()
            if (now - lastTapTime < DOUBLE_TAP_TIMEOUT) {
                // Double tap detected
                if (LockGestureService.isAccessibilityEnabled(context)) {
                    LockGestureService.lockDevice(context)
                } else {
                    // Optionally prompt to enable accessibility
                    onDoubleTap()
                }
            }
            lastTapTime = now
        }
    }
}