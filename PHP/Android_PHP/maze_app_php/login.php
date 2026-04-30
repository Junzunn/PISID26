<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

try {
    $pdo = db();

    $username = get_param('username');

    if ($username === 'root') {
        echo json_encode([
            'success' => true,
            'IDGrupo' => '0',
            'Tipo' => 'root'
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $stmt = $pdo->prepare(
        'SELECT IDUtilizador, Tipo, Equipa
         FROM Utilizador
         WHERE Email = :email
         LIMIT 1'
    );

    $stmt->execute([
        ':email' => $username
    ]);

    $user = $stmt->fetch();

    if (!$user) {
        echo json_encode([
            'success' => false,
            'message' => 'Utilizador nao existe na tabela Utilizador'
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    echo json_encode([
        'success' => true,
        'IDGrupo' => (string)($user['Equipa'] ?? '0'),
        'Tipo' => $user['Tipo'],
        'IDUtilizador' => $user['IDUtilizador']
    ], JSON_UNESCAPED_UNICODE);
    exit;

} catch (Throwable $e) {
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
    exit;
}