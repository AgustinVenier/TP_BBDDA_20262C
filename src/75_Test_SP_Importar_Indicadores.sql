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

 Fecha: 29/10/2026
 Archivo: 75_Test_SP_Importar_Indicadores.sql
 Objetivo: Probar la importación masiva de indicadores económicos de
           25_SP_Importar_Indicadores.sql, y la carga en bloque
           DatosGenerales.usp_ImportarIndicadoresEconomicos de
           16_SP_Importacion.sql que usa:
             - desde los archivos XML chicos de datos/pruebas/ (con el formato
               de la API del Banco Mundial): alta, reimportación sin
               duplicados, actualización, importación con errores parciales y
               los archivos que no se pueden importar;
             - consultando la API del Banco Mundial (casos AP, necesitan
               internet).
           Requiere haber ejecutado 00 a 25. No depende del juego de datos:
           los archivos usan su propio indicador (TP.PRUEBA.PBI) y el caso de
           la API importa solo la población de Argentina en 2024
           (SP.POP.TOTL). Al final se borra lo que cargó el test, así que se
           puede ejecutar más de una vez.
================================================================================

 Antes de ejecutar: CAMBIAR @carpeta, en el primer lote, por la ruta de la
 carpeta datos\pruebas\ del repositorio en tu máquina. Es distinta para cada
 uno: depende de dónde se clonó el repositorio. Además, la cuenta del servicio
 de SQL Server tiene que poder leerla. El error "does not exist or you don't
 have file access rights" aparece tanto si la ruta está mal como si falta el
 permiso. Cómo darlo: ver "Antes de ejecutar" en 26_ImportarIndicadores.sql.

 Transacciones: la importación es un solo upsert y puede correr dentro de
 una transacción, que IX9 deshace con ROLLBACK. Los demás casos no se
 deshacen: el test borra al final, con el SP de baja, los indicadores que
 cargó.

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
   - Al final, la verificación tiene que mostrar 0 datos de prueba y OLE
     Automation como estaba antes del test.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Carpeta de los archivos de prueba y configuración de OLE Automation antes del test (para los lotes siguientes).
-- CAMBIAR: ruta de la carpeta datos\pruebas\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @carpeta NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\datos\pruebas\';
DECLARE @ole_antes INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                          WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                WHERE name = N'show advanced options');

EXEC sp_set_session_context @key = N'carpeta_pruebas', @value = @carpeta;
EXEC sp_set_session_context @key = N'ole_antes', @value = @ole_antes;
EXEC sp_set_session_context @key = N'avanzadas_antes', @value = @avanzadas_antes;

IF OBJECT_ID(N'DatosGenerales.usp_ImportarIndicadoresXML', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_ImportarIndicadoresEconomicos', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_ConsumirAPI', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_iso3 = 'GBR')
BEGIN
    RAISERROR(N'Faltan los SP de importación o los datos iniciales: ejecutar los scripts 00 a 25.', 16, 1);
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

-- Borra con el SP de baja el valor de TP.PRUEBA.PBI de un país y año, si existe.
IF OBJECT_ID(N'tempdb..#usp_BorrarIndicadorPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_BorrarIndicadorPrueba;
GO
CREATE PROCEDURE #usp_BorrarIndicadorPrueba
    @pais  VARCHAR(60),
    @anio  SMALLINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = (SELECT ie.id_indicador
                       FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
                       WHERE p.nombre = @pais COLLATE DATABASE_DEFAULT
                         AND ie.codigo_indicador = 'TP.PRUEBA.PBI' AND ie.anio = @anio);
    IF @id IS NOT NULL
        EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
END;
GO

-- Por si una corrida anterior del test quedó a medias: los 7 valores que cargan los casos IX.
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2023;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Inglaterra', @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Escocia',    @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Brasil',     @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Uruguay',    @anio = 2022;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Ecuador',    @anio = 2023;
GO


/* IX1 (OK) Importación de indicadores_prueba_ok.xml: 6 registros.
   Esperado: 6 leídos, 3 insertados y 3 omitidos (World y High income, que no
   son países del sistema, y Brasil 2024, que viene sin valor). Quedan 4
   filas de TP.PRUEBA.PBI: Argentina 2023 (1000.5000) y 2024 (1100.2500), e
   Inglaterra y Escocia 2024 (2000.0000), las dos por el código GBR. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'indicadores_prueba_ok.xml';

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;

SELECT 'IX1 indicadores' AS caso, p.nombre AS pais, ie.anio, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI'
ORDER BY p.nombre, ie.anio;
GO


/* IX2 (OK) Reimportación del mismo archivo.
   Esperado: 3 SIN CAMBIOS y 3 omitidos; siguen las mismas 4 filas (no se
   duplica nada). */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'indicadores_prueba_ok.xml';

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;

SELECT 'IX2 después' AS caso, COUNT(*) AS filas
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE codigo_indicador = 'TP.PRUEBA.PBI';
GO


/* IX3 (OK) Importación de indicadores_prueba_cambios.xml: el Banco Mundial
   revisó Argentina 2024, Argentina 2023 viene sin valor y se agrega Brasil
   2024.
   Esperado: 4 leídos: 1 insertado (Brasil 2024, 900.0000), 1 actualizado
   (Argentina 2024 pasa de 1100.2500 a 1150.7500 y renueva su
   fecha_actualizacion), 1 sin cambios (GBR 2024) y 1 omitido (Argentina 2023
   sin valor, que conserva su 1000.5000: un dato que no viene no borra el
   guardado). Quedan 5 filas. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'indicadores_prueba_cambios.xml';

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;

SELECT 'IX3 indicadores' AS caso, p.nombre AS pais, ie.anio, ie.valor, ie.fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI'
ORDER BY p.nombre, ie.anio;
GO


/* IX4 (OK) Importación con errores parciales: indicadores_prueba_errores.xml
   trae 12 registros.
   Esperado: 12 leídos, 2 insertados (Uruguay 2022 y Ecuador 2023), 1 omitido
   (la copia de Ecuador 2023 con el mismo valor) y 9 rechazados, con estos
   motivos:
     BOL (sin año)    el año es obligatorio.
     CHL 2023         el código del indicador es obligatorio.
     CHL 2024         el código "TP PRUEBA PBI" tiene espacios.
     COL 2023 (x2)    el archivo trae 2 veces Colombia 2023 con valores
                      distintos: se rechazan las dos.
     PER 2023         el valor no es un número válido (15 dígitos enteros).
     PRY 1950         el año debe estar entre 1960 y el actual.
     URY 2023         el valor "dos mil" no es un número.
     URY 2023Q1       el año no es un año (AAAA).
   Quedan importados Uruguay 2022 (1234.5000) y Ecuador 2023 (300.0000), y
   nada de Colombia, Paraguay, Perú, Bolivia ni Chile. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'indicadores_prueba_errores.xml';

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;

SELECT 'IX4 importados' AS caso, p.nombre AS pais, ie.anio, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI' AND p.codigo_iso3 IN ('URY', 'PRY', 'COL', 'ECU', 'PER', 'BOL', 'CHL')
ORDER BY p.nombre, ie.anio;
GO


/* IX5 (OK) Importación de indicadores_prueba_vacio.xml: la respuesta de la
   API para un año que todavía no tiene datos publicados.
   Esperado: 0 leídos. No es un error. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'indicadores_prueba_vacio.xml';

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
GO


/* IX6 (ERROR) Archivo que no existe.
   Esperado: error 50002, no se importó nada porque no se pudo leer el
   archivo. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'no_existe.xml';

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
    PRINT N'IX6: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX6', @error_esperado = 50002;
END CATCH;
GO


/* IX7 (ERROR) Archivos que no se pueden importar:
     a) indicadores_prueba_invalido.xml, una descarga cortada (no es un XML
        válido);
     b) indicadores_prueba_otro_formato.xml, un XML que no es de la API del
        Banco Mundial;
     c) indicadores_prueba_error_api.xml, el mensaje de error que devuelve la
        API cuando el indicador o el país no existen;
     d) indicadores_prueba_paginado.xml, la primera página de un resultado de
        dos (descargado sin per_page).
   Esperado: cuatro errores 50002, cada uno con su motivo, sin nada
   importado. */
DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
DECLARE @archivo NVARCHAR(400);

BEGIN TRY
    SET @archivo = @carpeta + N'indicadores_prueba_invalido.xml';
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
    PRINT N'IX7a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX7a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'indicadores_prueba_otro_formato.xml';
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
    PRINT N'IX7b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX7b', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'indicadores_prueba_error_api.xml';
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
    PRINT N'IX7c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX7c', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'indicadores_prueba_paginado.xml';
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
    PRINT N'IX7d: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX7d', @error_esperado = 50002;
END CATCH;
GO


/* IX8 (ERROR) Ruta vacía y archivo que no es .xml.
   Esperado: dos errores 50001 de validación. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = N'  ';
    PRINT N'IX8a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX8a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = N'C:\datos\pbi.json';
    PRINT N'IX8b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX8b', @error_esperado = 50001;
END CATCH;
GO


/* IX9 (OK) Importación dentro de una transacción que se deshace: se vuelve a
   importar indicadores_prueba_ok.xml, que tiene Argentina 2024 en 1100.2500
   (IX3 la dejó en 1150.7500).
   Esperado: 6 leídos, 1 actualizado (Argentina 2024), 2 sin cambios
   (Argentina 2023 y GBR 2024) y 3 omitidos. Dentro de la transacción
   Argentina 2024 vale 1100.2500; después del ROLLBACK vuelve a 1150.7500. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'indicadores_prueba_ok.xml';

BEGIN TRANSACTION;

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;

SELECT 'IX9 dentro de la transacción' AS caso, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI' AND p.nombre = 'Argentina' AND ie.anio = 2024;

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

SELECT 'IX9 después del ROLLBACK' AS caso, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI' AND p.nombre = 'Argentina' AND ie.anio = 2024;
GO


/* IX10 (ERROR) Carga en bloque con usp_ImportarIndicadoresEconomicos de un
   conjunto con errores (el SP de la Entrega 5, sin el procesamiento de 25
   que los filtra).
   Esperado: error 50001 con 5 condiciones en un solo mensaje: 1 fila sin
   valor, el código ISO XYZ no es de ningún país, el código "TP PRUEBA" tiene
   espacios, el año 1950 está fuera de rango y Argentina 2020 viene
   repetida. No se carga ninguno, ni siquiera los válidos. */
DECLARE @indicadores DatosGenerales.TT_INDICADOR_ECONOMICO;

INSERT INTO @indicadores (codigo_iso3, codigo_indicador, anio, valor)
VALUES ('ARG', 'TP.PRUEBA.PBI', 2020, 10), ('ARG', 'TP.PRUEBA.PBI', 2020, 11), ('URY', 'TP.PRUEBA.PBI', 2020, NULL),
       ('XYZ', 'TP.PRUEBA.PBI', 2020, 12), ('URY', 'TP PRUEBA', 2020, 13), ('BRA', 'TP.PRUEBA.PBI', 1950, 14),
       ('CHL', 'TP.PRUEBA.PBI', 2020, 15);

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresEconomicos @indicadores = @indicadores;
    PRINT N'IX10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX10', @error_esperado = 50001;
END CATCH;

SELECT 'IX10 después' AS caso, COUNT(*) AS indicadores_de_2020_y_1950
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE codigo_indicador IN ('TP.PRUEBA.PBI', 'TP PRUEBA') AND anio IN (2020, 1950);
GO


/* AP1 (ERROR) Consulta a la API con parámetros inválidos.
     a) código con espacios (no puede ir en la URL), países separados por
        coma y año 1950;
     b) año desde mayor que año hasta.
   Esperado: error 50001 con 3 condiciones y error 50001 con 1 condición, sin
   consultar la API. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI @codigo_indicador = 'NY GDP', @paises = 'ARG,BRA', @anio_desde = 1950;
    PRINT N'AP1a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP1a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI @anio_desde = 2024, @anio_hasta = 2020;
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


/* AP2 (OK, requiere internet) Población de Argentina en 2024 (SP.POP.TOTL),
   consultando la API solo por ese país.
   Esperado: 1 leído y 1 insertado (o sin cambios, si ya estaba cargado), y
   la fila con la población que publica el Banco Mundial (unos 45 millones).
   Si no estaba antes del test, se borra al final del caso.
   Sin conexión: error 50002 (no se pudo enviar el pedido). */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_iso3 = 'ARG');
DECLARE @existia BIT = IIF(EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO
                                   WHERE id_pais = @id_pais AND codigo_indicador = 'SP.POP.TOTL'
                                     AND anio = 2024), 1, 0);
DECLARE @id INT;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI
        @codigo_indicador = 'SP.POP.TOTL', @anio_desde = 2024, @anio_hasta = 2024, @paises = 'ARG';

    SELECT 'AP2 población' AS caso, p.nombre AS pais, ie.codigo_indicador, ie.anio, ie.valor
    FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
    WHERE ie.id_pais = @id_pais AND ie.codigo_indicador = 'SP.POP.TOTL' AND ie.anio = 2024;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'AP2: no se pudo consultar la API (¿hay conexión a internet?). Error ', ERROR_NUMBER(), N':',
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END CATCH;

SET @id = (SELECT id_indicador FROM DatosGenerales.INDICADOR_ECONOMICO
           WHERE id_pais = @id_pais AND codigo_indicador = 'SP.POP.TOTL' AND anio = 2024);
IF @existia = 0 AND @id IS NOT NULL
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
GO


/* AP3 (ERROR, requiere internet) Indicador con formato válido que no existe
   en el Banco Mundial.
   Esperado: error 50002, la API del Banco Mundial devolvió un error ("The
   provided parameter value is not valid"). Sin conexión también es 50002,
   pero porque no se pudo enviar el pedido. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI @codigo_indicador = 'TP.NO.EXISTE', @anio_desde = 2024;
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


-- Se borra lo que cargaron los casos IX.
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2023;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Inglaterra', @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Escocia',    @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Brasil',     @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Uruguay',    @anio = 2022;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Ecuador',    @anio = 2023;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 indicadores de prueba, y OLE Automation y las opciones
   avanzadas con el mismo valor que antes del test.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.INDICADOR_ECONOMICO WHERE codigo_indicador = 'TP.PRUEBA.PBI') AS indicadores_de_prueba;

SELECT 'Final' AS caso, c.name AS opcion, c.value_in_use AS valor_actual,
       CAST(SESSION_CONTEXT(IIF(c.name = N'show advanced options', N'avanzadas_antes', N'ole_antes')) AS INT) AS valor_antes
FROM sys.configurations AS c
WHERE c.name IN (N'Ole Automation Procedures', N'show advanced options');
GO

SET NOEXEC OFF;
GO
