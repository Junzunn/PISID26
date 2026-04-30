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
            Seq AS idtemperatura,
            CAST(Temperatura AS DECIMAL(10,3)) AS temperatura
         FROM (
            SELECT Seq, Temperatura
            FROM Temperatura
            WHERE IDSimulacao = :idsimulacao
            ORDER BY Seq DESC
            LIMIT 100
         ) x
         ORDER BY Seq ASC'
    );

    $stmt->execute([
        ':idsimulacao' => $idSimulacao
    ]);

    json_ok($stmt->fetchAll());

} catch (Throwable $e) {
    json_error($e->getMessage());
}