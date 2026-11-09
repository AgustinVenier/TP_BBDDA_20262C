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

 Fecha: 02/11/2026
 Archivo: 70_Test_SP_Importar_Publicidad.sql
 Objetivo: Probar la importación de campañas del Dossier Mundial de
           20_SP_Importar_Publicidad.sql, con el registro de cada
           importación y de sus rechazadas (Publicidad.ERRORES_CAMPANIA):
             - procesando respuestas con el formato de la API REST de
               Firestore escritas en el test: alta, reimportación sin
               duplicados, actualización, importación con errores parciales
               y los documentos y parámetros que no se pueden importar;
             - consultando la API (caso AP1, necesita internet).
           Las reglas de anunciantes, campañas y piezas las prueba
           66_Test_SP_CargaMasiva.sql, con Publicidad.usp_CargarCampanias.
           Requiere haber ejecutado 01 a 28. No depende del juego de datos:
           las campañas de prueba son del "Anunciante Prueba 71". Los casos
           CD y AP1 corren dentro de una transacción que se deshace, así que
           el test no deja datos y se puede ejecutar más de una vez.
================================================================================

 OLE Automation: el caso AP1 llama a la API con OLE Automation. Si la
 instancia lo tiene deshabilitado, el test lo habilita antes de ese caso y
 después lo deja como estaba. Hace falta ser sysadmin.

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el resumen de la importación (leídos,
     insertados, actualizados, sin cambios, omitidos y rechazados), las
     rechazadas con sus motivos, las campañas cargadas y los datos que
     quedaron.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con otro número de error, se imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba y OLE
     Automation como estaba antes del test.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los índices filtrados y los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

-- Configuración de OLE Automation antes del test (para los lotes siguientes).
DECLARE @ole_antes INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                          WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                WHERE name = N'show advanced options');

EXEC sp_set_session_context @key = N'ole_antes', @value = @ole_antes;
EXEC sp_set_session_context @key = N'avanzadas_antes', @value = @avanzadas_antes;

IF OBJECT_ID(N'Publicidad.usp_ImportarCampaniasAPI', N'P') IS NULL
   OR OBJECT_ID(N'Publicidad.usp_CargarCampanias', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_ConsumirAPI', N'P') IS NULL
BEGIN
    RAISERROR(N'Faltan los SP de importación de campañas: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
ELSE IF @@TRANCOUNT > 0
BEGIN
    RAISERROR(N'Hay una transacción abierta: este test usa la suya y la deshace al final. Cerrarla y volver a ejecutar.', 16, 1);
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


/* ============================================================================
   CASOS CD: RESPUESTAS ESCRITAS EN EL TEST, DENTRO DE UNA TRANSACCIÓN
   ============================================================================ */
SET XACT_ABORT OFF;
BEGIN TRANSACTION;
GO


/* CD1 (OK) Importación de una respuesta con 8 campañas (importación con
   errores parciales).
   Esperado: 8 leídos, 3 insertados y 5 rechazados.
     - 1 "Campaña Prueba 71 Uno": INSERTADO, con 1 pieza (su video de portada).
     - 2 "Campaña Prueba 71 Dos": INSERTADO, con 3 piezas: "Dos", "Dos (2)" y
       "Dos (3)". El video de portada se repite en la lista y otro viene dos
       veces: no duplican piezas. bbbbbbbbbb1 y BBBBBBBBBB1 son dos videos
       distintos (YouTube distingue mayúsculas).
     - 3 sin anunciante: RECHAZADO.
     - 4 nombre de 151 caracteres: RECHAZADO (la campaña y su pieza).
     - 5 y 6 la misma campaña del mismo anunciante dos veces: RECHAZADO.
     - 7 un elemento que no es un objeto: RECHAZADO (sin anunciante, sin
       nombre y su pieza sin título).
     - 8 "Campaña Prueba 71 Sin Video": INSERTADO, con 1 pieza.
   Todas del 11/06 al 19/07/2026, del país ARG, con piezas en español y
   mercado ARG. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @json NVARCHAR(MAX) = CAST(N'' AS NVARCHAR(MAX)) + N'{"documents": [
    {"name": "projects/p/databases/(default)/documents/campanas/cd1",
     "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                "titulo": {"stringValue": "Campaña Prueba 71 Uno"},
                "youtube": {"stringValue": "aaaaaaaaaa1"},
                "creditos": {"mapValue": {"fields": {"Director": {"stringValue": "No se importa"}}}}}},
    {"name": "projects/p/databases/(default)/documents/campanas/cd2",
     "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                "titulo": {"stringValue": "Campaña Prueba 71 Dos"},
                "youtube": {"stringValue": "bbbbbbbbbb1"},
                "videos": {"arrayValue": {"values": [{"stringValue": "bbbbbbbbbb1"}, {"stringValue": "BBBBBBBBBB1"},
                                                     {"stringValue": "bbbbbbbbbb2"}, {"stringValue": "bbbbbbbbbb2"}]}}}},
    {"name": "projects/p/databases/(default)/documents/campanas/cd3",
     "fields": {"titulo": {"stringValue": "Campaña Prueba 71 Sin Anunciante"},
                "youtube": {"stringValue": "cccccccccc1"}}},
    {"name": "projects/p/databases/(default)/documents/campanas/cd4",
     "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                "titulo": {"stringValue": "' + REPLICATE(N'x', 151) + N'"},
                "youtube": {"stringValue": "dddddddddd1"}}},
    {"name": "projects/p/databases/(default)/documents/campanas/cd5",
     "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                "titulo": {"stringValue": "Campaña Prueba 71 Repetida"}}},
    {"name": "projects/p/databases/(default)/documents/campanas/cd6",
     "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                "titulo": {"stringValue": "Campaña Prueba 71 Repetida"}}},
    "no es un objeto",
    {"name": "projects/p/databases/(default)/documents/campanas/cd8",
     "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                "titulo": {"stringValue": "Campaña Prueba 71 Sin Video"}}}]}';

EXEC Publicidad.usp_ProcesarCampaniasJSON @json = @json, @origen = N'CD1';

SELECT 'CD1 cargado' AS caso, an.razon_social, pa.codigo_fifa AS pais, c.nombre AS campania, c.fecha_inicio, c.fecha_fin,
       pz.titulo AS pieza, i.codigo_iso AS idioma,
       (SELECT STRING_AGG(p2.codigo_fifa, ', ')
        FROM Publicidad.PIEZA_PAIS_INTERES AS ppi INNER JOIN DatosGenerales.PAIS AS p2 ON p2.id_pais = ppi.id_pais
        WHERE ppi.id_pieza = pz.id_pieza) AS mercados
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
WHERE an.razon_social = N'Anunciante Prueba 71'
ORDER BY c.nombre, pz.titulo;

-- Para los casos siguientes (se crea dentro de la transacción: el ROLLBACK la borra).
CREATE TABLE #json_cd (json NVARCHAR(MAX) NOT NULL);
INSERT INTO #json_cd (json) VALUES (@json);
GO


/* CD2 (OK) La misma respuesta otra vez.
   Esperado: 8 leídos, 3 sin cambios y 5 rechazados (con los mismos motivos
   que en CD1). Siguen siendo 3 campañas y 5 piezas del anunciante de
   prueba. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @json NVARCHAR(MAX) = (SELECT json FROM #json_cd);

EXEC Publicidad.usp_ProcesarCampaniasJSON @json = @json, @origen = N'CD2';

SELECT 'CD2 sin duplicados' AS caso, COUNT(DISTINCT c.id_campania) AS campanias, COUNT(*) AS piezas
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
WHERE an.razon_social = N'Anunciante Prueba 71';
GO


/* CD3 (OK) La misma respuesta con un video nuevo en "Uno" y otro período
   (del 11/06 al 31/07/2026).
   Esperado: 8 leídos, 3 actualizados y 5 rechazados. "Uno" suma la pieza
   "Campaña Prueba 71 Uno (2)" y las piezas que ya tenía no cambian de
   título; las tres campañas quedan hasta el 31/07/2026. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @json NVARCHAR(MAX) = REPLACE((SELECT json FROM #json_cd),
    N'"youtube": {"stringValue": "aaaaaaaaaa1"},',
    N'"youtube": {"stringValue": "aaaaaaaaaa1"}, "videos": {"arrayValue": {"values": [{"stringValue": "aaaaaaaaaa1"}, {"stringValue": "aaaaaaaaaa2"}]}},');

EXEC Publicidad.usp_ProcesarCampaniasJSON @json = @json, @origen = N'CD3', @fecha_fin = '2026-07-31';

SELECT 'CD3 cargado' AS caso, c.nombre AS campania, c.fecha_inicio, c.fecha_fin, pz.titulo AS pieza
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
WHERE an.razon_social = N'Anunciante Prueba 71'
ORDER BY c.nombre, pz.titulo;
GO


/* CD4 (OK) El registro de las importaciones de CD1 a CD3.
   Esperado: tres importaciones de Publicidad.usp_ProcesarCampaniasJSON
   (origen CD1, CD2 y CD3), cada una con 5 rechazadas en
   Publicidad.ERRORES_CAMPANIA (registros 3 a 7). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

SELECT 'CD4' AS caso, im.origen, im.proceso, im.leidos, im.insertados, im.actualizados, im.sin_cambios, im.rechazados,
       (SELECT STRING_AGG(CAST(e.registro AS VARCHAR(5)), ', ') WITHIN GROUP (ORDER BY e.registro)
        FROM Publicidad.ERRORES_CAMPANIA AS e WHERE e.id_importacion = im.id_importacion) AS registros_rechazados
FROM DatosGenerales.IMPORTACION AS im
WHERE im.origen IN (N'CD1', N'CD2', N'CD3')
ORDER BY im.origen;
GO


-- Se deshace todo lo que cargaron los casos CD.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #json_cd;
GO


/* ============================================================================
   CASOS QUE NO SE PUEDEN IMPORTAR (no cargan nada)
   ============================================================================ */

/* ER1 (ERROR) Documentos que no son una respuesta de campañas:
     a) un texto que no es JSON;
     b) un mensaje de error de Firestore;
     c) un objeto vacío (la respuesta de una colección sin documentos).
   Esperado: tres errores 50002. */
BEGIN TRY
    EXEC Publicidad.usp_ProcesarCampaniasJSON @json = N'<html>no es JSON</html>', @origen = N'ER1a';
    PRINT N'ER1a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER1a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    EXEC Publicidad.usp_ProcesarCampaniasJSON
         @json = N'{"error": {"code": 403, "message": "Missing or insufficient permissions.", "status": "PERMISSION_DENIED"}}',
         @origen = N'ER1b';
    PRINT N'ER1b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER1b', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    EXEC Publicidad.usp_ProcesarCampaniasJSON @json = N'{}', @origen = N'ER1c';
    PRINT N'ER1c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER1c', @error_esperado = 50002;
END CATCH;
GO


/* ER2 (ERROR) Parámetros inválidos, con un documento válido:
     a) la fecha de fin anterior a la de inicio;
     b) un país y un idioma que no existen (los dos motivos juntos).
   Esperado: dos errores 50001. */
DECLARE @json NVARCHAR(MAX) = N'{"documents": [{"name": "x/cd1", "fields": {"anunciante": {"stringValue": "Anunciante Prueba 71"},
                                 "titulo": {"stringValue": "Campaña Prueba 71 Uno"}}}]}';
BEGIN TRY
    EXEC Publicidad.usp_ProcesarCampaniasJSON @json = @json, @origen = N'ER2a',
         @fecha_inicio = '2026-07-19', @fecha_fin = '2026-06-11';
    PRINT N'ER2a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER2a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Publicidad.usp_ProcesarCampaniasJSON @json = @json, @origen = N'ER2b', @codigo_fifa = 'ZZZ', @codigo_idioma = 'zz';
    PRINT N'ER2b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER2b', @error_esperado = 50001;
END CATCH;
GO


/* ============================================================================
   CASO AP1: CONSULTA A LA API (necesita internet)
   ============================================================================ */

-- OLE Automation habilitado solo para este caso (sp_configure no puede ir dentro de una transacción).
IF CAST(SESSION_CONTEXT(N'ole_antes') AS INT) = 0
BEGIN
    IF CAST(SESSION_CONTEXT(N'avanzadas_antes') AS INT) = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 1;
        RECONFIGURE;
    END;
    EXEC sp_configure 'Ole Automation Procedures', 1;
    RECONFIGURE;
END;
GO

/* AP1 (OK) Importación desde la API, dentro de una transacción que se deshace.
   Esperado: el resumen con tantos leídos como campañas tenga el Dossier (75
   el 02/11/2026) y 0 rechazados. Si la base no tenía las campañas, quedan
   INSERTADO; si ya las importó 31_Importar_APIs.sql, SIN CAMBIOS. Sin
   conexión, se imprime el error 50002 de la consulta y no se carga nada. */
SET XACT_ABORT OFF;
BEGIN TRANSACTION;

DECLARE @id_importacion INT;
BEGIN TRY
    EXEC Publicidad.usp_ImportarCampaniasAPI @id_importacion = @id_importacion OUTPUT;

    SELECT 'AP1' AS caso, im.leidos, im.insertados, im.sin_cambios, im.rechazados,
           (SELECT COUNT(DISTINCT an.id_anunciante)
            FROM Publicidad.ANUNCIANTE AS an
            INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
            INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
            WHERE pa.codigo_fifa = 'ARG' AND c.fecha_inicio = '2026-06-11' AND c.fecha_fin = '2026-07-19') AS anunciantes_argentinos
    FROM DatosGenerales.IMPORTACION AS im
    WHERE im.id_importacion = @id_importacion;
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP1', @error_esperado = 50002;
END CATCH;

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- OLE Automation como estaba antes del test.
IF CAST(SESSION_CONTEXT(N'ole_antes') AS INT) = 0
BEGIN
    EXEC sp_configure 'Ole Automation Procedures', 0;
    RECONFIGURE;
    IF CAST(SESSION_CONTEXT(N'avanzadas_antes') AS INT) = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 0;
        RECONFIGURE;
    END;
END;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en las tres primeras columnas, y OLE Automation como estaba
   antes del test.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba 71')        AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.CAMPANIA WHERE nombre LIKE N'Campaña Prueba 71%')               AS campanias_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION WHERE origen IN (N'CD1', N'CD2', N'CD3'))       AS importaciones_de_prueba,
       (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'Ole Automation Procedures') AS ole_ahora,
       CAST(SESSION_CONTEXT(N'ole_antes') AS INT)                                                        AS ole_antes;
GO

SET NOEXEC OFF;
GO
