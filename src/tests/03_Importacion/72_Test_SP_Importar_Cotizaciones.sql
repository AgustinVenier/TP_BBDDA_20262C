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
 Archivo: 72_Test_SP_Importar_Cotizaciones.sql
 Objetivo: Probar la importación de cotizaciones de 22_SP_Importar_Cotizaciones.sql,
           con el registro de cada importación y de sus rechazados
           (DatosGenerales.ERRORES_COTIZACION):
             - procesando respuestas con el formato de la API Frankfurter
               escritas en el test: alta, reimportación sin duplicados,
               actualización, importación con errores parciales y los
               documentos que no se pueden importar;
             - consultando la API Frankfurter (casos AP, necesitan internet).
           Las reglas de las cotizaciones las prueba 66_Test_SP_CargaMasiva.sql,
           con DatosGenerales.usp_CargarCotizaciones.
           Requiere haber ejecutado 01 a 28. No depende del juego de datos:
           las respuestas escritas usan XTS y XXX, los códigos de ISO 4217
           para pruebas y para "sin moneda", que ninguna API cotiza, y el
           caso de la API trae ARS y EUR de dos días de 2024 dentro de una
           transacción que se deshace. Al final se borra lo que cargó el
           test, con el registro de sus importaciones, así que se puede
           ejecutar más de una vez.
================================================================================

 OLE Automation: los casos AP llaman a la API con OLE Automation. Si la
 instancia lo tiene deshabilitado, el test lo habilita antes de esos casos y
 después lo deja como estaba. Hace falta ser sysadmin.

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el resumen de la importación (leídos,
     insertados, actualizados, sin cambios, omitidos y rechazados), los
     omitidos por motivo, los rechazados con sus motivos y los datos que
     quedaron.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con otro número de error, se imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 cotizaciones de prueba y
     OLE Automation como estaba antes del test.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
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

IF OBJECT_ID(N'DatosGenerales.usp_ImportarCotizacionesAPI', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_CargarCotizaciones', N'P') IS NULL
BEGIN
    RAISERROR(N'Faltan los SP de importación de cotizaciones: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Por si una corrida anterior del test quedó a medias: las 6 cotizaciones que cargan
-- los casos CX y el registro de sus importaciones, con sus rechazados.
DELETE FROM DatosGenerales.COTIZACION
WHERE (codigo_moneda = 'XTS' AND fecha IN ('2026-06-11', '2026-06-12', '2026-06-15', '2026-06-16'))
   OR (codigo_moneda = 'XXX' AND fecha IN ('2026-06-11', '2026-06-12'));
DELETE e FROM DatosGenerales.ERRORES_COTIZACION AS e
INNER JOIN DatosGenerales.IMPORTACION AS i ON i.id_importacion = e.id_importacion
WHERE i.origen IN (N'CX1', N'CX2', N'CX3', N'CX4');
DELETE FROM DatosGenerales.IMPORTACION WHERE origen IN (N'CX1', N'CX2', N'CX3', N'CX4');
GO


/* CX1 (OK) Importación de una respuesta con 4 registros.
   Esperado: 4 leídos, 3 insertados (XTS del 11 y del 12/06, XXX del 11/06) y
   1 omitido (el dólar contra el dólar). Quedan XTS 1000.500000 y
   1001.250000, y XXX 2.500000. */
DECLARE @json NVARCHAR(MAX) = N'[
    {"date":"2026-06-11","base":"USD","quote":"XTS","rate":1000.5},
    {"date":"2026-06-12","base":"USD","quote":"XTS","rate":1001.25},
    {"date":"2026-06-11","base":"USD","quote":"XXX","rate":2.5},
    {"date":"2026-06-11","base":"USD","quote":"USD","rate":1.0}]';

EXEC DatosGenerales.usp_ProcesarCotizacionesJSON @json = @json, @origen = N'CX1';

SELECT 'CX1 cotizaciones' AS caso, codigo_moneda, fecha, unidades_por_usd
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda IN ('XTS', 'XXX')
ORDER BY codigo_moneda, fecha;
GO


/* CX2 (OK) Reimportación de la misma respuesta.
   Esperado: 3 sin cambios y 1 omitido; siguen las mismas 3 filas (no se
   duplica nada). */
DECLARE @json NVARCHAR(MAX) = N'[
    {"date":"2026-06-11","base":"USD","quote":"XTS","rate":1000.5},
    {"date":"2026-06-12","base":"USD","quote":"XTS","rate":1001.25},
    {"date":"2026-06-11","base":"USD","quote":"XXX","rate":2.5},
    {"date":"2026-06-11","base":"USD","quote":"USD","rate":1.0}]';

EXEC DatosGenerales.usp_ProcesarCotizacionesJSON @json = @json, @origen = N'CX2';

SELECT 'CX2 después' AS caso, COUNT(*) AS cotizaciones
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda IN ('XTS', 'XXX');
GO


/* CX3 (OK) La fuente corrige XTS del 12/06 y agrega XXX del 12/06.
   Esperado: 3 leídos: 1 insertado (XXX 2.600000), 1 actualizado (XTS del
   12/06 pasa de 1001.250000 a 1010.000000 y renueva su fecha_actualizacion)
   y 1 sin cambios (XTS del 11/06). Quedan 4 filas. */
DECLARE @json NVARCHAR(MAX) = N'[
    {"date":"2026-06-11","base":"USD","quote":"XTS","rate":1000.5},
    {"date":"2026-06-12","base":"USD","quote":"XTS","rate":1010},
    {"date":"2026-06-12","base":"USD","quote":"XXX","rate":2.6}]';

EXEC DatosGenerales.usp_ProcesarCotizacionesJSON @json = @json, @origen = N'CX3';

SELECT 'CX3 cotizaciones' AS caso, codigo_moneda, fecha, unidades_por_usd, fecha_actualizacion
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda IN ('XTS', 'XXX')
ORDER BY codigo_moneda, fecha;
GO


/* CX4 (OK) Importación con errores parciales: 9 registros.
   Esperado: 9 leídos, 2 insertados (XTS del 15/06, 1020.000000, y del
   16/06, 1000.000000, que viene en notación científica) y 7 rechazados, con
   estos motivos:
     XTS 2026-06-17   la cotización es contra EUR y no contra el dólar.
     X1 2026-06-15    la moneda no es un código de 3 letras.
     XTS 15/06/2026   la fecha no es una fecha (AAAA-MM-DD).
     XTS (mañana)     la fecha es futura.
     XTS 2026-06-18   el valor "abc" no es un número.
     XTS 2026-06-19   el valor tiene que ser mayor que cero (-1).
     XTS 2026-06-20   el valor es obligatorio (no viene rate).
   Los 7 rechazados quedan en
   DatosGenerales.ERRORES_COTIZACION, con el número de la importación y el
   texto que traía la respuesta. */
DECLARE @manana CHAR(10) = CONVERT(CHAR(10), DATEADD(DAY, 1, CONVERT(DATE, GETDATE())), 23);
DECLARE @json NVARCHAR(MAX) = CONCAT(N'[
    {"date":"2026-06-15","base":"USD","quote":"XTS","rate":1020},
    {"date":"2026-06-16","base":"USD","quote":"XTS","rate":1.0E+3},
    {"date":"2026-06-17","base":"EUR","quote":"XTS","rate":1100},
    {"date":"2026-06-15","base":"USD","quote":"X1","rate":5},
    {"date":"15/06/2026","base":"USD","quote":"XTS","rate":1020},
    {"date":"', @manana, N'","base":"USD","quote":"XTS","rate":1030},
    {"date":"2026-06-18","base":"USD","quote":"XTS","rate":"abc"},
    {"date":"2026-06-19","base":"USD","quote":"XTS","rate":-1},
    {"date":"2026-06-20","base":"USD","quote":"XTS"}]');

DECLARE @id_importacion INT;

EXEC DatosGenerales.usp_ProcesarCotizacionesJSON @json = @json, @origen = N'CX4', @id_importacion = @id_importacion OUTPUT;

SELECT 'CX4 registro' AS caso, i.leidos, i.insertados, i.omitidos, i.rechazados, e.registro, e.fecha, e.moneda_base,
       e.codigo_moneda, e.valor, REPLACE(e.motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM DatosGenerales.IMPORTACION AS i
INNER JOIN DatosGenerales.ERRORES_COTIZACION AS e ON e.id_importacion = i.id_importacion
WHERE i.id_importacion = @id_importacion
ORDER BY e.registro;

SELECT 'CX4 importados' AS caso, codigo_moneda, fecha, unidades_por_usd
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda IN ('XTS', 'XXX') AND fecha >= '2026-06-15'
ORDER BY codigo_moneda, fecha;
GO


/* CX5 (ERROR) Documentos que no se pueden importar:
     a) un texto que no es JSON (respuesta cortada);
     b) el mensaje de error de la API ante una moneda que no existe;
     c) un objeto en vez de un arreglo.
   Esperado: error 50002 en los tres, sin importar nada. */
BEGIN TRY
    EXEC DatosGenerales.usp_ProcesarCotizacionesJSON @json = N'[{"date":"2026-06-11","base":"US', @origen = N'CX5a';
    PRINT N'CX5a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
        PRINT N'CX5a: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'CX5a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ProcesarCotizacionesJSON
        @json = N'{"status":422,"message":"invalid currency: XYZ"}', @origen = N'CX5b';
    PRINT N'CX5b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
        PRINT N'CX5b: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'CX5b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ProcesarCotizacionesJSON
        @json = N'{"date":"2026-06-11","base":"USD","quote":"XTS","rate":1000}', @origen = N'CX5c';
    PRINT N'CX5c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
        PRINT N'CX5c: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'CX5c: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* AP1 (ERROR) Consulta a la API con parámetros inválidos.
     a) monedas separadas por coma y fecha hasta futura;
     b) fecha desde mayor que fecha hasta;
     c) rango de más de un año.
   Esperado: error 50001 con 2 condiciones y error 50001 con 1 condición en
   los otros dos, sin consultar la API. */
DECLARE @manana DATE = DATEADD(DAY, 1, CONVERT(DATE, GETDATE()));

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI @monedas = 'ARS,EUR', @fecha_hasta = @manana;
    PRINT N'AP1a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP1a: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP1a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI @fecha_desde = '2026-07-01', @fecha_hasta = '2026-06-01';
    PRINT N'AP1b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP1b: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP1b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI @fecha_desde = '2024-01-01', @fecha_hasta = '2025-06-01';
    PRINT N'AP1c: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP1c: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP1c: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


-- OLE Automation para los casos AP2 y AP3, si estaba deshabilitado.
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


/* AP2 (OK, requiere internet) Cotizaciones de ARS y EUR del 2 y el 3 de
   enero de 2024, consultando la API, dentro de una transacción que se
   deshace al final del caso.
   Esperado: 4 leídos y 4 insertados (o sin cambios, si ya estaban), y las 4
   filas con lo que publica la fuente (unos 810 ARS y 0,91 EUR por dólar).
   Sin conexión: error 50002 (no se pudo enviar el pedido). */
BEGIN TRANSACTION;
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI
        @monedas = 'ARS;EUR', @fecha_desde = '2024-01-02', @fecha_hasta = '2024-01-03';

    SELECT 'AP2 cotizaciones' AS caso, codigo_moneda, fecha, unidades_por_usd
    FROM DatosGenerales.COTIZACION
    WHERE codigo_moneda IN ('ARS', 'EUR') AND fecha BETWEEN '2024-01-02' AND '2024-01-03'
    ORDER BY codigo_moneda, fecha;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'AP2: no se pudo consultar la API (¿hay conexión a internet?). Error ', ERROR_NUMBER(), N':',
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* AP3 (ERROR, requiere internet) Moneda con formato válido que no existe.
   Esperado: error 50002, la API respondió con el código HTTP 422 ("invalid
   currency: XYZ"). Sin conexión también es 50002, pero porque no se pudo
   enviar el pedido. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI @monedas = 'ARS;XYZ';
    PRINT N'AP3: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
        PRINT N'AP3: OK, falló como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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


-- Se borra lo que cargaron los casos CX, con el registro de sus importaciones.
DELETE FROM DatosGenerales.COTIZACION
WHERE (codigo_moneda = 'XTS' AND fecha IN ('2026-06-11', '2026-06-12', '2026-06-15', '2026-06-16'))
   OR (codigo_moneda = 'XXX' AND fecha IN ('2026-06-11', '2026-06-12'));
DELETE e FROM DatosGenerales.ERRORES_COTIZACION AS e
INNER JOIN DatosGenerales.IMPORTACION AS i ON i.id_importacion = e.id_importacion
WHERE i.origen IN (N'CX1', N'CX2', N'CX3', N'CX4');
DELETE FROM DatosGenerales.IMPORTACION WHERE origen IN (N'CX1', N'CX2', N'CX3', N'CX4');
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 cotizaciones e importaciones de prueba, y OLE Automation y las
   opciones avanzadas con el mismo valor que antes del test.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.COTIZACION WHERE codigo_moneda IN ('XTS', 'XXX')) AS cotizaciones_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION WHERE origen IN (N'CX1', N'CX2', N'CX3', N'CX4')) AS importaciones_de_prueba;

SELECT 'Final' AS caso, c.name AS opcion, c.value_in_use AS valor_actual,
       CAST(SESSION_CONTEXT(IIF(c.name = N'show advanced options', N'avanzadas_antes', N'ole_antes')) AS INT) AS valor_antes
FROM sys.configurations AS c
WHERE c.name IN (N'Ole Automation Procedures', N'show advanced options');
GO

SET NOEXEC OFF;
GO
