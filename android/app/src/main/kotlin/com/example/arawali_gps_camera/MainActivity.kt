package com.example.arawali_gps_camera

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioManager
import android.media.ToneGenerator
import android.view.SoundEffectConstants

class MainActivity : FlutterActivity() {
    private val CHANNEL = "arawali_gps_camera/sound"
    private var toneGen: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
        } catch (e: Exception) {}

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playClick" -> {
                    try {
                        window.decorView.playSoundEffect(SoundEffectConstants.CLICK)
                        toneGen?.startTone(ToneGenerator.TONE_PROP_BEEP, 35)
                    } catch (e: Exception) {}
                    result.success(true)
                }
                "playShutter" -> {
                    try {
                        toneGen?.startTone(ToneGenerator.TONE_PROP_BEEP2, 90)
                    } catch (e: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
