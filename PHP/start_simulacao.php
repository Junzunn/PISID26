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

function abrir_lock_inicio_simulacao()
{
    $lockPath = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'marsabirinto_start_simulacao.lock';
    $lock = fopen($lockPath, 'c');

    if ($lock === false) {
        throw new RuntimeException('Nao foi possivel criar lock de inicio de simulacao.');
    }

    if (!flock($lock, LOCK_EX)) {
        fclose($lock);
        throw new RuntimeException('Nao foi possivel bloquear inicio de simulacao.');
    }

    return $lock;
}

$idSimulacao = filter_input(INPUT_POST, 'idsimulacao', FILTER_VALIDATE_INT);

if ($idSimulacao === false || $idSimulacao === null) {
    set_flash('error', 'IDSimulacao invalido.');
    redirect('simulacoes.php');
}

$lock = null;

try {
    $lock = abrir_lock_inicio_simulacao();
    $pdo = db();

    $stmt = $pdo->prepare(
        'SELECT
            s.IDSimulacao,
            s.Equipa,
            s.DataHorainicio,
            s.DataHoraFim,
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

    if ($simulacao['DataHorainicio'] !== null) {
        throw new RuntimeException('Esta simulacao ja foi iniciada.');
    }

    $stmt = $pdo->prepare(
        'SELECT IDSimulacao
           FROM Simulacao
          WHERE Equipa = :equipa
            AND DataHorainicio IS NOT NULL
            AND DataHoraFim IS NULL
          LIMIT 1'
    );

    $stmt->bindValue(':equipa', (int)$simulacao['Equipa'], PDO::PARAM_INT);
    $stmt->execute();

    if ($stmt->fetch()) {
        throw new RuntimeException('Esta equipa ja tem uma simulacao em execucao.');
    }

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

    $stmt = $pdo->prepare('CALL simulacao_iniciar(:id)');
    $stmt->bindValue(':id', $idSimulacao, PDO::PARAM_INT);
    $stmt->execute();
    $stmt->closeCursor();

    set_flash('success', 'Mensagem MQTT enviada e simulacao iniciada.');
    redirect('simulacoes.php');

} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
    redirect('simulacoes.php');

} finally {
    if (is_resource($lock)) {
        flock($lock, LOCK_UN);
        fclose($lock);
    }
}