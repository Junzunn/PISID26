<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_admin_user();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('utilizadores.php');
}

try {
    $email = nullable_string_from_post('email');

    if ($email === null) {
        throw new RuntimeException('Email obrigatorio.');
    }

    $pdo = db();

    $stmt = $pdo->prepare('CALL utilizador_eliminar(:email)');
    $stmt->bindValue(':email', $email, PDO::PARAM_STR);
    $stmt->execute();
    $stmt->closeCursor();

    set_flash('success', 'Utilizador apagado com sucesso.');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
}

redirect('utilizadores.php');