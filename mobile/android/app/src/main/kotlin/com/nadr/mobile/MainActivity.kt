package com.nadr.mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var stepDetector: Sensor? = null
    private var stepEventSink: EventChannel.EventSink? = null
    private var awaitingStepPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepDetector = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nadr/heading_capability")
            .setMethodCallHandler { call, result ->
                if (call.method != "hasNorthReferencedHeading") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // flutter_compass uses TYPE_ROTATION_VECTOR or accelerometer +
                // magnetic field. A game rotation vector is not north referenced.
                val rotationVector = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                val magneticField = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                result.success(rotationVector != null || (accelerometer != null && magneticField != null))
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "nadr/step_detector")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stepEventSink = events
                    startStepDetector()
                }

                override fun onCancel(arguments: Any?) {
                    stopStepDetector()
                    stepEventSink = null
                }
            })
    }

    private fun startStepDetector() {
        val detector = stepDetector
        if (detector == null) {
            stepEventSink?.error("step_detector_unavailable", "Android step detector is absent", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
        ) {
            if (!awaitingStepPermission) {
                awaitingStepPermission = true
                requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), STEP_PERMISSION_REQUEST)
            }
            return
        }
        val registered = sensorManager.registerListener(this, detector, SensorManager.SENSOR_DELAY_NORMAL)
        if (registered) {
            stepEventSink?.success(mapOf("type" to "ready"))
        } else {
            stepEventSink?.error("step_detector_registration_failed", "Android rejected step detector registration", null)
        }
    }

    private fun stopStepDetector() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type == Sensor.TYPE_STEP_DETECTOR && event.values.firstOrNull() == 1.0f) {
            stepEventSink?.success(mapOf("type" to "step"))
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STEP_PERMISSION_REQUEST) return
        awaitingStepPermission = false
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startStepDetector()
        } else {
            stepEventSink?.error("activity_recognition_denied", "Physical activity permission denied", null)
        }
    }

    override fun onDestroy() {
        if (::sensorManager.isInitialized) stopStepDetector()
        super.onDestroy()
    }

    companion object {
        private const val STEP_PERMISSION_REQUEST = 4701
    }
}
