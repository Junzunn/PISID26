<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

require_login();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirect('simulacoes.php');
}

try {
    $descricao = nullable_string_from_post('descricao');

    $tempoMaxRuido = nullable_string_from_post('tempo_max_ruido');
    $tempoMinRuido = nullable_string_from_post('tempo_min_ruido');
    $thresholdRuido = nullable_string_from_post('threshold_ruido');

    $tempoMaxTemp = nullable_string_from_post('tempo_max_temp');
    $tempoMinTemp = nullable_string_from_post('tempo_min_temp');
    $thresholdTemp = nullable_string_from_post('threshold_temp');

    $janelaOutliers = nullable_string_from_post('janela_outliers');
    $variacaoOutlier = nullable_string_from_post('variacao_outlier');

    $pdo = db();

    $stmt = $pdo->prepare(
        'CALL simulacao_criar(
            :descricao,
            :tempo_max_ruido,
            :tempo_min_ruido,
            :threshold_ruido,
            :tempo_max_temp,
            :tempo_min_temp,
            :threshold_temp,
            :janela_outliers,
            :variacao_outlier
        )'
    );

    bind_nullable_string($stmt, ':descricao', $descricao);
    bind_nullable_string($stmt, ':tempo_max_ruido', $tempoMaxRuido);
    bind_nullable_string($stmt, ':tempo_min_ruido', $tempoMinRuido);
    bind_nullable_string($stmt, ':threshold_ruido', $thresholdRuido);
    bind_nullable_string($stmt, ':tempo_max_temp', $tempoMaxTemp);
    bind_nullable_string($stmt, ':tempo_min_temp', $tempoMinTemp);
    bind_nullable_string($stmt, ':threshold_temp', $thresholdTemp);
    bind_nullable_string($stmt, ':janela_outliers', $janelaOutliers);
    bind_nullable_string($stmt, ':variacao_outlier', $variacaoOutlier);

    $stmt->execute();
    $stmt->closeCursor();

    set_flash('success', 'Simulacao criada com sucesso.');
} catch (Throwable $e) {
    set_flash('error', $e->getMessage());
}

redirect('simulacoes.php');