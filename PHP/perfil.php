<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

$user = current_user_info();
$flash = get_flash();

if (!$user || $user['Tipo'] === 'root') {
    $user = null;
}
?>

<!doctype html>
<html lang="pt">
<head>
    <meta charset="utf-8">
    <title>Perfil</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="page small-page">
    <div class="topbar">
        <h1>Perfil</h1>

        <div class="actions">
            <a href="home.php">Voltar</a>
            <a href="logout.php">Sair</a>
        </div>
    </div>

    <?php if ($flash): ?>
        <div class="alert <?= h($flash['type']) ?>">
            <?= h($flash['message']) ?>
        </div>
    <?php endif; ?>

    <?php if (!$user): ?>
        <div class="alert error">
            Utilizador atual nao existe na tabela Utilizador.
        </div>
    <?php else: ?>
        <div class="card info-card">
            <p><strong>IDUtilizador:</strong> <?= h($user['IDUtilizador']) ?></p>
            <p><strong>Nome:</strong> <?= h($user['Nome']) ?></p>
            <p><strong>Telemovel:</strong> <?= h($user['Telemovel']) ?></p>
            <p><strong>Tipo:</strong> <?= h($user['Tipo']) ?></p>
            <p><strong>Email:</strong> <?= h($user['Email']) ?></p>
            <p><strong>Data Nascimento:</strong> <?= h($user['DataNascimento']) ?></p>
            <p><strong>Equipa:</strong> <?= h($user['Equipa']) ?></p>

            <button type="button" onclick='openEditPerfil(<?= json_for_html($user) ?>)'>
                Editar
            </button>
        </div>
    <?php endif; ?>
</div>

<dialog id="editarPerfilDialog">
    <form method="post" action="update_perfil.php" class="dialog-form">
        <h2>Editar perfil</h2>

        <label>
            Nome
            <input type="text" name="nome" id="perfil_nome">
        </label>

        <label>
            Telemovel
            <input type="text" name="telemovel" id="perfil_telemovel">
        </label>

        <label>
            Email
            <input type="email" name="email" id="perfil_email">
        </label>

        <label>
            Data Nascimento
            <input type="date" name="datanascimento" id="perfil_datanascimento">
            <span class="hint" id="perfil_datanascimento_hint"></span>
        </label>

        <label>
            Equipa
            <input type="number" name="equipa" id="perfil_equipa" min="1">
        </label>

        <div class="dialog-actions">
            <button type="button" onclick="document.getElementById('editarPerfilDialog').close()">
                Cancelar
            </button>
            <button type="submit">Confirmar</button>
        </div>
    </form>
</dialog>

<script>
    function openEditPerfil(user) {
        document.getElementById('perfil_nome').value = '';
        document.getElementById('perfil_nome').placeholder = user.Nome ?? '';

        document.getElementById('perfil_telemovel').value = '';
        document.getElementById('perfil_telemovel').placeholder = user.Telemovel ?? '';

        document.getElementById('perfil_email').value = '';
        document.getElementById('perfil_email').placeholder = user.Email ?? '';

        document.getElementById('perfil_datanascimento').value = '';
        document.getElementById('perfil_datanascimento_hint').textContent =
            user.DataNascimento ? 'Atual: ' + user.DataNascimento : 'Atual: vazio';

        document.getElementById('perfil_equipa').value = '';
        document.getElementById('perfil_equipa').placeholder = user.Equipa ?? '';

        document.getElementById('editarPerfilDialog').showModal();
    }
</script>
</body>
</html>