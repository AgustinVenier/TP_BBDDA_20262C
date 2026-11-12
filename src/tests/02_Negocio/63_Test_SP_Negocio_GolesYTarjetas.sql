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
 Archivo: 63_Test_SP_Negocio_GolesYTarjetas.sql
 Objetivo: Probar los SP de 13_SP_Negocio_GolesYTarjetas.sql
           (usp_RegistrarGol y usp_RegistrarAmonestacion): goles con autor y
           asistente en cancha, gol en contra, alargue y penales solo con
           empate; tarjetas, roja automática por doble amarilla y cálculo de
           la suspensión (doble amarilla, roja directa y acumulación de
           amarillas en partidos distintos).
           Requiere haber ejecutado 01 a 28; no depende del juego de datos.
           Cada caso arma sus propios datos con INSERT directos a las tablas:
           los países Argentina1 y Brasil1 con su plantel de 23 jugadores, la
           sede "Arrowhead Stadium1", el partido 241 (Argentina1 - Brasil1, de
           dieciseisavos, ya jugado, con una amarilla a Germán Pezzella,
           dorsal 6 de Argentina1) y el partido 240 (Argentina1 - Brasil1, de
           octavos, EN_JUEGO, con las dos formaciones). Los deshace al
           terminar, así que se puede ejecutar más de una vez.
           Los casos obligatorios se prueban acá con datos propios.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
     Las suspensiones que genera una tarjeta se informan en Mensajes
     ("Suspensión: ...") y en la consulta del SP.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.

 Cada caso corre en su propia transacción (BEGIN TRANSACTION ... ROLLBACK)
 y en un solo lote: estos SP usan SET XACT_ABORT ON, así que un error deja
 la transacción sin poder confirmarse y SQL Server la deshace al terminar el
 lote. Por eso no hay una sola transacción para todo el test, y en un mismo
 lote puede haber casos OK pero un solo caso de error, al final. Cada lote
 vuelve a cargar con INSERT lo que dejaron los casos OK anteriores.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.usp_RegistrarAmonestacion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'EN CONTRA', 'PENAL', 'CABEZAZO')
                  HAVING COUNT(*) = 4)
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Planteles de 23 jugadores que cargan los casos. Son tablas temporales, no
-- tablas de la base: la transacción de cada caso no las borra.
DROP TABLE IF EXISTS #plantel_argentina;
CREATE TABLE #plantel_argentina (dorsal TINYINT, nombre NVARCHAR(60), apellido NVARCHAR(60), posicion VARCHAR(15));
INSERT INTO #plantel_argentina (dorsal, nombre, apellido, posicion) VALUES
    ( 1, N'Emiliano', N'Martínez',     'ARQUERO'),
    (12, N'Gerónimo', N'Rulli',        'ARQUERO'),
    (23, N'Walter',   N'Benítez',      'ARQUERO'),
    ( 2, N'Juan',     N'Foyth',        'DEFENSOR'),
    ( 3, N'Nicolás',  N'Tagliafico',   'DEFENSOR'),
    ( 4, N'Gonzalo',  N'Montiel',      'DEFENSOR'),
    ( 5, N'Leonardo', N'Balerdi',      'DEFENSOR'),
    ( 6, N'Germán',   N'Pezzella',     'DEFENSOR'),
    (13, N'Cristian', N'Romero',       'DEFENSOR'),
    (14, N'Lisandro', N'Martínez',     'DEFENSOR'),
    (15, N'Nicolás',  N'Otamendi',     'DEFENSOR'),
    ( 7, N'Rodrigo',  N'De Paul',      'MEDIOCAMPISTA'),
    ( 8, N'Enzo',     N'Fernández',    'MEDIOCAMPISTA'),
    (10, N'Lionel',   N'Messi',        'MEDIOCAMPISTA'),
    (16, N'Thiago',   N'Almada',       'MEDIOCAMPISTA'),
    (17, N'Leandro',  N'Paredes',      'MEDIOCAMPISTA'),
    (18, N'Alexis',   N'Mac Allister', 'MEDIOCAMPISTA'),
    ( 9, N'Julián',   N'Álvarez',      'DELANTERO'),
    (11, N'Ángel',    N'Di María',     'DELANTERO'),
    (19, N'Nicolás',  N'González',     'DELANTERO'),
    (20, N'Giuliano', N'Simeone',      'DELANTERO'),
    (21, N'Paulo',    N'Dybala',       'DELANTERO'),
    (22, N'Lautaro',  N'Martínez',     'DELANTERO');

-- Plantel de Brasil1.
DROP TABLE IF EXISTS #plantel_brasil;
CREATE TABLE #plantel_brasil (dorsal TINYINT, nombre NVARCHAR(60), apellido NVARCHAR(60), posicion VARCHAR(15));
INSERT INTO #plantel_brasil (dorsal, nombre, apellido, posicion) VALUES
    ( 1, N'Alisson',     N'Becker',     'ARQUERO'),
    (12, N'Ederson',     N'Moraes',     'ARQUERO'),
    (23, N'Bento',       N'Krepski',    'ARQUERO'),
    ( 2, N'Danilo',      N'Luiz',       'DEFENSOR'),
    ( 3, N'Gabriel',     N'Magalhães',  'DEFENSOR'),
    ( 4, N'Marcos',      N'Aoás',       'DEFENSOR'),
    ( 5, N'Éder',        N'Militão',    'DEFENSOR'),
    ( 6, N'Alex',        N'Sandro',     'DEFENSOR'),
    (13, N'Wesley',      N'França',     'DEFENSOR'),
    (14, N'Lucas',       N'Beraldo',    'DEFENSOR'),
    (15, N'Douglas',     N'Santos',     'DEFENSOR'),
    ( 7, N'Lucas',       N'Paquetá',    'MEDIOCAMPISTA'),
    ( 8, N'Bruno',       N'Guimarães',  'MEDIOCAMPISTA'),
    (10, N'Rodrygo',     N'Goes',       'MEDIOCAMPISTA'),
    (16, N'André',       N'Trindade',   'MEDIOCAMPISTA'),
    (17, N'Joelinton',   N'Lira',       'MEDIOCAMPISTA'),
    (18, N'Gerson',      N'Santos',     'MEDIOCAMPISTA'),
    ( 9, N'Matheus',     N'Cunha',      'DELANTERO'),
    (11, N'Raphael',     N'Dias',       'DELANTERO'),
    (19, N'Vinícius',    N'Júnior',     'DELANTERO'),
    (20, N'Gabriel',     N'Martinelli', 'DELANTERO'),
    (21, N'Richarlison', N'Andrade',    'DELANTERO'),
    (22, N'Estêvão',     N'Willian',    'DELANTERO');
GO

/* ============================================================================
   usp_RegistrarGol
   La preparación de todos los casos es la que describe el encabezado, más
   los goles que registraron los casos OK anteriores.
   ============================================================================ */

/* GO1 (OK) Gol de Argentina1 con asistencia.
   Esperado: gol de Julián Álvarez (9) en el minuto 20 con asistencia de
   Messi (10); la consulta del SP muestra el marcador 1 - 0.
   GO2 (ERROR) Autor y asistente que están en el banco.
   Esperado: error 50001 con 2 condiciones: el autor (Douglas Santos, dorsal
   15 de Brasil1) y el que asiste (André Trindade, 16) no estaban en cancha
   en ese minuto. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
DECLARE @jugada    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @en_contra TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
DECLARE @cabezazo  TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal     TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');

DECLARE @autor INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @asiste INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @jugada,
    @periodo = 'PRIMER_TIEMPO', @minuto = 20, @id_jugador_asistencia = @asiste;

SET @autor  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 15);
SET @asiste = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 16);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @jugada,
        @periodo = 'PRIMER_TIEMPO', @minuto = 30, @id_jugador_asistencia = @asiste;
    PRINT N'GO2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'GO2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'GO2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* GO3 (OK) Gol en contra.
   Preparación: además, el gol de GO1.
   Esperado: Danilo (2 de Brasil1) hace un gol en contra en el minuto 35,
   que suma para Argentina1: el marcador pasa a 2 - 0.
   GO4 (ERROR) Gol de alargue sin empate en los 90 minutos.
   Esperado: error 50001 con 1 condición: el partido no terminó empatado el
   tiempo reglamentario (2 - 0) y no hay alargue. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
DECLARE @jugada    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @en_contra TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
DECLARE @cabezazo  TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal     TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
-- Gol de GO1: Álvarez (9) en el minuto 20, con asistencia de Messi (10).
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_jugador_asistencia, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9),
        (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10), @jugada, 'PRIMER_TIEMPO', 20);

DECLARE @autor INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 2);
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @en_contra,
    @periodo = 'PRIMER_TIEMPO', @minuto = 35;

SET @autor = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @jugada,
        @periodo = 'ALARGUE', @minuto = 100;
    PRINT N'GO4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'GO4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'GO4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* GO5 (ERROR) Penal de definición sin empate.
   Preparación: además, los goles de GO1 y GO3 (2 - 0).
   Esperado: error 50001 con 1 condición: el partido no está empatado (2 - 0)
   y no hay definición por penales. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
DECLARE @jugada    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @en_contra TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
DECLARE @cabezazo  TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal     TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
-- Gol de GO1: Álvarez (9) en el minuto 20, con asistencia de Messi (10).
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_jugador_asistencia, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9),
        (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10), @jugada, 'PRIMER_TIEMPO', 20);
-- Gol de GO3: en contra de Danilo (2 de Brasil1) en el minuto 35.
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 2), @en_contra, 'PRIMER_TIEMPO', 35);

DECLARE @autor INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @penal,
        @periodo = 'PENALES';
    PRINT N'GO5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'GO5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'GO5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* GO6 (OK) Empate de Brasil1 y gol de Argentina1 en el alargue.
   Preparación: además, los goles de GO1 y GO3 (2 - 0).
   Esperado: goles de Cunha (9) en el minuto 60 y de Raphinha (11) en el
   90+3 (2 - 2 al terminar los 90 minutos) y, ya con el empate, gol de Messi
   en el alargue (minuto 100): el marcador final es 3 - 2.
   GO7 (ERROR) Gol de un jugador que ya había salido.
   Preparación: con un INSERT, Álvarez (9) sale en el minuto 70 y entra
   Nicolás González (19).
   Esperado: error 50001 con 1 condición: el autor no estaba en cancha en el
   minuto 80. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
DECLARE @jugada    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @en_contra TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
DECLARE @cabezazo  TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
DECLARE @penal     TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
-- Gol de GO1: Álvarez (9) en el minuto 20, con asistencia de Messi (10).
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_jugador_asistencia, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9),
        (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10), @jugada, 'PRIMER_TIEMPO', 20);
-- Gol de GO3: en contra de Danilo (2 de Brasil1) en el minuto 35.
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 2), @en_contra, 'PRIMER_TIEMPO', 35);

DECLARE @autor INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @cabezazo,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 60, @mostrar_resultados = 0;
SET @autor = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @cabezazo,
    @periodo = 'ADICIONALES', @minuto = 90, @minuto_adicional = 3, @mostrar_resultados = 0;
SET @autor = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @cabezazo,
    @periodo = 'ALARGUE', @minuto = 100;
SELECT 'GO6 después' AS caso, goles_local, goles_visitante, goles_local_90, goles_visitante_90
FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);

DECLARE @alvarez INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @gonzalez INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 19);
INSERT INTO DesarrolloPartido.CAMBIO (id_partido, id_jugador_sale, id_jugador_entra, minuto, motivo)
VALUES (@id_partido, @alvarez, @gonzalez, 70, 'TACTICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @alvarez, @id_tipo_gol = @jugada,
        @periodo = 'SEGUNDO_TIEMPO', @minuto = 80;
    PRINT N'GO7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'GO7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'GO7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_RegistrarAmonestacion
   ============================================================================ */

/* TA1 (OK) Primera amarilla de un jugador sin tarjetas en el torneo.
   Esperado: Gabriel Magalhães (3 de Brasil1) recibe una amarilla en el
   minuto 25; la consulta del SP muestra 1 amarilla en el partido y "SIN
   SUSPENSION".
   TA2 (OK) Caso obligatorio: expulsión por doble amarilla.
   Esperado: la segunda amarilla de Magalhães registra, en la misma
   transacción, la ROJA con es_doble_amarilla = 1 en el minuto 50. En
   Mensajes aparece la suspensión por DOBLE AMARILLA (1 partido).
   TA4 (OK) Caso obligatorio: suspensión por acumulación de amarillas.
   Pezzella (6 de Argentina1), que ya vio una amarilla en el partido 241
   (dieciseisavos), ve otra en este partido (octavos): dieciseisavos, octavos
   y cuartos son el mismo tramo, así que las amarillas se acumulan.
   Esperado: en Mensajes, "Suspensión: ... no puede jugar los próximos 1
   partido(s) de su selección (ACUMULACION DE AMARILLAS)", y la consulta del
   SP muestra esa suspensión.
   TA5 (OK) Caso obligatorio: roja directa.
   Esperado: ROJA sin doble amarilla en el minuto 85 a Juan Foyth (2 de
   Argentina1); en Mensajes, la suspensión por ROJA DIRECTA (1 partido).
   TA6 (OK) Amarilla al director técnico de Brasil1.
   Esperado: una AMARILLA para Ancelotti (las suspensiones se calculan solo
   para jugadores).
   Después, fn_Sanciones muestra las 3 sanciones que generó el partido 240.
   TA3 (ERROR) Tarjeta a un jugador ya expulsado.
   Esperado: el error 50001 lo informa DesarrolloPartido.usp_AMONESTACION_Alta:
   Magalhães ya había sido expulsado en este partido. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;

DECLARE @magalhaes INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 3);
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 25,
    @motivo = 'Falta imprudente', @id_jugador = @magalhaes;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 50,
    @motivo = 'Sujetar a un rival', @id_jugador = @magalhaes;
SELECT 'TA2 después' AS caso, id_amonestacion, tipo_tarjeta, es_doble_amarilla, minuto, motivo
FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND id_jugador = @magalhaes ORDER BY id_amonestacion;

SELECT 'TA4 antes' AS caso, j.dorsal, j.apellido, p.numero_partido AS partido_con_amarilla_previa
FROM Torneo.JUGADOR AS j
INNER JOIN DesarrolloPartido.AMONESTACION AS a ON a.id_jugador = j.id_jugador
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
WHERE j.id_jugador = @pezzella;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 75,
    @motivo = 'Demorar la reanudación', @id_jugador = @pezzella;

DECLARE @foyth INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 2);
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 85,
    @motivo = 'Agresión a un rival', @id_jugador = @foyth;

DECLARE @ancelotti INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion_bra AND rol = 'DIRECTOR_TECNICO');
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 88,
    @motivo = 'Salir del área técnica', @id_persona_ct = @ancelotti;
SELECT 'TA6 después' AS caso, ct.apellido, ct.rol, a.tipo_tarjeta, a.minuto, a.motivo
FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PERSONA_CUERPO_TECNICO AS ct ON ct.id_persona_ct = a.id_persona_ct
WHERE a.id_partido = @id_partido;

-- Evidencia: sanciones que generó el partido 240 (fn_Sanciones).
SELECT 'Sanciones del partido 240' AS caso, j.dorsal, j.apellido, s.motivo, s.partidos_de_suspension
FROM DesarrolloPartido.fn_Sanciones() AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
WHERE s.id_partido_origen = @id_partido
ORDER BY s.motivo;

BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 60,
        @motivo = 'Protestar', @id_jugador = @magalhaes;
    PRINT N'TA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'TA3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'TA3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* TA7a (ERROR) Tarjeta en un partido que no existe.
   Esperado: error 50001 de usp_RegistrarAmonestacion: no existe el partido -1. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;

DECLARE @bento INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 23);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = -1, @tipo_tarjeta = 'AMARILLA', @minuto = 10,
        @motivo = 'Falta', @id_jugador = @bento;
    PRINT N'TA7a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'TA7a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'TA7a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* TA7b (ERROR) Tarjeta a un jugador que no juega.
   Esperado: error 50001 de usp_AMONESTACION_Alta: el jugador (Bento, dorsal
   23 de Brasil1, que no está en su formación) no figura en la formación del
   partido. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @lista_arg INT, @lista_bra INT;
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
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol) VALUES
    (@id_seleccion_arg, N'Lionel', N'Scaloni',   'DIRECTOR_TECNICO'),
    (@id_seleccion_bra, N'Carlo',  N'Ancelotti', 'DIRECTOR_TECNICO');
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_arg, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_argentina;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT @lista_bra, dorsal, nombre, apellido, posicion, '2026-06-01' FROM #plantel_brasil;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @id_partido_241 INT, @formacion_241 INT, @id_partido INT, @formacion_arg INT, @formacion_bra INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 241 (dieciseisavos), ya jugado: amarilla a Pezzella (dorsal 6 de Argentina1).
DECLARE @pezzella INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (241, @sede, 'DIECISEISAVOS', '2026-08-25 15:00', '2026-08-25 20:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_241, @id_seleccion_arg, '4-3-3');
SET @formacion_241 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_241, @pezzella, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_241, @pezzella, 'AMARILLA', 40, 'Falta táctica');
-- Partido 240 (octavos), EN_JUEGO, con las dos formaciones en 4-3-3
-- (dorsales 1 a 11 titulares y 12 a 22 suplentes).
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (240, @sede, 'OCTAVOS', '2026-08-30 15:00', '2026-08-30 20:00', @id_seleccion_arg, @id_seleccion_bra, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-3-3');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;

DECLARE @bento INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 23);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 10,
        @motivo = 'Falta', @id_jugador = @bento;
    PRINT N'TA7b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'TA7b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'TA7b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (240, 241))           AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'Brasil1')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Arrowhead Stadium1')      AS sedes_de_prueba,
       @@TRANCOUNT                                                                        AS transacciones_abiertas;
GO

SET NOEXEC OFF;
GO
