<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

try {
    $pdo = db();

    $idSimulacao = current_running_simulacao_id($pdo);

    if ($idSimulacao === null) {
        json_ok([
            'minimo' => 0,
            'maximo' => 0
        ]);
    }

    $stmt = $pdo->prepare(
        'SELECT
            COALESCE(MIN(CAST(Temperatura AS DECIMAL(10,3))), 0) AS minimo,
            COALESCE(MAX(CAST(Temperatura AS DECIMAL(10,3))), 0) AS maximo
         FROM Temperatura
         WHERE IDSimulacao = :idsimulacao'
    );

    $stmt->execute([
        ':idsimulacao' => $idSimulacao
    ]);

    json_ok($stmt->fetch());

} catch (Throwable $e) {
    json_error($e->getMessage());
}