<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/vendor/autoload.php';

use PhpMqtt\Client\MqttClient;

function publicar_inicio_simulacao(array $payload): void
{
    $clientId = 'marsabirinto-php-' . bin2hex(random_bytes(4));

    $mqtt = new MqttClient(
        MQTT_BROKER,
        MQTT_PORT,
        $clientId,
        MqttClient::MQTT_3_1
    );

    $connected = false;

    try {
        $mqtt->connect(null, true);
        $connected = true;

        $message = json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);

        $mqtt->publish(
            MQTT_TOPIC,
            $message,
            MqttClient::QOS_AT_LEAST_ONCE
        );

        $mqtt->loop(true, true);
    } finally {
        if ($connected) {
            $mqtt->disconnect();
        }
    }
}