package com.nadr.mobile

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nadr/heading_capability")
            .setMethodCallHandler { call, result ->
                if (call.method != "hasNorthReferencedHeading") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                // flutter_compass uses TYPE_ROTATION_VECTOR or accelerometer +
                // magnetic field. A game rotation vector is not north referenced.
                val rotationVector = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                val magneticField = sensors.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                result.success(rotationVector != null || (accelerometer != null && magneticField != null))
            }
    }
}
