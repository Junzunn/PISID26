<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('simulacoes.php');
}

$equipa = filter_input(INPUT_POST, 'equipa', FILTER_VALIDATE_INT);
$descricao = trim($_POST['descricao'] ?? '');

if ($equipa === false || $equipa === null || $equipa <= 0) {
    set_flash('error', 'Equipa deve ser maior que zero.');
    redirect('simulacoes.php');
}

if ($descricao === '') {
    $descricao = null;
}

try {
    $pdo = db();

    $stmt = $pdo->prepare('CALL simulacao_criar(:equipa, :descricao)');
    $stmt->bindValue(':equipa', $equipa, PDO::PARAM_INT);
    $stmt->bindValue(':descricao', $descricao, $descricao === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
    $stmt->execute();
    $stmt->closeCursor();

    set_flash('success', 'Simulacao criada com sucesso.');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
}

redirect('simulacoes.php');