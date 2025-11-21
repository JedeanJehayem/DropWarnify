package com.example.dropwarnify

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.android.gms.wearable.*

class MainActivity : FlutterActivity(), 
    MessageClient.OnMessageReceivedListener {

    private val CHANNEL = "br.com.dropwarnify/wear_contacts"

    private lateinit var methodChannel: MethodChannel

    companion object {
        private const val TAG = "WearMainActivity"
        private const val PATH_GET_CONTACTS = "/dropwarnify/get_contacts"
        private const val PATH_CONTACTS_RESPONSE = "/dropwarnify/contacts"
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        methodChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestContactsFromPhone" -> {
                    requestContactsFromPhone()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun onPause() {
        super.onPause()
        Wearable.getMessageClient(this).removeListener(this)
    }

    /**
     * Quando o Flutter pedir contatos, enviamos a requisição
     * para o celular via Data Layer.
     */
    private fun requestContactsFromPhone() {
        Log.d(TAG, "Enviando pedido GET_CONTACTS ao celular...")

        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (node in nodes) {
                    Wearable.getMessageClient(this).sendMessage(
                        node.id,
                        PATH_GET_CONTACTS,
                        ByteArray(0)
                    )
                }
            }
    }

    /**
     * Quando o celular responder com PATH_CONTACTS_RESPONSE,
     * repassamos ao Flutter.
     */
    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Mensagem recebida no relógio: ${messageEvent.path}")

        if (messageEvent.path == PATH_CONTACTS_RESPONSE) {
            val json = String(messageEvent.data, Charsets.UTF_8)
            Log.d(TAG, "Contatos recebidos do celular: $json")

            // envia para o Flutter
            methodChannel.invokeMethod("onContactsReceived", json)
        }
    }
}
