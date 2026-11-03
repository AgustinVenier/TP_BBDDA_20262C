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
 Archivo: 29_ImportarAPIs.sql
 Objetivo: Importar, con los SP de 21_SP_Importar_Publicidad.sql,
           27_SP_Importar_Cotizaciones.sql y 28_SP_Importar_Feriados.sql:
             0. las campañas publicitarias del Mundial 2026 del Dossier
                Mundial, con sus anunciantes y piezas, desde la API de
                Firestore que usa la página;
             1. las cotizaciones contra el dólar de las monedas de todos los
                países del sistema en junio y julio de 2026 (el torneo y las
                campañas publicitarias), desde la API Frankfurter;
             2. los feriados de 2026 de todos los países del sistema, desde
                la API Nager.Date, de a un país por consulta;
             3. a mano, los feriados del período del torneo de los países que
                Nager.Date no cubre.
           Requiere haber ejecutado 00 a 28. Va antes del juego de datos
           (31): así las piezas del Dossier compiten en la asignación de
           publicidad de sus partidos. Se puede ejecutar más de una vez: lo
           que ya está cargado queda SIN CAMBIOS.
================================================================================

 Antes de ejecutar:
   - Necesita internet y OLE Automation, que la instancia trae deshabilitado.
     Este script lo habilita solo mientras consulta las APIs y después lo deja
     como estaba. Hace falta ser sysadmin. Si no hay conexión, las campañas y
     las cotizaciones fallan con su motivo, los feriados de cada país quedan
     informados con su error y se cargan igual los de la parte 3.

 Por qué hay un WHILE: Nager.Date responde los feriados de un país por
 consulta y cada consulta es una llamada a usp_ConsumirAPI. El WHILE recorre
 los países (uno por código ISO: Inglaterra y Escocia comparten GB) y nada
 más; cada respuesta se procesa por conjuntos dentro del SP.

 Feriados cargados a mano (parte 3): Nager.Date no tiene feriados de Irán,
 Arabia Saudita, Catar, Uzbekistán, Jordania, India ni Emiratos Árabes
 Unidos (responde sin contenido). Se cargan los feriados nacionales del
 período del torneo (11/06 al 19/07/2026). Arabia Saudita, Catar y
 Uzbekistán no tienen ninguno en ese período. Los demás son del calendario
 lunar islámico y su fecha se confirma con la observación de la luna: son
 las fechas previstas, a verificar con el calendario oficial de cada país.
 Solo se cargan para los países que la API no cubrió en esta ejecución.

 Resultado: el resumen de las campañas y el de las cotizaciones (leídos,
 insertados, actualizados, sin cambios, omitidos y rechazados), el de los
 feriados por país, el de la carga a mano, los partidos que caen en feriado
 en algún mercado y los anunciantes por país.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- La tabla de la carga a mano (parte 3) no puede existir durante las consultas a la API: si
-- quedó de una ejecución anterior en esta sesión, se borra. Va en un lote aparte porque el
-- lote siguiente se compila entero antes de ejecutarse, contra la tabla que ya exista.
DROP TABLE IF EXISTS #staging_feriados;
GO

DECLARE @ole_antes        INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes  INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'show advanced options');
DECLARE @numero_error     INT;
DECLARE @mensaje_error    NVARCHAR(2048);
-- Feriados: un país por vuelta del WHILE.
DECLARE @anio             SMALLINT = 2026;
DECLARE @i                INT = 1;
DECLARE @total            INT;
DECLARE @codigo_iso2      CHAR(2);
DECLARE @leidos INT, @insertados INT, @actualizados INT, @sin_cambios INT, @omitidos INT, @rechazados INT;
DECLARE @id_importacion   INT;

DECLARE @paises TABLE (orden INT IDENTITY(1,1) PRIMARY KEY, codigo_iso2 CHAR(2));
DECLARE @resultados TABLE (
    codigo_iso2   CHAR(2) PRIMARY KEY,
    leidos        INT,
    insertados    INT,
    actualizados  INT,
    sin_cambios   INT,
    omitidos      INT,
    rechazados    INT,
    error         NVARCHAR(2048)
);

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

-- 0. Campañas del Dossier Mundial, con el período del torneo.
BEGIN TRY
    EXEC Publicidad.usp_ImportarCampaniasAPI @fecha_inicio = '2026-06-11', @fecha_fin = '2026-07-19';
END TRY
BEGIN CATCH
    SELECT @numero_error = ERROR_NUMBER(), @mensaje_error = ERROR_MESSAGE();
END CATCH;

-- 1. Cotizaciones de junio y julio de 2026.
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI @fecha_desde = '2026-06-01', @fecha_hasta = '2026-07-31';
END TRY
BEGIN CATCH
    -- Si fallan también las campañas, se informa ese error, que es el primero.
    IF @mensaje_error IS NULL
        SELECT @numero_error = ERROR_NUMBER(), @mensaje_error = ERROR_MESSAGE();
END CATCH;

-- 2. Feriados de cada país, de a una consulta por código ISO.
INSERT INTO @paises (codigo_iso2)
SELECT DISTINCT codigo_iso2
FROM DatosGenerales.PAIS
WHERE codigo_iso2 IS NOT NULL
ORDER BY codigo_iso2;

SET @total = (SELECT COUNT(*) FROM @paises);

WHILE @i <= @total
BEGIN
    SELECT @codigo_iso2 = codigo_iso2 FROM @paises WHERE orden = @i;

    BEGIN TRY
        EXEC DatosGenerales.usp_ImportarFeriadosAPI
            @codigo_iso2  = @codigo_iso2,
            @anio         = @anio,
            @mostrar      = 0,
            @leidos       = @leidos       OUTPUT,
            @insertados   = @insertados   OUTPUT,
            @actualizados = @actualizados OUTPUT,
            @sin_cambios  = @sin_cambios  OUTPUT,
            @omitidos     = @omitidos     OUTPUT,
            @rechazados   = @rechazados   OUTPUT;

        INSERT INTO @resultados (codigo_iso2, leidos, insertados, actualizados, sin_cambios, omitidos, rechazados)
        VALUES (@codigo_iso2, @leidos, @insertados, @actualizados, @sin_cambios, @omitidos, @rechazados);
    END TRY
    BEGIN CATCH
        INSERT INTO @resultados (codigo_iso2, error) VALUES (@codigo_iso2, ERROR_MESSAGE());
    END CATCH;

    SET @i += 1;
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

SELECT CONCAT(N'https://date.nager.at/api/v3/PublicHolidays/', @anio, N'/{país}') AS origen,
       COUNT(r.leidos)                       AS paises_importados,
       SUM(IIF(r.error IS NULL, 0, 1))       AS paises_con_error,
       ISNULL(SUM(r.leidos), 0)              AS leidos,
       ISNULL(SUM(r.insertados), 0)          AS insertados,
       ISNULL(SUM(r.actualizados), 0)        AS actualizados,
       ISNULL(SUM(r.sin_cambios), 0)         AS sin_cambios,
       ISNULL(SUM(r.omitidos), 0)            AS omitidos,
       ISNULL(SUM(r.rechazados), 0)          AS rechazados
FROM @resultados AS r;

SELECT r.codigo_iso2, pa.paises, r.leidos, r.insertados, r.actualizados, r.sin_cambios, r.omitidos, r.rechazados, r.error
FROM @resultados AS r
CROSS APPLY (SELECT STRING_AGG(nombre, ', ') AS paises FROM DatosGenerales.PAIS
             WHERE codigo_iso2 = r.codigo_iso2) AS pa
ORDER BY IIF(r.error IS NULL, 1, 0), r.codigo_iso2;

/* 3. Carga a mano, con el SP de la Entrega 5, de los países que la API no
      cubrió en esta ejecución (ver "Feriados cargados a mano"). Se registra
      como una importación más, con sus rechazados en
      DatosGenerales.ERRORES_FERIADO. La tabla que lee usp_ImportarFeriados
      se crea recién acá y se borra al terminar: si existiera durante las
      consultas a la API, usp_ProcesarFeriadosJSON crearía otra con el mismo
      nombre y no se sabría cuál lee ese SP. */
CREATE TABLE #staging_feriados (
    id_registro  INT IDENTITY(1,1) PRIMARY KEY,
    codigo_iso2  CHAR(2)        COLLATE DATABASE_DEFAULT NOT NULL,
    id_pais      SMALLINT       NOT NULL,
    fecha        DATE           NOT NULL,
    nombre       NVARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    errores      NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion       VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_feriados (codigo_iso2, id_pais, fecha, nombre)
SELECT f.codigo_iso2, p.id_pais, f.fecha, f.nombre
FROM (VALUES
        ('IR', CAST('2026-06-24' AS DATE), N'Tasua'),
        ('IR', CAST('2026-06-25' AS DATE), N'Ashura'),
        ('IN', CAST('2026-06-26' AS DATE), N'Muharram (Ashura)'),
        ('AE', CAST('2026-06-16' AS DATE), N'Año Nuevo Islámico'),
        ('JO', CAST('2026-06-16' AS DATE), N'Año Nuevo Islámico')
     ) AS f (codigo_iso2, fecha, nombre)
INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_iso2 = f.codigo_iso2
INNER JOIN @resultados AS r ON r.codigo_iso2 = f.codigo_iso2
WHERE r.error IS NOT NULL;

SET @id_importacion = NULL;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM #staging_feriados)
    BEGIN
        BEGIN TRANSACTION;

        EXEC DatosGenerales.usp_ImportarFeriados;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_feriados;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = '29_ImportarAPIs.sql', @origen = N'Feriados cargados a mano (parte 3 del script)',
            @leidos = @leidos, @insertados = @insertados, @actualizados = @actualizados, @sin_cambios = @sin_cambios,
            @rechazados = @rechazados, @id_importacion = @id_importacion OUTPUT;

        INSERT INTO DatosGenerales.ERRORES_FERIADO (id_importacion, registro, codigo_iso2, fecha, nombre_local, motivos)
        SELECT @id_importacion, id_registro, codigo_iso2, CONVERT(NVARCHAR(10), fecha, 23), nombre, STUFF(errores, 1, 2, N'')
        FROM #staging_feriados
        WHERE accion = 'RECHAZADO';

        COMMIT TRANSACTION;
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    -- Si fallan también las campañas o las cotizaciones, se informa ese error, que es el primero.
    IF @mensaje_error IS NULL
        SELECT @numero_error = ERROR_NUMBER(), @mensaje_error = ERROR_MESSAGE();
END CATCH;

SELECT @id_importacion AS id_importacion, N'Carga a mano' AS origen, COUNT(*) AS feriados,
       ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0)   AS insertados,
       ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0) AS actualizados,
       ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0) AS sin_cambios,
       ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)   AS rechazados
FROM #staging_feriados;

SELECT pa.nombre AS pais, sf.fecha, sf.nombre, STUFF(sf.errores, 1, 2, N'') AS motivos
FROM #staging_feriados AS sf
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = sf.id_pais
WHERE sf.accion = 'RECHAZADO';

DROP TABLE #staging_feriados;

-- El error se informa después de restaurar la configuración.
IF @mensaje_error IS NOT NULL
BEGIN
    SET @numero_error = IIF(@numero_error >= 50000, @numero_error, 50000);
    THROW @numero_error, @mensaje_error, 1;
END;
GO


-- Evidencia: partidos del torneo que caen en feriado en algún mercado (fecha local de cada mercado).
SELECT p.numero_partido, p.fecha_hora_utc, m.mercado, m.hora_local, m.feriado, m.en_prime_time
FROM Torneo.PARTIDO AS p
CROSS APPLY Publicidad.fn_MercadosEnPrimeTime(p.id_partido) AS m
WHERE m.es_feriado = 1
ORDER BY p.numero_partido, m.mercado;

-- Evidencia: anunciantes, campañas y piezas por país del anunciante (las del Dossier son de Argentina).
SELECT pa.nombre AS pais, COUNT(DISTINCT an.id_anunciante) AS anunciantes, COUNT(DISTINCT c.id_campania) AS campanias,
       COUNT(pz.id_pieza) AS piezas
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
LEFT JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
LEFT JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
GROUP BY pa.nombre
ORDER BY anunciantes DESC;

-- Evidencia: tarifa de cada espacio de la primera sede en la moneda de cada mercado, el día del primer partido.
DECLARE @fecha DATE = (SELECT CAST(MIN(fecha_hora_local) AS DATE) FROM Torneo.PARTIDO);

SELECT TOP (20) s.nombre_estadio, ep.numero_espacio, ep.tarifa_usd, pa.nombre AS mercado, c.codigo_moneda,
       c.fecha_cotizacion, CAST(ep.tarifa_usd * c.unidades_por_usd AS DECIMAL(19,2)) AS tarifa_en_moneda
FROM Publicidad.ESPACIO_PUBLICITARIO AS ep
INNER JOIN Torneo.SEDE AS s ON s.id_sede = ep.id_sede
CROSS JOIN DatosGenerales.PAIS AS pa
CROSS APPLY DatosGenerales.fn_CotizacionVigente(pa.codigo_moneda, @fecha) AS c
WHERE s.id_sede = (SELECT MIN(id_sede) FROM Torneo.SEDE) AND ep.numero_espacio = 1
ORDER BY pa.nombre;
GO
