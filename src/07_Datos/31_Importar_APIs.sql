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
 Archivo: 31_Importar_APIs.sql
 Objetivo: Importar desde las APIs, con los SP de 20 a 23:
             1. el PBI per cápita (NY.GDP.PCAP.CD) de los últimos 10 años de
                todos los países del sistema, desde la API del Banco Mundial;
             2. las campañas publicitarias del Mundial 2026 del Dossier
                Mundial, con sus anunciantes y piezas, desde la API de
                Firestore que usa la página;
             3. las cotizaciones contra el dólar de las monedas de todos los
                países del sistema en junio y julio de 2026 (el torneo y las
                campañas publicitarias), desde la API Frankfurter;
             4. los feriados de 2026 de todos los países del sistema, desde
                la API Nager.Date, de a un país por consulta.
           Requiere haber ejecutado 01 a 28. Va antes de los datos
           complementarios (33), que usan el PBI y las piezas del Dossier
           para asignar la publicidad de cada partido, y que cargan los
           feriados de los países que Nager.Date no cubre. Se puede ejecutar
           más de una vez: lo que ya está cargado queda SIN CAMBIOS, y si una
           fuente corrigió un valor, se actualiza.
================================================================================

 Antes de ejecutar:
   - Necesita internet y OLE Automation, que la instancia trae deshabilitado.
     Este script lo habilita solo mientras consulta las APIs y después lo deja
     como estaba. Hace falta ser sysadmin. Si no hay conexión, cada
     importación falla con su motivo y no se importa nada.

 Por qué hay un WHILE: Nager.Date responde los feriados de un país por
 consulta y cada consulta es una llamada a usp_ConsumirAPI. El WHILE recorre
 los países (uno por código ISO: Inglaterra y Escocia comparten GB); el SP
 procesa cada respuesta entera, de una vez.
 Nager.Date no tiene feriados de algunos países (responde sin contenido): esos
 quedan en la grilla de lo que no se pudo importar y no cortan el script.

 Resultado: el resumen de cada importación (leídos, insertados, actualizados,
 sin cambios, omitidos y rechazados), con sus omitidos y rechazados; el de
 los feriados, sumando todos los países; lo que no se pudo importar; y las
 evidencias del final.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

DECLARE @ole_antes        INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes  INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'show advanced options');
-- Las importaciones de esta ejecución son las que se registren desde acá (para el resumen de feriados).
DECLARE @importacion_desde INT = ISNULL((SELECT MAX(id_importacion) FROM DatosGenerales.IMPORTACION), 0);
-- Feriados: un país por vuelta del WHILE.
DECLARE @anio             SMALLINT = 2026;
DECLARE @orden_pais       INT = 1;
DECLARE @total            INT;
DECLARE @codigo_iso2      CHAR(2);

DECLARE @paises TABLE (orden INT IDENTITY(1,1) PRIMARY KEY, codigo_iso2 CHAR(2));
-- Lo que falló: una importación entera (1 a 3) o los feriados de un país (4).
DECLARE @errores TABLE (importacion NVARCHAR(40), codigo_iso2 CHAR(2) NULL, error NVARCHAR(2048));

IF @ole_antes = 0
BEGIN
    IF @avanzadas_antes = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 1;
        RECONFIGURE;
    END;
    EXEC sp_configure 'Ole Automation Procedures', 1;
    RECONFIGURE;
END;

-- 1. PBI per cápita de los últimos 10 años.
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI @codigo_indicador = 'NY.GDP.PCAP.CD';
END TRY
BEGIN CATCH
    INSERT INTO @errores (importacion, error) VALUES (N'PBI per cápita', ERROR_MESSAGE());
END CATCH;

-- 2. Campañas del Dossier Mundial, con el período del torneo.
BEGIN TRY
    EXEC Publicidad.usp_ImportarCampaniasAPI @fecha_inicio = '2026-06-11', @fecha_fin = '2026-07-19';
END TRY
BEGIN CATCH
    INSERT INTO @errores (importacion, error) VALUES (N'Campañas', ERROR_MESSAGE());
END CATCH;

-- 3. Cotizaciones de junio y julio de 2026.
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI @fecha_desde = '2026-06-01', @fecha_hasta = '2026-07-31';
END TRY
BEGIN CATCH
    INSERT INTO @errores (importacion, error) VALUES (N'Cotizaciones', ERROR_MESSAGE());
END CATCH;

-- 4. Feriados de cada país, de a una consulta por código ISO.
INSERT INTO @paises (codigo_iso2)
SELECT DISTINCT codigo_iso2
FROM DatosGenerales.PAIS
WHERE codigo_iso2 IS NOT NULL
ORDER BY codigo_iso2;

SET @total = (SELECT COUNT(*) FROM @paises);

WHILE @orden_pais <= @total
BEGIN
    SELECT @codigo_iso2 = codigo_iso2 FROM @paises WHERE orden = @orden_pais;

    BEGIN TRY
        EXEC DatosGenerales.usp_ImportarFeriadosAPI @codigo_iso2 = @codigo_iso2, @anio = @anio, @mostrar_resultados = 0;
    END TRY
    BEGIN CATCH
        INSERT INTO @errores (importacion, codigo_iso2, error) VALUES (N'Feriados', @codigo_iso2, ERROR_MESSAGE());
    END CATCH;

    SET @orden_pais += 1;
END;

IF @ole_antes = 0
BEGIN
    EXEC sp_configure 'Ole Automation Procedures', 0;
    RECONFIGURE;
    IF @avanzadas_antes = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 0;
        RECONFIGURE;
    END;
END;

-- Resumen de los feriados: las importaciones que registró esta ejecución, una por país.
SELECT CONCAT(N'https://date.nager.at/api/v3/PublicHolidays/', @anio, N'/{país}') AS origen,
       COUNT(*)                      AS paises_importados,
       ISNULL(SUM(leidos), 0)        AS leidos,
       ISNULL(SUM(insertados), 0)    AS insertados,
       ISNULL(SUM(actualizados), 0)  AS actualizados,
       ISNULL(SUM(sin_cambios), 0)   AS sin_cambios,
       ISNULL(SUM(omitidos), 0)      AS omitidos,
       ISNULL(SUM(rechazados), 0)    AS rechazados
FROM DatosGenerales.IMPORTACION
WHERE id_importacion > @importacion_desde
  AND proceso = 'DatosGenerales.usp_ImportarFeriadosAPI';

-- Lo que no se pudo importar. Los feriados de un país que Nager.Date no cubre los carga el 33.
SELECT e.importacion, e.codigo_iso2, pa.paises, e.error
FROM @errores AS e
LEFT JOIN (SELECT codigo_iso2, STRING_AGG(nombre, ', ') AS paises
           FROM DatosGenerales.PAIS
           GROUP BY codigo_iso2) AS pa ON pa.codigo_iso2 = e.codigo_iso2
ORDER BY e.importacion, e.codigo_iso2;

-- Si falló una importación entera (no los feriados de un país), el script termina con error,
-- después de restaurar la configuración.
IF EXISTS (SELECT 1 FROM @errores WHERE codigo_iso2 IS NULL)
    THROW 50002, N'31_Importar_APIs.sql: alguna importación falló (ver la grilla con los errores).', 1;
GO


-- Evidencia: el último PBI per cápita de cada país.
SELECT p.nombre AS pais, p.codigo_iso3, ie.anio AS ultimo_anio, ie.valor AS pbi_per_capita_usd,
       ie.fecha_actualizacion
FROM DatosGenerales.PAIS AS p
LEFT JOIN (SELECT id_pais, MAX(anio) AS ultimo_anio
           FROM DatosGenerales.INDICADOR_ECONOMICO
           WHERE codigo_indicador = 'NY.GDP.PCAP.CD'
           GROUP BY id_pais) AS u ON u.id_pais = p.id_pais
LEFT JOIN DatosGenerales.INDICADOR_ECONOMICO AS ie
       ON ie.id_pais = p.id_pais AND ie.codigo_indicador = 'NY.GDP.PCAP.CD' AND ie.anio = u.ultimo_anio
ORDER BY ie.valor DESC;

-- Evidencia: anunciantes, campañas y piezas por país del anunciante (las del Dossier son de Argentina).
SELECT pa.nombre AS pais, COUNT(DISTINCT an.id_anunciante) AS anunciantes, COUNT(DISTINCT c.id_campania) AS campanias,
       COUNT(pz.id_pieza) AS piezas
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
LEFT JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
LEFT JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
GROUP BY pa.nombre
ORDER BY anunciantes DESC;
GO
