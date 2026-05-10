<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

$user = current_user_info();

if (!$user || !in_array($user['Tipo'], ['Equipe', 'root'], true)) {
    http_response_code(403);
    echo 'Acesso negado.';
    exit;
}

$flash = get_flash();

try {
    $pdo = db();

    $sql = 'SELECT
                s.IDSimulacao,
                COALESCE(u.Email, "Utilizador apagado") AS Criador,
                s.Descricao,
                s.Equipa,
                s.DataHorainicio,
                s.DataHoraFim,
                p.tempo_max_ruido,
                p.tempo_min_ruido,
                p.threshold_ruido,
                p.tempo_max_temp,
                p.tempo_min_temp,
                p.threshold_temp,
                p.janela_outliers,
                p.variacao_outlier
         FROM Simulacao s
         LEFT JOIN Utilizador u
            ON u.IDUtilizador = s.IDCriador
         LEFT JOIN SimulacaoParametros p
            ON p.IDSimulacao = s.IDSimulacao';

    $params = [];

    if ($user['Tipo'] === 'Equipe') {
        $sql .= ' WHERE s.Equipa = :equipa';
        $params[':equipa'] = (int)$user['Equipa'];
    }

    $sql .= ' ORDER BY s.IDSimulacao DESC';

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
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
<div class="page wide-page">
    <div class="topbar">
        <h1>Simulacoes</h1>

        <div class="actions">
            <?php if ($user['Tipo'] === 'Equipe'): ?>
                <button type="button" onclick="document.getElementById('criarDialog').showModal()">
                    Criar simulacao
                </button>
            <?php endif; ?>

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
            <th>ID</th>
            <th>Criador</th>
            <th>Descricao</th>
            <th>Equipa</th>
            <th>Inicio</th>
            <th>Fim</th>
            <th>Ruido</th>
            <th>Temperatura</th>
            <th>Outliers</th>
            <th>Acao</th>
        </tr>
        </thead>
        <tbody>
        <?php if (count($simulacoes) === 0): ?>
            <tr>
                <td colspan="10" class="center">Nenhuma simulacao encontrada.</td>
            </tr>
        <?php endif; ?>

        <?php foreach ($simulacoes as $s): ?>
            <tr>
                <td><?= h($s['IDSimulacao']) ?></td>
                <td><?= h($s['Criador']) ?></td>
                <td><?= h($s['Descricao']) ?></td>
                <td><?= h($s['Equipa']) ?></td>
                <td><?= h($s['DataHorainicio']) ?></td>
                <td><?= h($s['DataHoraFim']) ?></td>
                <td>
                    max: <?= h($s['tempo_max_ruido']) ?><br>
                    min: <?= h($s['tempo_min_ruido']) ?><br>
                    threshold: <?= h($s['threshold_ruido']) ?>
                </td>
                <td>
                    max: <?= h($s['tempo_max_temp']) ?><br>
                    min: <?= h($s['tempo_min_temp']) ?><br>
                    threshold: <?= h($s['threshold_temp']) ?>
                </td>
                <td>
                    janela: <?= h($s['janela_outliers']) ?><br>
                    variacao: <?= h($s['variacao_outlier']) ?>
                </td>
                <td>
                    <?php
                    $podeAlterar = $s['DataHorainicio'] === null && $s['DataHoraFim'] === null;
                    ?>
                    <div class="row-actions">
                        <?php if ($podeAlterar): ?>
                            <form method="post" action="start_simulacao.php" class="inline-form"
                                  onsubmit="return confirm('Tem a certeza que quer iniciar esta simulacao?');">
                                <input type="hidden" name="idsimulacao" value="<?= h($s['IDSimulacao']) ?>">
                                <button type="submit">Iniciar</button>
                            </form>

                            <button type="button" onclick='openEditSimulacao(<?= json_for_html($s) ?>)'>
                                Editar
                            </button>
                        <?php else: ?>
                            <span class="muted">Sem acao</span>
                        <?php endif; ?>
                    </div>
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
            Descricao
            <textarea name="descricao" rows="3" placeholder="Opcional"></textarea>
        </label>

        <label>
            tempo_max_ruido
            <input type="number" step="0.001" name="tempo_max_ruido" placeholder="20.000">
        </label>

        <label>
            tempo_min_ruido
            <input type="number" step="0.001" name="tempo_min_ruido" placeholder="1.000">
        </label>

        <label>
            threshold_ruido
            <input type="number" step="0.001" name="threshold_ruido" placeholder="0.200">
        </label>

        <label>
            tempo_max_temp
            <input type="number" step="0.001" name="tempo_max_temp" placeholder="20.000">
        </label>

        <label>
            tempo_min_temp
            <input type="number" step="0.001" name="tempo_min_temp" placeholder="1.000">
        </label>

        <label>
            threshold_temp
            <input type="number" step="0.001" name="threshold_temp" placeholder="0.200">
        </label>

        <label>
            janela_outliers
            <input type="number" min="1" step="1" name="janela_outliers" placeholder="6">
        </label>

        <label>
            variacao_outlier
            <input type="number" step="0.001" name="variacao_outlier" placeholder="0.200">
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

<dialog id="editarSimulacaoDialog">
    <form method="post" action="update_simulacao.php" class="dialog-form">
        <h2>Editar simulacao</h2>

        <label>
            IDSimulacao
            <input type="number" name="idsimulacao" id="edit_idsimulacao" readonly>
        </label>

        <label>
            Descricao
            <textarea name="descricao" id="edit_descricao" rows="3"></textarea>
        </label>

        <label>
            tempo_max_ruido
            <input type="number" step="0.001" name="tempo_max_ruido" id="edit_tempo_max_ruido">
        </label>

        <label>
            tempo_min_ruido
            <input type="number" step="0.001" name="tempo_min_ruido" id="edit_tempo_min_ruido">
        </label>

        <label>
            threshold_ruido
            <input type="number" step="0.001" name="threshold_ruido" id="edit_threshold_ruido">
        </label>

        <label>
            tempo_max_temp
            <input type="number" step="0.001" name="tempo_max_temp" id="edit_tempo_max_temp">
        </label>

        <label>
            tempo_min_temp
            <input type="number" step="0.001" name="tempo_min_temp" id="edit_tempo_min_temp">
        </label>

        <label>
            threshold_temp
            <input type="number" step="0.001" name="threshold_temp" id="edit_threshold_temp">
        </label>

        <label>
            janela_outliers
            <input type="number" min="1" step="1" name="janela_outliers" id="edit_janela_outliers">
        </label>

        <label>
            variacao_outlier
            <input type="number" step="0.001" name="variacao_outlier" id="edit_variacao_outlier">
        </label>

        <div class="dialog-actions">
            <button type="button" onclick="document.getElementById('editarSimulacaoDialog').close()">
                Cancelar
            </button>
            <button type="submit">Confirmar</button>
        </div>
    </form>
</dialog>

<script>
    function setPlaceholder(id, value) {
        const el = document.getElementById(id);
        el.value = '';
        el.placeholder = value ?? '';
    }

    function openEditSimulacao(s) {
        document.getElementById('edit_idsimulacao').value = s.IDSimulacao;

        setPlaceholder('edit_descricao', s.Descricao);
        setPlaceholder('edit_tempo_max_ruido', s.tempo_max_ruido);
        setPlaceholder('edit_tempo_min_ruido', s.tempo_min_ruido);
        setPlaceholder('edit_threshold_ruido', s.threshold_ruido);
        setPlaceholder('edit_tempo_max_temp', s.tempo_max_temp);
        setPlaceholder('edit_tempo_min_temp', s.tempo_min_temp);
        setPlaceholder('edit_threshold_temp', s.threshold_temp);
        setPlaceholder('edit_janela_outliers', s.janela_outliers);
        setPlaceholder('edit_variacao_outlier', s.variacao_outlier);

        document.getElementById('editarSimulacaoDialog').showModal();
    }

    document.addEventListener('submit', function (event) {
        const form = event.target;
        const button = form.querySelector('button[type="submit"]');

        if (button) {
            button.disabled = true;
            button.innerText = 'A iniciar...';
        }
    });

</script>
</body>
</html>