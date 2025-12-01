package com.example.dropwarnify

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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

        // ACTION do broadcast que vamos mandar para o Flutter
        const val ACTION_FALL_EVENT_FROM_WATCH =
            "com.example.dropwarnify.FALL_EVENT_FROM_WATCH"

        // extra com o JSON do evento
        const val EXTRA_FALL_EVENT_JSON = "fall_event_json"
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        // 🚨 Evita que o WATCH responda a si mesmo.
        // Só queremos que este serviço responda quando estiver rodando NO TELEFONE.
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

                // monta JSON com os contatos salvos pelo Flutter (SharedPreferences)
                val json = buildContactsJson()

                // responde para o nó que pediu (relógio)
                Wearable.getMessageClient(this)
                    .sendMessage(
                        messageEvent.sourceNodeId,
                        PATH_CONTACTS_RESPONSE,
                        json.toByteArray(Charsets.UTF_8)
                    )
            }

            // novo: evento de queda vindo do relógio
            PATH_LOG_FALL_EVENT -> {
                val jsonEvent = String(messageEvent.data, Charsets.UTF_8)

                // 🔥 garante que o JSON tenha origin = "watch"
                val enrichedJson = try {
                    val obj = JSONObject(jsonEvent)
                    if (!obj.has("origin")) {
                        obj.put("origin", "watch")
                    }
                    obj.toString()
                } catch (e: Exception) {
                    Log.e(TAG, "Erro ao enriquecer JSON de FallEvent com origin=watch", e)
                    // se der erro, segue com o original mesmo
                    jsonEvent
                }

                Log.d(TAG, "Recebido evento de queda do relógio: $enrichedJson")
                notifyFlutterFallEvent(enrichedJson)
            }

            else -> {
                // ignora outros paths
            }
        }
    }

    /**
     * Envia um broadcast para o app Flutter com o JSON do FallEvent.
     * Quem vai realmente gravar no SharedPreferences é o Flutter (via MethodChannel).
     */
    private fun notifyFlutterFallEvent(jsonEvent: String) {
        val intent = Intent(ACTION_FALL_EVENT_FROM_WATCH).apply {
            putExtra(EXTRA_FALL_EVENT_JSON, jsonEvent)
        }
        Log.d(TAG, "Enviando broadcast de evento de queda para o Flutter: $jsonEvent")
        sendBroadcast(intent)
    }

    /**
     * Lê os contatos salvos pelo Flutter nas SharedPreferences
     * "FlutterSharedPreferences" e monta um JSON:
     * [ { "name": "Fulano", "phone": "11999999999" }, ... ]
     *
     * Aqui tratamos dois formatos possíveis:
     *  - StringList do Flutter salva como String JSON
     *  - (legado) StringSet
     */
    private fun buildContactsJson(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val list = mutableListOf<Pair<String, String>>()

        // Pega o valor cru, sem forçar tipo, para evitar ClassCastException
        val rawEntry = prefs.all["flutter.emergency_contacts"]

        when (rawEntry) {
            is Set<*> -> {
                // Caso antigo: armazenado como Set<String>
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
                // Novo formato: StringList do Flutter salva como String com prefixo
                Log.d(TAG, "Lendo emergency_contacts como String JSON (com prefixo possivelmente)")
                try {
                    var jsonString = rawEntry

                    // Ex.: "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!["{...}"]"
                    val bangIndex = jsonString.indexOf('!')
                    if (bangIndex >= 0 && bangIndex < jsonString.length - 1) {
                        jsonString = jsonString.substring(bangIndex + 1) // pega só a parte a partir do '['
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

        // Fallback pro modelo antigo (contato único)
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
