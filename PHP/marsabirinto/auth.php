<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';

session_start();

function h($value): string
{
    return htmlspecialchars((string)$value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function redirect(string $url): void
{
    header('Location: ' . $url);
    exit;
}

function require_login(): void
{
    if (empty($_SESSION['db_user']) || empty($_SESSION['db_pass'])) {
        redirect('login.php');
    }
}

function pdo_from_credentials(string $user, string $password): PDO
{
    $dsn = 'mysql:host=' . DB_HOST .
        ';port=' . DB_PORT .
        ';dbname=' . DB_NAME .
        ';charset=' . DB_CHARSET;

    return new PDO($dsn, $user, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

function db(): PDO
{
    require_login();

    return pdo_from_credentials(
        $_SESSION['db_user'],
        $_SESSION['db_pass']
    );
}

function set_flash(string $type, string $message): void
{
    $_SESSION['flash'] = [
        'type' => $type,
        'message' => $message,
    ];
}

function get_flash(): ?array
{
    if (empty($_SESSION['flash'])) {
        return null;
    }

    $flash = $_SESSION['flash'];
    unset($_SESSION['flash']);

    return $flash;
}

function current_user_info(): ?array
{
    require_login();

    if ($_SESSION['db_user'] === 'root') {
        return [
            'IDUtilizador' => null,
            'Nome' => 'root',
            'Telemovel' => null,
            'Tipo' => 'root',
            'Email' => 'root',
            'DataNascimento' => null,
            'Equipa' => null,
        ];
    }

    try {
        $pdo = db();

        $stmt = $pdo->query(
            'SELECT IDUtilizador, Nome, Telemovel, Tipo, Email, DataNascimento, Equipa
             FROM v_utilizador_atual
             LIMIT 1'
        );

        $user = $stmt->fetch();

        return $user ?: null;
    } catch (Throwable $e) {
        return null;
    }
}

function is_admin_user(): bool
{
    $user = current_user_info();

    if (!$user) {
        return false;
    }

    return $user['Tipo'] === 'root' || $user['Tipo'] === 'AdminApp';
}

function require_admin_user(): void
{
    require_login();

    if (!is_admin_user()) {
        http_response_code(403);
        echo 'Acesso negado.';
        exit;
    }
}

function nullable_string_from_post(string $name): ?string
{
    $value = trim($_POST[$name] ?? '');

    return $value === '' ? null : $value;
}

function nullable_int_from_post(string $name): ?int
{
    $value = trim($_POST[$name] ?? '');

    if ($value === '') {
        return null;
    }

    if (!filter_var($value, FILTER_VALIDATE_INT)) {
        throw new RuntimeException($name . ' invalido.');
    }

    return (int)$value;
}

function nullable_positive_int_from_post(string $name): ?int
{
    $value = trim($_POST[$name] ?? '');

    if ($value === '') {
        return null;
    }

    if (!filter_var($value, FILTER_VALIDATE_INT)) {
        throw new RuntimeException($name . ' invalido.');
    }

    $number = (int)$value;

    if ($number <= 0) {
        throw new RuntimeException($name . ' deve ser maior que zero.');
    }

    return $number;
}

function bind_nullable_string(PDOStatement $stmt, string $name, ?string $value): void
{
    if ($value === null) {
        $stmt->bindValue($name, null, PDO::PARAM_NULL);
    } else {
        $stmt->bindValue($name, $value, PDO::PARAM_STR);
    }
}

function bind_nullable_int(PDOStatement $stmt, string $name, ?int $value): void
{
    if ($value === null) {
        $stmt->bindValue($name, null, PDO::PARAM_NULL);
    } else {
        $stmt->bindValue($name, $value, PDO::PARAM_INT);
    }
}

function json_for_html(array $data): string
{
    return json_encode(
        $data,
        JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_UNESCAPED_UNICODE
    );
}