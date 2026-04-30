<?php
declare(strict_types=1);

ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/mqtt.php';

require_login();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('simulacoes.php');
}

$idSimulacao = filter_input(INPUT_POST, 'idsimulacao', FILTER_VALIDATE_INT);

if ($idSimulacao === false || $idSimulacao === null) {
    set_flash('error', 'IDSimulacao invalido.');
    redirect('simulacoes.php');
}

try {
    $pdo = db();

    $stmt = $pdo->prepare(
        'SELECT
            s.IDSimulacao,
            s.Equipa,
            p.tempo_max_ruido,
            p.tempo_min_ruido,
            p.threshold_ruido,
            p.tempo_max_temp,
            p.tempo_min_temp,
            p.threshold_temp,
            p.janela_outliers,
            p.variacao_outlier
         FROM Simulacao s
         INNER JOIN SimulacaoParametros p
            ON p.IDSimulacao = s.IDSimulacao
         WHERE s.IDSimulacao = :id'
    );

    $stmt->bindValue(':id', $idSimulacao, PDO::PARAM_INT);
    $stmt->execute();

    $simulacao = $stmt->fetch();

    if (!$simulacao) {
        throw new RuntimeException('Simulacao ou parametros nao existem.');
    }

    $stmt = $pdo->prepare('CALL simulacao_iniciar(:id)');
    $stmt->bindValue(':id', $idSimulacao, PDO::PARAM_INT);
    $stmt->execute();
    $stmt->closeCursor();

    $payload = [
        'type' => 'Start',
        'IDSimulacao' => (int)$simulacao['IDSimulacao'],
        'Equipa' => (int)$simulacao['Equipa'],
        'playerid' => (int)$simulacao['Equipa'],

        'tempo_max_ruido' => (float)$simulacao['tempo_max_ruido'],
        'tempo_min_ruido' => (float)$simulacao['tempo_min_ruido'],
        'threshold_ruido' => (float)$simulacao['threshold_ruido'],

        'tempo_max_temp' => (float)$simulacao['tempo_max_temp'],
        'tempo_min_temp' => (float)$simulacao['tempo_min_temp'],
        'threshold_temp' => (float)$simulacao['threshold_temp'],

        'janela_outliers' => (int)$simulacao['janela_outliers'],
        'variacao_outlier' => (float)$simulacao['variacao_outlier'],
    ];

    publicar_inicio_simulacao($payload);

    set_flash('success', 'Simulacao iniciada e mensagem MQTT enviada.');
    redirect('simulacoes.php');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
    redirect('simulacoes.php');
}