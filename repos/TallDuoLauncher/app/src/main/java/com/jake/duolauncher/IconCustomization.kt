package com.jake.duolauncher

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asComposePath
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.content.res.ResourcesCompat
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.InputStream
import kotlin.math.min

enum class IconShape(val label: String) {
    ROUNDED_SQUARE("Rounded Square"),
    CIRCLE("Circle"),
    SQUIRCLE("Squircle"),
    SQUARE("Square"),
    TEARDROP("Teardrop"),
    CYLINDER("Pebble");

    fun maskPath(width: Float, height: Float): android.graphics.Path {
        val path = android.graphics.Path()
        val w = width
        val h = height
        when (this) {
            ROUNDED_SQUARE -> {
                val r = min(w, h) * 0.24f
                path.addRoundRect(0f, 0f, w, h, r, r, android.graphics.Path.Direction.CW)
            }
            CIRCLE -> {
                val radius = min(w, h) / 2f
                path.addCircle(w / 2f, h / 2f, radius, android.graphics.Path.Direction.CW)
            }
            SQUIRCLE -> {
                // Continuous curvature superellipse approximation using cubic Bézier curves
                val r = min(w, h) / 2f
                val cx = w / 2f
                val cy = h / 2f
                val c = r * 0.86f // control point offset for squircle
                path.moveTo(cx, cy - r)
                path.cubicTo(cx + c, cy - r, cx + r, cy - c, cx + r, cy)
                path.cubicTo(cx + r, cy + c, cx + c, cy + r, cx, cy + r)
                path.cubicTo(cx - c, cy + r, cx - r, cy + c, cx - r, cy)
                path.cubicTo(cx - r, cy - c, cx - c, cy - r, cx, cy - r)
                path.close()
            }
            SQUARE -> {
                val r = min(w, h) * 0.08f
                path.addRoundRect(0f, 0f, w, h, r, r, android.graphics.Path.Direction.CW)
            }
            TEARDROP -> {
                // Top-left, top-right, bottom-left rounded, bottom-right sharper
                val rLarge = min(w, h) * 0.48f
                val rSmall = min(w, h) * 0.12f
                val radii = floatArrayOf(
                    rLarge, rLarge, // top-left
                    rLarge, rLarge, // top-right
                    rSmall, rSmall, // bottom-right (sharp teardrop point)
                    rLarge, rLarge  // bottom-left
                )
                path.addRoundRect(0f, 0f, w, h, radii, android.graphics.Path.Direction.CW)
            }
            CYLINDER -> {
                // Smooth pebble/pill corner
                val rx = w * 0.36f
                val ry = h * 0.36f
                path.addRoundRect(0f, 0f, w, h, rx, ry, android.graphics.Path.Direction.CW)
            }
        }
        return path
    }

    fun composeShape(): Shape {
        return object : Shape {
            override fun createOutline(
                size: Size,
                layoutDirection: LayoutDirection,
                density: Density
            ): Outline {
                val androidPath = maskPath(size.width, size.height)
                return Outline.Generic(androidPath.asComposePath())
            }
        }
    }
}

data class IconPackInfo(
    val packageName: String,
    val label: String,
    val icon: Bitmap?,
)

data class IconPreferencesState(
    val iconPackPackage: String? = null,
    val iconShape: IconShape = IconShape.ROUNDED_SQUARE,
)

class IconPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("duo_icons", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(
        IconPreferencesState(
            iconPackPackage = prefs.getString("icon_pack", null)?.takeIf { it.isNotBlank() },
            iconShape = runCatching {
                IconShape.valueOf(prefs.getString("icon_shape", IconShape.ROUNDED_SQUARE.name) ?: IconShape.ROUNDED_SQUARE.name)
            }.getOrDefault(IconShape.ROUNDED_SQUARE)
        )
    )
    val state: StateFlow<IconPreferencesState> = _state.asStateFlow()

    fun setIconPack(packageName: String?) {
        val clean = packageName?.trim()?.takeIf { it.isNotEmpty() }
        prefs.edit().putString("icon_pack", clean).apply()
        _state.value = _state.value.copy(iconPackPackage = clean)
    }

    fun setIconShape(shape: IconShape) {
        prefs.edit().putString("icon_shape", shape.name).apply()
        _state.value = _state.value.copy(iconShape = shape)
    }
}

object IconPackManager {
    private val THEME_ACTIONS = listOf(
        "org.adw.launcher.THEMES",
        "com.novalauncher.THEME",
        "com.gau.go.launcherex.theme",
        "com.teslacoilsw.launcher.THEME",
        "com.anddoes.launcher.THEME",
        "com.dlto.atom.launcher.THEME"
    )

    private val THEME_CATEGORIES = listOf(
        "com.fede.launcher.THEME_ICONPACK",
        "com.anddoes.launcher.THEME"
    )

    fun getInstalledIconPacks(context: Context): List<IconPackInfo> {
        val pm = context.packageManager
        val packages = mutableMapOf<String, IconPackInfo>()

        for (action in THEME_ACTIONS) {
            val intent = Intent(action)
            val resolves = pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            for (resolve in resolves) {
                val pkg = resolve.activityInfo.packageName
                if (pkg != context.packageName && pkg !in packages) {
                    val label = resolve.loadLabel(pm).toString()
                    val icon = runCatching { resolve.loadIcon(pm).toBitmap(96, 96) }.getOrNull()
                    packages[pkg] = IconPackInfo(pkg, label, icon)
                }
            }
        }

        for (category in THEME_CATEGORIES) {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(category)
            val resolves = pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            for (resolve in resolves) {
                val pkg = resolve.activityInfo.packageName
                if (pkg != context.packageName && pkg !in packages) {
                    val label = resolve.loadLabel(pm).toString()
                    val icon = runCatching { resolve.loadIcon(pm).toBitmap(96, 96) }.getOrNull()
                    packages[pkg] = IconPackInfo(pkg, label, icon)
                }
            }
        }

        return packages.values.sortedBy { it.label.lowercase() }
    }

    fun openPlayStoreForIconPacks(context: Context) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=icon%20pack")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (_: Throwable) {
            val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/search?q=icon%20pack&c=apps")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            runCatching { context.startActivity(webIntent) }
        }
    }

    fun loadIconPack(context: Context, packageName: String?): LoadedIconPack? {
        if (packageName.isNullOrBlank()) return null
        return try {
            val pm = context.packageManager
            val packRes = pm.getResourcesForApplication(packageName)
            val pack = LoadedIconPack(packageName, packRes)
            pack.load()
            pack
        } catch (_: Throwable) {
            null
        }
    }
}

class LoadedIconPack(
    val packageName: String,
    private val resources: Resources
) {
    private val componentMap = mutableMapOf<String, String>()
    private val packageMap = mutableMapOf<String, String>()
    private val iconBacks = mutableListOf<String>()
    private var iconMask: String? = null
    private var iconUpon: String? = null
    private var scaleFactor: Float = 1.0f

    fun load() {
        var inputStream: InputStream? = null
        try {
            // Try assets/appfilter.xml first, then res/xml/appfilter.xml
            inputStream = try {
                resources.assets.open("appfilter.xml")
            } catch (_: Throwable) {
                null
            }

            if (inputStream != null) {
                parseAppFilter(inputStream)
            } else {
                val resId = resources.getIdentifier("appfilter", "xml", packageName)
                if (resId != 0) {
                    val parser = resources.getXml(resId)
                    parseAppFilterXml(parser)
                }
            }
        } catch (_: Throwable) {
            // Error loading appfilter, will fall back gracefully
        } finally {
            try { inputStream?.close() } catch (_: Throwable) {}
        }
    }

    private fun parseAppFilter(inputStream: InputStream) {
        val factory = XmlPullParserFactory.newInstance()
        val parser = factory.newPullParser()
        parser.setInput(inputStream, "UTF-8")
        parseAppFilterXml(parser)
    }

    private fun parseAppFilterXml(parser: XmlPullParser) {
        var eventType = parser.eventType
        while (eventType != XmlPullParser.END_DOCUMENT) {
            if (eventType == XmlPullParser.START_TAG) {
                val name = parser.name
                when (name) {
                    "item" -> {
                        val component = parser.getAttributeValue(null, "component")
                        val drawable = parser.getAttributeValue(null, "drawable")
                        if (!component.isNullOrBlank() && !drawable.isNullOrBlank()) {
                            // Extract ComponentInfo{com.pkg/com.pkg.Activity} or raw string
                            componentMap[component] = drawable
                            val cleanComp = component.removePrefix("ComponentInfo{").removeSuffix("}")
                            componentMap[cleanComp] = drawable
                            val parts = cleanComp.split("/")
                            if (parts.isNotEmpty()) {
                                packageMap[parts[0]] = drawable
                            }
                        }
                    }
                    "iconback" -> {
                        for (i in 0 until parser.attributeCount) {
                            val attrName = parser.getAttributeName(i)
                            if (attrName.startsWith("img")) {
                                val value = parser.getAttributeValue(i)
                                if (!value.isNullOrBlank()) iconBacks.add(value)
                            }
                        }
                    }
                    "iconmask" -> {
                        val img = parser.getAttributeValue(null, "img1") ?: parser.getAttributeValue(null, "img")
                        if (!img.isNullOrBlank()) iconMask = img
                    }
                    "iconupon" -> {
                        val img = parser.getAttributeValue(null, "img1") ?: parser.getAttributeValue(null, "img")
                        if (!img.isNullOrBlank()) iconUpon = img
                    }
                    "scale" -> {
                        val factor = parser.getAttributeValue(null, "factor")
                        factor?.toFloatOrNull()?.let { scaleFactor = it }
                    }
                }
            }
            eventType = parser.next()
        }
    }

    fun getIcon(component: ComponentName): Bitmap? {
        val flattened = component.flattenToString()
        val compInfo = "ComponentInfo{${component.packageName}/${component.className}}"

        val drawableName = componentMap[compInfo]
            ?: componentMap[flattened]
            ?: packageMap[component.packageName]
            ?: return null

        val resId = resources.getIdentifier(drawableName, "drawable", packageName)
        if (resId == 0) return null

        return try {
            ResourcesCompat.getDrawable(resources, resId, null)?.toBitmap(144, 144)
        } catch (_: Throwable) {
            null
        }
    }

    fun composeFallback(baseDrawable: Drawable, shape: IconShape): Bitmap {
        val size = 144
        val result = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)

        // Draw iconback if available
        if (iconBacks.isNotEmpty()) {
            val backName = iconBacks.first()
            val backResId = resources.getIdentifier(backName, "drawable", packageName)
            if (backResId != 0) {
                runCatching {
                    ResourcesCompat.getDrawable(resources, backResId, null)?.let { back ->
                        back.setBounds(0, 0, size, size)
                        back.draw(canvas)
                    }
                }
            }
        }

        // Draw scaled base icon
        val scaledSize = (size * scaleFactor).toInt().coerceIn(32, size)
        val inset = (size - scaledSize) / 2
        val baseBitmap = baseDrawable.toBitmap(scaledSize, scaledSize)
        canvas.drawBitmap(baseBitmap, inset.toFloat(), inset.toFloat(), null)

        // Apply iconmask if provided
        iconMask?.let { maskName ->
            val maskResId = resources.getIdentifier(maskName, "drawable", packageName)
            if (maskResId != 0) {
                runCatching {
                    val maskDrawable = ResourcesCompat.getDrawable(resources, maskResId, null)
                    val maskBitmap = maskDrawable?.toBitmap(size, size)
                    if (maskBitmap != null) {
                        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                        }
                        canvas.drawBitmap(maskBitmap, 0f, 0f, paint)
                    }
                }
            }
        }

        // Apply iconupon overlay if provided
        iconUpon?.let { uponName ->
            val uponResId = resources.getIdentifier(uponName, "drawable", packageName)
            if (uponResId != 0) {
                runCatching {
                    ResourcesCompat.getDrawable(resources, uponResId, null)?.let { upon ->
                        upon.setBounds(0, 0, size, size)
                        upon.draw(canvas)
                    }
                }
            }
        }

        // Apply shape mask
        val masked = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val maskCanvas = Canvas(masked)
        maskCanvas.clipPath(shape.maskPath(size.toFloat(), size.toFloat()))
        maskCanvas.drawBitmap(result, 0f, 0f, null)

        return masked
    }
}
