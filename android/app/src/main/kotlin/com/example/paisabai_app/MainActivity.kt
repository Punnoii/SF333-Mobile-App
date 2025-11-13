package com.example.paisabai_app

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    private val diagnosticsChannel = "com.paisabai/diagnostics"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagnosticsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMemoryStats" -> result.success(collectMemoryStats())
                    else -> result.notImplemented()
                }
            }
    }

    private fun collectMemoryStats(): Map<String, Any> {
        val runtime = Runtime.getRuntime()
        val usedMemory = runtime.totalMemory() - runtime.freeMemory()
        val nativeHeapBytes = Debug.getNativeHeapAllocatedSize()
        val pssBytes = Debug.getPss() * 1024L
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(info)

        return mapOf(
            "residentSizeBytes" to usedMemory,
            "nativeHeapBytes" to nativeHeapBytes,
            "pssBytes" to pssBytes,
            "physicalMemoryBytes" to info.totalMem,
            "timestampMs" to System.currentTimeMillis(),
        )
    }
}
