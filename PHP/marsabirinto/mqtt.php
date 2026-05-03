<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/vendor/autoload.php';

use PhpMqtt\Client\MqttClient;

function publicar_inicio_simulacao(array $payload): void
{
    $message = json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
    $ultimoErro = null;

    for ($tentativa = 1; $tentativa <= 5; $tentativa++) {
        $clientId = 'marsabirinto-php-' . bin2hex(random_bytes(16));

        $mqtt = new MqttClient(
            MQTT_BROKER,
            MQTT_PORT,
            $clientId,
            MqttClient::MQTT_3_1_1
        );

        $connected = false;

        try {
            $mqtt->connect(null, true);
            $connected = true;

            $mqtt->publish(
                MQTT_TOPIC,
                $message,
                MqttClient::QOS_AT_LEAST_ONCE
            );

            $mqtt->loop(true, true);
            return;

        } catch (Throwable $e) {
            $ultimoErro = $e;

            if ($tentativa < 5) {
                usleep($tentativa * 500000);
            }

        } finally {
            if ($connected) {
                try {
                    $mqtt->disconnect();
                } catch (Throwable $ex) {
                }
            }
        }
    }

    throw new RuntimeException(
        'Falha ao enviar mensagem MQTT Start apos 5 tentativas: ' .
        ($ultimoErro ? $ultimoErro->getMessage() : 'erro desconhecido')
    );
}