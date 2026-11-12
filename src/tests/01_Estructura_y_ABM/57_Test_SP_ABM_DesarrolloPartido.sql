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
 Archivo: 57_Test_SP_ABM_DesarrolloPartido.sql
 Objetivo: Probar los SP de 07_SP_ABM_DesarrolloPartido.sql (TIPO_GOL,
           FORMACION, ALINEACION, CAMBIO, GOL y AMONESTACION), con casos
           exitosos y su evidencia y casos que no cumplen las validaciones.
           Requiere haber ejecutado 01 a 28; no depende del juego de datos.
           Arma sus propios datos con INSERT directos a las tablas: los países
           Argentina1 y Brasil1 (con su plantel de 23 jugadores) y Uruguay1
           (sin jugadores), con su director técnico, la sede "BC Place1", el
           partido 211 (Argentina1 - Brasil1, ya jugado, con un gol y una roja
           directa a Juan Foyth, dorsal 2 de Argentina1) y el partido 210
           (Argentina1 - Brasil1, de octavos), sobre el que se prueban los
           SP. Corre dentro de una transacción que se deshace al final, así
           que no deja datos y se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba. Si no da
     0, quedó algo sin deshacer.
 Los países de prueba se llaman como uno real con un 1 al final: así no
 chocan con las selecciones reales que se importen.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.usp_GOL_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'EN CONTRA', 'PENAL', 'CABEZAZO')
                  HAVING COUNT(*) = 4)
BEGIN
    RAISERROR(N'Faltan los SP o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
-- Se puede porque los SP de ABM no usan XACT_ABORT: un error de validación no
-- arruina la transacción.
BEGIN TRANSACTION;
GO


/* ============================================================================
   TIPO_GOL
   ============================================================================ */

/* TG1 (OK) Alta de un tipo de gol.
   Esperado: una fila nueva con la descripción en mayúsculas ("OLÍMPICO")
   y es_en_contra en 0. */
DECLARE @id_tipo_gol TINYINT;
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta @descripcion = 'Olímpico', @id_tipo_gol = @id_tipo_gol OUTPUT;
SELECT 'TG1 después' AS caso, id_tipo_gol, descripcion, es_en_contra FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol;
GO

/* TG2 (ERROR) Alta repetida y sin indicar si es en contra.
   Esperado: error 50001 con 2 condiciones: ya existe el tipo PENAL y hay que
   indicar si es un gol en contra. */
BEGIN TRY
    EXEC DesarrolloPartido.usp_TIPO_GOL_Alta @descripcion = 'penal', @es_en_contra = NULL;
    PRINT N'TG2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'TG2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'TG2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* TG3 (OK) Modificación de la descripción.
   Esperado: pasa a "GOL OLÍMPICO". */
DECLARE @id_tipo_gol TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'OLÍMPICO');
SELECT 'TG3 antes' AS caso, id_tipo_gol, descripcion FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol;
EXEC DesarrolloPartido.usp_TIPO_GOL_Modificacion @id_tipo_gol = @id_tipo_gol, @descripcion = 'Gol olímpico';
SELECT 'TG3 después' AS caso, id_tipo_gol, descripcion FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol;
GO


/* ============================================================================
   PREPARACIÓN, con INSERT directos (no se usan los SP de otros scripts):
   selecciones, sede, partido 211 ya jugado y partido 210.
   Esperado: el partido 211 FINALIZADO 1 - 0 (gol olímpico de Julián Álvarez,
   dorsal 9 de Argentina1) con una roja directa a Juan Foyth (dorsal 2), que
   queda suspendido para el partido 210 (ROJA DIRECTA, origen en el partido 211).
   ============================================================================ */
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_uru SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_uru INT, @lista_arg INT, @lista_bra INT;
DECLARE @sede INT, @id_partido_211 INT, @formacion_211 INT;

INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Uruguay1', 'Montevideo Standard Time');
SET @id_pais_uru = SCOPE_IDENTITY();

INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_uru, 'CONMEBOL');
SET @id_seleccion_uru = SCOPE_IDENTITY();

INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @lista_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_bra, '2026-06-01');
SET @lista_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_uru, '2026-06-01');

INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel',  N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',   N'Ancelotti', 'DIRECTOR_TECNICO'),
    (@id_seleccion_uru, N'Marcelo', N'Bielsa',    'DIRECTOR_TECNICO');

INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_arg,  1, N'Emiliano', N'Martínez',     'ARQUERO',       '2026-06-01'),
    (@lista_arg, 12, N'Gerónimo', N'Rulli',        'ARQUERO',       '2026-06-01'),
    (@lista_arg, 23, N'Walter',   N'Benítez',      'ARQUERO',       '2026-06-01'),
    (@lista_arg,  2, N'Juan',     N'Foyth',        'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  3, N'Nicolás',  N'Tagliafico',   'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  4, N'Gonzalo',  N'Montiel',      'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  5, N'Leonardo', N'Balerdi',      'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  6, N'Germán',   N'Pezzella',     'DEFENSOR',      '2026-06-01'),
    (@lista_arg, 13, N'Cristian', N'Romero',       'DEFENSOR',      '2026-06-01'),
    (@lista_arg, 14, N'Lisandro', N'Martínez',     'DEFENSOR',      '2026-06-01'),
    (@lista_arg, 15, N'Nicolás',  N'Otamendi',     'DEFENSOR',      '2026-06-01'),
    (@lista_arg,  7, N'Rodrigo',  N'De Paul',      'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg,  8, N'Enzo',     N'Fernández',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 10, N'Lionel',   N'Messi',        'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 16, N'Thiago',   N'Almada',       'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 17, N'Leandro',  N'Paredes',      'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg, 18, N'Alexis',   N'Mac Allister', 'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_arg,  9, N'Julián',   N'Álvarez',      'DELANTERO',     '2026-06-01'),
    (@lista_arg, 11, N'Ángel',    N'Di María',     'DELANTERO',     '2026-06-01'),
    (@lista_arg, 19, N'Nicolás',  N'González',     'DELANTERO',     '2026-06-01'),
    (@lista_arg, 20, N'Giuliano', N'Simeone',      'DELANTERO',     '2026-06-01'),
    (@lista_arg, 21, N'Paulo',    N'Dybala',       'DELANTERO',     '2026-06-01'),
    (@lista_arg, 22, N'Lautaro',  N'Martínez',     'DELANTERO',     '2026-06-01');

INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@lista_bra,  1, N'Alisson',     N'Becker',     'ARQUERO',       '2026-06-01'),
    (@lista_bra, 12, N'Ederson',     N'Moraes',     'ARQUERO',       '2026-06-01'),
    (@lista_bra, 23, N'Bento',       N'Krepski',    'ARQUERO',       '2026-06-01'),
    (@lista_bra,  2, N'Danilo',      N'Luiz',       'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  3, N'Gabriel',     N'Magalhães',  'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  4, N'Marcos',      N'Aoás',       'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  5, N'Éder',        N'Militão',    'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  6, N'Alex',        N'Sandro',     'DEFENSOR',      '2026-06-01'),
    (@lista_bra, 13, N'Wesley',      N'França',     'DEFENSOR',      '2026-06-01'),
    (@lista_bra, 14, N'Lucas',       N'Beraldo',    'DEFENSOR',      '2026-06-01'),
    (@lista_bra, 15, N'Douglas',     N'Santos',     'DEFENSOR',      '2026-06-01'),
    (@lista_bra,  7, N'Lucas',       N'Paquetá',    'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra,  8, N'Bruno',       N'Guimarães',  'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 10, N'Rodrygo',     N'Goes',       'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 16, N'André',       N'Trindade',   'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 17, N'Joelinton',   N'Lira',       'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra, 18, N'Gerson',      N'Santos',     'MEDIOCAMPISTA', '2026-06-01'),
    (@lista_bra,  9, N'Matheus',     N'Cunha',      'DELANTERO',     '2026-06-01'),
    (@lista_bra, 11, N'Raphael',     N'Dias',       'DELANTERO',     '2026-06-01'),
    (@lista_bra, 19, N'Vinícius',    N'Júnior',     'DELANTERO',     '2026-06-01'),
    (@lista_bra, 20, N'Gabriel',     N'Martinelli', 'DELANTERO',     '2026-06-01'),
    (@lista_bra, 21, N'Richarlison', N'Andrade',    'DELANTERO',     '2026-06-01'),
    (@lista_bra, 22, N'Estêvão',     N'Willian',    'DELANTERO',     '2026-06-01');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();

-- Partido 211 (dieciseisavos, 05/08/2026), ya jugado: Argentina1 alineó a
-- Foyth (2) y Álvarez (9); gol olímpico de Álvarez y roja directa a Foyth.
DECLARE @foyth   INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 2);
DECLARE @alvarez INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'GOL OLÍMPICO');

INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (211, @sede, 'DIECISEISAVOS', '2026-08-04 19:00', '2026-08-05 02:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_211 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_211, @id_seleccion_arg, '4-4-2');
SET @formacion_211 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha) VALUES
    (@formacion_211, @foyth,   1, 'DEFENSOR'),
    (@formacion_211, @alvarez, 1, 'DELANTERO');
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido_211, @alvarez, @tipo, 'PRIMER_TIEMPO', 20);
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_211, @foyth, 'ROJA', 89, 'Juego brusco grave');

-- Partido 210 (octavos, 10/08/2026), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (210, @sede, 'OCTAVOS', '2026-08-09 19:00', '2026-08-10 02:00', @id_seleccion_arg, @id_seleccion_bra);

SELECT 'Preparación' AS caso, numero_partido, seleccion_local, resultado, seleccion_visitante, estado
FROM Torneo.vw_Fixture WHERE numero_partido IN (210, 211) ORDER BY numero_partido;

SELECT 'Preparación' AS caso, s.motivo, s.numero_partido_origen, j.dorsal, j.apellido
FROM DesarrolloPartido.fn_JugadoresSuspendidos((SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210)) AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador;
GO


/* ============================================================================
   TIPO_GOL (casos que necesitan goles registrados)
   ============================================================================ */

/* TG4 (ERROR) Cambiar la marca de "en contra" de un tipo con goles.
   Esperado: error 50001 con 1 condición: hay goles de este tipo (el gol del
   partido 211) y cambiar si es en contra alteraría sus resultados. */
DECLARE @id_tipo_gol TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'GOL OLÍMPICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_TIPO_GOL_Modificacion @id_tipo_gol = @id_tipo_gol, @es_en_contra = 1;
    PRINT N'TG4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'TG4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'TG4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* TG5 (ERROR) Baja de un tipo con goles.
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   DesarrolloPartido.GOL (el gol del partido 211). */
DECLARE @id_tipo_gol TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'GOL OLÍMPICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_TIPO_GOL_Baja @id_tipo_gol = @id_tipo_gol;
    PRINT N'TG5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'TG5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'TG5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

-- TG6 (baja del tipo GOL OLÍMPICO) se prueba al final, después de borrar el gol del partido 211.


/* ============================================================================
   FORMACION
   ============================================================================ */

/* F1 (OK) Alta de la formación de Argentina1.
   Esperado: una formación 4-2-3-1 de Argentina1 para el partido 210. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_formacion INT;
EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @id_seleccion_xda,
    @esquema_tactico = '4-2-3-1', @id_formacion = @id_formacion OUTPUT;
SELECT 'F1 después' AS caso, id_formacion, id_partido, id_seleccion, esquema_tactico FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
GO

/* F2 (ERROR) Selección que no juega el partido y esquema que no suma 10.
   Esperado: error 50001 con 2 condiciones: Uruguay1 no juega ese partido y el
   esquema 4-4-3 no suma 10 jugadores de campo. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_uru INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Uruguay1');
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @id_seleccion_uru, @esquema_tactico = '4-4-3';
    PRINT N'F2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* F3 (ERROR) Formación para un partido ya jugado, repetida y con esquema mal escrito.
   Esperado: error 50001 con 3 condiciones: el partido 211 está FINALIZADO,
   Argentina1 ya tiene formación para ese partido y el esquema 4-x-3 no es válido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 211);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @id_seleccion_xda, @esquema_tactico = '4-x-3';
    PRINT N'F3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* F4 (OK) Modificación del esquema.
   Esperado: Argentina1 pasa de 4-2-3-1 a 4-3-3. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                   WHERE p.numero_partido = 210);
SELECT 'F4 antes' AS caso, id_formacion, esquema_tactico FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
EXEC DesarrolloPartido.usp_FORMACION_Modificacion @id_formacion = @id_formacion, @esquema_tactico = '4-3-3';
SELECT 'F4 después' AS caso, id_formacion, esquema_tactico FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
GO

/* F5 (ERROR) Modificación de la formación de un partido terminado, con esquema incompleto.
   Esperado: error 50001 con 2 condiciones: el partido 211 ya terminó y el
   esquema 3-3 no suma 10. */
DECLARE @id_formacion INT = (SELECT TOP (1) f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                   WHERE p.numero_partido = 211);
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Modificacion @id_formacion = @id_formacion, @esquema_tactico = '3-3';
    PRINT N'F5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* F6 (OK) Baja de una formación sin alineaciones.
   Preparación: con un INSERT, una formación 4-4-2 de Brasil1 para el partido
   210 (la que se usa después se carga en la preparación de CAMBIO).
   Esperado: 2 formaciones del partido 210 antes y 1 después (queda la de Argentina1).
   F7 (ERROR) Baja de la misma formación otra vez.
   Esperado: error 50001 con 1 condición: no existe una formación con ese id. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_formacion INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_xdb, '4-4-2');
SET @id_formacion = SCOPE_IDENTITY();

SELECT 'F6 antes' AS caso, COUNT(*) AS formaciones_del_partido FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;
EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id_formacion;
SELECT 'F6 después' AS caso, COUNT(*) AS formaciones_del_partido FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;

BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id_formacion;
    PRINT N'F7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   ALINEACION (formación de Argentina1)
   ============================================================================ */

/* A1 (OK) Alta de un titular y de un suplente.
   Preparación: con un INSERT, 10 titulares (dorsales 1 y 3 a 11) y 4
   suplentes (12, 13, 15 y 16) en la formación de Argentina1. Foyth (dorsal
   2), suspendido, no se incluye.
   Esperado: 14 alineados antes; después, 11 titulares (se suma Nicolás
   González, dorsal 19) y 5 suplentes (se suma Leandro Paredes, dorsal 17). */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                         WHERE f.id_formacion = @id_formacion);

INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @id_formacion, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR
WHERE id_lista = @id_lista AND dorsal IN (1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16);

SELECT 'A1 antes' AS caso, COUNT(*) AS alineados FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;

DECLARE @gonzalez INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 19);
DECLARE @paredes  INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 17);
EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @gonzalez,
    @es_titular = 1, @posicion_en_cancha = 'DELANTERO';
EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @paredes, @es_titular = 0;

SELECT 'A1 después' AS caso, IIF(a.es_titular = 1, 'TITULAR', 'SUPLENTE') AS condicion, COUNT(*) AS jugadores,
       STRING_AGG(CAST(j.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY j.dorsal) AS dorsales
FROM DesarrolloPartido.ALINEACION AS a
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE a.id_formacion = @id_formacion
GROUP BY a.es_titular;
GO

/* A2 (ERROR) Un jugador suspendido en el banco.
   Esperado: error 50001 con 1 condición: el dorsal 2 de Argentina1 está suspendido
   para este partido (ROJA DIRECTA en el partido 211). */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_xda_2 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                                 INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                                 WHERE f.id_formacion = @id_formacion AND j.dorsal = 2);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @id_jugador_xda_2, @es_titular = 0;
    PRINT N'A2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'A2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'A2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* A3 (ERROR) Un jugador de otra selección como duodécimo titular y sin posición.
   Esperado: error 50001 con 3 condiciones: el jugador (dorsal 9 de Brasil1) no
   es de la selección de la formación, un titular necesita su posición en
   cancha y la formación ya tiene sus 11 titulares. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_xdb_9 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                                 INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                                 INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Brasil1' AND j.dorsal = 9);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @id_jugador_xdb_9, @es_titular = 1;
    PRINT N'A3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'A3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'A3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* A4 (ERROR) Un jugador que ya figura en la formación.
   Esperado: error 50001 con 1 condición: el jugador ya figura en la formación. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_xda_12 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                                  INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                                  WHERE f.id_formacion = @id_formacion AND j.dorsal = 12);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @id_jugador_xda_12, @es_titular = 0;
    PRINT N'A4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'A4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'A4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* A5 (OK) El dorsal 11 pasa al banco y el 15 entra de titular.
   Esperado: siguen 11 titulares; el 11 queda SUPLENTE y el 15 TITULAR como
   DEFENSOR. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_dorsal_11 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                                     WHERE a.id_formacion = @id_formacion AND j.dorsal = 11);
DECLARE @id_jugador_dorsal_15 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                                     WHERE a.id_formacion = @id_formacion AND j.dorsal = 15);

SELECT 'A5 antes' AS caso, j.dorsal, a.es_titular, a.posicion_en_cancha
FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE a.id_formacion = @id_formacion AND j.dorsal IN (11, 15);

EXEC DesarrolloPartido.usp_ALINEACION_Modificacion @id_formacion = @id_formacion, @id_jugador = @id_jugador_dorsal_11, @es_titular = 0;
EXEC DesarrolloPartido.usp_ALINEACION_Modificacion @id_formacion = @id_formacion, @id_jugador = @id_jugador_dorsal_15,
    @es_titular = 1, @posicion_en_cancha = 'defensor';

SELECT 'A5 después' AS caso, j.dorsal, a.es_titular, a.posicion_en_cancha,
       (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion AND es_titular = 1) AS titulares
FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE a.id_formacion = @id_formacion AND j.dorsal IN (11, 15);
GO

/* A6 (ERROR) Un duodécimo titular con una posición demasiado larga.
   Esperado: error 50001 con 2 condiciones: la posición supera los 30
   caracteres y la formación ya tiene sus 11 titulares. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_dorsal_13 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                                     WHERE a.id_formacion = @id_formacion AND j.dorsal = 13);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Modificacion @id_formacion = @id_formacion, @id_jugador = @id_jugador_dorsal_13,
        @es_titular = 1, @posicion_en_cancha = 'Defensor central por la izquierda con salida';
    PRINT N'A6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'A6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'A6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* A7 (OK) Baja de un suplente sin eventos.
   Esperado: 16 alineados antes y 15 después (sale el dorsal 13). */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_dorsal_13 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                                     WHERE a.id_formacion = @id_formacion AND j.dorsal = 13);
SELECT 'A7 antes' AS caso, COUNT(*) AS alineados FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;
EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @id_jugador_dorsal_13;
SELECT 'A7 después' AS caso, COUNT(*) AS alineados FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;
GO

/* A8 (ERROR) Baja del mismo suplente otra vez.
   Esperado: error 50001 con 1 condición: el jugador (dorsal 13) no figura en
   esa formación. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @id_jugador_xda_13 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                                  INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                                  WHERE f.id_formacion = @id_formacion AND j.dorsal = 13);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @id_jugador_xda_13;
    PRINT N'A8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'A8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'A8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* F8 (ERROR) Baja de una formación con jugadores alineados.
   Esperado: error 50001 con 1 condición: a la formación de Argentina1 la referencian
   15 registros de DesarrolloPartido.ALINEACION. La formación sigue existiendo. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id_formacion;
    PRINT N'F8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'F8 después' AS caso, COUNT(*) AS formaciones FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
GO


/* ============================================================================
   PREPARACIÓN, con INSERT directos: formación 4-3-3 de Brasil1 (titulares
   1 a 5, 7 a 11 y 19; suplentes los demás hasta el 20) y el partido 210
   pasa a EN_JUEGO.
   ============================================================================ */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_formacion INT;

INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_xdb, '4-3-3');
SET @id_formacion = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @id_formacion, j.id_jugador,
       IIF(j.dorsal IN (1, 2, 3, 4, 5, 7, 8, 10, 9, 11, 19), 1, 0),
       IIF(j.dorsal IN (1, 2, 3, 4, 5, 7, 8, 10, 9, 11, 19), j.posicion_habitual, NULL)
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal <= 20;

UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;

SELECT 'Preparación' AS caso, numero_partido, estado,
       (SELECT COUNT(*) FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido) AS formaciones
FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO


/* ============================================================================
   CAMBIO (Argentina1)
   ============================================================================ */

/* CA1 (OK) Alta de un cambio.
   Esperado: en el minuto 60 sale el dorsal 19 y entra el 16, por motivo TACTICO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 19);
DECLARE @entra INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 16);
DECLARE @id_cambio INT;
EXEC DesarrolloPartido.usp_CAMBIO_Alta @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
    @minuto = 60, @motivo = 'tactico', @id_cambio = @id_cambio OUTPUT;
SELECT 'CA1 después' AS caso, c.id_cambio, js.dorsal AS sale, je.dorsal AS entra, c.minuto, c.motivo
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.JUGADOR AS je ON je.id_jugador = c.id_jugador_entra
WHERE c.id_cambio = @id_cambio;
GO

/* CA2 (ERROR) Cambio con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: el que entra (dorsal 3) es
   titular, el que sale (dorsal 19) ya había salido, el minuto 121 está fuera
   de rango y el motivo CANSANCIO no es válido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 19);
DECLARE @entra INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 3);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Alta @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
        @minuto = 121, @motivo = 'CANSANCIO';
    PRINT N'CA2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CA2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CA2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* CA3 (ERROR) Jugadores de selecciones distintas y entretiempo en un minuto que no corresponde.
   Esperado: error 50001 con 2 condiciones: los dos jugadores tienen que ser
   de la misma selección y un cambio en el entretiempo va en el minuto 46, 91
   o 106. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 9);
DECLARE @entra INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 12);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Alta @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
        @minuto = 50, @motivo = 'TACTICO', @en_entretiempo = 1;
    PRINT N'CA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CA3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CA3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* CA4 (OK) Modificación del minuto y del motivo.
   Esperado: el cambio pasa del minuto 60 al 62 y el motivo a LESION. */
DECLARE @id_cambio INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
SELECT 'CA4 antes' AS caso, id_cambio, minuto, motivo FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id_cambio;
EXEC DesarrolloPartido.usp_CAMBIO_Modificacion @id_cambio = @id_cambio, @minuto = 62, @motivo = 'LESION';
SELECT 'CA4 después' AS caso, id_cambio, minuto, motivo FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id_cambio;
GO

/* CA5 (ERROR) Modificación a entretiempo en el minuto 62 con adicional fuera de rango.
   Esperado: error 50001 con 2 condiciones: el adicional no puede superar los
   30 minutos y un cambio en el entretiempo va en el minuto 46, 91 o 106. */
DECLARE @id_cambio INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Modificacion @id_cambio = @id_cambio, @en_entretiempo = 1, @minuto_adicional = 31;
    PRINT N'CA5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CA5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CA5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   GOL
   ============================================================================ */

/* G1 (OK) Gol del dorsal 16 de Argentina1 (entró en el 62) con asistencia del 7.
   Esperado: un gol en el minuto 70, SEGUNDO_TIEMPO, tipo JUGADA; el marcador
   según los goles queda 1 - 0. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 16);
DECLARE @asiste INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 7);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @id_gol INT;
EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'segundo_tiempo', @minuto = 70, @id_jugador_asistencia = @asiste, @id_gol = @id_gol OUTPUT;
SELECT 'G1 después' AS caso, g.id_gol, ja.dorsal AS autor, js.dorsal AS asistencia, g.periodo, g.minuto, m.goles_local, m.goles_visitante
FROM DesarrolloPartido.GOL AS g
INNER JOIN Torneo.JUGADOR AS ja ON ja.id_jugador = g.id_jugador_autor
LEFT JOIN Torneo.JUGADOR AS js ON js.id_jugador = g.id_jugador_asistencia
CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(g.id_partido) AS m
WHERE g.id_gol = @id_gol;
GO

/* G2 (ERROR) Gol de un jugador que no juega el partido, tipo inexistente y penal con minuto.
   Esperado: error 50001 con 3 condiciones: el autor (dorsal 23 de Brasil1, que
   no está en su formación) no figura en la formación, no existe el tipo de
   gol 99 y el minuto no corresponde al período PENALES. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_jugador_xdb_23 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 23);
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @id_jugador_xdb_23, @id_tipo_gol = 99,
        @periodo = 'PENALES', @minuto = 50;
    PRINT N'G2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'G2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'G2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* G3 (ERROR) Adicional sin minutos agregados y asistencia del rival.
   Esperado: error 50001 con 2 condiciones: el minuto no corresponde al
   período ADICIONALES (falta el adicional) y el que asiste tiene que ser de
   la misma selección que el autor. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xda AND j.dorsal = 9);
DECLARE @asiste INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 9);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'ADICIONALES', @minuto = 90, @minuto_adicional = 0, @id_jugador_asistencia = @asiste;
    PRINT N'G3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'G3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'G3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* G4 (ERROR) Gol en contra con asistencia.
   Esperado: error 50001 con 1 condición: un gol en contra no tiene asistencia. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 3);
DECLARE @asiste INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 4);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'PRIMER_TIEMPO', @minuto = 20, @id_jugador_asistencia = @asiste;
    PRINT N'G4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'G4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'G4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* G5 (OK) Modificación del minuto.
   Esperado: el gol pasa del minuto 70 al 75. */
DECLARE @id_gol INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 210 ORDER BY g.id_gol);
SELECT 'G5 antes' AS caso, id_gol, periodo, minuto FROM DesarrolloPartido.GOL WHERE id_gol = @id_gol;
EXEC DesarrolloPartido.usp_GOL_Modificacion @id_gol = @id_gol, @minuto = 75;
SELECT 'G5 después' AS caso, id_gol, periodo, minuto FROM DesarrolloPartido.GOL WHERE id_gol = @id_gol;
GO

/* G6 (ERROR) Período de alargue con un minuto del segundo tiempo.
   Esperado: error 50001 con 1 condición: el minuto no corresponde al período. */
DECLARE @id_gol INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 210 ORDER BY g.id_gol);
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Modificacion @id_gol = @id_gol, @periodo = 'ALARGUE';
    PRINT N'G6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'G6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'G6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* CA6 (ERROR) Baja de un cambio cuyo jugador ya hizo un gol.
   Esperado: error 50001 con 1 condición: el jugador que entró (dorsal 16)
   tiene 1 registro de DesarrolloPartido.GOL en el partido. */
DECLARE @id_cambio INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Baja @id_cambio = @id_cambio;
    PRINT N'CA6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CA6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CA6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* A9 (ERROR) Baja de un jugador con eventos en el partido.
   Esperado: error 50001 con 2 condiciones: el dorsal 16 de Argentina1 tiene 1
   registro de DesarrolloPartido.CAMBIO (entró en el 62) y 1 de
   DesarrolloPartido.GOL (el de G1) en el partido. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210 AND f.id_seleccion = p.id_seleccion_local);
DECLARE @id_jugador_dorsal_16 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                                     WHERE a.id_formacion = @id_formacion AND j.dorsal = 16);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @id_jugador_dorsal_16;
    PRINT N'A9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'A9: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'A9: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* G7 (OK) Baja de un gol con el partido EN_JUEGO.
   Esperado: 1 gol antes y 0 después; el marcador según los goles vuelve a 0 - 0. */
DECLARE @id_gol INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 210 ORDER BY g.id_gol);
DECLARE @id_partido INT = (SELECT id_partido FROM DesarrolloPartido.GOL WHERE id_gol = @id_gol);
SELECT 'G7 antes' AS caso, goles_registrados, goles_local, goles_visitante FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);
EXEC DesarrolloPartido.usp_GOL_Baja @id_gol = @id_gol;
SELECT 'G7 después' AS caso, goles_registrados, goles_local, goles_visitante FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);
GO

/* CA7 (OK) Baja de un cambio cuyo jugador ya no tiene eventos.
   Esperado: después de G7 el dorsal 16 ya no tiene goles, así que el cambio
   del minuto 62 se puede borrar: 1 cambio del partido 210 antes y 0 después. */
DECLARE @id_cambio INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
DECLARE @id_partido INT = (SELECT id_partido FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id_cambio);
SELECT 'CA7 antes' AS caso, COUNT(*) AS cambios FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido;
EXEC DesarrolloPartido.usp_CAMBIO_Baja @id_cambio = @id_cambio;
SELECT 'CA7 después' AS caso, COUNT(*) AS cambios FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido;
GO

/* G8 (ERROR) Baja de un gol de un partido finalizado.
   Esperado: error 50001 con 1 condición: el partido 211 está FINALIZADO y un
   gol solo se quita con el partido EN_JUEGO. */
DECLARE @id_gol INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 211);
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Baja @id_gol = @id_gol;
    PRINT N'G8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'G8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'G8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   AMONESTACION (Brasil1)
   ============================================================================ */

/* AM1 (OK) Amarilla al dorsal 5 de Brasil1.
   Esperado: una tarjeta AMARILLA en el minuto 30, sin doble amarilla. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 5);
DECLARE @id_amonestacion INT;
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'amarilla', @minuto = 30,
    @motivo = 'Falta táctica', @id_jugador = @id_jugador, @id_amonestacion = @id_amonestacion OUTPUT;
SELECT 'AM1 después' AS caso, id_amonestacion, tipo_tarjeta, es_doble_amarilla, minuto, motivo FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_amonestacion;
GO

/* AM2 (ERROR) Tarjeta con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: la tarjeta la recibe exactamente
   un jugador o una persona del cuerpo técnico, el tipo AZUL no es válido, el
   minuto 125 está fuera de rango y el motivo es obligatorio. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 5);
DECLARE @id_persona_ct INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion_xdb AND rol = 'DIRECTOR_TECNICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'AZUL', @minuto = 125,
        @motivo = ' ', @id_jugador = @id_jugador, @id_persona_ct = @id_persona_ct;
    PRINT N'AM2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AM2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AM2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AM3 (ERROR) Roja por doble amarilla con una sola amarilla.
   Esperado: error 50001 con 1 condición: una roja por doble amarilla
   necesita las dos amarillas registradas antes. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 5);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 35,
        @motivo = 'Doble amarilla', @id_jugador = @id_jugador, @es_doble_amarilla = 1;
    PRINT N'AM3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AM3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AM3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AM4 (OK) Segunda amarilla y roja por doble amarilla, cargadas con el ABM.
   Esperado: el dorsal 5 queda con dos amarillas (30 y 40) y una roja con
   es_doble_amarilla = 1 en el minuto 40. (La roja automática la agrega el SP
   de negocio usp_RegistrarAmonestacion; acá se carga a mano.) */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 5);
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 40,
    @motivo = 'Mano intencional', @id_jugador = @id_jugador;
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 40,
    @motivo = 'Doble amarilla', @id_jugador = @id_jugador, @es_doble_amarilla = 1;
SELECT 'AM4 después' AS caso, id_amonestacion, tipo_tarjeta, es_doble_amarilla, minuto, motivo
FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND id_jugador = @id_jugador ORDER BY id_amonestacion;
GO

/* AM5 (ERROR) Tarjeta a un jugador ya expulsado.
   Esperado: error 50001 con 1 condición: el receptor ya había sido
   expulsado en este partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_seleccion_xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_xdb AND j.dorsal = 5);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 50,
        @motivo = 'Insultos', @id_jugador = @id_jugador;
    PRINT N'AM5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AM5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AM5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AM6 (ERROR) Baja de una amarilla que forma parte de la doble amarilla.
   Esperado: error 50001 con 1 condición: primero hay que dar de baja la roja. */
DECLARE @id_amonestacion INT = (SELECT TOP (1) a.id_amonestacion FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                   WHERE p.numero_partido = 210 AND a.tipo_tarjeta = 'AMARILLA' ORDER BY a.id_amonestacion);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id_amonestacion;
    PRINT N'AM6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AM6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AM6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AM7 (OK) Modificación del motivo de la primera amarilla.
   Esperado: el motivo pasa a "Falta táctica para cortar un contraataque". */
DECLARE @id_amonestacion INT = (SELECT TOP (1) a.id_amonestacion FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                   WHERE p.numero_partido = 210 AND a.tipo_tarjeta = 'AMARILLA' ORDER BY a.id_amonestacion);
SELECT 'AM7 antes' AS caso, id_amonestacion, motivo FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_amonestacion;
EXEC DesarrolloPartido.usp_AMONESTACION_Modificacion @id_amonestacion = @id_amonestacion, @motivo = 'Falta táctica para cortar un contraataque';
SELECT 'AM7 después' AS caso, id_amonestacion, motivo FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_amonestacion;
GO

/* AM8 (ERROR) Tarjeta al cuerpo técnico de una selección que no juega.
   Esperado: error 50001 con 1 condición: el director técnico de Uruguay1 no es
   del cuerpo técnico de una de las selecciones del partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_persona_ct INT = (SELECT ct.id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                   WHERE p.nombre = 'Uruguay1' AND ct.rol = 'DIRECTOR_TECNICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 55,
        @motivo = 'Protestar', @id_persona_ct = @id_persona_ct;
    PRINT N'AM8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AM8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AM8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AM9 (OK) Baja de la roja y después de una amarilla.
   Esperado: 3 tarjetas antes y 1 después. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_amonestacion INT;
SELECT 'AM9 antes' AS caso, COUNT(*) AS tarjetas FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido;
SET @id_amonestacion = (SELECT id_amonestacion FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND tipo_tarjeta = 'ROJA');
EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id_amonestacion;
SET @id_amonestacion = (SELECT MAX(id_amonestacion) FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido);
EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id_amonestacion;
SELECT 'AM9 después' AS caso, COUNT(*) AS tarjetas FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido;
GO

/* AM10 (ERROR) Modificación con minuto, adicional y motivo fuera de rango.
   Esperado: error 50001 con 3 condiciones: el minuto 125 está fuera de rango,
   el adicional no puede superar los 30 minutos y el motivo supera los 200
   caracteres. La tarjeta que quedó (la amarilla del minuto 30) no cambia. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id_amonestacion INT = (SELECT MIN(id_amonestacion) FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido);
DECLARE @motivo_largo VARCHAR(400) = REPLICATE('Motivo demasiado largo. ', 10);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Modificacion @id_amonestacion = @id_amonestacion, @minuto = 125,
        @minuto_adicional = 31, @motivo = @motivo_largo;
    PRINT N'AM10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AM10: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AM10: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'AM10 después' AS caso, id_amonestacion, minuto, minuto_adicional, motivo
FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_amonestacion;
GO


/* ============================================================================
   TIPO_GOL (baja del tipo GOL OLÍMPICO)
   ============================================================================ */

/* TG6 (OK) Baja del tipo GOL OLÍMPICO.
   Preparación: se borra con un DELETE el gol del partido 211, que es el único
   que usa ese tipo.
   Esperado: 1 tipo GOL OLÍMPICO antes y 0 después. */
DELETE FROM DesarrolloPartido.GOL
WHERE id_partido = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 211);

DECLARE @id_tipo_gol TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'GOL OLÍMPICO');
SELECT 'TG6 antes' AS caso, COUNT(*) AS tipos_gol_olimpico FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'GOL OLÍMPICO';
EXEC DesarrolloPartido.usp_TIPO_GOL_Baja @id_tipo_gol = @id_tipo_gol;
SELECT 'TG6 después' AS caso, COUNT(*) AS tipos_gol_olimpico FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'GOL OLÍMPICO';
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
ROLLBACK TRANSACTION;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (210, 211))                     AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DesarrolloPartido.TIPO_GOL WHERE descripcion LIKE '%OLÍMPICO')         AS tipos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'Brasil1', 'Uruguay1')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'BC Place1')                        AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
