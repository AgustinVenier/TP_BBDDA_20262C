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

 Fecha: 09/11/2026
 Archivo: 74_Test_SP_Importar_Jugadores.sql
 Objetivo: Probar la importación de las listas de convocados y de los cuerpos
           técnicos de 24_SP_Importar_Jugadores.sql
           (Torneo.usp_ImportarJugadoresCSV y
           Torneo.usp_ImportarCuerpoTecnicoCSV), con los archivos chicos de
           datos/pruebas/mundial_prueba_*: alta, reimportación sin
           duplicados, actualización, importación con errores parciales (con
           el registro de la importación y sus rechazados en las tablas
           ERRORES_) y los archivos y parámetros que no se pueden importar.
           Las reglas de cada tabla las prueba 66_Test_SP_Importacion.sql, con
           los SP de 16_SP_Importacion.sql.
           Requiere haber ejecutado 01 a 24. No depende del juego de datos
           (sirve con o sin el torneo real del 32 cargado): crea sus propios
           países (códigos ZZA, ZZB y ZZC) y sus selecciones (con
           Torneo.usp_ImportarSeleccionesJSON de 23, que se prueba en
           73_Test_SP_Importar_Mundial2026.sql), y al final los borra con los
           SP de baja, junto con el registro de sus importaciones
           (DatosGenerales.usp_BorrarImportacion), así que se puede ejecutar
           más de una vez.
================================================================================

 Antes de ejecutar: CAMBIAR @carpeta, en el primer lote, por la ruta de la
 carpeta datos\pruebas\ del repositorio en tu máquina. La cuenta del servicio
 de SQL Server tiene que poder leerla (ver "Antes de ejecutar" en
 32_Ejecutar_ImportarMundial2026.sql).

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el resumen de la importación y los
     rechazados con sus motivos, y después los datos que quedaron.
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

IF OBJECT_ID(N'Torneo.usp_ImportarJugadoresCSV', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_ImportarCuerpoTecnicoCSV', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_ImportarSeleccionesJSON', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG')
BEGIN
    RAISERROR(N'Faltan los SP de importación o los datos iniciales: ejecutar los scripts 01 a 24.', 16, 1);
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

-- Borra todo lo que carga el test, con los SP de baja.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT;

    WHILE EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                  INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = na.id_seleccion
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = na.id_nombre_alternativo
        FROM Torneo.NOMBRE_ALTERNATIVO AS na
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = na.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Baja @id_nombre_alternativo = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j
                  INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
                  INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = j.id_jugador
        FROM Torneo.JUGADOR AS j
        INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS AS lc
                  INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = lc.id_lista
        FROM Torneo.LISTA_CONVOCADOS AS lc
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
    END;

    DELETE ct
    FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');

    WHILE EXISTS (SELECT 1 FROM Torneo.SELECCION AS s
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = s.id_seleccion
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;

    -- El registro de las importaciones de los archivos de prueba, con sus rechazados.
    DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
    DECLARE @archivo NVARCHAR(400);
    SET @archivo = @carpeta + N'mundial_prueba_selecciones.json';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_jugadores.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_jugadores_cambios.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_cuerpo_tecnico.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_cuerpo_tecnico_cambios.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
END;
GO

-- Por si una corrida anterior del test (o del 73, que usa los mismos países) quedó a medias.
EXEC #usp_LimpiarPruebas;
GO

-- Países y selecciones de prueba (los códigos ZZA, ZZB y ZZC no son de ninguna
-- federación). Las selecciones ZZA y ZZB, con su lista de convocados vacía, las
-- carga la importación de 23; ZZC se rechaza (lo prueba el MI3 del 73).
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Importación A', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZA', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Importación B', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZB', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Importación C', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZC', @codigo_moneda = 'ARS';
GO

DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_selecciones.json';
EXEC Torneo.usp_ImportarSeleccionesJSON @ruta_archivo = @archivo, @fecha_presentacion = '2026-07-01';
GO


/* ============================================================================
   JUGADORES (Torneo.usp_ImportarJugadoresCSV)
   ============================================================================ */

/* MJ1 (OK) Importación con errores parciales de mundial_prueba_jugadores.csv:
   23 jugadores de ZZA y 23 de ZZB, más 4 filas con errores.
   Esperado: 50 leídos, 46 insertados y 4 rechazados (línea 25: el dorsal 150
   no está entre 1 y 99; línea 49: la posición "XX" no es ARQUERO, DEFENSOR,
   MEDIOCAMPISTA ni DELANTERO; línea 50: la fecha "1999-13-40" no es una
   fecha; línea 51: no hay una selección con lista con código QQQ). Los
   cuatro quedan en Torneo.ERRORES_JUGADOR con el número de la importación.
   El club de ZZB, que viene entre comillas porque tiene una coma, queda
   completo. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_jugadores.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MJ1 registro' AS caso, i.proceso, i.leidos, i.insertados, i.rechazados,
       (SELECT COUNT(*) FROM Torneo.ERRORES_JUGADOR AS e WHERE e.id_importacion = i.id_importacion) AS en_errores,
       IIF(i.leidos = 50 AND i.insertados = 46 AND i.rechazados = 4, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MJ1 rechazados' AS caso, registro AS linea, codigo_fifa, dorsal, posicion, nombre, apellido, fecha_nacimiento,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Torneo.ERRORES_JUGADOR
WHERE id_importacion = @id_importacion
ORDER BY registro;

SELECT 'MJ1 listas' AS caso, p.codigo_fifa, COUNT(*) AS jugadores, SUM(IIF(j.posicion_habitual = 'ARQUERO', 1, 0)) AS arqueros,
       MIN(j.fecha_alta) AS fecha_alta, MIN(j.motivo_alta) AS motivo_alta, MAX(j.club_origen) AS club
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa IN ('ZZA', 'ZZB')
GROUP BY p.codigo_fifa;
GO


/* MJ2 (OK) Reimportación de mundial_prueba_jugadores.csv.
   Esperado: 46 sin cambios y los mismos 4 rechazados; siguen 46 jugadores. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_jugadores.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MJ2 verificacion' AS caso, i.leidos, i.insertados, i.actualizados, i.sin_cambios, i.rechazados,
       IIF(i.insertados = 0 AND i.sin_cambios = 46 AND i.rechazados = 4
           AND (SELECT COUNT(*) FROM Torneo.JUGADOR AS j
                INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
                INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                WHERE p.codigo_fifa IN ('ZZA', 'ZZB')) = 46, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;
GO


/* MJ3 (OK) Importación de mundial_prueba_jugadores_cambios.csv sobre las
   listas cargadas.
   Esperado: 4 leídos: 1 actualizado (Bruno Prueba cambia de club), 1 sin
   cambios (Carlos Prueba), 1 insertado (Nuevo Prueba, dorsal 24: la lista
   queda con 24) y 1 rechazado (Otro Prueba: el dorsal 4 ya lo tiene Darío
   Prueba, que no viene en el archivo). */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_jugadores_cambios.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MJ3 verificacion' AS caso, i.leidos, i.insertados, i.actualizados, i.sin_cambios, i.rechazados,
       IIF(i.leidos = 4 AND i.insertados = 1 AND i.actualizados = 1 AND i.sin_cambios = 1 AND i.rechazados = 1,
           'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MJ3 jugadores' AS caso, j.dorsal, j.nombre, j.apellido, j.club_origen
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa = 'ZZA' AND j.dorsal IN (2, 3, 4, 24)
ORDER BY j.dorsal;
GO


/* ============================================================================
   CUERPO TÉCNICO (Torneo.usp_ImportarCuerpoTecnicoCSV)
   ============================================================================ */

/* MJ4 (OK) Importación con errores parciales de mundial_prueba_cuerpo_tecnico.csv.
   Esperado: 6 leídos, 3 insertados (el director técnico de ZZA, nacido en
   Argentina; un ayudante de campo de ZZA, sin país; la directora técnica de
   ZZB) y 3 rechazados: línea 5, la selección QQQ no existe; línea 6, el rol
   UTILERO no es válido; línea 7, el país XXX no existe. Quedan en
   Torneo.ERRORES_CUERPO_TECNICO con el número de la importación. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_cuerpo_tecnico.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MJ4 registro' AS caso, i.leidos, i.insertados, i.rechazados,
       (SELECT COUNT(*) FROM Torneo.ERRORES_CUERPO_TECNICO AS e WHERE e.id_importacion = i.id_importacion) AS en_errores,
       IIF(i.leidos = 6 AND i.insertados = 3 AND i.rechazados = 3, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MJ4 cuerpo tecnico' AS caso, p.codigo_fifa, ct.rol, ct.nombre, ct.apellido, pn.nombre AS pais_nacimiento
FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
LEFT JOIN DatosGenerales.PAIS AS pn ON pn.id_pais = ct.id_pais_nacimiento
WHERE p.codigo_fifa IN ('ZZA', 'ZZB')
ORDER BY p.codigo_fifa, ct.rol;
GO


/* MJ5 (OK) Importación de mundial_prueba_cuerpo_tecnico_cambios.csv sobre lo
   cargado en MJ4.
   Esperado: 3 leídos, 1 sin cambios (el director técnico de ZZA), 1
   actualizado (el ayudante de campo, ahora nacido en Uruguay) y 1 rechazado:
   otro director técnico para ZZB, que ya tiene. Siguen 3 personas en el
   cuerpo técnico de prueba. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_cuerpo_tecnico_cambios.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MJ5 verificacion' AS caso, i.leidos, i.insertados, i.actualizados, i.sin_cambios, i.rechazados,
       (SELECT pn.codigo_fifa FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
        INNER JOIN DatosGenerales.PAIS AS pn ON pn.id_pais = ct.id_pais_nacimiento
        WHERE ct.apellido = N'Ayudante' AND ct.nombre = N'Rubén') AS pais_ayudante,
       IIF(i.leidos = 3 AND i.insertados = 0 AND i.actualizados = 1 AND i.sin_cambios = 1 AND i.rechazados = 1
           AND (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
                INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                WHERE p.codigo_fifa IN ('ZZA', 'ZZB')) = 3, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MJ5 rechazados' AS caso, registro AS linea, codigo_fifa, rol, nombre, apellido,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Torneo.ERRORES_CUERPO_TECNICO
WHERE id_importacion = @id_importacion
ORDER BY registro;
GO


/* ============================================================================
   ARCHIVOS QUE NO SE PUEDEN IMPORTAR Y VALIDACIONES DE PARÁMETROS
   ============================================================================ */

/* MJ6 (ERROR) Archivos que no se pueden importar:
     a) mundial_prueba_columnas.csv, un CSV con otras columnas, como jugadores;
     b) un archivo de jugadores que no existe;
     c) mundial_prueba_jugadores.csv como archivo de cuerpo técnico (otras
        columnas).
   Esperado: tres errores 50002, cada uno con su motivo, sin nada importado. */
DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
DECLARE @archivo NVARCHAR(400);

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_columnas.csv';
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;
    PRINT N'MJ6a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MJ6a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'no_existe.csv';
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;
    PRINT N'MJ6b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MJ6b', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_jugadores.csv';
    EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo;
    PRINT N'MJ6c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MJ6c', @error_esperado = 50002;
END CATCH;
GO


/* MJ7 (ERROR) Parámetros inválidos:
     a) un .txt como CSV de jugadores;
     b) ruta vacía para el CSV de jugadores;
     c) un .json como CSV de cuerpo técnico.
   Esperado: tres errores 50001, sin leer el archivo. */
BEGIN TRY
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = N'C:\jugadores.txt';
    PRINT N'MJ7a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MJ7a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = N' ';
    PRINT N'MJ7b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MJ7b', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = N'C:\cuerpo_tecnico.json';
    PRINT N'MJ7c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MJ7c', @error_esperado = 50001;
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
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido = N'Prueba' AND club_origen LIKE N'Club%Prueba%') AS jugadores_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido IN (N'Prueba', N'Ayudante', N'Técnica')) AS cuerpo_tecnico_de_prueba,
       (SELECT COUNT(*) FROM Torneo.NOMBRE_ALTERNATIVO WHERE nombre IN (N'Testland A', N'Testland B')) AS nombres_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION
        WHERE origen LIKE CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial[_]prueba%') AS importaciones_de_prueba;
GO

SET NOEXEC OFF;
GO
