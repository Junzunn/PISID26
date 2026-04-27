-- MariaDB dump 10.19  Distrib 10.4.28-MariaDB, for osx10.10 (x86_64)
--
-- Host: localhost    Database: Marsabirinto
-- ------------------------------------------------------
-- Server version	10.4.28-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `Marsabirinto`
--

/*!40000 DROP DATABASE IF EXISTS `Marsabirinto`*/;

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `Marsabirinto` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `Marsabirinto`;

--
-- Table structure for table `MedicoesPassagens`
--

DROP TABLE IF EXISTS `MedicoesPassagens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MedicoesPassagens` (
  `IDMedicao` int(11) NOT NULL AUTO_INCREMENT,
  `IDSimulacao` int(11) NOT NULL,
  `Seq` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `SalaOrigem` int(11) DEFAULT NULL,
  `SalaDestino` int(11) DEFAULT NULL,
  `Marsami` int(11) DEFAULT NULL,
  `Status` int(11) DEFAULT NULL,
  PRIMARY KEY (`IDMedicao`),
  UNIQUE KEY `idsimulacao_seq` (`IDSimulacao`,`Seq`) USING BTREE,
  CONSTRAINT `fk_medicoespassagens_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `MedicoesPassagens`
--

LOCK TABLES `MedicoesPassagens` WRITE;
/*!40000 ALTER TABLE `MedicoesPassagens` DISABLE KEYS */;
/*!40000 ALTER TABLE `MedicoesPassagens` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Mensagens`
--

DROP TABLE IF EXISTS `Mensagens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Mensagens` (
  `ID` int(11) NOT NULL AUTO_INCREMENT,
  `IDSimulacao` int(11) NOT NULL,
  `Seq` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `Sensor` varchar(10) DEFAULT NULL COMMENT '1(temperatura) e 2 (Ruído)',
  `Leitura` decimal(6,2) DEFAULT NULL,
  `TipoAlerta` varchar(50) DEFAULT NULL,
  `Msg` varchar(100) DEFAULT NULL,
  `HoraEscrita` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`ID`),
  UNIQUE KEY `idsimulacao_seq` (`IDSimulacao`,`Seq`) USING BTREE,
  CONSTRAINT `fk_mensagens_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Mensagens`
--

LOCK TABLES `Mensagens` WRITE;
/*!40000 ALTER TABLE `Mensagens` DISABLE KEYS */;
/*!40000 ALTER TABLE `Mensagens` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `OcupacaoLabirinto`
--

DROP TABLE IF EXISTS `OcupacaoLabirinto`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `OcupacaoLabirinto` (
  `IDJogo` int(11) NOT NULL,
  `NumeroMarsamisOdd` int(11) DEFAULT NULL,
  `NumeroMarsamisEven` int(11) DEFAULT NULL,
  `Sala` int(11) NOT NULL,
  PRIMARY KEY (`IDJogo`,`Sala`),
  CONSTRAINT `fk_ocupacaolabirinto_simulacao` FOREIGN KEY (`IDJogo`) REFERENCES `Simulacao` (`IDSimulacao`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `OcupacaoLabirinto`
--

LOCK TABLES `OcupacaoLabirinto` WRITE;
/*!40000 ALTER TABLE `OcupacaoLabirinto` DISABLE KEYS */;
/*!40000 ALTER TABLE `OcupacaoLabirinto` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Simulacao`
--

DROP TABLE IF EXISTS `Simulacao`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Simulacao` (
  `IDSimulacao` int(11) NOT NULL AUTO_INCREMENT,
  `Descricao` text DEFAULT NULL,
  `Equipa` int(11) NOT NULL,
  `IDCriador` int(11) DEFAULT NULL,
  `DataHorainicio` timestamp NULL DEFAULT NULL,
  `DataHoraFim` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`IDSimulacao`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Simulacao`
--

LOCK TABLES `Simulacao` WRITE;
/*!40000 ALTER TABLE `Simulacao` DISABLE KEYS */;
INSERT INTO `Simulacao` VALUES (1,'Primeira Simulação',5,1,NULL,NULL);
/*!40000 ALTER TABLE `Simulacao` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Som`
--

DROP TABLE IF EXISTS `Som`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Som` (
  `IDSom` int(11) NOT NULL AUTO_INCREMENT,
  `IDSimulacao` int(11) NOT NULL,
  `Seq` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `Som` varchar(12) DEFAULT NULL,
  PRIMARY KEY (`IDSom`),
  UNIQUE KEY `idsimulacao_seq` (`IDSimulacao`,`Seq`) USING BTREE,
  CONSTRAINT `fk_som_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Som`
--

LOCK TABLES `Som` WRITE;
/*!40000 ALTER TABLE `Som` DISABLE KEYS */;
/*!40000 ALTER TABLE `Som` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Temperatura`
--

DROP TABLE IF EXISTS `Temperatura`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Temperatura` (
  `IDTemperatura` int(11) NOT NULL AUTO_INCREMENT,
  `IDSimulacao` int(11) NOT NULL,
  `Seq` int(11) NOT NULL,
  `Hora` timestamp NULL DEFAULT NULL,
  `Temperatura` varchar(12) DEFAULT NULL,
  PRIMARY KEY (`IDTemperatura`),
  UNIQUE KEY `idsimulacao_seq` (`IDSimulacao`,`Seq`) USING BTREE,
  CONSTRAINT `fk_temperatura_simulacao` FOREIGN KEY (`IDSimulacao`) REFERENCES `Simulacao` (`IDSimulacao`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Temperatura`
--

LOCK TABLES `Temperatura` WRITE;
/*!40000 ALTER TABLE `Temperatura` DISABLE KEYS */;
/*!40000 ALTER TABLE `Temperatura` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Utilizador`
--

DROP TABLE IF EXISTS `Utilizador`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Utilizador` (
  `IDUtilizador` int(11) NOT NULL AUTO_INCREMENT,
  `Nome` varchar(100) DEFAULT NULL,
  `Telemovel` varchar(12) DEFAULT NULL,
  `Tipo` enum('AdminApp','Equipe','Analista','Software') DEFAULT NULL,
  `Email` varchar(50) NOT NULL,
  `DataNascimento` date DEFAULT NULL,
  `Equipa` int(11) DEFAULT NULL,
  PRIMARY KEY (`IDUtilizador`),
  UNIQUE KEY `uq_utilizador_email` (`Email`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Utilizador`
--

LOCK TABLES `Utilizador` WRITE;
/*!40000 ALTER TABLE `Utilizador` DISABLE KEYS */;
INSERT INTO `Utilizador` VALUES (1,'Jun','','AdminApp','jun@pisid.pt',NULL,NULL),(2,'Software',NULL,'Software','software@pisid.pt',NULL,NULL);
/*!40000 ALTER TABLE `Utilizador` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Temporary table structure for view `v_utilizador_atual`
--

DROP TABLE IF EXISTS `v_utilizador_atual`;
/*!50001 DROP VIEW IF EXISTS `v_utilizador_atual`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE VIEW `v_utilizador_atual` AS SELECT
 1 AS `IDUtilizador`,
  1 AS `Nome`,
  1 AS `Telemovel`,
  1 AS `Tipo`,
  1 AS `Email`,
  1 AS `DataNascimento`,
  1 AS `Equipa` */;
SET character_set_client = @saved_cs_client;

--
-- Dumping events for database 'Marsabirinto'
--

--
-- Dumping routines for database 'Marsabirinto'
--
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `simulacao_atualizar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_atualizar`(
    IN p_idsimulacao INT,
    IN p_descricao TEXT
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_id_atual INT;
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_idcriador INT;

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(IDUtilizador), MAX(Tipo)
        INTO v_existe, v_id_atual, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Equipe') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Equipe pode atualizar simulacao';
        END IF;
    END IF;

    SELECT COUNT(*), MAX(IDCriador)
    INTO v_existe, v_idcriador
    FROM Simulacao
    WHERE IDSimulacao = p_idsimulacao;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao existe';
    END IF;

    IF v_utilizador_atual <> 'root' AND v_tipo_atual = 'Equipe' AND v_idcriador <> v_id_atual THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipe so pode atualizar simulacoes criadas por si';
    END IF;

    UPDATE Simulacao
    SET Descricao = p_descricao
    WHERE IDSimulacao = p_idsimulacao;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `simulacao_criar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_criar`(
    IN p_equipa INT,
    IN p_descricao TEXT
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_id_atual INT;
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_equipa_atual INT;

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    SELECT COUNT(*), MAX(IDUtilizador), MAX(Tipo), MAX(Equipa)
    INTO v_existe, v_id_atual, v_tipo_atual, v_equipa_atual
    FROM Utilizador
    WHERE Email = v_utilizador_atual;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador atual nao existe na tabela Utilizador';
    END IF;

    IF v_utilizador_atual <> 'root' AND v_tipo_atual NOT IN ('AdminApp', 'Equipe') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Equipe pode criar simulacao';
    END IF;

    IF p_equipa IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipa obrigatoria';
    END IF;

    IF v_tipo_atual = 'Equipe' AND p_equipa <> v_equipa_atual THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipe so pode criar simulacao para a propria equipa';
    END IF;

    INSERT INTO Simulacao (
        Descricao,
        Equipa,
        IDCriador,
        DataHorainicio,
        DataHoraFim
    )
    VALUES (
        p_descricao,
        p_equipa,
        v_id_atual,
        NULL,
        NULL
    );
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `simulacao_iniciar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_iniciar`(
    IN p_idsimulacao INT
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_equipa_atual INT;
    DECLARE v_equipa_simulacao INT;
    DECLARE v_data_inicio TIMESTAMP;

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo), MAX(Equipa)
        INTO v_existe, v_tipo_atual, v_equipa_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Equipe') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Equipe pode iniciar simulacao';
        END IF;
    END IF;

    SELECT COUNT(*), MAX(Equipa), MAX(DataHorainicio)
    INTO v_existe, v_equipa_simulacao, v_data_inicio
    FROM Simulacao
    WHERE IDSimulacao = p_idsimulacao;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao existe';
    END IF;

    IF v_data_inicio IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao ja foi iniciada';
    END IF;

    IF v_utilizador_atual <> 'root' AND v_tipo_atual = 'Equipe' AND v_equipa_simulacao <> v_equipa_atual THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipe so pode iniciar simulacao da propria equipa';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Simulacao
        WHERE Equipa = v_equipa_simulacao
          AND DataHorainicio IS NOT NULL
          AND DataHoraFim IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Esta equipa ja tem uma simulacao em execucao';
    END IF;

    UPDATE Simulacao
    SET DataHorainicio = CURRENT_TIMESTAMP
    WHERE IDSimulacao = p_idsimulacao;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `simulacao_registar_fim` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `simulacao_registar_fim`(
    IN p_idsimulacao INT
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_data_fim TIMESTAMP;

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo)
        INTO v_existe, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Software') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Software pode registar fim da simulacao';
        END IF;
    END IF;

    SELECT COUNT(*), MAX(DataHoraFim)
    INTO v_existe, v_data_fim
    FROM Simulacao
    WHERE IDSimulacao = p_idsimulacao;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Simulacao nao existe';
    END IF;

    IF v_data_fim IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fim da simulacao ja foi registado';
    END IF;

    UPDATE Simulacao
    SET DataHoraFim = CURRENT_TIMESTAMP
    WHERE IDSimulacao = p_idsimulacao;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_registar_mensagem` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registar_mensagem`(
    IN p_idsimulacao INT,
    IN p_seq INT,
    IN p_hora TIMESTAMP,
    IN p_sensor VARCHAR(10),
    IN p_leitura DECIMAL(6,2),
    IN p_tipoalerta VARCHAR(50),
    IN p_msg VARCHAR(100)
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipo_atual VARCHAR(9);

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo)
        INTO v_existe, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Software') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Software pode registar mensagem';
        END IF;
    END IF;

    INSERT IGNORE INTO Mensagens (
        IDSimulacao,
        Seq,
        Hora,
        Sensor,
        Leitura,
        TipoAlerta,
        Msg
    )
    VALUES (
        p_idsimulacao,
        p_seq,
        p_hora,
        p_sensor,
        p_leitura,
        p_tipoalerta,
        p_msg
    );
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_registar_movimento` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registar_movimento`(
    IN p_idsimulacao INT,
    IN p_seq INT,
    IN p_hora TIMESTAMP,
    IN p_salaorigem INT,
    IN p_saladestino INT,
    IN p_marsami INT,
    IN p_status INT
)
proc: BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_odd INT DEFAULT 0;
    DECLARE v_even INT DEFAULT 0;

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo)
        INTO v_existe, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Software') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Software pode registar movimento';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM MedicoesPassagens
        WHERE IDSimulacao = p_idsimulacao
          AND Seq = p_seq
    ) THEN
        LEAVE proc;
    END IF;

    INSERT INTO MedicoesPassagens (
        IDSimulacao,
        Seq,
        Hora,
        SalaOrigem,
        SalaDestino,
        Marsami,
        Status
    )
    VALUES (
        p_idsimulacao,
        p_seq,
        p_hora,
        p_salaorigem,
        p_saladestino,
        p_marsami,
        p_status
    );

    IF p_status = 2 OR p_saladestino = 0 THEN
        LEAVE proc;
    END IF;

    IF MOD(p_marsami, 2) = 0 THEN
        SET v_odd = 1;
    ELSE
        SET v_even = 1;
    END IF;

    INSERT IGNORE INTO OcupacaoLabirinto (
        IDJogo,
        NumeroMarsamisOdd,
        NumeroMarsamisEven,
        Sala
    )
    VALUES (
        p_idsimulacao,
        0,
        0,
        p_salaorigem
    );

    UPDATE OcupacaoLabirinto
    SET
        NumeroMarsamisOdd = COALESCE(NumeroMarsamisOdd, 0) - v_odd,
        NumeroMarsamisEven = COALESCE(NumeroMarsamisEven, 0) - v_even
    WHERE IDJogo = p_idsimulacao
      AND Sala = p_salaorigem;

    INSERT IGNORE INTO OcupacaoLabirinto (
        IDJogo,
        NumeroMarsamisOdd,
        NumeroMarsamisEven,
        Sala
    )
    VALUES (
        p_idsimulacao,
        0,
        0,
        p_saladestino
    );

    UPDATE OcupacaoLabirinto
    SET
        NumeroMarsamisOdd = COALESCE(NumeroMarsamisOdd, 0) + v_odd,
        NumeroMarsamisEven = COALESCE(NumeroMarsamisEven, 0) + v_even
    WHERE IDJogo = p_idsimulacao
      AND Sala = p_saladestino;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_registar_som` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registar_som`(
    IN p_idsimulacao INT,
    IN p_seq INT,
    IN p_hora TIMESTAMP,
    IN p_som VARCHAR(12)
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipo_atual VARCHAR(9);

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo)
        INTO v_existe, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Software') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Software pode registar som';
        END IF;
    END IF;

    INSERT IGNORE INTO Som (
        IDSimulacao,
        Seq,
        Hora,
        Som
    )
    VALUES (
        p_idsimulacao,
        p_seq,
        p_hora,
        p_som
    );
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_registar_temperatura` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registar_temperatura`(
    IN p_idsimulacao INT,
    IN p_seq INT,
    IN p_hora TIMESTAMP,
    IN p_temperatura VARCHAR(12)
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_tipo_atual VARCHAR(9);

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo)
        INTO v_existe, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual NOT IN ('AdminApp', 'Software') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas root, AdminApp ou Software pode registar temperatura';
        END IF;
    END IF;

    INSERT IGNORE INTO Temperatura (
        IDSimulacao,
        Seq,
        Hora,
        Temperatura
    )
    VALUES (
        p_idsimulacao,
        p_seq,
        p_hora,
        p_temperatura
    );
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `utilizadorAdmin_alterar_dados` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizadorAdmin_alterar_dados`(
    IN p_idutilizador INT,
    IN p_nome VARCHAR(100),
    IN p_telemovel VARCHAR(12),
    IN p_tipo VARCHAR(9),
    IN p_email VARCHAR(50),
    IN p_datanascimento DATE,
    IN p_equipa INT
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_tipo_atual VARCHAR(9);

    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_old_email VARCHAR(50);
    DECLARE v_old_tipo VARCHAR(9);
    DECLARE v_new_email VARCHAR(50);
    DECLARE v_new_tipo VARCHAR(9);

    DECLARE v_old_role VARCHAR(50);
    DECLARE v_new_role VARCHAR(50);

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT COUNT(*), MAX(Tipo)
        INTO v_existe, v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual;

        IF v_existe = 0 OR v_tipo_atual <> 'AdminApp' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas AdminApp ou root pode alterar dados de utilizadores';
        END IF;
    END IF;

    SELECT COUNT(*), MAX(Email), MAX(Tipo)
    INTO v_existe, v_old_email, v_old_tipo
    FROM Utilizador
    WHERE IDUtilizador = p_idutilizador;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador nao existe';
    END IF;

    IF v_old_email = v_utilizador_atual THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nao pode alterar os proprios dados neste procedimento';
    END IF;

    IF v_utilizador_atual <> 'root' AND v_old_tipo = 'AdminApp' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'AdminApp nao pode alterar outro AdminApp';
    END IF;

    IF p_tipo IS NOT NULL AND p_tipo NOT IN ('AdminApp', 'Equipe', 'Analista', 'Software') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de utilizador invalido';
    END IF;

    IF v_utilizador_atual <> 'root' AND p_tipo = 'AdminApp' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'AdminApp nao pode atribuir tipo AdminApp';
    END IF;

    IF p_email IS NOT NULL AND TRIM(p_email) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email invalido';
    END IF;

    IF p_equipa IS NOT NULL AND p_equipa <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipa deve ser maior que zero';
    END IF;

    SET v_new_email = COALESCE(p_email, v_old_email);
    SET v_new_tipo = COALESCE(p_tipo, v_old_tipo);

    IF v_new_email <> v_old_email THEN
        IF EXISTS (
            SELECT 1
            FROM Utilizador
            WHERE Email = v_new_email
              AND IDUtilizador <> p_idutilizador
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Este email ja existe na tabela Utilizador';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM mysql.user
            WHERE User = v_new_email
              AND Host = '%'
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Este utilizador MySQL ja existe';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM mysql.user
            WHERE User = v_old_email
              AND Host = '%'
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Utilizador MySQL antigo nao existe';
        END IF;

        SET @sql = CONCAT(
            'RENAME USER ',
            QUOTE(v_old_email),
            '@',
            QUOTE('%'),
            ' TO ',
            QUOTE(v_new_email),
            '@',
            QUOTE('%')
        );

        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;

    IF v_new_tipo <> v_old_tipo THEN
        SET v_old_role =
            CASE v_old_tipo
                WHEN 'AdminApp' THEN 'role_AdminApp'
                WHEN 'Equipe' THEN 'role_Equipe'
                WHEN 'Analista' THEN 'role_Analista'
                WHEN 'Software' THEN 'role_Software'
            END;

        SET v_new_role =
            CASE v_new_tipo
                WHEN 'AdminApp' THEN 'role_AdminApp'
                WHEN 'Equipe' THEN 'role_Equipe'
                WHEN 'Analista' THEN 'role_Analista'
                WHEN 'Software' THEN 'role_Software'
            END;

        SET @sql = CONCAT(
            'REVOKE ',
            v_old_role,
            ' FROM ',
            QUOTE(v_new_email),
            '@',
            QUOTE('%')
        );

        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = CONCAT(
            'GRANT ',
            v_new_role,
            ' TO ',
            QUOTE(v_new_email),
            '@',
            QUOTE('%')
        );

        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = CONCAT(
            'SET DEFAULT ROLE ',
            v_new_role,
            ' FOR ',
            QUOTE(v_new_email),
            '@',
            QUOTE('%')
        );

        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;

    UPDATE Utilizador
    SET
        Nome = COALESCE(p_nome, Nome),
        Telemovel = COALESCE(p_telemovel, Telemovel),
        Tipo = v_new_tipo,
        Email = v_new_email,
        DataNascimento = COALESCE(p_datanascimento, DataNascimento),
        Equipa = COALESCE(p_equipa, Equipa)
    WHERE IDUtilizador = p_idutilizador;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `utilizador_alterar_proprios_dados` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizador_alterar_proprios_dados`(
    IN p_nome VARCHAR(100),
    IN p_telemovel VARCHAR(12),
    IN p_email VARCHAR(50),
    IN p_datanascimento DATE,
    IN p_equipa INT
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);

    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_idutilizador INT;
    DECLARE v_old_email VARCHAR(50);
    DECLARE v_new_email VARCHAR(50);

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    SELECT COUNT(*), MAX(IDUtilizador), MAX(Email)
    INTO v_existe, v_idutilizador, v_old_email
    FROM Utilizador
    WHERE Email = v_utilizador_atual;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador atual nao existe na tabela Utilizador';
    END IF;

    IF p_email IS NOT NULL AND TRIM(p_email) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email invalido';
    END IF;

    SET v_new_email = COALESCE(p_email, v_old_email);

    IF v_new_email <> v_old_email THEN
        IF EXISTS (
            SELECT 1
            FROM Utilizador
            WHERE Email = v_new_email
              AND IDUtilizador <> v_idutilizador
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Este email ja existe na tabela Utilizador';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM mysql.user
            WHERE User = v_new_email
              AND Host = '%'
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Este utilizador MySQL ja existe';
        END IF;

        SET @sql = CONCAT(
            'RENAME USER ',
            QUOTE(v_old_email),
            '@',
            QUOTE('%'),
            ' TO ',
            QUOTE(v_new_email),
            '@',
            QUOTE('%')
        );

        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;

    UPDATE Utilizador
    SET
        Nome = COALESCE(p_nome, Nome),
        Telemovel = COALESCE(p_telemovel, Telemovel),
        Email = v_new_email,
        DataNascimento = COALESCE(p_datanascimento, DataNascimento),
        Equipa = COALESCE(p_equipa, Equipa)
    WHERE IDUtilizador = v_idutilizador;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `utilizador_criar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizador_criar`(
    IN p_nome VARCHAR(100),
    IN p_telemovel VARCHAR(12),
    IN p_tipo VARCHAR(9),
    IN p_email VARCHAR(50),
    IN p_datanascimento DATE,
    IN p_equipa INT,
    IN p_password VARCHAR(255)
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_role VARCHAR(50);

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT Tipo
        INTO v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual
        LIMIT 1;

        IF v_tipo_atual IS NULL OR v_tipo_atual <> 'AdminApp' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas AdminApp ou root pode criar utilizadores';
        END IF;
    END IF;

    IF p_tipo IS NULL OR p_tipo NOT IN ('AdminApp', 'Equipe', 'Analista', 'Software') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de utilizador invalido';
    END IF;

    IF v_utilizador_atual <> 'root' AND p_tipo = 'AdminApp' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Apenas root pode criar AdminApp';
    END IF;

    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email obrigatorio';
    END IF;

    IF p_tipo = 'Equipe' AND p_equipa IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipa obrigatoria para utilizador do tipo Equipe';
    END IF;

    IF p_equipa IS NOT NULL AND p_equipa <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Equipa deve ser maior que zero';
    END IF;

    IF p_password IS NULL OR CHAR_LENGTH(p_password) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Password obrigatoria';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Utilizador
        WHERE Email = p_email
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Este email ja existe na tabela Utilizador';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM mysql.user
        WHERE User = p_email
          AND Host = '%'
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Este utilizador MySQL ja existe';
    END IF;

    SET v_role =
        CASE p_tipo
            WHEN 'AdminApp' THEN 'role_AdminApp'
            WHEN 'Equipe' THEN 'role_Equipe'
            WHEN 'Analista' THEN 'role_Analista'
            WHEN 'Software' THEN 'role_Software'
        END;

    SET @sql = CONCAT(
        'CREATE USER ',
        QUOTE(p_email),
        '@',
        QUOTE('%'),
        ' IDENTIFIED BY ',
        QUOTE(p_password)
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT(
        'GRANT ',
        v_role,
        ' TO ',
        QUOTE(p_email),
        '@',
        QUOTE('%')
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT(
        'SET DEFAULT ROLE ',
        v_role,
        ' FOR ',
        QUOTE(p_email),
        '@',
        QUOTE('%')
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    INSERT INTO Utilizador (
        Nome,
        Telemovel,
        Tipo,
        Email,
        DataNascimento,
        Equipa
    )
    VALUES (
        p_nome,
        p_telemovel,
        p_tipo,
        p_email,
        p_datanascimento,
        p_equipa
    );
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `utilizador_eliminar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `utilizador_eliminar`(
    IN p_email VARCHAR(50)
)
BEGIN
    DECLARE v_login VARCHAR(255);
    DECLARE v_host VARCHAR(255);
    DECLARE v_utilizador_atual VARCHAR(255);
    DECLARE v_tipo_atual VARCHAR(9);
    DECLARE v_email_existe INT DEFAULT 0;

    SET v_login = USER();
    SET v_host = SUBSTRING_INDEX(v_login, '@', -1);
    SET v_utilizador_atual = LEFT(v_login, LENGTH(v_login) - LENGTH(v_host) - 1);

    IF v_utilizador_atual <> 'root' THEN
        SELECT Tipo
        INTO v_tipo_atual
        FROM Utilizador
        WHERE Email = v_utilizador_atual
        LIMIT 1;

        IF v_tipo_atual IS NULL OR v_tipo_atual <> 'AdminApp' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Apenas AdminApp ou root pode eliminar utilizadores';
        END IF;
    END IF;

    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email obrigatorio';
    END IF;

    IF p_email = v_utilizador_atual THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nao pode eliminar o proprio utilizador';
    END IF;

    SELECT COUNT(*)
    INTO v_email_existe
    FROM Utilizador
    WHERE Email = p_email;

    IF v_email_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador nao existe';
    END IF;

    DELETE FROM Utilizador
    WHERE Email = p_email;

    SET @sql = CONCAT(
        'DROP USER IF EXISTS ',
        QUOTE(p_email),
        '@',
        QUOTE('%')
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;

--
-- Current Database: `Marsabirinto`
--

USE `Marsabirinto`;

--
-- Final view structure for view `v_utilizador_atual`
--

/*!50001 DROP VIEW IF EXISTS `v_utilizador_atual`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_unicode_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `marsabirinto`.`v_utilizador_atual` AS select `marsabirinto`.`utilizador`.`IDUtilizador` AS `IDUtilizador`,`marsabirinto`.`utilizador`.`Nome` AS `Nome`,`marsabirinto`.`utilizador`.`Telemovel` AS `Telemovel`,`marsabirinto`.`utilizador`.`Tipo` AS `Tipo`,`marsabirinto`.`utilizador`.`Email` AS `Email`,`marsabirinto`.`utilizador`.`DataNascimento` AS `DataNascimento`,`marsabirinto`.`utilizador`.`Equipa` AS `Equipa` from `marsabirinto`.`utilizador` where `marsabirinto`.`utilizador`.`Email` = left(user(),char_length(user()) - char_length(substring_index(user(),'@',-1)) - 1) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-04-27 18:57:29
