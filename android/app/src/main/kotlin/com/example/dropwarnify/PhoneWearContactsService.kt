package com.example.dropwarnify

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import br.pucrio.inf.lac.mobilehub.core.MobileHub
import br.pucrio.inf.lac.mrudp.MrudpWLAN
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONArray
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class PhoneWearContactsService : WearableListenerService() {

    companion object {
        private const val TAG = "PhoneWearContactsService"

        private const val PATH_GET_CONTACTS = "/dropwarnify/get_contacts"
        private const val PATH_CONTACTS_RESPONSE = "/dropwarnify/contacts"

        private const val PATH_LOG_FALL_EVENT = "/dropwarnify/log_fall_event"
        private const val PATH_WATCH_LOCATION = "/dropwarnify/watch_location"
        private const val PATH_WATCH_SENSORS = "/dropwarnify/watch_sensors"

        const val ACTION_FALL_EVENT_FROM_WATCH =
            "com.example.dropwarnify.FALL_EVENT_FROM_WATCH"
        const val EXTRA_FALL_EVENT_JSON = "fall_event_json"

        const val ACTION_WATCH_LOCATION_UPDATED =
            "com.example.dropwarnify.WATCH_LOCATION_UPDATED"
        const val EXTRA_WATCH_LOCATION_JSON = "watch_location_json"

        const val ACTION_WATCH_SENSOR_SNAPSHOT =
            "com.example.dropwarnify.WATCH_SENSOR_SNAPSHOT"
        const val EXTRA_WATCH_SENSOR_JSON = "watch_sensor_json"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ===============================
    // === MOBILEHUB (AUTO-START)
    // ===============================
    @Volatile private var mhubStarted: Boolean = false

    private val MhubIp: String = "10.0.2.2"
    private val MhubPort: Int = 6200

    // ===============================
    // === AUTO-RECONNECT (Backoff)
    // ===============================
    private val reconnectHandler = Handler(Looper.getMainLooper())
    private var reconnectScheduled = false
    private var reconnectAttempt = 0

    private fun nextReconnectDelayMs(): Long {
        val delays = longArrayOf(1_000, 2_000, 4_000, 8_000, 16_000, 30_000)
        val idx = reconnectAttempt.coerceAtMost(delays.lastIndex)
        return delays[idx]
    }

    private fun scheduleMHubReconnect(reason: String, error: Throwable? = null) {
        if (reconnectScheduled) return
        reconnectScheduled = true

        val delay = nextReconnectDelayMs()
        Log.w(TAG, "🔁 Agendando reconnect do MobileHub em ${delay}ms | reason=$reason", error)

        reconnectHandler.postDelayed({
            reconnectScheduled = false

            try { MobileHub.stop() } catch (_: Exception) { }
            mhubStarted = false

            reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(10)
            ensureMHubStarted()
        }, delay)
    }

    /**
     * Teste de rede: UDP cru (não é MrUDP), só pra ver tráfego na porta 6200.
     */
    private fun sendUdpTestOnce() {
        Thread {
            try {
                val addr = InetAddress.getByName(MhubIp)
                val msg = "PING_UDP_${System.currentTimeMillis()}"
                val data = msg.toByteArray(Charsets.UTF_8)
                val pkt = DatagramPacket(data, data.size, addr, MhubPort)

                DatagramSocket().use { it.send(pkt) }
                Log.d(TAG, "✅ UDPTEST sent to $MhubIp:$MhubPort | $msg")
            } catch (e: Exception) {
                Log.e(TAG, "❌ UDPTEST failed", e)
            }
        }.start()
    }

    // ===============================
    // === START + WAIT UNTIL STARTED
    // ===============================

    private val mhubCheckHandler = Handler(Looper.getMainLooper())
    private var mhubCheckScheduled = false
    private var mhubCheckTries = 0

    private fun scheduleStartedCheck() {
        if (mhubCheckScheduled) return
        mhubCheckScheduled = true
        mhubCheckTries = 0

        mhubCheckHandler.post(object : Runnable {
            override fun run() {
                mhubCheckTries++

                val startedNow = try { MobileHub.isStarted } catch (_: Throwable) { false }
                Log.d(TAG, "🔎 MobileHub.isStarted=$startedNow (try=$mhubCheckTries)")

                if (startedNow) {
                    mhubStarted = true
                    reconnectAttempt = 0
                    mhubCheckScheduled = false
                    Log.i(TAG, "✅ MobileHub READY (started=true). Agora pode publicar.")
                    return
                }

                if (mhubCheckTries >= 20) { // ~10s (500ms * 20)
                    mhubCheckScheduled = false
                    mhubStarted = false
                    Log.w(TAG, "⚠️ MobileHub não ficou READY a tempo. Vou agendar reconnect.")
                    scheduleMHubReconnect("MobileHub did not become started")
                    return
                }

                mhubCheckHandler.postDelayed(this, 500)
            }
        })
    }

    private fun ensureMHubStarted() {
        // Se já ficou ready, ok.
        val libStarted = try { MobileHub.isStarted } catch (_: Throwable) { false }
        if (mhubStarted && libStarted) return

        Log.d(TAG, "🔧 MHub target => ip=$MhubIp port=$MhubPort")

        try {
            val wlan = MrudpWLAN.Builder()
                .ipAddress(MhubIp)
                .port(MhubPort)
                .build()

            MobileHub.init(applicationContext)
                .setWlanTechnology(wlan)
                .setAutoConnect(true)
                .setLog(true)
                .build()

            MobileHub.start()

            // NÃO assume started aqui (é assíncrono)
            mhubStarted = false
            Log.d(TAG, "🚀 MobileHub.start() chamado. Aguardando ficar READY...")
            Log.d(TAG, "MobileHub.isStarted=${try { MobileHub.isStarted } catch (_: Throwable) { false }}")

            sendUdpTestOnce()
            scheduleStartedCheck()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start MobileHub automatically", e)
            mhubStarted = false
            scheduleMHubReconnect("start failed", e)
        }
    }

    // ===============================
    // === FLUSH A CADA 5s (Sensor/Loc)
    // ===============================
    private val publishHandler = Handler(Looper.getMainLooper())
    private var publishLoopStarted = false

    @Volatile private var lastLocJson: String? = null
    @Volatile private var lastSensorJson: String? = null

    private val PUBLISH_INTERVAL_MS = 5_000L

    private val publishRunnable = object : Runnable {
        override fun run() {
            try {
                if (!mhubStarted) {
                    ensureMHubStarted()
                    Log.w(TAG, "⏳ Ainda iniciando MobileHub... aguardando READY.")
                    return
                }

                val ready = try { MobileHub.isStarted } catch (_: Throwable) { false }
                if (!ready) {
                    Log.w(TAG, "⏳ MobileHub ainda não READY (mhubStarted=true, isStarted=false). Vou agendar reconnect.")
                    scheduleMHubReconnect("isStarted=false while mhubStarted=true")
                    return
                }
                val loc = lastLocJson.also { lastLocJson = null }
                val sensor = lastSensorJson.also { lastSensorJson = null }

                if (loc != null) {
                    MHubPublisher.publishWatchLocation(loc)
                    Log.d(TAG, "📤 Flush loc -> MHub (5s)")
                }

                if (sensor != null) {
                    MHubPublisher.publishSensorSnapshot(sensor)
                    Log.d(TAG, "📤 Flush sensor -> MHub (5s)")
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Falha no flush periódico para MobileHub", e)
                scheduleMHubReconnect("periodic flush failed", e)
            } finally {
                publishHandler.postDelayed(this, PUBLISH_INTERVAL_MS)
            }
        }
    }

    private fun startPublishLoopIfNeeded() {
        if (publishLoopStarted) return
        publishLoopStarted = true
        publishHandler.postDelayed(publishRunnable, PUBLISH_INTERVAL_MS)
        Log.d(TAG, "⏲️ Publish loop iniciado (intervalo=${PUBLISH_INTERVAL_MS}ms)")
    }

    override fun onDestroy() {
        super.onDestroy()
        try { publishHandler.removeCallbacks(publishRunnable) } catch (_: Exception) {}
        try { mhubCheckHandler.removeCallbacksAndMessages(null) } catch (_: Exception) {}
        publishLoopStarted = false
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        val isWatch =
            packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH) ||
                resources.configuration.isScreenRound

        if (isWatch) {
            Log.d(TAG, "Ignorando mensagem no watch — serviço só deve responder no telefone.")
            return
        }

        when (messageEvent.path) {

            PATH_GET_CONTACTS -> {
                Log.d(TAG, "Recebido pedido de contatos do relógio")
                val json = buildContactsJson()

                Wearable.getMessageClient(this)
                    .sendMessage(
                        messageEvent.sourceNodeId,
                        PATH_CONTACTS_RESPONSE,
                        json.toByteArray(Charsets.UTF_8)
                    )
            }

            PATH_LOG_FALL_EVENT -> {
                val jsonEvent = String(messageEvent.data, Charsets.UTF_8)

                val enrichedJson = try {
                    val obj = JSONObject(jsonEvent)
                    if (!obj.has("origin")) obj.put("origin", "watch")
                    obj.toString()
                } catch (e: Exception) {
                    Log.e(TAG, "Erro ao enriquecer JSON de FallEvent com origin=watch", e)
                    jsonEvent
                }

                Log.d(TAG, "🚨 Recebido evento de queda do relógio: $enrichedJson")

                notifyFlutterFallEvent(enrichedJson)

                ensureMHubStarted()
                val ready = mhubStarted && (try { MobileHub.isStarted } catch (_: Throwable) { false })
                if (!ready) {
                    Log.w(TAG, "⏳ MobileHub não READY ainda, não vou publicar FallEvent agora.")
                    return
                }

                try {
                    MHubPublisher.publishFallEvent(enrichedJson)
                    Log.d(TAG, "📤 FallEvent enviado IMEDIATO -> MHub")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Falha ao publicar FallEvent no MobileHub", e)
                    scheduleMHubReconnect("FallEvent publish failed", e)
                }
            }

            PATH_WATCH_LOCATION -> {
                val jsonLoc = String(messageEvent.data, Charsets.UTF_8)

                // 🔍 DIAGNÓSTICO
                Log.d(TAG, "LOCATION raw startsWithQuote=${jsonLoc.trim().startsWith("\"")}")
                Log.d(TAG, "LOCATION raw head=${jsonLoc.take(80)}")

                Log.d(TAG, "Recebida localização do relógio: $jsonLoc")

                notifyFlutterWatchLocation(jsonLoc)

                lastLocJson = jsonLoc
                startPublishLoopIfNeeded()
            }

            PATH_WATCH_SENSORS -> {
                val jsonSensor = String(messageEvent.data, Charsets.UTF_8)

                // 🔍 DIAGNÓSTICO
                Log.d(TAG, "SENSOR raw startsWithQuote=${jsonSensor.trim().startsWith("\"")}")
                Log.d(TAG, "SENSOR raw head=${jsonSensor.take(80)}")

                Log.d(TAG, "Recebido snapshot de sensor do relógio: $jsonSensor")

                notifyFlutterWatchSensor(jsonSensor)

                lastSensorJson = jsonSensor
                startPublishLoopIfNeeded()
            }

            else -> { }
        }
    }

    private fun notifyFlutterFallEvent(jsonEvent: String) {
        val intent = Intent(ACTION_FALL_EVENT_FROM_WATCH).apply {
            putExtra(EXTRA_FALL_EVENT_JSON, jsonEvent)
        }
        Log.d(TAG, "Enviando broadcast de evento de queda para o Flutter: $jsonEvent")
        sendBroadcast(intent)
    }

    private fun notifyFlutterWatchLocation(jsonLoc: String) {
        val intent = Intent(ACTION_WATCH_LOCATION_UPDATED).apply {
            putExtra(EXTRA_WATCH_LOCATION_JSON, jsonLoc)
        }
        Log.d(TAG, "Enviando broadcast de localização do relógio para o Flutter: $jsonLoc")
        sendBroadcast(intent)
    }

    private fun notifyFlutterWatchSensor(jsonSensor: String) {
        Log.d(TAG, "Enviando snapshot de sensor para o Flutter via MethodChannel: $jsonSensor")

        val channel = MainActivity.sensorsChannel
        if (channel == null) {
            Log.w(TAG, "sensorsChannel nulo - Flutter ainda não inicializado ou app não está em primeiro plano.")
            return
        }

        mainHandler.post {
            channel.invokeMethod("onWatchSensorSnapshot", jsonSensor)
        }
    }

    // ================= CONTATOS ==================

    private fun buildContactsJson(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val list = mutableListOf<Pair<String, String>>()

        val rawEntry = prefs.all["flutter.emergency_contacts"]

        when (rawEntry) {
            is Set<*> -> {
                Log.d(TAG, "Lendo emergency_contacts como Set<String>")
                for (itemAny in rawEntry) {
                    val item = itemAny as? String ?: continue
                    try {
                        val obj = JSONObject(item)
                        val name = obj.optString("name", "")
                        val phone = obj.optString("phone", "")
                        if (phone.isNotBlank()) list.add(name to phone)
                    } catch (e: Exception) {
                        Log.w(TAG, "Falha ao parsear contato (Set): $item", e)
                    }
                }
            }

            is String -> {
                Log.d(TAG, "Lendo emergency_contacts como String JSON (com prefixo possivelmente)")
                try {
                    var jsonString = rawEntry
                    val bangIndex = jsonString.indexOf('!')
                    if (bangIndex >= 0 && bangIndex < jsonString.length - 1) {
                        jsonString = jsonString.substring(bangIndex + 1)
                    }

                    val outerArray = JSONArray(jsonString)
                    for (i in 0 until outerArray.length()) {
                        val innerStr = outerArray.optString(i, null) ?: continue
                        val obj = JSONObject(innerStr)
                        val name = obj.optString("name", "")
                        val phone = obj.optString("phone", "")
                        if (phone.isNotBlank()) list.add(name to phone)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Erro ao interpretar emergency_contacts como JSONArray: $rawEntry", e)
                }
            }

            else -> {
                Log.d(TAG, "Nenhuma lista emergency_contacts encontrada, usando fallback antigo.")
            }
        }

        if (list.isEmpty()) {
            val name = prefs.getString("flutter.contato_nome", "") ?: ""
            val phone = prefs.getString("flutter.contato_telefone", "") ?: ""
            if (phone.isNotBlank()) list.add(name to phone)
        }

        val array = JSONArray()
        for ((name, phone) in list) {
            val obj = JSONObject()
            obj.put("name", name)
            obj.put("phone", phone)
            array.put(obj)
        }

        val jsonFinal = array.toString()
        Log.d(TAG, "Enviando contatos para relógio: $jsonFinal")
        return jsonFinal
    }
}
