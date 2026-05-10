<?php
declare(strict_types=1);

$appConfigPath = __DIR__ . '/config.json';
$appConfig = [];

if (is_file($appConfigPath)) {
    $decoded = json_decode((string)file_get_contents($appConfigPath), true);
    if (is_array($decoded)) {
        $appConfig = $decoded;
    }
}

$mysqlConfig = $appConfig['mysql'] ?? [];
$mqttConfig = $appConfig['mqtt'] ?? [];
$managerConfig = $appConfig['manager'] ?? [];

define('DB_HOST', (string)($mysqlConfig['host'] ?? '127.0.0.1'));
define('DB_PORT', (int)($mysqlConfig['port'] ?? 3306));
define('DB_NAME', (string)($mysqlConfig['database'] ?? 'Marsabirinto'));
define('DB_CHARSET', (string)($mysqlConfig['charset'] ?? 'utf8mb4'));

define('MQTT_BROKER', (string)($mqttConfig['broker'] ?? 'broker.emqx.io'));
define('MQTT_PORT', (int)($mqttConfig['port'] ?? 1883));
define('MQTT_TOPIC', (string)($mqttConfig['topic_php'] ?? 'msgPHP'));

define('MIGRATION_MANAGER_TOKEN', (string)($managerConfig['token'] ?? 'root'));
define('PC1_MANAGER_URL', 'http://' . (string)($managerConfig['pc1_host'] ?? '127.0.0.1') . ':' . (int)($managerConfig['pc1_port'] ?? 8081));
define('PC2_MANAGER_URL', 'http://' . (string)($managerConfig['pc2_host'] ?? '127.0.0.1') . ':' . (int)($managerConfig['pc2_port'] ?? 8082));
