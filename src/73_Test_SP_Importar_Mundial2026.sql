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
 Archivo: 73_Test_SP_Importar_Mundial2026.sql
 Objetivo: Probar la importación del Mundial 2026 de
           23_SP_Importar_Mundial2026.sql (sedes, selecciones y partidos en
           JSON, y el equipo arbitral en CSV) y 24_SP_Importar_Jugadores.sql
           (jugadores y directores técnicos en CSV), y el ABM
           de Torneo.NOMBRE_ALTERNATIVO de 05_SP_ABM_Torneo.sql, con los
           archivos chicos de datos/pruebas/mundial_prueba_*: alta,
           reimportación sin duplicados, actualización, importación con
           errores parciales (con el registro de la importación y sus
           rechazados en las tablas ERRORES_), reconocimiento de jugadores por
           nombre y los archivos que no se pueden importar. Las reglas de cada
           tabla las prueba 66_Test_SP_Importacion.sql, con los SP de
           16_SP_Importacion.sql.
           Requiere haber ejecutado 00 a 24. No depende del juego de datos
           (sirve con o sin el torneo real del 31 cargado): crea
           sus propios países (códigos ZZA, ZZB y ZZC), selecciones, sede,
           partidos (números 201 a 203) y árbitros ("Árbitro Prueba ...", con
           sus designaciones), y al final los borra con los SP de
           baja, junto con el registro de sus importaciones
           (DatosGenerales.usp_BorrarImportacion), así que se puede ejecutar
           más de una vez.
================================================================================

 Antes de ejecutar: CAMBIAR @carpeta, en el primer lote, por la ruta de la
 carpeta datos\pruebas\ del repositorio en tu máquina. La cuenta del servicio
 de SQL Server tiene que poder leerla (ver "Antes de ejecutar" en
 26_ImportarIndicadores.sql).

 Los jugadores de los archivos de prueba están escritos para pasar por cada
 paso de Torneo.usp_IdentificarJugadores:
   "Arturo PRUEBA"     Arturo Prueba          1. nombre completo
   "Fabian PRUEBA"     Fabián Prueba          1. sin distinguir tildes
   "Juergen RUEDIGER"  Jürgen Rüdiger         1. ue como ü
   "Maxi ARAUJO"       Maximiliano Araújo     2. mismo apellido, nombre parecido
   "Mostafa ZICO"      Mostafa Ziko           3. mismo nombre, apellido parecido
   "MOUSA ALTAMARI"    Musa Al-Taamari        4. suenan igual (todo en mayúsculas)
   "CASEMIRO"          Casemiro Casemiro      5. conocido por un solo nombre
   "Diego GOMEZ"       Diego Gómez o Gomez    ambiguo: se rechaza
   "DANILO"            Danilo Luiz            no se reconoce: se rechaza
 Los dos últimos se resuelven en MI8 con nombres alternativos.

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el resumen de la importación y los
     rechazados con sus motivos, y después los datos que quedaron.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con otro número de error, se imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Carpeta de los archivos de prueba (para los lotes siguientes).
-- CAMBIAR: ruta de la carpeta datos\pruebas\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @carpeta NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\datos\pruebas\';
EXEC sp_set_session_context @key = N'carpeta_pruebas', @value = @carpeta;

IF OBJECT_ID(N'Torneo.usp_ImportarPartidosJSON', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_ImportarJugadoresCSV', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA')
BEGIN
    RAISERROR(N'Faltan los SP de importación o los datos iniciales: ejecutar los scripts 00 a 24.', 16, 1);
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

-- Borra un partido de prueba y todo lo que tenga, en el orden que exigen los SP de baja.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPartido', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPartido;
GO
CREATE PROCEDURE #usp_LimpiarPartido
    @numero_partido TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = @numero_partido);
    DECLARE @id INT, @id2 INT;
    IF @id_partido IS NULL RETURN;

    IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido) = 'FINALIZADO'
        EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.GOL WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_gol FROM DesarrolloPartido.GOL WHERE id_partido = @id_partido;
        EXEC DesarrolloPartido.usp_GOL_Baja @id_gol = @id;
    END;
    -- Primero las rojas: una roja por doble amarilla impide borrar sus amarillas.
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_amonestacion FROM DesarrolloPartido.AMONESTACION
        WHERE id_partido = @id_partido ORDER BY IIF(tipo_tarjeta = 'ROJA', 0, 1);
        EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
    END;
    -- Del último cambio al primero: el que entró puede haber salido en un cambio posterior.
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_cambio FROM DesarrolloPartido.CAMBIO
        WHERE id_partido = @id_partido ORDER BY minuto DESC, minuto_adicional DESC, id_cambio DESC;
        EXEC DesarrolloPartido.usp_CAMBIO_Baja @id_cambio = @id;
    END;
    IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido) IN ('EN_JUEGO', 'SUSPENDIDO')
        EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'PROGRAMADO';
    -- Las designaciones se dan de baja con el partido PROGRAMADO.
    WHILE EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_arbitro FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido;
        EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                  INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                  WHERE f.id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = a.id_formacion, @id2 = a.id_jugador
        FROM DesarrolloPartido.ALINEACION AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
        WHERE f.id_partido = @id_partido;
        EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id, @id_jugador = @id2;
    END;
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_formacion FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;
        EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id;
    END;
    EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id_partido;
END;
GO

-- Borra todo lo que carga el test, con los SP de baja.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT;

    EXEC #usp_LimpiarPartido @numero_partido = 201;
    EXEC #usp_LimpiarPartido @numero_partido = 202;
    EXEC #usp_LimpiarPartido @numero_partido = 203;

    WHILE EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                  INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = na.id_seleccion
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = na.id_nombre_alternativo
        FROM Torneo.NOMBRE_ALTERNATIVO AS na
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = na.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Baja @id_nombre_alternativo = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j
                  INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
                  INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = j.id_jugador
        FROM Torneo.JUGADOR AS j
        INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS AS lc
                  INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = lc.id_lista
        FROM Torneo.LISTA_CONVOCADOS AS lc
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
    END;

    DELETE ct
    FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');

    WHILE EXISTS (SELECT 1 FROM Torneo.SELECCION AS s
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = s.id_seleccion
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO AS e
                  INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                  WHERE s.nombre_estadio = 'Estadio Prueba Importacion')
    BEGIN
        SELECT TOP (1) @id = e.id_espacio
        FROM Publicidad.ESPACIO_PUBLICITARIO AS e
        INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
        WHERE s.nombre_estadio = 'Estadio Prueba Importacion';
        EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id;
    END;

    SET @id = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Importacion');
    IF @id IS NOT NULL EXEC Torneo.usp_SEDE_Baja @id_sede = @id;

    WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO AS a
                  INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
                  WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = a.id_arbitro
        FROM Arbitraje.ARBITRO AS a
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
        WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id, @eliminar_registro = 1;
    END;

    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC'))
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC');
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;

    -- El registro de las importaciones de los archivos de prueba, con sus rechazados.
    DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
    DECLARE @archivo NVARCHAR(400);
    SET @archivo = @carpeta + N'mundial_prueba_estadios.json';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_selecciones.json';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_jugadores.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_jugadores_cambios.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_partidos.json';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_partidos_cambios.json';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_designaciones.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_cuerpo_tecnico.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
    SET @archivo = @carpeta + N'mundial_prueba_cuerpo_tecnico_cambios.csv';
    EXEC DatosGenerales.usp_BorrarImportacion @origen = @archivo;
END;
GO

-- Por si una corrida anterior del test quedó a medias.
EXEC #usp_LimpiarPruebas;
GO

-- Países de prueba (los códigos ZZA, ZZB y ZZC no son de ninguna federación).
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Importación A', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZA', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Importación B', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZB', @codigo_moneda = 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'País Prueba Importación C', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'ZZC', @codigo_moneda = 'ARS';
GO


/* ============================================================================
   SEDES Y SELECCIONES
   ============================================================================ */

/* MI1 (OK) Importación con errores parciales de mundial_prueba_estadios.json.
   Esperado: 2 leídos, 1 insertado y 1 rechazado (Estadio Prueba Invalido: el
   país "XX" no es un código ISO alfa-2 registrado, no se reconoce el huso
   para ese país, la capacidad "mucha" no es un número y las coordenadas "al
   norte" no son válidas). La sede nueva queda en Eastern Standard Time
   (desfase UTC-4 en Estados Unidos), con latitud -34.586667 y longitud
   -58.381806 (34°35'12"S 58°22'54.5"W) y sus 4 espacios publicitarios.
   La importación queda registrada en DatosGenerales.IMPORTACION (proceso
   Torneo.usp_ImportarSedesJSON, 2 leídos, 1 insertado y 1 rechazado) y el
   rechazado, en Torneo.ERRORES_SEDE con el número de la importación, tal
   como venía en el archivo (país XX, huso UTC-4, capacidad "mucha",
   coordenadas "al norte") y con sus motivos. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_estadios.json';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarSedesJSON @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI1 sede' AS caso, s.nombre_estadio, s.ciudad, p.codigo_fifa, s.capacidad, s.huso_horario, s.latitud, s.longitud,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS espacios
FROM Torneo.SEDE AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE s.nombre_estadio LIKE 'Estadio Prueba%';

SELECT 'MI1 registro' AS caso, i.proceso, i.leidos, i.insertados, i.rechazados, e.registro, e.nombre_estadio, e.pais,
       e.huso_horario, e.capacidad, e.coordenadas, REPLACE(e.motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM DatosGenerales.IMPORTACION AS i
LEFT JOIN Torneo.ERRORES_SEDE AS e ON e.id_importacion = i.id_importacion
WHERE i.id_importacion = @id_importacion;
GO


/* MI2 (OK) Reimportación de mundial_prueba_estadios.json.
   Esperado: 1 sin cambios y 1 rechazado; sigue habiendo una sola sede de
   prueba con 4 espacios. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_estadios.json';

EXEC Torneo.usp_ImportarSedesJSON @ruta_archivo = @archivo;

SELECT 'MI2 después' AS caso, COUNT(*) AS sedes,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e
        INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
        WHERE s.nombre_estadio LIKE 'Estadio Prueba%') AS espacios
FROM Torneo.SEDE
WHERE nombre_estadio LIKE 'Estadio Prueba%';
GO


/* MI3 (OK) Importación con errores parciales de mundial_prueba_selecciones.json.
   Esperado: 4 leídos, 2 insertados (ZZA y ZZB, con su lista de convocados
   presentada el 01/07/2026 y su nombre en inglés como nombre alternativo) y
   2 rechazados (ZZC: la confederación "MARS" no es válida; QQQ: no hay un
   país con ese código). */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_selecciones.json';

EXEC Torneo.usp_ImportarSeleccionesJSON @ruta_archivo = @archivo, @fecha_presentacion = '2026-07-01';

SELECT 'MI3 selecciones' AS caso, p.codigo_fifa, s.confederacion, s.grupo, lc.fecha_presentacion, na.nombre AS nombre_alternativo
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_seleccion = s.id_seleccion
LEFT JOIN Torneo.NOMBRE_ALTERNATIVO AS na ON na.id_seleccion = s.id_seleccion AND na.id_jugador IS NULL
WHERE p.codigo_fifa IN ('ZZA', 'ZZB', 'ZZC')
ORDER BY p.codigo_fifa;
GO


/* ============================================================================
   JUGADORES (CSV)
   ============================================================================ */

/* MI4 (OK) Importación con errores parciales de mundial_prueba_jugadores.csv:
   23 jugadores de ZZA y 23 de ZZB, más 4 filas con errores.
   Esperado: 50 leídos, 46 insertados y 4 rechazados (línea 25: el dorsal 150
   no está entre 1 y 99; línea 49: la posición "XX" no es ARQUERO, DEFENSOR,
   MEDIOCAMPISTA ni DELANTERO; línea 50: la fecha "1999-13-40" no es una
   fecha; línea 51: no hay una selección con lista con código QQQ). Los
   cuatro quedan en Torneo.ERRORES_JUGADOR con el número de la importación.
   El club de ZZB, que viene entre comillas porque tiene una coma, queda
   completo. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_jugadores.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI4 rechazados' AS caso, registro AS linea, codigo_fifa, dorsal, posicion, nombre, apellido, fecha_nacimiento,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Torneo.ERRORES_JUGADOR
WHERE id_importacion = @id_importacion
ORDER BY registro;

SELECT 'MI4 listas' AS caso, p.codigo_fifa, COUNT(*) AS jugadores, SUM(IIF(j.posicion_habitual = 'ARQUERO', 1, 0)) AS arqueros,
       MIN(j.fecha_alta) AS fecha_alta, MIN(j.motivo_alta) AS motivo_alta, MAX(j.club_origen) AS club
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa IN ('ZZA', 'ZZB')
GROUP BY p.codigo_fifa;
GO


/* MI5 (OK) Reimportación de mundial_prueba_jugadores.csv.
   Esperado: 46 sin cambios y los mismos 4 rechazados; siguen 46 jugadores. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_jugadores.csv';

EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;
GO


/* MI6 (OK) Importación de mundial_prueba_jugadores_cambios.csv sobre las
   listas cargadas.
   Esperado: 4 leídos: 1 actualizado (Bruno Prueba cambia de club), 1 sin
   cambios (Carlos Prueba), 1 insertado (Nuevo Prueba, dorsal 24: la lista
   queda con 24) y 1 rechazado (Otro Prueba: el dorsal 4 ya lo tiene Darío
   Prueba, que no viene en el archivo). */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_jugadores_cambios.csv';

EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;

SELECT 'MI6 jugadores' AS caso, j.dorsal, j.nombre, j.apellido, j.club_origen
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa = 'ZZA' AND j.dorsal IN (2, 3, 4, 24)
ORDER BY j.dorsal;
GO


/* ============================================================================
   PARTIDOS
   ============================================================================ */

/* MI7 (OK) Importación con errores parciales de mundial_prueba_partidos.json,
   numerando desde el 201.
   Esperado:
   - Partidos: 4 leídos, 2 insertados y 2 rechazados. El 201 (octavos, 3 a 2
     en el alargue) y el 202 (cuartos, 1 a 1 y 4 a 3 en penales) quedan
     FINALIZADOS. Se rechaza el de Atlantis (la hora "tarde" no es una hora,
     no hay una selección Atlantis y el estadio no es de ninguna sede) y la
     semifinal (la asistencia 50000 no está entre 0 y la capacidad de la
     sede, 40000). La hora local es la del archivo (16:00 y 20:00) y la UTC,
     4 horas más. Los dos partidos rechazados quedan en
     Torneo.ERRORES_PARTIDO y los 4 eventos rechazados, en
     DesarrolloPartido.ERRORES_EVENTO, con el número de la importación.
   - Eventos: se rechazan DANILO (no coincide con ningún jugador de ZZA) y
     Diego GOMEZ (puede ser Diego Gómez o Diego Gomez) en el banco del 201, el
     cambio en el que entra DANILO y la amarilla de Diego GOMEZ. Se cargan las
     4 formaciones (4-3-3), 3 cambios en el 201 (Lucas por Kevin en el
     entretiempo, minuto 46; Fabián por Arturo en el 120+1, que el archivo
     escribe 121; Damián por Alan), 7 goles con su período (el penal del 45+2
     en ADICIONALES, el del 105 en ALARGUE y el en contra de Bruno Prueba,
     que suma para ZZB), los 7 penales convertidos de la definición del 202
     (4 de ZZB y 3 de ZZA; el errado no se carga) y las tarjetas (la Y/R de
     Bruno Prueba como amarilla y roja por doble amarilla).
   - Ningún partido con el resultado distinto de los goles cargados. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_partidos.json';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201, @id_importacion = @id_importacion OUTPUT;
EXEC sp_set_session_context @key = N'importacion_mi7', @value = @id_importacion;   -- la reprocesa MI8

SELECT 'MI7 registro' AS caso, i.proceso, i.leidos, i.insertados, i.rechazados,
       (SELECT COUNT(*) FROM Torneo.ERRORES_PARTIDO AS e WHERE e.id_importacion = i.id_importacion) AS errores_partido,
       (SELECT COUNT(*) FROM DesarrolloPartido.ERRORES_EVENTO AS e WHERE e.id_importacion = i.id_importacion) AS errores_evento
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MI7 errores' AS caso, registro, ronda, fecha, hora, equipo_1, equipo_2, estadio, asistencia, resultado,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Torneo.ERRORES_PARTIDO
WHERE id_importacion = @id_importacion
ORDER BY registro;

SELECT 'MI7 partidos' AS caso, f.numero_partido, f.fase, f.seleccion_local, f.resultado, f.seleccion_visitante,
       f.asistencia, f.estado, p.fecha_hora_local, p.fecha_hora_utc
FROM Torneo.vw_Fixture AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
WHERE f.numero_partido BETWEEN 201 AND 203
ORDER BY f.numero_partido;

SELECT 'MI7 formaciones' AS caso, p.numero_partido, pa.codigo_fifa, f.esquema_tactico,
       SUM(IIF(a.es_titular = 1, 1, 0)) AS titulares, SUM(IIF(a.es_titular = 0, 1, 0)) AS suplentes
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
WHERE p.numero_partido BETWEEN 201 AND 203
GROUP BY p.numero_partido, pa.codigo_fifa, f.esquema_tactico
ORDER BY p.numero_partido, pa.codigo_fifa;

SELECT 'MI7 goles' AS caso, p.numero_partido, j.nombre + N' ' + j.apellido AS autor, tg.descripcion AS tipo,
       g.periodo, g.minuto, g.minuto_adicional
FROM DesarrolloPartido.GOL AS g
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
WHERE p.numero_partido BETWEEN 201 AND 203
ORDER BY p.numero_partido, g.periodo, g.minuto;

SELECT 'MI7 cambios y tarjetas' AS caso, p.numero_partido, 'CAMBIO' AS registro,
       js.nombre + N' por ' + je.nombre AS detalle, c.minuto, c.minuto_adicional, CAST(c.en_entretiempo AS INT) AS otro
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
INNER JOIN Torneo.JUGADOR AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.JUGADOR AS je ON je.id_jugador = c.id_jugador_entra
WHERE p.numero_partido BETWEEN 201 AND 203
UNION ALL
SELECT 'MI7 cambios y tarjetas', p.numero_partido, a.tipo_tarjeta, j.nombre + N' ' + j.apellido, a.minuto, a.minuto_adicional,
       CAST(a.es_doble_amarilla AS INT)
FROM DesarrolloPartido.AMONESTACION AS a
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE p.numero_partido BETWEEN 201 AND 203
ORDER BY 2, 3, 5, 6;
GO


/* MI8 (OK) Nombres alternativos y reproceso: se registra que DANILO es
   Danilo Luiz y que "Diego GOMEZ" es Diego Gómez, y se reprocesan los
   partidos rechazados en MI7 (@reprocesar_importacion).
   Esperado: se procesan solo los 3 partidos con algún rechazo en MI7: el
   201, que queda SIN CAMBIOS, y los 2 rechazados, que se vuelven a rechazar
   (con el número de la nueva importación). El 202, que se cargó completo,
   no se vuelve a leer. Del 201 se cargan los 4 eventos que faltaban (la
   formación de ZZA se completa con Danilo Luiz y Diego Gómez en el banco, el
   cambio de Esteban por Danilo y la amarilla de Diego Gómez) y el resto
   queda SIN CAMBIOS: 0 eventos rechazados y nada repetido. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_partidos.json';
DECLARE @reprocesar INT = CAST(SESSION_CONTEXT(N'importacion_mi7') AS INT);
DECLARE @id_importacion INT;
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                             INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'ZZA');
DECLARE @danilo INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j
                       INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
                       WHERE lc.id_seleccion = @id_seleccion AND j.nombre = N'Danilo' AND j.apellido = N'Luiz');
DECLARE @gomez INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j
                      INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
                      WHERE lc.id_seleccion = @id_seleccion AND j.nombre = N'Diego' AND j.apellido = N'Gómez');

EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Alta @id_seleccion = @id_seleccion, @nombre = N'DANILO', @id_jugador = @danilo;
EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Alta @id_seleccion = @id_seleccion, @nombre = N'Diego GOMEZ', @id_jugador = @gomez;

EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201,
     @reprocesar_importacion = @reprocesar, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI8 registro' AS caso, i.leidos, i.insertados, i.sin_cambios, i.rechazados,
       (SELECT COUNT(*) FROM Torneo.ERRORES_PARTIDO AS e WHERE e.id_importacion = i.id_importacion) AS errores_partido,
       (SELECT COUNT(*) FROM DesarrolloPartido.ERRORES_EVENTO AS e WHERE e.id_importacion = i.id_importacion) AS errores_evento
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MI8 después' AS caso, p.numero_partido,
       (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion WHERE f.id_partido = p.id_partido) AS alineados,
       (SELECT COUNT(*) FROM DesarrolloPartido.CAMBIO AS c WHERE c.id_partido = p.id_partido) AS cambios,
       (SELECT COUNT(*) FROM DesarrolloPartido.GOL AS g WHERE g.id_partido = p.id_partido) AS goles,
       (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION AS a WHERE a.id_partido = p.id_partido) AS tarjetas
FROM Torneo.PARTIDO AS p
WHERE p.numero_partido BETWEEN 201 AND 203
ORDER BY p.numero_partido;
GO


/* MI8b (OK) Importación completa de mundial_prueba_partidos.json después del
   reproceso, para comprobar que no le faltó nada.
   Esperado: 4 partidos leídos: el 201 y el 202 SIN CAMBIOS y los mismos 2
   rechazados; todos los eventos SIN CAMBIOS (0 insertados y 0 rechazados). */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_partidos.json';

EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201;
GO


/* MI8c (OK) Importación de mundial_prueba_partidos_cambios.json: el mismo
   archivo, con correcciones de la fuente en el 201.
   Esperado: los partidos como en MI8b (el 201 y el 202 SIN CAMBIOS y los
   mismos 2 rechazados). De los eventos, 6 ACTUALIZADO: el gol de Jürgen
   Rüdiger, del 9 al 10 (no se repite); el de Mostafa Ziko en el 45+2, de
   PENAL a JUGADA; la amarilla de Diego Gómez, del 50 al 52; el cambio de
   Alan por Damián, del 75 al 78 (sigue TACTICO); y en ZZB, Emilio titular y
   Víctor al banco. 1 RECHAZADO: el gol del 60, que el archivo le atribuye a
   Xavier en lugar de Yago (es otro gol, y ZZB quedaría con 3 y su
   resultado es 2). El resto SIN CAMBIOS: el 201 sigue con 5 goles, 4
   cambios y 5 tarjetas, y el de Yago queda. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400))
                               + N'mundial_prueba_partidos_cambios.json';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI8c registro' AS caso, i.leidos, i.insertados, i.actualizados, i.sin_cambios, i.rechazados,
       (SELECT COUNT(*) FROM DesarrolloPartido.ERRORES_EVENTO AS e WHERE e.id_importacion = i.id_importacion) AS errores_evento
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MI8c 201' AS caso, 'GOL' AS registro, j.nombre + N' ' + j.apellido AS detalle, tg.descripcion AS tipo, g.minuto,
       g.minuto_adicional
FROM DesarrolloPartido.GOL AS g
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
WHERE p.numero_partido = 201
UNION ALL
SELECT 'MI8c 201', 'CAMBIO', js.nombre + N' por ' + je.nombre, c.motivo, c.minuto, c.minuto_adicional
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
INNER JOIN Torneo.JUGADOR AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.JUGADOR AS je ON je.id_jugador = c.id_jugador_entra
WHERE p.numero_partido = 201
UNION ALL
SELECT 'MI8c 201', 'TARJETA', j.nombre + N' ' + j.apellido, a.tipo_tarjeta, a.minuto, a.minuto_adicional
FROM DesarrolloPartido.AMONESTACION AS a
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE p.numero_partido = 201
ORDER BY 2, 5, 6;

SELECT 'MI8c banco' AS caso, pa.codigo_fifa, STRING_AGG(j.nombre, N', ') WITHIN GROUP (ORDER BY j.dorsal) AS suplentes
FROM DesarrolloPartido.ALINEACION AS a
INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE p.numero_partido = 201 AND a.es_titular = 0
GROUP BY pa.codigo_fifa
ORDER BY pa.codigo_fifa;
GO


/* ============================================================================
   EQUIPO ARBITRAL (CSV)
   ============================================================================ */

/* MI12 (OK) Importación con errores parciales de mundial_prueba_designaciones.csv,
   sobre los partidos 201 (ZZA - ZZB, 01/08/2026) y 202 (ZZB - ZZA, 05/08/2026),
   que ya se jugaron (es una carga histórica).
   Esperado:
   - Designaciones: 13 leídas, 6 insertadas y 7 rechazadas. Se cargan en el
     201 el PRINCIPAL, los dos asistentes, el CUARTO y el VAR (de ZZC, con los
     roles en inglés) y el ASISTENTE_RESERVA "Árbitro, Jr." (viene entre
     comillas porque tiene una coma). Se rechazan: el AVAR "Prueba
     Conflicto" (conflicto de nacionalidad: es de ZZA); las dos del 202, que
     traen dos PRINCIPAL (las selecciones vienen en los dos órdenes); la del
     03/08, que no tiene partido; la fecha 2026-13-01; la de "Prueba Seis",
     un árbitro rechazado (no hay un país QQQ); y el rol Linesman.
   - Árbitros: 9 leídos, 8 insertados (categoría FIFA) y 1 rechazado
     ("Prueba Seis"). "Prueba Conflicto" se carga: lo que se rechaza es su
     designación.
   - Al 202 le faltan los cinco roles de la consigna.
   La importación queda registrada y las 7 filas rechazadas, en
   Arbitraje.ERRORES_DESIGNACION, con el texto que traían. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_designaciones.csv';
DECLARE @id_importacion INT;

EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI12 registro' AS caso, i.proceso, i.leidos, i.insertados, i.rechazados,
       (SELECT COUNT(*) FROM Arbitraje.ERRORES_DESIGNACION AS e WHERE e.id_importacion = i.id_importacion) AS errores_designacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MI12 designaciones' AS caso, p.numero_partido, d.rol, a.nombre, a.apellido, pa.codigo_fifa AS pais, a.categoria
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
WHERE p.numero_partido BETWEEN 201 AND 203
ORDER BY p.numero_partido, d.rol;
GO


/* MI13 (OK) Reimportación de mundial_prueba_designaciones.csv.
   Esperado: las 6 designaciones y los 8 árbitros SIN CAMBIOS, y los mismos
   7 y 1 rechazados; siguen 6 designaciones en el 201. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_designaciones.csv';

EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo;

SELECT 'MI13 después' AS caso, p.numero_partido, COUNT(*) AS designaciones
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
WHERE p.numero_partido BETWEEN 201 AND 203
GROUP BY p.numero_partido;
GO


/* ============================================================================
   ARCHIVOS QUE NO SE PUEDEN IMPORTAR Y VALIDACIONES DE PARÁMETROS
   ============================================================================ */

/* MI14 (OK) Importación con errores parciales de mundial_prueba_cuerpo_tecnico.csv
   (24_SP_Importar_Jugadores.sql, usp_ImportarCuerpoTecnicoCSV).
   Esperado: 6 leídos, 3 insertados (el director técnico de ZZA, nacido en
   Argentina; un ayudante de campo de ZZA, sin país; la directora técnica de
   ZZB) y 3 rechazados: línea 5, la selección QQQ no existe; línea 6, el rol
   UTILERO no es válido; línea 7, el país XXX no existe. Quedan en
   Torneo.ERRORES_CUERPO_TECNICO con el número de la importación. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_cuerpo_tecnico.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI14 registro' AS caso, i.leidos, i.insertados, i.rechazados,
       (SELECT COUNT(*) FROM Torneo.ERRORES_CUERPO_TECNICO AS e WHERE e.id_importacion = i.id_importacion) AS en_errores,
       IIF(i.leidos = 6 AND i.insertados = 3 AND i.rechazados = 3, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MI14 cuerpo tecnico' AS caso, p.codigo_fifa, ct.rol, ct.nombre, ct.apellido, pn.nombre AS pais_nacimiento
FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
LEFT JOIN DatosGenerales.PAIS AS pn ON pn.id_pais = ct.id_pais_nacimiento
WHERE p.codigo_fifa IN ('ZZA', 'ZZB')
ORDER BY p.codigo_fifa, ct.rol;
GO


/* MI15 (OK) Importación de mundial_prueba_cuerpo_tecnico_cambios.csv sobre lo
   cargado en MI14.
   Esperado: 3 leídos, 1 sin cambios (el director técnico de ZZA), 1
   actualizado (el ayudante de campo, ahora nacido en Uruguay) y 1 rechazado:
   otro director técnico para ZZB, que ya tiene. Siguen 3 personas en el
   cuerpo técnico de prueba. */
DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_cuerpo_tecnico_cambios.csv';
DECLARE @id_importacion INT;

EXEC Torneo.usp_ImportarCuerpoTecnicoCSV @ruta_archivo = @archivo, @id_importacion = @id_importacion OUTPUT;

SELECT 'MI15 verificacion' AS caso, i.leidos, i.insertados, i.actualizados, i.sin_cambios, i.rechazados,
       (SELECT pn.codigo_fifa FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
        INNER JOIN DatosGenerales.PAIS AS pn ON pn.id_pais = ct.id_pais_nacimiento
        WHERE ct.apellido = N'Ayudante' AND ct.nombre = N'Rubén') AS pais_ayudante,
       IIF(i.leidos = 3 AND i.insertados = 0 AND i.actualizados = 1 AND i.sin_cambios = 1 AND i.rechazados = 1
           AND (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
                INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                WHERE p.codigo_fifa IN ('ZZA', 'ZZB')) = 3, 'OK', 'FALLÓ') AS verificacion
FROM DatosGenerales.IMPORTACION AS i
WHERE i.id_importacion = @id_importacion;

SELECT 'MI15 rechazados' AS caso, registro AS linea, codigo_fifa, rol, nombre, apellido,
       REPLACE(motivos, NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM Torneo.ERRORES_CUERPO_TECNICO
WHERE id_importacion = @id_importacion
ORDER BY registro;
GO


/* MI9 (ERROR) Archivos que no se pueden importar:
     a) un archivo que no existe;
     b) mundial_prueba_invalido.json, cortado (no es JSON válido);
     c) mundial_prueba_otro_formato.json, un JSON sin la lista "matches";
     d) mundial_prueba_otro_formato.json como archivo de estadios (no tiene "stadiums");
     e) mundial_prueba_estadios.json como archivo de selecciones (no es una lista con fifa_code);
     f) mundial_prueba_columnas.csv, un CSV con otras columnas;
     g) el reproceso de MI7 numerando desde el 1 (sus eventos rechazados
        eran del partido 201);
     h) mundial_prueba_jugadores.csv como archivo del equipo arbitral (otras
        columnas).
   Esperado: ocho errores 50002, cada uno con su motivo, sin nada importado. */
DECLARE @carpeta NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400));
DECLARE @archivo NVARCHAR(400);

BEGIN TRY
    SET @archivo = @carpeta + N'no_existe.json';
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201;
    PRINT N'MI9a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9a', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_invalido.json';
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201;
    PRINT N'MI9b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9b', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_otro_formato.json';
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 201;
    PRINT N'MI9c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9c', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_otro_formato.json';
    EXEC Torneo.usp_ImportarSedesJSON @ruta_archivo = @archivo;
    PRINT N'MI9d: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9d', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_estadios.json';
    EXEC Torneo.usp_ImportarSeleccionesJSON @ruta_archivo = @archivo, @fecha_presentacion = '2026-07-01';
    PRINT N'MI9e: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9e', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_columnas.csv';
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = @archivo;
    PRINT N'MI9f: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9f', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    DECLARE @reprocesar INT = CAST(SESSION_CONTEXT(N'importacion_mi7') AS INT);
    SET @archivo = @carpeta + N'mundial_prueba_partidos.json';
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @primer_numero = 1, @reprocesar_importacion = @reprocesar;
    PRINT N'MI9g: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9g', @error_esperado = 50002;
END CATCH;

BEGIN TRY
    SET @archivo = @carpeta + N'mundial_prueba_jugadores.csv';
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = @archivo;
    PRINT N'MI9h: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI9h', @error_esperado = 50002;
END CATCH;
GO


/* MI10 (ERROR) Parámetros inválidos:
     a) ruta vacía y primer número 0;
     b) un .txt como CSV de jugadores;
     c) tarifas negativas para las sedes nuevas;
     d) reprocesar la importación de MI7 (de mundial_prueba_partidos.json)
        con otro archivo (mundial_prueba_otro_formato.json);
     e) el equipo arbitral con la categoría NACIONAL.
   Esperado: cinco errores 50001, sin leer el archivo. */
BEGIN TRY
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = N' ', @primer_numero = 0;
    PRINT N'MI10a: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI10a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = N'C:\jugadores.txt';
    PRINT N'MI10b: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI10b', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Torneo.usp_ImportarSedesJSON @ruta_archivo = N'C:\estadios.json', @tarifa_espacio_1 = -1;
    PRINT N'MI10c: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI10c', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    DECLARE @reprocesar INT = CAST(SESSION_CONTEXT(N'importacion_mi7') AS INT);
    DECLARE @archivo NVARCHAR(400) = CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial_prueba_otro_formato.json';
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = @archivo, @reprocesar_importacion = @reprocesar;
    PRINT N'MI10d: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI10d', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Arbitraje.usp_ImportarDesignacionesCSV @ruta_archivo = N'C:\designaciones.csv', @categoria = 'NACIONAL';
    PRINT N'MI10e: FALLÓ, se esperaba un error.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI10e', @error_esperado = 50001;
END CATCH;
GO


/* MI11 (ERROR) ABM de NOMBRE_ALTERNATIVO:
     a) alta de un nombre de jugador para una selección que no es la suya
        (Bruno Prueba, de ZZA, como jugador de ZZB);
     b) alta de un nombre de selección que ya tiene otra ("Testland A" para ZZB);
     c) modificación a un nombre vacío.
   Esperado: tres errores 50001. */
DECLARE @zzb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'ZZB');
DECLARE @bruno INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j
                      INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
                      INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
                      INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                      WHERE p.codigo_fifa = 'ZZA' AND j.nombre = N'Bruno');
DECLARE @id INT = (SELECT TOP (1) id_nombre_alternativo FROM Torneo.NOMBRE_ALTERNATIVO WHERE nombre = N'DANILO');

BEGIN TRY
    EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Alta @id_seleccion = @zzb, @nombre = N'B. PRUEBA', @id_jugador = @bruno;
    PRINT N'MI11a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI11a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Alta @id_seleccion = @zzb, @nombre = N'Testland A';
    PRINT N'MI11b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI11b', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC Torneo.usp_NOMBRE_ALTERNATIVO_Modificacion @id_nombre_alternativo = @id, @nombre = N' ';
    PRINT N'MI11c: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'MI11c', @error_esperado = 50001;
END CATCH;
GO


-- Se borra todo lo que cargó el test.
EXEC #usp_LimpiarPruebas;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 211) AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba%') AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('ZZA', 'ZZB', 'ZZC')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido IN (N'Prueba', N'Ayudante', N'Técnica')) AS cuerpo_tecnico_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO WHERE apellido LIKE N'Prueba %' AND nombre LIKE N'Árbitro%') AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Torneo.NOMBRE_ALTERNATIVO
        WHERE nombre IN (N'Testland A', N'Testland B', N'Diego GOMEZ')) AS nombres_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION
        WHERE origen LIKE CAST(SESSION_CONTEXT(N'carpeta_pruebas') AS NVARCHAR(400)) + N'mundial[_]prueba%') AS importaciones_de_prueba;
GO

SET NOEXEC OFF;
GO
