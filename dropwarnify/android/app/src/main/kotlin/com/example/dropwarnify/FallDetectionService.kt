package com.example.dropwarnify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject

class FallDetectionService : Service(), SensorEventListener {

    companion object {
        private const val TAG = "FallDetectionService"
        private const val CHANNEL_ID = "fall_detection_channel"
        private const val NOTIFICATION_ID = 1001

        // thresholds (ajuste depois com calma)
        private const val FALL_THRESHOLD_G = 2.5f
        private const val NEAR_FALL_THRESHOLD_G = 1.8f

        // Caminho usado no DataLayer
        private const val PATH_LOG_FALL_EVENT = "/dropwarnify/log_fall_event"
    }

    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null

    private var lastTriggerTime: Long = 0
    private val minIntervalMs: Long = 5_000 // 5s

    // 🔹 Contador de amostras para debug
    private var sampleCount: Long = 0

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate: iniciando serviço de detecção de quedas")

        if (!isWatchDevice()) {
            Log.d(TAG, "Não é dispositivo Wear, encerrando serviço.")
            stopSelf()
            return
        }

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        if (accelerometer == null) {
            Log.e(TAG, "Nenhum acelerômetro disponível neste dispositivo.")
            stopSelf()
            return
        }

        Log.d(TAG, "Registrando listener do acelerômetro...")
        sensorManager.registerListener(
            this,
            accelerometer,
            SensorManager.SENSOR_DELAY_GAME
        )
    }

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: parando serviço e removendo listener")
        sensorManager.unregisterListener(this)
    }

    override fun onBind(intent: android.content.Intent?): IBinder? = null

    private fun isWatchDevice(): Boolean {
        val pm = packageManager
        val isWatchFeature = pm.hasSystemFeature(PackageManager.FEATURE_WATCH)
        val isRound = resources.configuration.isScreenRound
        return isWatchFeature || isRound
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Monitor de quedas",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Serviço de detecção de quedas em wearable"
            }

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("DropWarnify")
            .setContentText("Monitorando quedas no relógio.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .build()
    }

    // ==================================================
    // =============== SENSOR LISTENER ==================
    // ==================================================

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return

        val ax = event.values[0]
        val ay = event.values[1]
        val az = event.values[2]

        // 🔹 Contagem de amostras
        sampleCount++
        if (sampleCount % 50L == 0L) {
            Log.d(TAG, "amostras=$sampleCount  acc=($ax, $ay, $az)")
        }

        // magnitude aproximada em “g”
        val magnitude = Math.sqrt(
            (ax * ax + ay * ay + az * az).toDouble()
        ).toFloat() / 9.81f

        val now = System.currentTimeMillis()
        if (now - lastTriggerTime < minIntervalMs) return

        when {
            magnitude > FALL_THRESHOLD_G -> {
                Log.d(TAG, "💥 Queda DETECTADA! magnitude=$magnitude")
                lastTriggerTime = now
                enviarEventoParaCelular(false)
            }
            magnitude > NEAR_FALL_THRESHOLD_G -> {
                Log.d(TAG, "⚠️ Quase queda detectada. magnitude=$magnitude")
                lastTriggerTime = now
                enviarEventoParaCelular(true)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // não utilizado
    }

    // ==================================================
    // =============== ENVIO PRO CELULAR ================
    // ==================================================

    private fun enviarEventoParaCelular(nearFall: Boolean) {
        val json = JSONObject().apply {
            put("timestamp", java.time.Instant.now().toString())
            put("simulated", false)
            put("nearFall", nearFall)
            put("destinos", JSONArray())
            put("origin", "watch")
            put("statusEnvio", "desconhecido")
        }

        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.e(TAG, "Nenhum dispositivo pareado encontrado para envio.")
                }
                for (node in nodes) {
                    Wearable.getMessageClient(this)
                        .sendMessage(
                            node.id,
                            PATH_LOG_FALL_EVENT,
                            json.toString().toByteArray(Charsets.UTF_8)
                        )
                        .addOnSuccessListener {
                            Log.d(TAG, "Evento enviado ao telefone (node=${node.id})")
                        }
                        .addOnFailureListener { e ->
                            Log.e(TAG, "Falha ao enviar evento de queda", e)
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Erro ao obter nós conectados", e)
            }
    }
}
