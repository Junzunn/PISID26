<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_admin_user();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('utilizadores.php');
}

try {
    $nome = nullable_string_from_post('nome');
    $telemovel = nullable_string_from_post('telemovel');
    $tipo = nullable_string_from_post('tipo');
    $email = nullable_string_from_post('email');
    $datanascimento = nullable_string_from_post('datanascimento');
    $equipa = nullable_int_from_post('equipa');
    $password = $_POST['password'] ?? '';

    if ($tipo === null || !in_array($tipo, ['AdminApp', 'Equipe', 'Analista', 'Software'], true)) {
        throw new RuntimeException('Tipo invalido.');
    }

    if ($email === null) {
        throw new RuntimeException('Email obrigatorio.');
    }

    if ($password === '') {
        throw new RuntimeException('Password obrigatoria.');
    }

    $pdo = db();

    $stmt = $pdo->prepare(
        'CALL utilizador_criar(:nome, :telemovel, :tipo, :email, :datanascimento, :equipa, :password)'
    );

    bind_nullable_string($stmt, ':nome', $nome);
    bind_nullable_string($stmt, ':telemovel', $telemovel);
    $stmt->bindValue(':tipo', $tipo, PDO::PARAM_STR);
    $stmt->bindValue(':email', $email, PDO::PARAM_STR);
    bind_nullable_string($stmt, ':datanascimento', $datanascimento);
    bind_nullable_int($stmt, ':equipa', $equipa);
    $stmt->bindValue(':password', $password, PDO::PARAM_STR);

    $stmt->execute();
    $stmt->closeCursor();

    set_flash('success', 'Utilizador criado com sucesso.');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
}

redirect('utilizadores.php');