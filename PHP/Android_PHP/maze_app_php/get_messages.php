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
            ID AS id,
            TipoAlerta AS tipoalerta,
            Hora AS hora,
            Msg AS msg,
            Leitura AS leitura,
            Sensor AS sensor
         FROM Mensagens
         WHERE IDSimulacao = :idsimulacao
         ORDER BY ID DESC
         LIMIT 100'
    );

    $stmt->execute([
        ':idsimulacao' => $idSimulacao
    ]);

    json_ok($stmt->fetchAll());

} catch (Throwable $e) {
    json_error($e->getMessage());
}