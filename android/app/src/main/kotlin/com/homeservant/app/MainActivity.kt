package com.example.homeservant

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.homeservant/app_icon"

    // Alias suffix (relative to the app's package) for each theme's icon.
    // "null" (Classic) means: leave MainActivity itself enabled and every
    // alias disabled, since Classic is the app's default/primary icon.
    private val aliases = mapOf(
        "Midnight" to ".MidnightIcon",
        "Sand" to ".SandIcon",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method != "setAppIcon") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val name = call.argument<String>("name")
            setActiveIcon(name)
            result.success(true)
        }
    }

    private fun setActiveIcon(name: String?) {
        val pm = packageManager
        val targetAlias = aliases[name]

        // Enable/disable MainActivity itself: only "on" when Classic (no alias) is selected.
        setComponentEnabled(pm, ComponentName(this, MainActivity::class.java), targetAlias == null)

        // Enable exactly the matching alias, disable the rest.
        for (alias in aliases.values) {
            setComponentEnabled(pm, ComponentName(this, "com.example.homeservant$alias"), alias == targetAlias)
        }
    }

    private fun setComponentEnabled(pm: PackageManager, component: ComponentName, enabled: Boolean) {
        pm.setComponentEnabledSetting(
            component,
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
