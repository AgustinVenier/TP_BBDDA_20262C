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
           25_SP_Importar_Indicadores.sql, con el registro de cada
           importación y de sus rechazados
           (DatosGenerales.ERRORES_INDICADOR_ECONOMICO):
             - procesando respuestas con el formato de la API del Banco
               Mundial escritas en el test: alta, reimportación sin
               duplicados, actualización, importación con errores parciales y
               los documentos que no se pueden importar;
             - consultando la API del Banco Mundial (casos AP, necesitan
               internet).
           Las reglas de los indicadores las prueba 66_Test_SP_Importacion.sql,
           con DatosGenerales.usp_ImportarIndicadoresEconomicos.
           Requiere haber ejecutado 00 a 25. No depende del juego de datos:
           las respuestas escritas usan su propio indicador (TP.PRUEBA.PBI) y
           el caso de la API importa solo la población de Argentina en 2024
           (SP.POP.TOTL). Al final se borra lo que cargó el test, con el
           registro de sus importaciones, así que se puede ejecutar más de una
           vez.
================================================================================

 Transacciones: la importación puede correr dentro de una transacción del
 que la llama, que IX7 deshace con ROLLBACK (con el registro de la
 importación). Los demás casos no se deshacen: el test borra al final, con
 los SP de baja, los indicadores que cargó y el registro de sus
 importaciones.

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

-- Configuración de OLE Automation antes del test (para los lotes siguientes).
DECLARE @ole_antes INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                          WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                WHERE name = N'show advanced options');

EXEC sp_set_session_context @key = N'ole_antes', @value = @ole_antes;
EXEC sp_set_session_context @key = N'avanzadas_antes', @value = @avanzadas_antes;

IF OBJECT_ID(N'DatosGenerales.usp_ImportarIndicadoresAPI', N'P') IS NULL
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

-- Borra el registro de las importaciones de los casos IX (su origen es el nombre del caso), con sus rechazados.
IF OBJECT_ID(N'tempdb..#usp_BorrarImportacionesPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_BorrarImportacionesPrueba;
GO
CREATE PROCEDURE #usp_BorrarImportacionesPrueba
AS
BEGIN
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'IX1';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'IX2';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'IX3';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'IX4';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = N'IX5';
END;
GO

-- Por si una corrida anterior del test quedó a medias: los 7 valores que cargan los casos IX y sus importaciones.
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2023;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Inglaterra', @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Escocia',    @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Brasil',     @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Uruguay',    @anio = 2022;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Ecuador',    @anio = 2023;
EXEC #usp_BorrarImportacionesPrueba;
GO


/* IX1 (OK) Importación de una respuesta con 6 registros.
   Esperado: 6 leídos, 3 insertados y 3 omitidos (World y High income, que no
   son países del sistema, y Brasil 2024, que viene sin valor). Quedan 4
   filas de TP.PRUEBA.PBI: Argentina 2023 (1000.5000) y 2024 (1100.2500), e
   Inglaterra y Escocia 2024 (2000.0000), las dos por el código GBR. */
DECLARE @xml XML = N'
<wb:data page="1" pages="1" per_page="50" total="6" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1100.25</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2023</wb:date><wb:value>1000.5</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="GB">United Kingdom</wb:country>
           <wb:countryiso3code>GBR</wb:countryiso3code><wb:date>2024</wb:date><wb:value>2000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="1W">World</wb:country>
           <wb:countryiso3code>WLD</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1500</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="XD">High income</wb:country>
           <wb:countryiso3code /><wb:date>2024</wb:date><wb:value>3000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="BR">Brazil</wb:country>
           <wb:countryiso3code>BRA</wb:countryiso3code><wb:date>2024</wb:date><wb:value /></wb:data>
</wb:data>';

EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX1';

SELECT 'IX1 indicadores' AS caso, p.nombre AS pais, ie.anio, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI'
ORDER BY p.nombre, ie.anio;
GO


/* IX2 (OK) Reimportación de la misma respuesta.
   Esperado: 3 SIN CAMBIOS y 3 omitidos; siguen las mismas 4 filas (no se
   duplica nada). */
DECLARE @xml XML = N'
<wb:data page="1" pages="1" per_page="50" total="6" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1100.25</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2023</wb:date><wb:value>1000.5</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="GB">United Kingdom</wb:country>
           <wb:countryiso3code>GBR</wb:countryiso3code><wb:date>2024</wb:date><wb:value>2000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="1W">World</wb:country>
           <wb:countryiso3code>WLD</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1500</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="XD">High income</wb:country>
           <wb:countryiso3code /><wb:date>2024</wb:date><wb:value>3000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="BR">Brazil</wb:country>
           <wb:countryiso3code>BRA</wb:countryiso3code><wb:date>2024</wb:date><wb:value /></wb:data>
</wb:data>';

EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX2';

SELECT 'IX2 después' AS caso, COUNT(*) AS filas
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE codigo_indicador = 'TP.PRUEBA.PBI';
GO


/* IX3 (OK) El Banco Mundial revisó Argentina 2024, Argentina 2023 viene sin
   valor y se agrega Brasil 2024.
   Esperado: 4 leídos: 1 insertado (Brasil 2024, 900.0000), 1 actualizado
   (Argentina 2024 pasa de 1100.2500 a 1150.7500 y renueva su
   fecha_actualizacion), 1 sin cambios (GBR 2024) y 1 omitido (Argentina 2023
   sin valor, que conserva su 1000.5000: un dato que no viene no borra el
   guardado). Quedan 5 filas. */
DECLARE @xml XML = N'
<wb:data page="1" pages="1" per_page="50" total="4" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1150.75</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2023</wb:date><wb:value /></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="GB">United Kingdom</wb:country>
           <wb:countryiso3code>GBR</wb:countryiso3code><wb:date>2024</wb:date><wb:value>2000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="BR">Brazil</wb:country>
           <wb:countryiso3code>BRA</wb:countryiso3code><wb:date>2024</wb:date><wb:value>900</wb:value></wb:data>
</wb:data>';

EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX3';

SELECT 'IX3 indicadores' AS caso, p.nombre AS pais, ie.anio, ie.valor, ie.fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI'
ORDER BY p.nombre, ie.anio;
GO


/* IX4 (OK) Importación con errores parciales: una respuesta con 12
   registros.
   Esperado: 12 leídos, 2 insertados (Uruguay 2022 y Ecuador 2023), 1 omitido
   (la copia de Ecuador 2023 con el mismo valor) y 9 rechazados, con estos
   motivos:
     BOL (sin año)    el año es obligatorio.
     CHL 2023         el código del indicador es obligatorio.
     CHL 2024         el código "TP PRUEBA PBI" tiene espacios.
     COL 2023 (x2)    la respuesta trae 2 veces Colombia 2023 con valores
                      distintos: se rechazan las dos.
     PER 2023         el valor no es un número válido (15 dígitos enteros).
     PRY 1950         el año debe estar entre 1960 y el actual.
     URY 2023         el valor "dos mil" no es un número.
     URY 2023Q1       el año no es un año (AAAA).
   Quedan importados Uruguay 2022 (1234.5000) y Ecuador 2023 (300.0000), y
   nada de Colombia, Paraguay, Perú, Bolivia ni Chile. Los 9 rechazados
   quedan en DatosGenerales.ERRORES_INDICADOR_ECONOMICO, con el número de la
   importación y el texto que traía la respuesta. */
DECLARE @xml XML = N'
<wb:data page="1" pages="1" per_page="50" total="12" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="UY">Uruguay</wb:country>
           <wb:countryiso3code>URY</wb:countryiso3code><wb:date>2022</wb:date><wb:value>1234.5</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="UY">Uruguay</wb:country>
           <wb:countryiso3code>URY</wb:countryiso3code><wb:date>2023</wb:date><wb:value>dos mil</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="UY">Uruguay</wb:country>
           <wb:countryiso3code>URY</wb:countryiso3code><wb:date>2023Q1</wb:date><wb:value>10</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="PY">Paraguay</wb:country>
           <wb:countryiso3code>PRY</wb:countryiso3code><wb:date>1950</wb:date><wb:value>10</wb:value></wb:data>
  <wb:data><wb:indicator id="TP PRUEBA PBI">PBI de prueba</wb:indicator><wb:country id="CL">Chile</wb:country>
           <wb:countryiso3code>CHL</wb:countryiso3code><wb:date>2024</wb:date><wb:value>10</wb:value></wb:data>
  <wb:data><wb:indicator>PBI de prueba</wb:indicator><wb:country id="CL">Chile</wb:country>
           <wb:countryiso3code>CHL</wb:countryiso3code><wb:date>2023</wb:date><wb:value>10</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="CO">Colombia</wb:country>
           <wb:countryiso3code>COL</wb:countryiso3code><wb:date>2023</wb:date><wb:value>100</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="CO">Colombia</wb:country>
           <wb:countryiso3code>COL</wb:countryiso3code><wb:date>2023</wb:date><wb:value>200</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="EC">Ecuador</wb:country>
           <wb:countryiso3code>ECU</wb:countryiso3code><wb:date>2023</wb:date><wb:value>300</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="EC">Ecuador</wb:country>
           <wb:countryiso3code>ECU</wb:countryiso3code><wb:date>2023</wb:date><wb:value>300</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="PE">Peru</wb:country>
           <wb:countryiso3code>PER</wb:countryiso3code><wb:date>2023</wb:date><wb:value>123456789012345</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="BO">Bolivia</wb:country>
           <wb:countryiso3code>BOL</wb:countryiso3code><wb:value>10</wb:value></wb:data>
</wb:data>';
DECLARE @id_importacion INT;

EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX4', @id_importacion = @id_importacion OUTPUT;

SELECT 'IX4 registro' AS caso, i.leidos, i.insertados, i.omitidos, i.rechazados, e.registro, e.codigo_iso3, e.anio,
       e.codigo_indicador, e.valor, REPLACE(e.motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM DatosGenerales.IMPORTACION AS i
INNER JOIN DatosGenerales.ERRORES_INDICADOR_ECONOMICO AS e ON e.id_importacion = i.id_importacion
WHERE i.id_importacion = @id_importacion
ORDER BY e.registro;

SELECT 'IX4 importados' AS caso, p.nombre AS pais, ie.anio, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI' AND p.codigo_iso3 IN ('URY', 'PRY', 'COL', 'ECU', 'PER', 'BOL', 'CHL')
ORDER BY p.nombre, ie.anio;
GO


/* IX5 (OK) La respuesta de la API para un año que todavía no tiene datos
   publicados.
   Esperado: 0 leídos. No es un error. */
DECLARE @xml XML = N'<wb:data page="0" pages="0" per_page="0" total="0" xmlns:wb="http://www.worldbank.org" />';

EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX5';
GO


/* IX6 (ERROR) Documentos que no se pueden importar:
     a) un XML que no es de la API del Banco Mundial;
     b) el mensaje de error que devuelve la API cuando el indicador o el país
        no existen;
     c) la primera página de un resultado de dos (pedido sin per_page).
   Esperado: tres errores 50002, cada uno con su motivo, sin nada
   importado. */
DECLARE @xml XML;

BEGIN TRY
    SET @xml = N'<paises><pais codigo="ARG" pbi="13969.78">Argentina</pais></paises>';
    EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX6a';
    PRINT N'IX6a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX6a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @xml = N'<wb:error xmlns:wb="http://www.worldbank.org"><wb:message id="120" key="Invalid value">The provided parameter value is not valid</wb:message></wb:error>';
    EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX6b';
    PRINT N'IX6b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX6b', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @xml = N'
<wb:data page="1" pages="2" per_page="50" total="60" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1100.25</wb:value></wb:data>
</wb:data>';
    EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX6c';
    PRINT N'IX6c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IX6c', @error_esperado = 50002;
END CATCH;
GO


/* IX7 (OK) Importación dentro de una transacción que se deshace: se vuelve a
   importar la respuesta de IX1, que tiene Argentina 2024 en 1100.2500 (IX3
   la dejó en 1150.7500).
   Esperado: 6 leídos, 1 actualizado (Argentina 2024), 2 sin cambios
   (Argentina 2023 y GBR 2024) y 3 omitidos. Dentro de la transacción
   Argentina 2024 vale 1100.2500; después del ROLLBACK vuelve a 1150.7500. */
DECLARE @xml XML = N'
<wb:data page="1" pages="1" per_page="50" total="6" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1100.25</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="AR">Argentina</wb:country>
           <wb:countryiso3code>ARG</wb:countryiso3code><wb:date>2023</wb:date><wb:value>1000.5</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="GB">United Kingdom</wb:country>
           <wb:countryiso3code>GBR</wb:countryiso3code><wb:date>2024</wb:date><wb:value>2000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="1W">World</wb:country>
           <wb:countryiso3code>WLD</wb:countryiso3code><wb:date>2024</wb:date><wb:value>1500</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="XD">High income</wb:country>
           <wb:countryiso3code /><wb:date>2024</wb:date><wb:value>3000</wb:value></wb:data>
  <wb:data><wb:indicator id="TP.PRUEBA.PBI">PBI de prueba</wb:indicator><wb:country id="BR">Brazil</wb:country>
           <wb:countryiso3code>BRA</wb:countryiso3code><wb:date>2024</wb:date><wb:value /></wb:data>
</wb:data>';

BEGIN TRANSACTION;

EXEC DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = N'IX7';

SELECT 'IX7 dentro de la transacción' AS caso, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI' AND p.nombre = 'Argentina' AND ie.anio = 2024;

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

SELECT 'IX7 después del ROLLBACK' AS caso, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.codigo_indicador = 'TP.PRUEBA.PBI' AND p.nombre = 'Argentina' AND ie.anio = 2024;
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
   Si no estaba antes del test, se borra al final del caso, con el registro
   de la importación.
   Sin conexión: error 50002 (no se pudo enviar el pedido). */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_iso3 = 'ARG');
DECLARE @existia BIT = IIF(EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO
                                   WHERE id_pais = @id_pais AND codigo_indicador = 'SP.POP.TOTL'
                                     AND anio = 2024), 1, 0);
DECLARE @id INT;
DECLARE @id_importacion INT;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI
        @codigo_indicador = 'SP.POP.TOTL', @anio_desde = 2024, @anio_hasta = 2024, @paises = 'ARG',
        @id_importacion = @id_importacion OUTPUT;

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
IF @id_importacion IS NOT NULL
    EXEC DatosGenerales.usp_BorrarImportacion @id_importacion = @id_importacion;
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


-- Se borra lo que cargaron los casos IX, con el registro de sus importaciones.
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2023;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Argentina',  @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Inglaterra', @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Escocia',    @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Brasil',     @anio = 2024;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Uruguay',    @anio = 2022;
EXEC #usp_BorrarIndicadorPrueba @pais = 'Ecuador',    @anio = 2023;
EXEC #usp_BorrarImportacionesPrueba;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 indicadores e importaciones de prueba, y OLE Automation y las
   opciones avanzadas con el mismo valor que antes del test.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.INDICADOR_ECONOMICO WHERE codigo_indicador = 'TP.PRUEBA.PBI') AS indicadores_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION
        WHERE origen LIKE N'IX[0-9]%'
           OR origen LIKE N'%/country/ARG/indicator/SP.POP.TOTL?date=2024:2024%') AS importaciones_de_prueba;

SELECT 'Final' AS caso, c.name AS opcion, c.value_in_use AS valor_actual,
       CAST(SESSION_CONTEXT(IIF(c.name = N'show advanced options', N'avanzadas_antes', N'ole_antes')) AS INT) AS valor_antes
FROM sys.configurations AS c
WHERE c.name IN (N'Ole Automation Procedures', N'show advanced options');
GO

SET NOEXEC OFF;
GO
