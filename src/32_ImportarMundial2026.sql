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
 Archivo: 32_ImportarMundial2026.sql
 Objetivo: Cargar el Mundial 2026 real (las 16 sedes, las 48 selecciones con
           sus 1248 convocados y su director técnico, y los 104 partidos con formaciones, cambios,
           goles y tarjetas) y las designaciones arbitrales de sus 104 partidos
           (terna, cuarto árbitro y VAR) desde los archivos de openfootball y
           los CSV del scraping, con los SP de 23_SP_Importar_Mundial2026.sql,
           24_SP_Importar_Jugadores.sql y 34_SP_Importar_Designaciones.sql.
           Es la alternativa a 31_DatosDePrueba.sql: el torneo de prueba y el
           real no pueden estar en la misma base (cada país tiene una sola
           selección y el número de partido no se repite). Para la base del
           torneo real: ejecutar 00 a 30, el 34 y después este script, en lugar
           del 31. Sobre una base con el torneo de prueba no hace nada.
================================================================================

 Antes de ejecutar:
   - CAMBIAR @repositorio (sección 1) por la ruta de la carpeta del
     repositorio en tu máquina, terminada en \.
   - Haber ejecutado 34_SP_Importar_Designaciones.sql (sin él, la sección 4 se salta).
   - La cuenta del servicio de SQL Server tiene que poder leer las carpetas
     datos\ y scraping\datos\ (ver 26_ImportarIndicadores.sql: icacls ...
     /grant 'NT Service\MSSQLSERVER:(OI)(CI)RX').

 Qué hace:
   1. Importa sedes, selecciones, jugadores, directores técnicos y
      partidos, en ese orden (cada uno necesita lo anterior). Es una
      importación con errores parciales:
      se cargan los registros válidos y se informan los rechazados, que
      quedan en las tablas ERRORES_ con el número de su importación (ver el
      resumen, al final).
      - 13 partidos se rechazan porque el archivo de partidos nombra a tres
        selecciones distinto que el de selecciones ("Bosnia and Herzegovina",
        "Côte d'Ivoire", "Congo DR").
      - 5 partidos se rechazan porque su asistencia supera la capacidad de
        SoFi Stadium que trae el archivo de estadios (70.000, redondeada).
      - Catorce jugadores no se reconocen: el archivo de partidos escribe sus
        nombres de otra forma que el CSV (DANILO, "Behruzjon KARIMOV", Kaku
        con su nombre completo...). Sus formaciones quedan incompletas y se
        rechazan, con sus cambios, goles y tarjetas.
   2. Corrige a mano lo que no se puede deducir de los archivos: registra
      los nombres alternativos de esas selecciones y jugadores, y la
      capacidad de SoFi Stadium.
   3. Vuelve a importar los partidos: lo que ya estaba queda SIN CAMBIOS y
      se carga lo que faltaba.
   4. Importa las designaciones arbitrales (scraping\datos\designaciones.csv):
      las 520 (5 por partido) con 162 árbitros, de los que da de alta a los que
      todavía no están.
   Se puede ejecutar más de una vez sobre la base del torneo real: lo que ya
   está cargado queda SIN CAMBIOS, salvo SoFi Stadium, que se rechaza porque
   el archivo trae una capacidad menor que la corregida (bajarla dejaría
   partidos con más asistencia que capacidad).
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Sobre una base con el torneo de prueba (31) no se carga nada. Se reconoce porque
-- tiene sedes que no vinieron de la importación del archivo de estadios.
IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS)
   OR (EXISTS (SELECT 1 FROM Torneo.SEDE)
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.IMPORTACION WHERE proceso = 'Torneo.usp_ImportarSedesJSON'))
BEGIN
    PRINT N'32_ImportarMundial2026.sql: la base tiene que tener los datos iniciales (20) y no tener el torneo de '
        + N'prueba del 31. Recreá la base con 00 a 30 y el 34, y volvé a ejecutarlo.';
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   1. IMPORTACIÓN (con errores parciales)
   ============================================================================ */

-- CAMBIAR: ruta de la carpeta del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @repositorio NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\';
EXEC sp_set_session_context @key = N'repositorio', @value = @repositorio;

-- Las importaciones de esta ejecución son las que se registren desde acá (para el resumen del final).
DECLARE @importacion_desde INT = ISNULL((SELECT MAX(id_importacion) FROM DatosGenerales.IMPORTACION), 0);
EXEC sp_set_session_context @key = N'importacion_desde', @value = @importacion_desde;
GO

DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'datos\fuentes\openfootball\';
DECLARE @archivo NVARCHAR(400) = @carpeta + N'worldcup.stadiums.json';
EXEC Torneo.usp_ImportarSedesJSON @ruta_archivo = @archivo;

-- Las listas de convocados se presentaron hasta el 1 de junio de 2026.
SET @archivo = @carpeta + N'worldcup.teams.json';
EXEC Torneo.usp_ImportarSeleccionesJSON @ruta_archivo = @archivo, @fecha_presentacion = '2026-06-01';
GO

DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'scraping\datos\jugadores.csv';
EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;

-- El director técnico de cada selección, del mismo scraping (Túnez tuvo dos: queda Hervé Renard).
SET @archivo = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'scraping\datos\cuerpo_tecnico.csv';
EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo;
GO

DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400))
                               + N'datos\fuentes\openfootball\worldcup-full.json';
EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo;
GO


/* ============================================================================
   2. CORRECCIONES CON LOS SP DE ABM
   ============================================================================ */

-- Registra un nombre alternativo de una selección (sin jugador) o de uno de
-- sus jugadores (por nombre y apellido), si todavía no está registrado.
IF OBJECT_ID(N'tempdb..#usp_RegistrarNombreAlternativo', N'P') IS NOT NULL
    DROP PROCEDURE #usp_RegistrarNombreAlternativo;
GO
CREATE PROCEDURE #usp_RegistrarNombreAlternativo
    @codigo_fifa  CHAR(3),
    @nombre_otro  NVARCHAR(120),
    @nombre       NVARCHAR(60) = NULL,
    @apellido     NVARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_seleccion INT, @id_jugador INT;

    SELECT @id_seleccion = s.id_seleccion
    FROM Torneo.SELECCION AS s
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa = @codigo_fifa;

    SELECT @id_jugador = j.id_jugador
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
    WHERE lc.id_seleccion = @id_seleccion
      AND j.nombre = @nombre COLLATE DATABASE_DEFAULT AND j.apellido = @apellido COLLATE DATABASE_DEFAULT;

    IF @nombre IS NOT NULL AND @id_jugador IS NULL
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT(N'No hay un jugador ', @nombre, N' ', @apellido, N' en la lista de ', @codigo_fifa, N'.');
        THROW 50001, @mensaje, 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO
                   WHERE id_seleccion = @id_seleccion AND nombre = @nombre_otro COLLATE DATABASE_DEFAULT
                     AND ISNULL(id_jugador, 0) = ISNULL(@id_jugador, 0))
        EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Alta
            @id_seleccion = @id_seleccion, @nombre = @nombre_otro, @id_jugador = @id_jugador;
END;
GO

BEGIN TRY
    -- Selecciones que el archivo de partidos escribe distinto que el de selecciones.
    EXEC #usp_RegistrarNombreAlternativo 'BIH', N'Bosnia and Herzegovina';
    EXEC #usp_RegistrarNombreAlternativo 'CIV', N'Côte d''Ivoire';
    EXEC #usp_RegistrarNombreAlternativo 'COD', N'Congo DR';

    -- Jugadores que el archivo de partidos escribe de otra forma. En el caso de
    -- DANILO hay dos en la lista de Brasil: es Danilo Luiz, el defensor (el
    -- archivo lo pone entre los defensores de la formación).
    EXEC #usp_RegistrarNombreAlternativo 'BRA', N'DANILO',                  N'Danilo',     N'Luiz';
    EXEC #usp_RegistrarNombreAlternativo 'GHA', N'Baba RAHMAN',             N'Abdul Rahman', N'Baba';
    EXEC #usp_RegistrarNombreAlternativo 'IRN', N'Hossein KANANI',          N'Hossein',    N'Kanaanizadegan';
    EXEC #usp_RegistrarNombreAlternativo 'IRN', N'Ehsan HAJISAFI',          N'Ehsan',      N'Hajsafi';
    EXEC #usp_RegistrarNombreAlternativo 'PAR', N'Alejandro ROMERO GAMARRA', N'Kaku',      N'Kaku';
    EXEC #usp_RegistrarNombreAlternativo 'JOR', N'EHSAN HADDAD',            N'Ihsan',      N'Haddad';
    EXEC #usp_RegistrarNombreAlternativo 'JOR', N'MOHAMMAD ABUHASHEESH',    N'Mohammad',   N'Abu Hashish';
    EXEC #usp_RegistrarNombreAlternativo 'JOR', N'ODEH FAKHOURY',           N'Odeh',       N'Al-Fakhouri';
    EXEC #usp_RegistrarNombreAlternativo 'PAN', N'Amir MURILLO',            N'Michael Amir', N'Murillo';
    EXEC #usp_RegistrarNombreAlternativo 'PAN', N'Edgar Yoel BARCENAS',     N'Yoel',       N'Bárcenas';
    EXEC #usp_RegistrarNombreAlternativo 'TUN', N'Anis SLIMANE',            N'Anis',       N'Ben Slimane';
    EXEC #usp_RegistrarNombreAlternativo 'TUN', N'Mohamed HADJ MAHMOUD',    N'Mohamed',    N'Belhadj Mahmoud';
    EXEC #usp_RegistrarNombreAlternativo 'UZB', N'Behruzjon KARIMOV',       N'Bekhruz',    N'Karimov';
    EXEC #usp_RegistrarNombreAlternativo 'UZB', N'Odiljon XAMROBEKOV',      N'Odiljon',    N'Hamrobekov';

    -- El archivo de estadios trae la capacidad redondeada (70.000) y en SoFi Stadium
    -- hubo partidos con 70.492 espectadores: se toma esa asistencia como capacidad.
    DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = N'SoFi Stadium');
    IF (SELECT capacidad FROM Torneo.SEDE WHERE id_sede = @id_sede) < 70492
        EXEC Torneo.usp_SEDE_Modificacion @id_sede = @id_sede, @capacidad = 70492;

    PRINT N'Correcciones: nombres alternativos y capacidad de SoFi Stadium registrados.';
END TRY
BEGIN CATCH
    PRINT N'Error en las correcciones: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   3. SEGUNDA IMPORTACIÓN DE LOS PARTIDOS
   ============================================================================ */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400))
                               + N'datos\fuentes\openfootball\worldcup-full.json';
EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo;
GO


/* ============================================================================
   4. DESIGNACIONES ARBITRALES
   ============================================================================ */
IF OBJECT_ID(N'Arbitraje.usp_ImportarDesignacionesCSV', N'P') IS NULL
    PRINT N'Designaciones arbitrales: falta ejecutar 34_SP_Importar_Designaciones.sql; no se cargaron.';
ELSE
BEGIN
    DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400))
                                   + N'scraping\datos\designaciones.csv';
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo;
END;
GO


/* ============================================================================
   5. RESUMEN
   ============================================================================ */
SELECT s.name + N'.' + t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE s.name IN (N'Torneo', N'DesarrolloPartido', N'Arbitraje')
GROUP BY s.name, t.name
ORDER BY s.name, t.name;

-- Fixture con resultados.
SELECT numero_partido, fase, seleccion_local, resultado, seleccion_visitante, asistencia, estado
FROM Torneo.vw_Fixture
ORDER BY numero_partido;

-- Las importaciones de esta ejecución, con cuántos rechazados quedaron en cada tabla ERRORES_.
SELECT i.id_importacion, i.proceso, i.origen, i.fecha_hora, i.leidos, i.insertados, i.actualizados, i.sin_cambios,
       i.rechazados,
       (SELECT COUNT(*) FROM Torneo.ERRORES_SEDE AS e WHERE e.id_importacion = i.id_importacion)          AS errores_sede,
       (SELECT COUNT(*) FROM Torneo.ERRORES_SELECCION AS e WHERE e.id_importacion = i.id_importacion)     AS errores_seleccion,
       (SELECT COUNT(*) FROM Torneo.ERRORES_JUGADOR AS e WHERE e.id_importacion = i.id_importacion)       AS errores_jugador,
       (SELECT COUNT(*) FROM Torneo.ERRORES_CUERPO_TECNICO AS e WHERE e.id_importacion = i.id_importacion) AS errores_cuerpo_tecnico,
       (SELECT COUNT(*) FROM Torneo.ERRORES_PARTIDO AS e WHERE e.id_importacion = i.id_importacion)       AS errores_partido,
       (SELECT COUNT(*) FROM DesarrolloPartido.ERRORES_EVENTO AS e WHERE e.id_importacion = i.id_importacion) AS errores_evento,
       (SELECT COUNT(*) FROM Arbitraje.ERRORES_DESIGNACION AS e WHERE e.id_importacion = i.id_importacion)   AS errores_designacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion > CAST(SESSION_CONTEXT(N'importacion_desde') AS INT)
ORDER BY i.id_importacion;
GO

SET NOEXEC OFF;
GO
