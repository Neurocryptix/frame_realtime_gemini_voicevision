package com.example.frame_realtime_gemini_voicevision

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val OAUTH_CHANNEL = "com.brilliantlabs.frame.realtime/oauth"
    private var oauthChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AiEdgeRagPlugin())
        
        // Setup OAuth callback channel
        oauthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OAUTH_CHANNEL)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.let { 
            if (it.action == Intent.ACTION_VIEW) {
                val uri: Uri? = it.data
                uri?.let { callbackUri ->
                    if (callbackUri.scheme == "com.brilliantlabs.frame.realtime" && 
                        callbackUri.host == "oauth") {
                        // Handle OAuth callback
                        oauthChannel?.invokeMethod("oauth_callback", callbackUri.toString())
                    }
                }
            }
        }
    }
}
