<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_admin_user();

function manager_status(string $url): array
{
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'timeout' => 3,
        ],
    ]);

    $raw = @file_get_contents(rtrim($url, '/') . '/status', false, $context);
    if ($raw === false) {
        return ['erro' => 'sem resposta'];
    }

    $data = json_decode($raw, true);
    return is_array($data) ? $data : ['erro' => 'resposta invalida'];
}

function manager_restart(string $url, bool $force): array
{
    $payload = json_encode([
        'request_id' => bin2hex(random_bytes(12)),
        'force' => $force,
    ], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);

    $context = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => "Content-Type: application/json\r\n",
            'content' => $payload,
            'timeout' => 8,
            'ignore_errors' => true,
        ],
    ]);

    $raw = @file_get_contents(rtrim($url, '/') . '/restart', false, $context);
    if ($raw === false) {
        return ['erro' => 'sem resposta'];
    }

    $data = json_decode($raw, true);
    return is_array($data) ? $data : ['erro' => 'resposta invalida'];
}

function estado_valor(array $status, string $campo): string
{
    return isset($status[$campo]) && $status[$campo] !== null ? (string)$status[$campo] : '-';
}

function estado_classe(?string $estado): string
{
    if ($estado === 'OK') {
        return 'ok';
    }
    if ($estado === '-' || $estado === null || $estado === '') {
        return 'warn';
    }
    return 'erro';
}

function semaforo(string $texto, ?string $estado, string $detalhe = ''): string
{
    $classe = estado_classe($estado);
    $html = '<span class="semaforo ' . h($classe) . '"></span>';
    $html .= '<strong>' . h($texto) . ':</strong> ' . h($estado ?: '-');
    if ($detalhe !== '') {
        $html .= '<br><small class="muted">' . h($detalhe) . '</small>';
    }
    return $html;
}

function estado_manager(array $status): string
{
    if (isset($status['erro'])) {
        return semaforo('Manager', 'ERRO', (string)$status['erro']);
    }
    return semaforo('Manager', 'OK');
}

function processo_ativo(array $status): bool
{
    return !isset($status['erro'])
        && isset($status['processo_estado'])
        && (string)$status['processo_estado'] === 'OK';
}

$statusPc1 = manager_status(PC1_MANAGER_URL);
$statusPc2 = manager_status(PC2_MANAGER_URL);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $password = $_POST['password_confirm'] ?? '';
        if ($password === '') {
            throw new RuntimeException('Confirme a password da sua conta.');
        }

        pdo_from_credentials($_SESSION['db_user'], $password);

        $target = $_POST['target'] ?? '';
        $force = isset($_POST['force']);

        if (!$force) {
            $ativoPc1 = ($target === 'pc1' || $target === 'all') && processo_ativo($statusPc1);
            $ativoPc2 = ($target === 'pc2' || $target === 'all') && processo_ativo($statusPc2);

            if ($ativoPc1 || $ativoPc2) {
                throw new RuntimeException('O processo selecionado ainda está ativo. Para reiniciar mesmo assim, confirme a opção Forçar reinício.');
            }
        }

        $resultados = [];

        if ($target === 'pc1' || $target === 'all') {
            $resultados[] = 'PC1: ' . json_encode(manager_restart(PC1_MANAGER_URL, $force), JSON_UNESCAPED_UNICODE);
        }
        if ($target === 'pc2' || $target === 'all') {
            $resultados[] = 'PC2: ' . json_encode(manager_restart(PC2_MANAGER_URL, $force), JSON_UNESCAPED_UNICODE);
        }
        if (!$resultados) {
            throw new RuntimeException('Alvo invalido.');
        }

        set_flash('success', implode(' | ', $resultados));
    } catch (Throwable $e) {
        set_flash('error', $e->getMessage());
    }

    redirect('estado_migracao.php');
}

$flash = get_flash();
?>
<!doctype html>
<html lang="pt">
<head>
    <meta charset="utf-8">
    <title>Estado da Migração - Marsabirinto</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="page wide-page">
    <div class="topbar">
        <h1>Estado da Migração</h1>
        <div class="actions">
            <a href="home.php">Voltar</a>
            <a href="logout.php">Sair</a>
        </div>
    </div>

    <?php if ($flash): ?>
        <div class="alert <?= h($flash['type']) ?>"><?= h($flash['message']) ?></div>
    <?php endif; ?>

    <p class="muted">
        Esta página verifica os gestores de migração dos dois PCs. O PC1 gere apenas o <strong>mongo_mqtt.py</strong>.
        O <strong>nuvem_mongo.py</strong> não é reiniciado aqui, porque está ligado à execução do mazerun e à receção original dos sensores.
        O PC2 gere o <strong>mqtt_mysql.py</strong>.
    </p>

    <div class="status-grid">
        <div class="status-card">
            <h2>PC1 - Mongo e envio para PC2</h2>
            <p><?= estado_manager($statusPc1) ?></p>
            <p><?= semaforo('MongoDB', estado_valor($statusPc1, 'mongo'), estado_valor($statusPc1, 'mongo_erro') !== '-' ? estado_valor($statusPc1, 'mongo_erro') : '') ?></p>
            <p><?= semaforo(estado_valor($statusPc1, 'processo'), estado_valor($statusPc1, 'processo_estado')) ?></p>
            <p>
                <strong>Documentos por tratar:</strong> <?= h(estado_valor($statusPc1, 'documentos_por_tratar')) ?><br>
                <small class="muted">Ainda não foram analisados pelo mongo_mqtt.py.</small>
            </p>
            <p>
                <strong>Documentos por migrar:</strong> <?= h(estado_valor($statusPc1, 'documentos_por_migrar')) ?><br>
                <small class="muted">Já foram tratados no PC1, mas ainda não têm confirmação do PC2/MySQL.</small>
            </p>
            <?php if (estado_valor($statusPc1, 'nota') !== '-'): ?>
                <p><small class="muted"><?= h(estado_valor($statusPc1, 'nota')) ?></small></p>
            <?php endif; ?>
        </div>

        <div class="status-card">
            <h2>PC2 - Escrita no MySQL</h2>
            <p><?= estado_manager($statusPc2) ?></p>
            <p><?= semaforo('MySQL', estado_valor($statusPc2, 'mysql'), estado_valor($statusPc2, 'mysql_erro') !== '-' ? estado_valor($statusPc2, 'mysql_erro') : '') ?></p>
            <p><?= semaforo(estado_valor($statusPc2, 'processo'), estado_valor($statusPc2, 'processo_estado')) ?></p>
            <p><small class="muted">Se o MySQL aparecer como ERRO mas o processo Python estiver OK, confirme o host, porta, utilizador e password no config.json do PC2.</small></p>
        </div>
    </div>

    <h2>Reiniciar migração</h2>
    <p class="muted">
        Use esta ação apenas para reiniciar os scripts de migração. Esta página não reinicia o nuvem_mongo.py nem reinicia automaticamente os serviços MongoDB/MySQL do sistema operativo.
        Para evitar cliques acidentais, é obrigatório confirmar a password da conta atual.
    </p>

    <form method="post" class="card">
        <label>
            Alvo
            <select name="target" id="restartTarget" required>
                <option value="pc1" data-active="<?= processo_ativo($statusPc1) ? '1' : '0' ?>">Reiniciar PC1: mongo_mqtt.py</option>
                <option value="pc2" data-active="<?= processo_ativo($statusPc2) ? '1' : '0' ?>">Reiniciar PC2: mqtt_mysql.py</option>
                <option value="all" data-active="<?= (processo_ativo($statusPc1) || processo_ativo($statusPc2)) ? '1' : '0' ?>">Reiniciar PC1 e PC2</option>
            </select>
        </label>

        <label>
            Password da conta atual
            <input type="password" name="password_confirm" required>
        </label>

        <label class="inline-check">
            <input type="checkbox" name="force" value="1" id="forceRestart">
            Forçar reinício mesmo que o processo esteja ativo
        </label>
        <p id="restartHint" class="muted"></p>

        <div class="actions">
            <button type="submit" class="danger" id="restartButton">Executar reinício</button>
        </div>
    </form>
</div>

<script>
(function () {
    const target = document.getElementById('restartTarget');
    const force = document.getElementById('forceRestart');
    const button = document.getElementById('restartButton');
    const hint = document.getElementById('restartHint');

    function updateButton() {
        const option = target.options[target.selectedIndex];
        const active = option && option.dataset.active === '1';
        const blocked = active && !force.checked;
        button.disabled = blocked;
        hint.textContent = blocked
            ? 'O processo selecionado está ativo. Para reiniciar, confirme primeiro a opção de força.'
            : 'Depois de confirmar a password, a ação será enviada ao gestor de migração selecionado.';
    }

    target.addEventListener('change', updateButton);
    force.addEventListener('change', updateButton);
    updateButton();
}());
</script>
</body>
</html>
