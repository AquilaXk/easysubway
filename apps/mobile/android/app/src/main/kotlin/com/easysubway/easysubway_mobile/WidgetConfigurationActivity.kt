package com.easysubway.easysubway_mobile

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class WidgetConfigurationActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        applyScreenOrientationPolicy(resources.configuration)
        super.onCreate(savedInstanceState)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyScreenOrientationPolicy(newConfig)
    }

    private fun applyScreenOrientationPolicy(configuration: Configuration) {
        requestedOrientation = if (configuration.smallestScreenWidthDp < 600) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    override fun getDartEntrypointFunctionName(): String = "configureMain"
}
