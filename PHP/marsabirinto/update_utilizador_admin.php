<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_admin_user();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('utilizadores.php');
}

try {
    $idUtilizador = filter_input(INPUT_POST, 'idutilizador', FILTER_VALIDATE_INT);

    if ($idUtilizador === false || $idUtilizador === null) {
        throw new RuntimeException('IDUtilizador invalido.');
    }

    $nome = nullable_string_from_post('nome');
    $telemovel = nullable_string_from_post('telemovel');
    $tipo = nullable_string_from_post('tipo');
    $email = nullable_string_from_post('email');
    $datanascimento = nullable_string_from_post('datanascimento');
    $equipa = nullable_int_from_post('equipa');

    if ($tipo !== null && !in_array($tipo, ['AdminApp', 'Equipe', 'Analista', 'Software'], true)) {
        throw new RuntimeException('Tipo invalido.');
    }

    $pdo = db();

    $stmt = $pdo->prepare(
        'CALL utilizadorAdmin_alterar_dados(:idutilizador, :nome, :telemovel, :tipo, :email, :datanascimento, :equipa)'
    );

    $stmt->bindValue(':idutilizador', $idUtilizador, PDO::PARAM_INT);
    bind_nullable_string($stmt, ':nome', $nome);
    bind_nullable_string($stmt, ':telemovel', $telemovel);
    bind_nullable_string($stmt, ':tipo', $tipo);
    bind_nullable_string($stmt, ':email', $email);
    bind_nullable_string($stmt, ':datanascimento', $datanascimento);
    bind_nullable_int($stmt, ':equipa', $equipa);

    $stmt->execute();
    $stmt->closeCursor();

    set_flash('success', 'Utilizador atualizado com sucesso.');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
}

redirect('utilizadores.php');