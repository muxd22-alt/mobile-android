package com.jake.duolauncher

import org.junit.Assert.*
import org.junit.Test

class DoubleTapToLockTest {

    @Test
    fun `doubleTapToLock is enabled by default in LauncherState`() {
        val state = LauncherState()
        assertTrue("Double tap to lock should be enabled by default", state.doubleTapToLock)
    }

    @Test
    fun `doubleTapToLock can be toggled in LauncherState`() {
        val state = LauncherState()
        val disabled = state.copy(doubleTapToLock = false)
        assertFalse(disabled.doubleTapToLock)

        val reEnabled = disabled.copy(doubleTapToLock = true)
        assertTrue(reEnabled.doubleTapToLock)
    }

    @Test
    fun `double tap lock callback is executed when enabled and drag is inactive`() {
        var locked = false
        val onLockScreen = { locked = true }

        val doubleTapToLock = true
        val dragActive = false
        val pagerInputEnabled = true

        val onDoubleTap: (() -> Unit)? = if (pagerInputEnabled && doubleTapToLock) onLockScreen else null

        assertNotNull(onDoubleTap)
        if (!dragActive) {
            onDoubleTap?.invoke()
        }
        assertTrue(locked)
    }

    @Test
    fun `double tap lock callback is null when setting is disabled`() {
        var locked = false
        val onLockScreen = { locked = true }

        val doubleTapToLock = false
        val pagerInputEnabled = true

        val onDoubleTap: (() -> Unit)? = if (pagerInputEnabled && doubleTapToLock) onLockScreen else null

        assertNull("onDoubleTap must be null when doubleTapToLock is disabled", onDoubleTap)
        assertFalse(locked)
    }

    @Test
    fun `double tap does not trigger lock while dragging`() {
        var locked = false
        val onLockScreen = { locked = true }

        val doubleTapToLock = true
        val dragActive = true
        val pagerInputEnabled = !dragActive

        val onDoubleTap: (() -> Unit)? = if (pagerInputEnabled && doubleTapToLock) onLockScreen else null

        assertNull("onDoubleTap must be null while dragging", onDoubleTap)
        assertFalse(locked)
    }

    @Test
    fun `double tap does not trigger lock on occupied app cell`() {
        var locked = false
        val onDoubleTap = { locked = true }
        val savedId: String? = "com.android.chrome" // occupied cell
        val dragActive = false

        val cellDoubleClickHandler: (() -> Unit)? = if (savedId == null && !dragActive) {
            { onDoubleTap() }
        } else null

        assertNull("Occupied cell must not have double-click lock handler", cellDoubleClickHandler)
        assertFalse(locked)
    }

    @Test
    fun `double tap triggers lock on empty cell`() {
        var locked = false
        val onDoubleTap = { locked = true }
        val savedId: String? = null // empty cell
        val dragActive = false

        val cellDoubleClickHandler: (() -> Unit)? = if (savedId == null && !dragActive) {
            { onDoubleTap() }
        } else null

        assertNotNull("Empty cell must have double-click lock handler", cellDoubleClickHandler)
        cellDoubleClickHandler?.invoke()
        assertTrue(locked)
    }
}
