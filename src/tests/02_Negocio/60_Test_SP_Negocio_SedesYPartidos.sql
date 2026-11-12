/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - CarolinaCaruso
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier

 Fecha: 25/10/2026
 Archivo: 60_Test_SP_Negocio_SedesYPartidos.sql
 Objetivo: Probar los SP de 10_SP_Negocio_SedesYPartidos.sql
           (usp_RegistrarSede, usp_ModificarSede, usp_EliminarSede,
           usp_IniciarPartido y usp_FinalizarPartido),
           con casos exitosos y su evidencia y casos que no cumplen las
           validaciones. Requiere haber ejecutado 01 a 28; no depende del juego de
           datos.
           Cada caso arma sus propios datos con INSERT directos a las tablas
           (los países Argentina1, Brasil1 e Italia1, la sede "Estadio
           Nacional1" de Lima con sus 4 espacios, jugadores de los planteles,
           cinco árbitros italianos y el partido 225, Argentina1 - Brasil1, de
           octavos) y los deshace al terminar, así que se puede ejecutar más
           de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.

 Cada caso corre en su propia transacción (BEGIN TRANSACTION ... ROLLBACK)
 y en un solo lote: estos SP usan SET XACT_ABORT ON, así que un error deja
 la transacción sin poder confirmarse y SQL Server la deshace al terminar el
 lote. Por eso no hay una sola transacción para todo el test, y en un mismo
 lote puede haber casos OK pero un solo caso de error, al final.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_RegistrarSede', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'CABEZAZO', 'PENAL') HAVING COUNT(*) = 3)
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ============================================================================
   usp_RegistrarSede
   ============================================================================ */

/* RS1 (OK) Alta de una sede con sus cuatro espacios en una sola transacción.
   Esperado: la consulta del SP muestra la sede con los espacios 1 a 4 y sus
   tarifas; en la tabla quedan 4 espacios para la sede nueva.
   RS3 (ERROR) Datos de la sede que no pasan las validaciones del ABM.
   Esperado: el error 50001 lo informa Torneo.usp_SEDE_Alta, con 2
   condiciones (ya existe la sede "Estadio Nacional1", dada de alta en RS1, y
   el huso no existe); la cantidad de espacios publicitarios no cambia. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @id_sede INT;
EXEC Torneo.usp_RegistrarSede
    @nombre_estadio = 'Estadio Nacional1', @ciudad = 'Lima', @id_pais = @id_pais_per, @capacidad = 50000,
    @huso_horario = 'SA Pacific Standard Time', @tarifa_espacio_1 = 70000, @tarifa_espacio_2 = 60000,
    @tarifa_espacio_3 = 50000, @tarifa_espacio_4 = 40000, @latitud = -12.067800, @longitud = -77.033600,
    @id_sede = @id_sede OUTPUT;
SELECT 'RS1 después' AS caso, COUNT(*) AS espacios_de_la_sede FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id_sede;

DECLARE @espacios_antes INT = (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO);
BEGIN TRY
    EXEC Torneo.usp_RegistrarSede
        @nombre_estadio = 'Estadio Nacional1', @ciudad = 'Arequipa', @id_pais = @id_pais_per, @capacidad = 40000,
        @huso_horario = 'Hora del Pacífico Sur', @tarifa_espacio_1 = 1, @tarifa_espacio_2 = 1,
        @tarifa_espacio_3 = 1, @tarifa_espacio_4 = 1;
    PRINT N'RS3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RS3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RS3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'RS3 después' AS caso, @espacios_antes AS espacios_antes, COUNT(*) AS espacios_despues FROM Publicidad.ESPACIO_PUBLICITARIO;
ROLLBACK TRANSACTION;
GO

/* RS2 (ERROR) Tarifas faltantes y negativas.
   Esperado: error 50001 de Torneo.usp_RegistrarSede con 2 condiciones: las
   tarifas de los 4 espacios son obligatorias y no pueden ser negativas. No
   se crea la sede. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
BEGIN TRY
    EXEC Torneo.usp_RegistrarSede
        @nombre_estadio = 'Estadio Inca Garcilaso de la Vega1', @ciudad = 'Cusco', @id_pais = @id_pais_per, @capacidad = 20000,
        @huso_horario = 'SA Pacific Standard Time', @tarifa_espacio_1 = 1000, @tarifa_espacio_2 = -5,
        @tarifa_espacio_3 = NULL, @tarifa_espacio_4 = 1000;
    PRINT N'RS2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RS2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RS2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'RS2 después' AS caso, COUNT(*) AS sedes FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Inca Garcilaso de la Vega1';
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_ModificarSede
   ============================================================================ */

/* MS1 (OK) Cambio de la ciudad y de las tarifas de los espacios 2 y 4.
   Preparación: la sede "Estadio Nacional1" con sus 4 espacios (tarifas
   70000, 60000, 50000 y 40000).
   Esperado: la ciudad pasa a "Lima Metropolitana" y las tarifas a 70000,
   65000, 50000 y 45000 (los espacios 1 y 3 no cambian).
   MS3 (ERROR) Huso inexistente junto con un cambio de tarifa válido.
   Esperado: el error 50001 lo informa Torneo.usp_SEDE_Modificacion (el huso no
   existe) y la tarifa del espacio 1 sigue en 70000. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);

EXEC Torneo.usp_ModificarSede @id_sede = @sede, @ciudad = 'Lima Metropolitana',
     @tarifa_espacio_2 = 65000, @tarifa_espacio_4 = 45000;

BEGIN TRY
    EXEC Torneo.usp_ModificarSede @id_sede = @sede, @huso_horario = 'Hora de Marte', @tarifa_espacio_1 = 1;
    PRINT N'MS3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'MS3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'MS3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'MS3 después' AS caso, numero_espacio, tarifa_usd
FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede ORDER BY numero_espacio;
ROLLBACK TRANSACTION;
GO

/* MS2 (ERROR) Sede inexistente y tarifa negativa.
   Esperado: error 50001 de Torneo.usp_ModificarSede con 2 condiciones. */
BEGIN TRANSACTION;
BEGIN TRY
    EXEC Torneo.usp_ModificarSede @id_sede = -1, @tarifa_espacio_1 = -1;
    PRINT N'MS2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'MS2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'MS2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_IniciarPartido
   La preparación de estos casos es la sede "Estadio Nacional1", las
   selecciones Argentina1 y Brasil1 y el partido 225 entre ellas.
   ============================================================================ */

/* IP1 (ERROR) Partido sin formaciones ni árbitros.
   Esperado: error 50001 con 3 condiciones: Argentina1 y Brasil1 tienen 0
   titulares cargados, y falta designar PRINCIPAL, ASISTENTE_1, ASISTENTE_2,
   CUARTO y VAR. El partido sigue PROGRAMADO. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'PROGRAMADO');
SET @id_partido = SCOPE_IDENTITY();

BEGIN TRY
    EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;
    PRINT N'IP1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'IP1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'IP1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'IP1 después' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
ROLLBACK TRANSACTION;
GO

/* IP3 (OK) Inicio del partido con formaciones y terna completas.
   Preparación: además, los 11 titulares de cada selección (dorsales 1 a 11)
   en su formación 4-3-3, y cinco árbitros de Italia1 (país sin selección,
   para que no haya conflicto de nacionalidad) designados en los cinco roles.
   Esperado: el partido 225 pasa de PROGRAMADO a EN_JUEGO. Como no tiene
   publicidad asignada, en Mensajes aparece la advertencia "el partido
   empieza con 0 de sus 4 espacios publicitarios asignados". */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'PROGRAMADO');
SET @id_partido = SCOPE_IDENTITY();

INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_arg,  1, N'Emiliano', N'Martínez',   'ARQUERO',       '2026-06-01'),
    (@lista_arg,  2, N'Juan',     N'Foyth',      'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  3, N'Nicolás',  N'Tagliafico', 'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  4, N'Gonzalo',  N'Montiel',    'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  5, N'Leonardo', N'Balerdi',    'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  6, N'Germán',   N'Pezzella',   'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  7, N'Rodrigo',  N'De Paul',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg,  8, N'Enzo',     N'Fernández',  'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 10, N'Lionel',   N'Messi',      'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg,  9, N'Julián',   N'Álvarez',    'DELANTERO',     '2026-06-01'),
    (@lista_arg, 11, N'Ángel',    N'Di María',   'DELANTERO',     '2026-06-01');

INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_bra,  1, N'Alisson', N'Becker',    'ARQUERO',       '2026-06-01'),
    (@lista_bra,  2, N'Danilo',  N'Luiz',      'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  3, N'Gabriel', N'Magalhães', 'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  4, N'Marcos',  N'Aoás',      'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  5, N'Éder',    N'Militão',   'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  6, N'Alex',    N'Sandro',    'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  7, N'Lucas',   N'Paquetá',   'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra,  8, N'Bruno',   N'Guimarães', 'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 10, N'Rodrygo', N'Goes',      'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra,  9, N'Matheus', N'Cunha',     'DELANTERO',     '2026-06-01'),
    (@lista_bra, 11, N'Raphael', N'Dias',      'DELANTERO',     '2026-06-01');

DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, 1, posicion_habitual FROM Torneo.JUGADOR WHERE id_lista = @lista_arg;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, 1, posicion_habitual FROM Torneo.JUGADOR WHERE id_lista = @lista_bra;

DECLARE @id_pais_ita SMALLINT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_ita, N'Daniele',      N'Orsato',  'FIFA'),
    (@id_pais_ita, N'Ciro',         N'Carbone', 'FIFA'),
    (@id_pais_ita, N'Alessandro',   N'Giallatini', 'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',  'FIFA');
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
SELECT @id_partido, id_arbitro,
       CASE apellido WHEN N'Orsato' THEN 'PRINCIPAL' WHEN N'Carbone' THEN 'ASISTENTE_1'
                     WHEN N'Giallatini' THEN 'ASISTENTE_2' WHEN N'Guida' THEN 'CUARTO' ELSE 'VAR' END
FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita;

SELECT 'IP3 antes' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;
SELECT 'IP3 después' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
ROLLBACK TRANSACTION;
GO

/* IP2 (ERROR) Iniciar un partido que ya se jugó.
   Preparación: el partido 225 ya FINALIZADO 1 - 0.
   Esperado: error 50001 con 4 condiciones: el partido 225 está FINALIZADO y
   solo empieza un partido PROGRAMADO; las otras 3 son las de IP1, porque en
   esta preparación no hay formaciones ni árbitros. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, NULL, NULL, 'FINALIZADO');
SET @id_partido = SCOPE_IDENTITY();

BEGIN TRY
    EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;
    PRINT N'IP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'IP2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'IP2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_FinalizarPartido
   La preparación de estos casos es el partido 225 EN_JUEGO, con los goles
   que indica cada caso.
   ============================================================================ */

/* FP1 (ERROR) Resultado informado que no coincide con los goles registrados.
   Preparación: gol de Julián Álvarez en el minuto 30.
   Esperado: error 50001 con 1 condición: el resultado no coincide con los
   goles registrados (1 - 0). */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_arg,  9, N'Julián',  N'Álvarez',  'DELANTERO',     '2026-06-01'),
    (@lista_arg, 10, N'Lionel',  N'Messi',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 11, N'Ángel',   N'Di María', 'DELANTERO',     '2026-06-01'),
    (@lista_bra,  9, N'Matheus', N'Cunha',    'DELANTERO',     '2026-06-01'),
    (@lista_bra, 10, N'Rodrygo', N'Goes',     'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 11, N'Raphael', N'Dias',     'DELANTERO',     '2026-06-01');
DECLARE @alvarez  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @messi    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
DECLARE @di_maria INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 11);
DECLARE @cunha    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
DECLARE @rodrygo  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 10);
DECLARE @raphinha INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
DECLARE @jugada   TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @cabezazo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @alvarez, @jugada, 'PRIMER_TIEMPO', 30);

BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @goles_local = 2, @goles_visitante = 0;
    PRINT N'FP1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'FP1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'FP1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* FP2 (ERROR) Empate en eliminación directa sin definición por penales.
   Preparación: gol de Julián Álvarez en el minuto 30 y empate de Rodrygo
   en el 80.
   Esperado: error 50001 con 1 condición: el partido de eliminación directa
   terminó empatado y falta la definición por penales. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_arg,  9, N'Julián',  N'Álvarez',  'DELANTERO',     '2026-06-01'),
    (@lista_arg, 10, N'Lionel',  N'Messi',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 11, N'Ángel',   N'Di María', 'DELANTERO',     '2026-06-01'),
    (@lista_bra,  9, N'Matheus', N'Cunha',    'DELANTERO',     '2026-06-01'),
    (@lista_bra, 10, N'Rodrygo', N'Goes',     'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 11, N'Raphael', N'Dias',     'DELANTERO',     '2026-06-01');
DECLARE @alvarez  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @messi    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
DECLARE @di_maria INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 11);
DECLARE @cunha    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
DECLARE @rodrygo  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 10);
DECLARE @raphinha INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
DECLARE @jugada   TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @cabezazo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @alvarez, @jugada, 'PRIMER_TIEMPO', 30);
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @rodrygo, @cabezazo, 'SEGUNDO_TIEMPO', 80);

BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido;
    PRINT N'FP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'FP2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'FP2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* FP3 (ERROR) Asistencia mayor que la capacidad de la sede.
   Preparación: 1 - 1 (Álvarez y Rodrygo) y penales 3 - 2.
   Esperado: el error 50001 lo informa Torneo.usp_PARTIDO_Modificacion, con
   1 condición: la asistencia (60000) supera la capacidad de la sede (50000).
   El partido sigue EN_JUEGO. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_arg,  9, N'Julián',  N'Álvarez',  'DELANTERO',     '2026-06-01'),
    (@lista_arg, 10, N'Lionel',  N'Messi',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 11, N'Ángel',   N'Di María', 'DELANTERO',     '2026-06-01'),
    (@lista_bra,  9, N'Matheus', N'Cunha',    'DELANTERO',     '2026-06-01'),
    (@lista_bra, 10, N'Rodrygo', N'Goes',     'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 11, N'Raphael', N'Dias',     'DELANTERO',     '2026-06-01');
DECLARE @alvarez  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @messi    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
DECLARE @di_maria INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 11);
DECLARE @cunha    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
DECLARE @rodrygo  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 10);
DECLARE @raphinha INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
DECLARE @jugada   TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @cabezazo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @alvarez, @jugada, 'PRIMER_TIEMPO', 30);
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @rodrygo, @cabezazo, 'SEGUNDO_TIEMPO', 80);
-- Penales: convierten Álvarez, Messi y Di María por Argentina1, y Cunha y Raphinha por Brasil1.
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo) VALUES
    (@id_partido, @alvarez,  @penal, 'PENALES'),
    (@id_partido, @messi,    @penal, 'PENALES'),
    (@id_partido, @di_maria, @penal, 'PENALES'),
    (@id_partido, @cunha,    @penal, 'PENALES'),
    (@id_partido, @raphinha, @penal, 'PENALES');

BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @asistencia = 60000;
    PRINT N'FP3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'FP3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'FP3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'FP3 después' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
ROLLBACK TRANSACTION;
GO

/* FP4 (OK) Cierre del partido con el resultado de los goles registrados.
   Preparación: la misma de FP3.
   Esperado: sin informar goles, el partido queda FINALIZADO 1 - 1 y 3 - 2
   por penales, con 45000 espectadores.
   FP5 (ERROR) Finalizar un partido ya finalizado.
   Esperado: error 50001 con 1 condición: solo se finaliza un partido EN_JUEGO. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_arg,  9, N'Julián',  N'Álvarez',  'DELANTERO',     '2026-06-01'),
    (@lista_arg, 10, N'Lionel',  N'Messi',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 11, N'Ángel',   N'Di María', 'DELANTERO',     '2026-06-01'),
    (@lista_bra,  9, N'Matheus', N'Cunha',    'DELANTERO',     '2026-06-01'),
    (@lista_bra, 10, N'Rodrygo', N'Goes',     'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 11, N'Raphael', N'Dias',     'DELANTERO',     '2026-06-01');
DECLARE @alvarez  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @messi    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
DECLARE @di_maria INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 11);
DECLARE @cunha    INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
DECLARE @rodrygo  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 10);
DECLARE @raphinha INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
DECLARE @jugada   TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @cabezazo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @alvarez, @jugada, 'PRIMER_TIEMPO', 30);
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, @rodrygo, @cabezazo, 'SEGUNDO_TIEMPO', 80);
-- Penales: convierten Álvarez, Messi y Di María por Argentina1, y Cunha y Raphinha por Brasil1.
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo) VALUES
    (@id_partido, @alvarez,  @penal, 'PENALES'),
    (@id_partido, @messi,    @penal, 'PENALES'),
    (@id_partido, @di_maria, @penal, 'PENALES'),
    (@id_partido, @cunha,    @penal, 'PENALES'),
    (@id_partido, @raphinha, @penal, 'PENALES');

SELECT 'FP4 antes' AS caso, numero_partido, resultado, estado FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @asistencia = 45000;

BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido;
    PRINT N'FP5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'FP5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'FP5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_EliminarSede
   ============================================================================ */

/* ES1 (ERROR) Eliminar una sede que ya se usó.
   Preparación: la sede "Estadio Nacional1" con sus 4 espacios y el partido 225.
   Esperado: error 50001 con 1 condición: "Estadio Nacional1" tiene 1
   partido asignado (el 225). La sede y sus 4 espacios siguen en la base. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local,
                            id_seleccion_visitante, goles_local, goles_visitante, penales_local, penales_visitante, estado)
VALUES (225, @sede, 'OCTAVOS', '2026-08-20 15:00', '2026-08-20 20:00', @id_seleccion_arg, @id_seleccion_bra, NULL, NULL, NULL, NULL, 'PROGRAMADO');
SET @id_partido = SCOPE_IDENTITY();

BEGIN TRY
    EXEC Torneo.usp_EliminarSede @id_sede = @sede;
    PRINT N'ES1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'ES1 después' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE id_sede = @sede)                       AS sedes,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede)   AS espacios;
ROLLBACK TRANSACTION;
GO

/* ES2a (ERROR) Sede obligatoria.
   ES2b (ERROR) Sede inexistente.
   Esperado: un error 50001 en cada caso. */
BEGIN TRANSACTION;
BEGIN TRY
    EXEC Torneo.usp_EliminarSede @id_sede = NULL;
    PRINT N'ES2a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES2a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES2a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

BEGIN TRANSACTION;
BEGIN TRY
    EXEC Torneo.usp_EliminarSede @id_sede = -1;
    PRINT N'ES2b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES2b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES2b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* ES3 (OK) Eliminar una sede que nunca se usó.
   Preparación: la sede "Estadio Nacional1" con sus 4 espacios, sin partidos.
   Esperado: el SP la elimina con sus espacios en una sola transacción: la
   consulta del SP informa 4 espacios eliminados y después quedan 0 sedes y
   0 espacios. */
BEGIN TRANSACTION;
DECLARE @id_pais_per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Lima', @id_pais_per, 50000, 'SA Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);

SELECT 'ES3 antes' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE id_sede = @sede)                       AS sedes,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede)   AS espacios;
EXEC Torneo.usp_EliminarSede @id_sede = @sede;
SELECT 'ES3 después' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE id_sede = @sede)                       AS sedes,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede)   AS espacios;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio%1')                     AS sedes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido = 225)                            AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'Brasil1', 'Italia1')) AS paises_de_prueba,
       @@TRANCOUNT                                                                                 AS transacciones_abiertas;
GO

SET NOEXEC OFF;
GO
