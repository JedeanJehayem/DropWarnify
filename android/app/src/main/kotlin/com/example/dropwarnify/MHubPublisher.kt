package com.example.dropwarnify

import android.util.Log
import br.pucrio.inf.lac.mobilehub.core.MobileHub
import br.pucrio.inf.lac.mobilehub.core.domain.technologies.wlan.Topic
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

object MHubPublisher {

    private const val TAG = "MHubPublisher"

    /**
     * DRY_RUN = true:
     *  - não envia nada ao ContextNet
     *  - apenas loga o JSON final
     */
    private const val DRY_RUN = false

    // ===============================
    // === API PÚBLICA (DropWarnify)
    // ===============================

    fun publishFallEvent(rawJson: String) {
        val event = buildFallEvent(rawJson).apply {
            // se o processing-node usar appTopic pra filtrar, já vai correto
            put("appTopic", "DropWarnify.fall_event")
        }
        publish(event)
    }

    fun publishWatchLocation(rawJson: String) {
        val event = buildLocationEvent(rawJson).apply {
            put("appTopic", "DropWarnify.location_update")
        }
        publish(event)
    }

    fun publishSensorSnapshot(rawJson: String) {
        val event = buildSensorSnapshotEvent(rawJson).apply {
            put("appTopic", "DropWarnify.sensor_snapshot")
        }
        publish(event)
    }

    // ===============================
    // === BUILDERS DE EVENTO
    // ===============================

    private fun buildFallEvent(rawJson: String): JSONObject {
        val src = JSONObject(rawJson)

        val nearFall = src.optBoolean("nearFall", false)
        val fallDetected = !nearFall

        val data = JSONObject().apply {
            put("fallDetected", fallDetected)
            put("nearFall", nearFall)
            put("confidence", if (fallDetected) 0.9 else 0.6)

            if (src.has("latitude") && src.has("longitude")) {
                put(
                    "location",
                    JSONObject().apply {
                        put("lat", src.optDouble("latitude"))
                        put("lng", src.optDouble("longitude"))
                        put("accuracy", src.optDouble("locationAccuracy", -1.0))
                    }
                )
            }
        }

        return baseEvent(
            eventType = "FALL_DETECTED",
            severity = if (fallDetected) "HIGH" else "MODERATE",
            data = data
        )
    }

    private fun buildLocationEvent(rawJson: String): JSONObject {
        val src = JSONObject(rawJson)

        val data = JSONObject().apply {
            put(
                "location",
                JSONObject().apply {
                    put("lat", src.optDouble("latitude"))
                    put("lng", src.optDouble("longitude"))
                    put("accuracy", src.optDouble("locationAccuracy", -1.0))
                    put("provider", src.optString("locationProvider", "unknown"))
                }
            )
        }

        return baseEvent(
            eventType = "LOCATION_UPDATE",
            severity = "LOW",
            data = data
        )
    }

    private fun buildSensorSnapshotEvent(rawJson: String): JSONObject {
        val src = JSONObject(rawJson)

        val data = JSONObject().apply {
            put(
                "sensors",
                JSONObject().apply {
                    put("accelX", src.optDouble("accelX"))
                    put("accelY", src.optDouble("accelY"))
                    put("accelZ", src.optDouble("accelZ"))
                    put("magnitudeG", src.optDouble("magnitudeG"))

                    put("gyroX", src.optDouble("gyroX"))
                    put("gyroY", src.optDouble("gyroY"))
                    put("gyroZ", src.optDouble("gyroZ"))
                    put("gyroTotal", src.optDouble("gyroTotal"))
                }
            )
        }

        return baseEvent(
            eventType = "SENSOR_SNAPSHOT",
            severity = "INFO",
            data = data
        )
    }

    // ===============================
    // === BASE EVENT
    // ===============================

    private fun baseEvent(
        eventType: String,
        severity: String,
        data: JSONObject
    ): JSONObject {
        return JSONObject().apply {
            // IMPORTANTE: case-sensitive (não use lowercase)
            put("app", "DropWarnify")
            put("schemaVersion", 1)

            put("eventId", UUID.randomUUID().toString())
            put("eventType", eventType)
            put("severity", severity)

            put("timestamp", Instant.now().toString())

            put(
                "source",
                JSONObject().apply {
                    put("platform", "wearos")
                    put("deviceType", "watch")
                }
            )

            put("deviceId", "watch-local")
            put("data", data)
        }
    }

    // ===============================
    // === PUBLICAÇÃO (MOBILEHUB)
    // ===============================

    private fun publish(event: JSONObject) {
        if (DRY_RUN) {
            Log.d(TAG, "🟡 DRY_RUN | event=$event")
            return
        }

        try {
            // ✅ manda SOMENTE o evento.
            // ❌ NÃO crie envelope {topic, appTopic, payload, ts}
            // pois o gateway/pipeline já faz isso pro Kafka.
            val jsonToSend = event.toString()

            Log.d(TAG, "📦 Sending to MobileHub Topic.Data | head=${jsonToSend.take(160)}")
            MobileHub.sendMessage(Topic.Data, jsonToSend)

            Log.d(
                TAG,
                "✅ Sent to MobileHub | app=${event.optString("app")} appTopic=${event.optString("appTopic")}"
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send event to MobileHub", e)
        }
    }
}
