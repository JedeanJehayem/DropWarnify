package com.example.dropwarnify

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONArray
import org.json.JSONObject

class PhoneWearContactsService : WearableListenerService() {

    companion object {
        private const val TAG = "PhoneWearContactsService"

        // PATHs de comunicação
        private const val PATH_GET_CONTACTS = "/dropwarnify/get_contacts"
        private const val PATH_CONTACTS_RESPONSE = "/dropwarnify/contacts"

        // path para registrar evento de queda vindo do relógio
        private const val PATH_LOG_FALL_EVENT = "/dropwarnify/log_fall_event"

        // path para atualização de localização contínua do relógio
        private const val PATH_WATCH_LOCATION = "/dropwarnify/watch_location"

        // path para snapshots de sensor do relógio
        private const val PATH_WATCH_SENSORS = "/dropwarnify/watch_sensors"

        // ACTION do broadcast que vamos mandar para o Flutter (queda)
        const val ACTION_FALL_EVENT_FROM_WATCH =
            "com.example.dropwarnify.FALL_EVENT_FROM_WATCH"

        // extra com o JSON do evento de queda
        const val EXTRA_FALL_EVENT_JSON = "fall_event_json"

        // ACTION/EXTRA da localização do relógio
        const val ACTION_WATCH_LOCATION_UPDATED =
            "com.example.dropwarnify.WATCH_LOCATION_UPDATED"
        const val EXTRA_WATCH_LOCATION_JSON = "watch_location_json"

        // ACTION/EXTRA dos snapshots de sensor (não estamos mais usando broadcast pra isso,
        // mas mantém se quiser reaproveitar depois)
        const val ACTION_WATCH_SENSOR_SNAPSHOT =
            "com.example.dropwarnify.WATCH_SENSOR_SNAPSHOT"
        const val EXTRA_WATCH_SENSOR_JSON = "watch_sensor_json"
    }

    // Handler pra postar coisas na main thread do app (obrigatório pro MethodChannel)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        // só deve rodar no TELEFONE
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
                    if (!obj.has("origin")) {
                        obj.put("origin", "watch")
                    }
                    obj.toString()
                } catch (e: Exception) {
                    Log.e(TAG, "Erro ao enriquecer JSON de FallEvent com origin=watch", e)
                    jsonEvent
                }

                Log.d(TAG, "Recebido evento de queda do relógio: $enrichedJson")
                notifyFlutterFallEvent(enrichedJson)
            }

            // localização contínua do relógio
            PATH_WATCH_LOCATION -> {
                val jsonLoc = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Recebida localização do relógio: $jsonLoc")
                notifyFlutterWatchLocation(jsonLoc)
            }

            // snapshot de sensor do relógio
            PATH_WATCH_SENSORS -> {
                val jsonSensor = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Recebido snapshot de sensor do relógio: $jsonSensor")
                notifyFlutterWatchSensor(jsonSensor)
            }

            else -> {
                // ignora outros paths
            }
        }
    }

    private fun notifyFlutterFallEvent(jsonEvent: String) {
        val intent = Intent(ACTION_FALL_EVENT_FROM_WATCH).apply {
            putExtra(EXTRA_FALL_EVENT_JSON, jsonEvent)
        }
        Log.d(TAG, "Enviando broadcast de evento de queda para o Flutter: $jsonEvent")
        sendBroadcast(intent)
    }

    // broadcast de localização do relógio
    private fun notifyFlutterWatchLocation(jsonLoc: String) {
        val intent = Intent(ACTION_WATCH_LOCATION_UPDATED).apply {
            putExtra(EXTRA_WATCH_LOCATION_JSON, jsonLoc)
        }
        Log.d(TAG, "Enviando broadcast de localização do relógio para o Flutter: $jsonLoc")
        sendBroadcast(intent)
    }

    // Envia snapshot de sensor direto pro Flutter via MethodChannel na MAIN THREAD
    private fun notifyFlutterWatchSensor(jsonSensor: String) {
        Log.d(TAG, "Enviando snapshot de sensor para o Flutter via MethodChannel: $jsonSensor")

        val channel = MainActivity.sensorsChannel
        if (channel == null) {
            Log.w(TAG, "sensorsChannel nulo - Flutter ainda não inicializado ou app não está em primeiro plano.")
            return
        }

        // Garante que a chamada ao MethodChannel acontece na main thread
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
                        if (phone.isNotBlank()) {
                            list.add(name to phone)
                        }
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
                        if (phone.isNotBlank()) {
                            list.add(name to phone)
                        }
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
            if (phone.isNotBlank()) {
                list.add(name to phone)
            }
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
