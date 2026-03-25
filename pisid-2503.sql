-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Mar 25, 2026 at 06:06 PM
-- Server version: 10.4.28-MariaDB
-- PHP Version: 8.2.4

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `pisid`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `alterar_dados_utilizador_admin` (IN `p_username` VARCHAR(50), IN `p_novo_nome` VARCHAR(100), IN `p_novo_telemovel` VARCHAR(12), IN `p_novo_tipo` VARCHAR(10), IN `p_novo_email` VARCHAR(50), IN `p_nova_data_nascimento` DATE, IN `p_nova_equipa` INT, IN `p_nova_password` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_current_tipo VARCHAR(10);
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

    IF v_current_tipo <> 'Admin' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas Admin pode alterar dados de outros utilizadores.';
    END IF;

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = p_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'O username indicado nao existe.';
    END IF;

    IF p_novo_tipo IS NOT NULL AND p_novo_tipo NOT IN ('Admin', 'User', 'Script') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo invalido. Use Admin, User ou Script.';
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `alterar_meus_dados_utilizador` (IN `p_NovoNome` VARCHAR(100), IN `p_NovoTelemovel` VARCHAR(12), IN `p_NovoEmail` VARCHAR(50), IN `p_NovaDataNascimento` DATE, IN `p_NovaEquipa` INT, IN `p_NovaPassword` VARCHAR(50))  MODIFIES SQL DATA BEGIN
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `criar_simulacao` (IN `p_descricao` TEXT)  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_id_utilizador INT;
    DECLARE v_equipa INT;

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = v_current_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    SELECT IDUtilizador, Equipa
      INTO v_id_utilizador, v_equipa
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    INSERT INTO Simulacao
    (
        IDUtilizadorCriador,
        Descricao,
        Equipa,
        DataHorainicio,
        DataHoraFim,
        Estado
    )
    VALUES
    (
        v_id_utilizador,
        p_descricao,
        v_equipa,
        NULL,
        NULL,
        'PorIniciar'
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `criar_utilizador` (IN `p_username` VARCHAR(50), IN `p_nome` VARCHAR(100), IN `p_telemovel` VARCHAR(12), IN `p_tipo` VARCHAR(10), IN `p_email` VARCHAR(50), IN `p_dataNascimento` DATE, IN `p_equipa` INT, IN `p_password` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_role_name VARCHAR(20);

    IF p_tipo NOT IN ('Admin', 'User', 'Script') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de utilizador invalido. Use Admin, User ou Script.';
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

    IF p_tipo = 'Admin' THEN
        SET v_role_name = 'role_admin';
    ELSEIF p_tipo = 'User' THEN
        SET v_role_name = 'role_user';
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `eliminar_utilizador_admin` (IN `p_username` VARCHAR(50))  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_current_tipo VARCHAR(10);
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

    IF v_current_tipo <> 'Admin' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas Admin pode eliminar utilizadores.';
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

    SET @sql_drop_user = CONCAT('DROP USER IF EXISTS ''', p_username, '''@''localhost''');
    PREPARE stmt FROM @sql_drop_user;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    FLUSH PRIVILEGES;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `iniciar_simulacao` (IN `p_idSimulacao` INT)  MODIFIES SQL DATA BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_equipa_utilizador INT;
    DECLARE v_equipa_simulacao INT;
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

    SELECT Equipa
      INTO v_equipa_utilizador
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

    SELECT Equipa, Estado
      INTO v_equipa_simulacao, v_estado
      FROM Simulacao
     WHERE IDSimulacao = p_idSimulacao
     LIMIT 1;

    IF v_equipa_utilizador <> v_equipa_simulacao THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas utilizadores da mesma equipa podem iniciar a simulacao.';
    END IF;

    IF v_estado <> 'PorIniciar' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao nao esta no estado PorIniciar.';
    END IF;

    UPDATE Simulacao
       SET DataHorainicio = NOW(),
           DataHoraFim = NULL,
           Estado = 'ACorrer'
     WHERE IDSimulacao = p_idSimulacao;

    UPDATE Corridor
       SET Active = 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_atualizar_simulacao` (IN `p_idSimulacao` INT, IN `p_descricao` TEXT)  MODIFIES SQL DATA BEGIN
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_bloquear_simulacao` (IN `p_idSimulacao` INT, IN `p_sensor` VARCHAR(50), IN `p_tipo_alerta` VARCHAR(50), IN `p_msg` VARCHAR(100), IN `p_hora_evento` DATETIME, IN `p_leitura` DECIMAL(10,2))  MODIFIES SQL DATA BEGIN
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_log_message` (IN `p_id_simulacao` INT, IN `p_sensor` VARCHAR(50), IN `p_tipo_alerta` VARCHAR(100), IN `p_msg` TEXT, IN `p_hora_evento` DATETIME, IN `p_valor` DECIMAL(10,2))   proc: BEGIN
    DECLARE v_last_alert_time DATETIME DEFAULT NULL;

    IF p_hora_evento IS NULL THEN
        SET p_hora_evento = NOW();
    END IF;

    IF p_tipo_alerta LIKE 'ALERTA\_%' THEN
        SELECT MAX(HoraEscrita)
          INTO v_last_alert_time
          FROM Mensagens
         WHERE IDSimulacao = p_id_simulacao
           AND TipoAlerta = p_tipo_alerta;

        IF v_last_alert_time IS NOT NULL
           AND TIMESTAMPDIFF(SECOND, v_last_alert_time, NOW()) < 17 THEN
            LEAVE proc;
        END IF;
    END IF;

    INSERT INTO Mensagens
    (
        Hora,
        Sala,
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
        NULL,
        p_sensor,
        p_valor,
        p_tipo_alerta,
        LEFT(p_msg, 100),
        NOW(),
        p_id_simulacao
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_tentar_score` (IN `p_id_simulacao` INT, IN `p_sala` INT)   BEGIN
    DECLARE v_current_username VARCHAR(50);
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_sim_exists INT DEFAULT 0;
    DECLARE v_room_exists INT DEFAULT 0;

    DECLARE v_id_utilizador INT DEFAULT NULL;
    DECLARE v_player_id INT DEFAULT NULL;
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;

    DECLARE v_contagem INT DEFAULT 0;
    DECLARE v_equipa_ator INT DEFAULT NULL;
    DECLARE v_equipa_sim INT DEFAULT NULL;

    DECLARE v_odds INT DEFAULT 0;
    DECLARE v_evens INT DEFAULT 0;

    DECLARE v_resultado VARCHAR(10);
    DECLARE v_pontos DECIMAL(4,2);

    SET v_current_username = SUBSTRING_INDEX(USER(), '@', 1);

    SELECT COUNT(*)
      INTO v_user_exists
      FROM Utilizador
     WHERE Username = v_current_username;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acesso negado: utilizador autenticado nao existe na tabela Utilizador.';
    END IF;

    SELECT IDUtilizador, Equipa
      INTO v_id_utilizador, v_equipa_ator
      FROM Utilizador
     WHERE Username = v_current_username
     LIMIT 1;

    SELECT COUNT(*)
      INTO v_sim_exists
      FROM Simulacao
     WHERE IDSimulacao = p_id_simulacao;

    IF v_sim_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao existe.';
    END IF;

    SELECT COUNT(*)
      INTO v_room_exists
      FROM Corridor
     WHERE RoomOrigin = p_sala
        OR RoomDestiny = p_sala;

    IF p_sala IS NULL OR p_sala <= 0 OR v_room_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sala invalida para acionar gatilho.';
    END IF;

    SELECT Estado, Equipa
      INTO v_estado, v_equipa_sim
      FROM Simulacao
     WHERE IDSimulacao = p_id_simulacao
     LIMIT 1;

    IF v_estado = 'PorIniciar' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao ainda nao foi iniciada.';
    END IF;

    IF v_estado IN ('Blocked', 'Terminada') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A simulacao nao esta ativa para acionar o gatilho.';
    END IF;

    IF v_equipa_ator IS NULL OR v_equipa_sim IS NULL OR v_equipa_ator <> v_equipa_sim THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sem permissao: apenas utilizadores da mesma equipa da simulacao podem acionar o gatilho.';
    END IF;

    SELECT MIN(Player)
      INTO v_player_id
      FROM Marsami
     WHERE IDSimulacao = p_id_simulacao;

    IF v_player_id IS NULL THEN
        SET v_player_id = 0;
    END IF;

    SELECT COUNT(*)
      INTO v_contagem
      FROM ScoreSala
     WHERE IDSimulacao = p_id_simulacao
       AND Sala = p_sala;

    IF v_contagem >= 3 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Limite de tentativas atingido para esta sala.';
    END IF;

    SELECT COALESCE(MAX(NumeroOdds), 0), COALESCE(MAX(NumeroEvens), 0)
      INTO v_odds, v_evens
      FROM OcupacaoLabirinto
     WHERE IDSimulacao = p_id_simulacao
       AND Sala = p_sala;

    IF (v_odds + v_evens) > 0 AND v_odds = v_evens THEN
        SET v_resultado = 'SUCESSO';
        SET v_pontos = 1.00;
    ELSE
        SET v_resultado = 'FALHA';
        SET v_pontos = -0.50;
    END IF;

    INSERT INTO ScoreSala
    (
        IDSimulacao,
        PlayerID,
        Sala,
        Tentativa,
        Hora,
        Resultado,
        Pontos
    )
    VALUES
    (
        p_id_simulacao,
        v_player_id,
        p_sala,
        v_contagem + 1,
        NOW(),
        v_resultado,
        v_pontos
    );

    CALL sp_log_message(
        p_id_simulacao,
        'score',
        'GATILHO_SCORE',
        CONCAT(
            'user=', v_current_username,
            ' | player=', v_player_id,
            ' | sala=', p_sala,
            ' | odds=', v_odds,
            ' | evens=', v_evens,
            ' | resultado=', v_resultado,
            ' | pontos=', v_pontos
        ),
        NOW(),
        v_pontos
    );
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_valid_movement` (IN `p_sim_id` INT, IN `p_player` INT, IN `p_marsami` INT, IN `p_origin` INT, IN `p_destiny` INT, IN `p_status` INT, IN `p_hora` DATETIME)   BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_tipo VARCHAR(4);
    DECLARE v_current_room INT DEFAULT NULL;
    DECLARE v_total_marsamis INT DEFAULT 0;
    DECLARE v_last_alert_time DATETIME DEFAULT NULL;
    DECLARE v_sim_estado VARCHAR(20) DEFAULT NULL;

    IF p_hora IS NULL THEN
        SET p_hora = NOW();
    END IF;

    SELECT Estado
      INTO v_sim_estado
      FROM Simulacao
     WHERE IDSimulacao = p_sim_id
     LIMIT 1;

    IF v_sim_estado IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: simulation does not exist';
    END IF;

    IF v_sim_estado NOT IN ('ACorrer', 'Blocked') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: simulation is not accepting movement events';
    END IF;

    IF v_sim_estado = 'Blocked'
       AND NOT (p_origin = 0 AND p_destiny = 0 AND p_status = 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)';
    END IF;

    SELECT COUNT(*)
      INTO v_exists
      FROM Marsami
     WHERE IDSimulacao = p_sim_id
       AND IDMarsami = p_marsami;

    IF v_exists = 0 THEN

        IF p_origin <> 0 OR p_destiny = 0 OR p_status <> 1 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Movement invalid: first event must be initial placement (origin=0, destiny>0, status=1)';
        END IF;

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
            NumeroOdds = NumeroOdds + IF(v_tipo = 'odd', 1, 0),
            NumeroEvens = NumeroEvens + IF(v_tipo = 'even', 1, 0);

        SELECT COALESCE(NumeroOdds, 0) + COALESCE(NumeroEvens, 0)
          INTO v_total_marsamis
          FROM OcupacaoLabirinto
         WHERE IDSimulacao = p_sim_id
           AND Sala = p_destiny;

        IF v_total_marsamis >= 6 THEN
            SELECT MAX(HoraEscrita)
              INTO v_last_alert_time
              FROM Mensagens
             WHERE IDSimulacao = p_sim_id
               AND TipoAlerta = 'ALERTA_SALA_CHEIA'
               AND COALESCE(Msg, '') LIKE CONCAT('%sala ', p_destiny, '%');

            IF v_last_alert_time IS NULL
               OR TIMESTAMPDIFF(SECOND, v_last_alert_time, NOW()) > 10 THEN
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

        SELECT SalaAtual, Tipo
          INTO v_current_room, v_tipo
          FROM Marsami
         WHERE IDSimulacao = p_sim_id
           AND IDMarsami = p_marsami
         LIMIT 1;

        IF p_origin = 0 AND p_destiny = 0 THEN

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

            UPDATE Marsami
               SET Estado = p_status,
                   UltimaHoraMovimento = p_hora
             WHERE IDSimulacao = p_sim_id
               AND IDMarsami = p_marsami;

        ELSE

            IF p_origin <> v_current_room THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Movement invalid: RoomOrigin does not match Marsami current room';
            END IF;

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
                SELECT MAX(HoraEscrita)
                  INTO v_last_alert_time
                  FROM Mensagens
                 WHERE IDSimulacao = p_sim_id
                   AND TipoAlerta = 'ALERTA_SALA_CHEIA'
                   AND COALESCE(Msg, '') LIKE CONCAT('%sala ', p_destiny, '%');

                IF v_last_alert_time IS NULL
                   OR TIMESTAMPDIFF(SECOND, v_last_alert_time, NOW()) > 10 THEN
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
               DataHoraFim = COALESCE(DataHoraFim, NOW())
         WHERE IDSimulacao = p_sim_id
           AND Estado <> 'Terminada';
    END IF;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_valid_sound` (IN `p_sim_id` INT, IN `p_hora` DATETIME, IN `p_val` DECIMAL(10,2))   proc: BEGIN
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
        CALL sp_bloquear_simulacao(
            p_sim_id,
            'SOUND',
            'BLOQUEIO_SOM',
            'Maximum sound reached - close all doors',
            p_hora,
            p_val
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_valid_temperature` (IN `p_sim_id` INT, IN `p_hora` DATETIME, IN `p_val` DECIMAL(10,2))   proc: BEGIN
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
        CALL sp_bloquear_simulacao(
            p_sim_id,
            'TEMPERATURE',
            'BLOQUEIO_TEMPERATURA',
            'Maximum temperature reached - close all doors',
            p_hora,
            p_val
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `terminar_simulacao` (IN `p_idSimulacao` INT)  MODIFIES SQL DATA BEGIN
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

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `Corridor`
--

CREATE TABLE `Corridor` (
  `ID` int(11) NOT NULL,
  `RoomOrigin` int(11) NOT NULL,
  `RoomDestiny` int(11) NOT NULL,
  `Active` tinyint(1) NOT NULL DEFAULT 1,
  `Distance` int(11) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `Corridor`
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
-- Table structure for table `EventosProcessados`
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
-- Dumping data for table `EventosProcessados`
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
('55:99', 55, 'sound', 'DONE', '2026-03-25 16:31:04', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `Marsami`
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
-- Dumping data for table `Marsami`
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
(30, 5, 55, 6, 'even', 2, '2026-03-25 16:32:10');

-- --------------------------------------------------------

--
-- Table structure for table `MedicoesPassagens`
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
-- Dumping data for table `MedicoesPassagens`
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
(293, '2026-03-25 16:32:10', 0, 0, 30, 2, 55);

--
-- Triggers `MedicoesPassagens`
--
DELIMITER $$
CREATE TRIGGER `before_insert_medicoes_passagens` BEFORE INSERT ON `MedicoesPassagens` FOR EACH ROW BEGIN
    DECLARE v_corridor_exists INT DEFAULT 0;
    DECLARE v_corridor_active TINYINT DEFAULT 0;
    DECLARE v_sim_estado VARCHAR(20) DEFAULT NULL;

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

    IF v_sim_estado = 'Blocked'
       AND NOT (NEW.SalaOrigem = 0 AND NEW.SalaDestino = 0 AND NEW.Status = 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)';
    END IF;

    IF NEW.Marsami IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: Marsami is NULL';
    END IF;

    IF NEW.Status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Movement invalid: Status is NULL';
    END IF;

    IF NEW.Status NOT IN (0,1,2) THEN
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

    IF NEW.SalaOrigem = 0 AND NEW.SalaDestino = 0 AND NEW.Status NOT IN (0,2) THEN
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
-- Table structure for table `Mensagens`
--

CREATE TABLE `Mensagens` (
  `ID` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `Sala` int(11) DEFAULT NULL,
  `Sensor` varchar(50) DEFAULT NULL,
  `Leitura` decimal(10,2) DEFAULT NULL,
  `TipoAlerta` varchar(50) NOT NULL,
  `Msg` varchar(100) DEFAULT NULL,
  `HoraEscrita` timestamp NOT NULL DEFAULT current_timestamp(),
  `IDSimulacao` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `Mensagens`
--

INSERT INTO `Mensagens` (`ID`, `Hora`, `Sala`, `Sensor`, `Leitura`, `TipoAlerta`, `Msg`, `HoraEscrita`, `IDSimulacao`) VALUES
(1, '2026-03-25 01:42:32', NULL, 'sound', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-25 01:42:32', 54),
(2, '2026-03-25 01:42:34', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:35', 54),
(3, '2026-03-25 01:42:35', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:36', 54),
(4, '2026-03-25 01:42:36', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:37', 54),
(5, '2026-03-25 01:42:37', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:38', 54),
(6, '2026-03-25 01:42:39', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:39', 54),
(7, '2026-03-25 01:42:40', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:40', 54),
(8, '2026-03-25 01:42:41', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:41', 54),
(9, '2026-03-25 01:42:42', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:43', 54),
(10, '2026-03-25 01:42:43', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:44', 54),
(11, '2026-03-25 01:42:44', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:45', 54),
(12, '2026-03-25 01:42:45', NULL, 'TEMPERATURE', 60.00, 'DADO_INVALIDO', 'Temperature invalid: 60.00', '2026-03-25 01:42:46', 54),
(13, '2026-03-25 01:42:46', NULL, 'TEMPERATURE', 19.24, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.24 | median=16.0800 | mad=0.4900 | robust_z=4.3498', '2026-03-25 01:42:47', 54),
(14, '2026-03-25 01:42:47', NULL, 'TEMPERATURE', 19.43, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.43 | median=16.1600 | mad=0.5650 | robust_z=3.9037', '2026-03-25 01:42:48', 54),
(15, '2026-03-25 01:42:48', NULL, 'TEMPERATURE', 19.62, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.62 | median=16.2400 | mad=0.6300 | robust_z=3.6187', '2026-03-25 01:42:49', 54),
(16, '2026-03-25 01:42:50', NULL, 'TEMPERATURE', 19.82, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.82 | median=16.4100 | mad=0.6400 | robust_z=3.5938', '2026-03-25 01:42:50', 54),
(17, '2026-03-25 01:42:51', NULL, 'TEMPERATURE', 20.02, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=20.02 | median=16.5700 | mad=0.6500 | robust_z=3.5800', '2026-03-25 01:42:51', 54),
(18, '2026-03-25 01:42:51', NULL, 'TEMPERATURE', 20.02, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:42:51', 54),
(19, '2026-03-25 01:42:55', NULL, 'SOUND', 60.00, 'DADO_INVALIDO', 'Sound invalid: 60.00', '2026-03-25 01:42:55', 54),
(20, '2026-03-25 01:42:56', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-25 01:42:56', 54),
(21, '2026-03-25 01:42:56', NULL, 'SOUND', 60.00, 'DADO_INVALIDO', 'Sound invalid: 60.00', '2026-03-25 01:42:57', 54),
(22, '2026-03-25 01:42:57', NULL, 'SOUND', 60.00, 'DADO_INVALIDO', 'Sound invalid: 60.00', '2026-03-25 01:42:58', 54),
(23, '2026-03-25 01:43:01', NULL, 'TEMPERATURE', 21.89, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:43:01', 54),
(24, '2026-03-25 01:43:03', NULL, 'SOUND', 22.08, 'ALERTA_SOM', 'High sound alert', '2026-03-25 01:43:03', 54),
(25, '2026-03-25 01:43:05', NULL, 'movement', NULL, 'DADO_INVALIDO', 'Movement invalid: RoomOrigin does not match Marsami current room', '2026-03-25 01:43:05', 54),
(26, '2026-03-25 01:43:11', NULL, 'TEMPERATURE', 23.94, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:43:11', 54),
(27, '2026-03-25 01:43:13', NULL, 'SOUND', 26.39, 'ALERTA_SOM', 'High sound alert', '2026-03-25 01:43:14', 54),
(28, '2026-03-25 01:43:21', NULL, 'TEMPERATURE', 26.19, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:43:21', 54),
(29, '2026-03-25 01:43:31', NULL, 'TEMPERATURE', 28.64, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:43:31', 54),
(30, '2026-03-25 01:43:41', NULL, 'TEMPERATURE', 31.32, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:43:41', 54),
(31, '2026-03-25 01:43:51', NULL, 'TEMPERATURE', 34.26, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 01:43:51', 54),
(32, '2026-03-25 16:30:25', NULL, 'movement', 6.00, 'ALERTA_SALA_CHEIA', 'Sala 10 atingiu ocupacao maxima: 6', '2026-03-25 16:30:25', 55),
(33, '2026-03-25 16:30:43', NULL, 'sound', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-25 16:30:43', 55),
(34, '2026-03-25 16:30:46', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:46', 55),
(35, '2026-03-25 16:30:47', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:47', 55),
(36, '2026-03-25 16:30:48', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:48', 55),
(37, '2026-03-25 16:30:50', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:50', 55),
(38, '2026-03-25 16:30:51', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:51', 55),
(39, '2026-03-25 16:30:52', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:52', 55),
(40, '2026-03-25 16:30:52', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:52', 55),
(41, '2026-03-25 16:30:53', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:53', 55),
(42, '2026-03-25 16:30:55', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:55', 55),
(43, '2026-03-25 16:30:55', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:55', 55),
(44, '2026-03-25 16:30:57', NULL, 'movement', 7.00, 'ALERTA_SALA_CHEIA', 'Sala 5 atingiu ocupacao maxima: 7', '2026-03-25 16:30:57', 55),
(45, '2026-03-25 16:30:57', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Temperature event invalid: value >= 60', '2026-03-25 16:30:57', 55),
(46, '2026-03-25 16:30:57', NULL, 'TEMPERATURE', 19.24, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.24 | median=16.0800 | mad=0.4900 | robust_z=4.3498', '2026-03-25 16:30:58', 55),
(47, '2026-03-25 16:30:58', NULL, 'TEMPERATURE', 19.43, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.43 | median=16.1600 | mad=0.5650 | robust_z=3.9037', '2026-03-25 16:30:59', 55),
(48, '2026-03-25 16:30:59', NULL, 'TEMPERATURE', 19.62, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.62 | median=16.2400 | mad=0.6300 | robust_z=3.6187', '2026-03-25 16:31:00', 55),
(49, '2026-03-25 16:31:00', NULL, 'TEMPERATURE', 19.82, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=19.82 | median=16.4100 | mad=0.6400 | robust_z=3.5938', '2026-03-25 16:31:01', 55),
(50, '2026-03-25 16:31:01', NULL, 'TEMPERATURE', 20.02, 'OUTLIER_TEMPERATURA', 'Temperature outlier detected | value=20.02 | median=16.5700 | mad=0.6500 | robust_z=3.5800', '2026-03-25 16:31:02', 55),
(51, '2026-03-25 16:31:01', NULL, 'TEMPERATURE', 20.02, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 16:31:02', 55),
(52, '2026-03-25 16:31:06', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'Hour invalid', '2026-03-25 16:31:06', 55),
(53, '2026-03-25 16:31:07', NULL, 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-25 16:31:07', 55),
(54, '2026-03-25 16:31:08', NULL, 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-25 16:31:08', 55),
(55, '2026-03-25 16:31:09', NULL, 'sound', NULL, 'DADO_INVALIDO', 'Sound event invalid: value >= 60', '2026-03-25 16:31:09', 55),
(56, '2026-03-25 16:31:13', NULL, 'SOUND', 22.08, 'ALERTA_SOM', 'High sound alert', '2026-03-25 16:31:14', 55),
(57, '2026-03-25 16:31:17', NULL, 'movement', 7.00, 'ALERTA_SALA_CHEIA', 'Sala 5 atingiu ocupacao maxima: 7', '2026-03-25 16:31:17', 55),
(58, '2026-03-25 16:31:18', NULL, 'TEMPERATURE', 23.47, 'ALERTA_TEMPERATURA', 'High temperature alert', '2026-03-25 16:31:19', 55),
(59, '2026-03-25 16:31:25', NULL, 'SOUND', 27.45, 'BLOQUEIO_SOM', 'Maximum sound reached - close all doors', '2026-03-25 16:31:26', 55),
(60, '2026-03-25 16:31:27', NULL, 'movement', NULL, 'DADO_INVALIDO', 'Movement invalid: blocked simulation only accepts fatigue events (origin=0, destiny=0, status=2)', '2026-03-25 16:31:27', 55),
(61, '2026-03-25 16:32:10', NULL, 'temperature', NULL, 'DADO_INVALIDO', 'A simulacao 55 ja foi terminada', '2026-03-25 16:32:10', 55);

-- --------------------------------------------------------

--
-- Table structure for table `OcupacaoLabirinto`
--

CREATE TABLE `OcupacaoLabirinto` (
  `IDSimulacao` int(11) NOT NULL,
  `NumeroOdds` int(11) DEFAULT NULL,
  `NumeroEvens` int(11) DEFAULT NULL,
  `Sala` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `OcupacaoLabirinto`
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
(55, 2, 3, 10);

-- --------------------------------------------------------

--
-- Table structure for table `ScoreSala`
--

CREATE TABLE `ScoreSala` (
  `IDScore` int(11) NOT NULL,
  `IDSimulacao` int(11) DEFAULT NULL,
  `PlayerID` int(11) DEFAULT NULL,
  `Sala` int(11) DEFAULT NULL,
  `Tentativa` int(11) DEFAULT NULL,
  `Hora` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `Resultado` varchar(10) DEFAULT NULL,
  `Pontos` decimal(4,2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `Simulacao`
--

CREATE TABLE `Simulacao` (
  `IDSimulacao` int(11) NOT NULL,
  `IDUtilizadorCriador` int(11) NOT NULL,
  `Descricao` text DEFAULT NULL,
  `Equipa` int(11) DEFAULT NULL,
  `DataHorainicio` timestamp NULL DEFAULT NULL,
  `DataHoraFim` timestamp NULL DEFAULT NULL,
  `Estado` enum('PorIniciar','ACorrer','Blocked','Terminada') NOT NULL DEFAULT 'PorIniciar'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `Simulacao`
--

INSERT INTO `Simulacao` (`IDSimulacao`, `IDUtilizadorCriador`, `Descricao`, `Equipa`, `DataHorainicio`, `DataHoraFim`, `Estado`) VALUES
(52, 71, NULL, NULL, '2026-03-25 01:04:43', '2026-03-25 01:08:55', 'Terminada'),
(53, 1, NULL, NULL, '2026-03-25 01:26:03', '2026-03-25 01:29:21', 'Terminada'),
(54, 1, NULL, NULL, '2026-03-25 01:26:03', '2026-03-25 01:43:58', 'Terminada'),
(55, 1, NULL, NULL, NULL, '2026-03-25 16:32:10', 'Terminada'),
(56, 1, NULL, NULL, NULL, NULL, 'ACorrer');

--
-- Triggers `Simulacao`
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

    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `Som`
--

CREATE TABLE `Som` (
  `IDSom` int(11) NOT NULL,
  `Hora` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `Som` double DEFAULT NULL,
  `IDSimulacao` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `Som`
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
(188, '2026-03-25 16:31:25', 27.45, 55);

--
-- Triggers `Som`
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
-- Table structure for table `Temperatura`
--

CREATE TABLE `Temperatura` (
  `IDTemperatura` int(11) NOT NULL,
  `Hora` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `Temperatura` double DEFAULT NULL,
  `IDSimulacao` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `Temperatura`
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
(272, '2026-03-25 16:31:25', 24.92, 55);

--
-- Triggers `Temperatura`
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
-- Table structure for table `Utilizador`
--

CREATE TABLE `Utilizador` (
  `IDUtilizador` int(11) NOT NULL,
  `Username` varchar(50) NOT NULL,
  `Nome` varchar(100) DEFAULT NULL,
  `Telemovel` varchar(12) DEFAULT NULL,
  `Tipo` varchar(6) DEFAULT NULL,
  `Email` varchar(50) NOT NULL,
  `DataNascimento` date DEFAULT NULL,
  `Equipa` int(11) NOT NULL,
  `Password` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `Utilizador`
--

INSERT INTO `Utilizador` (`IDUtilizador`, `Username`, `Nome`, `Telemovel`, `Tipo`, `Email`, `DataNascimento`, `Equipa`, `Password`) VALUES
(1, 'Jun', 'Jun', NULL, 'Admin', 'jun@mail.com', NULL, 5, '1234'),
(67, 'Teste', 'Teste', NULL, 'User', 'test@mail.com', NULL, 5, '1234'),
(71, 'admin1', 'Administrador', NULL, 'Admin', 'admin1@test.com', NULL, 1, 'admin123'),
(72, 'user1', 'coelho', NULL, 'User', 'user1novo@test.com', NULL, 2, 'novapass123'),
(73, 'user2', 'Bomdia', NULL, 'User', 'user2novo@test.com', NULL, 1, 'novapass123'),
(74, 'uuuuser', 'Novo', NULL, 'User', 'userNOVO@test.com', NULL, 1, 'user123'),
(75, 'script1', 'umaScript', NULL, NULL, 'script1@test.com', NULL, 5, 'script123');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `Corridor`
--
ALTER TABLE `Corridor`
  ADD PRIMARY KEY (`ID`);

--
-- Indexes for table `EventosProcessados`
--
ALTER TABLE `EventosProcessados`
  ADD PRIMARY KEY (`EventID`),
  ADD KEY `idx_eventosprocessados_sim` (`IDSimulacao`);

--
-- Indexes for table `Marsami`
--
ALTER TABLE `Marsami`
  ADD PRIMARY KEY (`IDSimulacao`,`IDMarsami`),
  ADD KEY `idx_marsami_id` (`IDMarsami`);

--
-- Indexes for table `MedicoesPassagens`
--
ALTER TABLE `MedicoesPassagens`
  ADD PRIMARY KEY (`IDMedicao`),
  ADD KEY `idx_medicoespassagens_sim_marsami` (`IDSimulacao`,`Marsami`);

--
-- Indexes for table `Mensagens`
--
ALTER TABLE `Mensagens`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `IDSimulacao` (`IDSimulacao`);

--
-- Indexes for table `OcupacaoLabirinto`
--
ALTER TABLE `OcupacaoLabirinto`
  ADD PRIMARY KEY (`IDSimulacao`,`Sala`),
  ADD UNIQUE KEY `uq_ocupacao_sim_sala` (`IDSimulacao`,`Sala`);

--
-- Indexes for table `ScoreSala`
--
ALTER TABLE `ScoreSala`
  ADD PRIMARY KEY (`IDScore`),
  ADD KEY `idx_scoresala_sim_sala` (`IDSimulacao`,`Sala`);

--
-- Indexes for table `Simulacao`
--
ALTER TABLE `Simulacao`
  ADD PRIMARY KEY (`IDSimulacao`),
  ADD KEY `fk_simulacao_utilizador` (`IDUtilizadorCriador`),
  ADD KEY `idx_simulacao_estado` (`Estado`);

--
-- Indexes for table `Som`
--
ALTER TABLE `Som`
  ADD PRIMARY KEY (`IDSom`),
  ADD KEY `IDSimulacao` (`IDSimulacao`);

--
-- Indexes for table `Temperatura`
--
ALTER TABLE `Temperatura`
  ADD PRIMARY KEY (`IDTemperatura`),
  ADD KEY `IDSimulacao` (`IDSimulacao`);

--
-- Indexes for table `Utilizador`
--
ALTER TABLE `Utilizador`
  ADD PRIMARY KEY (`IDUtilizador`),
  ADD UNIQUE KEY `uq_utilizador_username` (`Username`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `MedicoesPassagens`
--
ALTER TABLE `MedicoesPassagens`
  MODIFY `IDMedicao` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=294;

--
-- AUTO_INCREMENT for table `Mensagens`
--
ALTER TABLE `Mensagens`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=62;

--
-- AUTO_INCREMENT for table `ScoreSala`
--
ALTER TABLE `ScoreSala`
  MODIFY `IDScore` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `Simulacao`
--
ALTER TABLE `Simulacao`
  MODIFY `IDSimulacao` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=57;

--
-- AUTO_INCREMENT for table `Som`
--
ALTER TABLE `Som`
  MODIFY `IDSom` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=189;

--
-- AUTO_INCREMENT for table `Temperatura`
--
ALTER TABLE `Temperatura`
  MODIFY `IDTemperatura` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=273;

--
-- AUTO_INCREMENT for table `Utilizador`
--
ALTER TABLE `Utilizador`
  MODIFY `IDUtilizador` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=76;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `EventosProcessados`
--
ALTER TABLE `EventosProcessados`
  ADD CONSTRAINT `fk_eventosprocessados_sim` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `Marsami`
--
ALTER TABLE `Marsami`
  ADD CONSTRAINT `fk_marsami_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `MedicoesPassagens`
--
ALTER TABLE `MedicoesPassagens`
  ADD CONSTRAINT `fk_medicoespassagens_marsami` FOREIGN KEY (`IDSimulacao`,`Marsami`) REFERENCES `Marsami` (`IDSimulacao`, `IDMarsami`),
  ADD CONSTRAINT `medicoespassagens_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `Mensagens`
--
ALTER TABLE `Mensagens`
  ADD CONSTRAINT `mensagens_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `OcupacaoLabirinto`
--
ALTER TABLE `OcupacaoLabirinto`
  ADD CONSTRAINT `fk_ocupacao_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `ScoreSala`
--
ALTER TABLE `ScoreSala`
  ADD CONSTRAINT `fk_scoresala_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `Simulacao`
--
ALTER TABLE `Simulacao`
  ADD CONSTRAINT `fk_simulacao_utilizador` FOREIGN KEY (`IDUtilizadorCriador`) REFERENCES `Utilizador` (`IDUtilizador`);

--
-- Constraints for table `Som`
--
ALTER TABLE `Som`
  ADD CONSTRAINT `som_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);

--
-- Constraints for table `Temperatura`
--
ALTER TABLE `Temperatura`
  ADD CONSTRAINT `temperatura_ibfk_1` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
