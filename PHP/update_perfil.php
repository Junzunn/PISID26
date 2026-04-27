<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('perfil.php');
}

try {
    $user = current_user_info();

    if (!$user || empty($user['Email'])) {
        throw new RuntimeException('Utilizador atual nao existe.');
    }

    $oldEmail = $user['Email'];

    $nome = nullable_string_from_post('nome');
    $telemovel = nullable_string_from_post('telemovel');
    $email = nullable_string_from_post('email');
    $datanascimento = nullable_string_from_post('datanascimento');
    $equipa = nullable_positive_int_from_post('equipa');

    $emailFoiAlterado = $email !== null && $email !== $oldEmail;

    $pdo = db();

    $stmt = $pdo->prepare(
        'CALL utilizador_alterar_proprios_dados(:nome, :telemovel, :email, :datanascimento, :equipa)'
    );

    bind_nullable_string($stmt, ':nome', $nome);
    bind_nullable_string($stmt, ':telemovel', $telemovel);
    bind_nullable_string($stmt, ':email', $email);
    bind_nullable_string($stmt, ':datanascimento', $datanascimento);
    bind_nullable_int($stmt, ':equipa', $equipa);

    $stmt->execute();
    $stmt->closeCursor();

    if ($emailFoiAlterado) {
        session_destroy();
        redirect('login.php?perfil=alterado');
    }

    set_flash('success', 'Dados alterados com sucesso.');
    redirect('perfil.php');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
    redirect('perfil.php');
}