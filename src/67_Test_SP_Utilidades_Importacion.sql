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

 Fecha: 31/10/2026
 Archivo: 67_Test_SP_Utilidades_Importacion.sql
 Objetivo: Probar DatosGenerales.usp_ConsumirAPI de 17_SP_Utilidades_Importacion.sql:
           sus validaciones, un pedido a la API del Banco Mundial, una ruta
           que la API no tiene y un servidor que no existe. Los casos CA2 y
           CA3 necesitan internet.
           Requiere haber ejecutado 01 a 28. No modifica ninguna tabla, así
           que se puede ejecutar más de una vez.
================================================================================

 OLE Automation: los casos CA2 a CA4 hacen el pedido con OLE Automation. Si
 la instancia lo tiene deshabilitado, el test lo habilita antes de esos
 casos y después lo deja como estaba. Hace falta ser sysadmin.

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el código HTTP y el largo y el comienzo de
     la respuesta.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con otro número de error, se imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar OLE Automation y las
     opciones avanzadas con el mismo valor que antes del test.
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

IF OBJECT_ID(N'DatosGenerales.usp_ConsumirAPI', N'P') IS NULL
BEGIN
    RAISERROR(N'Falta el SP que consume APIs: ejecutar los scripts 01 a 28.', 16, 1);
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


/* CA1 (ERROR) Una URL vacía y una que no es https.
   Esperado: dos errores 50001 de validación, sin hacer ningún pedido. Si OLE
   Automation está deshabilitado, cada mensaje también lo informa. */
BEGIN TRY
    EXEC DatosGenerales.usp_ConsumirAPI @url = N'  ';
    PRINT N'CA1a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA1a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ConsumirAPI @url = N'http://api.worldbank.org/v2/country/all/indicator/NY.GDP.PCAP.CD';
    PRINT N'CA1b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA1b', @error_esperado = 50001;
END CATCH;
GO


-- OLE Automation para los casos CA2 a CA4, si estaba deshabilitado.
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


/* CA2 (OK, requiere internet) PBI per cápita de Argentina de 2000 a 2024 en
   la API del Banco Mundial: una respuesta de unos 7500 caracteres, más que
   los 4000 que admite un parámetro OUTPUT de sp_OAGetProperty.
   Esperado: código HTTP 200, largo mayor que 4000 y la respuesta completa
   (termina con </wb:data>, el cierre del documento).
   Sin conexión: error 50002 (no se pudo enviar el pedido). */
DECLARE @estado_http SMALLINT;
DECLARE @respuesta NVARCHAR(MAX);

BEGIN TRY
    EXEC DatosGenerales.usp_ConsumirAPI
        @url = N'https://api.worldbank.org/v2/country/ARG/indicator/NY.GDP.PCAP.CD?date=2000:2024&format=xml',
        @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;

    SELECT 'CA2 pedido' AS caso, @estado_http AS estado_http, LEN(@respuesta) AS largo_respuesta,
           IIF(RIGHT(@respuesta, 10) = N'</wb:data>', 'SI', 'NO') AS respuesta_completa,
           LEFT(@respuesta, 150) AS comienzo_respuesta;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'CA2: no se pudo consultar la API (¿hay conexión a internet?). Error ', ERROR_NUMBER(), N':',
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END CATCH;
GO


/* CA3 (OK, requiere internet) Una ruta que la API del Banco Mundial no tiene.
   El SP no decide qué respuesta es un error: devuelve el código HTTP y quien
   llama lo evalúa (usp_ImportarIndicadoresAPI no importa nada si no es 200).
   Esperado: sin error, código HTTP 404.
   Sin conexión: error 50002 (no se pudo enviar el pedido). */
DECLARE @estado_http SMALLINT;
DECLARE @respuesta NVARCHAR(MAX);

BEGIN TRY
    EXEC DatosGenerales.usp_ConsumirAPI
        @url = N'https://api.worldbank.org/v2/no-existe',
        @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;

    SELECT 'CA3 ruta inexistente' AS caso, @estado_http AS estado_http, LEN(@respuesta) AS largo_respuesta;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'CA3: no se pudo consultar la API (¿hay conexión a internet?). Error ', ERROR_NUMBER(), N':',
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END CATCH;
GO


/* CA4 (ERROR) Un servidor que no existe (.invalid es un dominio reservado
   que nunca se resuelve).
   Esperado: error 50002, no se pudo enviar el pedido porque el nombre del
   servidor no se pudo resolver. Sin conexión es el mismo error. */
BEGIN TRY
    EXEC DatosGenerales.usp_ConsumirAPI @url = N'https://servidor-inexistente.invalid/';
    PRINT N'CA4: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA4', @error_esperado = 50002;
END CATCH;
GO


-- OLE Automation vuelve a como estaba antes del test.
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


/* CA5 (ERROR) Con OLE Automation deshabilitado. Solo se prueba si la
   instancia lo tenía deshabilitado antes del test (y ya volvió a estarlo).
   Esperado: error 50001 con 1 condición: la instancia no tiene habilitada la
   opción 'Ole Automation Procedures'. */
IF CAST(SESSION_CONTEXT(N'ole_antes') AS INT) = 1
    PRINT N'CA5: no se prueba, porque la instancia tiene OLE Automation habilitado.';
ELSE
BEGIN
    BEGIN TRY
        EXEC DatosGenerales.usp_ConsumirAPI @url = N'https://api.worldbank.org/v2/country/ARG/indicator/NY.GDP.PCAP.CD';
        PRINT N'CA5: FALLÓ, se esperaba un error de validación.';
    END TRY
    BEGIN CATCH
        EXEC #usp_MostrarError @caso = 'CA5', @error_esperado = 50001;
    END CATCH;
END;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: OLE Automation y las opciones avanzadas con el mismo valor que
   antes del test.
   ============================================================================ */
SELECT 'Final' AS caso, c.name AS opcion, c.value_in_use AS valor_actual,
       CAST(SESSION_CONTEXT(IIF(c.name = N'show advanced options', N'avanzadas_antes', N'ole_antes')) AS INT) AS valor_antes
FROM sys.configurations AS c
WHERE c.name IN (N'Ole Automation Procedures', N'show advanced options');
GO

SET NOEXEC OFF;
GO
