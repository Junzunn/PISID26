<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

try {
    $pdo = db();

    $idSimulacao = current_running_simulacao_id($pdo);

    if ($idSimulacao === null) {
        json_ok([
            'maximo' => 0
        ]);
    }

    $stmt = $pdo->prepare(
        'SELECT
            COALESCE(MAX(CAST(Som AS DECIMAL(10,3))), 0) AS maximo
         FROM Som
         WHERE IDSimulacao = :idsimulacao'
    );

    $stmt->execute([
        ':idsimulacao' => $idSimulacao
    ]);

    json_ok($stmt->fetch());

} catch (Throwable $e) {
    json_error($e->getMessage());
}