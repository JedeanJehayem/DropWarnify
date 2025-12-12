package com.example.dropwarnify
import android.os.Bundle
import android.os.StrictMode
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
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
    private val SENSORS_CHANNEL = "br.com.dropwarnify/wear_sensors"

    private lateinit var methodChannel: MethodChannel

    // Receivers
    private var fallEventReceiver: BroadcastReceiver? = null
    private var watchLocationReceiver: BroadcastReceiver? = null
    private var watchSensorReceiver: BroadcastReceiver? = null

    companion object {
        private const val TAG = "WearMainActivity"

        const val PATH_GET_CONTACTS = "/dropwarnify/get_contacts"
        const val PATH_CONTACTS_RESPONSE = "/dropwarnify/contacts"
        const val PATH_LOG_FALL_EVENT = "/dropwarnify/log_fall_event"

        // 🔹 Canal de sensores acessível pelo serviço (PhoneWearContactsService)
        @JvmStatic
        var sensorsChannel: MethodChannel? = null
    }

    private fun isWatchDevice(): Boolean {
        val pm = packageManager
        val isWatchFeature = pm.hasSystemFeature(PackageManager.FEATURE_WATCH)
        val isRound = resources.configuration.isScreenRound
        return isWatchFeature || isRound
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ⚠️ HACK: permitir rede na main thread (útil só para DEV / testes)
        val policy = StrictMode.ThreadPolicy.Builder()
            .permitAll()
            .build()
        StrictMode.setThreadPolicy(policy)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // Canal principal (contatos, quedas, localização)
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

        // Canal para start/stop do serviço de queda no relógio
        val serviceChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            SERVICE_CHANNEL
        )

        serviceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start_fall_service" -> {
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

        // 🔹 Canal específico para snapshots de sensor do relógio
        sensorsChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            SENSORS_CHANNEL
        )

        // Registra receivers
        registerFallEventReceiver()
        registerWatchLocationReceiver()
        registerWatchSensorReceiver()
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
        fallEventReceiver?.let {
            unregisterReceiver(it)
            fallEventReceiver = null
        }
        watchLocationReceiver?.let {
            unregisterReceiver(it)
            watchLocationReceiver = null
        }
        watchSensorReceiver?.let {
            unregisterReceiver(it)
            watchSensorReceiver = null
        }
        super.onDestroy()
    }

    private fun registerFallEventReceiver() {
        if (fallEventReceiver != null) return

        fallEventReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action
                Log.d(TAG, "Broadcast recebido em $TAG: $action")
                // hoje você não trata nada aqui; o fluxo de queda vem via DataLayer direto
            }
        }

        val filter = IntentFilter("br.com.dropwarnify.ACTION_FALL_EVENT_FROM_WATCH")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                fallEventReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(fallEventReceiver, filter)
        }
    }

    private fun registerWatchLocationReceiver() {
        if (watchLocationReceiver != null) return

        watchLocationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action
                if (action == PhoneWearContactsService.ACTION_WATCH_LOCATION_UPDATED) {
                    val json =
                        intent.getStringExtra(PhoneWearContactsService.EXTRA_WATCH_LOCATION_JSON)
                            ?: return
                    Log.d(TAG, "Broadcast de localização do relógio recebido: $json")

                    // manda direto para o Flutter (WearContactsBridge)
                    methodChannel.invokeMethod("onWatchLocationUpdated", json)
                }
            }
        }

        val filter = IntentFilter(PhoneWearContactsService.ACTION_WATCH_LOCATION_UPDATED)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                watchLocationReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(watchLocationReceiver, filter)
        }
    }

    private fun registerWatchSensorReceiver() {
        if (watchSensorReceiver != null) return

        watchSensorReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action
                if (action == PhoneWearContactsService.ACTION_WATCH_SENSOR_SNAPSHOT) {
                    val json =
                        intent.getStringExtra(PhoneWearContactsService.EXTRA_WATCH_SENSOR_JSON)
                            ?: return
                    Log.d(TAG, "Broadcast de snapshot de sensor recebido: $json")

                    // manda para o Flutter (WearSensorsBridge)
                    sensorsChannel?.invokeMethod("onWatchSensorSnapshot", json)
                }
            }
        }

        val filter = IntentFilter(PhoneWearContactsService.ACTION_WATCH_SENSOR_SNAPSHOT)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                watchSensorReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(watchSensorReceiver, filter)
        }
    }

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

    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Mensagem recebida no relógio: ${messageEvent.path}")

        when (messageEvent.path) {
            PATH_CONTACTS_RESPONSE -> {
                val json = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Contatos recebidos do celular: $json")
                methodChannel.invokeMethod("onContactsReceived", json)
            }

            PATH_LOG_FALL_EVENT -> {
                val json = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Evento de queda recebido direto via Data Layer: $json")
                methodChannel.invokeMethod("onFallEventFromWatch", json)
            }

            else -> {
                // outros paths futuros (/watch_sensors não é tratado aqui; vai pela service)
            }
        }
    }
}
