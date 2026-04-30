<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

try {
    $pdo = db();

    $idSimulacao = current_running_simulacao_id($pdo);

    if ($idSimulacao === null) {
        json_ok([]);
    }

    $stmt = $pdo->prepare(
        'SELECT
            Sala,
            COALESCE(NumeroMarsamisEven, 0) AS NumeroMarsamisEven,
            COALESCE(NumeroMarsamisOdd, 0) AS NumeroMarsamisOdd
         FROM OcupacaoLabirinto
         WHERE IDJogo = :idsimulacao
         ORDER BY Sala ASC'
    );

    $stmt->execute([
        ':idsimulacao' => $idSimulacao
    ]);

    json_ok($stmt->fetchAll());

} catch (Throwable $e) {
    json_error($e->getMessage());
}