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
 Archivo: 62_Test_SP_Negocio_FormacionesYCambios.sql
 Objetivo: Probar los SP de 12_SP_Negocio_FormacionesYCambios.sql
           (usp_RegistrarFormacion y usp_RegistrarCambio) y la reconstrucción
           del equipo en cancha con fn_EquipoEnCancha: casos exitosos con su
           evidencia y casos que no cumplen el reglamento (titulares, arquero,
           suspendidos, jugador en cancha, máximo de cambios y ventanas, cambio
           extra del alargue). Requiere haber ejecutado 01 a 28; no depende del
           juego de datos.
           Cada caso arma sus propios datos con INSERT directos a las tablas:
           los países Argentina1 y Brasil1 con su plantel de 23 jugadores, la
           sede "Lumen Field1", el partido 236 (Argentina1 - Brasil1, ya
           jugado, con una roja directa a Nicolás Tagliafico, dorsal 3 de
           Argentina1, que queda suspendido) y el partido 235 (Argentina1 -
           Brasil1, de octavos). Los deshace al terminar, así que se puede
           ejecutar más de una vez.
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
 lote puede haber casos OK pero un solo caso de error, al final. Cada lote
 vuelve a cargar con INSERT lo que dejaron los casos OK anteriores.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.usp_RegistrarFormacion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo IN ('MAX_CAMBIOS', 'MAX_VENTANAS') HAVING COUNT(*) = 2)
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
   usp_RegistrarFormacion
   La preparación de todos los casos es la que describe el encabezado:
   selecciones, planteles, sede, partido 236 ya jugado y partido 235.
   ============================================================================ */

/* RF1 (ERROR) Formación con todos los problemas posibles.
   10 titulares (dos como ARQUERO, uno sin posición y uno repetido), un
   jugador de Brasil1, Tagliafico (dorsal 3, suspendido) en el banco y una
   fila sin jugador.
   Esperado: error 50001 con 7 condiciones en un solo mensaje, entre ellas
   "Suspendido: 3 ... (ROJA DIRECTA en el partido 236)". No se crea la
   formación. */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();

DECLARE @id_jugador_dorsal_1 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 1);
DECLARE @id_jugador_dorsal_12 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 12);
DECLARE @id_jugador_dorsal_4 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 4);
DECLARE @id_jugador_dorsal_5 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 5);
DECLARE @id_jugador_dorsal_6 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 6);
DECLARE @id_jugador_dorsal_7 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 7);
DECLARE @id_jugador_dorsal_8 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 8);
DECLARE @id_jugador_dorsal_9 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @cunha INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
VALUES (@id_jugador_dorsal_1, 1, 'ARQUERO'), (@id_jugador_dorsal_12, 1, 'ARQUERO'), (@id_jugador_dorsal_4, 1, NULL), (@id_jugador_dorsal_5, 1, 'DEFENSOR'), (@id_jugador_dorsal_5, 1, 'DEFENSOR'),
       (@id_jugador_dorsal_6, 1, 'DEFENSOR'), (@id_jugador_dorsal_7, 1, 'MEDIOCAMPISTA'), (@id_jugador_dorsal_8, 1, 'MEDIOCAMPISTA'), (@id_jugador_dorsal_9, 1, 'DELANTERO'),
       (@cunha, 1, 'DELANTERO'), (@tagliafico, 0, NULL), (NULL, 0, NULL);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_seleccion_arg,
        @esquema_tactico = '4-3-3', @jugadores = @alineacion;
    PRINT N'RF1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RF1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RF1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'RF1 después' AS caso, COUNT(*) AS formaciones FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;
ROLLBACK TRANSACTION;
GO

/* RF2 (OK) Formaciones válidas de las dos selecciones.
   Esperado: la consulta del SP muestra, para Argentina1, 11 titulares
   (dorsales 1, 2, 4 a 11 y Romero, el 13, que juega por Tagliafico) y un
   banco de 10 sin el dorsal 3, que está suspendido. Brasil1 queda con 11
   titulares y 11 suplentes.
   RF3 (ERROR) Segunda formación para la misma selección.
   Esperado: el error 50001 lo informa DesarrolloPartido.usp_FORMACION_Alta
   (la selección ya tiene formación para ese partido) y no se agrega ninguna
   alineación. */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();

-- Argentina1 (local), en 4-3-3 y sin los suspendidos; Romero (13) titular por Tagliafico.
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
SELECT id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_seleccion_arg,
    @esquema_tactico = '4-3-3', @jugadores = @alineacion;

-- Brasil1 (visitante), en 4-4-2.
DELETE FROM @alineacion;
INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
SELECT id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_seleccion_bra,
    @esquema_tactico = '4-4-2', @jugadores = @alineacion, @mostrar_resultados = 0;

SELECT 'RF2 después' AS caso, pa.nombre AS seleccion, f.esquema_tactico,
       SUM(IIF(a.es_titular = 1, 1, 0)) AS titulares, SUM(IIF(a.es_titular = 0, 1, 0)) AS suplentes
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE f.id_partido = @id_partido
GROUP BY pa.nombre, f.esquema_tactico;

DECLARE @antes INT = (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION AS a INNER JOIN DesarrolloPartido.FORMACION AS f
                      ON f.id_formacion = a.id_formacion WHERE f.id_partido = @id_partido);
DELETE FROM @alineacion;
INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
SELECT id_jugador, 1, posicion_habitual
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_seleccion_arg,
        @esquema_tactico = '4-3-3', @jugadores = @alineacion;
    PRINT N'RF3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RF3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RF3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'RF3 después' AS caso, @antes AS alineados_antes, COUNT(*) AS alineados_despues
FROM DesarrolloPartido.ALINEACION AS a INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
WHERE f.id_partido = @id_partido;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_RegistrarCambio (Argentina1)
   La preparación de estos casos agrega las formaciones de RF2 y el partido
   235 EN_JUEGO (este test no necesita la terna arbitral), y los cambios que
   registraron los casos anteriores.
   ============================================================================ */

/* RC1 (OK) Caso obligatorio: cambio por lesión dentro de los primeros 20 minutos.
   Esperado: en el minuto 15 sale Montiel (4) por LESION y entra Lisandro
   Martínez (14). Con fn_EquipoEnCancha, en el minuto 14 está el 4 y en el 16
   está el 14.
   RC2 (ERROR) El que sale ya no está en cancha y el que entra es titular.
   Esperado: error 50001 con 2 condiciones: el dorsal 4 no está en cancha en
   ese minuto y el dorsal 5 no está en el banco. */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();
-- Formaciones de RF2 y el partido EN_JUEGO. Argentina1 en 4-3-3, con
-- Romero (13) por Tagliafico (3, suspendido); Brasil1 en 4-4-2.
DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-4-2');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;

DECLARE @sale INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 4);
DECLARE @entra INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 14);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 15, @motivo = 'LESION';
SELECT 'RC1 después' AS caso, m.minuto, STRING_AGG(CAST(e.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY e.dorsal) AS en_cancha
FROM (VALUES (CAST(14 AS TINYINT)), (CAST(16 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion_arg, m.minuto, 0) AS e
GROUP BY m.minuto;

SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 5);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 30, @motivo = 'TACTICO';
    PRINT N'RC2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RC2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RC2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RC3 (OK) Dos cambios en la misma ventana (minuto 60).
   Preparación: además, el cambio del minuto 15 (RC1).
   Esperado: salen Álvarez (9) y De Paul (7), entran González (19) y Almada
   (16). Argentina1 lleva 3 cambios en 2 ventanas (15 y 60).
   RC4 (ERROR) Un cambio anterior al último registrado.
   Esperado: error 50001 con 1 condición: la selección ya tiene un cambio
   registrado después de ese minuto. */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();
-- Formaciones de RF2 y el partido EN_JUEGO. Argentina1 en 4-3-3, con
-- Romero (13) por Tagliafico (3, suspendido); Brasil1 en 4-4-2.
DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-4-2');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;
-- Cambio de RC1.
INSERT INTO DesarrolloPartido.CAMBIO (id_partido, id_jugador_sale, id_jugador_entra, minuto, motivo, en_entretiempo) VALUES
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  4),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 14), 15, 'LESION', 0);

DECLARE @sale INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 9);
DECLARE @entra INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 19);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 60, @motivo = 'TACTICO';
SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 7);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 16);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 60, @motivo = 'TACTICO';
SELECT 'RC3 después' AS caso, COUNT(*) AS cambios, COUNT(DISTINCT c.minuto * 100 + c.minuto_adicional) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
WHERE c.id_partido = @id_partido AND j.id_lista = @lista_arg;

SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 17);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 50, @motivo = 'TACTICO';
    PRINT N'RC4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RC4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RC4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RC5 (OK) Tercera ventana con dos cambios (minuto 75).
   Preparación: además, los cambios de los minutos 15 y 60 (RC1 y RC3).
   Esperado: salen Di María (11) y Enzo Fernández (8), entran Dybala (21) y
   Paredes (17). Argentina1 llega a 5 cambios en 3 ventanas, el máximo del
   tiempo reglamentario.
   RC6 (ERROR) Sexto cambio en el tiempo reglamentario.
   Esperado: error 50001 con 2 condiciones: Argentina1 ya hizo sus 5 cambios
   permitidos (MAX_CAMBIOS) y ya usó sus 3 ventanas (MAX_VENTANAS). */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();
-- Formaciones de RF2 y el partido EN_JUEGO. Argentina1 en 4-3-3, con
-- Romero (13) por Tagliafico (3, suspendido); Brasil1 en 4-4-2.
DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-4-2');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;
-- Cambios de RC1 y RC3.
INSERT INTO DesarrolloPartido.CAMBIO (id_partido, id_jugador_sale, id_jugador_entra, minuto, motivo, en_entretiempo) VALUES
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  4),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 14), 15, 'LESION', 0),
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  9),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 19), 60, 'TACTICO', 0),
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  7),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 16), 60, 'TACTICO', 0);

DECLARE @sale INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 11);
DECLARE @entra INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 21);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 75, @motivo = 'TACTICO';
SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 8);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 17);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 75, @motivo = 'PRECAUCION';
SELECT 'RC5 después' AS caso, COUNT(*) AS cambios, COUNT(DISTINCT c.minuto * 100 + c.minuto_adicional) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
WHERE c.id_partido = @id_partido AND j.id_lista = @lista_arg;

SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 18);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 85, @motivo = 'TACTICO';
    PRINT N'RC6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RC6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RC6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RC7 (OK) Cambio adicional del tiempo suplementario.
   Preparación: además, los 5 cambios de RC1, RC3 y RC5.
   Esperado: en el minuto 95 (alargue) se permite un sexto cambio y una
   cuarta ventana (CAMBIOS_EXTRA_ALARGUE y VENTANAS_EXTRA_ALARGUE): sale
   Messi (10) y entra Mac Allister (18).
   Después, fn_EquipoEnCancha muestra el equipo de Argentina1 a lo largo del
   partido: 11 jugadores en cada minuto, con los cambios aplicados (en el 10
   juega el 4; en el 70, el 14, el 19 y el 16; en el 100, el 21, el 17 y el 18).
   RC8 (ERROR) Séptimo cambio, ya en el alargue.
   Esperado: error 50001 con 2 condiciones: Argentina1 ya hizo sus 6 cambios
   y usó sus 4 ventanas permitidos con el tiempo suplementario. */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();
-- Formaciones de RF2 y el partido EN_JUEGO. Argentina1 en 4-3-3, con
-- Romero (13) por Tagliafico (3, suspendido); Brasil1 en 4-4-2.
DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-4-2');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;
-- Cambios de RC1, RC3 y RC5.
INSERT INTO DesarrolloPartido.CAMBIO (id_partido, id_jugador_sale, id_jugador_entra, minuto, motivo, en_entretiempo) VALUES
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  4),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 14), 15, 'LESION', 0),
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  9),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 19), 60, 'TACTICO', 0),
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  7),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 16), 60, 'TACTICO', 0),
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 11),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 21), 75, 'TACTICO', 0),
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal =  8),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 17), 75, 'PRECAUCION', 0);

DECLARE @sale INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 10);
DECLARE @entra INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 18);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 95, @motivo = 'TACTICO';
SELECT 'RC7 después' AS caso, COUNT(*) AS cambios, COUNT(DISTINCT c.minuto * 100 + c.minuto_adicional) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
WHERE c.id_partido = @id_partido AND j.id_lista = @lista_arg;

SELECT 'Equipo en cancha' AS caso, m.minuto, COUNT(*) AS jugadores,
       STRING_AGG(CAST(e.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY e.dorsal) AS dorsales
FROM (VALUES (CAST(10 AS TINYINT)), (CAST(70 AS TINYINT)), (CAST(100 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion_arg, m.minuto, 0) AS e
GROUP BY m.minuto
ORDER BY m.minuto;

SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 13);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 15);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 100, @motivo = 'TACTICO';
    PRINT N'RC8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RC8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RC8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_RegistrarCambio (Brasil1): entretiempo y jugador expulsado
   ============================================================================ */

/* RC9 (OK) Cambio en el entretiempo, que no consume ventana.
   Esperado: en el minuto 46 (entretiempo) sale Cunha (9) y entra Vinícius
   Júnior (19); Brasil1 queda con 1 cambio y 0 ventanas usadas.
   RC10 (ERROR) Un suplente expulsado no puede entrar.
   Preparación: con un INSERT, roja en el banco a Martinelli (20) en el
   minuto 50.
   Esperado: error 50001 con 1 condición: el jugador que entra no está en el
   banco (fue expulsado). */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();
-- Formaciones de RF2 y el partido EN_JUEGO. Argentina1 en 4-3-3, con
-- Romero (13) por Tagliafico (3, suspendido); Brasil1 en 4-4-2.
DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-4-2');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;

DECLARE @sale INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 9);
DECLARE @entra INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 19);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 46, @motivo = 'TACTICO', @en_entretiempo = 1;
SELECT 'RC9 después' AS caso, COUNT(*) AS cambios,
       COUNT(DISTINCT IIF(c.en_entretiempo = 0, c.minuto * 100 + c.minuto_adicional, NULL)) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
WHERE c.id_partido = @id_partido AND j.id_lista = @lista_bra;

SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 20);
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido, @entra, 'ROJA', 50, 'Insultos al árbitro desde el banco');
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 55, @motivo = 'TACTICO';
    PRINT N'RC10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RC10: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RC10: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RC11 (OK) Tres ventanas más después del cambio del entretiempo.
   Preparación: además, el cambio del entretiempo de RC9.
   Esperado: Brasil1 hace cambios en los minutos 55, 65 y 75: queda con
   4 cambios y 3 ventanas, dentro del reglamento. */
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
DECLARE @sede INT, @id_partido_236 INT, @formacion_236 INT, @id_partido INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
-- Partido 236, ya jugado: roja directa a Tagliafico (dorsal 3 de Argentina1).
DECLARE @tagliafico INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal = 3);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (236, @sede, 'DIECISEISAVOS', '2026-08-21 20:00', '2026-08-22 03:00', @id_seleccion_arg, @id_seleccion_bra, 1, 0, 'FINALIZADO');
SET @id_partido_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido_236, @id_seleccion_arg, '4-3-3');
SET @formacion_236 = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@formacion_236, @tagliafico, 1, 'DEFENSOR');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido_236, @tagliafico, 'ROJA', 88, 'Juego brusco grave');
-- Partido 235 (octavos), sobre el que se prueban los SP.
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (235, @sede, 'OCTAVOS', '2026-08-27 20:00', '2026-08-28 03:00', @id_seleccion_arg, @id_seleccion_bra);
SET @id_partido = SCOPE_IDENTITY();
-- Formaciones de RF2 y el partido EN_JUEGO. Argentina1 en 4-3-3, con
-- Romero (13) por Tagliafico (3, suspendido); Brasil1 en 4-4-2.
DECLARE @formacion_arg INT, @formacion_bra INT;
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_arg, '4-3-3');
SET @formacion_arg = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_bra, '4-4-2');
SET @formacion_bra = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_arg, id_jugador,
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), 1, 0),
       IIF(dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13), posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_arg AND dorsal <= 22 AND dorsal <> 3;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT @formacion_bra, id_jugador, IIF(dorsal <= 11, 1, 0), IIF(dorsal <= 11, posicion_habitual, NULL)
FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal <= 22;
UPDATE Torneo.PARTIDO SET estado = 'EN_JUEGO' WHERE id_partido = @id_partido;
-- Cambio de RC9, en el entretiempo.
INSERT INTO DesarrolloPartido.CAMBIO (id_partido, id_jugador_sale, id_jugador_entra, minuto, motivo, en_entretiempo) VALUES
    (@id_partido, (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal =  9),
                  (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 19), 46, 'TACTICO', 1);

DECLARE @sale INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 11);
DECLARE @entra INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 21);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra, @minuto = 55, @motivo = 'TACTICO';
SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 10);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 16);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra, @minuto = 65, @motivo = 'TACTICO';
SET @sale  = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 8);
SET @entra = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @lista_bra AND dorsal = 17);
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra, @minuto = 75, @motivo = 'TACTICO';
SELECT 'RC11 después' AS caso, COUNT(*) AS cambios,
       COUNT(DISTINCT IIF(c.en_entretiempo = 0, c.minuto * 100 + c.minuto_adicional, NULL)) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
WHERE c.id_partido = @id_partido AND j.id_lista = @lista_bra;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (235, 236))           AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'Brasil1')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Lumen Field1')            AS sedes_de_prueba,
       @@TRANCOUNT                                                                        AS transacciones_abiertas;
GO

SET NOEXEC OFF;
GO
