<?php
declare(strict_types=1);

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
        'SELECT Equipa
         FROM Simulacao
         WHERE IDSimulacao = :id'
    );
    $stmt->bindValue(':id', $idSimulacao, PDO::PARAM_INT);
    $stmt->execute();

    $simulacao = $stmt->fetch();

    if (!$simulacao) {
        throw new RuntimeException('Simulacao nao existe.');
    }

    $equipa = (int)$simulacao['Equipa'];

    $stmt = $pdo->prepare('CALL simulacao_iniciar(:id)');
    $stmt->bindValue(':id', $idSimulacao, PDO::PARAM_INT);
    $stmt->execute();
    $stmt->closeCursor();
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
    redirect('simulacoes.php');
}

try {
    publicar_inicio_simulacao($idSimulacao, $equipa);

    set_flash('success', 'Simulacao iniciada e mensagem MQTT enviada.');
} catch (Throwable $e) {
    set_flash(
        'error',
        'Simulacao iniciada, mas falhou o envio MQTT: ' . $e->getMessage()
    );
}

redirect('simulacoes.php');