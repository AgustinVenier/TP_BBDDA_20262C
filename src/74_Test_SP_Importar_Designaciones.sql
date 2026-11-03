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

 Fecha: 03/11/2026
 Archivo: 74_Test_SP_Importar_Designaciones.sql
 Objetivo: Probar la importación de designaciones arbitrales de
           34_SP_Importar_Designaciones.sql con los archivos chicos
           datos/pruebas/designaciones_prueba*.csv: alta de árbitros y
           designaciones, reimportación sin duplicados, rechazo de las filas
           inválidas (con el registro de la importación y sus rechazados en
           Arbitraje.ERRORES_DESIGNACION), designaciones que contradicen lo ya
           cargado y los archivos que no se pueden importar.
           Requiere haber ejecutado 00 a 34 y tener al menos una sede cargada
           (con el torneo de prueba del 31 o con el real del 32). Crea sus
           propios países (ZZA y ZZB, las selecciones; ZZC y ZZD, los árbitros),
           selecciones y partidos (números 221 y 222), y al final los borra,
           junto con el registro de sus importaciones, así que se puede
           ejecutar más de una vez.
================================================================================

 Antes de ejecutar: CAMBIAR @carpeta, en el primer lote, por la ruta de la
 carpeta datos\pruebas\ del repositorio en tu máquina. La cuenta del servicio
 de SQL Server tiene que poder leerla (ver "Antes de ejecutar" en
 26_ImportarIndicadores.sql).

 Qué tiene designaciones_prueba.csv (15 filas, de los partidos 221, del
 2026-12-01, y 222, del 2026-12-05, entre ZZA y ZZB):
   Línea  2 a  6  la terna completa del 221 (la línea 3 con las selecciones al revés)
   Línea  7       el mismo árbitro principal en el 222: no se duplica el árbitro
   Línea  8       conflicto de nacionalidad (árbitro de ZZA, que juega)
   Línea  9       el país ZZX no está cargado
   Línea 10       asistente 2 del 222 (válida)
   Línea 11       otro asistente 2 en el mismo partido
   Línea 12       el árbitro principal también como VAR en el mismo partido
   Línea 13       un partido que no existe (2026-12-09)
   Línea 14       un rol que no existe
   Línea 15       sin nombre
   Línea 16       una fecha que no es AAAA-MM-DD

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el resumen de la importación, los rechazados
     con sus motivos y las designaciones que quedaron. La columna "verificacion"
     dice OK o FALLÓ según lo esperado.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con otro número de error, se imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Carpeta de los archivos de prueba (para los lotes siguientes).
-- CAMBIAR: ruta de la carpeta datos\pruebas\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @carpeta NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\datos\pruebas\';
EXEC sp_set_session_context @key = N'carpeta_pruebas', @value = @carpeta;

IF OBJECT_ID(N'Arbitraje.usp_ImportarDesignacionesCSV', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM Torneo.SEDE)
BEGIN
    RAISERROR(N'Falta el SP de importación o una sede cargada: ejecutar los scripts 00 a 34 y el 31 o el 32.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'tempdb..#usp_MostrarError', N'P') IS NOT NULL
    DROP PROCEDURE #usp_MostrarError;
GO
CREATE PROCEDURE #usp_MostrarError
    @caso            VARCHAR(10),
    @error_esperado  INT
AS
BEGIN
    PRINT CONCAT(@caso, N': ',
                 IIF(ERROR_NUMBER() = @error_esperado, N'OK, falló como se esperaba.',
                     CONCAT(N'FALLÓ, error inesperado ', ERROR_NUMBER(), N'.')),
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END;
GO

-- Borra todo lo que carga el test.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT;

    -- Las designaciones y los árbitros de prueba (los países ZZC y ZZD).
    DELETE d
    FROM Arbitraje.DESIGNACION_ARBITRAL AS d
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
    WHERE p.numero_partido IN (221, 222);

    DELETE a
    FROM Arbitraje.ARBITRO AS a
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
    WHERE pa.codigo_fifa IN ('ZZC', 'ZZD');

    SET @id = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 221);
    IF @id IS NOT NULL EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    SET @id = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 222);
    IF @id IS NOT NULL EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;

    SET @id = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
               INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'ZZA');
    IF @id IS NOT NULL EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
    SET @id = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
               INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'ZZB');
    IF @id IS NOT NULL EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;

    SET @id = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ZZA');
    IF @id IS NOT NULL EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    SET @id = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ZZB');
    IF @id IS NOT NULL EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    SET @id = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ZZC');
    IF @id IS NOT NULL EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    SET @id = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ZZD');
    IF @id IS NOT NULL EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;

    -- El registro de las importaciones de los archivos de prueba, con sus rechazados.
    DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
    DECLARE @archivo NVARCHAR(400);
    SET @archivo = @carpeta + N'designaciones_prueba.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'designaciones_prueba_cambios.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
END;
GO

-- Por si una corrida anterior del test quedó a medias.
EXEC #usp_LimpiarPruebas;
GO

-- Países de prueba (los códigos ZZA a ZZD no son de ninguna federación) y dos partidos entre ZZA y ZZB.
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Designaciones A', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZA', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Designaciones B', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZB', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Designaciones C', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZC', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Designaciones D', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZD', @codigo_moneda = 'ARS';

DECLARE @pais_a SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ZZA');
DECLARE @pais_b SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ZZB');
DECLARE @sede INT = (SELECT TOP (1) id_sede FROM Torneo.SEDE ORDER BY id_sede);
DECLARE @a INT, @b INT;

EXEC Torneo.usp_SELECCION_Alta @id_pais = @pais_a, @confederacion = 'CONMEBOL', @id_seleccion = @a OUTPUT;
EXEC Torneo.usp_SELECCION_Alta @id_pais = @pais_b, @confederacion = 'CONMEBOL', @id_seleccion = @b OUTPUT;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 221, @id_sede = @sede, @fase = 'OCTAVOS',
     @fecha_hora_local = '2026-12-01 18:00', @id_seleccion_local = @a, @id_seleccion_visitante = @b;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 222, @id_sede = @sede, @fase = 'OCTAVOS',
     @fecha_hora_local = '2026-12-05 18:00', @id_seleccion_local = @a, @id_seleccion_visitante = @b;
GO


/* ============================================================================
   IMPORTACIÓN
   ============================================================================ */

/* DD1 (OK) Importación con errores parciales de designaciones_prueba.csv.
   Esperado: 15 leídas, 7 insertadas y 8 rechazados; 6 árbitros nuevos (el
   principal del 221 y del 222 es el mismo). Los rechazados, con su motivo:
   línea 8 conflicto de nacionalidad, 9 país ZZX no cargado, 11 más de un
   asistente 2, 12 el mismo árbitro con dos roles, 13 sin partido, 14 rol
   inválido, 15 sin nombre, 16 fecha inválida. Quedan en
   Arbitraje.ERRORES_DESIGNACION con el número de la importación. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'designaciones_prueba.csv';
DECLARE @id_importacion INT;

EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'DD1 registro' AS caso, i.proceso, i.leidos, i.insertados, i.sin_cambios, i.rechazados,
       (SELECT COUNT(*) FROM Arbitraje.ERRORES_DESIGNACION AS e WHERE e.id_importacion = i.id_importacion) AS en_errores,
       IIF(i.leidos = 15 AND i.insertados = 7 AND i.sin_cambios = 0 AND i.rechazados = 8, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'DD1 rechazados' AS caso, registro AS linea, fecha, rol, nombre, apellido, codigo_pais,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Arbitraje.ERRORES_DESIGNACION
WHERE id_importacion = @id_importacion
ORDER BY registro;

SELECT 'DD1 designaciones' AS caso, p.numero_partido, d.rol, a.nombre, a.apellido, pa.codigo_fifa AS pais, a.categoria
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
WHERE p.numero_partido IN (221, 222)
ORDER BY p.numero_partido, CHARINDEX(d.rol, 'PRINCIPAL ASISTENTE_1 ASISTENTE_2 CUARTO VAR');

SELECT 'DD1 verificacion' AS caso,
       (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        WHERE p.numero_partido = 221) AS designaciones_221,
       (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        WHERE p.numero_partido = 222) AS designaciones_222,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        WHERE pa.codigo_fifa IN ('ZZC', 'ZZD')) AS arbitros_nuevos,
       IIF((SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
            WHERE p.numero_partido = 221) = 5
           AND (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                WHERE p.numero_partido = 222) = 2
           AND (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
                WHERE pa.codigo_fifa IN ('ZZC', 'ZZD')) = 6, 'OK', 'FALLÓ') AS verificacion;
GO


/* DD2 (OK) Reimportación de designaciones_prueba.csv.
   Esperado: 7 sin cambios y los mismos 8 rechazados; siguen 7 designaciones y
   6 árbitros. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'designaciones_prueba.csv';
DECLARE @id_importacion INT;

EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'DD2 verificacion' AS caso, i.leidos, i.insertados, i.sin_cambios, i.rechazados,
       (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        WHERE p.numero_partido IN (221, 222)) AS designaciones,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        WHERE pa.codigo_fifa IN ('ZZC', 'ZZD')) AS arbitros,
       IIF(i.insertados = 0 AND i.sin_cambios = 7 AND i.rechazados = 8
           AND (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                WHERE p.numero_partido IN (221, 222)) = 7, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;
GO


/* DD3 (OK) Importación de designaciones_prueba_cambios.csv sobre lo ya cargado.
   Esperado: 5 leídas, 1 sin cambios (el principal del 221), 2 insertadas (el
   cuarto árbitro y un asistente 1 del 222, árbitros que ya existían) y 2
   rechazadas: otro VAR en el 221, que ya tiene el suyo, y el asistente 2 del
   222 como VAR, que ya tiene otro rol en ese partido. No se da de alta ningún
   árbitro. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'designaciones_prueba_cambios.csv';
DECLARE @id_importacion INT;

EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'DD3 verificacion' AS caso, i.leidos, i.insertados, i.sin_cambios, i.rechazados,
       (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        WHERE p.numero_partido IN (221, 222)) AS designaciones,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        WHERE pa.codigo_fifa IN ('ZZC', 'ZZD')) AS arbitros,
       IIF(i.leidos = 5 AND i.insertados = 2 AND i.sin_cambios = 1 AND i.rechazados = 2
           AND (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                WHERE p.numero_partido IN (221, 222)) = 9
           AND (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
                WHERE pa.codigo_fifa IN ('ZZC', 'ZZD')) = 6, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'DD3 rechazados' AS caso, registro AS linea, fecha, rol, nombre, apellido,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Arbitraje.ERRORES_DESIGNACION
WHERE id_importacion = @id_importacion
ORDER BY registro;
GO


/* DD4 (ERROR) Archivos que no se pueden importar:
     a) un archivo que no existe;
     b) mundial_prueba_columnas.csv, un CSV con otras columnas.
   Esperado: dos errores 50002, sin nada importado. */
DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
DECLARE @archivo NVARCHAR(400);

BEGIN TRY
    SET @archivo = @carpeta + N'no_existe.csv';
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo;
    PRINT N'DD4a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DD4a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_columnas.csv';
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo;
    PRINT N'DD4b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DD4b', @error_esperado = 50002;
END CATCH;
GO


/* DD5 (ERROR) Parámetros inválidos:
     a) ruta vacía;
     b) un .txt como CSV de designaciones.
   Esperado: dos errores 50001, sin leer el archivo. */
BEGIN TRY
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = N' ';
    PRINT N'DD5a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DD5a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = N'C:\designaciones.txt';
    PRINT N'DD5b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DD5b', @error_esperado = 50001;
END CATCH;
GO


-- Se borra todo lo que cargó el test.
EXEC #usp_LimpiarPruebas;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (221, 222)) AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC', 'ZZD')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        WHERE pa.codigo_fifa IN ('ZZC', 'ZZD')) AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION
        WHERE origen LIKE CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'designaciones[_]prueba%') AS importaciones_de_prueba;
GO

SET NOEXEC OFF;
GO
