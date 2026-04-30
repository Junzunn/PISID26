<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

const DB_HOST = '127.0.0.1';
const DB_PORT = 3306;
const DB_CHARSET = 'utf8mb4';

function json_ok($data = null): void
{
    echo json_encode([
        'success' => true,
        'data' => $data
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

function json_error(string $message): void
{
    echo json_encode([
        'success' => false,
        'message' => $message
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

function get_param(string $name): string
{
    $value = trim($_GET[$name] ?? '');

    if ($value === '') {
        json_error("Parametro obrigatorio em falta: " . $name);
    }

    return $value;
}

function db(): PDO
{
    $database = get_param('database');
    $username = get_param('username');
    $password = $_GET['password'] ?? '';

    if (!preg_match('/^[A-Za-z0-9_]+$/', $database)) {
        json_error('Nome da base de dados invalido');
    }

    $dsn = 'mysql:host=' . DB_HOST .
        ';port=' . DB_PORT .
        ';dbname=' . $database .
        ';charset=' . DB_CHARSET;

    return new PDO($dsn, $username, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

function current_running_simulacao_id(PDO $pdo): ?int
{
    $sql = "
        SELECT s.IDSimulacao
        FROM Simulacao s
        INNER JOIN Utilizador u
            ON u.Equipa = s.Equipa
        WHERE u.Email = LEFT(
            USER(),
            CHAR_LENGTH(USER()) - CHAR_LENGTH(SUBSTRING_INDEX(USER(), '@', -1)) - 1
        )
          AND u.Equipa IS NOT NULL
          AND s.DataHorainicio IS NOT NULL
        ORDER BY
            CASE
                WHEN s.DataHoraFim IS NULL THEN 0
                ELSE 1
            END ASC,
            COALESCE(s.DataHoraFim, s.DataHorainicio) DESC,
            s.IDSimulacao DESC
        LIMIT 1
    ";

    $stmt = $pdo->query($sql);
    $row = $stmt->fetch();

    if (!$row) {
        return null;
    }

    return (int)$row['IDSimulacao'];
}
