<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_admin_user();

$flash = get_flash();

try {
    $pdo = db();

    $stmt = $pdo->query(
        'SELECT IDUtilizador, Nome, Telemovel, Tipo, Email, DataNascimento, Equipa
         FROM Utilizador
         ORDER BY IDUtilizador ASC'
    );

    $utilizadores = $stmt->fetchAll();
} catch (Throwable $e) {
    $utilizadores = [];
    $flash = [
        'type' => 'error',
        'message' => $e->getMessage(),
    ];
}
?>

<!doctype html>
<html lang="pt">
<head>
    <meta charset="utf-8">
    <title>Gestao de Utilizadores</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="page">
    <div class="topbar">
        <h1>Gestao de Utilizadores</h1>

        <div class="actions">
            <button type="button" onclick="document.getElementById('criarUtilizadorDialog').showModal()">
                Criar utilizador
            </button>
            <a href="home.php">Voltar</a>
            <a href="logout.php">Sair</a>
        </div>
    </div>

    <?php if ($flash): ?>
        <div class="alert <?= h($flash['type']) ?>">
            <?= h($flash['message']) ?>
        </div>
    <?php endif; ?>

    <table>
        <thead>
        <tr>
            <th>IDUtilizador</th>
            <th>Nome</th>
            <th>Telemovel</th>
            <th>Tipo</th>
            <th>Email</th>
            <th>Data Nascimento</th>
            <th>Equipa</th>
            <th>Acao</th>
        </tr>
        </thead>
        <tbody>
        <?php if (count($utilizadores) === 0): ?>
            <tr>
                <td colspan="8" class="center">Nenhum utilizador encontrado.</td>
            </tr>
        <?php endif; ?>

        <?php foreach ($utilizadores as $u): ?>
            <tr>
                <td><?= h($u['IDUtilizador']) ?></td>
                <td><?= h($u['Nome']) ?></td>
                <td><?= h($u['Telemovel']) ?></td>
                <td><?= h($u['Tipo']) ?></td>
                <td><?= h($u['Email']) ?></td>
                <td><?= h($u['DataNascimento']) ?></td>
                <td><?= h($u['Equipa']) ?></td>
                <td>
                    <div class="row-actions">
                        <button type="button" onclick='openEditUser(<?= json_for_html($u) ?>)'>
                            Editar
                        </button>

                        <button type="button" class="danger" onclick='openDeleteUser(<?= json_for_html($u) ?>)'>
                            Apagar
                        </button>
                    </div>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
</div>

<dialog id="criarUtilizadorDialog">
    <form method="post" action="create_utilizador.php" class="dialog-form">
        <h2>Criar utilizador</h2>

        <label>
            Nome
            <input type="text" name="nome">
        </label>

        <label>
            Telemovel
            <input type="text" name="telemovel">
        </label>

        <label>
            Tipo
            <select name="tipo" required>
                <option value="">Escolher tipo</option>
                <option value="AdminApp">AdminApp</option>
                <option value="Equipe">Equipe</option>
                <option value="Software">Software</option>
            </select>
        </label>

        <label>
            Email
            <input type="email" name="email" required>
        </label>

        <label>
            Data Nascimento
            <input type="date" name="datanascimento">
        </label>

        <label>
            Equipa
            <input type="number" name="equipa" min="1">
        </label>

        <label>
            Password MySQL
            <input type="password" name="password" required>
        </label>

        <div class="dialog-actions">
            <button type="button" onclick="document.getElementById('criarUtilizadorDialog').close()">
                Cancelar
            </button>
            <button type="submit">Confirmar</button>
        </div>
    </form>
</dialog>

<dialog id="editarUtilizadorDialog">
    <form method="post" action="update_utilizador_admin.php" class="dialog-form">
        <h2>Editar utilizador</h2>

        <label>
            IDUtilizador
            <input type="number" name="idutilizador" id="edit_idutilizador" readonly>
        </label>

        <label>
            Nome
            <input type="text" name="nome" id="edit_nome">
        </label>

        <label>
            Telemovel
            <input type="text" name="telemovel" id="edit_telemovel">
        </label>

        <label>
            Tipo
            <select name="tipo" id="edit_tipo">
                <option value="">Manter atual</option>
                <option value="AdminApp">AdminApp</option>
                <option value="Equipe">Equipe</option>
                <option value="Software">Software</option>
            </select>
        </label>

        <label>
            Email
            <input type="email" name="email" id="edit_email">
        </label>

        <label>
            Data Nascimento
            <input type="date" name="datanascimento" id="edit_datanascimento">
            <span class="hint" id="edit_datanascimento_hint"></span>
        </label>

        <label>
            Equipa
            <input type="number" name="equipa" id="edit_equipa" min="1">
        </label>

        <div class="dialog-actions">
            <button type="button" onclick="document.getElementById('editarUtilizadorDialog').close()">
                Cancelar
            </button>
            <button type="submit">Confirmar</button>
        </div>
    </form>
</dialog>

<dialog id="apagarUtilizadorDialog">
    <form method="post" action="delete_utilizador.php" class="dialog-form">
        <h2>Apagar utilizador</h2>

        <input type="hidden" name="email" id="delete_email">

        <p id="delete_text"></p>

        <div class="dialog-actions">
            <button type="button" onclick="document.getElementById('apagarUtilizadorDialog').close()">
                Cancelar
            </button>
            <button type="submit" class="danger">Apagar</button>
        </div>
    </form>
</dialog>

<script>
    function openEditUser(user) {
        document.getElementById('edit_idutilizador').value = user.IDUtilizador;

        document.getElementById('edit_nome').value = '';
        document.getElementById('edit_nome').placeholder = user.Nome ?? '';

        document.getElementById('edit_telemovel').value = '';
        document.getElementById('edit_telemovel').placeholder = user.Telemovel ?? '';

        document.getElementById('edit_tipo').value = '';

        document.getElementById('edit_email').value = '';
        document.getElementById('edit_email').placeholder = user.Email ?? '';

        document.getElementById('edit_datanascimento').value = '';
        document.getElementById('edit_datanascimento_hint').textContent =
            user.DataNascimento ? 'Atual: ' + user.DataNascimento : 'Atual: vazio';

        document.getElementById('edit_equipa').value = '';
        document.getElementById('edit_equipa').placeholder = user.Equipa ?? '';

        document.getElementById('editarUtilizadorDialog').showModal();
    }

    function openDeleteUser(user) {
        document.getElementById('delete_email').value = user.Email;
        document.getElementById('delete_text').textContent =
            'Tem a certeza que quer apagar ' + user.Email + '?';

        document.getElementById('apagarUtilizadorDialog').showModal();
    }
</script>
</body>
</html>