<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

$flash = get_flash();

try {
    $pdo = db();

    $stmt = $pdo->query(
        'SELECT IDSimulacao, IDCriador, Descricao, Equipa, DataHorainicio, DataHoraFim
         FROM Simulacao
         ORDER BY IDSimulacao DESC'
    );

    $simulacoes = $stmt->fetchAll();
} catch (Throwable $e) {
    $simulacoes = [];
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
    <title>Simulacoes - Marsabirinto</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="page">
    <div class="topbar">
        <h1>Simulacoes</h1>

        <div class="actions">
            <button type="button" onclick="document.getElementById('criarDialog').showModal()">
                Criar simulacao
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
            <th>IDSimulacao</th>
            <th>IDCriador</th>
            <th>Descricao</th>
            <th>Equipa</th>
            <th>DataHoraInicio</th>
            <th>DataHoraFim</th>
            <th>Acao</th>
        </tr>
        </thead>
        <tbody>
        <?php if (count($simulacoes) === 0): ?>
            <tr>
                <td colspan="7" class="center">Nenhuma simulacao encontrada.</td>
            </tr>
        <?php endif; ?>

        <?php foreach ($simulacoes as $s): ?>
            <tr>
                <td><?= h($s['IDSimulacao']) ?></td>
                <td><?= h($s['IDCriador']) ?></td>
                <td><?= h($s['Descricao']) ?></td>
                <td><?= h($s['Equipa']) ?></td>
                <td><?= h($s['DataHorainicio']) ?></td>
                <td><?= h($s['DataHoraFim']) ?></td>
                <td>
                    <form method="post" action="start_simulacao.php" class="inline-form">
                        <input type="hidden" name="idsimulacao" value="<?= h($s['IDSimulacao']) ?>">
                        <button type="submit">Iniciar</button>
                    </form>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
</div>

<dialog id="criarDialog">
    <form method="post" action="create_simulacao.php" class="dialog-form">
        <h2>Criar simulacao</h2>

        <label>
            Equipa
            <input type="number" name="equipa" min="1" required>
        </label>

        <label>
            Descricao
            <textarea name="descricao" rows="4"></textarea>
        </label>

        <div class="dialog-actions">
            <button type="button" onclick="document.getElementById('criarDialog').close()">
                Cancelar
            </button>
            <button type="submit">
                Confirmar
            </button>
        </div>
    </form>
</dialog>
</body>
</html>