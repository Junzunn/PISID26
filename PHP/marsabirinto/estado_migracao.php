<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_admin_user();

function manager_status(string $url): array
{
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'timeout' => 1.5,
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
        'token' => MIGRATION_MANAGER_TOKEN,
        'request_id' => bin2hex(random_bytes(12)),
        'force' => $force,
    ], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);

    $context = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => "Content-Type: application/json\r\n",
            'content' => $payload,
            'timeout' => 3,
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

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $password = $_POST['password_confirm'] ?? '';
        if ($password === '') {
            throw new RuntimeException('Confirme a password da sua conta.');
        }

        pdo_from_credentials($_SESSION['db_user'], $password);

        $target = $_POST['target'] ?? '';
        $force = isset($_POST['force']);
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

$statusPc1 = manager_status(PC1_MANAGER_URL);
$statusPc2 = manager_status(PC2_MANAGER_URL);
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
        Esta página consulta os managers locais dos dois PCs. O PC1 gere o mongo_mqtt.py e o MongoDB.
        O PC2 gere o mqtt_mysql.py e a ligação ao MySQL. O nuvem_mongo.py não é reiniciado por esta página.
    </p>

    <table>
        <thead>
        <tr>
            <th>PC</th>
            <th>Manager</th>
            <th>Base de Dados</th>
            <th>Processo Python</th>
            <th>Documentos pendentes</th>
        </tr>
        </thead>
        <tbody>
        <tr>
            <td>PC1</td>
            <td><?= isset($statusPc1['erro']) ? h($statusPc1['erro']) : 'OK' ?></td>
            <td>MongoDB: <?= h(estado_valor($statusPc1, 'mongo')) ?></td>
            <td><?= h(estado_valor($statusPc1, 'processo')) ?>: <?= h(estado_valor($statusPc1, 'processo_estado')) ?></td>
            <td>
                Por tratar: <?= h(estado_valor($statusPc1, 'documentos_por_tratar')) ?><br>
                Por migrar: <?= h(estado_valor($statusPc1, 'documentos_por_migrar')) ?>
            </td>
        </tr>
        <tr>
            <td>PC2</td>
            <td><?= isset($statusPc2['erro']) ? h($statusPc2['erro']) : 'OK' ?></td>
            <td>MySQL: <?= h(estado_valor($statusPc2, 'mysql')) ?></td>
            <td><?= h(estado_valor($statusPc2, 'processo')) ?>: <?= h(estado_valor($statusPc2, 'processo_estado')) ?></td>
            <td>-</td>
        </tr>
        </tbody>
    </table>

    <h2>Reiniciar migração</h2>
    <p class="muted">
        Use esta ação apenas quando o processo de migração estiver parado ou quando for necessário forçar nova ligação.
        Para evitar cliques acidentais, é obrigatório confirmar a password da conta atual.
    </p>

    <form method="post" class="card">
        <label>
            Alvo
            <select name="target" required>
                <option value="pc1">Reiniciar PC1: mongo_mqtt.py</option>
                <option value="pc2">Reiniciar PC2: mqtt_mysql.py</option>
                <option value="all">Reiniciar PC1 e PC2</option>
            </select>
        </label>

        <label>
            Password da conta atual
            <input type="password" name="password_confirm" required>
        </label>

        <label class="inline-check">
            <input type="checkbox" name="force" value="1">
            Forçar reinício mesmo que o processo esteja ativo
        </label>

        <div class="actions">
            <button type="submit" class="danger">Executar reinício</button>
        </div>
    </form>
</div>
</body>
</html>
