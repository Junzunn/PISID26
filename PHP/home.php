<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

$user = current_user_info();
$isAdmin = is_admin_user();
?>

<!doctype html>
<html lang="pt">
<head>
    <meta charset="utf-8">
    <title>Home - Marsabirinto</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="page small-page">
    <div class="topbar">
        <h1>Marsabirinto</h1>
        <a href="logout.php">Sair</a>
    </div>

    <p class="muted">
        Ligado como:
        <?php if ($user && $user['Tipo'] !== 'root'): ?>
            <a href="perfil.php"><?= h($user['Email']) ?></a>
        <?php else: ?>
            <?= h($_SESSION['db_user']) ?>
        <?php endif; ?>
    </p>

    <div class="menu">
        <a class="menu-card" href="simulacoes.php">
            Lista de Simulacoes
        </a>

        <?php if ($isAdmin): ?>
            <a class="menu-card" href="utilizadores.php">
                Gestao de Utilizadores
            </a>
        <?php endif; ?>
    </div>
</div>
</body>
</html>