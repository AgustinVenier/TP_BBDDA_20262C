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

 Fecha: 03/11/2026
 Archivo: 36_Ejecutar_Entrega6_Importacion.sql
 Objetivo: Entrega 6. Mostrar en vivo el scraping y la importación sobre la
           base ya cargada, sin recrearla: importación sin duplicados, con
           errores parciales y con registros nuevos.
           Requiere haber ejecutado 00 a 32. Para las pruebas de cada SP está
           73_Test_SP_Importar_Mundial2026.sql.
================================================================================

 Antes de ejecutar:
   - CAMBIAR @repositorio (primer lote) por la ruta de la carpeta del
     repositorio en tu máquina, terminada en \.
   - La cuenta del servicio de SQL Server tiene que poder leer las carpetas
     datos\ y scraping\datos\ (ver "Antes de ejecutar" en
     31_Ejecutar_ImportarMundial2026.sql).
   - El paso 3 necesita internet y OLE Automation, que la instancia trae
     deshabilitado. El script lo habilita solo mientras consulta la API y
     después lo deja como estaba. Hace falta ser sysadmin.
   - Conviene ejecutar de a un paso: seleccionar el lote y F5, en la misma
     ventana, empezando por el primer lote.

 PASO 1. Scraping (en una terminal, desde la carpeta del repositorio). Se puede
 repetir aunque los CSV ya existan: los sobrescribe, y si falla una descarga no
 los toca. Si no están instaladas las bibliotecas:
   pip install requests beautifulsoup4 lxml

   python scraping/Scraping_Jugadores.py
     Esperado: Selecciones: 48  Jugadores: 1248  Directores técnicos: 48
     Genera scraping/datos/jugadores.csv y scraping/datos/cuerpo_tecnico.csv
   python scraping/Scraping_Arbitros.py
     Esperado: Partidos: 104  Designaciones: 832  Árbitros: 169
     Genera scraping/datos/designaciones_arbitrales.csv

 Los pasos siguientes, en este script:
   Paso 2. Importar lo scrapeado: no duplica nada.
             Torneo.usp_ImportarJugadoresCSV
             Torneo.usp_ImportarCuerpoTecnicoCSV
             Arbitraje.usp_ImportarDesignacionesCSV
   Paso 3. Importación con errores parciales: una sede rechazada.
             Torneo.usp_ImportarSedesJSON
   Paso 4. Registros nuevos desde una API: inserta y, la segunda vez, no duplica.
             DatosGenerales.usp_ImportarCotizacionesAPI
   Paso 5. Registro de lo importado.

 Qué queda en la base: el registro de cada importación, el rechazo del paso 3 y
 las cotizaciones del paso 4, que ningún reporte usa porque las conversiones
 toman la fecha de cada partido (junio y julio de 2026).

 Los demás procesos de importación, en sus propios scripts:
   26_Ejecutar_ImportarIndicadores.sql   DatosGenerales.usp_ImportarIndicadoresAPI
   29_Ejecutar_ImportarAPIs.sql          Publicidad.usp_ImportarCampaniasAPI
                                         DatosGenerales.usp_ImportarCotizacionesAPI
                                         DatosGenerales.usp_ImportarFeriadosAPI
   31_Ejecutar_ImportarMundial2026.sql   Torneo.usp_ImportarSedesJSON
                                         Torneo.usp_ImportarSeleccionesJSON
                                         Torneo.usp_ImportarJugadoresCSV
                                         Torneo.usp_ImportarCuerpoTecnicoCSV
                                         Torneo.usp_ImportarPartidosJSON
                                         Arbitraje.usp_ImportarDesignacionesCSV
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- CAMBIAR: ruta de la carpeta del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @repositorio NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\';
EXEC sp_set_session_context @key = N'repositorio', @value = @repositorio;

-- Las importaciones de esta ejecución son las que se registren desde acá (para el paso 5).
DECLARE @importacion_desde INT = ISNULL((SELECT MAX(id_importacion) FROM DatosGenerales.IMPORTACION), 0);
EXEC sp_set_session_context @key = N'importacion_desde', @value = @importacion_desde;

IF NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE estado = 'FINALIZADO')
   OR NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR WHERE fecha_baja IS NOT NULL)
BEGIN
    RAISERROR(N'Falta el torneo real cargado: ejecutar 00 a 32.', 16, 1);
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   PASO 2. IMPORTAR LO SCRAPEADO
   Todo ya estaba cargado, así que nada se duplica.
   Esperado: jugadores, 1248 leídos y 1248 sin cambios; directores técnicos, 48
   leídos y 48 sin cambios; designaciones, 832 sin cambios, y árbitros, 169 sin
   cambios. Sin rechazados.
   ============================================================================ */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'scraping\datos\jugadores.csv';
EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;

SET @archivo = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'scraping\datos\cuerpo_tecnico.csv';
EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo;

SET @archivo = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'scraping\datos\designaciones_arbitrales.csv';
EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo;
GO


/* ============================================================================
   PASO 3. IMPORTACIÓN CON ERRORES PARCIALES
   El archivo trae la capacidad de SoFi Stadium redondeada (70.000), menor que
   la asistencia de partidos ya jugados: 31_Ejecutar_ImportarMundial2026.sql la
   corrigió a 70.492, y bajarla dejaría esos partidos con más asistencia que
   capacidad.
   Esperado: 16 leídos, 15 sin cambios y 1 rechazado (SoFi Stadium), que queda
   registrado en Torneo.ERRORES_SEDE.
   ============================================================================ */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400))
                               + N'datos\fuentes\openfootball\worldcup.stadiums.json';
EXEC Torneo.usp_ImportarSedesJSON @ruta_archivo = @archivo;
GO


/* ============================================================================
   PASO 4. REGISTROS NUEVOS DESDE UNA API
   Cotizaciones contra el dólar de un mes que todavía no está cargado, pedidas
   dos veces. La importación de 29_Ejecutar_ImportarAPIs.sql cargó junio y julio
   de 2026.
   Esperado, con octubre de 2026: la primera vez 91 leídos y 91 insertados; la
   segunda 91 leídos y 91 sin cambios.
   Para volver a ver insertados hay que pedir otro mes: CAMBIAR @fecha_desde y
   @fecha_hasta (por ejemplo, ensayar con agosto y presentar con octubre).
   ============================================================================ */
DECLARE @fecha_desde      DATE = '2026-10-01';
DECLARE @fecha_hasta      DATE = '2026-10-31';
DECLARE @ole_antes        INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes  INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'show advanced options');
DECLARE @numero_error     INT;
DECLARE @mensaje_error    NVARCHAR(2048);

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

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarCotizacionesAPI
        @monedas = 'ARS;EUR;BRL', @fecha_desde = @fecha_desde, @fecha_hasta = @fecha_hasta;

    EXEC DatosGenerales.usp_ImportarCotizacionesAPI
        @monedas = 'ARS;EUR;BRL', @fecha_desde = @fecha_desde, @fecha_hasta = @fecha_hasta;
END TRY
BEGIN CATCH
    SELECT @numero_error = ERROR_NUMBER(), @mensaje_error = ERROR_MESSAGE();
END CATCH;

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

-- El error se informa después de restaurar la configuración.
IF @mensaje_error IS NOT NULL
BEGIN
    SET @numero_error = IIF(@numero_error >= 50000, @numero_error, 50000);
    THROW @numero_error, @mensaje_error, 1;
END;
GO


/* ============================================================================
   PASO 5. REGISTRO DE LO IMPORTADO
   Esperado: una fila por cada importación de esta ejecución, y SoFi Stadium
   con su motivo.
   ============================================================================ */
SELECT id_importacion, proceso, origen, fecha_hora, leidos, insertados, actualizados, sin_cambios, omitidos, rechazados
FROM DatosGenerales.IMPORTACION
WHERE id_importacion > CAST(SESSION_CONTEXT(N'importacion_desde') AS INT)
ORDER BY id_importacion;

SELECT e.id_importacion, e.registro, e.nombre_estadio, e.capacidad, e.motivos
FROM Torneo.ERRORES_SEDE AS e
WHERE e.id_importacion > CAST(SESSION_CONTEXT(N'importacion_desde') AS INT)
ORDER BY e.id_importacion, e.registro;
GO

SET NOEXEC OFF;
GO
