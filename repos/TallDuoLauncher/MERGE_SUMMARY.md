# tallDuo - Merged Android Launcher for Tall/Foldable Devices

## Overview
A unified Android launcher combining features from:
1. **DuoLauncher-main** (base - jakesgoodapps/DuoLauncher)
2. **Lalitmukesh69/DuoLauncher** fork (7 commits ahead with new features)
3. **Makedeckonside.txt** architectural guide (3-column grid, foldable continuity, etc.)
4. Custom implementations (FeedOverlayController, LockGestureService, etc.)

## Features Implemented

### 1. 3-Column Grid Layout (from Makedeckonside.txt)
- **File**: `HomeEditing.kt` - `GRID_COLUMNS = 3`
- **File**: `LayoutModel.kt` - `homeGeometry()` calculates grid for 3 columns
- **File**: `LauncherScreen.kt` - `SharedHomeGrid` uses 3-column cell width
- Optimized for taller, less wide foldable displays (like iPhone Duo but for vertical foldables)

### 2. Foldable Continuity Controller (from Makedeckonside.txt)
- **File**: `FoldableContinuityController.kt`
- Detects fold/unfold state via `Configuration.smallestScreenWidthDp >= 600`
- Preserves grid cell indices (cellX, cellY) during transitions
- Integrated in `MainActivity.onConfigurationChanged()`

### 3. Google Discover Feed Integration (from Makedeckonside.txt)
- **File**: `FeedOverlayController.kt`
- Implements Lawnfeed AIDL interface for Google Discover
- Binds to Google Search app's overlay service
- Scroll callbacks for Discover feed integration

### 4. Double-Tap to Lock Screen (from Lalitmukesh69 fork + Makedeckonside.txt)
- **File**: `LockGestureService.kt` - AccessibilityService using `GLOBAL_ACTION_LOCK_SCREEN`
- **File**: `MainActivity.kt` - `lockScreen()` using `SystemShadeAccessibilityService.lock()`
- **File**: `CustomizationSheet.kt` - Toggle setting in Gestures page
- **File**: `LauncherModel.kt` - `doubleTapToLock` state with persistence
- **File**: `AndroidManifest.xml` - LockGestureService declaration
- **File**: `res/xml/accessibility_service_config.xml` - Service config
- **File**: `res/values/strings.xml` - Service description

### 5. Third-Party Icon Packs & Custom Icon Shapes (from Lalitmukesh69 fork)
- **File**: `IconCustomization.kt` - Full implementation (395 lines)
  - 6 icon shapes: Rounded Square, Circle, Squircle, Square, Teardrop, Cylinder (Pebble)
  - Icon pack manager with appfilter.xml parsing
  - Adaptive icon composition with iconback, iconmask, iconupon, scale
- **File**: `CustomizationSheet.kt` - ICONS page with live preview, shape selector, pack selector
- **File**: `LauncherModel.kt` - `IconPreferences` with StateFlow persistence

### 6. 144Hz High Refresh Rate Animations (from Lalitmukesh69 fork + Makedeckonside.txt)
- **File**: `HighRefreshRate.kt` - Window extension `enableHighRefreshRate()`
- **File**: `HighRefreshRateAnimations.kt` - Custom spring physics
  - `AnimationPhysics` - SpringForce configs (HIGH_REFRESH, ULTRA_SMOOTH, QUICK_RESPONSE, GENTLE_SETTLE)
  - `ComposeSprings` - Compose SpringSpecs
  - `PhysicsSpringAnimation` - View-based spring animation wrapper
  - `GestureVelocityTracker` - Velocity calculation for natural spring continuation
- Integrated in `MainActivity.onCreate()` and `onResume()`

### 7. Dock Recents Support (from Lalitmukesh69 fork)
- **File**: `LauncherModel.kt` - `showRecentApps` state + `setShowRecentApps()`
- **File**: `CustomizationSheet.kt` - Toggle in Home layout settings
- **File**: `DiscoverActivity.kt` - Shows recent apps in dock (up to 4)
- **File**: `LauncherScreen.kt` - Renders recent apps in dock
- **File**: `DockRecentsTest.kt` - Unit tests

### 8. Wallpaper Improvements (from Lalitmukesh69 fork)
- **File**: `MainActivity.kt` - `previewWallpaper()`, `openWallpaperPicker()`, `previewDuneWallpaper()`
- **File**: `CustomizationSheet.kt` - Wallpaper page with system picker + live wallpaper preview
- **File**: `DuneWallpaper.kt` - `showDunesFallback` parameter for previews

### 9. Test Coverage (from Lalitmukesh69 fork)
- **File**: `DockRecentsTest.kt` - 6 tests for dock recents logic
- **File**: `DoubleTapToLockTest.kt` - 6 tests for double-tap lock behavior

## Architecture

### Core Components
- **MainActivity** - Entry point, integrates all controllers
- **LauncherModel** - State management (ViewModel with SharedPreferences persistence)
- **LauncherScreen** - Compose UI for home screen, dock, widgets, gestures
- **CustomizationSheet** - Settings UI with pages: Overview, Wallpaper, Icons, Home, Gestures, Backup, Help

### Foldable Support
- Cover screen (folded): Single 3-column workspace + right-side dock
- Inner screen (unfolded): Dual-pane with extra workspace on left + right-side dock
- Seamless transition preserving icon positions

### Key Technical Details
- **Target SDK**: Android 16 (API 36)
- **Language**: Kotlin with Jetpack Compose
- **Architecture**: MVVM with StateFlow
- **Widget Hosting**: Native Android AppWidgetHost
- **Google Discover**: Activity embedding via Lawnfeed AIDL
- **Accessibility**: System shade + lock screen gestures

## File Structure
```
tallDuo/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/jake/duolauncher/
│   │   │   │   ├── Core: MainActivity, LauncherModel, LauncherScreen
│   │   │   │   ├── UI: CustomizationSheet, IconSettingsPage, HomeLayoutSettings
│   │   │   │   ├── Foldable: FoldableContinuityController
│   │   │   │   ├── Discover: FeedOverlayController, DiscoverActivity
│   │   │   │   ├── Lock: LockGestureService, SystemShadeAccessibilityService
│   │   │   │   ├── Animations: HighRefreshRate, HighRefreshRateAnimations
│   │   │   │   ├── Icons: IconCustomization, IconPackManager, LoadedIconPack
│   │   │   │   ├── Widgets: WidgetController, WidgetPicker, WidgetSizing
│   │   │   │   ├── Layout: LayoutModel, HomeEditing, HomeDrag
│   │   │   │   └── Backgrounds: DuneWallpaper, LauncherBackground
│   │   │   ├── res/
│   │   │   │   ├── xml/accessibility_service_config.xml
│   │   │   │   └── values/strings.xml
│   │   │   └── AndroidManifest.xml
│   │   └── test/
│   │       └── java/com/jake/duolauncher/
│   │           ├── DockRecentsTest.kt
│   │           └── DoubleTapToLockTest.kt
│   └── build.gradle.kts
└── README.md
```

## Build Instructions
```bash
# Requires JDK 17+, Android SDK 36
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

## Testing
- Unit tests: `./gradlew :app:testDebugUnitTest`
- Instrumentation tests: `./gradlew :app:connectedAndroidTest`
- Lint: `./gradlew :app:lintDebug`

## Key Differences from Base DuoLauncher
1. **3-column grid** instead of 4-column (better for tall foldables)
2. **FoldableContinuityController** for seamless fold/unfold
3. **FeedOverlayController** for Google Discover integration
4. **LockGestureService** + SystemShadeAccessibilityService for double-tap lock
5. **Full icon pack support** with 6 custom shapes
6. **144Hz optimized** spring animations
7. **Dock recents** showing recently used apps
8. **System wallpaper picker** integration
9. **Comprehensive test coverage** for new features