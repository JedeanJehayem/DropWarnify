package com.example.dropwarnify

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONArray
import org.json.JSONObject

class PhoneWearContactsService : WearableListenerService() {

    companion object {
        private const val TAG = "PhoneWearContactsService"
        private const val PATH_GET_CONTACTS = "/dropwarnify/get_contacts"
        private const val PATH_CONTACTS_RESPONSE = "/dropwarnify/contacts"
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        if (messageEvent.path == PATH_GET_CONTACTS) {
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
    }

    /**
     * Lê os contatos salvos pelo Flutter nas SharedPreferences
     * "FlutterSharedPreferences" e monta um JSON:
     * [ { "name": "Fulano", "phone": "11999999999" }, ... ]
     */
    private fun buildContactsJson(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val list = mutableListOf<Pair<String, String>>()

        // stringList do Flutter vira um Set<String> aqui
        val set = prefs.getStringSet("flutter.emergency_contacts", null)

        if (set != null && set.isNotEmpty()) {
            for (item in set) {
                try {
                    // cada item é um JSON do EmergencyContact.toJson()
                    val obj = JSONObject(item)
                    val name = obj.optString("name", "")
                    val phone = obj.optString("phone", "")
                    if (phone.isNotBlank()) {
                        list.add(name to phone)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Falha ao parsear contato: $item", e)
                }
            }
        } else {
            // fallback pro modelo antigo (contato único)
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
