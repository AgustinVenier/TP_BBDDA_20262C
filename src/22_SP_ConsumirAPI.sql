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
 Archivo: 22_SP_ConsumirAPI.sql
 Objetivo: Crear el SP que consume APIs REST desde T-SQL:
             DatosGenerales.usp_ConsumirAPI  hace un pedido GET a una URL https
           No depende de ninguna API: lo usan los procesos que consultan una,
           como la importación de indicadores del Banco Mundial
           (25_SP_Importar_Indicadores.sql), de cotizaciones de Frankfurter
           (26_SP_Importar_Cotizaciones.sql) y de feriados de Nager.Date
           (27_SP_Importar_Feriados.sql).
           Requiere haber ejecutado 01 y 02. Su script de testing es
           72_Test_SP_ConsumirAPI.sql.
================================================================================

 SQL Server 2022 (el motor de la Entrega 4) no tiene un procedimiento propio
 para llamar a una API REST (sp_invoke_external_rest_endpoint recién está en
 SQL Server 2025). Por eso se usa OLE Automation con MSXML2.ServerXMLHTTP,
 que corre dentro del motor y no necesita CLR.

 OLE Automation: requiere la opción de instancia 'Ole Automation Procedures',
 que viene deshabilitada. Quien consulta una API la habilita solo mientras
 llama a este SP y después la deja como estaba, como hace
 30_Ejecutar_ImportarIndicadores.sql. Hace falta ser sysadmin.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ConsumirAPI
  Hace un pedido GET a @url y devuelve el código HTTP y el cuerpo de la
  respuesta como texto. Sirve para cualquier API REST que no pida
  autenticación. Valida: URL obligatoria y https, y OLE Automation habilitado
  en la instancia. Si el pedido no se puede hacer (sin conexión, servidor
  inexistente, tiempo agotado), lanza el error 50002 con el motivo que
  informa MSXML.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ConsumirAPI
    @url          NVARCHAR(2000),
    @estado_http  SMALLINT      = NULL OUTPUT,
    @respuesta    NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- sp_OAGetProperty corta el texto en @@TEXTSIZE bytes (sqlcmd usa 4096). Vuelve a su valor al salir.
    SET TEXTSIZE 2147483647;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @http         INT;
    DECLARE @hr           INT;
    DECLARE @estado       INT;
    DECLARE @paso         NVARCHAR(50);
    DECLARE @fuente       NVARCHAR(255);
    DECLARE @descripcion  NVARCHAR(2000);
    DECLARE @blancos      NCHAR(3)       = NCHAR(13) + NCHAR(10) + N' ';
    DECLARE @texto        TABLE (texto NVARCHAR(MAX));

    SET @url = NULLIF(TRIM(@url), N'');

    IF @url IS NULL
        SET @errores += @nl + N'- La URL es obligatoria.';
    ELSE IF @url NOT LIKE N'https://%'
        SET @errores += @nl + N'- La URL tiene que empezar con https://.';

    IF NOT EXISTS (SELECT 1 FROM sys.configurations
                   WHERE name = N'Ole Automation Procedures' AND value_in_use = 1)
        SET @errores += @nl + N'- La instancia no tiene habilitada la opción ''Ole Automation Procedures'', '
                      + N'que se usa para llamar a la API (ver 22_SP_ConsumirAPI.sql).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ConsumirAPI: no se pudo consultar la API.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Pedido sincrónico. Cada paso devuelve un HRESULT (0 es éxito); si uno falla, no se sigue.
    SET @paso = N'crear el objeto MSXML2.ServerXMLHTTP';
    EXEC @hr = sp_OACreate 'MSXML2.ServerXMLHTTP.6.0', @http OUTPUT;
    IF @hr = 0
    BEGIN
        -- Tiempos máximos en milisegundos: resolver el nombre, conectar, enviar y recibir.
        SET @paso = N'configurar los tiempos de espera';
        EXEC @hr = sp_OAMethod @http, 'setTimeouts', NULL, 10000, 10000, 10000, 60000;
    END;
    IF @hr = 0
    BEGIN
        SET @paso = N'abrir el pedido';
        EXEC @hr = sp_OAMethod @http, 'open', NULL, 'GET', @url, 'false';
    END;
    IF @hr = 0
    BEGIN
        SET @paso = N'enviar el pedido';
        EXEC @hr = sp_OAMethod @http, 'send';
    END;
    IF @hr = 0
    BEGIN
        SET @paso = N'leer el código de la respuesta';
        EXEC @hr = sp_OAGetProperty @http, 'status', @estado OUTPUT;
    END;
    IF @hr = 0
    BEGIN
        -- Como conjunto de resultados y no como OUTPUT, que no admite más de 4000 caracteres.
        SET @paso = N'leer la respuesta';
        INSERT INTO @texto (texto)
        EXEC @hr = sp_OAGetProperty @http, 'responseText';
    END;

    IF @hr <> 0
        EXEC sp_OAGetErrorInfo @http, @fuente OUTPUT, @descripcion OUTPUT;
    IF @http IS NOT NULL
        EXEC sp_OADestroy @http;

    IF @hr <> 0
    BEGIN
        SET @errores = N'DatosGenerales.usp_ConsumirAPI: no se pudo ' + @paso + N' ('
                     + ISNULL(TRIM(@blancos FROM @descripcion),
                              N'HRESULT ' + CONVERT(NVARCHAR(20), CONVERT(VARBINARY(4), @hr), 1))
                     + N').';
        THROW 50002, @errores, 1;
    END;

    SET @estado_http = @estado;
    SELECT @respuesta = texto FROM @texto;
END;
GO


-- Evidencia: SP creado.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DatosGenerales' AND p.name = N'usp_ConsumirAPI';
GO
