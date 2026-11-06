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
 Archivo: 78_Test_SP_Importar_Feriados.sql
 Objetivo: Probar la importación de feriados de 28_SP_Importar_Feriados.sql,
           con el registro de cada importación y de sus rechazados
           (DatosGenerales.ERRORES_FERIADO). Las reglas de los feriados las
           prueba 66_Test_SP_Importacion.sql, con
           DatosGenerales.usp_ImportarFeriados:
             - procesando respuestas con el formato de la API Nager.Date
               escritas en el test: alta (con Inglaterra y Escocia por
               separado), reimportación sin duplicados, actualización, dos
               feriados el mismo día, importación con errores parciales y los
               documentos que no se pueden importar;
             - consultando la API Nager.Date (casos AP, necesitan internet).
           Requiere haber ejecutado 00 a 28 (usa Argentina, Inglaterra y
           Escocia de 20_Ejecutar_DatosIniciales.sql). No depende del juego de datos:
           las respuestas escritas son de 2001, un año que no importa
           29_Ejecutar_ImportarAPIs.sql, y el caso de la API corre
           dentro de una transacción que se deshace. Al final se borra lo que
           cargó el test, con el registro de sus importaciones, así que se
           puede ejecutar más de una vez.
================================================================================

 OLE Automation: los casos AP llaman a la API con OLE Automation. Si la
 instancia lo tiene deshabilitado, el test lo habilita antes de esos casos y
 después lo deja como estaba. Hace falta ser sysadmin.

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el resumen de la importación (leídos,
     insertados, actualizados, sin cambios, omitidos y rechazados), los
     omitidos por motivo, los rechazados con sus motivos y los datos que
     quedaron. Leídos, omitidos y rechazados cuentan registros de la API;
     insertados, actualizados y sin cambios, feriados por país y día.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con otro número de error, se imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 feriados de prueba y OLE
     Automation como estaba antes del test.
*/

USE MundialFutbol;
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

IF OBJECT_ID(N'DatosGenerales.usp_ImportarFeriadosAPI', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_ImportarFeriados', N'P') IS NULL
   OR (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ARG', 'ENG', 'SCO')) < 3
BEGIN
    RAISERROR(N'Faltan los SP de importación de feriados o los datos iniciales: ejecutar los scripts 00 a 28.', 16, 1);
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

-- Borra con el SP de baja el feriado de un país (por código FIFA) y fecha, si existe.
IF OBJECT_ID(N'tempdb..#usp_BorrarFeriadoPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_BorrarFeriadoPrueba;
GO
CREATE PROCEDURE #usp_BorrarFeriadoPrueba
    @codigo_fifa  CHAR(3),
    @fecha        DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = (SELECT f.id_feriado
                       FROM DatosGenerales.FERIADO AS f
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
                       WHERE p.codigo_fifa = @codigo_fifa AND f.fecha = @fecha);
    IF @id IS NOT NULL
        EXEC DatosGenerales.usp_FERIADO_Baja @id_feriado = @id;
END;
GO

-- Borra el registro de las importaciones de los casos FX (su origen es el nombre del caso), con sus rechazados.
IF OBJECT_ID(N'tempdb..#usp_BorrarImportacionesPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_BorrarImportacionesPrueba;
GO
CREATE PROCEDURE #usp_BorrarImportacionesPrueba
AS
BEGIN
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'FX1';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'FX2';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'FX3';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'FX4';
END;
GO

-- Por si una corrida anterior del test quedó a medias: los 7 feriados que cargan los casos FX y sus importaciones.
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-05-25';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-06-20';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-07-09';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-12-25';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ENG', @fecha = '2001-01-01';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'SCO', @fecha = '2001-01-01';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'SCO', @fecha = '2001-01-02';
EXEC #usp_BorrarImportacionesPrueba;
GO


/* FX1 (OK) Importación de una respuesta con 7 registros.
   Esperado: 7 leídos, 5 feriados insertados y 3 omitidos:
     - Argentina 09/07 (Día de la Independencia) y 25/12 (sin localName: se
       guarda el nombre en inglés, Christmas Day);
     - el 01/01 del Reino Unido, que no es global pero rige en GB-ENG y
       GB-SCT: un feriado para Inglaterra y otro para Escocia;
     - el 02/01, que rige solo en GB-SCT: solo para Escocia;
     - omitidos: San Patricio (solo GB-NIR, regional), el Jueves Santo de
       Argentina (tipo Bank, no es feriado público) y uno de ZZ (país no
       registrado). */
DECLARE @json NVARCHAR(MAX) = N'[
    {"date":"2001-07-09","localName":"Día de la Independencia","name":"Independence Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-12-25","localName":null,"name":"Christmas Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-01-01","localName":"New Year''s Day","name":"New Year''s Day","countryCode":"GB","global":false,"counties":["GB-ENG","GB-NIR","GB-SCT","GB-WLS"],"types":["Public"]},
    {"date":"2001-01-02","localName":"2 January","name":"2 January","countryCode":"GB","global":false,"counties":["GB-SCT"],"types":["Public"]},
    {"date":"2001-03-17","localName":"Saint Patrick''s Day","name":"Saint Patrick''s Day","countryCode":"GB","global":false,"counties":["GB-NIR"],"types":["Public"]},
    {"date":"2001-04-12","localName":"Jueves Santo","name":"Maundy Thursday","countryCode":"AR","global":true,"counties":null,"types":["Bank"]},
    {"date":"2001-01-01","localName":"Año Nuevo","name":"New Year''s Day","countryCode":"ZZ","global":true,"counties":null,"types":["Public"]}]';

EXEC DatosGenerales.usp_ProcesarFeriadosJSON @json = @json, @origen = N'FX1';

SELECT 'FX1 feriados' AS caso, p.nombre AS pais, f.fecha, f.nombre
FROM DatosGenerales.FERIADO AS f
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
WHERE YEAR(f.fecha) = 2001
ORDER BY p.nombre, f.fecha;
GO


/* FX2 (OK) Reimportación de la misma respuesta.
   Esperado: 5 sin cambios y 3 omitidos; siguen las mismas 5 filas (no se
   duplica nada). */
DECLARE @json NVARCHAR(MAX) = N'[
    {"date":"2001-07-09","localName":"Día de la Independencia","name":"Independence Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-12-25","localName":null,"name":"Christmas Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-01-01","localName":"New Year''s Day","name":"New Year''s Day","countryCode":"GB","global":false,"counties":["GB-ENG","GB-NIR","GB-SCT","GB-WLS"],"types":["Public"]},
    {"date":"2001-01-02","localName":"2 January","name":"2 January","countryCode":"GB","global":false,"counties":["GB-SCT"],"types":["Public"]},
    {"date":"2001-03-17","localName":"Saint Patrick''s Day","name":"Saint Patrick''s Day","countryCode":"GB","global":false,"counties":["GB-NIR"],"types":["Public"]},
    {"date":"2001-04-12","localName":"Jueves Santo","name":"Maundy Thursday","countryCode":"AR","global":true,"counties":null,"types":["Bank"]},
    {"date":"2001-01-01","localName":"Año Nuevo","name":"New Year''s Day","countryCode":"ZZ","global":true,"counties":null,"types":["Public"]}]';

EXEC DatosGenerales.usp_ProcesarFeriadosJSON @json = @json, @origen = N'FX2';

SELECT 'FX2 después' AS caso, COUNT(*) AS feriados_2001
FROM DatosGenerales.FERIADO
WHERE YEAR(fecha) = 2001;
GO


/* FX3 (OK) La fuente renombra el 09/07 y trae dos feriados el 25/05.
   Esperado: 3 leídos: 1 actualizado (el 09/07 pasa a "Independencia" y
   renueva su fecha_actualizacion) y 1 insertado (el 25/05, con los dos
   nombres juntos en orden alfabético: "Otro feriado / Revolución de Mayo").
   Quedan 6 filas. */
DECLARE @json NVARCHAR(MAX) = N'[
    {"date":"2001-07-09","localName":"Independencia","name":"Independence Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-05-25","localName":"Revolución de Mayo","name":"May Revolution","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-05-25","localName":"Otro feriado","name":"Other holiday","countryCode":"AR","global":true,"counties":null,"types":["Public"]}]';

EXEC DatosGenerales.usp_ProcesarFeriadosJSON @json = @json, @origen = N'FX3';

SELECT 'FX3 feriados' AS caso, p.nombre AS pais, f.fecha, f.nombre, f.fecha_actualizacion
FROM DatosGenerales.FERIADO AS f
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
WHERE YEAR(f.fecha) = 2001 AND p.codigo_fifa = 'ARG'
ORDER BY f.fecha;
GO


/* FX4 (OK) Importación con errores parciales: 5 registros.
   Esperado: 5 leídos, 1 insertado (Argentina 20/06, Día de la Bandera) y 4
   rechazados, con estos motivos:
     AR 09/07/2001        la fecha no es una fecha (AAAA-MM-DD).
     AR (sin fecha)       la fecha es obligatoria.
     AR 2001-08-17        el nombre es obligatorio (no vienen localName ni name).
     AR 2001-10-12        el nombre supera los 200 caracteres.
   Los 4 rechazados quedan en DatosGenerales.ERRORES_FERIADO, con el número
   de la importación y el texto que traía la respuesta. */
DECLARE @json NVARCHAR(MAX) = CONCAT(N'[
    {"date":"2001-06-20","localName":"Día de la Bandera","name":"Flag Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"09/07/2001","localName":"Independencia","name":"Independence Day","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"localName":"Sin fecha","name":"No date","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-08-17","countryCode":"AR","global":true,"counties":null,"types":["Public"]},
    {"date":"2001-10-12","localName":"', REPLICATE(N'x', 201), N'","countryCode":"AR","global":true,"counties":null,"types":["Public"]}]');

DECLARE @id_importacion INT;

EXEC DatosGenerales.usp_ProcesarFeriadosJSON @json = @json, @origen = N'FX4', @id_importacion = @id_importacion OUTPUT;

SELECT 'FX4 registro' AS caso, i.leidos, i.insertados, i.rechazados, e.registro, e.codigo_iso2, e.fecha,
       LEFT(e.nombre_local, 20) AS nombre_local, e.nombre_ingles, REPLACE(e.motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM DatosGenerales.IMPORTACION AS i
INNER JOIN DatosGenerales.ERRORES_FERIADO AS e ON e.id_importacion = i.id_importacion
WHERE i.id_importacion = @id_importacion
ORDER BY e.registro;

SELECT 'FX4 importados' AS caso, p.nombre AS pais, f.fecha, f.nombre
FROM DatosGenerales.FERIADO AS f
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
WHERE f.fecha IN ('2001-06-20', '2001-08-17', '2001-10-12') AND p.codigo_fifa = 'ARG';
GO


/* FX5 (ERROR) Documentos que no se pueden importar:
     a) un texto que no es JSON (respuesta cortada);
     b) el mensaje de error de la API ante un país que no existe;
     c) un objeto en vez de un arreglo.
   Esperado: error 50002 en los tres, sin importar nada. */
BEGIN TRY
    EXEC DatosGenerales.usp_ProcesarFeriadosJSON @json = N'[{"date":"2001-07-09","localNa', @origen = N'FX5a';
    PRINT N'FX5a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FX5a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ProcesarFeriadosJSON
        @json = N'{"title":"Unknown country code","status":404,"detail":"The country code provided is invalid or not recognized."}',
        @origen = N'FX5b';
    PRINT N'FX5b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FX5b', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ProcesarFeriadosJSON
        @json = N'{"date":"2001-07-09","localName":"Independencia","countryCode":"AR","global":true,"types":["Public"]}',
        @origen = N'FX5c';
    PRINT N'FX5c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FX5c', @error_esperado = 50002;
END CATCH;
GO


/* AP1 (ERROR) Consulta a la API con parámetros inválidos.
     a) código ISO de 3 letras y año 1950;
     b) código ISO que no es de ningún país del sistema.
   Esperado: error 50001 con 2 condiciones y error 50001 con 1 condición, sin
   consultar la API. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarFeriadosAPI @codigo_iso2 = 'ARG', @anio = 1950;
    PRINT N'AP1a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP1a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarFeriadosAPI @codigo_iso2 = 'zz';
    PRINT N'AP1b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP1b', @error_esperado = 50001;
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


/* AP2 (OK, requiere internet) Feriados de 2001 del Reino Unido, consultando
   la API, dentro de una transacción que se deshace al final del caso.
   Esperado: 13 leídos y 2 omitidos (los regionales de Irlanda del Norte), y
   17 feriados entre Inglaterra y Escocia: 14 insertados y 3 sin cambios (el
   01/01 de las dos y el 02/01 de Escocia, que cargó FX1). Escocia tiene el
   02/01 y San Andrés (30/11), e Inglaterra el lunes de Pascua (16/04); el
   Summer Bank Holiday es el 06/08 en Escocia y el 27/08 en Inglaterra.
   Sin conexión: error 50002 (no se pudo enviar el pedido). */
BEGIN TRANSACTION;
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarFeriadosAPI @codigo_iso2 = 'GB', @anio = 2001;

    SELECT 'AP2 feriados' AS caso, p.nombre AS pais, f.fecha, f.nombre
    FROM DatosGenerales.FERIADO AS f
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
    WHERE YEAR(f.fecha) = 2001 AND p.codigo_iso2 = 'GB'
    ORDER BY f.fecha, p.nombre;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'AP2: no se pudo consultar la API (¿hay conexión a internet?). Error ', ERROR_NUMBER(), N':',
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* AP3 (ERROR, requiere internet) País del sistema que la API no cubre (Irán).
   Esperado: error 50002, la API no tiene feriados de Irán (responde sin
   contenido): hay que cargarlos a mano. Sin conexión también es 50002, pero
   porque no se pudo enviar el pedido. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarFeriadosAPI @codigo_iso2 = 'IR', @anio = 2026;
    PRINT N'AP3: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP3', @error_esperado = 50002;
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


-- Se borra lo que cargaron los casos FX, con el registro de sus importaciones.
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-05-25';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-06-20';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-07-09';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ARG', @fecha = '2001-12-25';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'ENG', @fecha = '2001-01-01';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'SCO', @fecha = '2001-01-01';
EXEC #usp_BorrarFeriadoPrueba @codigo_fifa = 'SCO', @fecha = '2001-01-02';
EXEC #usp_BorrarImportacionesPrueba;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 feriados (de 2001) e importaciones de prueba, y OLE Automation
   y las opciones avanzadas con el mismo valor que antes del test.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.FERIADO WHERE YEAR(fecha) = 2001) AS feriados_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION WHERE origen IN (N'FX1', N'FX2', N'FX3', N'FX4')) AS importaciones_de_prueba;

SELECT 'Final' AS caso, c.name AS opcion, c.value_in_use AS valor_actual,
       CAST(SESSION_CONTEXT(IIF(c.name = N'show advanced options', N'avanzadas_antes', N'ole_antes')) AS INT) AS valor_antes
FROM sys.configurations AS c
WHERE c.name IN (N'Ole Automation Procedures', N'show advanced options');
GO

SET NOEXEC OFF;
GO
