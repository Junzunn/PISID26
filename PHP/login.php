<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$error = '';

if (!empty($_SESSION['db_user']) && !empty($_SESSION['db_pass'])) {
    redirect('home.php');
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = trim($_POST['user'] ?? '');
    $password = $_POST['password'] ?? '';

    if ($user === '' || $password === '') {
        $error = 'Utilizador e password sao obrigatorios.';
    } else {
        try {
            pdo_from_credentials($user, $password);

            session_regenerate_id(true);

            $_SESSION['db_user'] = $user;
            $_SESSION['db_pass'] = $password;

            redirect('home.php');
        } catch (Throwable $e) {
            $error = 'Login invalido.';
        }
    }
}
?>

<!doctype html>
<html lang="pt">
<head>
    <meta charset="utf-8">
    <title>Login - Marsabirinto</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="page small-page">
    <h1>Login</h1>

    <?php if ($error !== ''): ?>
        <div class="alert error"><?= h($error) ?></div>
    <?php endif; ?>

    <?php if (($_GET['perfil'] ?? '') === 'alterado'): ?>
        <div class="alert success">
            Dados alterados com sucesso. Faca login novamente.
        </div>
    <?php endif; ?>

    <form method="post" class="card">
        <label>
            MySQL username / Email
            <input type="text" name="user" required>
        </label>

        <label>
            Password
            <input type="password" name="password" required>
        </label>

        <button type="submit">Entrar</button>
    </form>
</div>
</body>
</html>