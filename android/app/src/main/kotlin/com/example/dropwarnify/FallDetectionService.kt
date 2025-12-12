package com.example.dropwarnify

import android.Manifest
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
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.sqrt

class FallDetectionService : Service(), SensorEventListener {

    companion object {
        private const val TAG = "FallDetectionService"
        private const val CHANNEL_ID = "fall_detection_channel"
        private const val NOTIFICATION_ID = 1001

        // thresholds (ajuste depois com calma)
        private const val FALL_THRESHOLD_G = 2.5f
        private const val NEAR_FALL_THRESHOLD_G = 1.8f

        // Caminho usado no DataLayer para evento de queda
        private const val PATH_LOG_FALL_EVENT = "/dropwarnify/log_fall_event"

        // Caminho para localização contínua do relógio
        private const val PATH_WATCH_LOCATION = "/dropwarnify/watch_location"

        // Caminho para snapshots de sensores do relógio (ACC + GYRO)
        private const val PATH_WATCH_SENSORS = "/dropwarnify/watch_sensors"
    }

    private lateinit var sensorManager: SensorManager

    // Sensores que vamos monitorar
    private var accelerometer: Sensor? = null
    private var linAccSensor: Sensor? = null
    private var gyroSensor: Sensor? = null
    private var gravitySensor: Sensor? = null

    // Últimas leituras de ACC e GYRO (para snapshot completo)
    private var accelX: Float = 0f
    private var accelY: Float = 0f
    private var accelZ: Float = 0f

    private var gyroX: Float = 0f
    private var gyroY: Float = 0f
    private var gyroZ: Float = 0f

    // Localização contínua
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    private var lastLocation: Location? = null

    private var lastTriggerTime: Long = 0
    private val minIntervalMs: Long = 5_000 // 5s

    // Rate limit para envio de localização ao celular
    private var lastLocationSendTime: Long = 0
    private val locationSendIntervalMs: Long = 10_000 // 10s

    // Rate limit para envio de snapshots de sensor
    private var lastSensorSendTime: Long = 0
    private val SENSOR_SEND_INTERVAL_MS: Long = 500 // 0.5s (2 Hz)

    // Contadores de amostras para debug por sensor
    private var accCount: Long = 0
    private var linAccCount: Long = 0
    private var gyroCount: Long = 0
    private var gravCount: Long = 0

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

        // Inicializa todos os sensores disponíveis
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        linAccSensor = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        gyroSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        gravitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY)

        if (accelerometer == null) {
            Log.e(TAG, "Nenhum acelerômetro disponível neste dispositivo.")
            stopSelf()
            return
        }

        Log.d(TAG, "Registrando listeners dos sensores...")

        accelerometer?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME
            )
        }

        linAccSensor?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME
            )
        }

        gyroSensor?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME
            )
        }

        gravitySensor?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME
            )
        }

        // Inicializa cliente de localização nativa
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startLocationUpdates()
    }

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: parando serviço e removendo listeners")
        sensorManager.unregisterListener(this)

        locationCallback?.let {
            fusedLocationClient.removeLocationUpdates(it)
        }
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
    // ============ LOCALIZAÇÃO CONTÍNUA =================
    // ==================================================

    private fun startLocationUpdates() {
        Log.d(TAG, "startLocationUpdates() chamado")

        val hasFine =
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
        val hasCoarse =
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED

        if (!hasFine && !hasCoarse) {
            Log.w(TAG, "startLocationUpdates: SEM permissão de localização, abortando.")
            return
        } else {
            Log.d(
                TAG,
                "startLocationUpdates: permissão de localização OK (fine=$hasFine, coarse=$hasCoarse)"
            )
        }

        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            5_000L // intervalo desejado (5s)
        )
            .setMinUpdateIntervalMillis(2_000L) // mínimo 2s
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                Log.d(TAG, "onLocationResult: result=$result")

                val loc = result.lastLocation
                if (loc == null) {
                    Log.w(TAG, "onLocationResult: lastLocation == null")
                    return
                }

                lastLocation = loc
                Log.d(
                    TAG,
                    "📍 localização contínua: lat=${loc.latitude} lng=${loc.longitude} provider=${loc.provider}"
                )

                // envia localização para o celular com rate limit
                sendLocationToPhone(loc)
            }
        }

        try {
            Log.d(TAG, "startLocationUpdates: chamando requestLocationUpdates()...")
            fusedLocationClient.requestLocationUpdates(
                request,
                locationCallback!!,
                Looper.getMainLooper()
            )

            // Tenta pegar um snapshot inicial
            fusedLocationClient.lastLocation
                .addOnSuccessListener { loc ->
                    if (loc != null) {
                        lastLocation = loc
                        Log.d(
                            TAG,
                            "📍 snapshot inicial: lat=${loc.latitude} lng=${loc.longitude} provider=${loc.provider}"
                        )
                        sendLocationToPhone(loc)
                    } else {
                        Log.w(
                            TAG,
                            "lastLocation inicial == null (ainda sem fix de GPS no emulador?)"
                        )
                    }
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Erro ao obter lastLocation inicial", e)
                }
        } catch (se: SecurityException) {
            Log.e(TAG, "SecurityException ao solicitar updates de localização", se)
        } catch (e: Exception) {
            Log.e(TAG, "Erro inesperado em startLocationUpdates", e)
        }
    }

    private fun sendLocationToPhone(location: Location) {
        val now = System.currentTimeMillis()
        if (now - lastLocationSendTime < locationSendIntervalMs) {
            return
        }
        lastLocationSendTime = now

        val json = JSONObject().apply {
            put("timestamp", java.time.Instant.now().toString())
            put("origin", "watch-location")
            put("latitude", location.latitude)
            put("longitude", location.longitude)
            put("locationProvider", location.provider ?: "unknown")
            put("locationAccuracy", location.accuracy.toDouble())
        }

        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.w(TAG, "Nenhum nó conectado para enviar localização.")
                }
                for (node in nodes) {
                    Wearable.getMessageClient(this)
                        .sendMessage(
                            node.id,
                            PATH_WATCH_LOCATION,
                            json.toString().toByteArray(Charsets.UTF_8)
                        )
                        .addOnSuccessListener {
                            Log.d(TAG, "Localização enviada ao phone (node=${node.id})")
                        }
                        .addOnFailureListener { e ->
                            Log.e(TAG, "Falha ao enviar localização", e)
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Erro ao obter nós conectados para localização", e)
            }
    }

    // ==================================================
    // =============== SENSOR LISTENER ==================
    // ==================================================

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accCount++

                accelX = event.values[0]
                accelY = event.values[1]
                accelZ = event.values[2]

                if (accCount % 20L == 0L) {
                    Log.d(TAG, "[ACC] n=$accCount  acc=($accelX, $accelY, $accelZ)")
                }

                val accelTotal = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ)
                val magnitudeG = accelTotal / 9.81f

                // Sempre manda snapshot (com rate limit separado)
                sendSensorSnapshotToPhone()

                // Detecção de queda respeita cooldown (minIntervalMs)
                val now = System.currentTimeMillis()
                if (now - lastTriggerTime < minIntervalMs) return

                when {
                    magnitudeG > FALL_THRESHOLD_G -> {
                        Log.d(TAG, "💥 Queda DETECTADA! magnitudeG=$magnitudeG")
                        lastTriggerTime = now
                        enviarEventoParaCelular(nearFall = false)
                    }

                    magnitudeG > NEAR_FALL_THRESHOLD_G -> {
                        Log.d(TAG, "⚠️ Quase queda detectada. magnitudeG=$magnitudeG")
                        lastTriggerTime = now
                        enviarEventoParaCelular(nearFall = true)
                    }
                }
            }

            Sensor.TYPE_LINEAR_ACCELERATION -> {
                linAccCount++
                val lx = event.values[0]
                val ly = event.values[1]
                val lz = event.values[2]
                if (linAccCount % 20L == 0L) {
                    Log.d(TAG, "[LIN] n=$linAccCount  linAcc=($lx, $ly, $lz)")
                }
            }

            Sensor.TYPE_GYROSCOPE -> {
                gyroCount++
                gyroX = event.values[0]
                gyroY = event.values[1]
                gyroZ = event.values[2]

                if (gyroCount % 20L == 0L) {
                    Log.d(TAG, "[GYRO] n=$gyroCount  gyro=($gyroX, $gyroY, $gyroZ)")
                }
                // Não precisa mandar snapshot aqui: ACC já chama sendSensorSnapshotToPhone()
            }

            Sensor.TYPE_GRAVITY -> {
                gravCount++
                val gx = event.values[0]
                val gy = event.values[1]
                val gz = event.values[2]
                if (gravCount % 20L == 0L) {
                    Log.d(TAG, "[GRAV] n=$gravCount  gravity=($gx, $gy, $gz)")
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // não utilizado
    }

    // ==================================================
    // =========== SNAPSHOT DE SENSORES PRO PHONE =======
    // ==================================================

    private fun sendSensorSnapshotToPhone() {
        val now = System.currentTimeMillis()
        if (now - lastSensorSendTime < SENSOR_SEND_INTERVAL_MS) {
            return
        }
        lastSensorSendTime = now

        // Usa os últimos valores conhecidos de ACC + GYRO
        val accelTotal = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ)
        val magnitudeG = accelTotal / 9.81f

        val gyroTotal = sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ)

        val json = JSONObject().apply {
            put("timestamp", java.time.Instant.now().toString())
            put("origin", "watch-sensor")
            put("magnitudeG", magnitudeG.toDouble())

            put("accelX", accelX.toDouble())
            put("accelY", accelY.toDouble())
            put("accelZ", accelZ.toDouble())

            put("gyroX", gyroX.toDouble())
            put("gyroY", gyroY.toDouble())
            put("gyroZ", gyroZ.toDouble())
            put("gyroTotal", gyroTotal.toDouble())
        }

        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.w(TAG, "Nenhum nó conectado para enviar snapshot de sensor.")
                }
                for (node in nodes) {
                    Wearable.getMessageClient(this)
                        .sendMessage(
                            node.id,
                            PATH_WATCH_SENSORS,
                            json.toString().toByteArray(Charsets.UTF_8)
                        )
                        .addOnSuccessListener {
                            Log.d(TAG, "Snapshot de sensor enviado ao phone (node=${node.id})")
                        }
                        .addOnFailureListener { e ->
                            Log.e(TAG, "Falha ao enviar snapshot de sensor", e)
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Erro ao obter nós conectados para sensores", e)
            }
    }

    // ==================================================
    // =============== ENVIO PRO CELULAR ================
    // ==================================================

    private fun enviarEventoParaCelular(nearFall: Boolean) {
        val locationSnapshot = lastLocation
        enviarEventoComJson(nearFall, locationSnapshot)
    }

    private fun enviarEventoComJson(nearFall: Boolean, location: Location?) {
        val json = JSONObject().apply {
            put("timestamp", java.time.Instant.now().toString())
            put("simulated", false)
            put("nearFall", nearFall)
            put("destinos", JSONArray())
            put("origin", "watch")
            put("statusEnvio", "desconhecido")

            if (location != null) {
                put("latitude", location.latitude)
                put("longitude", location.longitude)
                put("locationProvider", location.provider ?: "unknown")
                put("locationAccuracy", location.accuracy.toDouble())
            }
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
