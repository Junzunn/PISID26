-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- 主机： localhost
-- 生成日期： 2026-04-05 00:17:54
-- 服务器版本： 10.4.28-MariaDB
-- PHP 版本： 8.2.4

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- 数据库： `pisid`
--

DELIMITER $$
--
-- 存储过程
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_atualizar` (IN `p_idSimulacao` INT, IN `p_descricao` TEXT)  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_id_utilizador INT;
    DECLARE v_criador INT;
    DECLARE v_estado VARCHAR(20);
    DECLARE v_sim_exists INT DEFAULT 0;

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = v_current_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    SELECT IDUtilizador
      INTO v_id_utilizador
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    SELECT COUNT(*)
      INTO v_sim_exists
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao;

    IF v_sim_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao indicada nao existe.';
    END IF;

    SELECT IDUtilizadorCriador, Estado
      INTO v_criador, v_estado
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao
     LIMIT 1;

    IF v_id_utilizador <> v_criador THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas o criador da simulacao a pode alterar.';
    END IF;

    IF v_estado <> 'PorIniciar' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao apenas pode ser alterada no estado PorIniciar.';
    END IF;

    UPDATE Simulacao
       SET Descricao = p_descricao
     WHERE IDSimulacao = p_idSimulacao;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_bloquear` (IN `p_idSimulacao` INT, IN `p_sensor` VARCHAR(50), IN `p_tipo_alerta` VARCHAR(50), IN `p_msg` VARCHAR(100), IN `p_hora_evento` DATETIME, IN `p_leitura` DECIMAL(10,2))  MODIFIES SQL DATA BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_estado_atual VARCHAR(20);

    SELECT COUNT(*)
      INTO v_exists
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao existe.';
    END IF;

    SELECT Estado
      INTO v_estado_atual
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao
     LIMIT 1;

    IF v_estado_atual = 'Terminada' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao ja terminou.';
    END IF;

    IF v_estado_atual <> 'Blocked' THEN
        UPDATE Corridor
           SET Active = 0;

        UPDATE Simulacao
           SET Estado = 'Blocked'
         WHERE IDSimulacao = p_idSimulacao;
    END IF;

    CALL sp_log_message(
        p_idSimulacao,
        p_sensor,
        p_tipo_alerta,
        p_msg,
        p_hora_evento,
        p_leitura
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_criar` (IN `p_descricao` TEXT)   proc: BEGIN
    DECLARE v_user_id INT;
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_descricao_final TEXT;

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_exists
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador atual nao encontrado.';
    END IF;

    SELECT IDUtilizador
      INTO v_user_id
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    IF p_descricao IS NULL OR TRIM(p_descricao) = '' THEN
        SET v_descricao_final = NULL;
    ELSE
        SET v_descricao_final = p_descricao;
    END IF;

    INSERT INTO Simulacao (
        IDUtilizadorCriador,
        Descricao,
        DataHoraInicio,
        DataHoraFim,
        Estado
    )
    VALUES (
        v_user_id,
        v_descricao_final,
        NULL,
        NULL,
        'PorIniciar'
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_iniciar` (IN `p_idSimulacao` INT)   proc: BEGIN
    DECLARE v_equipa_user INT;
    DECLARE v_equipa_simulacao INT;
    DECLARE v_estado VARCHAR(20);
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_current_username VARCHAR(50);

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_exists
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador atual nao encontrado.';
    END IF;

    SELECT Equipa
      INTO v_equipa_user
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    SELECT COUNT(*)
      INTO v_exists
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao
     LIMIT 1;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao encontrada.';
    END IF;

    SELECT u.Equipa, s.Estado
      INTO v_equipa_simulacao, v_estado
      FROM Simulacao s
      JOIN Utilizador u
        ON u.IDUtilizador = s.IDUtilizadorCriador
     WHERE s.IDSimulacao = p_idSimulacao
     LIMIT 1;

    IF v_equipa_user <> v_equipa_simulacao THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nao tem permissao para iniciar esta simulacao.';
    END IF;

    IF v_estado <> 'PorIniciar' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao nao pode ser iniciada neste estado.';
    END IF;

    UPDATE Simulacao
       SET Estado = 'ACorrer',
           DataHorainicio = NOW()
     WHERE IDSimulacao = p_idSimulacao;

    UPDATE Corridor
       SET Active = 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_terminar` (IN `p_idSimulacao` INT)  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_id_utilizador INT;
    DECLARE v_criador INT;
    DECLARE v_estado VARCHAR(20);
    DECLARE v_sim_exists INT DEFAULT 0;

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = v_current_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    SELECT IDUtilizador
      INTO v_id_utilizador
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    SELECT COUNT(*)
      INTO v_sim_exists
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao;

    IF v_sim_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao indicada nao existe.';
    END IF;

    SELECT IDUtilizadorCriador, Estado
      INTO v_criador, v_estado
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao
     LIMIT 1;

    IF v_id_utilizador <> v_criador THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas o criador da simulacao a pode terminar antecipadamente.';
    END IF;

    IF v_estado = 'Terminada' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao ja terminou.';
    END IF;

    IF v_estado = 'PorIniciar' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao ainda nao foi iniciada.';
    END IF;

    UPDATE Simulacao
       SET Estado = 'Terminada',
           DataHoraFim = COALESCE(DataHoraFim, NOW())
     WHERE IDSimulacao = p_idSimulacao;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_log_message` (IN `p_id_simulacao` INT, IN `p_sensor` VARCHAR(50), IN `p_tipo_alerta` VARCHAR(100), IN `p_msg` TEXT, IN `p_hora_evento` DATETIME, IN `p_valor` DECIMAL(10,2))   proc: BEGIN
    DECLARE v_last_event_time DATETIME DEFAULT NULL;

    IF p_hora_evento IS NULL THEN
        SET p_hora_evento = NOW();
    END IF;

    IF p_tipo_alerta LIKE 'ALERTA\_%' THEN
        SELECT MAX(Hora)
          INTO v_last_event_time
          FROM Mensagens
         WHERE IDSimulacao = p_id_simulacao
           AND TipoAlerta = p_tipo_alerta;

        IF v_last_event_time IS NOT NULL
           AND TIMESTAMPDIFF(SECOND, v_last_event_time, p_hora_evento) < 17 THEN
            LEAVE proc;
        END IF;
    END IF;

    INSERT INTO Mensagens
    (
        Hora,
        Sensor,
        Leitura,
        TipoAlerta,
        Msg,
        HoraEscrita,
        IDSimulacao
    )
    VALUES
    (
        p_hora_evento,
        p_sensor,
        p_valor,
        p_tipo_alerta,
        LEFT(p_msg, 100),
        NOW(),
        p_id_simulacao
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_processar_movimento` (IN `p_sim_id` INT, IN `p_player` INT, IN `p_marsami` INT, IN `p_origin` INT, IN `p_destiny` INT, IN `p_status` INT, IN `p_hora` DATETIME)   BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_tipo VARCHAR(4);
    DECLARE v_total_marsamis INT DEFAULT 0;
    DECLARE v_last_room_alert_time DATETIME DEFAULT NULL;

    SELECT COUNT(*)
      INTO v_exists
      FROM Marsami
     WHERE IDSimulacao = p_sim_id
       AND IDMarsami = p_marsami;

    IF v_exists = 0 THEN

        IF MOD(p_marsami, 2) = 0 THEN
            SET v_tipo = 'even';
        ELSE
            SET v_tipo = 'odd';
        END IF;

        INSERT INTO Marsami
        (
            IDMarsami,
            Player,
            IDSimulacao,
            SalaAtual,
            Tipo,
            Estado,
            UltimaHoraMovimento
        )
        VALUES
        (
            p_marsami,
            p_player,
            p_sim_id,
            p_destiny,
            v_tipo,
            p_status,
            p_hora
        );

        INSERT INTO MedicoesPassagens
        (
            Hora,
            SalaOrigem,
            SalaDestino,
            Marsami,
            Status,
            IDSimulacao
        )
        VALUES
        (
            p_hora,
            p_origin,
            p_destiny,
            p_marsami,
            p_status,
            p_sim_id
        );

        INSERT INTO OcupacaoLabirinto
        (
            IDSimulacao,
            Sala,
            NumeroOdds,
            NumeroEvens
        )
        VALUES
        (
            p_sim_id,
            p_destiny,
            IF(v_tipo = 'odd', 1, 0),
            IF(v_tipo = 'even', 1, 0)
        )
        ON DUPLICATE KEY UPDATE
            NumeroOdds  = NumeroOdds + IF(v_tipo = 'odd', 1, 0),
            NumeroEvens = NumeroEvens + IF(v_tipo = 'even', 1, 0);

        SELECT COALESCE(NumeroOdds, 0) + COALESCE(NumeroEvens, 0)
          INTO v_total_marsamis
          FROM OcupacaoLabirinto
         WHERE IDSimulacao = p_sim_id
           AND Sala = p_destiny;

        IF v_total_marsamis >= 6 THEN
            SELECT MAX(Hora)
              INTO v_last_room_alert_time
              FROM Mensagens
             WHERE IDSimulacao = p_sim_id
               AND TipoAlerta = 'ALERTA_SALA_CHEIA'
               AND COALESCE(Msg, '') LIKE CONCAT('%Sala ', p_destiny, ' %');

            IF v_last_room_alert_time IS NULL
               OR TIMESTAMPDIFF(SECOND, v_last_room_alert_time, p_hora) >= 10 THEN
                CALL sp_log_message(
                    p_sim_id,
                    'movement',
                    'ALERTA_SALA_CHEIA',
                    CONCAT('Sala ', p_destiny, ' atingiu ocupacao maxima: ', v_total_marsamis),
                    p_hora,
                    v_total_marsamis
                );
            END IF;
        END IF;

    ELSE

        SELECT Tipo
          INTO v_tipo
          FROM Marsami
         WHERE IDSimulacao = p_sim_id
           AND IDMarsami = p_marsami
         LIMIT 1;

        INSERT INTO MedicoesPassagens
        (
            Hora,
            SalaOrigem,
            SalaDestino,
            Marsami,
            Status,
            IDSimulacao
        )
        VALUES
        (
            p_hora,
            p_origin,
            p_destiny,
            p_marsami,
            p_status,
            p_sim_id
        );

        IF p_origin = 0 AND p_destiny = 0 THEN

            UPDATE Marsami
               SET Estado = p_status,
                   UltimaHoraMovimento = p_hora
             WHERE IDSimulacao = p_sim_id
               AND IDMarsami = p_marsami;

        ELSE

            INSERT INTO OcupacaoLabirinto
            (
                IDSimulacao,
                Sala,
                NumeroOdds,
                NumeroEvens
            )
            VALUES
            (
                p_sim_id,
                p_origin,
                0,
                0
            )
            ON DUPLICATE KEY UPDATE
                NumeroOdds  = IF(v_tipo = 'odd',  GREATEST(0, NumeroOdds - 1), NumeroOdds),
                NumeroEvens = IF(v_tipo = 'even', GREATEST(0, NumeroEvens - 1), NumeroEvens);

            INSERT INTO OcupacaoLabirinto
            (
                IDSimulacao,
                Sala,
                NumeroOdds,
                NumeroEvens
            )
            VALUES
            (
                p_sim_id,
                p_destiny,
                IF(v_tipo = 'odd', 1, 0),
                IF(v_tipo = 'even', 1, 0)
            )
            ON DUPLICATE KEY UPDATE
                NumeroOdds  = NumeroOdds + IF(v_tipo = 'odd', 1, 0),
                NumeroEvens = NumeroEvens + IF(v_tipo = 'even', 1, 0);

            UPDATE Marsami
               SET SalaAtual = p_destiny,
                   Estado = p_status,
                   UltimaHoraMovimento = p_hora
             WHERE IDSimulacao = p_sim_id
               AND IDMarsami = p_marsami;

            SELECT COALESCE(NumeroOdds, 0) + COALESCE(NumeroEvens, 0)
              INTO v_total_marsamis
              FROM OcupacaoLabirinto
             WHERE IDSimulacao = p_sim_id
               AND Sala = p_destiny;

            IF v_total_marsamis >= 6 THEN
                SELECT MAX(Hora)
                  INTO v_last_room_alert_time
                  FROM Mensagens
                 WHERE IDSimulacao = p_sim_id
                   AND TipoAlerta = 'ALERTA_SALA_CHEIA'
                   AND COALESCE(Msg, '') LIKE CONCAT('%Sala ', p_destiny, ' %');

                IF v_last_room_alert_time IS NULL
                   OR TIMESTAMPDIFF(SECOND, v_last_room_alert_time, p_hora) >= 10 THEN
                    CALL sp_log_message(
                        p_sim_id,
                        'movement',
                        'ALERTA_SALA_CHEIA',
                        CONCAT('Sala ', p_destiny, ' atingiu ocupacao maxima: ', v_total_marsamis),
                        p_hora,
                        v_total_marsamis
                    );
                END IF;
            END IF;

        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM Marsami
         WHERE IDSimulacao = p_sim_id
    )
    AND NOT EXISTS (
        SELECT 1
          FROM Marsami
         WHERE IDSimulacao = p_sim_id
           AND Estado <> 2
    )
    THEN
        UPDATE Simulacao
           SET Estado = 'Terminada',
               DataHoraFim = COALESCE(DataHoraFim, p_hora)
         WHERE IDSimulacao = p_sim_id
           AND Estado <> 'Terminada';
    END IF;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_processar_ruido` (IN `p_sim_id` INT, IN `p_hora` DATETIME, IN `p_val` DECIMAL(10,2))   proc: BEGIN
    DECLARE v_is_outlier BOOLEAN DEFAULT FALSE;
    DECLARE v_last_alert_time DATETIME DEFAULT NULL;
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;

    DECLARE v_window_size INT DEFAULT 10;
    DECLARE v_min_sample INT DEFAULT 5;
    DECLARE v_threshold DECIMAL(10,4) DEFAULT 3.0;

    DECLARE v_total_count INT DEFAULT 0;
    DECLARE v_sample_size INT DEFAULT 0;
    DECLARE v_offset_idx INT DEFAULT 0;
    DECLARE v_take_count INT DEFAULT 1;

    DECLARE v_median DECIMAL(12,4) DEFAULT NULL;
    DECLARE v_mad DECIMAL(12,4) DEFAULT NULL;
    DECLARE v_robust_z DECIMAL(12,4) DEFAULT NULL;

    SELECT Estado
      INTO v_estado
      FROM Simulacao
     WHERE IDSimulacao = p_sim_id
     LIMIT 1;

    IF v_estado <> 'ACorrer' THEN
        LEAVE proc;
    END IF;

    SELECT COUNT(*)
      INTO v_total_count
      FROM Som
     WHERE IDSimulacao = p_sim_id;

    SET v_sample_size = LEAST(v_total_count, v_window_size);

    IF v_sample_size >= v_min_sample THEN
        SET v_offset_idx = FLOOR((v_sample_size - 1) / 2);
        SET v_take_count = 2 - MOD(v_sample_size, 2);

        SELECT AVG(t.val)
          INTO v_median
          FROM (
                SELECT r.val
                  FROM (
                        SELECT Som AS val
                          FROM Som
                         WHERE IDSimulacao = p_sim_id
                         ORDER BY Hora DESC
                         LIMIT v_window_size
                       ) r
                 ORDER BY r.val
                 LIMIT v_take_count OFFSET v_offset_idx
               ) t;

        SELECT AVG(t.abs_dev)
          INTO v_mad
          FROM (
                SELECT d.abs_dev
                  FROM (
                        SELECT ABS(r2.val - v_median) AS abs_dev
                          FROM (
                                SELECT Som AS val
                                  FROM Som
                                 WHERE IDSimulacao = p_sim_id
                                 ORDER BY Hora DESC
                                 LIMIT v_window_size
                               ) r2
                       ) d
                 ORDER BY d.abs_dev
                 LIMIT v_take_count OFFSET v_offset_idx
               ) t;

        IF v_mad IS NOT NULL AND v_mad > 0 THEN
            SET v_robust_z = 0.6745 * ABS(p_val - v_median) / v_mad;

            IF v_robust_z > v_threshold THEN
                SET v_is_outlier = TRUE;
            END IF;
        END IF;
    END IF;

    INSERT INTO Som (Hora, Som, IDSimulacao)
    VALUES (p_hora, p_val, p_sim_id);

    IF v_is_outlier THEN
        CALL sp_log_message(
            p_sim_id,
            'SOUND',
            'OUTLIER_SOM',
            CONCAT(
                'Sound outlier detected | value=', p_val,
                ' | median=', COALESCE(v_median, -1),
                ' | mad=', COALESCE(v_mad, -1),
                ' | robust_z=', COALESCE(v_robust_z, -1)
            ),
            p_hora,
            p_val
        );
    END IF;

    /* aproximacao ao maximo: >=22 e <27 */
    IF p_val >= 22 AND p_val < 27 THEN
        SELECT MAX(HoraEscrita)
          INTO v_last_alert_time
          FROM Mensagens
         WHERE IDSimulacao = p_sim_id
           AND TipoAlerta = 'ALERTA_SOM';

        IF v_last_alert_time IS NULL
           OR TIMESTAMPDIFF(SECOND, v_last_alert_time, NOW()) >= 10 THEN
            CALL sp_log_message(
                p_sim_id,
                'SOUND',
                'ALERTA_SOM',
                'High sound alert',
                p_hora,
                p_val
            );
        END IF;
    END IF;

    /* maximo atingido: >=27 e <60 */
    IF p_val >= 27 AND p_val < 60 THEN
        CALL simulacao_bloquear(
            p_sim_id,
            'SOUND',
            'BLOQUEIO_SOM',
            'Maximum sound reached - close all doors',
            p_hora,
            p_val
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_processar_temperatura` (IN `p_sim_id` INT, IN `p_hora` DATETIME, IN `p_val` DECIMAL(10,2))   proc: BEGIN
    DECLARE v_is_outlier BOOLEAN DEFAULT FALSE;
    DECLARE v_last_alert_time DATETIME DEFAULT NULL;
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;

    DECLARE v_window_size INT DEFAULT 15;
    DECLARE v_min_sample INT DEFAULT 7;
    DECLARE v_threshold DECIMAL(10,4) DEFAULT 3.5;

    DECLARE v_total_count INT DEFAULT 0;
    DECLARE v_sample_size INT DEFAULT 0;
    DECLARE v_offset_idx INT DEFAULT 0;
    DECLARE v_take_count INT DEFAULT 1;

    DECLARE v_median DECIMAL(12,4) DEFAULT NULL;
    DECLARE v_mad DECIMAL(12,4) DEFAULT NULL;
    DECLARE v_robust_z DECIMAL(12,4) DEFAULT NULL;

    SELECT Estado
      INTO v_estado
      FROM Simulacao
     WHERE IDSimulacao = p_sim_id
     LIMIT 1;

    IF v_estado <> 'ACorrer' THEN
        LEAVE proc;
    END IF;

    SELECT COUNT(*)
      INTO v_total_count
      FROM Temperatura
     WHERE IDSimulacao = p_sim_id;

    SET v_sample_size = LEAST(v_total_count, v_window_size);

    IF v_sample_size >= v_min_sample THEN
        SET v_offset_idx = FLOOR((v_sample_size - 1) / 2);
        SET v_take_count = 2 - MOD(v_sample_size, 2);

        SELECT AVG(t.val)
          INTO v_median
          FROM (
                SELECT r.val
                  FROM (
                        SELECT Temperatura AS val
                          FROM Temperatura
                         WHERE IDSimulacao = p_sim_id
                         ORDER BY Hora DESC
                         LIMIT v_window_size
                       ) r
                 ORDER BY r.val
                 LIMIT v_take_count OFFSET v_offset_idx
               ) t;

        SELECT AVG(t.abs_dev)
          INTO v_mad
          FROM (
                SELECT d.abs_dev
                  FROM (
                        SELECT ABS(r2.val - v_median) AS abs_dev
                          FROM (
                                SELECT Temperatura AS val
                                  FROM Temperatura
                                 WHERE IDSimulacao = p_sim_id
                                 ORDER BY Hora DESC
                                 LIMIT v_window_size
                               ) r2
                       ) d
                 ORDER BY d.abs_dev
                 LIMIT v_take_count OFFSET v_offset_idx
               ) t;

        IF v_mad IS NOT NULL AND v_mad > 0 THEN
            SET v_robust_z = 0.6745 * ABS(p_val - v_median) / v_mad;

            IF v_robust_z > v_threshold THEN
                SET v_is_outlier = TRUE;
            END IF;
        END IF;
    END IF;

    INSERT INTO Temperatura (Hora, Temperatura, IDSimulacao)
    VALUES (p_hora, p_val, p_sim_id);

    IF v_is_outlier THEN
        CALL sp_log_message(
            p_sim_id,
            'TEMPERATURE',
            'OUTLIER_TEMPERATURA',
            CONCAT(
                'Temperature outlier detected | value=', p_val,
                ' | median=', COALESCE(v_median, -1),
                ' | mad=', COALESCE(v_mad, -1),
                ' | robust_z=', COALESCE(v_robust_z, -1)
            ),
            p_hora,
            p_val
        );
    END IF;

    /* aproximacao ao maximo: >=20 e <25 */
    IF p_val >= 20 AND p_val < 25 THEN
        SELECT MAX(HoraEscrita)
          INTO v_last_alert_time
          FROM Mensagens
         WHERE IDSimulacao = p_sim_id
           AND TipoAlerta = 'ALERTA_TEMPERATURA';

        IF v_last_alert_time IS NULL
           OR TIMESTAMPDIFF(SECOND, v_last_alert_time, NOW()) >= 10 THEN
            CALL sp_log_message(
                p_sim_id,
                'TEMPERATURE',
                'ALERTA_TEMPERATURA',
                'High temperature alert',
                p_hora,
                p_val
            );
        END IF;
    END IF;

    /* maximo atingido: >=25 e <60 */
    IF p_val >= 25 AND p_val < 60 THEN
        CALL simulacao_bloquear(
            p_sim_id,
            'TEMPERATURE',
            'BLOQUEIO_TEMPERATURA',
            'Maximum temperature reached - close all doors',
            p_hora,
            p_val
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_tentar_score` (IN `p_id_simulacao` INT, IN `p_sala` INT)   proc: BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_equipa_user INT;
    DECLARE v_equipa_sim INT;
    DECLARE v_id_utilizador INT;
    DECLARE v_odd INT DEFAULT 0;
    DECLARE v_even INT DEFAULT 0;
    DECLARE v_tentativas_usadas INT DEFAULT 0;
    DECLARE v_num_tentativa INT DEFAULT 0;
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_delta_pontos DECIMAL(4,2) DEFAULT 0.0;
    DECLARE v_resultado VARCHAR(10);
    DECLARE v_current_username VARCHAR(50);

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_exists
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador atual nao encontrado.';
    END IF;

    SELECT IDUtilizador, Equipa
      INTO v_id_utilizador, v_equipa_user
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    SELECT COUNT(*)
      INTO v_exists
      FROM Simulacao
     WHERE IDSimulacao = p_id_simulacao
     LIMIT 1;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao encontrada.';
    END IF;

    SELECT s.Estado, u.Equipa
      INTO v_estado, v_equipa_sim
      FROM Simulacao s
      JOIN Utilizador u
        ON u.IDUtilizador = s.IDUtilizadorCriador
     WHERE s.IDSimulacao = p_id_simulacao
     LIMIT 1;

    IF v_equipa_user <> v_equipa_sim THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nao tem permissao para pontuar esta simulacao.';
    END IF;

    IF v_estado NOT IN ('ACorrer', 'Blocked') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao nao esta num estado valido para pontuar.';
    END IF;

    SELECT COUNT(*)
      INTO v_exists
      FROM OcupacaoLabirinto
     WHERE IDSimulacao = p_id_simulacao
       AND Sala = p_sala;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sala nao encontrada para esta simulacao.';
    END IF;

    SELECT NumeroOdds, NumeroEvens
      INTO v_odd, v_even
      FROM OcupacaoLabirinto
     WHERE IDSimulacao = p_id_simulacao
       AND Sala = p_sala
     LIMIT 1;

    SELECT COUNT(*)
      INTO v_tentativas_usadas
      FROM ScoreSala
     WHERE IDSimulacao = p_id_simulacao
       AND IDUtilizador = v_id_utilizador
       AND Sala = p_sala;

    IF v_tentativas_usadas >= 3 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Numero maximo de tentativas para esta sala atingido.';
    END IF;

    SET v_num_tentativa = v_tentativas_usadas + 1;

    IF v_odd = v_even AND v_odd <> 0 THEN
        SET v_delta_pontos = 1.0;
        SET v_resultado = 'SUCESSO';
    ELSE
        SET v_delta_pontos = -0.5;
        SET v_resultado = 'FALHADO';
    END IF;

    INSERT INTO ScoreSala (
        IDSimulacao,
        IDUtilizador,
        Sala,
        NumTentativa,
        Hora,
        Resultado,
        Pontos
    )
    VALUES (
        p_id_simulacao,
        v_id_utilizador,
        p_sala,
        v_num_tentativa,
        NOW(),
        v_resultado,
        v_delta_pontos
    );

    CALL sp_log_message(
        p_id_simulacao,
        'SCORE',
        CASE
            WHEN v_resultado = 'SUCESSO' THEN 'SCORE_SUCESSO'
            ELSE 'SCORE_FALHADO'
        END,
        CONCAT(
            'Tentativa ',
            v_num_tentativa,
            ' de score na sala ',
            p_sala,
            ' | odd=',
            v_odd,
            ' even=',
            v_even
        ),
        NOW(),
        v_delta_pontos
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizadorAdmin_alterar_dados` (IN `p_username` VARCHAR(50), IN `p_novo_nome` VARCHAR(100), IN `p_novo_telemovel` VARCHAR(12), IN `p_novo_tipo` VARCHAR(20), IN `p_novo_email` VARCHAR(50), IN `p_nova_data_nascimento` DATE, IN `p_nova_equipa` INT, IN `p_nova_password` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_current_tipo VARCHAR(20);
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_email_exists INT DEFAULT 0;

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT Tipo
      INTO v_current_tipo
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    IF v_current_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    IF v_current_tipo <> 'AdminApp' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas AdminApp pode alterar dados de outros utilizadores.';
    END IF;

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = p_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'O username indicado nao existe.';
    END IF;

    IF p_novo_tipo IS NOT NULL
       AND p_novo_tipo NOT IN ('AdminApp', 'Investigador', 'Tecnico', 'Script') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo invalido. Use AdminApp, Investigador, Tecnico ou Script.';
    END IF;

    IF p_novo_nome IS NULL
       AND p_novo_telemovel IS NULL
       AND p_novo_tipo IS NULL
       AND p_novo_email IS NULL
       AND p_nova_data_nascimento IS NULL
       AND p_nova_equipa IS NULL
       AND p_nova_password IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nenhum dado para alterar.';
    END IF;

    IF p_novo_email IS NOT NULL THEN
        SELECT COUNT(*)
          INTO v_email_exists
          FROM Utilizador
         WHERE Email = p_novo_email
           AND Username <> p_username;

        IF v_email_exists > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ja existe outro utilizador com esse email.';
        END IF;
    END IF;

    UPDATE Utilizador
       SET Nome = COALESCE(p_novo_nome, Nome),
           Telemovel = COALESCE(p_novo_telemovel, Telemovel),
           Tipo = COALESCE(p_novo_tipo, Tipo),
           Email = COALESCE(p_novo_email, Email),
           DataNascimento = COALESCE(p_nova_data_nascimento, DataNascimento),
           Equipa = COALESCE(p_nova_equipa, Equipa),
           Password = COALESCE(p_nova_password, Password)
     WHERE Username = p_username;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizador_alterar_proprios_dados` (IN `p_NovoNome` VARCHAR(100), IN `p_NovoTelemovel` VARCHAR(12), IN `p_NovoEmail` VARCHAR(50), IN `p_NovaDataNascimento` DATE, IN `p_NovaEquipa` INT, IN `p_NovaPassword` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_username VARCHAR(50);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_email_existente INT DEFAULT 0;

    SET v_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
    INTO v_existe
    FROM Utilizador
    WHERE Username = v_username;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    IF p_NovoNome IS NULL
       AND p_NovoTelemovel IS NULL
       AND p_NovoEmail IS NULL
       AND p_NovaDataNascimento IS NULL
       AND p_NovaEquipa IS NULL
       AND p_NovaPassword IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nenhum dado para alterar.';
    END IF;

    IF p_NovoEmail IS NOT NULL THEN
        SELECT COUNT(*)
        INTO v_email_existente
        FROM Utilizador
        WHERE Email = p_NovoEmail
          AND Username <> v_username;

        IF v_email_existente > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ja existe outro utilizador com esse email.';
        END IF;
    END IF;

    UPDATE Utilizador
    SET
        Nome = COALESCE(p_NovoNome, Nome),
        Telemovel = COALESCE(p_NovoTelemovel, Telemovel),
        Email = COALESCE(p_NovoEmail, Email),
        DataNascimento = COALESCE(p_NovaDataNascimento, DataNascimento),
        Equipa = COALESCE(p_NovaEquipa, Equipa),
        Password = COALESCE(p_NovaPassword, Password)
    WHERE Username = v_username;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizador_criar` (IN `p_username` VARCHAR(50), IN `p_nome` VARCHAR(100), IN `p_telemovel` VARCHAR(12), IN `p_tipo` VARCHAR(20), IN `p_email` VARCHAR(50), IN `p_dataNascimento` DATE, IN `p_equipa` INT, IN `p_password` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_role_name VARCHAR(20);

    IF p_tipo NOT IN ('AdminApp', 'Investigador', 'Tecnico', 'Script') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de utilizador invalido. Use AdminApp, Investigador, Tecnico ou Script.';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM Utilizador
     WHERE Username = p_username;

    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ja existe um utilizador com esse username.';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM Utilizador
     WHERE Email = p_email;

    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ja existe um utilizador com esse email.';
    END IF;

    INSERT INTO Utilizador
    (
        Username,
        Nome,
        Telemovel,
        Tipo,
        Email,
        DataNascimento,
        Equipa,
        Password
    )
    VALUES
    (
        p_username,
        p_nome,
        p_telemovel,
        p_tipo,
        p_email,
        p_dataNascimento,
        p_equipa,
        p_password
    );

    SET @sql_create = CONCAT(
        'CREATE USER IF NOT EXISTS ''', p_username, '''@''localhost'' IDENTIFIED BY ''', p_password, ''''
    );
    PREPARE stmt1 FROM @sql_create;
    EXECUTE stmt1;
    DEALLOCATE PREPARE stmt1;

    IF p_tipo = 'AdminApp' THEN
        SET v_role_name = 'role_admin';
    ELSEIF p_tipo = 'Investigador' THEN
        SET v_role_name = 'role_user';
    ELSEIF p_tipo = 'Tecnico' THEN
        SET v_role_name = 'role_tecnico';
    ELSE
        SET v_role_name = 'role_script';
    END IF;

    SET @sql_grant = CONCAT(
        'GRANT `', v_role_name, '` TO ''', p_username, '''@''localhost'''
    );
    PREPARE stmt2 FROM @sql_grant;
    EXECUTE stmt2;
    DEALLOCATE PREPARE stmt2;

    SET @sql_default = CONCAT(
        'SET DEFAULT ROLE `', v_role_name, '` FOR ''', p_username, '''@''localhost'''
    );
    PREPARE stmt3 FROM @sql_default;
    EXECUTE stmt3;
    DEALLOCATE PREPARE stmt3;

    FLUSH PRIVILEGES;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizador_eliminar` (IN `p_username` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_current_tipo VARCHAR(20);
    DECLARE v_user_exists INT DEFAULT 0;

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT Tipo
      INTO v_current_tipo
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    IF v_current_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    IF v_current_tipo <> 'AdminApp' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas AdminApp pode eliminar utilizadores.';
    END IF;

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = p_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'O username indicado nao existe.';
    END IF;

    IF p_username = v_current_username THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nao e permitido eliminar o proprio utilizador.';
    END IF;

    DELETE FROM Utilizador
     WHERE Username = p_username;

    SET @sql_drop_user = CONCAT(
        'DROP USER IF EXISTS ''', p_username, '''@''localhost'''
    );
    PREPARE stmt FROM @sql_drop_user;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    FLUSH PRIVILEGES;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- 表的结构 `Corridor`
--

CREATE TABLE `Corridor` (
  `ID` int(11) NOT NULL,
  `RoomOrigin` int(11) NOT NULL,
  `RoomDestiny` int(11) NOT NULL,
  `Active` tinyint(1) NOT NULL DEFAULT 1,
  `Distance` int(11) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Corridor`
--

INSERT INTO `Corridor` (`ID`, `RoomOrigin`, `RoomDestiny`, `Active`, `Distance`) VALUES
(1, 1, 2, 0, 1),
(2, 1, 3, 0, 1),
(3, 2, 4, 0, 1),
(4, 2, 5, 0, 1),
(5, 3, 2, 0, 1),
(6, 4, 5, 0, 1),
(7, 5, 3, 0, 1),
(8, 5, 6, 0, 1),
(9, 5, 7, 0, 1),
(10, 6, 8, 0, 1),
(11, 7, 5, 0, 1),
(12, 8, 9, 0, 1),
(13, 8, 10, 0, 1),
(14, 9, 7, 0, 1),
(15, 10, 1, 0, 1);

-- --------------------------------------------------------

--
-- 表的结构 `EventosProcessados`
--

CREATE TABLE `EventosProcessados` (
  `EventID` char(64) NOT NULL,
  `IDSimulacao` int(11) NOT NULL,
  `TipoEvento` varchar(20) NOT NULL,
  `EstadoProcessamento` varchar(20) NOT NULL,
  `ProcessedAt` timestamp NULL DEFAULT NULL,
  `ErrorMessage` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `EventosProcessados`
--

INSERT INTO `EventosProcessados` (`EventID`, `IDSimulacao`, `TipoEvento`, `EstadoProcessamento`, `ProcessedAt`, `ErrorMessage`) VALUES
('53:1', 53, 'movement', 'DONE', '2026-03-25 01:27:08', NULL),
('53:10', 53, 'movement', 'DONE', '2026-03-25 01:27:18', NULL),
('53:100', 53, 'sound', 'DONE', '2026-03-25 01:28:16', NULL),
('53:101', 53, 'temperature', 'DONE', '2026-03-25 01:28:16', NULL),
('53:102', 53, 'sound', 'DONE', '2026-03-25 01:28:17', NULL),
('53:103', 53, 'temperature', 'DONE', '2026-03-25 01:28:17', NULL),
('53:104', 53, 'sound', 'DONE', '2026-03-25 01:28:18', NULL),
('53:105', 53, 'temperature', 'INVALID', '2026-03-25 01:28:18', 'Hour invalid'),
('53:106', 53, 'movement', 'DONE', '2026-03-25 01:28:19', NULL),
('53:107', 53, 'sound', 'DONE', '2026-03-25 01:28:19', NULL),
('53:108', 53, 'temperature', 'DONE', '2026-03-25 01:28:20', NULL),
('53:109', 53, 'sound', 'DONE', '2026-03-25 01:28:20', NULL),
('53:11', 53, 'movement', 'DONE', '2026-03-25 01:27:19', NULL),
('53:110', 53, 'temperature', 'DONE', '2026-03-25 01:28:21', NULL),
('53:111', 53, 'sound', 'DONE', '2026-03-25 01:28:21', NULL),
('53:112', 53, 'temperature', 'DONE', '2026-03-25 01:28:22', NULL),
('53:113', 53, 'sound', 'DONE', '2026-03-25 01:28:23', NULL),
('53:114', 53, 'temperature', 'DONE', '2026-03-25 01:28:23', NULL),
('53:115', 53, 'movement', 'DONE', '2026-03-25 01:28:24', NULL),
('53:116', 53, 'sound', 'DONE', '2026-03-25 01:28:24', NULL),
('53:117', 53, 'temperature', 'DONE', '2026-03-25 01:28:24', NULL),
('53:118', 53, 'sound', 'DONE', '2026-03-25 01:28:25', NULL),
('53:119', 53, 'temperature', 'DONE', '2026-03-25 01:28:25', NULL),
('53:12', 53, 'movement', 'DONE', '2026-03-25 01:27:20', NULL),
('53:120', 53, 'sound', 'DONE', '2026-03-25 01:28:26', NULL),
('53:121', 53, 'temperature', 'DONE', '2026-03-25 01:28:26', NULL),
('53:122', 53, 'temperature', 'DONE', '2026-03-25 01:28:27', NULL),
('53:123', 53, 'sound', 'DONE', '2026-03-25 01:28:27', NULL),
('53:124', 53, 'movement', 'INVALID', '2026-03-25 01:28:28', 'Movement invalid: RoomOrigin does not match Marsami current room'),
('53:125', 53, 'movement', 'DONE', '2026-03-25 01:28:28', NULL),
('53:126', 53, 'temperature', 'DONE', '2026-03-25 01:28:28', NULL),
('53:127', 53, 'sound', 'DONE', '2026-03-25 01:28:29', NULL),
('53:128', 53, 'temperature', 'DONE', '2026-03-25 01:28:29', NULL),
('53:129', 53, 'sound', 'DONE', '2026-03-25 01:28:30', NULL),
('53:13', 53, 'movement', 'DONE', '2026-03-25 01:27:21', NULL),
('53:130', 53, 'temperature', 'DONE', '2026-03-25 01:28:30', NULL),
('53:131', 53, 'sound', 'DONE', '2026-03-25 01:28:31', NULL),
('53:132', 53, 'temperature', 'DONE', '2026-03-25 01:28:31', NULL),
('53:133', 53, 'sound', 'DONE', '2026-03-25 01:28:32', NULL),
('53:134', 53, 'movement', 'DONE', '2026-03-25 01:28:32', NULL),
('53:135', 53, 'temperature', 'DONE', '2026-03-25 01:28:33', NULL),
('53:136', 53, 'sound', 'DONE', '2026-03-25 01:28:33', NULL),
('53:137', 53, 'temperature', 'DONE', '2026-03-25 01:28:33', NULL),
('53:138', 53, 'sound', 'DONE', '2026-03-25 01:28:34', NULL),
('53:139', 53, 'temperature', 'DONE', '2026-03-25 01:28:34', NULL),
('53:14', 53, 'movement', 'DONE', '2026-03-25 01:27:22', NULL),
('53:140', 53, 'sound', 'DONE', '2026-03-25 01:28:35', NULL),
('53:141', 53, 'temperature', 'DONE', '2026-03-25 01:28:36', NULL),
('53:142', 53, 'sound', 'DONE', '2026-03-25 01:28:36', NULL),
('53:143', 53, 'movement', 'DONE', '2026-03-25 01:28:36', NULL),
('53:144', 53, 'temperature', 'DONE', '2026-03-25 01:28:37', NULL),
('53:145', 53, 'sound', 'DONE', '2026-03-25 01:28:37', NULL),
('53:146', 53, 'temperature', 'DONE', '2026-03-25 01:28:38', NULL),
('53:147', 53, 'sound', 'DONE', '2026-03-25 01:28:39', NULL),
('53:148', 53, 'temperature', 'DONE', '2026-03-25 01:28:39', NULL),
('53:149', 53, 'temperature', 'DONE', '2026-03-25 01:28:40', NULL),
('53:15', 53, 'movement', 'DONE', '2026-03-25 01:27:23', NULL),
('53:150', 53, 'temperature', 'DONE', '2026-03-25 01:28:41', NULL),
('53:151', 53, 'temperature', 'DONE', '2026-03-25 01:28:42', NULL),
('53:152', 53, 'temperature', 'DONE', '2026-03-25 01:28:43', NULL),
('53:153', 53, 'temperature', 'DONE', '2026-03-25 01:28:44', NULL),
('53:154', 53, 'temperature', 'DONE', '2026-03-25 01:28:45', NULL),
('53:155', 53, 'temperature', 'DONE', '2026-03-25 01:28:47', NULL),
('53:156', 53, 'temperature', 'DONE', '2026-03-25 01:28:48', NULL),
('53:157', 53, 'temperature', 'DONE', '2026-03-25 01:28:49', NULL),
('53:158', 53, 'movement', 'DONE', '2026-03-25 01:28:49', NULL),
('53:159', 53, 'temperature', 'DONE', '2026-03-25 01:28:50', NULL),
('53:16', 53, 'movement', 'DONE', '2026-03-25 01:27:24', NULL),
('53:160', 53, 'temperature', 'DONE', '2026-03-25 01:28:51', NULL),
('53:161', 53, 'temperature', 'DONE', '2026-03-25 01:28:52', NULL),
('53:162', 53, 'movement', 'DONE', '2026-03-25 01:28:53', NULL),
('53:163', 53, 'temperature', 'DONE', '2026-03-25 01:28:53', NULL),
('53:164', 53, 'movement', 'DONE', '2026-03-25 01:28:54', NULL),
('53:165', 53, 'temperature', 'DONE', '2026-03-25 01:28:55', NULL),
('53:166', 53, 'movement', 'DONE', '2026-03-25 01:28:55', NULL),
('53:167', 53, 'temperature', 'DONE', '2026-03-25 01:28:55', NULL),
('53:168', 53, 'movement', 'DONE', '2026-03-25 01:28:56', NULL),
('53:169', 53, 'temperature', 'DONE', '2026-03-25 01:28:56', NULL),
('53:17', 53, 'movement', 'DONE', '2026-03-25 01:27:26', NULL),
('53:170', 53, 'movement', 'DONE', '2026-03-25 01:28:57', NULL),
('53:171', 53, 'movement', 'DONE', '2026-03-25 01:28:57', NULL),
('53:172', 53, 'temperature', 'DONE', '2026-03-25 01:28:58', NULL),
('53:173', 53, 'temperature', 'DONE', '2026-03-25 01:28:59', NULL),
('53:174', 53, 'temperature', 'DONE', '2026-03-25 01:29:00', NULL),
('53:175', 53, 'movement', 'DONE', '2026-03-25 01:29:00', NULL),
('53:176', 53, 'movement', 'DONE', '2026-03-25 01:29:01', NULL),
('53:177', 53, 'temperature', 'DONE', '2026-03-25 01:29:01', NULL),
('53:178', 53, 'movement', 'DONE', '2026-03-25 01:29:01', NULL),
('53:179', 53, 'movement', 'DONE', '2026-03-25 01:29:02', NULL),
('53:18', 53, 'movement', 'DONE', '2026-03-25 01:27:27', NULL),
('53:180', 53, 'temperature', 'DONE', '2026-03-25 01:29:02', NULL),
('53:181', 53, 'movement', 'DONE', '2026-03-25 01:29:03', NULL),
('53:182', 53, 'temperature', 'DONE', '2026-03-25 01:29:03', NULL),
('53:183', 53, 'movement', 'DONE', '2026-03-25 01:29:04', NULL),
('53:184', 53, 'movement', 'DONE', '2026-03-25 01:29:04', NULL),
('53:185', 53, 'temperature', 'DONE', '2026-03-25 01:29:04', NULL),
('53:186', 53, 'movement', 'DONE', '2026-03-25 01:29:05', NULL),
('53:187', 53, 'movement', 'DONE', '2026-03-25 01:29:05', NULL),
('53:188', 53, 'temperature', 'DONE', '2026-03-25 01:29:05', NULL),
('53:189', 53, 'movement', 'DONE', '2026-03-25 01:29:06', NULL),
('53:19', 53, 'movement', 'DONE', '2026-03-25 01:27:29', NULL),
('53:190', 53, 'temperature', 'DONE', '2026-03-25 01:29:06', NULL),
('53:191', 53, 'temperature', 'DONE', '2026-03-25 01:29:08', NULL),
('53:192', 53, 'movement', 'DONE', '2026-03-25 01:29:08', NULL),
('53:193', 53, 'temperature', 'DONE', '2026-03-25 01:29:09', NULL),
('53:194', 53, 'temperature', 'DONE', '2026-03-25 01:29:10', NULL),
('53:195', 53, 'movement', 'DONE', '2026-03-25 01:29:10', NULL),
('53:196', 53, 'movement', 'DONE', '2026-03-25 01:29:10', NULL),
('53:197', 53, 'movement', 'DONE', '2026-03-25 01:29:10', NULL),
('53:198', 53, 'temperature', 'DONE', '2026-03-25 01:29:11', NULL),
('53:199', 53, 'movement', 'DONE', '2026-03-25 01:29:11', NULL),
('53:2', 53, 'movement', 'DONE', '2026-03-25 01:27:09', NULL),
('53:20', 53, 'movement', 'DONE', '2026-03-25 01:27:30', NULL),
('53:200', 53, 'temperature', 'DONE', '2026-03-25 01:29:12', NULL),
('53:201', 53, 'movement', 'DONE', '2026-03-25 01:29:13', NULL),
('53:202', 53, 'temperature', 'DONE', '2026-03-25 01:29:13', NULL),
('53:203', 53, 'movement', 'DONE', '2026-03-25 01:29:14', NULL),
('53:204', 53, 'temperature', 'DONE', '2026-03-25 01:29:14', NULL),
('53:205', 53, 'movement', 'DONE', '2026-03-25 01:29:15', NULL),
('53:206', 53, 'temperature', 'DONE', '2026-03-25 01:29:16', NULL),
('53:207', 53, 'temperature', 'DONE', '2026-03-25 01:29:16', NULL),
('53:208', 53, 'movement', 'DONE', '2026-03-25 01:29:17', NULL),
('53:209', 53, 'movement', 'DONE', '2026-03-25 01:29:18', NULL),
('53:21', 53, 'movement', 'DONE', '2026-03-25 01:27:31', NULL),
('53:210', 53, 'temperature', 'DONE', '2026-03-25 01:29:18', NULL),
('53:211', 53, 'movement', 'DONE', '2026-03-25 01:29:19', NULL),
('53:212', 53, 'temperature', 'DONE', '2026-03-25 01:29:19', NULL),
('53:213', 53, 'movement', 'DONE', '2026-03-25 01:29:20', NULL),
('53:214', 53, 'temperature', 'DONE', '2026-03-25 01:29:20', NULL),
('53:215', 53, 'movement', 'DONE', '2026-03-25 01:29:21', NULL),
('53:22', 53, 'movement', 'DONE', '2026-03-25 01:27:32', NULL),
('53:23', 53, 'movement', 'DONE', '2026-03-25 01:27:33', NULL),
('53:24', 53, 'movement', 'DONE', '2026-03-25 01:27:34', NULL),
('53:25', 53, 'movement', 'DONE', '2026-03-25 01:27:35', NULL),
('53:26', 53, 'movement', 'DONE', '2026-03-25 01:27:36', NULL),
('53:27', 53, 'movement', 'DONE', '2026-03-25 01:27:37', NULL),
('53:28', 53, 'movement', 'DONE', '2026-03-25 01:27:38', NULL),
('53:29', 53, 'movement', 'DONE', '2026-03-25 01:27:39', NULL),
('53:3', 53, 'movement', 'DONE', '2026-03-25 01:27:10', NULL),
('53:30', 53, 'movement', 'DONE', '2026-03-25 01:27:40', NULL),
('53:31', 53, 'movement', 'DONE', '2026-03-25 01:27:41', NULL),
('53:32', 53, 'temperature', 'DONE', '2026-03-25 01:27:43', NULL),
('53:33', 53, 'sound', 'DONE', '2026-03-25 01:27:43', NULL),
('53:34', 53, 'temperature', 'DONE', '2026-03-25 01:27:44', NULL),
('53:35', 53, 'sound', 'DONE', '2026-03-25 01:27:44', NULL),
('53:36', 53, 'temperature', 'DONE', '2026-03-25 01:27:45', NULL),
('53:37', 53, 'sound', 'DONE', '2026-03-25 01:27:46', NULL),
('53:38', 53, 'movement', 'DONE', '2026-03-25 01:27:46', NULL),
('53:39', 53, 'temperature', 'DONE', '2026-03-25 01:27:47', NULL),
('53:4', 53, 'movement', 'DONE', '2026-03-25 01:27:11', NULL),
('53:40', 53, 'sound', 'DONE', '2026-03-25 01:27:47', NULL),
('53:41', 53, 'sound', 'DONE', '2026-03-25 01:27:48', NULL),
('53:42', 53, 'temperature', 'DONE', '2026-03-25 01:27:48', NULL),
('53:43', 53, 'sound', 'DONE', '2026-03-25 01:27:48', NULL),
('53:44', 53, 'temperature', 'DONE', '2026-03-25 01:27:49', NULL),
('53:45', 53, 'sound', 'DONE', '2026-03-25 01:27:49', NULL),
('53:46', 53, 'temperature', 'DONE', '2026-03-25 01:27:50', NULL),
('53:47', 53, 'movement', 'DONE', '2026-03-25 01:27:50', NULL),
('53:48', 53, 'sound', 'DONE', '2026-03-25 01:27:51', NULL),
('53:49', 53, 'temperature', 'DONE', '2026-03-25 01:27:51', NULL),
('53:5', 53, 'movement', 'DONE', '2026-03-25 01:27:12', NULL),
('53:50', 53, 'sound', 'DONE', '2026-03-25 01:27:52', NULL),
('53:51', 53, 'temperature', 'DONE', '2026-03-25 01:27:52', NULL),
('53:52', 53, 'sound', 'DONE', '2026-03-25 01:27:52', NULL),
('53:53', 53, 'temperature', 'DONE', '2026-03-25 01:27:53', NULL),
('53:54', 53, 'sound', 'INVALID', '2026-03-25 01:27:54', 'Hour invalid'),
('53:55', 53, 'temperature', 'DONE', '2026-03-25 01:27:54', NULL),
('53:56', 53, 'movement', 'DONE', '2026-03-25 01:27:55', NULL),
('53:57', 53, 'temperature', 'DONE', '2026-03-25 01:27:55', NULL),
('53:58', 53, 'sound', 'DONE', '2026-03-25 01:27:55', NULL),
('53:59', 53, 'temperature', 'DONE', '2026-03-25 01:27:56', NULL),
('53:6', 53, 'movement', 'DONE', '2026-03-25 01:27:14', NULL),
('53:60', 53, 'sound', 'DONE', '2026-03-25 01:27:56', NULL),
('53:61', 53, 'temperature', 'DONE', '2026-03-25 01:27:57', NULL),
('53:62', 53, 'sound', 'DONE', '2026-03-25 01:27:58', NULL),
('53:63', 53, 'temperature', 'DONE', '2026-03-25 01:27:59', NULL),
('53:64', 53, 'sound', 'DONE', '2026-03-25 01:27:59', NULL),
('53:65', 53, 'movement', 'DONE', '2026-03-25 01:27:59', NULL),
('53:66', 53, 'temperature', 'DONE', '2026-03-25 01:28:00', NULL),
('53:67', 53, 'sound', 'DONE', '2026-03-25 01:28:00', NULL),
('53:68', 53, 'temperature', 'DONE', '2026-03-25 01:28:01', NULL),
('53:69', 53, 'sound', 'DONE', '2026-03-25 01:28:01', NULL),
('53:7', 53, 'movement', 'DONE', '2026-03-25 01:27:15', NULL),
('53:70', 53, 'temperature', 'DONE', '2026-03-25 01:28:01', NULL),
('53:71', 53, 'sound', 'DONE', '2026-03-25 01:28:02', NULL),
('53:72', 53, 'movement', 'DONE', '2026-03-25 01:28:03', NULL),
('53:73', 53, 'temperature', 'DONE', '2026-03-25 01:28:03', NULL),
('53:74', 53, 'sound', 'DONE', '2026-03-25 01:28:03', NULL),
('53:75', 53, 'temperature', 'DONE', '2026-03-25 01:28:04', NULL),
('53:76', 53, 'sound', 'DONE', '2026-03-25 01:28:04', NULL),
('53:77', 53, 'temperature', 'DONE', '2026-03-25 01:28:05', NULL),
('53:78', 53, 'sound', 'DONE', '2026-03-25 01:28:05', NULL),
('53:79', 53, 'sound', 'DONE', '2026-03-25 01:28:06', NULL),
('53:8', 53, 'movement', 'DONE', '2026-03-25 01:27:16', NULL),
('53:80', 53, 'temperature', 'DONE', '2026-03-25 01:28:06', NULL),
('53:81', 53, 'movement', 'DONE', '2026-03-25 01:28:07', NULL),
('53:82', 53, 'sound', 'DONE', '2026-03-25 01:28:07', NULL),
('53:83', 53, 'temperature', 'DONE', '2026-03-25 01:28:07', NULL),
('53:84', 53, 'sound', 'DONE', '2026-03-25 01:28:08', NULL),
('53:85', 53, 'temperature', 'DONE', '2026-03-25 01:28:08', NULL),
('53:86', 53, 'sound', 'DONE', '2026-03-25 01:28:09', NULL),
('53:87', 53, 'temperature', 'DONE', '2026-03-25 01:28:09', NULL),
('53:88', 53, 'sound', 'DONE', '2026-03-25 01:28:10', NULL),
('53:89', 53, 'temperature', 'DONE', '2026-03-25 01:28:11', NULL),
('53:9', 53, 'movement', 'DONE', '2026-03-25 01:27:17', NULL),
('53:90', 53, 'movement', 'DONE', '2026-03-25 01:28:11', NULL),
('53:91', 53, 'sound', 'DONE', '2026-03-25 01:28:12', NULL),
('53:92', 53, 'temperature', 'DONE', '2026-03-25 01:28:12', NULL),
('53:93', 53, 'sound', 'DONE', '2026-03-25 01:28:13', NULL),
('53:94', 53, 'temperature', 'DONE', '2026-03-25 01:28:13', NULL),
('53:95', 53, 'sound', 'DONE', '2026-03-25 01:28:14', NULL),
('53:96', 53, 'temperature', 'DONE', '2026-03-25 01:28:14', NULL),
('53:97', 53, 'sound', 'DONE', '2026-03-25 01:28:15', NULL),
('53:98', 53, 'temperature', 'DONE', '2026-03-25 01:28:15', NULL),
('53:99', 53, 'movement', 'DONE', '2026-03-25 01:28:15', NULL),
('54:1', 54, 'movement', 'DONE', '2026-03-25 01:41:46', NULL),
('54:10', 54, 'movement', 'DONE', '2026-03-25 01:41:56', NULL),
('54:100', 54, 'sound', 'DONE', '2026-03-25 01:42:54', NULL),
('54:101', 54, 'temperature', 'DONE', '2026-03-25 01:42:54', NULL),
('54:102', 54, 'sound', 'DONE', '2026-03-25 01:42:54', NULL),
('54:103', 54, 'temperature', 'DONE', '2026-03-25 01:42:55', NULL),
('54:104', 54, 'sound', 'DONE', '2026-03-25 01:42:55', NULL),
('54:105', 54, 'temperature', 'INVALID', '2026-03-25 01:42:56', 'Hour invalid'),
('54:106', 54, 'movement', 'DONE', '2026-03-25 01:42:57', NULL),
('54:107', 54, 'sound', 'DONE', '2026-03-25 01:42:57', NULL),
('54:108', 54, 'temperature', 'DONE', '2026-03-25 01:42:57', NULL),
('54:109', 54, 'sound', 'DONE', '2026-03-25 01:42:58', NULL),
('54:11', 54, 'movement', 'DONE', '2026-03-25 01:41:57', NULL),
('54:110', 54, 'temperature', 'DONE', '2026-03-25 01:42:58', NULL),
('54:111', 54, 'sound', 'DONE', '2026-03-25 01:42:59', NULL),
('54:112', 54, 'temperature', 'DONE', '2026-03-25 01:42:59', NULL),
('54:113', 54, 'sound', 'DONE', '2026-03-25 01:43:00', NULL),
('54:114', 54, 'temperature', 'DONE', '2026-03-25 01:43:00', NULL),
('54:115', 54, 'movement', 'DONE', '2026-03-25 01:43:01', NULL),
('54:116', 54, 'sound', 'DONE', '2026-03-25 01:43:01', NULL),
('54:117', 54, 'temperature', 'DONE', '2026-03-25 01:43:01', NULL),
('54:118', 54, 'sound', 'DONE', '2026-03-25 01:43:02', NULL),
('54:119', 54, 'temperature', 'DONE', '2026-03-25 01:43:02', NULL),
('54:12', 54, 'movement', 'DONE', '2026-03-25 01:41:58', NULL),
('54:120', 54, 'sound', 'DONE', '2026-03-25 01:43:03', NULL),
('54:121', 54, 'temperature', 'DONE', '2026-03-25 01:43:03', NULL),
('54:122', 54, 'sound', 'DONE', '2026-03-25 01:43:04', NULL),
('54:123', 54, 'temperature', 'DONE', '2026-03-25 01:43:05', NULL),
('54:124', 54, 'movement', 'INVALID', '2026-03-25 01:43:05', 'Movement invalid: RoomOrigin does not match Marsami current room'),
('54:125', 54, 'movement', 'DONE', '2026-03-25 01:43:05', NULL),
('54:126', 54, 'sound', 'DONE', '2026-03-25 01:43:06', NULL),
('54:127', 54, 'temperature', 'DONE', '2026-03-25 01:43:06', NULL),
('54:128', 54, 'temperature', 'DONE', '2026-03-25 01:43:07', NULL),
('54:129', 54, 'sound', 'DONE', '2026-03-25 01:43:07', NULL),
('54:13', 54, 'movement', 'DONE', '2026-03-25 01:41:59', NULL),
('54:130', 54, 'sound', 'DONE', '2026-03-25 01:43:08', NULL),
('54:131', 54, 'temperature', 'DONE', '2026-03-25 01:43:08', NULL),
('54:132', 54, 'sound', 'DONE', '2026-03-25 01:43:09', NULL),
('54:133', 54, 'temperature', 'DONE', '2026-03-25 01:43:09', NULL),
('54:134', 54, 'movement', 'DONE', '2026-03-25 01:43:10', NULL),
('54:135', 54, 'sound', 'DONE', '2026-03-25 01:43:10', NULL),
('54:136', 54, 'temperature', 'DONE', '2026-03-25 01:43:10', NULL),
('54:137', 54, 'sound', 'DONE', '2026-03-25 01:43:11', NULL),
('54:138', 54, 'temperature', 'DONE', '2026-03-25 01:43:11', NULL),
('54:139', 54, 'sound', 'DONE', '2026-03-25 01:43:12', NULL),
('54:14', 54, 'movement', 'DONE', '2026-03-25 01:42:00', NULL),
('54:140', 54, 'temperature', 'DONE', '2026-03-25 01:43:13', NULL),
('54:141', 54, 'sound', 'DONE', '2026-03-25 01:43:14', NULL),
('54:142', 54, 'movement', 'DONE', '2026-03-25 01:43:14', NULL),
('54:143', 54, 'temperature', 'DONE', '2026-03-25 01:43:14', NULL),
('54:144', 54, 'sound', 'DONE', '2026-03-25 01:43:14', NULL),
('54:145', 54, 'temperature', 'DONE', '2026-03-25 01:43:15', NULL),
('54:146', 54, 'sound', 'DONE', '2026-03-25 01:43:16', NULL),
('54:147', 54, 'temperature', 'DONE', '2026-03-25 01:43:16', NULL),
('54:148', 54, 'temperature', 'DONE', '2026-03-25 01:43:17', NULL),
('54:149', 54, 'temperature', 'DONE', '2026-03-25 01:43:18', NULL),
('54:15', 54, 'movement', 'DONE', '2026-03-25 01:42:01', NULL),
('54:150', 54, 'temperature', 'DONE', '2026-03-25 01:43:19', NULL),
('54:151', 54, 'temperature', 'DONE', '2026-03-25 01:43:20', NULL),
('54:152', 54, 'temperature', 'DONE', '2026-03-25 01:43:21', NULL),
('54:153', 54, 'temperature', 'DONE', '2026-03-25 01:43:22', NULL),
('54:154', 54, 'temperature', 'DONE', '2026-03-25 01:43:23', NULL),
('54:155', 54, 'temperature', 'DONE', '2026-03-25 01:43:25', NULL),
('54:156', 54, 'temperature', 'DONE', '2026-03-25 01:43:26', NULL),
('54:157', 54, 'movement', 'DONE', '2026-03-25 01:43:26', NULL),
('54:158', 54, 'temperature', 'DONE', '2026-03-25 01:43:27', NULL),
('54:159', 54, 'movement', 'DONE', '2026-03-25 01:43:27', NULL),
('54:16', 54, 'movement', 'DONE', '2026-03-25 01:42:02', NULL),
('54:160', 54, 'temperature', 'DONE', '2026-03-25 01:43:28', NULL),
('54:161', 54, 'movement', 'DONE', '2026-03-25 01:43:28', NULL),
('54:162', 54, 'temperature', 'DONE', '2026-03-25 01:43:29', NULL),
('54:163', 54, 'movement', 'DONE', '2026-03-25 01:43:29', NULL),
('54:164', 54, 'movement', 'DONE', '2026-03-25 01:43:30', NULL),
('54:165', 54, 'temperature', 'DONE', '2026-03-25 01:43:30', NULL),
('54:166', 54, 'temperature', 'DONE', '2026-03-25 01:43:31', NULL),
('54:167', 54, 'temperature', 'DONE', '2026-03-25 01:43:32', NULL),
('54:168', 54, 'movement', 'DONE', '2026-03-25 01:43:33', NULL),
('54:169', 54, 'temperature', 'DONE', '2026-03-25 01:43:34', NULL),
('54:17', 54, 'movement', 'DONE', '2026-03-25 01:42:03', NULL),
('54:170', 54, 'temperature', 'DONE', '2026-03-25 01:43:35', NULL),
('54:171', 54, 'movement', 'DONE', '2026-03-25 01:43:35', NULL),
('54:172', 54, 'movement', 'DONE', '2026-03-25 01:43:35', NULL),
('54:173', 54, 'temperature', 'DONE', '2026-03-25 01:43:36', NULL),
('54:174', 54, 'movement', 'DONE', '2026-03-25 01:43:37', NULL),
('54:175', 54, 'temperature', 'DONE', '2026-03-25 01:43:37', NULL),
('54:176', 54, 'temperature', 'DONE', '2026-03-25 01:43:38', NULL),
('54:177', 54, 'movement', 'DONE', '2026-03-25 01:43:38', NULL),
('54:178', 54, 'temperature', 'DONE', '2026-03-25 01:43:39', NULL),
('54:179', 54, 'movement', 'DONE', '2026-03-25 01:43:39', NULL),
('54:18', 54, 'movement', 'DONE', '2026-03-25 01:42:04', NULL),
('54:180', 54, 'movement', 'DONE', '2026-03-25 01:43:40', NULL),
('54:181', 54, 'temperature', 'DONE', '2026-03-25 01:43:40', NULL),
('54:182', 54, 'movement', 'DONE', '2026-03-25 01:43:41', NULL),
('54:183', 54, 'temperature', 'DONE', '2026-03-25 01:43:41', NULL),
('54:184', 54, 'movement', 'DONE', '2026-03-25 01:43:42', NULL),
('54:185', 54, 'temperature', 'DONE', '2026-03-25 01:43:43', NULL),
('54:186', 54, 'movement', 'DONE', '2026-03-25 01:43:43', NULL),
('54:187', 54, 'movement', 'DONE', '2026-03-25 01:43:43', NULL),
('54:188', 54, 'temperature', 'DONE', '2026-03-25 01:43:44', NULL),
('54:189', 54, 'movement', 'DONE', '2026-03-25 01:43:44', NULL),
('54:19', 54, 'movement', 'DONE', '2026-03-25 01:42:05', NULL),
('54:190', 54, 'temperature', 'DONE', '2026-03-25 01:43:45', NULL),
('54:191', 54, 'movement', 'DONE', '2026-03-25 01:43:45', NULL),
('54:192', 54, 'temperature', 'DONE', '2026-03-25 01:43:46', NULL),
('54:193', 54, 'movement', 'DONE', '2026-03-25 01:43:46', NULL),
('54:194', 54, 'temperature', 'DONE', '2026-03-25 01:43:47', NULL),
('54:195', 54, 'temperature', 'DONE', '2026-03-25 01:43:48', NULL),
('54:196', 54, 'movement', 'DONE', '2026-03-25 01:43:48', NULL),
('54:197', 54, 'temperature', 'DONE', '2026-03-25 01:43:49', NULL),
('54:198', 54, 'movement', 'DONE', '2026-03-25 01:43:50', NULL),
('54:199', 54, 'temperature', 'DONE', '2026-03-25 01:43:50', NULL),
('54:2', 54, 'movement', 'DONE', '2026-03-25 01:41:47', NULL),
('54:20', 54, 'movement', 'DONE', '2026-03-25 01:42:06', NULL),
('54:200', 54, 'movement', 'DONE', '2026-03-25 01:43:50', NULL),
('54:201', 54, 'temperature', 'DONE', '2026-03-25 01:43:51', NULL),
('54:202', 54, 'movement', 'DONE', '2026-03-25 01:43:51', NULL),
('54:203', 54, 'movement', 'DONE', '2026-03-25 01:43:52', NULL),
('54:204', 54, 'temperature', 'DONE', '2026-03-25 01:43:53', NULL),
('54:205', 54, 'movement', 'DONE', '2026-03-25 01:43:53', NULL),
('54:206', 54, 'temperature', 'DONE', '2026-03-25 01:43:54', NULL),
('54:207', 54, 'movement', 'DONE', '2026-03-25 01:43:54', NULL),
('54:208', 54, 'movement', 'DONE', '2026-03-25 01:43:55', NULL),
('54:209', 54, 'temperature', 'DONE', '2026-03-25 01:43:55', NULL),
('54:21', 54, 'movement', 'DONE', '2026-03-25 01:42:07', NULL),
('54:210', 54, 'temperature', 'DONE', '2026-03-25 01:43:56', NULL),
('54:211', 54, 'movement', 'DONE', '2026-03-25 01:43:56', NULL),
('54:212', 54, 'temperature', 'DONE', '2026-03-25 01:43:57', NULL),
('54:213', 54, 'movement', 'DONE', '2026-03-25 01:43:57', NULL),
('54:214', 54, 'temperature', 'DONE', '2026-03-25 01:43:58', NULL),
('54:215', 54, 'movement', 'DONE', '2026-03-25 01:43:58', NULL),
('54:22', 54, 'movement', 'DONE', '2026-03-25 01:42:09', NULL),
('54:23', 54, 'movement', 'DONE', '2026-03-25 01:42:10', NULL),
('54:24', 54, 'movement', 'DONE', '2026-03-25 01:42:11', NULL),
('54:25', 54, 'movement', 'DONE', '2026-03-25 01:42:12', NULL),
('54:26', 54, 'movement', 'DONE', '2026-03-25 01:42:13', NULL),
('54:27', 54, 'movement', 'DONE', '2026-03-25 01:42:14', NULL),
('54:28', 54, 'movement', 'DONE', '2026-03-25 01:42:15', NULL),
('54:29', 54, 'movement', 'DONE', '2026-03-25 01:42:16', NULL),
('54:3', 54, 'movement', 'DONE', '2026-03-25 01:41:48', NULL),
('54:30', 54, 'movement', 'DONE', '2026-03-25 01:42:18', NULL),
('54:31', 54, 'movement', 'DONE', '2026-03-25 01:42:19', NULL),
('54:32', 54, 'temperature', 'DONE', '2026-03-25 01:42:20', NULL),
('54:33', 54, 'sound', 'DONE', '2026-03-25 01:42:20', NULL),
('54:34', 54, 'temperature', 'DONE', '2026-03-25 01:42:21', NULL),
('54:35', 54, 'sound', 'DONE', '2026-03-25 01:42:22', NULL),
('54:36', 54, 'temperature', 'DONE', '2026-03-25 01:42:23', NULL),
('54:37', 54, 'sound', 'DONE', '2026-03-25 01:42:23', NULL),
('54:38', 54, 'movement', 'DONE', '2026-03-25 01:42:23', NULL),
('54:39', 54, 'temperature', 'DONE', '2026-03-25 01:42:24', NULL),
('54:4', 54, 'movement', 'DONE', '2026-03-25 01:41:49', NULL),
('54:40', 54, 'sound', 'DONE', '2026-03-25 01:42:24', NULL),
('54:41', 54, 'temperature', 'DONE', '2026-03-25 01:42:25', NULL),
('54:42', 54, 'sound', 'DONE', '2026-03-25 01:42:25', NULL),
('54:43', 54, 'sound', 'DONE', '2026-03-25 01:42:26', NULL),
('54:44', 54, 'temperature', 'DONE', '2026-03-25 01:42:26', NULL),
('54:45', 54, 'sound', 'DONE', '2026-03-25 01:42:27', NULL),
('54:46', 54, 'temperature', 'DONE', '2026-03-25 01:42:27', NULL),
('54:47', 54, 'movement', 'DONE', '2026-03-25 01:42:27', NULL),
('54:48', 54, 'sound', 'DONE', '2026-03-25 01:42:28', NULL),
('54:49', 54, 'temperature', 'DONE', '2026-03-25 01:42:28', NULL),
('54:5', 54, 'movement', 'DONE', '2026-03-25 01:41:50', NULL),
('54:50', 54, 'sound', 'DONE', '2026-03-25 01:42:29', NULL),
('54:51', 54, 'temperature', 'DONE', '2026-03-25 01:42:29', NULL),
('54:52', 54, 'sound', 'DONE', '2026-03-25 01:42:30', NULL),
('54:53', 54, 'temperature', 'DONE', '2026-03-25 01:42:30', NULL),
('54:54', 54, 'temperature', 'DONE', '2026-03-25 01:42:31', NULL),
('54:55', 54, 'sound', 'INVALID', '2026-03-25 01:42:32', 'Hour invalid'),
('54:56', 54, 'movement', 'DONE', '2026-03-25 01:42:32', NULL),
('54:57', 54, 'temperature', 'DONE', '2026-03-25 01:42:33', NULL),
('54:58', 54, 'sound', 'DONE', '2026-03-25 01:42:33', NULL),
('54:59', 54, 'sound', 'DONE', '2026-03-25 01:42:34', NULL),
('54:6', 54, 'movement', 'DONE', '2026-03-25 01:41:51', NULL),
('54:60', 54, 'temperature', 'DONE', '2026-03-25 01:42:34', NULL),
('54:61', 54, 'sound', 'DONE', '2026-03-25 01:42:35', NULL),
('54:62', 54, 'temperature', 'DONE', '2026-03-25 01:42:35', NULL),
('54:63', 54, 'temperature', 'DONE', '2026-03-25 01:42:36', NULL),
('54:64', 54, 'sound', 'DONE', '2026-03-25 01:42:36', NULL),
('54:65', 54, 'movement', 'DONE', '2026-03-25 01:42:36', NULL),
('54:66', 54, 'sound', 'DONE', '2026-03-25 01:42:37', NULL),
('54:67', 54, 'temperature', 'DONE', '2026-03-25 01:42:37', NULL),
('54:68', 54, 'sound', 'DONE', '2026-03-25 01:42:38', NULL),
('54:69', 54, 'temperature', 'DONE', '2026-03-25 01:42:38', NULL),
('54:7', 54, 'movement', 'DONE', '2026-03-25 01:41:52', NULL),
('54:70', 54, 'sound', 'DONE', '2026-03-25 01:42:39', NULL),
('54:71', 54, 'temperature', 'DONE', '2026-03-25 01:42:39', NULL),
('54:72', 54, 'movement', 'DONE', '2026-03-25 01:42:40', NULL),
('54:73', 54, 'temperature', 'DONE', '2026-03-25 01:42:40', NULL),
('54:74', 54, 'sound', 'DONE', '2026-03-25 01:42:41', NULL),
('54:75', 54, 'temperature', 'DONE', '2026-03-25 01:42:41', NULL),
('54:76', 54, 'sound', 'DONE', '2026-03-25 01:42:42', NULL),
('54:77', 54, 'sound', 'DONE', '2026-03-25 01:42:43', NULL),
('54:78', 54, 'temperature', 'DONE', '2026-03-25 01:42:43', NULL),
('54:79', 54, 'sound', 'DONE', '2026-03-25 01:42:44', NULL),
('54:8', 54, 'movement', 'DONE', '2026-03-25 01:41:53', NULL),
('54:80', 54, 'temperature', 'DONE', '2026-03-25 01:42:44', NULL),
('54:81', 54, 'movement', 'DONE', '2026-03-25 01:42:44', NULL),
('54:82', 54, 'sound', 'DONE', '2026-03-25 01:42:45', NULL),
('54:83', 54, 'temperature', 'DONE', '2026-03-25 01:42:45', NULL),
('54:84', 54, 'sound', 'DONE', '2026-03-25 01:42:46', NULL),
('54:85', 54, 'temperature', 'DONE', '2026-03-25 01:42:46', NULL),
('54:86', 54, 'sound', 'DONE', '2026-03-25 01:42:47', NULL),
('54:87', 54, 'temperature', 'DONE', '2026-03-25 01:42:47', NULL),
('54:88', 54, 'sound', 'DONE', '2026-03-25 01:42:48', NULL),
('54:89', 54, 'temperature', 'DONE', '2026-03-25 01:42:48', NULL),
('54:9', 54, 'movement', 'DONE', '2026-03-25 01:41:54', NULL),
('54:90', 54, 'movement', 'DONE', '2026-03-25 01:42:48', NULL),
('54:91', 54, 'sound', 'DONE', '2026-03-25 01:42:49', NULL),
('54:92', 54, 'temperature', 'DONE', '2026-03-25 01:42:49', NULL),
('54:93', 54, 'sound', 'DONE', '2026-03-25 01:42:50', NULL),
('54:94', 54, 'temperature', 'DONE', '2026-03-25 01:42:50', NULL),
('54:95', 54, 'sound', 'DONE', '2026-03-25 01:42:51', NULL),
('54:96', 54, 'temperature', 'DONE', '2026-03-25 01:42:51', NULL),
('54:97', 54, 'sound', 'DONE', '2026-03-25 01:42:52', NULL),
('54:98', 54, 'temperature', 'DONE', '2026-03-25 01:42:53', NULL),
('54:99', 54, 'movement', 'DONE', '2026-03-25 01:42:53', NULL),
('55:1', 55, 'movement', 'DONE', '2026-03-25 16:29:59', NULL),
('55:10', 55, 'movement', 'DONE', '2026-03-25 16:30:08', NULL),
('55:100', 55, 'temperature', 'DONE', '2026-03-25 16:31:05', NULL),
('55:101', 55, 'sound', 'DONE', '2026-03-25 16:31:05', NULL),
('55:102', 55, 'temperature', 'INVALID', '2026-03-25 16:31:06', 'Hour invalid'),
('55:103', 55, 'sound', 'INVALID', '2026-03-25 16:31:07', 'Sound event invalid: value >= 60'),
('55:104', 55, 'movement', 'DONE', '2026-03-25 16:31:07', NULL),
('55:105', 55, 'temperature', 'DONE', '2026-03-25 16:31:08', NULL),
('55:106', 55, 'sound', 'INVALID', '2026-03-25 16:31:08', 'Sound event invalid: value >= 60'),
('55:107', 55, 'temperature', 'DONE', '2026-03-25 16:31:09', NULL),
('55:108', 55, 'sound', 'INVALID', '2026-03-25 16:31:09', 'Sound event invalid: value >= 60'),
('55:109', 55, 'temperature', 'DONE', '2026-03-25 16:31:10', NULL),
('55:11', 55, 'movement', 'DONE', '2026-03-25 16:30:09', NULL),
('55:110', 55, 'sound', 'DONE', '2026-03-25 16:31:10', NULL),
('55:111', 55, 'temperature', 'DONE', '2026-03-25 16:31:11', NULL),
('55:112', 55, 'sound', 'DONE', '2026-03-25 16:31:11', NULL),
('55:113', 55, 'temperature', 'DONE', '2026-03-25 16:31:12', NULL),
('55:114', 55, 'sound', 'DONE', '2026-03-25 16:31:12', NULL),
('55:115', 55, 'movement', 'DONE', '2026-03-25 16:31:12', NULL),
('55:116', 55, 'temperature', 'DONE', '2026-03-25 16:31:13', NULL),
('55:117', 55, 'sound', 'DONE', '2026-03-25 16:31:13', NULL),
('55:118', 55, 'temperature', 'DONE', '2026-03-25 16:31:14', NULL),
('55:119', 55, 'sound', 'DONE', '2026-03-25 16:31:14', NULL),
('55:12', 55, 'movement', 'DONE', '2026-03-25 16:30:10', NULL),
('55:120', 55, 'temperature', 'DONE', '2026-03-25 16:31:15', NULL),
('55:121', 55, 'sound', 'DONE', '2026-03-25 16:31:15', NULL),
('55:122', 55, 'temperature', 'DONE', '2026-03-25 16:31:16', NULL),
('55:123', 55, 'sound', 'DONE', '2026-03-25 16:31:16', NULL),
('55:124', 55, 'movement', 'DONE', '2026-03-25 16:31:17', NULL),
('55:125', 55, 'temperature', 'DONE', '2026-03-25 16:31:17', NULL),
('55:126', 55, 'sound', 'DONE', '2026-03-25 16:31:17', NULL),
('55:127', 55, 'temperature', 'DONE', '2026-03-25 16:31:18', NULL),
('55:128', 55, 'sound', 'DONE', '2026-03-25 16:31:18', NULL),
('55:129', 55, 'temperature', 'DONE', '2026-03-25 16:31:19', NULL),
('55:13', 55, 'movement', 'DONE', '2026-03-25 16:30:12', NULL),
('55:130', 55, 'sound', 'DONE', '2026-03-25 16:31:19', NULL),
('55:131', 55, 'temperature', 'DONE', '2026-03-25 16:31:20', NULL),
('55:132', 55, 'sound', 'DONE', '2026-03-25 16:31:20', NULL),
('55:133', 55, 'temperature', 'DONE', '2026-03-25 16:31:21', NULL),
('55:134', 55, 'sound', 'DONE', '2026-03-25 16:31:21', NULL),
('55:135', 55, 'movement', 'DONE', '2026-03-25 16:31:22', NULL),
('55:136', 55, 'temperature', 'DONE', '2026-03-25 16:31:22', NULL),
('55:137', 55, 'sound', 'DONE', '2026-03-25 16:31:22', NULL),
('55:138', 55, 'temperature', 'DONE', '2026-03-25 16:31:23', NULL),
('55:139', 55, 'sound', 'DONE', '2026-03-25 16:31:23', NULL),
('55:14', 55, 'movement', 'DONE', '2026-03-25 16:30:13', NULL),
('55:140', 55, 'temperature', 'DONE', '2026-03-25 16:31:24', NULL),
('55:141', 55, 'sound', 'DONE', '2026-03-25 16:31:24', NULL),
('55:142', 55, 'temperature', 'DONE', '2026-03-25 16:31:25', NULL),
('55:143', 55, 'sound', 'DONE', '2026-03-25 16:31:26', NULL),
('55:144', 55, 'temperature', 'DONE', '2026-03-25 16:31:27', NULL),
('55:145', 55, 'movement', 'INVALID', '2026-03-25 16:31:27', 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)'),
('55:146', 55, 'temperature', 'DONE', '2026-03-25 16:31:28', NULL),
('55:147', 55, 'temperature', 'DONE', '2026-03-25 16:31:29', NULL),
('55:148', 55, 'temperature', 'DONE', '2026-03-25 16:31:30', NULL),
('55:149', 55, 'temperature', 'DONE', '2026-03-25 16:31:31', NULL),
('55:15', 55, 'movement', 'DONE', '2026-03-25 16:30:14', NULL),
('55:150', 55, 'temperature', 'DONE', '2026-03-25 16:31:32', NULL),
('55:151', 55, 'temperature', 'DONE', '2026-03-25 16:31:33', NULL),
('55:152', 55, 'temperature', 'DONE', '2026-03-25 16:31:34', NULL),
('55:153', 55, 'temperature', 'DONE', '2026-03-25 16:31:35', NULL),
('55:154', 55, 'temperature', 'DONE', '2026-03-25 16:31:36', NULL),
('55:155', 55, 'temperature', 'DONE', '2026-03-25 16:31:37', NULL),
('55:156', 55, 'temperature', 'DONE', '2026-03-25 16:31:38', NULL),
('55:157', 55, 'temperature', 'DONE', '2026-03-25 16:31:40', NULL),
('55:158', 55, 'temperature', 'DONE', '2026-03-25 16:31:41', NULL),
('55:159', 55, 'movement', 'DONE', '2026-03-25 16:31:41', NULL),
('55:16', 55, 'movement', 'DONE', '2026-03-25 16:30:15', NULL),
('55:160', 55, 'movement', 'DONE', '2026-03-25 16:31:42', NULL),
('55:161', 55, 'temperature', 'DONE', '2026-03-25 16:31:42', NULL),
('55:162', 55, 'temperature', 'DONE', '2026-03-25 16:31:43', NULL),
('55:163', 55, 'movement', 'DONE', '2026-03-25 16:31:43', NULL),
('55:164', 55, 'movement', 'DONE', '2026-03-25 16:31:43', NULL),
('55:165', 55, 'temperature', 'DONE', '2026-03-25 16:31:44', NULL),
('55:166', 55, 'movement', 'DONE', '2026-03-25 16:31:44', NULL),
('55:167', 55, 'temperature', 'DONE', '2026-03-25 16:31:45', NULL),
('55:168', 55, 'movement', 'DONE', '2026-03-25 16:31:45', NULL),
('55:169', 55, 'temperature', 'DONE', '2026-03-25 16:31:46', NULL),
('55:17', 55, 'movement', 'DONE', '2026-03-25 16:30:16', NULL),
('55:170', 55, 'movement', 'DONE', '2026-03-25 16:31:46', NULL),
('55:171', 55, 'temperature', 'DONE', '2026-03-25 16:31:47', NULL),
('55:172', 55, 'movement', 'DONE', '2026-03-25 16:31:47', NULL),
('55:173', 55, 'temperature', 'DONE', '2026-03-25 16:31:48', NULL),
('55:174', 55, 'movement', 'DONE', '2026-03-25 16:31:49', NULL),
('55:175', 55, 'temperature', 'DONE', '2026-03-25 16:31:49', NULL),
('55:176', 55, 'movement', 'DONE', '2026-03-25 16:31:49', NULL),
('55:177', 55, 'movement', 'DONE', '2026-03-25 16:31:50', NULL),
('55:178', 55, 'temperature', 'DONE', '2026-03-25 16:31:50', NULL),
('55:179', 55, 'temperature', 'DONE', '2026-03-25 16:31:51', NULL),
('55:18', 55, 'movement', 'DONE', '2026-03-25 16:30:17', NULL),
('55:180', 55, 'movement', 'DONE', '2026-03-25 16:31:52', NULL),
('55:181', 55, 'temperature', 'DONE', '2026-03-25 16:31:52', NULL),
('55:182', 55, 'movement', 'DONE', '2026-03-25 16:31:53', NULL),
('55:183', 55, 'movement', 'DONE', '2026-03-25 16:31:53', NULL),
('55:184', 55, 'temperature', 'DONE', '2026-03-25 16:31:53', NULL),
('55:185', 55, 'temperature', 'DONE', '2026-03-25 16:31:54', NULL),
('55:186', 55, 'movement', 'DONE', '2026-03-25 16:31:54', NULL),
('55:187', 55, 'temperature', 'DONE', '2026-03-25 16:31:55', NULL),
('55:188', 55, 'movement', 'DONE', '2026-03-25 16:31:56', NULL),
('55:189', 55, 'temperature', 'DONE', '2026-03-25 16:31:56', NULL),
('55:19', 55, 'movement', 'DONE', '2026-03-25 16:30:18', NULL),
('55:190', 55, 'temperature', 'DONE', '2026-03-25 16:31:57', NULL),
('55:191', 55, 'movement', 'DONE', '2026-03-25 16:31:57', NULL),
('55:192', 55, 'movement', 'DONE', '2026-03-25 16:31:58', NULL),
('55:193', 55, 'temperature', 'DONE', '2026-03-25 16:31:58', NULL),
('55:194', 55, 'movement', 'DONE', '2026-03-25 16:31:58', NULL),
('55:195', 55, 'temperature', 'DONE', '2026-03-25 16:31:59', NULL),
('55:196', 55, 'movement', 'DONE', '2026-03-25 16:32:00', NULL),
('55:197', 55, 'temperature', 'DONE', '2026-03-25 16:32:01', NULL),
('55:198', 55, 'movement', 'DONE', '2026-03-25 16:32:01', NULL),
('55:199', 55, 'temperature', 'DONE', '2026-03-25 16:32:02', NULL),
('55:2', 55, 'movement', 'DONE', '2026-03-25 16:30:00', NULL),
('55:20', 55, 'movement', 'DONE', '2026-03-25 16:30:19', NULL),
('55:200', 55, 'movement', 'DONE', '2026-03-25 16:32:03', NULL),
('55:201', 55, 'temperature', 'DONE', '2026-03-25 16:32:03', NULL),
('55:202', 55, 'movement', 'DONE', '2026-03-25 16:32:03', NULL),
('55:203', 55, 'temperature', 'DONE', '2026-03-25 16:32:04', NULL),
('55:204', 55, 'movement', 'DONE', '2026-03-25 16:32:04', NULL),
('55:205', 55, 'temperature', 'DONE', '2026-03-25 16:32:05', NULL),
('55:206', 55, 'movement', 'DONE', '2026-03-25 16:32:05', NULL),
('55:207', 55, 'temperature', 'DONE', '2026-03-25 16:32:06', NULL),
('55:208', 55, 'movement', 'DONE', '2026-03-25 16:32:06', NULL),
('55:209', 55, 'temperature', 'DONE', '2026-03-25 16:32:07', NULL),
('55:21', 55, 'movement', 'DONE', '2026-03-25 16:30:21', NULL),
('55:210', 55, 'movement', 'DONE', '2026-03-25 16:32:07', NULL),
('55:211', 55, 'movement', 'DONE', '2026-03-25 16:32:08', NULL),
('55:212', 55, 'temperature', 'DONE', '2026-03-25 16:32:08', NULL),
('55:213', 55, 'movement', 'DONE', '2026-03-25 16:32:09', NULL),
('55:214', 55, 'temperature', 'DONE', '2026-03-25 16:32:09', NULL),
('55:215', 55, 'movement', 'DONE', '2026-03-25 16:32:10', NULL),
('55:216', 55, 'temperature', 'INVALID', '2026-03-25 16:32:10', 'A simulacao 55 ja foi terminada'),
('55:22', 55, 'movement', 'DONE', '2026-03-25 16:30:22', NULL),
('55:23', 55, 'movement', 'DONE', '2026-03-25 16:30:23', NULL),
('55:24', 55, 'movement', 'DONE', '2026-03-25 16:30:23', NULL),
('55:25', 55, 'movement', 'DONE', '2026-03-25 16:30:24', NULL),
('55:26', 55, 'movement', 'DONE', '2026-03-25 16:30:25', NULL),
('55:27', 55, 'movement', 'DONE', '2026-03-25 16:30:26', NULL),
('55:28', 55, 'movement', 'DONE', '2026-03-25 16:30:27', NULL),
('55:29', 55, 'movement', 'DONE', '2026-03-25 16:30:29', NULL),
('55:3', 55, 'movement', 'DONE', '2026-03-25 16:30:01', NULL),
('55:30', 55, 'movement', 'DONE', '2026-03-25 16:30:30', NULL),
('55:31', 55, 'movement', 'DONE', '2026-03-25 16:30:32', NULL),
('55:32', 55, 'temperature', 'DONE', '2026-03-25 16:30:32', NULL),
('55:33', 55, 'sound', 'DONE', '2026-03-25 16:30:33', NULL),
('55:34', 55, 'temperature', 'DONE', '2026-03-25 16:30:33', NULL),
('55:35', 55, 'sound', 'DONE', '2026-03-25 16:30:34', NULL),
('55:36', 55, 'temperature', 'DONE', '2026-03-25 16:30:34', NULL),
('55:37', 55, 'sound', 'DONE', '2026-03-25 16:30:35', NULL),
('55:38', 55, 'temperature', 'DONE', '2026-03-25 16:30:35', NULL),
('55:39', 55, 'sound', 'DONE', '2026-03-25 16:30:36', NULL),
('55:4', 55, 'movement', 'DONE', '2026-03-25 16:30:02', NULL),
('55:40', 55, 'movement', 'DONE', '2026-03-25 16:30:36', NULL),
('55:41', 55, 'temperature', 'DONE', '2026-03-25 16:30:37', NULL),
('55:42', 55, 'sound', 'DONE', '2026-03-25 16:30:37', NULL),
('55:43', 55, 'temperature', 'DONE', '2026-03-25 16:30:37', NULL),
('55:44', 55, 'sound', 'DONE', '2026-03-25 16:30:38', NULL),
('55:45', 55, 'temperature', 'DONE', '2026-03-25 16:30:39', NULL),
('55:46', 55, 'sound', 'DONE', '2026-03-25 16:30:39', NULL),
('55:47', 55, 'temperature', 'DONE', '2026-03-25 16:30:40', NULL),
('55:48', 55, 'sound', 'DONE', '2026-03-25 16:30:40', NULL),
('55:49', 55, 'temperature', 'DONE', '2026-03-25 16:30:41', NULL),
('55:5', 55, 'movement', 'DONE', '2026-03-25 16:30:03', NULL),
('55:50', 55, 'sound', 'DONE', '2026-03-25 16:30:41', NULL),
('55:51', 55, 'movement', 'DONE', '2026-03-25 16:30:42', NULL),
('55:52', 55, 'temperature', 'DONE', '2026-03-25 16:30:42', NULL),
('55:53', 55, 'sound', 'DONE', '2026-03-25 16:30:42', NULL),
('55:54', 55, 'temperature', 'DONE', '2026-03-25 16:30:43', NULL),
('55:55', 55, 'sound', 'INVALID', '2026-03-25 16:30:43', 'Hour invalid'),
('55:56', 55, 'temperature', 'DONE', '2026-03-25 16:30:44', NULL),
('55:57', 55, 'sound', 'DONE', '2026-03-25 16:30:44', NULL),
('55:58', 55, 'temperature', 'DONE', '2026-03-25 16:30:45', NULL),
('55:59', 55, 'sound', 'DONE', '2026-03-25 16:30:45', NULL),
('55:6', 55, 'movement', 'DONE', '2026-03-25 16:30:04', NULL),
('55:60', 55, 'temperature', 'INVALID', '2026-03-25 16:30:46', 'Temperature event invalid: value >= 60'),
('55:61', 55, 'sound', 'DONE', '2026-03-25 16:30:46', NULL),
('55:62', 55, 'movement', 'DONE', '2026-03-25 16:30:47', NULL),
('55:63', 55, 'temperature', 'INVALID', '2026-03-25 16:30:47', 'Temperature event invalid: value >= 60'),
('55:64', 55, 'sound', 'DONE', '2026-03-25 16:30:47', NULL),
('55:65', 55, 'temperature', 'INVALID', '2026-03-25 16:30:48', 'Temperature event invalid: value >= 60'),
('55:66', 55, 'sound', 'DONE', '2026-03-25 16:30:49', NULL),
('55:67', 55, 'temperature', 'INVALID', '2026-03-25 16:30:50', 'Temperature event invalid: value >= 60'),
('55:68', 55, 'sound', 'DONE', '2026-03-25 16:30:50', NULL),
('55:69', 55, 'temperature', 'INVALID', '2026-03-25 16:30:51', 'Temperature event invalid: value >= 60'),
('55:7', 55, 'movement', 'DONE', '2026-03-25 16:30:05', NULL),
('55:70', 55, 'sound', 'DONE', '2026-03-25 16:30:51', NULL),
('55:71', 55, 'movement', 'DONE', '2026-03-25 16:30:51', NULL),
('55:72', 55, 'temperature', 'INVALID', '2026-03-25 16:30:52', 'Temperature event invalid: value >= 60'),
('55:73', 55, 'sound', 'DONE', '2026-03-25 16:30:52', NULL),
('55:74', 55, 'temperature', 'INVALID', '2026-03-25 16:30:52', 'Temperature event invalid: value >= 60'),
('55:75', 55, 'sound', 'DONE', '2026-03-25 16:30:53', NULL),
('55:76', 55, 'temperature', 'INVALID', '2026-03-25 16:30:53', 'Temperature event invalid: value >= 60'),
('55:77', 55, 'sound', 'DONE', '2026-03-25 16:30:54', NULL),
('55:78', 55, 'temperature', 'INVALID', '2026-03-25 16:30:55', 'Temperature event invalid: value >= 60'),
('55:79', 55, 'sound', 'DONE', '2026-03-25 16:30:55', NULL),
('55:8', 55, 'movement', 'DONE', '2026-03-25 16:30:06', NULL),
('55:80', 55, 'temperature', 'INVALID', '2026-03-25 16:30:55', 'Temperature event invalid: value >= 60'),
('55:81', 55, 'sound', 'DONE', '2026-03-25 16:30:56', NULL),
('55:82', 55, 'movement', 'DONE', '2026-03-25 16:30:57', NULL),
('55:83', 55, 'temperature', 'INVALID', '2026-03-25 16:30:57', 'Temperature event invalid: value >= 60'),
('55:84', 55, 'sound', 'DONE', '2026-03-25 16:30:57', NULL),
('55:85', 55, 'temperature', 'DONE', '2026-03-25 16:30:58', NULL),
('55:86', 55, 'sound', 'DONE', '2026-03-25 16:30:58', NULL),
('55:87', 55, 'temperature', 'DONE', '2026-03-25 16:30:59', NULL),
('55:88', 55, 'sound', 'DONE', '2026-03-25 16:30:59', NULL),
('55:89', 55, 'temperature', 'DONE', '2026-03-25 16:31:00', NULL),
('55:9', 55, 'movement', 'DONE', '2026-03-25 16:30:07', NULL),
('55:90', 55, 'sound', 'DONE', '2026-03-25 16:31:00', NULL),
('55:91', 55, 'temperature', 'DONE', '2026-03-25 16:31:01', NULL),
('55:92', 55, 'sound', 'DONE', '2026-03-25 16:31:01', NULL),
('55:93', 55, 'movement', 'DONE', '2026-03-25 16:31:02', NULL),
('55:94', 55, 'temperature', 'DONE', '2026-03-25 16:31:02', NULL),
('55:95', 55, 'sound', 'DONE', '2026-03-25 16:31:02', NULL),
('55:96', 55, 'temperature', 'DONE', '2026-03-25 16:31:03', NULL),
('55:97', 55, 'sound', 'DONE', '2026-03-25 16:31:03', NULL),
('55:98', 55, 'temperature', 'DONE', '2026-03-25 16:31:04', NULL),
('55:99', 55, 'sound', 'DONE', '2026-03-25 16:31:04', NULL),
('56:1', 56, 'movement', 'DONE', '2026-03-26 14:49:53', NULL),
('56:10', 56, 'movement', 'DONE', '2026-03-26 14:50:02', NULL),
('56:100', 56, 'temperature', 'DONE', '2026-03-26 14:50:58', NULL),
('56:101', 56, 'sound', 'DONE', '2026-03-26 14:50:59', NULL),
('56:102', 56, 'temperature', 'INVALID', '2026-03-26 14:50:59', 'Hour invalid'),
('56:103', 56, 'sound', 'INVALID', '2026-03-26 14:50:59', 'Sound event invalid: value >= 60'),
('56:104', 56, 'movement', 'INVALID', '2026-03-26 14:51:00', 'Movement invalid: RoomOrigin does not match Marsami current room'),
('56:105', 56, 'temperature', 'DONE', '2026-03-26 14:51:01', NULL),
('56:106', 56, 'sound', 'INVALID', '2026-03-26 14:51:01', 'Sound event invalid: value >= 60'),
('56:107', 56, 'temperature', 'DONE', '2026-03-26 14:51:01', NULL),
('56:108', 56, 'sound', 'INVALID', '2026-03-26 14:51:01', 'Sound event invalid: value >= 60'),
('56:109', 56, 'temperature', 'DONE', '2026-03-26 14:51:02', NULL),
('56:11', 56, 'movement', 'DONE', '2026-03-26 14:50:03', NULL),
('56:110', 56, 'sound', 'DONE', '2026-03-26 14:51:02', NULL),
('56:111', 56, 'temperature', 'DONE', '2026-03-26 14:51:03', NULL),
('56:112', 56, 'sound', 'DONE', '2026-03-26 14:51:03', NULL),
('56:113', 56, 'temperature', 'DONE', '2026-03-26 14:51:04', NULL),
('56:114', 56, 'sound', 'DONE', '2026-03-26 14:51:04', NULL),
('56:115', 56, 'movement', 'INVALID', '2026-03-26 14:51:05', 'Movement invalid: corridor is not active'),
('56:116', 56, 'temperature', 'DONE', '2026-03-26 14:51:05', NULL),
('56:117', 56, 'sound', 'DONE', '2026-03-26 14:51:05', NULL),
('56:118', 56, 'sound', 'DONE', '2026-03-26 14:51:07', NULL),
('56:119', 56, 'temperature', 'DONE', '2026-03-26 14:51:07', NULL),
('56:12', 56, 'movement', 'DONE', '2026-03-26 14:50:04', NULL),
('56:120', 56, 'sound', 'DONE', '2026-03-26 14:51:08', NULL),
('56:121', 56, 'temperature', 'DONE', '2026-03-26 14:51:08', NULL),
('56:122', 56, 'sound', 'DONE', '2026-03-26 14:51:09', NULL),
('56:123', 56, 'temperature', 'DONE', '2026-03-26 14:51:09', NULL),
('56:124', 56, 'sound', 'DONE', '2026-03-26 14:52:35', NULL),
('56:125', 56, 'temperature', 'DONE', '2026-03-26 14:52:35', NULL),
('56:126', 56, 'movement', 'INVALID', '2026-03-26 14:52:35', 'Movement invalid: corridor is not active'),
('56:127', 56, 'sound', 'DONE', '2026-03-26 14:52:35', NULL),
('56:128', 56, 'temperature', 'DONE', '2026-03-26 14:52:35', NULL),
('56:129', 56, 'sound', 'DONE', '2026-03-26 14:52:35', NULL),
('56:13', 56, 'movement', 'DONE', '2026-03-26 14:50:05', NULL),
('56:130', 56, 'temperature', 'DONE', '2026-03-26 14:52:35', NULL),
('56:131', 56, 'sound', 'DONE', '2026-03-26 14:52:35', NULL),
('56:132', 56, 'temperature', 'DONE', '2026-03-26 14:52:35', NULL),
('56:133', 56, 'sound', 'DONE', '2026-03-26 14:52:35', NULL),
('56:134', 56, 'temperature', 'DONE', '2026-03-26 14:52:35', NULL),
('56:135', 56, 'movement', 'INVALID', '2026-03-26 14:52:35', 'Movement invalid: corridor is not active'),
('56:136', 56, 'sound', 'DONE', '2026-03-26 14:52:35', NULL),
('56:137', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:138', 56, 'sound', 'DONE', '2026-03-26 14:52:36', NULL),
('56:139', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:14', 56, 'movement', 'DONE', '2026-03-26 14:50:06', NULL),
('56:140', 56, 'sound', 'DONE', '2026-03-26 14:52:36', NULL),
('56:141', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:142', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:143', 56, 'sound', 'DONE', '2026-03-26 14:52:36', NULL),
('56:144', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:145', 56, 'movement', 'INVALID', '2026-03-26 14:52:36', 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)'),
('56:146', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:147', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:148', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:149', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:15', 56, 'movement', 'DONE', '2026-03-26 14:50:07', NULL),
('56:150', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:151', 56, 'temperature', 'DONE', '2026-03-26 14:52:36', NULL),
('56:152', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:153', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:154', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:155', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:156', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:157', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:158', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:159', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:16', 56, 'movement', 'DONE', '2026-03-26 14:50:08', NULL),
('56:160', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:161', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:162', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:163', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:164', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:165', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:166', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:167', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:168', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:169', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:17', 56, 'movement', 'DONE', '2026-03-26 14:50:09', NULL),
('56:170', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:171', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:172', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:173', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:174', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:175', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:176', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:177', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:178', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:179', 56, 'movement', 'DONE', '2026-03-26 14:52:37', NULL),
('56:18', 56, 'movement', 'DONE', '2026-03-26 14:50:11', NULL),
('56:180', 56, 'temperature', 'DONE', '2026-03-26 14:52:37', NULL),
('56:181', 56, 'movement', 'DONE', '2026-03-26 14:52:38', NULL),
('56:182', 56, 'temperature', 'DONE', '2026-03-26 14:52:38', NULL),
('56:183', 56, 'temperature', 'DONE', '2026-03-26 14:52:38', NULL),
('56:184', 56, 'movement', 'DONE', '2026-03-26 14:52:38', NULL),
('56:185', 56, 'temperature', 'DONE', '2026-03-26 14:52:38', NULL),
('56:186', 56, 'movement', 'DONE', '2026-03-26 14:52:38', NULL),
('56:187', 56, 'temperature', 'DONE', '2026-03-26 14:52:38', NULL),
('56:188', 56, 'movement', 'DONE', '2026-03-26 14:52:38', NULL),
('56:189', 56, 'movement', 'DONE', '2026-03-26 14:52:38', NULL),
('56:19', 56, 'movement', 'DONE', '2026-03-26 14:50:12', NULL),
('56:190', 56, 'temperature', 'DONE', '2026-03-26 14:52:38', NULL),
('56:191', 56, 'movement', 'DONE', '2026-03-26 14:52:38', NULL),
('56:192', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:193', 56, 'temperature', 'DONE', '2026-03-26 14:52:41', NULL),
('56:194', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:195', 56, 'temperature', 'DONE', '2026-03-26 14:52:41', NULL),
('56:196', 56, 'temperature', 'DONE', '2026-03-26 14:52:41', NULL),
('56:197', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:198', 56, 'temperature', 'DONE', '2026-03-26 14:52:41', NULL),
('56:199', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:2', 56, 'movement', 'DONE', '2026-03-26 14:49:54', NULL),
('56:20', 56, 'movement', 'DONE', '2026-03-26 14:50:13', NULL),
('56:200', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:201', 56, 'temperature', 'DONE', '2026-03-26 14:52:41', NULL),
('56:202', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:203', 56, 'temperature', 'DONE', '2026-03-26 14:52:41', NULL),
('56:204', 56, 'movement', 'DONE', '2026-03-26 14:52:41', NULL),
('56:205', 56, 'temperature', 'DONE', '2026-03-26 14:52:51', NULL),
('56:206', 56, 'movement', 'DONE', '2026-03-26 14:52:51', NULL),
('56:207', 56, 'temperature', 'DONE', '2026-03-26 14:52:51', NULL),
('56:208', 56, 'movement', 'DONE', '2026-03-26 14:52:51', NULL),
('56:209', 56, 'temperature', 'DONE', '2026-03-26 14:52:51', NULL);
INSERT INTO `EventosProcessados` (`EventID`, `IDSimulacao`, `TipoEvento`, `EstadoProcessamento`, `ProcessedAt`, `ErrorMessage`) VALUES
('56:21', 56, 'movement', 'DONE', '2026-03-26 14:50:14', NULL),
('56:210', 56, 'movement', 'DONE', '2026-03-26 14:52:51', NULL),
('56:211', 56, 'temperature', 'DONE', '2026-03-26 14:52:51', NULL),
('56:212', 56, 'movement', 'DONE', '2026-03-26 14:52:51', NULL),
('56:213', 56, 'temperature', 'DONE', '2026-03-26 14:52:51', NULL),
('56:214', 56, 'movement', 'DONE', '2026-03-26 14:52:51', NULL),
('56:215', 56, 'temperature', 'DONE', '2026-03-26 14:52:51', NULL),
('56:216', 56, 'movement', 'DONE', '2026-03-26 14:52:51', NULL),
('56:217', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:218', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:219', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:22', 56, 'movement', 'DONE', '2026-03-26 14:50:15', NULL),
('56:220', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:221', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:222', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:223', 56, 'temperature', 'INVALID', '2026-03-26 14:52:53', 'A simulacao 56 ja foi terminada'),
('56:23', 56, 'movement', 'DONE', '2026-03-26 14:50:16', NULL),
('56:24', 56, 'movement', 'DONE', '2026-03-26 14:50:17', NULL),
('56:25', 56, 'movement', 'DONE', '2026-03-26 14:50:18', NULL),
('56:26', 56, 'movement', 'DONE', '2026-03-26 14:50:19', NULL),
('56:27', 56, 'movement', 'DONE', '2026-03-26 14:50:20', NULL),
('56:28', 56, 'movement', 'DONE', '2026-03-26 14:50:21', NULL),
('56:29', 56, 'movement', 'DONE', '2026-03-26 14:50:22', NULL),
('56:3', 56, 'movement', 'DONE', '2026-03-26 14:49:55', NULL),
('56:30', 56, 'movement', 'DONE', '2026-03-26 14:50:23', NULL),
('56:31', 56, 'movement', 'INVALID', '2026-03-26 14:50:24', 'Movement invalid: corridor is not active'),
('56:32', 56, 'temperature', 'DONE', '2026-03-26 14:50:26', NULL),
('56:33', 56, 'sound', 'DONE', '2026-03-26 14:50:26', NULL),
('56:34', 56, 'temperature', 'DONE', '2026-03-26 14:50:27', NULL),
('56:35', 56, 'sound', 'DONE', '2026-03-26 14:50:27', NULL),
('56:36', 56, 'temperature', 'DONE', '2026-03-26 14:50:28', NULL),
('56:37', 56, 'sound', 'DONE', '2026-03-26 14:50:28', NULL),
('56:38', 56, 'temperature', 'DONE', '2026-03-26 14:50:29', NULL),
('56:39', 56, 'sound', 'DONE', '2026-03-26 14:50:29', NULL),
('56:4', 56, 'movement', 'DONE', '2026-03-26 14:49:56', NULL),
('56:40', 56, 'movement', 'INVALID', '2026-03-26 14:50:30', 'Movement invalid: corridor is not active'),
('56:41', 56, 'temperature', 'DONE', '2026-03-26 14:50:30', NULL),
('56:42', 56, 'sound', 'DONE', '2026-03-26 14:50:30', NULL),
('56:43', 56, 'temperature', 'DONE', '2026-03-26 14:50:31', NULL),
('56:44', 56, 'sound', 'DONE', '2026-03-26 14:50:31', NULL),
('56:45', 56, 'temperature', 'DONE', '2026-03-26 14:50:32', NULL),
('56:46', 56, 'sound', 'DONE', '2026-03-26 14:50:32', NULL),
('56:47', 56, 'temperature', 'DONE', '2026-03-26 14:50:33', NULL),
('56:48', 56, 'sound', 'DONE', '2026-03-26 14:50:33', NULL),
('56:49', 56, 'temperature', 'DONE', '2026-03-26 14:50:34', NULL),
('56:5', 56, 'movement', 'DONE', '2026-03-26 14:49:57', NULL),
('56:50', 56, 'sound', 'DONE', '2026-03-26 14:50:34', NULL),
('56:51', 56, 'movement', 'INVALID', '2026-03-26 14:50:34', 'Movement invalid: corridor is not active'),
('56:52', 56, 'temperature', 'DONE', '2026-03-26 14:50:35', NULL),
('56:53', 56, 'sound', 'DONE', '2026-03-26 14:50:35', NULL),
('56:54', 56, 'temperature', 'DONE', '2026-03-26 14:50:36', NULL),
('56:55', 56, 'sound', 'INVALID', '2026-03-26 14:50:36', 'Hour invalid'),
('56:56', 56, 'temperature', 'DONE', '2026-03-26 14:50:37', NULL),
('56:57', 56, 'sound', 'DONE', '2026-03-26 14:50:37', NULL),
('56:58', 56, 'temperature', 'DONE', '2026-03-26 14:50:38', NULL),
('56:59', 56, 'sound', 'DONE', '2026-03-26 14:50:38', NULL),
('56:6', 56, 'movement', 'DONE', '2026-03-26 14:49:58', NULL),
('56:60', 56, 'temperature', 'INVALID', '2026-03-26 14:50:39', 'Temperature event invalid: value >= 60'),
('56:61', 56, 'sound', 'DONE', '2026-03-26 14:50:39', NULL),
('56:62', 56, 'movement', 'INVALID', '2026-03-26 14:50:40', 'Movement invalid: corridor is not active'),
('56:63', 56, 'temperature', 'INVALID', '2026-03-26 14:50:41', 'Temperature event invalid: value >= 60'),
('56:64', 56, 'sound', 'DONE', '2026-03-26 14:50:41', NULL),
('56:65', 56, 'temperature', 'INVALID', '2026-03-26 14:50:42', 'Temperature event invalid: value >= 60'),
('56:66', 56, 'sound', 'DONE', '2026-03-26 14:50:42', NULL),
('56:67', 56, 'temperature', 'INVALID', '2026-03-26 14:50:43', 'Temperature event invalid: value >= 60'),
('56:68', 56, 'sound', 'DONE', '2026-03-26 14:50:43', NULL),
('56:69', 56, 'temperature', 'INVALID', '2026-03-26 14:50:43', 'Temperature event invalid: value >= 60'),
('56:7', 56, 'movement', 'DONE', '2026-03-26 14:49:59', NULL),
('56:70', 56, 'sound', 'DONE', '2026-03-26 14:50:44', NULL),
('56:71', 56, 'temperature', 'INVALID', '2026-03-26 14:50:44', 'Temperature event invalid: value >= 60'),
('56:72', 56, 'sound', 'DONE', '2026-03-26 14:50:45', NULL),
('56:73', 56, 'movement', 'INVALID', '2026-03-26 14:50:45', 'Movement invalid: corridor is not active'),
('56:74', 56, 'temperature', 'INVALID', '2026-03-26 14:50:45', 'Temperature event invalid: value >= 60'),
('56:75', 56, 'sound', 'DONE', '2026-03-26 14:50:45', NULL),
('56:76', 56, 'temperature', 'INVALID', '2026-03-26 14:50:47', 'Temperature event invalid: value >= 60'),
('56:77', 56, 'sound', 'DONE', '2026-03-26 14:50:47', NULL),
('56:78', 56, 'temperature', 'INVALID', '2026-03-26 14:50:48', 'Temperature event invalid: value >= 60'),
('56:79', 56, 'sound', 'DONE', '2026-03-26 14:50:48', NULL),
('56:8', 56, 'movement', 'DONE', '2026-03-26 14:50:00', NULL),
('56:80', 56, 'temperature', 'INVALID', '2026-03-26 14:50:49', 'Temperature event invalid: value >= 60'),
('56:81', 56, 'sound', 'DONE', '2026-03-26 14:50:49', NULL),
('56:82', 56, 'temperature', 'INVALID', '2026-03-26 14:50:50', 'Temperature event invalid: value >= 60'),
('56:83', 56, 'movement', 'INVALID', '2026-03-26 14:50:50', 'Movement invalid: RoomOrigin does not match Marsami current room'),
('56:84', 56, 'sound', 'DONE', '2026-03-26 14:50:50', NULL),
('56:85', 56, 'temperature', 'DONE', '2026-03-26 14:50:51', NULL),
('56:86', 56, 'sound', 'DONE', '2026-03-26 14:50:51', NULL),
('56:87', 56, 'temperature', 'DONE', '2026-03-26 14:50:52', NULL),
('56:88', 56, 'sound', 'DONE', '2026-03-26 14:50:52', NULL),
('56:89', 56, 'temperature', 'DONE', '2026-03-26 14:50:53', NULL),
('56:9', 56, 'movement', 'DONE', '2026-03-26 14:50:01', NULL),
('56:90', 56, 'sound', 'DONE', '2026-03-26 14:50:53', NULL),
('56:91', 56, 'temperature', 'DONE', '2026-03-26 14:50:54', NULL),
('56:92', 56, 'sound', 'DONE', '2026-03-26 14:50:54', NULL),
('56:93', 56, 'movement', 'INVALID', '2026-03-26 14:50:55', 'Movement invalid: corridor is not active'),
('56:94', 56, 'temperature', 'DONE', '2026-03-26 14:50:55', NULL),
('56:95', 56, 'sound', 'DONE', '2026-03-26 14:50:55', NULL),
('56:96', 56, 'temperature', 'DONE', '2026-03-26 14:50:56', NULL),
('56:97', 56, 'sound', 'DONE', '2026-03-26 14:50:56', NULL),
('56:98', 56, 'temperature', 'DONE', '2026-03-26 14:50:57', NULL),
('56:99', 56, 'sound', 'DONE', '2026-03-26 14:50:57', NULL),
('57:1', 57, 'movement', 'DONE', '2026-03-26 15:00:39', NULL),
('57:10', 57, 'movement', 'DONE', '2026-03-26 15:00:49', NULL),
('57:100', 57, 'sound', 'DONE', '2026-03-26 15:01:45', NULL),
('57:101', 57, 'temperature', 'DONE', '2026-03-26 15:01:45', NULL),
('57:102', 57, 'temperature', 'INVALID', '2026-03-26 15:01:46', 'Hour invalid'),
('57:103', 57, 'sound', 'INVALID', '2026-03-26 15:01:46', 'Sound event invalid: value >= 60'),
('57:104', 57, 'movement', 'DONE', '2026-03-26 15:01:47', NULL),
('57:105', 57, 'sound', 'INVALID', '2026-03-26 15:01:47', 'Sound event invalid: value >= 60'),
('57:106', 57, 'temperature', 'DONE', '2026-03-26 15:01:47', NULL),
('57:107', 57, 'temperature', 'DONE', '2026-03-26 15:01:48', NULL),
('57:108', 57, 'sound', 'INVALID', '2026-03-26 15:01:48', 'Sound event invalid: value >= 60'),
('57:109', 57, 'temperature', 'DONE', '2026-03-26 15:01:49', NULL),
('57:11', 57, 'movement', 'DONE', '2026-03-26 15:00:50', NULL),
('57:110', 57, 'sound', 'DONE', '2026-03-26 15:01:49', NULL),
('57:111', 57, 'temperature', 'DONE', '2026-03-26 15:01:50', NULL),
('57:112', 57, 'sound', 'DONE', '2026-03-26 15:01:50', NULL),
('57:113', 57, 'temperature', 'DONE', '2026-03-26 15:01:51', NULL),
('57:114', 57, 'sound', 'DONE', '2026-03-26 15:01:51', NULL),
('57:115', 57, 'movement', 'DONE', '2026-03-26 15:01:52', NULL),
('57:116', 57, 'temperature', 'DONE', '2026-03-26 15:01:52', NULL),
('57:117', 57, 'sound', 'DONE', '2026-03-26 15:01:52', NULL),
('57:118', 57, 'temperature', 'DONE', '2026-03-26 15:01:53', NULL),
('57:119', 57, 'sound', 'DONE', '2026-03-26 15:01:53', NULL),
('57:12', 57, 'movement', 'DONE', '2026-03-26 15:00:51', NULL),
('57:120', 57, 'temperature', 'DONE', '2026-03-26 15:01:54', NULL),
('57:121', 57, 'sound', 'DONE', '2026-03-26 15:01:54', NULL),
('57:122', 57, 'temperature', 'DONE', '2026-03-26 15:01:56', NULL),
('57:123', 57, 'sound', 'DONE', '2026-03-26 15:01:56', NULL),
('57:124', 57, 'temperature', 'DONE', '2026-03-26 15:01:57', NULL),
('57:125', 57, 'sound', 'DONE', '2026-03-26 15:01:57', NULL),
('57:126', 57, 'movement', 'DONE', '2026-03-26 15:01:57', NULL),
('57:127', 57, 'temperature', 'DONE', '2026-03-26 15:01:58', NULL),
('57:128', 57, 'sound', 'DONE', '2026-03-26 15:01:58', NULL),
('57:129', 57, 'temperature', 'DONE', '2026-03-26 15:01:59', NULL),
('57:13', 57, 'movement', 'DONE', '2026-03-26 15:00:52', NULL),
('57:130', 57, 'sound', 'DONE', '2026-03-26 15:01:59', NULL),
('57:131', 57, 'sound', 'DONE', '2026-03-26 15:02:00', NULL),
('57:132', 57, 'temperature', 'DONE', '2026-03-26 15:02:00', NULL),
('57:133', 57, 'sound', 'DONE', '2026-03-26 15:02:01', NULL),
('57:134', 57, 'temperature', 'DONE', '2026-03-26 15:02:01', NULL),
('57:135', 57, 'sound', 'DONE', '2026-03-26 15:02:02', NULL),
('57:136', 57, 'temperature', 'DONE', '2026-03-26 15:02:02', NULL),
('57:137', 57, 'movement', 'DONE', '2026-03-26 15:02:02', NULL),
('57:138', 57, 'sound', 'DONE', '2026-03-26 15:02:03', NULL),
('57:139', 57, 'temperature', 'DONE', '2026-03-26 15:02:03', NULL),
('57:14', 57, 'movement', 'DONE', '2026-03-26 15:00:53', NULL),
('57:140', 57, 'temperature', 'DONE', '2026-03-26 15:02:04', NULL),
('57:141', 57, 'sound', 'DONE', '2026-03-26 15:02:04', NULL),
('57:142', 57, 'temperature', 'DONE', '2026-03-26 15:02:05', NULL),
('57:143', 57, 'sound', 'DONE', '2026-03-26 15:02:05', NULL),
('57:144', 57, 'temperature', 'DONE', '2026-03-26 15:02:06', NULL),
('57:145', 57, 'temperature', 'DONE', '2026-03-26 15:02:07', NULL),
('57:146', 57, 'movement', 'INVALID', '2026-03-26 15:02:07', 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)'),
('57:147', 57, 'temperature', 'DONE', '2026-03-26 15:02:08', NULL),
('57:148', 57, 'temperature', 'DONE', '2026-03-26 15:02:09', NULL),
('57:149', 57, 'temperature', 'DONE', '2026-03-26 15:02:10', NULL),
('57:15', 57, 'movement', 'DONE', '2026-03-26 15:00:54', NULL),
('57:150', 57, 'temperature', 'DONE', '2026-03-26 15:02:11', NULL),
('57:151', 57, 'temperature', 'DONE', '2026-03-26 15:02:12', NULL),
('57:152', 57, 'temperature', 'DONE', '2026-03-26 15:02:13', NULL),
('57:153', 57, 'temperature', 'DONE', '2026-03-26 15:02:15', NULL),
('57:154', 57, 'temperature', 'DONE', '2026-03-26 15:02:16', NULL),
('57:155', 57, 'temperature', 'DONE', '2026-03-26 15:02:17', NULL),
('57:156', 57, 'temperature', 'DONE', '2026-03-26 15:02:18', NULL),
('57:157', 57, 'temperature', 'DONE', '2026-03-26 15:02:18', NULL),
('57:158', 57, 'temperature', 'DONE', '2026-03-26 15:02:19', NULL),
('57:159', 57, 'movement', 'DONE', '2026-03-26 15:02:20', NULL),
('57:16', 57, 'movement', 'DONE', '2026-03-26 15:00:56', NULL),
('57:160', 57, 'temperature', 'DONE', '2026-03-26 15:02:20', NULL),
('57:161', 57, 'movement', 'DONE', '2026-03-26 15:02:22', NULL),
('57:162', 57, 'temperature', 'DONE', '2026-03-26 15:02:22', NULL),
('57:163', 57, 'temperature', 'DONE', '2026-03-26 15:02:23', NULL),
('57:164', 57, 'movement', 'DONE', '2026-03-26 15:02:23', NULL),
('57:165', 57, 'temperature', 'DONE', '2026-03-26 15:02:24', NULL),
('57:166', 57, 'movement', 'DONE', '2026-03-26 15:02:24', NULL),
('57:167', 57, 'temperature', 'DONE', '2026-03-26 15:02:25', NULL),
('57:168', 57, 'temperature', 'DONE', '2026-03-26 15:02:26', NULL),
('57:169', 57, 'movement', 'DONE', '2026-03-26 15:02:26', NULL),
('57:17', 57, 'movement', 'DONE', '2026-03-26 15:00:57', NULL),
('57:170', 57, 'movement', 'DONE', '2026-03-26 15:02:27', NULL),
('57:171', 57, 'temperature', 'DONE', '2026-03-26 15:02:27', NULL),
('57:172', 57, 'movement', 'DONE', '2026-03-26 15:02:27', NULL),
('57:173', 57, 'temperature', 'DONE', '2026-03-26 15:02:28', NULL),
('57:174', 57, 'movement', 'DONE', '2026-03-26 15:02:29', NULL),
('57:175', 57, 'movement', 'DONE', '2026-03-26 15:02:29', NULL),
('57:176', 57, 'temperature', 'DONE', '2026-03-26 15:02:29', NULL),
('57:177', 57, 'movement', 'DONE', '2026-03-26 15:02:30', NULL),
('57:178', 57, 'temperature', 'DONE', '2026-03-26 15:02:30', NULL),
('57:179', 57, 'temperature', 'DONE', '2026-03-26 15:02:31', NULL),
('57:18', 57, 'movement', 'DONE', '2026-03-26 15:00:58', NULL),
('57:180', 57, 'movement', 'DONE', '2026-03-26 15:02:32', NULL),
('57:181', 57, 'temperature', 'DONE', '2026-03-26 15:02:32', NULL),
('57:182', 57, 'movement', 'DONE', '2026-03-26 15:02:32', NULL),
('57:183', 57, 'movement', 'DONE', '2026-03-26 15:02:33', NULL),
('57:184', 57, 'temperature', 'DONE', '2026-03-26 15:02:33', NULL),
('57:185', 57, 'movement', 'DONE', '2026-03-26 15:02:33', NULL),
('57:186', 57, 'temperature', 'DONE', '2026-03-26 15:02:34', NULL),
('57:187', 57, 'movement', 'DONE', '2026-03-26 15:02:35', NULL),
('57:188', 57, 'temperature', 'DONE', '2026-03-26 15:02:35', NULL),
('57:189', 57, 'movement', 'DONE', '2026-03-26 15:02:36', NULL),
('57:19', 57, 'movement', 'DONE', '2026-03-26 15:00:59', NULL),
('57:190', 57, 'temperature', 'DONE', '2026-03-26 15:02:37', NULL),
('57:191', 57, 'temperature', 'DONE', '2026-03-26 15:02:38', NULL),
('57:192', 57, 'movement', 'DONE', '2026-03-26 15:02:38', NULL),
('57:193', 57, 'movement', 'DONE', '2026-03-26 15:02:38', NULL),
('57:194', 57, 'temperature', 'DONE', '2026-03-26 15:02:39', NULL),
('57:195', 57, 'movement', 'DONE', '2026-03-26 15:02:39', NULL),
('57:196', 57, 'temperature', 'DONE', '2026-03-26 15:02:40', NULL),
('57:197', 57, 'movement', 'DONE', '2026-03-26 15:02:40', NULL),
('57:198', 57, 'temperature', 'DONE', '2026-03-26 15:02:41', NULL),
('57:199', 57, 'movement', 'DONE', '2026-03-26 15:02:41', NULL),
('57:2', 57, 'movement', 'DONE', '2026-03-26 15:00:41', NULL),
('57:20', 57, 'movement', 'DONE', '2026-03-26 15:01:00', NULL),
('57:200', 57, 'temperature', 'DONE', '2026-03-26 15:02:42', NULL),
('57:201', 57, 'movement', 'DONE', '2026-03-26 15:02:42', NULL),
('57:202', 57, 'temperature', 'DONE', '2026-03-26 15:02:42', NULL),
('57:203', 57, 'movement', 'DONE', '2026-03-26 15:02:43', NULL),
('57:204', 57, 'temperature', 'DONE', '2026-03-26 15:02:44', NULL),
('57:205', 57, 'movement', 'DONE', '2026-03-26 15:02:44', NULL),
('57:206', 57, 'temperature', 'DONE', '2026-03-26 15:02:45', NULL),
('57:207', 57, 'movement', 'DONE', '2026-03-26 15:02:45', NULL),
('57:208', 57, 'temperature', 'DONE', '2026-03-26 15:02:46', NULL),
('57:209', 57, 'movement', 'DONE', '2026-03-26 15:02:46', NULL),
('57:21', 57, 'movement', 'DONE', '2026-03-26 15:01:01', NULL),
('57:210', 57, 'temperature', 'DONE', '2026-03-26 15:02:47', NULL),
('57:211', 57, 'movement', 'DONE', '2026-03-26 15:02:47', NULL),
('57:212', 57, 'temperature', 'DONE', '2026-03-26 15:02:48', NULL),
('57:213', 57, 'movement', 'DONE', '2026-03-26 15:02:48', NULL),
('57:214', 57, 'temperature', 'DONE', '2026-03-26 15:02:49', NULL),
('57:215', 57, 'movement', 'DONE', '2026-03-26 15:02:49', NULL),
('57:216', 57, 'temperature', 'DONE', '2026-03-26 15:02:50', NULL),
('57:217', 57, 'movement', 'DONE', '2026-03-26 15:02:51', NULL),
('57:22', 57, 'movement', 'DONE', '2026-03-26 15:01:02', NULL),
('57:23', 57, 'movement', 'DONE', '2026-03-26 15:01:03', NULL),
('57:24', 57, 'movement', 'DONE', '2026-03-26 15:01:04', NULL),
('57:25', 57, 'movement', 'DONE', '2026-03-26 15:01:05', NULL),
('57:26', 57, 'movement', 'DONE', '2026-03-26 15:01:06', NULL),
('57:27', 57, 'movement', 'DONE', '2026-03-26 15:01:07', NULL),
('57:28', 57, 'movement', 'DONE', '2026-03-26 15:01:08', NULL),
('57:29', 57, 'movement', 'DONE', '2026-03-26 15:01:09', NULL),
('57:3', 57, 'movement', 'DONE', '2026-03-26 15:00:42', NULL),
('57:30', 57, 'movement', 'DONE', '2026-03-26 15:01:10', NULL),
('57:31', 57, 'movement', 'DONE', '2026-03-26 15:01:11', NULL),
('57:32', 57, 'temperature', 'DONE', '2026-03-26 15:01:12', NULL),
('57:33', 57, 'sound', 'DONE', '2026-03-26 15:01:12', NULL),
('57:34', 57, 'temperature', 'DONE', '2026-03-26 15:01:13', NULL),
('57:35', 57, 'sound', 'DONE', '2026-03-26 15:01:13', NULL),
('57:36', 57, 'temperature', 'DONE', '2026-03-26 15:01:14', NULL),
('57:37', 57, 'sound', 'DONE', '2026-03-26 15:01:14', NULL),
('57:38', 57, 'temperature', 'DONE', '2026-03-26 15:01:15', NULL),
('57:39', 57, 'sound', 'DONE', '2026-03-26 15:01:16', NULL),
('57:4', 57, 'movement', 'DONE', '2026-03-26 15:00:43', NULL),
('57:40', 57, 'movement', 'DONE', '2026-03-26 15:01:17', NULL),
('57:41', 57, 'temperature', 'DONE', '2026-03-26 15:01:17', NULL),
('57:42', 57, 'sound', 'DONE', '2026-03-26 15:01:17', NULL),
('57:43', 57, 'temperature', 'DONE', '2026-03-26 15:01:18', NULL),
('57:44', 57, 'sound', 'DONE', '2026-03-26 15:01:18', NULL),
('57:45', 57, 'temperature', 'DONE', '2026-03-26 15:01:19', NULL),
('57:46', 57, 'sound', 'DONE', '2026-03-26 15:01:19', NULL),
('57:47', 57, 'temperature', 'DONE', '2026-03-26 15:01:20', NULL),
('57:48', 57, 'sound', 'DONE', '2026-03-26 15:01:20', NULL),
('57:49', 57, 'temperature', 'DONE', '2026-03-26 15:01:21', NULL),
('57:5', 57, 'movement', 'DONE', '2026-03-26 15:00:44', NULL),
('57:50', 57, 'sound', 'DONE', '2026-03-26 15:01:21', NULL),
('57:51', 57, 'movement', 'DONE', '2026-03-26 15:01:21', NULL),
('57:52', 57, 'temperature', 'DONE', '2026-03-26 15:01:22', NULL),
('57:53', 57, 'sound', 'DONE', '2026-03-26 15:01:22', NULL),
('57:54', 57, 'temperature', 'DONE', '2026-03-26 15:01:23', NULL),
('57:55', 57, 'sound', 'INVALID', '2026-03-26 15:01:23', 'Hour invalid'),
('57:56', 57, 'sound', 'DONE', '2026-03-26 15:01:24', NULL),
('57:57', 57, 'temperature', 'DONE', '2026-03-26 15:01:24', NULL),
('57:58', 57, 'temperature', 'DONE', '2026-03-26 15:01:25', NULL),
('57:59', 57, 'sound', 'DONE', '2026-03-26 15:01:25', NULL),
('57:6', 57, 'movement', 'DONE', '2026-03-26 15:00:45', NULL),
('57:60', 57, 'sound', 'DONE', '2026-03-26 15:01:26', NULL),
('57:61', 57, 'temperature', 'INVALID', '2026-03-26 15:01:26', 'Temperature event invalid: value >= 60'),
('57:62', 57, 'movement', 'DONE', '2026-03-26 15:01:27', NULL),
('57:63', 57, 'temperature', 'INVALID', '2026-03-26 15:01:27', 'Temperature event invalid: value >= 60'),
('57:64', 57, 'sound', 'DONE', '2026-03-26 15:01:27', NULL),
('57:65', 57, 'temperature', 'INVALID', '2026-03-26 15:01:28', 'Temperature event invalid: value >= 60'),
('57:66', 57, 'sound', 'DONE', '2026-03-26 15:01:28', NULL),
('57:67', 57, 'temperature', 'INVALID', '2026-03-26 15:01:30', 'Temperature event invalid: value >= 60'),
('57:68', 57, 'sound', 'DONE', '2026-03-26 15:01:30', NULL),
('57:69', 57, 'temperature', 'INVALID', '2026-03-26 15:01:31', 'Temperature event invalid: value >= 60'),
('57:7', 57, 'movement', 'DONE', '2026-03-26 15:00:46', NULL),
('57:70', 57, 'sound', 'DONE', '2026-03-26 15:01:31', NULL),
('57:71', 57, 'temperature', 'INVALID', '2026-03-26 15:01:32', 'Temperature event invalid: value >= 60'),
('57:72', 57, 'sound', 'DONE', '2026-03-26 15:01:32', NULL),
('57:73', 57, 'movement', 'DONE', '2026-03-26 15:01:32', NULL),
('57:74', 57, 'temperature', 'INVALID', '2026-03-26 15:01:33', 'Temperature event invalid: value >= 60'),
('57:75', 57, 'sound', 'DONE', '2026-03-26 15:01:33', NULL),
('57:76', 57, 'temperature', 'INVALID', '2026-03-26 15:01:33', 'Temperature event invalid: value >= 60'),
('57:77', 57, 'sound', 'DONE', '2026-03-26 15:01:34', NULL),
('57:78', 57, 'temperature', 'INVALID', '2026-03-26 15:01:34', 'Temperature event invalid: value >= 60'),
('57:79', 57, 'sound', 'DONE', '2026-03-26 15:01:34', NULL),
('57:8', 57, 'movement', 'DONE', '2026-03-26 15:00:47', NULL),
('57:80', 57, 'temperature', 'INVALID', '2026-03-26 15:01:35', 'Temperature event invalid: value >= 60'),
('57:81', 57, 'sound', 'DONE', '2026-03-26 15:01:36', NULL),
('57:82', 57, 'temperature', 'INVALID', '2026-03-26 15:01:37', 'Temperature event invalid: value >= 60'),
('57:83', 57, 'sound', 'DONE', '2026-03-26 15:01:37', NULL),
('57:84', 57, 'movement', 'DONE', '2026-03-26 15:01:37', NULL),
('57:85', 57, 'temperature', 'DONE', '2026-03-26 15:01:38', NULL),
('57:86', 57, 'sound', 'DONE', '2026-03-26 15:01:38', NULL),
('57:87', 57, 'temperature', 'DONE', '2026-03-26 15:01:39', NULL),
('57:88', 57, 'sound', 'DONE', '2026-03-26 15:01:39', NULL),
('57:89', 57, 'temperature', 'DONE', '2026-03-26 15:01:40', NULL),
('57:9', 57, 'movement', 'DONE', '2026-03-26 15:00:48', NULL),
('57:90', 57, 'sound', 'DONE', '2026-03-26 15:01:40', NULL),
('57:91', 57, 'temperature', 'DONE', '2026-03-26 15:01:41', NULL),
('57:92', 57, 'sound', 'DONE', '2026-03-26 15:01:41', NULL),
('57:93', 57, 'movement', 'DONE', '2026-03-26 15:01:42', NULL),
('57:94', 57, 'temperature', 'DONE', '2026-03-26 15:01:42', NULL),
('57:95', 57, 'sound', 'DONE', '2026-03-26 15:01:42', NULL),
('57:96', 57, 'temperature', 'DONE', '2026-03-26 15:01:43', NULL),
('57:97', 57, 'sound', 'DONE', '2026-03-26 15:01:43', NULL),
('57:98', 57, 'temperature', 'DONE', '2026-03-26 15:01:44', NULL),
('57:99', 57, 'sound', 'DONE', '2026-03-26 15:01:44', NULL),
('58:1', 58, 'movement', 'DONE', '2026-03-26 15:19:59', NULL),
('58:10', 58, 'movement', 'DONE', '2026-03-26 15:20:09', NULL),
('58:100', 58, 'movement', 'DONE', '2026-03-26 15:21:00', NULL),
('58:101', 58, 'sound', 'DONE', '2026-03-26 15:21:00', NULL),
('58:102', 58, 'temperature', 'DONE', '2026-03-26 15:21:00', NULL),
('58:103', 58, 'temperature', 'DONE', '2026-03-26 15:21:01', NULL),
('58:104', 58, 'sound', 'DONE', '2026-03-26 15:21:02', NULL),
('58:105', 58, 'movement', 'DONE', '2026-03-26 15:21:02', NULL),
('58:106', 58, 'temperature', 'DONE', '2026-03-26 15:21:03', NULL),
('58:107', 58, 'sound', 'DONE', '2026-03-26 15:21:03', NULL),
('58:108', 58, 'temperature', 'DONE', '2026-03-26 15:21:04', NULL),
('58:109', 58, 'sound', 'DONE', '2026-03-26 15:21:04', NULL),
('58:11', 58, 'movement', 'DONE', '2026-03-26 15:20:10', NULL),
('58:110', 58, 'movement', 'DONE', '2026-03-26 15:21:04', NULL),
('58:111', 58, 'temperature', 'DONE', '2026-03-26 15:21:05', NULL),
('58:112', 58, 'sound', 'DONE', '2026-03-26 15:21:05', NULL),
('58:113', 58, 'temperature', 'INVALID', '2026-03-26 15:21:06', 'Hour invalid'),
('58:114', 58, 'sound', 'INVALID', '2026-03-26 15:21:06', 'Sound event invalid: value >= 60'),
('58:115', 58, 'movement', 'DONE', '2026-03-26 15:21:06', NULL),
('58:116', 58, 'temperature', 'DONE', '2026-03-26 15:21:07', NULL),
('58:117', 58, 'sound', 'INVALID', '2026-03-26 15:21:07', 'Sound event invalid: value >= 60'),
('58:118', 58, 'temperature', 'DONE', '2026-03-26 15:21:08', NULL),
('58:119', 58, 'sound', 'INVALID', '2026-03-26 15:21:08', 'Sound event invalid: value >= 60'),
('58:12', 58, 'movement', 'DONE', '2026-03-26 15:20:11', NULL),
('58:120', 58, 'movement', 'DONE', '2026-03-26 15:21:09', NULL),
('58:121', 58, 'temperature', 'DONE', '2026-03-26 15:21:09', NULL),
('58:122', 58, 'sound', 'DONE', '2026-03-26 15:21:09', NULL),
('58:123', 58, 'temperature', 'DONE', '2026-03-26 15:21:10', NULL),
('58:124', 58, 'sound', 'DONE', '2026-03-26 15:21:10', NULL),
('58:125', 58, 'movement', 'DONE', '2026-03-26 15:21:10', NULL),
('58:126', 58, 'temperature', 'DONE', '2026-03-26 15:21:11', NULL),
('58:127', 58, 'sound', 'DONE', '2026-03-26 15:21:11', NULL),
('58:128', 58, 'temperature', 'DONE', '2026-03-26 15:21:12', NULL),
('58:129', 58, 'sound', 'DONE', '2026-03-26 15:21:12', NULL),
('58:13', 58, 'movement', 'DONE', '2026-03-26 15:20:12', NULL),
('58:130', 58, 'movement', 'DONE', '2026-03-26 15:21:12', NULL),
('58:131', 58, 'temperature', 'DONE', '2026-03-26 15:21:13', NULL),
('58:132', 58, 'sound', 'DONE', '2026-03-26 15:21:13', NULL),
('58:133', 58, 'temperature', 'DONE', '2026-03-26 15:21:14', NULL),
('58:134', 58, 'sound', 'DONE', '2026-03-26 15:21:14', NULL),
('58:135', 58, 'movement', 'INVALID', '2026-03-26 15:21:15', 'Movement invalid: RoomOrigin does not match Marsami current room'),
('58:136', 58, 'temperature', 'DONE', '2026-03-26 15:21:15', NULL),
('58:137', 58, 'sound', 'DONE', '2026-03-26 15:21:15', NULL),
('58:138', 58, 'temperature', 'DONE', '2026-03-26 15:21:16', NULL),
('58:139', 58, 'sound', 'DONE', '2026-03-26 15:21:16', NULL),
('58:14', 58, 'movement', 'DONE', '2026-03-26 15:20:13', NULL),
('58:140', 58, 'movement', 'DONE', '2026-03-26 15:21:17', NULL),
('58:141', 58, 'temperature', 'DONE', '2026-03-26 15:21:17', NULL),
('58:142', 58, 'sound', 'DONE', '2026-03-26 15:21:17', NULL),
('58:143', 58, 'temperature', 'DONE', '2026-03-26 15:21:18', NULL),
('58:144', 58, 'sound', 'DONE', '2026-03-26 15:21:18', NULL),
('58:145', 58, 'movement', 'DONE', '2026-03-26 15:21:19', NULL),
('58:146', 58, 'temperature', 'DONE', '2026-03-26 15:21:19', NULL),
('58:147', 58, 'sound', 'DONE', '2026-03-26 15:21:19', NULL),
('58:148', 58, 'temperature', 'DONE', '2026-03-26 15:21:21', NULL),
('58:149', 58, 'sound', 'DONE', '2026-03-26 15:21:21', NULL),
('58:15', 58, 'movement', 'DONE', '2026-03-26 15:20:14', NULL),
('58:150', 58, 'movement', 'DONE', '2026-03-26 15:21:21', NULL),
('58:151', 58, 'temperature', 'DONE', '2026-03-26 15:21:22', NULL),
('58:152', 58, 'sound', 'DONE', '2026-03-26 15:21:22', NULL),
('58:153', 58, 'temperature', 'DONE', '2026-03-26 15:21:23', NULL),
('58:154', 58, 'sound', 'DONE', '2026-03-26 15:21:23', NULL),
('58:155', 58, 'movement', 'DONE', '2026-03-26 15:21:23', NULL),
('58:156', 58, 'temperature', 'DONE', '2026-03-26 15:21:24', NULL),
('58:157', 58, 'sound', 'DONE', '2026-03-26 15:21:24', NULL),
('58:158', 58, 'temperature', 'DONE', '2026-03-26 15:21:25', NULL),
('58:159', 58, 'sound', 'DONE', '2026-03-26 15:21:25', NULL),
('58:16', 58, 'movement', 'DONE', '2026-03-26 15:20:15', NULL),
('58:160', 58, 'temperature', 'DONE', '2026-03-26 15:21:26', NULL),
('58:161', 58, 'temperature', 'DONE', '2026-03-26 15:21:27', NULL),
('58:162', 58, 'temperature', 'DONE', '2026-03-26 15:21:28', NULL),
('58:163', 58, 'temperature', 'DONE', '2026-03-26 15:21:29', NULL),
('58:164', 58, 'temperature', 'DONE', '2026-03-26 15:21:30', NULL),
('58:165', 58, 'temperature', 'DONE', '2026-03-26 15:21:31', NULL),
('58:166', 58, 'temperature', 'DONE', '2026-03-26 15:21:32', NULL),
('58:167', 58, 'temperature', 'DONE', '2026-03-26 15:21:33', NULL),
('58:168', 58, 'temperature', 'DONE', '2026-03-26 15:21:34', NULL),
('58:169', 58, 'temperature', 'DONE', '2026-03-26 15:21:35', NULL),
('58:17', 58, 'movement', 'DONE', '2026-03-26 15:20:16', NULL),
('58:170', 58, 'temperature', 'DONE', '2026-03-26 15:21:36', NULL),
('58:171', 58, 'temperature', 'DONE', '2026-03-26 15:21:37', NULL),
('58:172', 58, 'temperature', 'DONE', '2026-03-26 15:21:38', NULL),
('58:173', 58, 'temperature', 'DONE', '2026-03-26 15:21:39', NULL),
('58:174', 58, 'movement', 'DONE', '2026-03-26 15:21:40', NULL),
('58:175', 58, 'temperature', 'DONE', '2026-03-26 15:21:41', NULL),
('58:176', 58, 'temperature', 'DONE', '2026-03-26 15:21:42', NULL),
('58:177', 58, 'movement', 'DONE', '2026-03-26 15:21:42', NULL),
('58:178', 58, 'temperature', 'DONE', '2026-03-26 15:21:43', NULL),
('58:179', 58, 'movement', 'DONE', '2026-03-26 15:21:43', NULL),
('58:18', 58, 'movement', 'DONE', '2026-03-26 15:20:17', NULL),
('58:180', 58, 'movement', 'DONE', '2026-03-26 15:21:43', NULL),
('58:181', 58, 'temperature', 'DONE', '2026-03-26 15:21:44', NULL),
('58:182', 58, 'movement', 'DONE', '2026-03-26 15:21:44', NULL),
('58:183', 58, 'temperature', 'DONE', '2026-03-26 15:21:44', NULL),
('58:184', 58, 'movement', 'DONE', '2026-03-26 15:21:45', NULL),
('58:185', 58, 'temperature', 'DONE', '2026-03-26 15:21:45', NULL),
('58:186', 58, 'movement', 'DONE', '2026-03-26 15:21:46', NULL),
('58:187', 58, 'temperature', 'DONE', '2026-03-26 15:21:46', NULL),
('58:188', 58, 'movement', 'DONE', '2026-03-26 15:21:47', NULL),
('58:189', 58, 'temperature', 'DONE', '2026-03-26 15:21:48', NULL),
('58:19', 58, 'movement', 'DONE', '2026-03-26 15:20:18', NULL),
('58:190', 58, 'movement', 'DONE', '2026-03-26 15:21:48', NULL),
('58:191', 58, 'temperature', 'DONE', '2026-03-26 15:21:49', NULL),
('58:192', 58, 'movement', 'DONE', '2026-03-26 15:21:50', NULL),
('58:193', 58, 'temperature', 'DONE', '2026-03-26 15:21:50', NULL),
('58:194', 58, 'temperature', 'DONE', '2026-03-26 15:21:51', NULL),
('58:195', 58, 'movement', 'DONE', '2026-03-26 15:21:51', NULL),
('58:196', 58, 'movement', 'DONE', '2026-03-26 15:21:52', NULL),
('58:197', 58, 'temperature', 'DONE', '2026-03-26 15:21:52', NULL),
('58:198', 58, 'movement', 'DONE', '2026-03-26 15:21:52', NULL),
('58:199', 58, 'movement', 'DONE', '2026-03-26 15:21:53', NULL),
('58:2', 58, 'movement', 'DONE', '2026-03-26 15:20:00', NULL),
('58:20', 58, 'movement', 'DONE', '2026-03-26 15:20:20', NULL),
('58:200', 58, 'temperature', 'DONE', '2026-03-26 15:21:54', NULL),
('58:201', 58, 'temperature', 'DONE', '2026-03-26 15:21:55', NULL),
('58:202', 58, 'temperature', 'DONE', '2026-03-26 15:21:56', NULL),
('58:203', 58, 'movement', 'DONE', '2026-03-26 15:21:56', NULL),
('58:204', 58, 'movement', 'DONE', '2026-03-26 15:21:56', NULL),
('58:205', 58, 'temperature', 'DONE', '2026-03-26 15:21:57', NULL),
('58:206', 58, 'movement', 'DONE', '2026-03-26 15:21:57', NULL),
('58:207', 58, 'movement', 'DONE', '2026-03-26 15:21:57', NULL),
('58:208', 58, 'temperature', 'DONE', '2026-03-26 15:21:57', NULL),
('58:209', 58, 'movement', 'DONE', '2026-03-26 15:21:58', NULL),
('58:21', 58, 'movement', 'DONE', '2026-03-26 15:20:21', NULL),
('58:210', 58, 'temperature', 'DONE', '2026-03-26 15:21:58', NULL),
('58:211', 58, 'temperature', 'DONE', '2026-03-26 15:21:59', NULL),
('58:212', 58, 'movement', 'DONE', '2026-03-26 15:22:00', NULL),
('58:213', 58, 'movement', 'DONE', '2026-03-26 15:22:00', NULL),
('58:214', 58, 'temperature', 'DONE', '2026-03-26 15:22:01', NULL),
('58:215', 58, 'movement', 'DONE', '2026-03-26 15:22:02', NULL),
('58:216', 58, 'temperature', 'DONE', '2026-03-26 15:22:02', NULL),
('58:217', 58, 'temperature', 'DONE', '2026-03-26 15:22:03', NULL),
('58:218', 58, 'movement', 'DONE', '2026-03-26 15:22:03', NULL),
('58:219', 58, 'temperature', 'DONE', '2026-03-26 15:22:04', NULL),
('58:22', 58, 'movement', 'DONE', '2026-03-26 15:20:22', NULL),
('58:220', 58, 'movement', 'DONE', '2026-03-26 15:22:04', NULL),
('58:221', 58, 'movement', 'DONE', '2026-03-26 15:22:05', NULL),
('58:222', 58, 'temperature', 'DONE', '2026-03-26 15:22:05', NULL),
('58:223', 58, 'movement', 'DONE', '2026-03-26 15:22:06', NULL),
('58:224', 58, 'temperature', 'DONE', '2026-03-26 15:22:06', NULL),
('58:225', 58, 'movement', 'DONE', '2026-03-26 15:22:07', NULL),
('58:226', 58, 'temperature', 'DONE', '2026-03-26 15:22:07', NULL),
('58:227', 58, 'movement', 'DONE', '2026-03-26 15:22:08', NULL),
('58:228', 58, 'temperature', 'DONE', '2026-03-26 15:22:08', NULL),
('58:229', 58, 'movement', 'DONE', '2026-03-26 15:22:09', NULL),
('58:23', 58, 'movement', 'DONE', '2026-03-26 15:20:23', NULL),
('58:230', 58, 'temperature', 'DONE', '2026-03-26 15:22:09', NULL),
('58:231', 58, 'movement', 'DONE', '2026-03-26 15:22:10', NULL),
('58:232', 58, 'temperature', 'INVALID', '2026-03-26 15:22:10', 'A simulacao 58 ja foi terminada'),
('58:24', 58, 'movement', 'DONE', '2026-03-26 15:20:24', NULL),
('58:25', 58, 'movement', 'DONE', '2026-03-26 15:20:25', NULL),
('58:26', 58, 'movement', 'DONE', '2026-03-26 15:20:26', NULL),
('58:27', 58, 'movement', 'DONE', '2026-03-26 15:20:27', NULL),
('58:28', 58, 'movement', 'DONE', '2026-03-26 15:20:28', NULL),
('58:29', 58, 'movement', 'DONE', '2026-03-26 15:20:29', NULL),
('58:3', 58, 'movement', 'DONE', '2026-03-26 15:20:01', NULL),
('58:30', 58, 'movement', 'DONE', '2026-03-26 15:20:30', NULL),
('58:31', 58, 'movement', 'DONE', '2026-03-26 15:20:31', NULL),
('58:32', 58, 'temperature', 'DONE', '2026-03-26 15:20:32', NULL),
('58:33', 58, 'sound', 'DONE', '2026-03-26 15:20:32', NULL),
('58:34', 58, 'movement', 'DONE', '2026-03-26 15:20:33', NULL),
('58:35', 58, 'sound', 'DONE', '2026-03-26 15:20:33', NULL),
('58:36', 58, 'temperature', 'DONE', '2026-03-26 15:20:33', NULL),
('58:37', 58, 'sound', 'DONE', '2026-03-26 15:20:34', NULL),
('58:38', 58, 'temperature', 'DONE', '2026-03-26 15:20:34', NULL),
('58:39', 58, 'movement', 'DONE', '2026-03-26 15:20:35', NULL),
('58:4', 58, 'movement', 'DONE', '2026-03-26 15:20:02', NULL),
('58:40', 58, 'sound', 'DONE', '2026-03-26 15:20:35', NULL),
('58:41', 58, 'temperature', 'DONE', '2026-03-26 15:20:35', NULL),
('58:42', 58, 'sound', 'DONE', '2026-03-26 15:20:36', NULL),
('58:43', 58, 'temperature', 'DONE', '2026-03-26 15:20:36', NULL),
('58:44', 58, 'movement', 'DONE', '2026-03-26 15:20:37', NULL),
('58:45', 58, 'sound', 'DONE', '2026-03-26 15:20:38', NULL),
('58:46', 58, 'temperature', 'DONE', '2026-03-26 15:20:38', NULL),
('58:47', 58, 'sound', 'DONE', '2026-03-26 15:20:39', NULL),
('58:48', 58, 'temperature', 'DONE', '2026-03-26 15:20:39', NULL),
('58:49', 58, 'movement', 'DONE', '2026-03-26 15:20:39', NULL),
('58:5', 58, 'movement', 'DONE', '2026-03-26 15:20:03', NULL),
('58:50', 58, 'sound', 'DONE', '2026-03-26 15:20:40', NULL),
('58:51', 58, 'temperature', 'DONE', '2026-03-26 15:20:40', NULL),
('58:52', 58, 'sound', 'DONE', '2026-03-26 15:20:41', NULL),
('58:53', 58, 'temperature', 'DONE', '2026-03-26 15:20:41', NULL),
('58:54', 58, 'movement', 'DONE', '2026-03-26 15:20:41', NULL),
('58:55', 58, 'sound', 'DONE', '2026-03-26 15:20:41', NULL),
('58:56', 58, 'temperature', 'DONE', '2026-03-26 15:20:41', NULL),
('58:57', 58, 'sound', 'INVALID', '2026-03-26 15:20:42', 'Hour invalid'),
('58:58', 58, 'temperature', 'DONE', '2026-03-26 15:20:42', NULL),
('58:59', 58, 'movement', 'DONE', '2026-03-26 15:20:44', NULL),
('58:6', 58, 'movement', 'DONE', '2026-03-26 15:20:04', NULL),
('58:60', 58, 'sound', 'DONE', '2026-03-26 15:20:44', NULL),
('58:61', 58, 'temperature', 'DONE', '2026-03-26 15:20:44', NULL),
('58:62', 58, 'sound', 'DONE', '2026-03-26 15:20:45', NULL),
('58:63', 58, 'temperature', 'DONE', '2026-03-26 15:20:45', NULL),
('58:64', 58, 'movement', 'DONE', '2026-03-26 15:20:46', NULL),
('58:65', 58, 'sound', 'DONE', '2026-03-26 15:20:46', NULL),
('58:66', 58, 'temperature', 'INVALID', '2026-03-26 15:20:46', 'Temperature event invalid: value >= 60'),
('58:67', 58, 'sound', 'DONE', '2026-03-26 15:20:47', NULL),
('58:68', 58, 'temperature', 'INVALID', '2026-03-26 15:20:47', 'Temperature event invalid: value >= 60'),
('58:69', 58, 'movement', 'DONE', '2026-03-26 15:20:47', NULL),
('58:7', 58, 'movement', 'DONE', '2026-03-26 15:20:05', NULL),
('58:70', 58, 'sound', 'DONE', '2026-03-26 15:20:48', NULL),
('58:71', 58, 'temperature', 'INVALID', '2026-03-26 15:20:48', 'Temperature event invalid: value >= 60'),
('58:72', 58, 'sound', 'DONE', '2026-03-26 15:20:49', NULL),
('58:73', 58, 'temperature', 'INVALID', '2026-03-26 15:20:49', 'Temperature event invalid: value >= 60'),
('58:74', 58, 'movement', 'DONE', '2026-03-26 15:20:50', NULL),
('58:75', 58, 'sound', 'DONE', '2026-03-26 15:20:50', NULL),
('58:76', 58, 'temperature', 'INVALID', '2026-03-26 15:20:50', 'Temperature event invalid: value >= 60'),
('58:77', 58, 'sound', 'DONE', '2026-03-26 15:20:51', NULL),
('58:78', 58, 'temperature', 'INVALID', '2026-03-26 15:20:51', 'Temperature event invalid: value >= 60'),
('58:79', 58, 'movement', 'DONE', '2026-03-26 15:20:52', NULL),
('58:8', 58, 'movement', 'DONE', '2026-03-26 15:20:07', NULL),
('58:80', 58, 'sound', 'DONE', '2026-03-26 15:20:52', NULL),
('58:81', 58, 'temperature', 'INVALID', '2026-03-26 15:20:52', 'Temperature event invalid: value >= 60'),
('58:82', 58, 'sound', 'DONE', '2026-03-26 15:20:53', NULL),
('58:83', 58, 'temperature', 'INVALID', '2026-03-26 15:20:53', 'Temperature event invalid: value >= 60'),
('58:84', 58, 'movement', 'INVALID', '2026-03-26 15:20:54', 'Movement invalid: RoomOrigin does not match Marsami current room'),
('58:85', 58, 'movement', 'DONE', '2026-03-26 15:20:54', NULL),
('58:86', 58, 'sound', 'DONE', '2026-03-26 15:20:54', NULL),
('58:87', 58, 'temperature', 'INVALID', '2026-03-26 15:20:54', 'Temperature event invalid: value >= 60'),
('58:88', 58, 'sound', 'DONE', '2026-03-26 15:20:55', NULL),
('58:89', 58, 'temperature', 'INVALID', '2026-03-26 15:20:55', 'Temperature event invalid: value >= 60'),
('58:9', 58, 'movement', 'DONE', '2026-03-26 15:20:08', NULL),
('58:90', 58, 'movement', 'DONE', '2026-03-26 15:20:56', NULL),
('58:91', 58, 'sound', 'DONE', '2026-03-26 15:20:56', NULL),
('58:92', 58, 'temperature', 'INVALID', '2026-03-26 15:20:56', 'Temperature event invalid: value >= 60'),
('58:93', 58, 'sound', 'DONE', '2026-03-26 15:20:57', NULL),
('58:94', 58, 'temperature', 'DONE', '2026-03-26 15:20:57', NULL),
('58:95', 58, 'movement', 'DONE', '2026-03-26 15:20:58', NULL),
('58:96', 58, 'sound', 'DONE', '2026-03-26 15:20:58', NULL),
('58:97', 58, 'temperature', 'DONE', '2026-03-26 15:20:58', NULL),
('58:98', 58, 'sound', 'DONE', '2026-03-26 15:20:59', NULL),
('58:99', 58, 'temperature', 'DONE', '2026-03-26 15:20:59', NULL);

-- --------------------------------------------------------

--
-- 表的结构 `Marsami`
--

CREATE TABLE `Marsami` (
  `IDMarsami` int(11) NOT NULL,
  `Player` int(11) DEFAULT NULL,
  `IDSimulacao` int(11) NOT NULL,
  `SalaAtual` int(11) DEFAULT NULL,
  `Tipo` varchar(4) DEFAULT NULL,
  `Estado` int(11) DEFAULT NULL,
  `UltimaHoraMovimento` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Marsami`
--

INSERT INTO `Marsami` (`IDMarsami`, `Player`, `IDSimulacao`, `SalaAtual`, `Tipo`, `Estado`, `UltimaHoraMovimento`) VALUES
(1, 5, 52, 1, 'odd', 2, '2026-03-25 01:08:23'),
(2, 5, 52, 7, 'even', 2, '2026-03-25 01:08:23'),
(3, 5, 52, 5, 'odd', 2, '2026-03-25 01:08:32'),
(4, 5, 52, 5, 'even', 2, '2026-03-25 01:08:29'),
(5, 5, 52, 5, 'odd', 2, '2026-03-25 01:08:28'),
(6, 5, 52, 1, 'even', 2, '2026-03-25 01:08:29'),
(7, 5, 52, 2, 'odd', 2, '2026-03-25 01:08:30'),
(8, 5, 52, 1, 'even', 2, '2026-03-25 01:08:31'),
(9, 5, 52, 6, 'odd', 2, '2026-03-25 01:08:31'),
(10, 5, 52, 1, 'even', 2, '2026-03-25 01:08:33'),
(11, 5, 52, 8, 'odd', 2, '2026-03-25 01:08:34'),
(12, 5, 52, 6, 'even', 2, '2026-03-25 01:08:35'),
(13, 5, 52, 7, 'odd', 2, '2026-03-25 01:08:36'),
(14, 5, 52, 1, 'even', 2, '2026-03-25 01:08:37'),
(15, 5, 52, 10, 'odd', 2, '2026-03-25 01:08:42'),
(16, 5, 52, 10, 'even', 2, '2026-03-25 01:08:41'),
(17, 5, 52, 1, 'odd', 2, '2026-03-25 01:08:43'),
(18, 5, 52, 5, 'even', 2, '2026-03-25 01:08:41'),
(19, 5, 52, 8, 'odd', 2, '2026-03-25 01:08:44'),
(20, 5, 52, 4, 'even', 2, '2026-03-25 01:08:45'),
(21, 5, 52, 3, 'odd', 2, '2026-03-25 01:08:45'),
(22, 5, 52, 3, 'even', 2, '2026-03-25 01:08:46'),
(23, 5, 52, 5, 'odd', 2, '2026-03-25 01:08:49'),
(24, 5, 52, 3, 'even', 2, '2026-03-25 01:08:49'),
(25, 5, 52, 7, 'odd', 2, '2026-03-25 01:08:49'),
(26, 5, 52, 8, 'even', 2, '2026-03-25 01:08:51'),
(27, 5, 52, 5, 'odd', 2, '2026-03-25 01:08:51'),
(28, 5, 52, 3, 'even', 2, '2026-03-25 01:08:52'),
(29, 5, 52, 1, 'odd', 2, '2026-03-25 01:08:54'),
(30, 5, 52, 10, 'even', 2, '2026-03-25 01:08:55'),
(1, 5, 53, 2, 'odd', 2, '2026-03-25 01:28:49'),
(2, 5, 53, 5, 'even', 2, '2026-03-25 01:28:53'),
(3, 5, 53, 7, 'odd', 2, '2026-03-25 01:28:55'),
(4, 5, 53, 7, 'even', 2, '2026-03-25 01:28:57'),
(5, 5, 53, 4, 'odd', 2, '2026-03-25 01:28:54'),
(6, 5, 53, 6, 'even', 2, '2026-03-25 01:28:56'),
(7, 5, 53, 6, 'odd', 2, '2026-03-25 01:28:57'),
(8, 5, 53, 1, 'even', 2, '2026-03-25 01:29:01'),
(9, 5, 53, 5, 'odd', 2, '2026-03-25 01:29:04'),
(10, 5, 53, 6, 'even', 2, '2026-03-25 01:29:01'),
(11, 5, 53, 4, 'odd', 2, '2026-03-25 01:29:00'),
(12, 5, 53, 5, 'even', 2, '2026-03-25 01:29:02'),
(13, 5, 53, 5, 'odd', 2, '2026-03-25 01:29:04'),
(14, 5, 53, 5, 'even', 2, '2026-03-25 01:29:03'),
(15, 5, 53, 2, 'odd', 2, '2026-03-25 01:29:05'),
(16, 5, 53, 9, 'even', 2, '2026-03-25 01:29:05'),
(17, 5, 53, 9, 'odd', 2, '2026-03-25 01:29:06'),
(18, 5, 53, 5, 'even', 2, '2026-03-25 01:29:08'),
(19, 5, 53, 7, 'odd', 2, '2026-03-25 01:29:10'),
(20, 5, 53, 10, 'even', 2, '2026-03-25 01:29:10'),
(21, 5, 53, 8, 'odd', 2, '2026-03-25 01:29:10'),
(22, 5, 53, 5, 'even', 2, '2026-03-25 01:29:11'),
(23, 5, 53, 4, 'odd', 2, '2026-03-25 01:29:13'),
(24, 5, 53, 2, 'even', 2, '2026-03-25 01:29:14'),
(25, 5, 53, 5, 'odd', 2, '2026-03-25 01:29:15'),
(26, 5, 53, 3, 'even', 2, '2026-03-25 01:29:17'),
(27, 5, 53, 7, 'odd', 2, '2026-03-25 01:29:18'),
(28, 5, 53, 3, 'even', 2, '2026-03-25 01:29:19'),
(29, 5, 53, 5, 'odd', 2, '2026-03-25 01:29:20'),
(30, 5, 53, 2, 'even', 2, '2026-03-25 01:29:21'),
(1, 5, 54, 10, 'odd', 2, '2026-03-25 01:43:26'),
(2, 5, 54, 2, 'even', 2, '2026-03-25 01:43:27'),
(3, 5, 54, 10, 'odd', 2, '2026-03-25 01:43:28'),
(4, 5, 54, 1, 'even', 2, '2026-03-25 01:43:29'),
(5, 5, 54, 8, 'odd', 2, '2026-03-25 01:43:30'),
(6, 5, 54, 7, 'even', 2, '2026-03-25 01:43:33'),
(7, 5, 54, 8, 'odd', 2, '2026-03-25 01:43:35'),
(8, 5, 54, 9, 'even', 2, '2026-03-25 01:43:35'),
(9, 5, 54, 3, 'odd', 2, '2026-03-25 01:43:43'),
(10, 5, 54, 5, 'even', 2, '2026-03-25 01:43:37'),
(11, 5, 54, 10, 'odd', 2, '2026-03-25 01:43:39'),
(12, 5, 54, 8, 'even', 2, '2026-03-25 01:43:38'),
(13, 5, 54, 1, 'odd', 2, '2026-03-25 01:43:40'),
(14, 5, 54, 3, 'even', 2, '2026-03-25 01:43:41'),
(15, 5, 54, 9, 'odd', 2, '2026-03-25 01:43:42'),
(16, 5, 54, 7, 'even', 2, '2026-03-25 01:43:43'),
(17, 5, 54, 9, 'odd', 2, '2026-03-25 01:43:44'),
(18, 5, 54, 7, 'even', 2, '2026-03-25 01:43:45'),
(19, 5, 54, 2, 'odd', 2, '2026-03-25 01:43:46'),
(20, 5, 54, 2, 'even', 2, '2026-03-25 01:43:48'),
(21, 5, 54, 1, 'odd', 2, '2026-03-25 01:43:50'),
(22, 5, 54, 3, 'even', 2, '2026-03-25 01:43:51'),
(23, 5, 54, 4, 'odd', 2, '2026-03-25 01:43:50'),
(24, 5, 54, 5, 'even', 2, '2026-03-25 01:43:52'),
(25, 5, 54, 5, 'odd', 2, '2026-03-25 01:43:53'),
(26, 5, 54, 2, 'even', 2, '2026-03-25 01:43:54'),
(27, 5, 54, 8, 'odd', 2, '2026-03-25 01:43:55'),
(28, 5, 54, 5, 'even', 2, '2026-03-25 01:43:56'),
(29, 5, 54, 10, 'odd', 2, '2026-03-25 01:43:57'),
(30, 5, 54, 7, 'even', 2, '2026-03-25 01:43:58'),
(1, 5, 55, 5, 'odd', 2, '2026-03-25 16:31:41'),
(2, 5, 55, 10, 'even', 2, '2026-03-25 16:31:42'),
(3, 5, 55, 1, 'odd', 2, '2026-03-25 16:31:43'),
(4, 5, 55, 3, 'even', 2, '2026-03-25 16:31:43'),
(5, 5, 55, 5, 'odd', 2, '2026-03-25 16:31:44'),
(6, 5, 55, 2, 'even', 2, '2026-03-25 16:31:45'),
(7, 5, 55, 3, 'odd', 2, '2026-03-25 16:31:46'),
(8, 5, 55, 10, 'even', 2, '2026-03-25 16:31:47'),
(9, 5, 55, 9, 'odd', 2, '2026-03-25 16:31:49'),
(10, 5, 55, 5, 'even', 2, '2026-03-25 16:31:49'),
(11, 5, 55, 5, 'odd', 2, '2026-03-25 16:31:50'),
(12, 5, 55, 5, 'even', 2, '2026-03-25 16:31:52'),
(13, 5, 55, 8, 'odd', 2, '2026-03-25 16:31:53'),
(14, 5, 55, 4, 'even', 2, '2026-03-25 16:31:53'),
(15, 5, 55, 10, 'odd', 2, '2026-03-25 16:31:54'),
(16, 5, 55, 7, 'even', 2, '2026-03-25 16:31:56'),
(17, 5, 55, 4, 'odd', 2, '2026-03-25 16:31:58'),
(18, 5, 55, 6, 'even', 2, '2026-03-25 16:31:57'),
(19, 5, 55, 5, 'odd', 2, '2026-03-25 16:31:58'),
(20, 5, 55, 10, 'even', 2, '2026-03-25 16:32:00'),
(21, 5, 55, 4, 'odd', 2, '2026-03-25 16:32:01'),
(22, 5, 55, 8, 'even', 2, '2026-03-25 16:32:03'),
(23, 5, 55, 9, 'odd', 2, '2026-03-25 16:32:03'),
(24, 5, 55, 2, 'even', 2, '2026-03-25 16:32:04'),
(25, 5, 55, 10, 'odd', 2, '2026-03-25 16:32:05'),
(26, 5, 55, 1, 'even', 2, '2026-03-25 16:32:06'),
(27, 5, 55, 7, 'odd', 2, '2026-03-25 16:32:07'),
(28, 5, 55, 6, 'even', 2, '2026-03-25 16:32:08'),
(29, 5, 55, 5, 'odd', 2, '2026-03-25 16:32:09'),
(30, 5, 55, 6, 'even', 2, '2026-03-25 16:32:10'),
(1, 5, 56, 7, 'odd', 2, '2026-03-26 14:52:37'),
(2, 5, 56, 1, 'even', 2, '2026-03-26 14:52:37'),
(3, 5, 56, 10, 'odd', 2, '2026-03-26 14:52:37'),
(4, 5, 56, 2, 'even', 2, '2026-03-26 14:52:37'),
(5, 5, 56, 6, 'odd', 2, '2026-03-26 14:52:37'),
(6, 5, 56, 5, 'even', 2, '2026-03-26 14:52:37'),
(7, 5, 56, 6, 'odd', 2, '2026-03-26 14:52:37'),
(8, 5, 56, 5, 'even', 2, '2026-03-26 14:52:37'),
(9, 5, 56, 4, 'odd', 2, '2026-03-26 14:52:37'),
(10, 5, 56, 1, 'even', 2, '2026-03-26 14:52:37'),
(11, 5, 56, 2, 'odd', 2, '2026-03-26 14:52:37'),
(12, 5, 56, 1, 'even', 2, '2026-03-26 14:52:38'),
(13, 5, 56, 3, 'odd', 2, '2026-03-26 14:52:38'),
(14, 5, 56, 7, 'even', 2, '2026-03-26 14:52:38'),
(15, 5, 56, 9, 'odd', 2, '2026-03-26 14:52:38'),
(16, 5, 56, 8, 'even', 2, '2026-03-26 14:52:38'),
(17, 5, 56, 3, 'odd', 2, '2026-03-26 14:52:38'),
(18, 5, 56, 10, 'even', 2, '2026-03-26 14:52:41'),
(19, 5, 56, 3, 'odd', 2, '2026-03-26 14:52:41'),
(20, 5, 56, 9, 'even', 2, '2026-03-26 14:52:41'),
(21, 5, 56, 3, 'odd', 2, '2026-03-26 14:52:41'),
(22, 5, 56, 7, 'even', 2, '2026-03-26 14:52:41'),
(23, 5, 56, 1, 'odd', 2, '2026-03-26 14:52:41'),
(24, 5, 56, 1, 'even', 2, '2026-03-26 14:52:41'),
(25, 5, 56, 5, 'odd', 2, '2026-03-26 14:52:51'),
(26, 5, 56, 2, 'even', 2, '2026-03-26 14:52:51'),
(27, 5, 56, 7, 'odd', 2, '2026-03-26 14:52:51'),
(28, 5, 56, 5, 'even', 2, '2026-03-26 14:52:51'),
(29, 5, 56, 9, 'odd', 2, '2026-03-26 14:52:51'),
(30, 5, 56, 5, 'even', 2, '2026-03-26 14:52:51'),
(1, 5, 57, 2, 'odd', 2, '2026-03-26 15:02:20'),
(2, 5, 57, 6, 'even', 2, '2026-03-26 15:02:22'),
(3, 5, 57, 1, 'odd', 2, '2026-03-26 15:02:23'),
(4, 5, 57, 10, 'even', 2, '2026-03-26 15:02:24'),
(5, 5, 57, 8, 'odd', 2, '2026-03-26 15:02:27'),
(6, 5, 57, 10, 'even', 2, '2026-03-26 15:02:27'),
(7, 5, 57, 2, 'odd', 2, '2026-03-26 15:02:26'),
(8, 5, 57, 7, 'even', 2, '2026-03-26 15:02:29'),
(9, 5, 57, 10, 'odd', 2, '2026-03-26 15:02:29'),
(10, 5, 57, 3, 'even', 2, '2026-03-26 15:02:30'),
(11, 5, 57, 2, 'odd', 2, '2026-03-26 15:02:32'),
(12, 5, 57, 5, 'even', 2, '2026-03-26 15:02:32'),
(13, 5, 57, 7, 'odd', 2, '2026-03-26 15:02:33'),
(14, 5, 57, 5, 'even', 2, '2026-03-26 15:02:33'),
(15, 5, 57, 5, 'odd', 2, '2026-03-26 15:02:35'),
(16, 5, 57, 2, 'even', 2, '2026-03-26 15:02:36'),
(17, 5, 57, 4, 'odd', 2, '2026-03-26 15:02:38'),
(18, 5, 57, 6, 'even', 2, '2026-03-26 15:02:38'),
(19, 5, 57, 8, 'odd', 2, '2026-03-26 15:02:39'),
(20, 5, 57, 7, 'even', 2, '2026-03-26 15:02:40'),
(21, 5, 57, 4, 'odd', 2, '2026-03-26 15:02:41'),
(22, 5, 57, 5, 'even', 2, '2026-03-26 15:02:42'),
(23, 5, 57, 10, 'odd', 2, '2026-03-26 15:02:43'),
(24, 5, 57, 7, 'even', 2, '2026-03-26 15:02:44'),
(25, 5, 57, 5, 'odd', 2, '2026-03-26 15:02:45'),
(26, 5, 57, 7, 'even', 2, '2026-03-26 15:02:46'),
(27, 5, 57, 2, 'odd', 2, '2026-03-26 15:02:47'),
(28, 5, 57, 9, 'even', 2, '2026-03-26 15:02:48'),
(29, 5, 57, 8, 'odd', 2, '2026-03-26 15:02:49'),
(30, 5, 57, 6, 'even', 2, '2026-03-26 15:02:51'),
(1, 5, 58, 7, 'odd', 2, '2026-03-26 15:21:40'),
(2, 5, 58, 5, 'even', 2, '2026-03-26 15:21:43'),
(3, 5, 58, 5, 'odd', 2, '2026-03-26 15:21:42'),
(4, 5, 58, 8, 'even', 2, '2026-03-26 15:21:43'),
(5, 5, 58, 5, 'odd', 2, '2026-03-26 15:21:44'),
(6, 5, 58, 5, 'even', 2, '2026-03-26 15:21:45'),
(7, 5, 58, 5, 'odd', 2, '2026-03-26 15:21:46'),
(8, 5, 58, 5, 'even', 2, '2026-03-26 15:21:47'),
(9, 5, 58, 7, 'odd', 2, '2026-03-26 15:21:48'),
(10, 5, 58, 3, 'even', 2, '2026-03-26 15:21:50'),
(11, 5, 58, 5, 'odd', 2, '2026-03-26 15:21:51'),
(12, 5, 58, 7, 'even', 2, '2026-03-26 15:21:52'),
(13, 5, 58, 7, 'odd', 2, '2026-03-26 15:21:52'),
(14, 5, 58, 1, 'even', 2, '2026-03-26 15:21:53'),
(15, 5, 58, 3, 'odd', 2, '2026-03-26 15:21:56'),
(16, 5, 58, 3, 'even', 2, '2026-03-26 15:21:56'),
(17, 5, 58, 10, 'odd', 2, '2026-03-26 15:21:57'),
(18, 5, 58, 5, 'even', 2, '2026-03-26 15:21:57'),
(19, 5, 58, 4, 'odd', 2, '2026-03-26 15:21:58'),
(20, 5, 58, 5, 'even', 2, '2026-03-26 15:22:00'),
(21, 5, 58, 7, 'odd', 2, '2026-03-26 15:22:00'),
(22, 5, 58, 10, 'even', 2, '2026-03-26 15:22:02'),
(23, 5, 58, 1, 'odd', 2, '2026-03-26 15:22:03'),
(24, 5, 58, 2, 'even', 2, '2026-03-26 15:22:04'),
(25, 5, 58, 5, 'odd', 2, '2026-03-26 15:22:05'),
(26, 5, 58, 7, 'even', 2, '2026-03-26 15:22:06'),
(27, 5, 58, 5, 'odd', 2, '2026-03-26 15:22:07'),
(28, 5, 58, 1, 'even', 2, '2026-03-26 15:22:08'),
(29, 5, 58, 9, 'odd', 2, '2026-03-26 15:22:09'),
(30, 5, 58, 3, 'even', 2, '2026-03-26 15:22:10');

-- --------------------------------------------------------

--
-- 表的结构 `MedicoesPassagens`
--

CREATE TABLE `MedicoesPassagens` (
  `IDMedicao` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `SalaOrigem` int(11) DEFAULT NULL,
  `SalaDestino` int(11) DEFAULT NULL,
  `Marsami` int(11) DEFAULT NULL,
  `Status` int(11) DEFAULT NULL,
  `IDSimulacao` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `MedicoesPassagens`
--

INSERT INTO `MedicoesPassagens` (`IDMedicao`, `Hora`, `SalaOrigem`, `SalaDestino`, `Marsami`, `Status`, `IDSimulacao`) VALUES
(1, '2026-03-25 01:06:42', 0, 1, 1, 1, 52),
(2, '2026-03-25 01:06:43', 0, 5, 2, 1, 52),
(3, '2026-03-25 01:06:44', 0, 4, 3, 1, 52),
(4, '2026-03-25 01:06:45', 0, 7, 4, 1, 52),
(5, '2026-03-25 01:06:46', 0, 2, 5, 1, 52),
(6, '2026-03-25 01:06:47', 0, 1, 6, 1, 52),
(7, '2026-03-25 01:06:48', 0, 2, 7, 1, 52),
(8, '2026-03-25 01:06:50', 0, 1, 8, 1, 52),
(9, '2026-03-25 01:06:51', 0, 6, 9, 1, 52),
(10, '2026-03-25 01:06:52', 0, 1, 10, 1, 52),
(11, '2026-03-25 01:06:53', 0, 6, 11, 1, 52),
(12, '2026-03-25 01:06:54', 0, 6, 12, 1, 52),
(13, '2026-03-25 01:06:55', 0, 7, 13, 1, 52),
(14, '2026-03-25 01:06:56', 0, 1, 14, 1, 52),
(15, '2026-03-25 01:06:57', 0, 8, 15, 1, 52),
(16, '2026-03-25 01:06:59', 0, 8, 16, 1, 52),
(17, '2026-03-25 01:07:00', 0, 1, 17, 1, 52),
(18, '2026-03-25 01:07:01', 0, 5, 18, 1, 52),
(19, '2026-03-25 01:07:02', 0, 8, 19, 1, 52),
(20, '2026-03-25 01:07:03', 0, 4, 20, 1, 52),
(21, '2026-03-25 01:07:04', 0, 3, 21, 1, 52),
(22, '2026-03-25 01:07:05', 0, 3, 22, 1, 52),
(23, '2026-03-25 01:07:06', 0, 7, 23, 1, 52),
(24, '2026-03-25 01:07:08', 0, 1, 24, 1, 52),
(25, '2026-03-25 01:07:09', 0, 5, 25, 1, 52),
(26, '2026-03-25 01:07:10', 0, 6, 26, 1, 52),
(27, '2026-03-25 01:07:11', 0, 9, 27, 1, 52),
(28, '2026-03-25 01:07:12', 0, 3, 28, 1, 52),
(29, '2026-03-25 01:07:13', 0, 1, 29, 1, 52),
(30, '2026-03-25 01:07:15', 0, 10, 30, 1, 52),
(31, '2026-03-25 01:07:16', 2, 4, 5, 1, 52),
(32, '2026-03-25 01:07:20', 4, 5, 3, 1, 52),
(33, '2026-03-25 01:07:24', 5, 7, 2, 1, 52),
(34, '2026-03-25 01:07:29', 6, 8, 11, 1, 52),
(35, '2026-03-25 01:07:33', 7, 5, 4, 1, 52),
(36, '2026-03-25 01:07:37', 8, 10, 16, 1, 52),
(37, '2026-03-25 01:07:41', 7, 5, 23, 1, 52),
(38, '2026-03-25 01:07:45', 9, 7, 27, 1, 52),
(39, '2026-03-25 01:07:50', 8, 10, 15, 1, 52),
(40, '2026-03-25 01:07:53', 6, 8, 26, 1, 52),
(41, '2026-03-25 01:07:58', 7, 5, 27, 1, 52),
(42, '2026-03-25 01:08:02', 4, 5, 5, 1, 52),
(43, '2026-03-25 01:08:06', 5, 7, 25, 1, 52),
(44, '2026-03-25 01:08:10', 1, 3, 24, 1, 52),
(45, '2026-03-25 01:08:23', 0, 0, 1, 2, 52),
(46, '2026-03-25 01:08:23', 0, 0, 2, 2, 52),
(47, '2026-03-25 01:08:28', 0, 0, 5, 2, 52),
(48, '2026-03-25 01:08:29', 0, 0, 6, 2, 52),
(49, '2026-03-25 01:08:29', 0, 0, 4, 2, 52),
(50, '2026-03-25 01:08:30', 0, 0, 7, 2, 52),
(51, '2026-03-25 01:08:31', 0, 0, 8, 2, 52),
(52, '2026-03-25 01:08:31', 0, 0, 9, 2, 52),
(53, '2026-03-25 01:08:32', 0, 0, 3, 2, 52),
(54, '2026-03-25 01:08:33', 0, 0, 10, 2, 52),
(55, '2026-03-25 01:08:34', 0, 0, 11, 2, 52),
(56, '2026-03-25 01:08:35', 0, 0, 12, 2, 52),
(57, '2026-03-25 01:08:36', 0, 0, 13, 2, 52),
(58, '2026-03-25 01:08:37', 0, 0, 14, 2, 52),
(59, '2026-03-25 01:08:41', 0, 0, 16, 2, 52),
(60, '2026-03-25 01:08:41', 0, 0, 18, 2, 52),
(61, '2026-03-25 01:08:42', 0, 0, 15, 2, 52),
(62, '2026-03-25 01:08:43', 0, 0, 17, 2, 52),
(63, '2026-03-25 01:08:44', 0, 0, 19, 2, 52),
(64, '2026-03-25 01:08:45', 0, 0, 20, 2, 52),
(65, '2026-03-25 01:08:45', 0, 0, 21, 2, 52),
(66, '2026-03-25 01:08:46', 0, 0, 22, 2, 52),
(67, '2026-03-25 01:08:49', 0, 0, 24, 2, 52),
(68, '2026-03-25 01:08:49', 0, 0, 23, 2, 52),
(69, '2026-03-25 01:08:49', 0, 0, 25, 2, 52),
(70, '2026-03-25 01:08:51', 0, 0, 26, 2, 52),
(71, '2026-03-25 01:08:51', 0, 0, 27, 2, 52),
(72, '2026-03-25 01:08:52', 0, 0, 28, 2, 52),
(73, '2026-03-25 01:08:54', 0, 0, 29, 2, 52),
(74, '2026-03-25 01:08:55', 0, 0, 30, 2, 52),
(75, '2026-03-25 01:27:08', 0, 2, 1, 1, 53),
(76, '2026-03-25 01:27:09', 0, 2, 2, 1, 53),
(77, '2026-03-25 01:27:10', 0, 2, 3, 1, 53),
(78, '2026-03-25 01:27:11', 0, 7, 4, 1, 53),
(79, '2026-03-25 01:27:12', 0, 4, 5, 1, 53),
(80, '2026-03-25 01:27:14', 0, 6, 6, 1, 53),
(81, '2026-03-25 01:27:15', 0, 6, 7, 1, 53),
(82, '2026-03-25 01:27:16', 0, 1, 8, 1, 53),
(83, '2026-03-25 01:27:17', 0, 7, 9, 1, 53),
(84, '2026-03-25 01:27:18', 0, 6, 10, 1, 53),
(85, '2026-03-25 01:27:19', 0, 4, 11, 1, 53),
(86, '2026-03-25 01:27:20', 0, 7, 12, 1, 53),
(87, '2026-03-25 01:27:21', 0, 4, 13, 1, 53),
(88, '2026-03-25 01:27:22', 0, 4, 14, 1, 53),
(89, '2026-03-25 01:27:23', 0, 3, 15, 1, 53),
(90, '2026-03-25 01:27:24', 0, 9, 16, 1, 53),
(91, '2026-03-25 01:27:26', 0, 9, 17, 1, 53),
(92, '2026-03-25 01:27:27', 0, 2, 18, 1, 53),
(93, '2026-03-25 01:27:29', 0, 7, 19, 1, 53),
(94, '2026-03-25 01:27:30', 0, 10, 20, 1, 53),
(95, '2026-03-25 01:27:31', 0, 8, 21, 1, 53),
(96, '2026-03-25 01:27:32', 0, 7, 22, 1, 53),
(97, '2026-03-25 01:27:33', 0, 2, 23, 1, 53),
(98, '2026-03-25 01:27:34', 0, 2, 24, 1, 53),
(99, '2026-03-25 01:27:35', 0, 2, 25, 1, 53),
(100, '2026-03-25 01:27:36', 0, 3, 26, 1, 53),
(101, '2026-03-25 01:27:37', 0, 7, 27, 1, 53),
(102, '2026-03-25 01:27:38', 0, 3, 28, 1, 53),
(103, '2026-03-25 01:27:39', 0, 7, 29, 1, 53),
(104, '2026-03-25 01:27:40', 0, 3, 30, 1, 53),
(105, '2026-03-25 01:27:41', 4, 5, 14, 1, 53),
(106, '2026-03-25 01:27:46', 7, 5, 9, 1, 53),
(107, '2026-03-25 01:27:50', 7, 5, 12, 1, 53),
(108, '2026-03-25 01:27:55', 2, 5, 25, 1, 53),
(109, '2026-03-25 01:27:59', 3, 2, 30, 1, 53),
(110, '2026-03-25 01:28:03', 2, 5, 3, 1, 53),
(111, '2026-03-25 01:28:07', 7, 5, 22, 1, 53),
(112, '2026-03-25 01:28:11', 3, 2, 15, 1, 53),
(113, '2026-03-25 01:28:15', 2, 5, 18, 1, 53),
(114, '2026-03-25 01:28:19', 4, 5, 13, 1, 53),
(115, '2026-03-25 01:28:24', 2, 5, 2, 1, 53),
(116, '2026-03-25 01:28:28', 2, 4, 23, 1, 53),
(117, '2026-03-25 01:28:32', 5, 7, 3, 1, 53),
(118, '2026-03-25 01:28:36', 7, 5, 29, 1, 53),
(119, '2026-03-25 01:28:49', 0, 0, 1, 2, 53),
(120, '2026-03-25 01:28:53', 0, 0, 2, 2, 53),
(121, '2026-03-25 01:28:54', 0, 0, 5, 2, 53),
(122, '2026-03-25 01:28:55', 0, 0, 3, 2, 53),
(123, '2026-03-25 01:28:56', 0, 0, 6, 2, 53),
(124, '2026-03-25 01:28:57', 0, 0, 7, 2, 53),
(125, '2026-03-25 01:28:57', 0, 0, 4, 2, 53),
(126, '2026-03-25 01:29:00', 0, 0, 11, 2, 53),
(127, '2026-03-25 01:29:01', 0, 0, 8, 2, 53),
(128, '2026-03-25 01:29:01', 0, 0, 10, 2, 53),
(129, '2026-03-25 01:29:02', 0, 0, 12, 2, 53),
(130, '2026-03-25 01:29:03', 0, 0, 14, 2, 53),
(131, '2026-03-25 01:29:04', 0, 0, 13, 2, 53),
(132, '2026-03-25 01:29:04', 0, 0, 9, 2, 53),
(133, '2026-03-25 01:29:05', 0, 0, 16, 2, 53),
(134, '2026-03-25 01:29:05', 0, 0, 15, 2, 53),
(135, '2026-03-25 01:29:06', 0, 0, 17, 2, 53),
(136, '2026-03-25 01:29:08', 0, 0, 18, 2, 53),
(137, '2026-03-25 01:29:10', 0, 0, 19, 2, 53),
(138, '2026-03-25 01:29:10', 0, 0, 20, 2, 53),
(139, '2026-03-25 01:29:10', 0, 0, 21, 2, 53),
(140, '2026-03-25 01:29:11', 0, 0, 22, 2, 53),
(141, '2026-03-25 01:29:13', 0, 0, 23, 2, 53),
(142, '2026-03-25 01:29:14', 0, 0, 24, 2, 53),
(143, '2026-03-25 01:29:15', 0, 0, 25, 2, 53),
(144, '2026-03-25 01:29:17', 0, 0, 26, 2, 53),
(145, '2026-03-25 01:29:18', 0, 0, 27, 2, 53),
(146, '2026-03-25 01:29:19', 0, 0, 28, 2, 53),
(147, '2026-03-25 01:29:20', 0, 0, 29, 2, 53),
(148, '2026-03-25 01:29:21', 0, 0, 30, 2, 53),
(149, '2026-03-25 01:41:46', 0, 10, 1, 1, 54),
(150, '2026-03-25 01:41:47', 0, 3, 2, 1, 54),
(151, '2026-03-25 01:41:48', 0, 10, 3, 1, 54),
(152, '2026-03-25 01:41:49', 0, 1, 4, 1, 54),
(153, '2026-03-25 01:41:50', 0, 8, 5, 1, 54),
(154, '2026-03-25 01:41:51', 0, 7, 6, 1, 54),
(155, '2026-03-25 01:41:52', 0, 8, 7, 1, 54),
(156, '2026-03-25 01:41:53', 0, 9, 8, 1, 54),
(157, '2026-03-25 01:41:54', 0, 1, 9, 1, 54),
(158, '2026-03-25 01:41:56', 0, 7, 10, 1, 54),
(159, '2026-03-25 01:41:57', 0, 10, 11, 1, 54),
(160, '2026-03-25 01:41:58', 0, 8, 12, 1, 54),
(161, '2026-03-25 01:41:59', 0, 10, 13, 1, 54),
(162, '2026-03-25 01:42:00', 0, 1, 14, 1, 54),
(163, '2026-03-25 01:42:01', 0, 9, 15, 1, 54),
(164, '2026-03-25 01:42:02', 0, 9, 16, 1, 54),
(165, '2026-03-25 01:42:03', 0, 9, 17, 1, 54),
(166, '2026-03-25 01:42:04', 0, 7, 18, 1, 54),
(167, '2026-03-25 01:42:05', 0, 2, 19, 1, 54),
(168, '2026-03-25 01:42:06', 0, 2, 20, 1, 54),
(169, '2026-03-25 01:42:07', 0, 1, 21, 1, 54),
(170, '2026-03-25 01:42:09', 0, 7, 22, 1, 54),
(171, '2026-03-25 01:42:10', 0, 4, 23, 1, 54),
(172, '2026-03-25 01:42:11', 0, 3, 24, 1, 54),
(173, '2026-03-25 01:42:12', 0, 7, 25, 1, 54),
(174, '2026-03-25 01:42:13', 0, 2, 26, 1, 54),
(175, '2026-03-25 01:42:14', 0, 8, 27, 1, 54),
(176, '2026-03-25 01:42:15', 0, 5, 28, 1, 54),
(177, '2026-03-25 01:42:16', 0, 8, 29, 1, 54),
(178, '2026-03-25 01:42:18', 0, 4, 30, 1, 54),
(179, '2026-03-25 01:42:19', 3, 2, 24, 1, 54),
(180, '2026-03-25 01:42:23', 9, 7, 16, 1, 54),
(181, '2026-03-25 01:42:27', 4, 5, 30, 1, 54),
(182, '2026-03-25 01:42:32', 10, 1, 13, 1, 54),
(183, '2026-03-25 01:42:36', 8, 10, 29, 1, 54),
(184, '2026-03-25 01:42:40', 7, 5, 10, 1, 54),
(185, '2026-03-25 01:42:44', 5, 7, 30, 1, 54),
(186, '2026-03-25 01:42:48', 1, 3, 9, 1, 54),
(187, '2026-03-25 01:42:53', 3, 2, 2, 1, 54),
(188, '2026-03-25 01:42:57', 7, 5, 22, 1, 54),
(189, '2026-03-25 01:43:01', 5, 3, 22, 1, 54),
(190, '2026-03-25 01:43:05', 7, 5, 25, 1, 54),
(191, '2026-03-25 01:43:10', 1, 3, 14, 1, 54),
(192, '2026-03-25 01:43:14', 2, 5, 24, 1, 54),
(193, '2026-03-25 01:43:26', 0, 0, 1, 2, 54),
(194, '2026-03-25 01:43:27', 0, 0, 2, 2, 54),
(195, '2026-03-25 01:43:28', 0, 0, 3, 2, 54),
(196, '2026-03-25 01:43:29', 0, 0, 4, 2, 54),
(197, '2026-03-25 01:43:30', 0, 0, 5, 2, 54),
(198, '2026-03-25 01:43:33', 0, 0, 6, 2, 54),
(199, '2026-03-25 01:43:35', 0, 0, 8, 2, 54),
(200, '2026-03-25 01:43:35', 0, 0, 7, 2, 54),
(201, '2026-03-25 01:43:37', 0, 0, 10, 2, 54),
(202, '2026-03-25 01:43:38', 0, 0, 12, 2, 54),
(203, '2026-03-25 01:43:39', 0, 0, 11, 2, 54),
(204, '2026-03-25 01:43:40', 0, 0, 13, 2, 54),
(205, '2026-03-25 01:43:41', 0, 0, 14, 2, 54),
(206, '2026-03-25 01:43:42', 0, 0, 15, 2, 54),
(207, '2026-03-25 01:43:43', 0, 0, 9, 2, 54),
(208, '2026-03-25 01:43:43', 0, 0, 16, 2, 54),
(209, '2026-03-25 01:43:44', 0, 0, 17, 2, 54),
(210, '2026-03-25 01:43:45', 0, 0, 18, 2, 54),
(211, '2026-03-25 01:43:46', 0, 0, 19, 2, 54),
(212, '2026-03-25 01:43:48', 0, 0, 20, 2, 54),
(213, '2026-03-25 01:43:50', 0, 0, 21, 2, 54),
(214, '2026-03-25 01:43:50', 0, 0, 23, 2, 54),
(215, '2026-03-25 01:43:51', 0, 0, 22, 2, 54),
(216, '2026-03-25 01:43:52', 0, 0, 24, 2, 54),
(217, '2026-03-25 01:43:53', 0, 0, 25, 2, 54),
(218, '2026-03-25 01:43:54', 0, 0, 26, 2, 54),
(219, '2026-03-25 01:43:55', 0, 0, 27, 2, 54),
(220, '2026-03-25 01:43:56', 0, 0, 28, 2, 54),
(221, '2026-03-25 01:43:57', 0, 0, 29, 2, 54),
(222, '2026-03-25 01:43:58', 0, 0, 30, 2, 54),
(223, '2026-03-25 16:29:59', 0, 4, 1, 1, 55),
(224, '2026-03-25 16:30:00', 0, 10, 2, 1, 55),
(225, '2026-03-25 16:30:01', 0, 1, 3, 1, 55),
(226, '2026-03-25 16:30:02', 0, 3, 4, 1, 55),
(227, '2026-03-25 16:30:03', 0, 5, 5, 1, 55),
(228, '2026-03-25 16:30:04', 0, 3, 6, 1, 55),
(229, '2026-03-25 16:30:05', 0, 3, 7, 1, 55),
(230, '2026-03-25 16:30:06', 0, 10, 8, 1, 55),
(231, '2026-03-25 16:30:07', 0, 9, 9, 1, 55),
(232, '2026-03-25 16:30:08', 0, 5, 10, 1, 55),
(233, '2026-03-25 16:30:09', 0, 7, 11, 1, 55),
(234, '2026-03-25 16:30:10', 0, 5, 12, 1, 55),
(235, '2026-03-25 16:30:12', 0, 6, 13, 1, 55),
(236, '2026-03-25 16:30:13', 0, 4, 14, 1, 55),
(237, '2026-03-25 16:30:14', 0, 10, 15, 1, 55),
(238, '2026-03-25 16:30:15', 0, 5, 16, 1, 55),
(239, '2026-03-25 16:30:16', 0, 4, 17, 1, 55),
(240, '2026-03-25 16:30:17', 0, 6, 18, 1, 55),
(241, '2026-03-25 16:30:18', 0, 5, 19, 1, 55),
(242, '2026-03-25 16:30:19', 0, 10, 20, 1, 55),
(243, '2026-03-25 16:30:21', 0, 4, 21, 1, 55),
(244, '2026-03-25 16:30:22', 0, 8, 22, 1, 55),
(245, '2026-03-25 16:30:23', 0, 9, 23, 1, 55),
(246, '2026-03-25 16:30:23', 0, 10, 24, 1, 55),
(247, '2026-03-25 16:30:24', 0, 8, 25, 1, 55),
(248, '2026-03-25 16:30:25', 0, 10, 26, 1, 55),
(249, '2026-03-25 16:30:26', 0, 5, 27, 1, 55),
(250, '2026-03-25 16:30:27', 0, 6, 28, 1, 55),
(251, '2026-03-25 16:30:29', 0, 5, 29, 1, 55),
(252, '2026-03-25 16:30:30', 0, 6, 30, 1, 55),
(253, '2026-03-25 16:30:32', 6, 8, 13, 1, 55),
(254, '2026-03-25 16:30:36', 8, 10, 25, 1, 55),
(255, '2026-03-25 16:30:42', 5, 7, 16, 1, 55),
(256, '2026-03-25 16:30:47', 10, 1, 24, 1, 55),
(257, '2026-03-25 16:30:51', 1, 3, 24, 1, 55),
(258, '2026-03-25 16:30:57', 4, 5, 1, 1, 55),
(259, '2026-03-25 16:31:02', 3, 2, 24, 1, 55),
(260, '2026-03-25 16:31:07', 10, 1, 26, 1, 55),
(261, '2026-03-25 16:31:12', 5, 7, 27, 1, 55),
(262, '2026-03-25 16:31:17', 7, 5, 11, 1, 55),
(263, '2026-03-25 16:31:22', 3, 2, 6, 1, 55),
(264, '2026-03-25 16:31:41', 0, 0, 1, 2, 55),
(265, '2026-03-25 16:31:42', 0, 0, 2, 2, 55),
(266, '2026-03-25 16:31:43', 0, 0, 3, 2, 55),
(267, '2026-03-25 16:31:43', 0, 0, 4, 2, 55),
(268, '2026-03-25 16:31:44', 0, 0, 5, 2, 55),
(269, '2026-03-25 16:31:45', 0, 0, 6, 2, 55),
(270, '2026-03-25 16:31:46', 0, 0, 7, 2, 55),
(271, '2026-03-25 16:31:47', 0, 0, 8, 2, 55),
(272, '2026-03-25 16:31:49', 0, 0, 9, 2, 55),
(273, '2026-03-25 16:31:49', 0, 0, 10, 2, 55),
(274, '2026-03-25 16:31:50', 0, 0, 11, 2, 55),
(275, '2026-03-25 16:31:52', 0, 0, 12, 2, 55),
(276, '2026-03-25 16:31:53', 0, 0, 13, 2, 55),
(277, '2026-03-25 16:31:53', 0, 0, 14, 2, 55),
(278, '2026-03-25 16:31:54', 0, 0, 15, 2, 55),
(279, '2026-03-25 16:31:56', 0, 0, 16, 2, 55),
(280, '2026-03-25 16:31:57', 0, 0, 18, 2, 55),
(281, '2026-03-25 16:31:58', 0, 0, 17, 2, 55),
(282, '2026-03-25 16:31:58', 0, 0, 19, 2, 55),
(283, '2026-03-25 16:32:00', 0, 0, 20, 2, 55),
(284, '2026-03-25 16:32:01', 0, 0, 21, 2, 55),
(285, '2026-03-25 16:32:03', 0, 0, 23, 2, 55),
(286, '2026-03-25 16:32:03', 0, 0, 22, 2, 55),
(287, '2026-03-25 16:32:04', 0, 0, 24, 2, 55),
(288, '2026-03-25 16:32:05', 0, 0, 25, 2, 55),
(289, '2026-03-25 16:32:06', 0, 0, 26, 2, 55),
(290, '2026-03-25 16:32:07', 0, 0, 27, 2, 55),
(291, '2026-03-25 16:32:08', 0, 0, 28, 2, 55),
(292, '2026-03-25 16:32:09', 0, 0, 29, 2, 55),
(293, '2026-03-25 16:32:10', 0, 0, 30, 2, 55),
(294, '2026-03-26 14:49:53', 0, 7, 1, 1, 56),
(295, '2026-03-26 14:49:54', 0, 1, 2, 1, 56),
(296, '2026-03-26 14:49:55', 0, 10, 3, 1, 56),
(297, '2026-03-26 14:49:56', 0, 2, 4, 1, 56),
(298, '2026-03-26 14:49:57', 0, 6, 5, 1, 56),
(299, '2026-03-26 14:49:58', 0, 5, 6, 1, 56),
(300, '2026-03-26 14:49:59', 0, 6, 7, 1, 56),
(301, '2026-03-26 14:50:00', 0, 5, 8, 1, 56),
(302, '2026-03-26 14:50:01', 0, 4, 9, 1, 56),
(303, '2026-03-26 14:50:02', 0, 1, 10, 1, 56),
(304, '2026-03-26 14:50:03', 0, 2, 11, 1, 56),
(305, '2026-03-26 14:50:04', 0, 1, 12, 1, 56),
(306, '2026-03-26 14:50:05', 0, 3, 13, 1, 56),
(307, '2026-03-26 14:50:06', 0, 7, 14, 1, 56),
(308, '2026-03-26 14:50:07', 0, 9, 15, 1, 56),
(309, '2026-03-26 14:50:08', 0, 8, 16, 1, 56),
(310, '2026-03-26 14:50:09', 0, 3, 17, 1, 56),
(311, '2026-03-26 14:50:11', 0, 10, 18, 1, 56),
(312, '2026-03-26 14:50:12', 0, 3, 19, 1, 56),
(313, '2026-03-26 14:50:13', 0, 9, 20, 1, 56),
(314, '2026-03-26 14:50:14', 0, 3, 21, 1, 56),
(315, '2026-03-26 14:50:15', 0, 7, 22, 1, 56),
(316, '2026-03-26 14:50:16', 0, 1, 23, 1, 56),
(317, '2026-03-26 14:50:17', 0, 1, 24, 1, 56),
(318, '2026-03-26 14:50:18', 0, 5, 25, 1, 56),
(319, '2026-03-26 14:50:19', 0, 2, 26, 1, 56),
(320, '2026-03-26 14:50:20', 0, 7, 27, 1, 56),
(321, '2026-03-26 14:50:21', 0, 5, 28, 1, 56),
(322, '2026-03-26 14:50:22', 0, 9, 29, 1, 56),
(323, '2026-03-26 14:50:23', 0, 5, 30, 1, 56),
(324, '2026-03-26 14:52:37', 0, 0, 1, 2, 56),
(325, '2026-03-26 14:52:37', 0, 0, 2, 2, 56),
(326, '2026-03-26 14:52:37', 0, 0, 3, 2, 56),
(327, '2026-03-26 14:52:37', 0, 0, 4, 2, 56),
(328, '2026-03-26 14:52:37', 0, 0, 5, 2, 56),
(329, '2026-03-26 14:52:37', 0, 0, 6, 2, 56),
(330, '2026-03-26 14:52:37', 0, 0, 8, 2, 56),
(331, '2026-03-26 14:52:37', 0, 0, 9, 2, 56),
(332, '2026-03-26 14:52:37', 0, 0, 7, 2, 56),
(333, '2026-03-26 14:52:37', 0, 0, 10, 2, 56),
(334, '2026-03-26 14:52:37', 0, 0, 11, 2, 56),
(335, '2026-03-26 14:52:38', 0, 0, 12, 2, 56),
(336, '2026-03-26 14:52:38', 0, 0, 13, 2, 56),
(337, '2026-03-26 14:52:38', 0, 0, 14, 2, 56),
(338, '2026-03-26 14:52:38', 0, 0, 16, 2, 56),
(339, '2026-03-26 14:52:38', 0, 0, 15, 2, 56),
(340, '2026-03-26 14:52:38', 0, 0, 17, 2, 56),
(341, '2026-03-26 14:52:41', 0, 0, 18, 2, 56),
(342, '2026-03-26 14:52:41', 0, 0, 19, 2, 56),
(343, '2026-03-26 14:52:41', 0, 0, 20, 2, 56),
(344, '2026-03-26 14:52:41', 0, 0, 21, 2, 56),
(345, '2026-03-26 14:52:41', 0, 0, 22, 2, 56),
(346, '2026-03-26 14:52:41', 0, 0, 23, 2, 56),
(347, '2026-03-26 14:52:41', 0, 0, 24, 2, 56),
(348, '2026-03-26 14:52:51', 0, 0, 25, 2, 56),
(349, '2026-03-26 14:52:51', 0, 0, 26, 2, 56),
(350, '2026-03-26 14:52:51', 0, 0, 27, 2, 56),
(351, '2026-03-26 14:52:51', 0, 0, 28, 2, 56),
(352, '2026-03-26 14:52:51', 0, 0, 29, 2, 56),
(353, '2026-03-26 14:52:51', 0, 0, 30, 2, 56),
(354, '2026-03-26 15:00:39', 0, 2, 1, 1, 57),
(355, '2026-03-26 15:00:41', 0, 6, 2, 1, 57),
(356, '2026-03-26 15:00:42', 0, 10, 3, 1, 57),
(357, '2026-03-26 15:00:43', 0, 10, 4, 1, 57),
(358, '2026-03-26 15:00:44', 0, 8, 5, 1, 57),
(359, '2026-03-26 15:00:45', 0, 8, 6, 1, 57),
(360, '2026-03-26 15:00:46', 0, 2, 7, 1, 57),
(361, '2026-03-26 15:00:47', 0, 7, 8, 1, 57),
(362, '2026-03-26 15:00:48', 0, 8, 9, 1, 57),
(363, '2026-03-26 15:00:49', 0, 3, 10, 1, 57),
(364, '2026-03-26 15:00:50', 0, 2, 11, 1, 57),
(365, '2026-03-26 15:00:51', 0, 7, 12, 1, 57),
(366, '2026-03-26 15:00:52', 0, 5, 13, 1, 57),
(367, '2026-03-26 15:00:53', 0, 4, 14, 1, 57),
(368, '2026-03-26 15:00:54', 0, 4, 15, 1, 57),
(369, '2026-03-26 15:00:56', 0, 1, 16, 1, 57),
(370, '2026-03-26 15:00:57', 0, 4, 17, 1, 57),
(371, '2026-03-26 15:00:58', 0, 6, 18, 1, 57),
(372, '2026-03-26 15:00:59', 0, 8, 19, 1, 57),
(373, '2026-03-26 15:01:00', 0, 7, 20, 1, 57),
(374, '2026-03-26 15:01:01', 0, 4, 21, 1, 57),
(375, '2026-03-26 15:01:02', 0, 7, 22, 1, 57),
(376, '2026-03-26 15:01:03', 0, 8, 23, 1, 57),
(377, '2026-03-26 15:01:04', 0, 7, 24, 1, 57),
(378, '2026-03-26 15:01:05', 0, 7, 25, 1, 57),
(379, '2026-03-26 15:01:06', 0, 7, 26, 1, 57),
(380, '2026-03-26 15:01:07', 0, 2, 27, 1, 57),
(381, '2026-03-26 15:01:08', 0, 9, 28, 1, 57),
(382, '2026-03-26 15:01:09', 0, 8, 29, 1, 57),
(383, '2026-03-26 15:01:10', 0, 6, 30, 1, 57),
(384, '2026-03-26 15:01:11', 10, 1, 3, 1, 57),
(385, '2026-03-26 15:01:17', 5, 7, 13, 1, 57),
(386, '2026-03-26 15:01:21', 7, 5, 12, 1, 57),
(387, '2026-03-26 15:01:27', 7, 5, 22, 1, 57),
(388, '2026-03-26 15:01:32', 8, 10, 23, 1, 57),
(389, '2026-03-26 15:01:37', 4, 5, 15, 1, 57),
(390, '2026-03-26 15:01:42', 7, 5, 25, 1, 57),
(391, '2026-03-26 15:01:47', 4, 5, 14, 1, 57),
(392, '2026-03-26 15:01:52', 8, 10, 9, 1, 57),
(393, '2026-03-26 15:01:57', 1, 2, 16, 1, 57),
(394, '2026-03-26 15:02:02', 8, 10, 6, 1, 57),
(395, '2026-03-26 15:02:20', 0, 0, 1, 2, 57),
(396, '2026-03-26 15:02:22', 0, 0, 2, 2, 57),
(397, '2026-03-26 15:02:23', 0, 0, 3, 2, 57),
(398, '2026-03-26 15:02:24', 0, 0, 4, 2, 57),
(399, '2026-03-26 15:02:26', 0, 0, 7, 2, 57),
(400, '2026-03-26 15:02:27', 0, 0, 6, 2, 57),
(401, '2026-03-26 15:02:27', 0, 0, 5, 2, 57),
(402, '2026-03-26 15:02:29', 0, 0, 8, 2, 57),
(403, '2026-03-26 15:02:29', 0, 0, 9, 2, 57),
(404, '2026-03-26 15:02:30', 0, 0, 10, 2, 57),
(405, '2026-03-26 15:02:32', 0, 0, 12, 2, 57),
(406, '2026-03-26 15:02:32', 0, 0, 11, 2, 57),
(407, '2026-03-26 15:02:33', 0, 0, 13, 2, 57),
(408, '2026-03-26 15:02:33', 0, 0, 14, 2, 57),
(409, '2026-03-26 15:02:35', 0, 0, 15, 2, 57),
(410, '2026-03-26 15:02:36', 0, 0, 16, 2, 57),
(411, '2026-03-26 15:02:38', 0, 0, 17, 2, 57),
(412, '2026-03-26 15:02:38', 0, 0, 18, 2, 57),
(413, '2026-03-26 15:02:39', 0, 0, 19, 2, 57),
(414, '2026-03-26 15:02:40', 0, 0, 20, 2, 57),
(415, '2026-03-26 15:02:41', 0, 0, 21, 2, 57),
(416, '2026-03-26 15:02:42', 0, 0, 22, 2, 57),
(417, '2026-03-26 15:02:43', 0, 0, 23, 2, 57),
(418, '2026-03-26 15:02:44', 0, 0, 24, 2, 57),
(419, '2026-03-26 15:02:45', 0, 0, 25, 2, 57),
(420, '2026-03-26 15:02:46', 0, 0, 26, 2, 57),
(421, '2026-03-26 15:02:47', 0, 0, 27, 2, 57),
(422, '2026-03-26 15:02:48', 0, 0, 28, 2, 57),
(423, '2026-03-26 15:02:49', 0, 0, 29, 2, 57),
(424, '2026-03-26 15:02:51', 0, 0, 30, 2, 57),
(425, '2026-03-26 15:19:59', 0, 9, 1, 1, 58),
(426, '2026-03-26 15:20:00', 0, 9, 2, 1, 58),
(427, '2026-03-26 15:20:01', 0, 3, 3, 1, 58),
(428, '2026-03-26 15:20:02', 0, 6, 4, 1, 58),
(429, '2026-03-26 15:20:03', 0, 5, 5, 1, 58),
(430, '2026-03-26 15:20:04', 0, 7, 6, 1, 58),
(431, '2026-03-26 15:20:05', 0, 5, 7, 1, 58),
(432, '2026-03-26 15:20:07', 0, 5, 8, 1, 58),
(433, '2026-03-26 15:20:08', 0, 7, 9, 1, 58),
(434, '2026-03-26 15:20:09', 0, 3, 10, 1, 58),
(435, '2026-03-26 15:20:10', 0, 5, 11, 1, 58),
(436, '2026-03-26 15:20:11', 0, 5, 12, 1, 58),
(437, '2026-03-26 15:20:12', 0, 5, 13, 1, 58),
(438, '2026-03-26 15:20:13', 0, 1, 14, 1, 58),
(439, '2026-03-26 15:20:14', 0, 3, 15, 1, 58),
(440, '2026-03-26 15:20:15', 0, 2, 16, 1, 58),
(441, '2026-03-26 15:20:16', 0, 8, 17, 1, 58),
(442, '2026-03-26 15:20:17', 0, 2, 18, 1, 58),
(443, '2026-03-26 15:20:18', 0, 4, 19, 1, 58),
(444, '2026-03-26 15:20:19', 0, 9, 20, 1, 58),
(445, '2026-03-26 15:20:21', 0, 5, 21, 1, 58),
(446, '2026-03-26 15:20:22', 0, 8, 22, 1, 58),
(447, '2026-03-26 15:20:23', 0, 10, 23, 1, 58),
(448, '2026-03-26 15:20:24', 0, 2, 24, 1, 58),
(449, '2026-03-26 15:20:25', 0, 5, 25, 1, 58),
(450, '2026-03-26 15:20:26', 0, 9, 26, 1, 58),
(451, '2026-03-26 15:20:27', 0, 2, 27, 1, 58),
(452, '2026-03-26 15:20:28', 0, 1, 28, 1, 58),
(453, '2026-03-26 15:20:29', 0, 9, 29, 1, 58),
(454, '2026-03-26 15:20:30', 0, 5, 30, 1, 58),
(455, '2026-03-26 15:20:31', 5, 7, 12, 1, 58),
(456, '2026-03-26 15:20:33', 3, 2, 3, 1, 58),
(457, '2026-03-26 15:20:35', 9, 7, 20, 1, 58),
(458, '2026-03-26 15:20:37', 6, 8, 4, 1, 58),
(459, '2026-03-26 15:20:39', 2, 5, 16, 1, 58),
(460, '2026-03-26 15:20:41', 5, 3, 30, 1, 58),
(461, '2026-03-26 15:20:44', 2, 5, 3, 1, 58),
(462, '2026-03-26 15:20:46', 7, 5, 20, 1, 58),
(463, '2026-03-26 15:20:47', 5, 3, 16, 1, 58),
(464, '2026-03-26 15:20:49', 7, 5, 6, 1, 58),
(465, '2026-03-26 15:20:52', 9, 7, 1, 1, 58),
(466, '2026-03-26 15:20:54', 8, 10, 22, 1, 58),
(467, '2026-03-26 15:20:56', 8, 10, 17, 1, 58),
(468, '2026-03-26 15:20:58', 5, 7, 20, 1, 58),
(469, '2026-03-26 15:21:00', 5, 7, 11, 1, 58),
(470, '2026-03-26 15:21:02', 2, 5, 18, 1, 58),
(471, '2026-03-26 15:21:04', 5, 7, 13, 1, 58),
(472, '2026-03-26 15:21:06', 9, 7, 26, 1, 58),
(473, '2026-03-26 15:21:09', 9, 7, 2, 1, 58),
(474, '2026-03-26 15:21:10', 5, 7, 21, 1, 58),
(475, '2026-03-26 15:21:12', 7, 5, 2, 1, 58),
(476, '2026-03-26 15:21:17', 10, 1, 23, 1, 58),
(477, '2026-03-26 15:21:19', 7, 5, 20, 1, 58),
(478, '2026-03-26 15:21:21', 2, 5, 27, 1, 58),
(479, '2026-03-26 15:21:23', 7, 5, 11, 1, 58),
(480, '2026-03-26 15:21:40', 0, 0, 1, 2, 58),
(481, '2026-03-26 15:21:42', 0, 0, 3, 2, 58),
(482, '2026-03-26 15:21:43', 0, 0, 4, 2, 58),
(483, '2026-03-26 15:21:43', 0, 0, 2, 2, 58),
(484, '2026-03-26 15:21:44', 0, 0, 5, 2, 58),
(485, '2026-03-26 15:21:45', 0, 0, 6, 2, 58),
(486, '2026-03-26 15:21:46', 0, 0, 7, 2, 58),
(487, '2026-03-26 15:21:47', 0, 0, 8, 2, 58),
(488, '2026-03-26 15:21:48', 0, 0, 9, 2, 58),
(489, '2026-03-26 15:21:50', 0, 0, 10, 2, 58),
(490, '2026-03-26 15:21:51', 0, 0, 11, 2, 58),
(491, '2026-03-26 15:21:52', 0, 0, 13, 2, 58),
(492, '2026-03-26 15:21:52', 0, 0, 12, 2, 58),
(493, '2026-03-26 15:21:53', 0, 0, 14, 2, 58),
(494, '2026-03-26 15:21:56', 0, 0, 15, 2, 58),
(495, '2026-03-26 15:21:56', 0, 0, 16, 2, 58),
(496, '2026-03-26 15:21:57', 0, 0, 17, 2, 58),
(497, '2026-03-26 15:21:57', 0, 0, 18, 2, 58),
(498, '2026-03-26 15:21:58', 0, 0, 19, 2, 58),
(499, '2026-03-26 15:22:00', 0, 0, 20, 2, 58),
(500, '2026-03-26 15:22:00', 0, 0, 21, 2, 58),
(501, '2026-03-26 15:22:02', 0, 0, 22, 2, 58),
(502, '2026-03-26 15:22:03', 0, 0, 23, 2, 58),
(503, '2026-03-26 15:22:04', 0, 0, 24, 2, 58),
(504, '2026-03-26 15:22:05', 0, 0, 25, 2, 58),
(505, '2026-03-26 15:22:06', 0, 0, 26, 2, 58),
(506, '2026-03-26 15:22:07', 0, 0, 27, 2, 58),
(507, '2026-03-26 15:22:08', 0, 0, 28, 2, 58),
(508, '2026-03-26 15:22:09', 0, 0, 29, 2, 58),
(509, '2026-03-26 15:22:10', 0, 0, 30, 2, 58);

--
-- 触发器 `MedicoesPassagens`
--
DELIMITER $$
CREATE TRIGGER `before_insert_medicoes_passagens` BEFORE INSERT ON `MedicoesPassagens` FOR EACH ROW BEGIN
    DECLARE v_corridor_exists INT DEFAULT 0;
    DECLARE v_corridor_active TINYINT DEFAULT 0;
    DECLARE v_sim_estado VARCHAR(20) DEFAULT NULL;
    DECLARE v_marsami_exists INT DEFAULT 0;
    DECLARE v_current_room INT DEFAULT NULL;

    IF NEW.IDSimulacao IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: simulation is NULL';
    END IF;

    SELECT Estado
      INTO v_sim_estado
      FROM Simulacao
     WHERE IDSimulacao = NEW.IDSimulacao
     LIMIT 1;

    IF v_sim_estado IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: simulation does not exist';
    END IF;

    IF v_sim_estado NOT IN ('ACorrer', 'Blocked') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: simulation is not accepting movement events';
    END IF;

    IF NEW.Marsami IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: Marsami is NULL';
    END IF;

    IF NEW.Status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: Status is NULL';
    END IF;

    IF NEW.Status NOT IN (0, 1, 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: Status must be 0, 1 or 2';
    END IF;

    IF NEW.SalaOrigem IS NULL OR NEW.SalaDestino IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: RoomOrigin/RoomDestiny is NULL';
    END IF;

    IF NEW.SalaOrigem < 0 OR NEW.SalaDestino < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: RoomOrigin/RoomDestiny cannot be negative';
    END IF;

    IF NEW.SalaOrigem = 0 AND NEW.SalaDestino = 0 AND NEW.Status NOT IN (0, 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: (0,0) only allowed with status 0 or 2';
    END IF;

    IF (NEW.SalaOrigem > 0 OR NEW.SalaDestino > 0) AND NEW.Status <> 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: room movement requires status 1';
    END IF;

    IF NEW.Status = 1 AND NEW.SalaDestino = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: status 1 cannot have destination 0';
    END IF;

    IF v_sim_estado = 'Blocked'
       AND NOT (NEW.SalaOrigem = 0 AND NEW.SalaDestino = 0 AND NEW.Status = 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)';
    END IF;

    SELECT COUNT(*)
      INTO v_marsami_exists
      FROM Marsami
     WHERE IDSimulacao = NEW.IDSimulacao
       AND IDMarsami = NEW.Marsami;

    IF v_marsami_exists = 0 THEN
        IF NOT (NEW.SalaOrigem = 0 AND NEW.SalaDestino > 0 AND NEW.Status = 1) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Movement invalid: first event must be initial placement (origin=0, destiny>0, status=1)';
        END IF;
    ELSE
        SELECT SalaAtual
          INTO v_current_room
          FROM Marsami
         WHERE IDSimulacao = NEW.IDSimulacao
           AND IDMarsami = NEW.Marsami
         LIMIT 1;

        IF NEW.SalaOrigem = 0 AND NEW.SalaDestino = 0 THEN
            IF NEW.Status NOT IN (0, 2) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Movement invalid: fatigue/inactive event must use status 0 or 2';
            END IF;
        ELSE
            IF NEW.SalaOrigem <> v_current_room THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Movement invalid: RoomOrigin does not match Marsami current room';
            END IF;
        END IF;
    END IF;

    IF NEW.SalaOrigem > 0 AND NEW.SalaDestino > 0 THEN
        SELECT COUNT(*), COALESCE(MAX(Active), 0)
          INTO v_corridor_exists, v_corridor_active
          FROM Corridor
         WHERE RoomOrigin = NEW.SalaOrigem
           AND RoomDestiny = NEW.SalaDestino;

        IF v_corridor_exists = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Movement invalid: corridor does not exist';
        END IF;

        IF v_corridor_active <> 1 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Movement invalid: corridor is not active';
        END IF;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- 表的结构 `Mensagens`
--

CREATE TABLE `Mensagens` (
  `ID` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `Sensor` varchar(50) DEFAULT NULL,
  `Leitura` decimal(10,2) DEFAULT NULL,
  `TipoAlerta` varchar(50) NOT NULL,
  `Msg` varchar(100) DEFAULT NULL,
  `HoraEscrita` timestamp NOT NULL DEFAULT current_timestamp(),
  `IDSimulacao` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Mensagens`
--

INSERT INTO `Mensagens` (`ID`, `Hora`, `Sensor`, `Leitura`, `TipoAlerta`, `Msg`, `HoraEscrita`, `IDSimulacao`) VALUES
(1, '2026-03-26 15:01:05', 'movement', 6.00, 'ALERTA_SALA_CHEIA', 'Sala 7 atingiu ocupacao maxima: 6', '2026-03-26 15:01:05', 57),
(2, '2026-03-26 15:01:23', 'sound', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-26 15:01:23', 57),
(3, '2026-03-26 15:01:26', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:26', 57),
(4, '2026-03-26 15:01:27', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:27', 57),
(5, '2026-03-26 15:01:28', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:28', 57),
(6, '2026-03-26 15:01:30', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:30', 57),
(7, '2026-03-26 15:01:31', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:31', 57),
(8, '2026-03-26 15:01:32', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:32', 57),
(9, '2026-03-26 15:01:33', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:33', 57),
(10, '2026-03-26 15:01:33', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:33', 57),
(11, '2026-03-26 15:01:34', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:34', 57),
(12, '2026-03-26 15:01:35', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:35', 57),
(13, '2026-03-26 15:01:37', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:01:37', 57),
(14, '2026-03-26 15:01:37', 'TEMPERATURE', 19.24, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.24 | median=16.0800 | mad=0.4900 | robust_z=4.3498', '2026-03-26 15:01:38', 57),
(15, '2026-03-26 15:01:38', 'TEMPERATURE', 19.43, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.43 | median=16.1600 | mad=0.5650 | robust_z=3.9037', '2026-03-26 15:01:39', 57),
(16, '2026-03-26 15:01:39', 'TEMPERATURE', 19.62, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.62 | median=16.2400 | mad=0.6300 | robust_z=3.6187', '2026-03-26 15:01:40', 57),
(17, '2026-03-26 15:01:40', 'TEMPERATURE', 19.82, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.82 | median=16.4100 | mad=0.6400 | robust_z=3.5938', '2026-03-26 15:01:41', 57),
(18, '2026-03-26 15:01:41', 'TEMPERATURE', 20.02, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=20.02 | median=16.5700 | mad=0.6500 | robust_z=3.5800', '2026-03-26 15:01:42', 57),
(19, '2026-03-26 15:01:41', 'TEMPERATURE', 20.02, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-26 15:01:42', 57),
(20, '2026-03-26 15:01:46', 'temperature', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-26 15:01:46', 57),
(21, '2026-03-26 15:01:46', 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-26 15:01:46', 57),
(22, '2026-03-26 15:01:47', 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-26 15:01:47', 57),
(23, '2026-03-26 15:01:48', 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-26 15:01:48', 57),
(24, '2026-03-26 15:01:53', 'SOUND', 22.08, 'ALERTA_SOM', 'High sound alert', '2026-03-26 15:01:53', 57),
(25, '2026-03-26 15:01:58', 'TEMPERATURE', 23.47, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-26 15:01:59', 57),
(26, '2026-03-26 15:02:05', 'SOUND', 27.45, 'BLOQUEIO_SOM', 'Maximum sound reached - close all doors', '2026-03-26 15:02:05', 57),
(27, '2026-03-26 15:02:07', 'movement', NULL, 'DADO_INVALIDO', 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)', '2026-03-26 15:02:07', 57),
(28, '2026-03-26 15:20:12', 'movement', 6.00, 'ALERTA_SALA_CHEIA', 'Sala 5 atingiu ocupacao maxima: 6', '2026-03-26 15:20:12', 58),
(29, '2026-03-26 15:20:30', 'movement', 9.00, 'ALERTA_SALA_CHEIA', 'Sala 5 atingiu ocupacao maxima: 9', '2026-03-26 15:20:30', 58),
(30, '2026-03-26 15:20:42', 'sound', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-26 15:20:42', 58),
(31, '2026-03-26 15:20:46', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:46', 58),
(32, '2026-03-26 15:20:47', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:47', 58),
(33, '2026-03-26 15:20:48', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:48', 58),
(34, '2026-03-26 15:20:49', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:49', 58),
(35, '2026-03-26 15:20:49', 'movement', 10.00, 'ALERTA_SALA_CHEIA', 'Sala 5 atingiu ocupacao maxima: 10', '2026-03-26 15:20:49', 58),
(36, '2026-03-26 15:20:50', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:50', 58),
(37, '2026-03-26 15:20:51', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:51', 58),
(38, '2026-03-26 15:20:52', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:52', 58),
(39, '2026-03-26 15:20:53', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:53', 58),
(40, '2026-03-26 15:20:54', 'movement', NULL, 'DADO_INVALIDO', 'Movement invalid: RoomOrigin does not match Marsami current room', '2026-03-26 15:20:54', 58),
(41, '2026-03-26 15:20:54', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:54', 58),
(42, '2026-03-26 15:20:55', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:55', 58),
(43, '2026-03-26 15:20:56', 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-26 15:20:56', 58),
(44, '2026-03-26 15:20:57', 'TEMPERATURE', 19.24, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.24 | median=16.0800 | mad=0.4900 | robust_z=4.3498', '2026-03-26 15:20:57', 58),
(45, '2026-03-26 15:20:58', 'TEMPERATURE', 19.43, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.43 | median=16.1600 | mad=0.5650 | robust_z=3.9037', '2026-03-26 15:20:58', 58),
(46, '2026-03-26 15:20:59', 'TEMPERATURE', 19.62, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.62 | median=16.2400 | mad=0.6300 | robust_z=3.6187', '2026-03-26 15:20:59', 58),
(47, '2026-03-26 15:21:00', 'TEMPERATURE', 19.82, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.82 | median=16.4100 | mad=0.6400 | robust_z=3.5938', '2026-03-26 15:21:00', 58),
(48, '2026-03-26 15:21:01', 'TEMPERATURE', 20.02, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=20.02 | median=16.5700 | mad=0.6500 | robust_z=3.5800', '2026-03-26 15:21:01', 58),
(49, '2026-03-26 15:21:01', 'TEMPERATURE', 20.02, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-26 15:21:01', 58),
(50, '2026-03-26 15:21:06', 'temperature', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-26 15:21:06', 58),
(51, '2026-03-26 15:21:06', 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-26 15:21:06', 58),
(52, '2026-03-26 15:21:06', 'movement', 7.00, 'ALERTA_SALA_CHEIA', 'Sala 7 atingiu ocupacao maxima: 7', '2026-03-26 15:21:06', 58),
(53, '2026-03-26 15:21:07', 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-26 15:21:07', 58),
(54, '2026-03-26 15:21:08', 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-26 15:21:08', 58),
(55, '2026-03-26 15:21:13', 'SOUND', 22.08, 'ALERTA_SOM', 'High sound alert', '2026-03-26 15:21:13', 58),
(56, '2026-03-26 15:21:15', 'movement', NULL, 'DADO_INVALIDO', 'Movement invalid: RoomOrigin does not match Marsami current room', '2026-03-26 15:21:15', 58),
(57, '2026-03-26 15:21:18', 'TEMPERATURE', 23.47, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-26 15:21:18', 58),
(58, '2026-03-26 15:21:23', 'movement', 11.00, 'ALERTA_SALA_CHEIA', 'Sala 5 atingiu ocupacao maxima: 11', '2026-03-26 15:21:23', 58),
(59, '2026-03-26 15:21:24', 'SOUND', 27.45, 'BLOQUEIO_SOM', 'Maximum sound reached - close all doors', '2026-03-26 15:21:25', 58),
(60, '2026-03-26 15:22:10', 'temperature', NULL, 'DADO_INVALIDO', 'A simulacao 58 ja foi terminada', '2026-03-26 15:22:10', 58);

-- --------------------------------------------------------

--
-- 表的结构 `OcupacaoLabirinto`
--

CREATE TABLE `OcupacaoLabirinto` (
  `IDSimulacao` int(11) NOT NULL,
  `NumeroOdds` int(11) NOT NULL DEFAULT 0,
  `NumeroEvens` int(11) NOT NULL DEFAULT 0,
  `Sala` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `OcupacaoLabirinto`
--

INSERT INTO `OcupacaoLabirinto` (`IDSimulacao`, `NumeroOdds`, `NumeroEvens`, `Sala`) VALUES
(52, 3, 4, 1),
(52, 1, 0, 2),
(52, 1, 3, 3),
(52, 0, 1, 4),
(52, 4, 2, 5),
(52, 1, 1, 6),
(52, 2, 1, 7),
(52, 2, 1, 8),
(52, 0, 0, 9),
(52, 1, 2, 10),
(53, 0, 1, 1),
(53, 2, 2, 2),
(53, 0, 2, 3),
(53, 3, 0, 4),
(53, 4, 5, 5),
(53, 1, 2, 6),
(53, 3, 1, 7),
(53, 1, 0, 8),
(53, 1, 1, 9),
(53, 0, 1, 10),
(54, 2, 1, 1),
(54, 1, 3, 2),
(54, 1, 2, 3),
(54, 1, 0, 4),
(54, 1, 3, 5),
(54, 0, 4, 7),
(54, 3, 1, 8),
(54, 2, 1, 9),
(54, 4, 0, 10),
(55, 1, 1, 1),
(55, 0, 2, 2),
(55, 1, 1, 3),
(55, 2, 1, 4),
(55, 5, 2, 5),
(55, 0, 3, 6),
(55, 1, 1, 7),
(55, 1, 1, 8),
(55, 2, 0, 9),
(55, 2, 3, 10),
(56, 1, 4, 1),
(56, 1, 2, 2),
(56, 4, 0, 3),
(56, 1, 0, 4),
(56, 1, 4, 5),
(56, 2, 0, 6),
(56, 2, 2, 7),
(56, 0, 1, 8),
(56, 2, 1, 9),
(56, 1, 1, 10),
(57, 1, 0, 1),
(57, 4, 1, 2),
(57, 0, 1, 3),
(57, 2, 0, 4),
(57, 2, 3, 5),
(57, 0, 3, 6),
(57, 1, 4, 7),
(57, 3, 0, 8),
(57, 0, 1, 9),
(57, 2, 2, 10),
(58, 1, 2, 1),
(58, 0, 1, 2),
(58, 1, 3, 3),
(58, 1, 0, 4),
(58, 6, 5, 5),
(58, 0, 0, 6),
(58, 4, 2, 7),
(58, 0, 1, 8),
(58, 1, 0, 9),
(58, 1, 1, 10);

-- --------------------------------------------------------

--
-- 表的结构 `ScoreSala`
--

CREATE TABLE `ScoreSala` (
  `IDScore` int(11) NOT NULL,
  `IDSimulacao` int(11) DEFAULT NULL,
  `IDUtilizador` int(11) NOT NULL,
  `Sala` int(11) DEFAULT NULL,
  `NumTentativa` int(11) NOT NULL,
  `Hora` timestamp NOT NULL DEFAULT current_timestamp(),
  `Resultado` enum('SUCESSO','FALHA') NOT NULL,
  `Pontos` decimal(4,2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `Simulacao`
--

CREATE TABLE `Simulacao` (
  `IDSimulacao` int(11) NOT NULL,
  `IDUtilizadorCriador` int(11) NOT NULL,
  `Descricao` text DEFAULT NULL,
  `DataHorainicio` timestamp NULL DEFAULT NULL,
  `DataHoraFim` timestamp NULL DEFAULT NULL,
  `Estado` enum('PorIniciar','ACorrer','Blocked','Terminada') NOT NULL DEFAULT 'PorIniciar'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Simulacao`
--

INSERT INTO `Simulacao` (`IDSimulacao`, `IDUtilizadorCriador`, `Descricao`, `DataHorainicio`, `DataHoraFim`, `Estado`) VALUES
(52, 71, NULL, '2026-03-25 01:04:43', '2026-03-25 01:08:55', 'Terminada'),
(53, 1, NULL, '2026-03-25 01:26:03', '2026-03-25 01:29:21', 'Terminada'),
(54, 1, NULL, '2026-03-25 01:26:03', '2026-03-25 01:43:58', 'Terminada'),
(55, 1, NULL, NULL, '2026-03-25 16:32:10', 'Terminada'),
(56, 1, NULL, NULL, '2026-03-26 14:52:51', 'Terminada'),
(57, 1, NULL, NULL, '2026-03-26 15:02:51', 'Terminada'),
(58, 1, NULL, NULL, '2026-03-26 15:22:10', 'Terminada');

--
-- 触发器 `Simulacao`
--
DELIMITER $$
CREATE TRIGGER `before_start_simulacao` BEFORE UPDATE ON `Simulacao` FOR EACH ROW BEGIN
    IF NEW.Estado = 'ACorrer' AND OLD.Estado <> 'ACorrer' THEN

        IF OLD.Estado <> 'PorIniciar' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas simulacoes em estado PorIniciar podem passar para ACorrer';
        END IF;

        IF EXISTS (
        SELECT 1
        FROM Simulacao
        WHERE IDSimulacao <> NEW.IDSimulacao
         AND Estado IN ('ACorrer', 'Blocked')
         ) THEN
          SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'Ja existe outra simulacao em execucao local';
        END IF;
        
        UPDATE Corridor
          SET Active = 1;

    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- 表的结构 `Som`
--

CREATE TABLE `Som` (
  `IDSom` int(11) NOT NULL,
  `Hora` timestamp NOT NULL DEFAULT current_timestamp(),
  `Som` double NOT NULL,
  `IDSimulacao` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Som`
--

INSERT INTO `Som` (`IDSom`, `Hora`, `Som`, `IDSimulacao`) VALUES
(1, '2026-03-25 01:07:16', 10.2, 52),
(2, '2026-03-25 01:07:18', 10.4, 52),
(3, '2026-03-25 01:07:19', 10.61, 52),
(4, '2026-03-25 01:07:20', 10.82, 52),
(5, '2026-03-25 01:07:21', 11.04, 52),
(6, '2026-03-25 01:07:22', 11.26, 52),
(7, '2026-03-25 01:07:23', 11.49, 52),
(8, '2026-03-25 01:07:24', 11.72, 52),
(9, '2026-03-25 01:07:25', 11.95, 52),
(10, '2026-03-25 01:07:26', 12.19, 52),
(11, '2026-03-25 01:07:29', 12.68, 52),
(12, '2026-03-25 01:07:30', 12.94, 52),
(13, '2026-03-25 01:07:31', 13.19, 52),
(14, '2026-03-25 01:07:32', 13.46, 52),
(15, '2026-03-25 01:07:33', 13.73, 52),
(16, '2026-03-25 01:07:34', 14, 52),
(17, '2026-03-25 01:07:35', 14.28, 52),
(18, '2026-03-25 01:07:36', 14.57, 52),
(19, '2026-03-25 01:07:37', 14.86, 52),
(20, '2026-03-25 01:07:38', 15.16, 52),
(21, '2026-03-25 01:07:40', 15.46, 52),
(22, '2026-03-25 01:07:41', 15.77, 52),
(23, '2026-03-25 01:07:42', 16.08, 52),
(24, '2026-03-25 01:07:43', 16.41, 52),
(25, '2026-03-25 01:07:44', 16.73, 52),
(26, '2026-03-25 01:07:45', 17.07, 52),
(27, '2026-03-25 01:07:46', 17.41, 52),
(28, '2026-03-25 01:07:47', 17.76, 52),
(29, '2026-03-25 01:07:48', 18.11, 52),
(30, '2026-03-25 01:07:50', 18.48, 52),
(31, '2026-03-25 01:07:51', 18.85, 52),
(32, '2026-03-25 01:07:55', 20.4, 52),
(33, '2026-03-25 01:07:56', 20.81, 52),
(34, '2026-03-25 01:07:57', 21.22, 52),
(35, '2026-03-25 01:07:58', 21.65, 52),
(36, '2026-03-25 01:07:59', 22.08, 52),
(37, '2026-03-25 01:08:00', 22.52, 52),
(38, '2026-03-25 01:08:02', 22.97, 52),
(39, '2026-03-25 01:08:03', 23.43, 52),
(40, '2026-03-25 01:08:04', 23.9, 52),
(41, '2026-03-25 01:08:05', 24.38, 52),
(42, '2026-03-25 01:08:06', 24.87, 52),
(43, '2026-03-25 01:08:07', 25.36, 52),
(44, '2026-03-25 01:08:08', 25.87, 52),
(45, '2026-03-25 01:08:09', 26.39, 52),
(46, '2026-03-25 01:08:10', 26.92, 52),
(47, '2026-03-25 01:08:12', 27.45, 52),
(48, '2026-03-25 01:27:42', 10.2, 53),
(49, '2026-03-25 01:27:43', 10.4, 53),
(50, '2026-03-25 01:27:44', 10.61, 53),
(51, '2026-03-25 01:27:45', 10.82, 53),
(52, '2026-03-25 01:27:47', 11.04, 53),
(53, '2026-03-25 01:27:48', 11.26, 53),
(54, '2026-03-25 01:27:49', 11.49, 53),
(55, '2026-03-25 01:27:50', 11.72, 53),
(56, '2026-03-25 01:27:51', 11.95, 53),
(57, '2026-03-25 01:27:52', 12.19, 53),
(58, '2026-03-25 01:27:54', 12.68, 53),
(59, '2026-03-25 01:27:55', 12.94, 53),
(60, '2026-03-25 01:27:57', 13.19, 53),
(61, '2026-03-25 01:27:58', 13.46, 53),
(62, '2026-03-25 01:27:59', 13.73, 53),
(63, '2026-03-25 01:28:00', 14, 53),
(64, '2026-03-25 01:28:01', 14.28, 53),
(65, '2026-03-25 01:28:02', 14.57, 53),
(66, '2026-03-25 01:28:03', 14.86, 53),
(67, '2026-03-25 01:28:04', 15.16, 53),
(68, '2026-03-25 01:28:05', 15.46, 53),
(69, '2026-03-25 01:28:06', 15.77, 53),
(70, '2026-03-25 01:28:08', 16.08, 53),
(71, '2026-03-25 01:28:09', 16.41, 53),
(72, '2026-03-25 01:28:10', 16.73, 53),
(73, '2026-03-25 01:28:11', 17.07, 53),
(74, '2026-03-25 01:28:12', 17.41, 53),
(75, '2026-03-25 01:28:13', 17.76, 53),
(76, '2026-03-25 01:28:14', 18.11, 53),
(77, '2026-03-25 01:28:15', 18.48, 53),
(78, '2026-03-25 01:28:16', 18.85, 53),
(79, '2026-03-25 01:28:21', 20.4, 53),
(80, '2026-03-25 01:28:22', 20.81, 53),
(81, '2026-03-25 01:28:23', 21.22, 53),
(82, '2026-03-25 01:28:24', 21.65, 53),
(83, '2026-03-25 01:28:25', 22.08, 53),
(84, '2026-03-25 01:28:26', 22.52, 53),
(85, '2026-03-25 01:28:28', 22.97, 53),
(86, '2026-03-25 01:28:29', 23.43, 53),
(87, '2026-03-25 01:28:30', 23.9, 53),
(88, '2026-03-25 01:28:31', 24.38, 53),
(89, '2026-03-25 01:28:32', 24.87, 53),
(90, '2026-03-25 01:28:33', 25.36, 53),
(91, '2026-03-25 01:28:34', 25.87, 53),
(92, '2026-03-25 01:28:35', 26.39, 53),
(93, '2026-03-25 01:28:36', 26.92, 53),
(94, '2026-03-25 01:28:38', 27.45, 53),
(95, '2026-03-25 01:42:20', 10.2, 54),
(96, '2026-03-25 01:42:21', 10.4, 54),
(97, '2026-03-25 01:42:22', 10.61, 54),
(98, '2026-03-25 01:42:23', 10.82, 54),
(99, '2026-03-25 01:42:24', 11.04, 54),
(100, '2026-03-25 01:42:25', 11.26, 54),
(101, '2026-03-25 01:42:26', 11.49, 54),
(102, '2026-03-25 01:42:27', 11.72, 54),
(103, '2026-03-25 01:42:28', 11.95, 54),
(104, '2026-03-25 01:42:29', 12.19, 54),
(105, '2026-03-25 01:42:32', 12.68, 54),
(106, '2026-03-25 01:42:33', 12.94, 54),
(107, '2026-03-25 01:42:34', 13.19, 54),
(108, '2026-03-25 01:42:35', 13.46, 54),
(109, '2026-03-25 01:42:36', 13.73, 54),
(110, '2026-03-25 01:42:37', 14, 54),
(111, '2026-03-25 01:42:38', 14.28, 54),
(112, '2026-03-25 01:42:40', 14.57, 54),
(113, '2026-03-25 01:42:41', 14.86, 54),
(114, '2026-03-25 01:42:42', 15.16, 54),
(115, '2026-03-25 01:42:43', 15.46, 54),
(116, '2026-03-25 01:42:44', 15.77, 54),
(117, '2026-03-25 01:42:45', 16.08, 54),
(118, '2026-03-25 01:42:46', 16.41, 54),
(119, '2026-03-25 01:42:47', 16.73, 54),
(120, '2026-03-25 01:42:48', 17.07, 54),
(121, '2026-03-25 01:42:50', 17.41, 54),
(122, '2026-03-25 01:42:51', 17.76, 54),
(123, '2026-03-25 01:42:52', 18.11, 54),
(124, '2026-03-25 01:42:53', 18.48, 54),
(125, '2026-03-25 01:42:54', 18.85, 54),
(126, '2026-03-25 01:42:58', 20.4, 54),
(127, '2026-03-25 01:42:59', 20.81, 54),
(128, '2026-03-25 01:43:01', 21.22, 54),
(129, '2026-03-25 01:43:02', 21.65, 54),
(130, '2026-03-25 01:43:03', 22.08, 54),
(131, '2026-03-25 01:43:04', 22.52, 54),
(132, '2026-03-25 01:43:05', 22.97, 54),
(133, '2026-03-25 01:43:06', 23.43, 54),
(134, '2026-03-25 01:43:07', 23.9, 54),
(135, '2026-03-25 01:43:08', 24.38, 54),
(136, '2026-03-25 01:43:10', 24.87, 54),
(137, '2026-03-25 01:43:11', 25.36, 54),
(138, '2026-03-25 01:43:12', 25.87, 54),
(139, '2026-03-25 01:43:13', 26.39, 54),
(140, '2026-03-25 01:43:14', 26.92, 54),
(141, '2026-03-25 01:43:15', 27.45, 54),
(142, '2026-03-25 16:30:31', 10.2, 55),
(143, '2026-03-25 16:30:33', 10.4, 55),
(144, '2026-03-25 16:30:34', 10.61, 55),
(145, '2026-03-25 16:30:35', 10.82, 55),
(146, '2026-03-25 16:30:36', 11.04, 55),
(147, '2026-03-25 16:30:37', 11.26, 55),
(148, '2026-03-25 16:30:38', 11.49, 55),
(149, '2026-03-25 16:30:39', 11.72, 55),
(150, '2026-03-25 16:30:40', 11.95, 55),
(151, '2026-03-25 16:30:41', 12.19, 55),
(152, '2026-03-25 16:30:43', 12.68, 55),
(153, '2026-03-25 16:30:44', 12.94, 55),
(154, '2026-03-25 16:30:45', 13.19, 55),
(155, '2026-03-25 16:30:47', 13.46, 55),
(156, '2026-03-25 16:30:48', 13.73, 55),
(157, '2026-03-25 16:30:49', 14, 55),
(158, '2026-03-25 16:30:50', 14.28, 55),
(159, '2026-03-25 16:30:51', 14.57, 55),
(160, '2026-03-25 16:30:52', 14.86, 55),
(161, '2026-03-25 16:30:53', 15.16, 55),
(162, '2026-03-25 16:30:54', 15.46, 55),
(163, '2026-03-25 16:30:55', 15.77, 55),
(164, '2026-03-25 16:30:56', 16.08, 55),
(165, '2026-03-25 16:30:57', 16.41, 55),
(166, '2026-03-25 16:30:58', 16.73, 55),
(167, '2026-03-25 16:30:59', 17.07, 55),
(168, '2026-03-25 16:31:00', 17.41, 55),
(169, '2026-03-25 16:31:02', 17.76, 55),
(170, '2026-03-25 16:31:03', 18.11, 55),
(171, '2026-03-25 16:31:04', 18.48, 55),
(172, '2026-03-25 16:31:05', 18.85, 55),
(173, '2026-03-25 16:31:09', 20.4, 55),
(174, '2026-03-25 16:31:10', 20.81, 55),
(175, '2026-03-25 16:31:11', 21.22, 55),
(176, '2026-03-25 16:31:12', 21.65, 55),
(177, '2026-03-25 16:31:13', 22.08, 55),
(178, '2026-03-25 16:31:14', 22.52, 55),
(179, '2026-03-25 16:31:15', 22.97, 55),
(180, '2026-03-25 16:31:16', 23.43, 55),
(181, '2026-03-25 16:31:17', 23.9, 55),
(182, '2026-03-25 16:31:19', 24.38, 55),
(183, '2026-03-25 16:31:20', 24.87, 55),
(184, '2026-03-25 16:31:21', 25.36, 55),
(185, '2026-03-25 16:31:22', 25.87, 55),
(186, '2026-03-25 16:31:23', 26.39, 55),
(187, '2026-03-25 16:31:24', 26.92, 55),
(188, '2026-03-25 16:31:25', 27.45, 55),
(189, '2026-03-26 14:50:25', 10.2, 56),
(190, '2026-03-26 14:50:26', 10.4, 56),
(191, '2026-03-26 14:50:27', 10.61, 56),
(192, '2026-03-26 14:50:28', 10.82, 56),
(193, '2026-03-26 14:50:29', 11.04, 56),
(194, '2026-03-26 14:50:30', 11.26, 56),
(195, '2026-03-26 14:50:31', 11.49, 56),
(196, '2026-03-26 14:50:32', 11.72, 56),
(197, '2026-03-26 14:50:33', 11.95, 56),
(198, '2026-03-26 14:50:34', 12.19, 56),
(199, '2026-03-26 14:50:36', 12.68, 56),
(200, '2026-03-26 14:50:38', 12.94, 56),
(201, '2026-03-26 14:50:39', 13.19, 56),
(202, '2026-03-26 14:50:40', 13.46, 56),
(203, '2026-03-26 14:50:41', 13.73, 56),
(204, '2026-03-26 14:50:42', 14, 56),
(205, '2026-03-26 14:50:43', 14.28, 56),
(206, '2026-03-26 14:50:44', 14.57, 56),
(207, '2026-03-26 14:50:45', 14.86, 56),
(208, '2026-03-26 14:50:46', 15.16, 56),
(209, '2026-03-26 14:50:47', 15.46, 56),
(210, '2026-03-26 14:50:48', 15.77, 56),
(211, '2026-03-26 14:50:49', 16.08, 56),
(212, '2026-03-26 14:50:50', 16.41, 56),
(213, '2026-03-26 14:50:51', 16.73, 56),
(214, '2026-03-26 14:50:52', 17.07, 56),
(215, '2026-03-26 14:50:53', 17.41, 56),
(216, '2026-03-26 14:50:54', 17.76, 56),
(217, '2026-03-26 14:50:55', 18.11, 56),
(218, '2026-03-26 14:50:56', 18.48, 56),
(219, '2026-03-26 14:50:57', 18.85, 56),
(220, '2026-03-26 14:51:02', 20.4, 56),
(221, '2026-03-26 14:51:03', 20.81, 56),
(222, '2026-03-26 14:51:04', 21.22, 56),
(223, '2026-03-26 14:51:05', 21.65, 56),
(224, '2026-03-26 14:51:06', 22.08, 56),
(225, '2026-03-26 14:51:07', 22.52, 56),
(226, '2026-03-26 14:51:08', 22.97, 56),
(227, '2026-03-26 14:51:09', 23.43, 56),
(228, '2026-03-26 14:51:10', 23.9, 56),
(229, '2026-03-26 14:51:11', 24.38, 56),
(230, '2026-03-26 14:51:12', 24.87, 56),
(231, '2026-03-26 14:51:13', 25.36, 56),
(232, '2026-03-26 14:51:14', 25.87, 56),
(233, '2026-03-26 14:51:16', 26.39, 56),
(234, '2026-03-26 14:51:17', 26.92, 56),
(235, '2026-03-26 14:51:18', 27.45, 56),
(236, '2026-03-26 15:01:12', 10.2, 57),
(237, '2026-03-26 15:01:13', 10.4, 57),
(238, '2026-03-26 15:01:14', 10.61, 57),
(239, '2026-03-26 15:01:15', 10.82, 57),
(240, '2026-03-26 15:01:16', 11.04, 57),
(241, '2026-03-26 15:01:17', 11.26, 57),
(242, '2026-03-26 15:01:18', 11.49, 57),
(243, '2026-03-26 15:01:19', 11.72, 57),
(244, '2026-03-26 15:01:20', 11.95, 57),
(245, '2026-03-26 15:01:22', 12.19, 57),
(246, '2026-03-26 15:01:24', 12.68, 57),
(247, '2026-03-26 15:01:25', 12.94, 57),
(248, '2026-03-26 15:01:26', 13.19, 57),
(249, '2026-03-26 15:01:27', 13.46, 57),
(250, '2026-03-26 15:01:28', 13.73, 57),
(251, '2026-03-26 15:01:29', 14, 57),
(252, '2026-03-26 15:01:30', 14.28, 57),
(253, '2026-03-26 15:01:31', 14.57, 57),
(254, '2026-03-26 15:01:32', 14.86, 57),
(255, '2026-03-26 15:01:33', 15.16, 57),
(256, '2026-03-26 15:01:34', 15.46, 57),
(257, '2026-03-26 15:01:35', 15.77, 57),
(258, '2026-03-26 15:01:36', 16.08, 57),
(259, '2026-03-26 15:01:37', 16.41, 57),
(260, '2026-03-26 15:01:38', 16.73, 57),
(261, '2026-03-26 15:01:39', 17.07, 57),
(262, '2026-03-26 15:01:40', 17.41, 57),
(263, '2026-03-26 15:01:42', 17.76, 57),
(264, '2026-03-26 15:01:43', 18.11, 57),
(265, '2026-03-26 15:01:44', 18.48, 57),
(266, '2026-03-26 15:01:45', 18.85, 57),
(267, '2026-03-26 15:01:49', 20.4, 57),
(268, '2026-03-26 15:01:50', 20.81, 57),
(269, '2026-03-26 15:01:51', 21.22, 57),
(270, '2026-03-26 15:01:52', 21.65, 57),
(271, '2026-03-26 15:01:53', 22.08, 57),
(272, '2026-03-26 15:01:54', 22.52, 57),
(273, '2026-03-26 15:01:55', 22.97, 57),
(274, '2026-03-26 15:01:56', 23.43, 57),
(275, '2026-03-26 15:01:57', 23.9, 57),
(276, '2026-03-26 15:01:58', 24.38, 57),
(277, '2026-03-26 15:01:59', 24.87, 57),
(278, '2026-03-26 15:02:00', 25.36, 57),
(279, '2026-03-26 15:02:01', 25.87, 57),
(280, '2026-03-26 15:02:02', 26.39, 57),
(281, '2026-03-26 15:02:04', 26.92, 57),
(282, '2026-03-26 15:02:05', 27.45, 57),
(283, '2026-03-26 15:20:32', 10.2, 58),
(284, '2026-03-26 15:20:33', 10.4, 58),
(285, '2026-03-26 15:20:34', 10.61, 58),
(286, '2026-03-26 15:20:35', 10.82, 58),
(287, '2026-03-26 15:20:36', 11.04, 58),
(288, '2026-03-26 15:20:37', 11.26, 58),
(289, '2026-03-26 15:20:38', 11.49, 58),
(290, '2026-03-26 15:20:39', 11.72, 58),
(291, '2026-03-26 15:20:40', 11.95, 58),
(292, '2026-03-26 15:20:41', 12.19, 58),
(293, '2026-03-26 15:20:43', 12.68, 58),
(294, '2026-03-26 15:20:44', 12.94, 58),
(295, '2026-03-26 15:20:45', 13.19, 58),
(296, '2026-03-26 15:20:46', 13.46, 58),
(297, '2026-03-26 15:20:47', 13.73, 58),
(298, '2026-03-26 15:20:48', 14, 58),
(299, '2026-03-26 15:20:49', 14.28, 58),
(300, '2026-03-26 15:20:51', 14.57, 58),
(301, '2026-03-26 15:20:52', 14.86, 58),
(302, '2026-03-26 15:20:53', 15.16, 58),
(303, '2026-03-26 15:20:54', 15.46, 58),
(304, '2026-03-26 15:20:55', 15.77, 58),
(305, '2026-03-26 15:20:56', 16.08, 58),
(306, '2026-03-26 15:20:57', 16.41, 58),
(307, '2026-03-26 15:20:58', 16.73, 58),
(308, '2026-03-26 15:20:59', 17.07, 58),
(309, '2026-03-26 15:21:00', 17.41, 58),
(310, '2026-03-26 15:21:01', 17.76, 58),
(311, '2026-03-26 15:21:02', 18.11, 58),
(312, '2026-03-26 15:21:03', 18.48, 58),
(313, '2026-03-26 15:21:04', 18.85, 58),
(314, '2026-03-26 15:21:09', 20.4, 58),
(315, '2026-03-26 15:21:10', 20.81, 58),
(316, '2026-03-26 15:21:11', 21.22, 58),
(317, '2026-03-26 15:21:12', 21.65, 58),
(318, '2026-03-26 15:21:13', 22.08, 58),
(319, '2026-03-26 15:21:14', 22.52, 58),
(320, '2026-03-26 15:21:15', 22.97, 58),
(321, '2026-03-26 15:21:16', 23.43, 58),
(322, '2026-03-26 15:21:17', 23.9, 58),
(323, '2026-03-26 15:21:18', 24.38, 58),
(324, '2026-03-26 15:21:19', 24.87, 58),
(325, '2026-03-26 15:21:20', 25.36, 58),
(326, '2026-03-26 15:21:21', 25.87, 58),
(327, '2026-03-26 15:21:22', 26.39, 58),
(328, '2026-03-26 15:21:23', 26.92, 58),
(329, '2026-03-26 15:21:24', 27.45, 58);

--
-- 触发器 `Som`
--
DELIMITER $$
CREATE TRIGGER `before_insert_som` BEFORE INSERT ON `Som` FOR EACH ROW BEGIN
    IF NEW.Hora IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sound event invalid: Hour is NULL';
    END IF;

    IF NEW.Som IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sound event invalid: value is NULL';
    END IF;

    IF NEW.Som < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sound event invalid: value below 0';
    END IF;

    IF NEW.Som >= 60 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sound event invalid: value >= 60';
    END IF;

    IF NEW.IDSimulacao IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sound event invalid: simulation is NULL';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- 表的结构 `Temperatura`
--

CREATE TABLE `Temperatura` (
  `IDTemperatura` int(11) NOT NULL,
  `Hora` timestamp NOT NULL DEFAULT current_timestamp(),
  `Temperatura` double NOT NULL,
  `IDSimulacao` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Temperatura`
--

INSERT INTO `Temperatura` (`IDTemperatura`, `Hora`, `Temperatura`, `IDSimulacao`) VALUES
(1, '2026-03-25 01:07:16', 15.15, 52),
(2, '2026-03-25 01:07:17', 15.3, 52),
(3, '2026-03-25 01:07:19', 15.45, 52),
(4, '2026-03-25 01:07:20', 15.61, 52),
(5, '2026-03-25 01:07:21', 15.77, 52),
(6, '2026-03-25 01:07:22', 15.92, 52),
(7, '2026-03-25 01:07:23', 16.08, 52),
(8, '2026-03-25 01:07:24', 16.24, 52),
(9, '2026-03-25 01:07:25', 16.41, 52),
(10, '2026-03-25 01:07:26', 16.57, 52),
(11, '2026-03-25 01:07:27', 16.74, 52),
(12, '2026-03-25 01:07:28', 16.9, 52),
(13, '2026-03-25 01:07:29', 17.07, 52),
(14, '2026-03-25 01:07:42', 19.24, 52),
(15, '2026-03-25 01:07:43', 19.43, 52),
(16, '2026-03-25 01:07:44', 19.62, 52),
(17, '2026-03-25 01:07:46', 19.82, 52),
(18, '2026-03-25 01:07:47', 20.02, 52),
(19, '2026-03-25 01:07:48', 20.22, 52),
(20, '2026-03-25 01:07:49', 20.42, 52),
(21, '2026-03-25 01:07:50', 20.62, 52),
(22, '2026-03-25 01:07:52', 21.04, 52),
(23, '2026-03-25 01:07:53', 21.25, 52),
(24, '2026-03-25 01:07:54', 21.46, 52),
(25, '2026-03-25 01:07:55', 21.68, 52),
(26, '2026-03-25 01:07:56', 21.89, 52),
(27, '2026-03-25 01:07:57', 22.11, 52),
(28, '2026-03-25 01:07:58', 22.33, 52),
(29, '2026-03-25 01:07:59', 22.56, 52),
(30, '2026-03-25 01:08:01', 22.78, 52),
(31, '2026-03-25 01:08:02', 23.01, 52),
(32, '2026-03-25 01:08:03', 23.24, 52),
(33, '2026-03-25 01:08:04', 23.47, 52),
(34, '2026-03-25 01:08:05', 23.71, 52),
(35, '2026-03-25 01:08:06', 23.94, 52),
(36, '2026-03-25 01:08:07', 24.18, 52),
(37, '2026-03-25 01:08:08', 24.43, 52),
(38, '2026-03-25 01:08:09', 24.67, 52),
(39, '2026-03-25 01:08:10', 24.92, 52),
(40, '2026-03-25 01:08:11', 25.17, 52),
(41, '2026-03-25 01:08:12', 25.42, 52),
(42, '2026-03-25 01:08:13', 25.67, 52),
(43, '2026-03-25 01:08:14', 25.93, 52),
(44, '2026-03-25 01:08:15', 26.19, 52),
(45, '2026-03-25 01:08:17', 26.45, 52),
(46, '2026-03-25 01:08:18', 26.71, 52),
(47, '2026-03-25 01:08:19', 26.98, 52),
(48, '2026-03-25 01:08:20', 27.25, 52),
(49, '2026-03-25 01:08:21', 27.52, 52),
(50, '2026-03-25 01:08:22', 27.8, 52),
(51, '2026-03-25 01:08:23', 28.08, 52),
(52, '2026-03-25 01:08:24', 28.36, 52),
(53, '2026-03-25 01:08:25', 28.64, 52),
(54, '2026-03-25 01:08:26', 28.93, 52),
(55, '2026-03-25 01:08:27', 29.22, 52),
(56, '2026-03-25 01:08:28', 29.51, 52),
(57, '2026-03-25 01:08:30', 29.8, 52),
(58, '2026-03-25 01:08:31', 30.1, 52),
(59, '2026-03-25 01:08:32', 30.4, 52),
(60, '2026-03-25 01:08:33', 30.71, 52),
(61, '2026-03-25 01:08:34', 31.01, 52),
(62, '2026-03-25 01:08:35', 31.32, 52),
(63, '2026-03-25 01:08:36', 31.64, 52),
(64, '2026-03-25 01:08:37', 31.95, 52),
(65, '2026-03-25 01:08:38', 32.27, 52),
(66, '2026-03-25 01:08:39', 32.6, 52),
(67, '2026-03-25 01:08:40', 32.92, 52),
(68, '2026-03-25 01:08:41', 33.25, 52),
(69, '2026-03-25 01:08:42', 33.58, 52),
(70, '2026-03-25 01:08:44', 33.92, 52),
(71, '2026-03-25 01:08:45', 34.26, 52),
(72, '2026-03-25 01:08:46', 34.6, 52),
(73, '2026-03-25 01:08:47', 34.95, 52),
(74, '2026-03-25 01:08:48', 35.3, 52),
(75, '2026-03-25 01:08:49', 35.65, 52),
(76, '2026-03-25 01:08:50', 36.01, 52),
(77, '2026-03-25 01:08:51', 36.37, 52),
(78, '2026-03-25 01:08:52', 36.73, 52),
(79, '2026-03-25 01:08:53', 37.1, 52),
(80, '2026-03-25 01:27:42', 15.15, 53),
(81, '2026-03-25 01:27:43', 15.3, 53),
(82, '2026-03-25 01:27:44', 15.45, 53),
(83, '2026-03-25 01:27:45', 15.61, 53),
(84, '2026-03-25 01:27:47', 15.77, 53),
(85, '2026-03-25 01:27:48', 15.92, 53),
(86, '2026-03-25 01:27:49', 16.08, 53),
(87, '2026-03-25 01:27:50', 16.24, 53),
(88, '2026-03-25 01:27:51', 16.41, 53),
(89, '2026-03-25 01:27:52', 16.57, 53),
(90, '2026-03-25 01:27:53', 16.74, 53),
(91, '2026-03-25 01:27:54', 16.9, 53),
(92, '2026-03-25 01:27:55', 17.07, 53),
(93, '2026-03-25 01:28:09', 19.24, 53),
(94, '2026-03-25 01:28:10', 19.43, 53),
(95, '2026-03-25 01:28:11', 19.62, 53),
(96, '2026-03-25 01:28:12', 19.82, 53),
(97, '2026-03-25 01:28:13', 20.02, 53),
(98, '2026-03-25 01:28:14', 20.22, 53),
(99, '2026-03-25 01:28:15', 20.42, 53),
(100, '2026-03-25 01:28:17', 20.62, 53),
(101, '2026-03-25 01:28:19', 21.04, 53),
(102, '2026-03-25 01:28:20', 21.25, 53),
(103, '2026-03-25 01:28:21', 21.46, 53),
(104, '2026-03-25 01:28:22', 21.68, 53),
(105, '2026-03-25 01:28:23', 21.89, 53),
(106, '2026-03-25 01:28:24', 22.11, 53),
(107, '2026-03-25 01:28:25', 22.33, 53),
(108, '2026-03-25 01:28:26', 22.56, 53),
(109, '2026-03-25 01:28:27', 22.78, 53),
(110, '2026-03-25 01:28:29', 23.01, 53),
(111, '2026-03-25 01:28:30', 23.24, 53),
(112, '2026-03-25 01:28:31', 23.47, 53),
(113, '2026-03-25 01:28:32', 23.71, 53),
(114, '2026-03-25 01:28:33', 23.94, 53),
(115, '2026-03-25 01:28:34', 24.18, 53),
(116, '2026-03-25 01:28:35', 24.43, 53),
(117, '2026-03-25 01:28:36', 24.67, 53),
(118, '2026-03-25 01:28:37', 24.92, 53),
(119, '2026-03-25 01:28:39', 25.17, 53),
(120, '2026-03-25 01:28:40', 25.42, 53),
(121, '2026-03-25 01:28:41', 25.67, 53),
(122, '2026-03-25 01:28:42', 25.93, 53),
(123, '2026-03-25 01:28:43', 26.19, 53),
(124, '2026-03-25 01:28:44', 26.45, 53),
(125, '2026-03-25 01:28:45', 26.71, 53),
(126, '2026-03-25 01:28:46', 26.98, 53),
(127, '2026-03-25 01:28:47', 27.25, 53),
(128, '2026-03-25 01:28:48', 27.52, 53),
(129, '2026-03-25 01:28:49', 27.8, 53),
(130, '2026-03-25 01:28:50', 28.08, 53),
(131, '2026-03-25 01:28:52', 28.36, 53),
(132, '2026-03-25 01:28:53', 28.64, 53),
(133, '2026-03-25 01:28:54', 28.93, 53),
(134, '2026-03-25 01:28:55', 29.22, 53),
(135, '2026-03-25 01:28:56', 29.51, 53),
(136, '2026-03-25 01:28:57', 29.8, 53),
(137, '2026-03-25 01:28:58', 30.1, 53),
(138, '2026-03-25 01:28:59', 30.4, 53),
(139, '2026-03-25 01:29:00', 30.71, 53),
(140, '2026-03-25 01:29:01', 31.01, 53),
(141, '2026-03-25 01:29:03', 31.32, 53),
(142, '2026-03-25 01:29:04', 31.64, 53),
(143, '2026-03-25 01:29:05', 31.95, 53),
(144, '2026-03-25 01:29:06', 32.27, 53),
(145, '2026-03-25 01:29:07', 32.6, 53),
(146, '2026-03-25 01:29:08', 32.92, 53),
(147, '2026-03-25 01:29:09', 33.25, 53),
(148, '2026-03-25 01:29:10', 33.58, 53),
(149, '2026-03-25 01:29:11', 33.92, 53),
(150, '2026-03-25 01:29:13', 34.26, 53),
(151, '2026-03-25 01:29:14', 34.6, 53),
(152, '2026-03-25 01:29:15', 34.95, 53),
(153, '2026-03-25 01:29:16', 35.3, 53),
(154, '2026-03-25 01:29:17', 35.65, 53),
(155, '2026-03-25 01:29:18', 36.01, 53),
(156, '2026-03-25 01:29:19', 36.37, 53),
(157, '2026-03-25 01:42:20', 15.15, 54),
(158, '2026-03-25 01:42:21', 15.3, 54),
(159, '2026-03-25 01:42:22', 15.45, 54),
(160, '2026-03-25 01:42:23', 15.61, 54),
(161, '2026-03-25 01:42:24', 15.77, 54),
(162, '2026-03-25 01:42:25', 15.92, 54),
(163, '2026-03-25 01:42:26', 16.08, 54),
(164, '2026-03-25 01:42:27', 16.24, 54),
(165, '2026-03-25 01:42:28', 16.41, 54),
(166, '2026-03-25 01:42:30', 16.57, 54),
(167, '2026-03-25 01:42:31', 16.74, 54),
(168, '2026-03-25 01:42:32', 16.9, 54),
(169, '2026-03-25 01:42:33', 17.07, 54),
(170, '2026-03-25 01:42:46', 19.24, 54),
(171, '2026-03-25 01:42:47', 19.43, 54),
(172, '2026-03-25 01:42:48', 19.62, 54),
(173, '2026-03-25 01:42:50', 19.82, 54),
(174, '2026-03-25 01:42:51', 20.02, 54),
(175, '2026-03-25 01:42:52', 20.22, 54),
(176, '2026-03-25 01:42:53', 20.42, 54),
(177, '2026-03-25 01:42:54', 20.62, 54),
(178, '2026-03-25 01:42:56', 21.04, 54),
(179, '2026-03-25 01:42:57', 21.25, 54),
(180, '2026-03-25 01:42:58', 21.46, 54),
(181, '2026-03-25 01:43:00', 21.68, 54),
(182, '2026-03-25 01:43:01', 21.89, 54),
(183, '2026-03-25 01:43:02', 22.11, 54),
(184, '2026-03-25 01:43:03', 22.33, 54),
(185, '2026-03-25 01:43:04', 22.56, 54),
(186, '2026-03-25 01:43:05', 22.78, 54),
(187, '2026-03-25 01:43:06', 23.01, 54),
(188, '2026-03-25 01:43:07', 23.24, 54),
(189, '2026-03-25 01:43:09', 23.47, 54),
(190, '2026-03-25 01:43:10', 23.71, 54),
(191, '2026-03-25 01:43:11', 23.94, 54),
(192, '2026-03-25 01:43:12', 24.18, 54),
(193, '2026-03-25 01:43:13', 24.43, 54),
(194, '2026-03-25 01:43:14', 24.67, 54),
(195, '2026-03-25 01:43:15', 24.92, 54),
(196, '2026-03-25 01:43:16', 25.17, 54),
(197, '2026-03-25 01:43:17', 25.42, 54),
(198, '2026-03-25 01:43:19', 25.67, 54),
(199, '2026-03-25 01:43:20', 25.93, 54),
(200, '2026-03-25 01:43:21', 26.19, 54),
(201, '2026-03-25 01:43:22', 26.45, 54),
(202, '2026-03-25 01:43:23', 26.71, 54),
(203, '2026-03-25 01:43:24', 26.98, 54),
(204, '2026-03-25 01:43:25', 27.25, 54),
(205, '2026-03-25 01:43:26', 27.52, 54),
(206, '2026-03-25 01:43:27', 27.8, 54),
(207, '2026-03-25 01:43:28', 28.08, 54),
(208, '2026-03-25 01:43:30', 28.36, 54),
(209, '2026-03-25 01:43:31', 28.64, 54),
(210, '2026-03-25 01:43:32', 28.93, 54),
(211, '2026-03-25 01:43:33', 29.22, 54),
(212, '2026-03-25 01:43:34', 29.51, 54),
(213, '2026-03-25 01:43:35', 29.8, 54),
(214, '2026-03-25 01:43:36', 30.1, 54),
(215, '2026-03-25 01:43:37', 30.4, 54),
(216, '2026-03-25 01:43:38', 30.71, 54),
(217, '2026-03-25 01:43:40', 31.01, 54),
(218, '2026-03-25 01:43:41', 31.32, 54),
(219, '2026-03-25 01:43:42', 31.64, 54),
(220, '2026-03-25 01:43:43', 31.95, 54),
(221, '2026-03-25 01:43:44', 32.27, 54),
(222, '2026-03-25 01:43:45', 32.6, 54),
(223, '2026-03-25 01:43:46', 32.92, 54),
(224, '2026-03-25 01:43:47', 33.25, 54),
(225, '2026-03-25 01:43:48', 33.58, 54),
(226, '2026-03-25 01:43:50', 33.92, 54),
(227, '2026-03-25 01:43:51', 34.26, 54),
(228, '2026-03-25 01:43:52', 34.6, 54),
(229, '2026-03-25 01:43:53', 34.95, 54),
(230, '2026-03-25 01:43:54', 35.3, 54),
(231, '2026-03-25 01:43:55', 35.65, 54),
(232, '2026-03-25 01:43:56', 36.01, 54),
(233, '2026-03-25 01:43:57', 36.37, 54),
(234, '2026-03-25 16:30:31', 15.15, 55),
(235, '2026-03-25 16:30:33', 15.3, 55),
(236, '2026-03-25 16:30:34', 15.45, 55),
(237, '2026-03-25 16:30:35', 15.61, 55),
(238, '2026-03-25 16:30:36', 15.77, 55),
(239, '2026-03-25 16:30:37', 15.92, 55),
(240, '2026-03-25 16:30:38', 16.08, 55),
(241, '2026-03-25 16:30:39', 16.24, 55),
(242, '2026-03-25 16:30:40', 16.41, 55),
(243, '2026-03-25 16:30:41', 16.57, 55),
(244, '2026-03-25 16:30:42', 16.74, 55),
(245, '2026-03-25 16:30:43', 16.9, 55),
(246, '2026-03-25 16:30:44', 17.07, 55),
(247, '2026-03-25 16:30:57', 19.24, 55),
(248, '2026-03-25 16:30:58', 19.43, 55),
(249, '2026-03-25 16:30:59', 19.62, 55),
(250, '2026-03-25 16:31:00', 19.82, 55),
(251, '2026-03-25 16:31:01', 20.02, 55),
(252, '2026-03-25 16:31:03', 20.22, 55),
(253, '2026-03-25 16:31:04', 20.42, 55),
(254, '2026-03-25 16:31:05', 20.62, 55),
(255, '2026-03-25 16:31:07', 21.04, 55),
(256, '2026-03-25 16:31:08', 21.25, 55),
(257, '2026-03-25 16:31:09', 21.46, 55),
(258, '2026-03-25 16:31:10', 21.68, 55),
(259, '2026-03-25 16:31:11', 21.89, 55),
(260, '2026-03-25 16:31:12', 22.11, 55),
(261, '2026-03-25 16:31:13', 22.33, 55),
(262, '2026-03-25 16:31:14', 22.56, 55),
(263, '2026-03-25 16:31:15', 22.78, 55),
(264, '2026-03-25 16:31:16', 23.01, 55),
(265, '2026-03-25 16:31:17', 23.24, 55),
(266, '2026-03-25 16:31:18', 23.47, 55),
(267, '2026-03-25 16:31:20', 23.71, 55),
(268, '2026-03-25 16:31:21', 23.94, 55),
(269, '2026-03-25 16:31:22', 24.18, 55),
(270, '2026-03-25 16:31:23', 24.43, 55),
(271, '2026-03-25 16:31:24', 24.67, 55),
(272, '2026-03-25 16:31:25', 24.92, 55),
(273, '2026-03-26 14:50:25', 15.15, 56),
(274, '2026-03-26 14:50:26', 15.3, 56),
(275, '2026-03-26 14:50:27', 15.45, 56),
(276, '2026-03-26 14:50:28', 15.61, 56),
(277, '2026-03-26 14:50:29', 15.77, 56),
(278, '2026-03-26 14:50:30', 15.92, 56),
(279, '2026-03-26 14:50:31', 16.08, 56),
(280, '2026-03-26 14:50:32', 16.24, 56),
(281, '2026-03-26 14:50:33', 16.41, 56),
(282, '2026-03-26 14:50:34', 16.57, 56),
(283, '2026-03-26 14:50:35', 16.74, 56),
(284, '2026-03-26 14:50:36', 16.9, 56),
(285, '2026-03-26 14:50:38', 17.07, 56),
(286, '2026-03-26 14:50:50', 19.24, 56),
(287, '2026-03-26 14:50:51', 19.43, 56),
(288, '2026-03-26 14:50:52', 19.62, 56),
(289, '2026-03-26 14:50:53', 19.82, 56),
(290, '2026-03-26 14:50:54', 20.02, 56),
(291, '2026-03-26 14:50:55', 20.22, 56),
(292, '2026-03-26 14:50:56', 20.42, 56),
(293, '2026-03-26 14:50:57', 20.62, 56),
(294, '2026-03-26 14:51:00', 21.04, 56),
(295, '2026-03-26 14:51:01', 21.25, 56),
(296, '2026-03-26 14:51:02', 21.46, 56),
(297, '2026-03-26 14:51:03', 21.68, 56),
(298, '2026-03-26 14:51:04', 21.89, 56),
(299, '2026-03-26 14:51:05', 22.11, 56),
(300, '2026-03-26 14:51:06', 22.33, 56),
(301, '2026-03-26 14:51:07', 22.56, 56),
(302, '2026-03-26 14:51:08', 22.78, 56),
(303, '2026-03-26 14:51:09', 23.01, 56),
(304, '2026-03-26 14:51:10', 23.24, 56),
(305, '2026-03-26 14:51:11', 23.47, 56),
(306, '2026-03-26 14:51:12', 23.71, 56),
(307, '2026-03-26 14:51:13', 23.94, 56),
(308, '2026-03-26 14:51:14', 24.18, 56),
(309, '2026-03-26 14:51:16', 24.43, 56),
(310, '2026-03-26 14:51:17', 24.67, 56),
(311, '2026-03-26 14:51:18', 24.92, 56),
(312, '2026-03-26 15:01:12', 15.15, 57),
(313, '2026-03-26 15:01:13', 15.3, 57),
(314, '2026-03-26 15:01:14', 15.45, 57),
(315, '2026-03-26 15:01:15', 15.61, 57),
(316, '2026-03-26 15:01:16', 15.77, 57),
(317, '2026-03-26 15:01:17', 15.92, 57),
(318, '2026-03-26 15:01:18', 16.08, 57),
(319, '2026-03-26 15:01:19', 16.24, 57),
(320, '2026-03-26 15:01:20', 16.41, 57),
(321, '2026-03-26 15:01:21', 16.57, 57),
(322, '2026-03-26 15:01:23', 16.74, 57),
(323, '2026-03-26 15:01:24', 16.9, 57),
(324, '2026-03-26 15:01:25', 17.07, 57),
(325, '2026-03-26 15:01:37', 19.24, 57),
(326, '2026-03-26 15:01:38', 19.43, 57),
(327, '2026-03-26 15:01:39', 19.62, 57),
(328, '2026-03-26 15:01:40', 19.82, 57),
(329, '2026-03-26 15:01:41', 20.02, 57),
(330, '2026-03-26 15:01:43', 20.22, 57),
(331, '2026-03-26 15:01:44', 20.42, 57),
(332, '2026-03-26 15:01:45', 20.62, 57),
(333, '2026-03-26 15:01:47', 21.04, 57),
(334, '2026-03-26 15:01:48', 21.25, 57),
(335, '2026-03-26 15:01:49', 21.46, 57),
(336, '2026-03-26 15:01:50', 21.68, 57),
(337, '2026-03-26 15:01:51', 21.89, 57),
(338, '2026-03-26 15:01:52', 22.11, 57),
(339, '2026-03-26 15:01:53', 22.33, 57),
(340, '2026-03-26 15:01:54', 22.56, 57),
(341, '2026-03-26 15:01:55', 22.78, 57),
(342, '2026-03-26 15:01:56', 23.01, 57),
(343, '2026-03-26 15:01:57', 23.24, 57),
(344, '2026-03-26 15:01:58', 23.47, 57),
(345, '2026-03-26 15:01:59', 23.71, 57),
(346, '2026-03-26 15:02:00', 23.94, 57),
(347, '2026-03-26 15:02:01', 24.18, 57),
(348, '2026-03-26 15:02:02', 24.43, 57),
(349, '2026-03-26 15:02:04', 24.67, 57),
(350, '2026-03-26 15:02:05', 24.92, 57),
(351, '2026-03-26 15:20:32', 15.15, 58),
(352, '2026-03-26 15:20:33', 15.3, 58),
(353, '2026-03-26 15:20:34', 15.45, 58),
(354, '2026-03-26 15:20:35', 15.61, 58),
(355, '2026-03-26 15:20:36', 15.77, 58),
(356, '2026-03-26 15:20:37', 15.92, 58),
(357, '2026-03-26 15:20:38', 16.08, 58),
(358, '2026-03-26 15:20:39', 16.24, 58),
(359, '2026-03-26 15:20:40', 16.41, 58),
(360, '2026-03-26 15:20:41', 16.57, 58),
(361, '2026-03-26 15:20:42', 16.74, 58),
(362, '2026-03-26 15:20:43', 16.9, 58),
(363, '2026-03-26 15:20:44', 17.07, 58),
(364, '2026-03-26 15:20:57', 19.24, 58),
(365, '2026-03-26 15:20:58', 19.43, 58),
(366, '2026-03-26 15:20:59', 19.62, 58),
(367, '2026-03-26 15:21:00', 19.82, 58),
(368, '2026-03-26 15:21:01', 20.02, 58),
(369, '2026-03-26 15:21:02', 20.22, 58),
(370, '2026-03-26 15:21:03', 20.42, 58),
(371, '2026-03-26 15:21:04', 20.62, 58),
(372, '2026-03-26 15:21:06', 21.04, 58),
(373, '2026-03-26 15:21:07', 21.25, 58),
(374, '2026-03-26 15:21:08', 21.46, 58),
(375, '2026-03-26 15:21:10', 21.68, 58),
(376, '2026-03-26 15:21:11', 21.89, 58),
(377, '2026-03-26 15:21:12', 22.11, 58),
(378, '2026-03-26 15:21:13', 22.33, 58),
(379, '2026-03-26 15:21:14', 22.56, 58),
(380, '2026-03-26 15:21:15', 22.78, 58),
(381, '2026-03-26 15:21:16', 23.01, 58),
(382, '2026-03-26 15:21:17', 23.24, 58),
(383, '2026-03-26 15:21:18', 23.47, 58),
(384, '2026-03-26 15:21:19', 23.71, 58),
(385, '2026-03-26 15:21:20', 23.94, 58),
(386, '2026-03-26 15:21:21', 24.18, 58),
(387, '2026-03-26 15:21:22', 24.43, 58),
(388, '2026-03-26 15:21:23', 24.67, 58),
(389, '2026-03-26 15:21:24', 24.92, 58);

--
-- 触发器 `Temperatura`
--
DELIMITER $$
CREATE TRIGGER `before_insert_temperatura` BEFORE INSERT ON `Temperatura` FOR EACH ROW BEGIN
    IF NEW.Hora IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Temperature event invalid: Hour is NULL';
    END IF;

    IF NEW.Temperatura IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Temperature event invalid: value is NULL';
    END IF;

    IF NEW.Temperatura < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Temperature event invalid: value below 0';
    END IF;

    IF NEW.Temperatura >= 60 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Temperature event invalid: value >= 60';
    END IF;

    IF NEW.IDSimulacao IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Temperature event invalid: simulation is NULL';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- 表的结构 `Utilizador`
--

CREATE TABLE `Utilizador` (
  `IDUtilizador` int(11) NOT NULL,
  `Username` varchar(50) NOT NULL,
  `Nome` varchar(100) DEFAULT NULL,
  `Telemovel` varchar(12) DEFAULT NULL,
  `Tipo` varchar(20) DEFAULT NULL,
  `Email` varchar(50) NOT NULL,
  `DataNascimento` date DEFAULT NULL,
  `Equipa` int(11) NOT NULL,
  `Password` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转存表中的数据 `Utilizador`
--

INSERT INTO `Utilizador` (`IDUtilizador`, `Username`, `Nome`, `Telemovel`, `Tipo`, `Email`, `DataNascimento`, `Equipa`, `Password`) VALUES
(1, 'Jun', 'Jun', NULL, 'AdminApp', 'jun@mail.com', NULL, 5, '1234'),
(67, 'Teste', 'Teste', NULL, 'Investigador', 'test@mail.com', NULL, 5, '1234'),
(71, 'admin1', 'Administrador', NULL, 'AdminApp', 'admin1@test.com', NULL, 1, 'admin123'),
(72, 'user1', 'coelho', NULL, 'Investigador', 'user1novo@test.com', NULL, 2, 'novapass123'),
(73, 'user2', 'Bomdia', NULL, 'Investigador', 'user2novo@test.com', NULL, 1, 'novapass123'),
(74, 'uuuuser', 'Novo', NULL, 'Investigador', 'userNOVO@test.com', NULL, 1, 'user123'),
(75, 'script1', 'umaScript', NULL, 'Script', 'script1@test.com', NULL, 5, 'script123');

--
-- 转储表的索引
--

--
-- 表的索引 `Corridor`
--
ALTER TABLE `Corridor`
  ADD PRIMARY KEY (`ID`);

--
-- 表的索引 `EventosProcessados`
--
ALTER TABLE `EventosProcessados`
  ADD PRIMARY KEY (`EventID`),
  ADD KEY `idx_eventosprocessados_sim` (`IDSimulacao`);

--
-- 表的索引 `Marsami`
--
ALTER TABLE `Marsami`
  ADD PRIMARY KEY (`IDSimulacao`,`IDMarsami`),
  ADD UNIQUE KEY `uq_marsami_simulacao` (`IDMarsami`,`IDSimulacao`),
  ADD KEY `idx_marsami_id` (`IDMarsami`);

--
-- 表的索引 `MedicoesPassagens`
--
ALTER TABLE `MedicoesPassagens`
  ADD PRIMARY KEY (`IDMedicao`),
  ADD KEY `idx_medicoespassagens_sim_marsami` (`IDSimulacao`,`Marsami`);

--
-- 表的索引 `Mensagens`
--
ALTER TABLE `Mensagens`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `IDSimulacao` (`IDSimulacao`);

--
-- 表的索引 `OcupacaoLabirinto`
--
ALTER TABLE `OcupacaoLabirinto`
  ADD PRIMARY KEY (`IDSimulacao`,`Sala`);

--
-- 表的索引 `ScoreSala`
--
ALTER TABLE `ScoreSala`
  ADD PRIMARY KEY (`IDScore`),
  ADD UNIQUE KEY `uq_scoresala_tentativa` (`IDSimulacao`,`IDUtilizador`,`Sala`,`NumTentativa`),
  ADD KEY `idx_scoresala_sim_sala` (`IDSimulacao`,`Sala`),
  ADD KEY `fk_scoresala_utilizador_01` (`IDUtilizador`);

--
-- 表的索引 `Simulacao`
--
ALTER TABLE `Simulacao`
  ADD PRIMARY KEY (`IDSimulacao`),
  ADD KEY `fk_simulacao_utilizador` (`IDUtilizadorCriador`),
  ADD KEY `idx_simulacao_estado` (`Estado`);

--
-- 表的索引 `Som`
--
ALTER TABLE `Som`
  ADD PRIMARY KEY (`IDSom`),
  ADD KEY `IDSimulacao` (`IDSimulacao`);

--
-- 表的索引 `Temperatura`
--
ALTER TABLE `Temperatura`
  ADD PRIMARY KEY (`IDTemperatura`),
  ADD KEY `IDSimulacao` (`IDSimulacao`);

--
-- 表的索引 `Utilizador`
--
ALTER TABLE `Utilizador`
  ADD PRIMARY KEY (`IDUtilizador`),
  ADD UNIQUE KEY `uq_utilizador_username` (`Username`);

--
-- 在导出的表使用AUTO_INCREMENT
--

--
-- 使用表AUTO_INCREMENT `MedicoesPassagens`
--
ALTER TABLE `MedicoesPassagens`
  MODIFY `IDMedicao` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=510;

--
-- 使用表AUTO_INCREMENT `Mensagens`
--
ALTER TABLE `Mensagens`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=61;

--
-- 使用表AUTO_INCREMENT `ScoreSala`
--
ALTER TABLE `ScoreSala`
  MODIFY `IDScore` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `Simulacao`
--
ALTER TABLE `Simulacao`
  MODIFY `IDSimulacao` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=59;

--
-- 使用表AUTO_INCREMENT `Som`
--
ALTER TABLE `Som`
  MODIFY `IDSom` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=330;

--
-- 使用表AUTO_INCREMENT `Temperatura`
--
ALTER TABLE `Temperatura`
  MODIFY `IDTemperatura` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=390;

--
-- 使用表AUTO_INCREMENT `Utilizador`
--
ALTER TABLE `Utilizador`
  MODIFY `IDUtilizador` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=76;

--
-- 限制导出的表
--

--
-- 限制表 `EventosProcessados`
--
ALTER TABLE `EventosProcessados`
  ADD CONSTRAINT `fk_eventosprocessados_sim` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- 限制表 `Marsami`
--
ALTER TABLE `Marsami`
  ADD CONSTRAINT `fk_marsami_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- 限制表 `MedicoesPassagens`
--
ALTER TABLE `MedicoesPassagens`
  ADD CONSTRAINT `fk_medicoespassagens_marsami` FOREIGN KEY (`IDSimulacao`,`Marsami`) REFERENCES `Marsami` (`IDSimulacao`, `IDMarsami`),
  ADD CONSTRAINT `fk_medicoespassagens_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- 限制表 `Mensagens`
--
ALTER TABLE `Mensagens`
  ADD CONSTRAINT `mensagens_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- 限制表 `OcupacaoLabirinto`
--
ALTER TABLE `OcupacaoLabirinto`
  ADD CONSTRAINT `fk_ocupacao_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- 限制表 `ScoreSala`
--
ALTER TABLE `ScoreSala`
  ADD CONSTRAINT `fk_scoresala_ocupacao_01` FOREIGN KEY (`IDSimulacao`,`Sala`) REFERENCES `OcupacaoLabirinto` (`IDSimulacao`, `Sala`),
  ADD CONSTRAINT `fk_scoresala_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`),
  ADD CONSTRAINT `fk_scoresala_utilizador` FOREIGN KEY (`IDUtilizador`) REFERENCES `Utilizador` (`IDUtilizador`);

--
-- 限制表 `Simulacao`
--
ALTER TABLE `Simulacao`
  ADD CONSTRAINT `fk_simulacao_utilizador` FOREIGN KEY (`IDUtilizadorCriador`) REFERENCES `Utilizador` (`IDUtilizador`);

--
-- 限制表 `Som`
--
ALTER TABLE `Som`
  ADD CONSTRAINT `som_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- 限制表 `Temperatura`
--
ALTER TABLE `Temperatura`
  ADD CONSTRAINT `temperatura_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
