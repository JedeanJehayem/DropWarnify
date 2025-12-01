package com.example.dropwarnify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable

class MainActivity : FlutterActivity(),
    MessageClient.OnMessageReceivedListener {

    private val CHANNEL = "br.com.dropwarnify/wear_contacts"
    private val SERVICE_CHANNEL = "br.com.dropwarnify/wear_service"

    private lateinit var methodChannel: MethodChannel

    // Receiver para eventos de queda (caso o phone envie algo de volta via broadcast)
    private var fallEventReceiver: BroadcastReceiver? = null

    companion object {
        private const val TAG = "WearMainActivity"

        private const val PATH_GET_CONTACTS = "/dropwarnify/get_contacts"
        private const val PATH_CONTACTS_RESPONSE = "/dropwarnify/contacts"

        // caminho para enviar/receber evento de queda via Data Layer
        private const val PATH_LOG_FALL_EVENT = "/dropwarnify/log_fall_event"
    }

    /** Helper pra saber se está rodando num relógio (Wear OS) */
    private fun isWatchDevice(): Boolean {
        val pm = packageManager
        val isWatchFeature = pm.hasSystemFeature(PackageManager.FEATURE_WATCH)
        val isRound = resources.configuration.isScreenRound
        return isWatchFeature || isRound
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // Canal de contatos + eventos de queda (bridge com WearContactsBridge)
        methodChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {

                // Flutter pedindo ao relógio para requisitar contatos ao celular
                "requestContactsFromPhone" -> {
                    requestContactsFromPhone()
                    result.success(null)
                }

                // Flutter enviando um FallEvent para o celular registrar no histórico
                "send_fall_event_to_phone" -> {
                    val map = call.arguments as? Map<String, Any?>
                    if (map != null) {
                        sendFallEventToPhone(map)
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // Canal específico para controlar o serviço nativo de detecção de quedas no relógio
        val serviceChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            SERVICE_CHANNEL
        )

        serviceChannel.setMethodCallHandler { call, result ->
            when (call.method) {

                "start_fall_service" -> {
                    // só faz sentido rodar isso em dispositivo Wear
                    if (isWatchDevice()) {
                        val intent = Intent(this, FallDetectionService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        Log.d(TAG, "start_fall_service: FallDetectionService solicitado")
                    } else {
                        Log.w(TAG, "start_fall_service chamado em dispositivo não-Wear")
                    }
                    result.success(null)
                }

                "stop_fall_service" -> {
                    val intent = Intent(this, FallDetectionService::class.java)
                    stopService(intent)
                    Log.d(TAG, "stop_fall_service: FallDetectionService interrompido")
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // registra o receiver DEPOIS de o methodChannel existir
        registerFallEventReceiver()
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun onPause() {
        super.onPause()
        Wearable.getMessageClient(this).removeListener(this)
    }

    override fun onDestroy() {
        // remove o receiver pra não vazar
        if (fallEventReceiver != null) {
            unregisterReceiver(fallEventReceiver)
            fallEventReceiver = null
        }
        super.onDestroy()
    }

    /**
     * Registra o BroadcastReceiver que receberia evento de queda
     * enviado por algum serviço do lado do celular (se usado).
     */
    private fun registerFallEventReceiver() {
        if (fallEventReceiver != null) return // já registrado

        fallEventReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                // Se você tiver um ACTION_FALL_EVENT_FROM_WATCH no phone e mandar broadcast de volta,
                // pode tratar aqui. Se não estiver usando, isso não atrapalha.
                val action = intent?.action
                Log.d(TAG, "Broadcast recebido em $TAG: $action")
            }
        }

        // Se não tiver uma ACTION específica, você pode remover esse receiver todo
        // ou ajustar para uma action real.
        val filter = IntentFilter("br.com.dropwarnify.ACTION_FALL_EVENT_FROM_WATCH")

        // Android 13+ exige flag RECEIVER_EXPORTED / RECEIVER_NOT_EXPORTED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                fallEventReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            // versões anteriores usam a API antiga
            registerReceiver(fallEventReceiver, filter)
        }
    }

    /**
     * Flutter → relógio → celular
     * Pedido para obter contatos.
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
     * Flutter → relógio → celular
     * Envia o FallEvent convertido em JSON para o celular registrar no histórico.
     */
    private fun sendFallEventToPhone(map: Map<String, Any?>) {
        val json = org.json.JSONObject(map).toString()
        Log.d(TAG, "Enviando evento de queda ao celular: $json")

        val dataBytes = json.toByteArray(Charsets.UTF_8)

        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (node in nodes) {
                    Log.d(TAG, "Enviando ao node ${node.id}...")
                    Wearable.getMessageClient(this).sendMessage(
                        node.id,
                        PATH_LOG_FALL_EVENT,
                        dataBytes
                    )
                }
            }
    }

    /**
     * Celular → relógio → Flutter
     * Passa a lista de contatos recebida para o Flutter.
     * E (se usado) eventos de queda vindos direto via Data Layer.
     */
    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Mensagem recebida no relógio: ${messageEvent.path}")

        when (messageEvent.path) {
            PATH_CONTACTS_RESPONSE -> {
                val json = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Contatos recebidos do celular: $json")

                // envia para o Flutter
                methodChannel.invokeMethod("onContactsReceived", json)
            }

            // evento de queda vindo direto via Data Layer
            PATH_LOG_FALL_EVENT -> {
                val json = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Evento de queda recebido direto via Data Layer: $json")

                // envia para o Flutter (WearSensorMonitor/WearContactsBridge tratam isso)
                methodChannel.invokeMethod("onFallEventFromWatch", json)
            }

            else -> {
                // outros paths, se aparecerem no futuro
            }
        }
    }
}
