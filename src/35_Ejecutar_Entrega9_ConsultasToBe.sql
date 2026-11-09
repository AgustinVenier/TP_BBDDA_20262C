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
 Archivo: 35_Ejecutar_Entrega9_ConsultasToBe.sql
 Objetivo: Entrega 9. Recorrer los puntos del alcance (sección 2, "To Be") con
           las consultas que muestran que el sistema los cumple, sobre el
           torneo real cargado. Usa las vistas y funciones de
           03_CrearFuncionesYVistas.sql y 30_SP_Reportes.sql; los reportes
           de la Entrega 7 se ven en 34_Ejecutar_Entrega7_Reportes.sql.
           Requiere haber ejecutado 00 a 33: el torneo real
           (31_Ejecutar_ImportarMundial2026.sql) con sus datos complementarios
           (32_Ejecutar_DatosComplementarios.sql) y las sedes propias del juego de
           datos (33_Ejecutar_SedesAdicionales.sql), y el cifrado de la
           Entrega 8 (38_Ejecutar_Cifrado.sql): los jugadores, cuerpos
           técnicos y árbitros se leen de las vistas descifradas de
           Seguridad (vw_Jugador, vw_PersonaCuerpoTecnico, vw_Arbitro).
================================================================================

 Cómo leer los resultados:
   - Cada consulta empieza con una grilla de una fila con su título (A1, B2,
     ...), que es el punto del alcance que cubre. Las grillas que siguen son
     la consulta.
   - Los parámetros no tienen valores fijos: se eligen de los datos cargados
     (el campeón, la final, el partido con más mercados en prime time), así
     que el script sirve con cualquier juego de datos.
   - Las consultas de control ("debe dar 0") verifican sobre todos los datos
     una regla que los SP hacen cumplir al registrar.
   - Solo lee, salvo G4 y G5: para mostrar el rechazo por nacionalidad y la
     advertencia de cruce hace falta un partido PROGRAMADO, así que dan de
     alta uno ficticio dentro de una transacción que se deshace. No queda
     nada (solo se consume un valor del IDENTITY de PARTIDO).

 Puntos del alcance:
   A. Gestión de sedes y partidos        F. Amonestaciones y expulsiones
   B. Selecciones y convocatoria         G. Gestión de árbitros
   C. Formaciones y alineaciones         H. Gestión de publicidad
   D. Cambios (sustituciones)            I. Importación de datos externos
   E. Goles y eventos de partido
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Reportes.vw_Plantillas', N'V') IS NULL
   OR NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE estado = 'FINALIZADO')
BEGIN
    RAISERROR(N'Faltan los objetos o los datos: ejecutar 00 a 33.', 16, 1);
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   A. Gestión de sedes y partidos
   ============================================================================ */

-- utc_al_inicio es la diferencia con UTC del huso de la sede el día del primer partido
-- (con el horario de verano que corresponda).
SELECT N'A1. Sedes: estadio, ciudad, país, capacidad y huso horario' AS consulta;
SELECT s.nombre_estadio, s.ciudad, s.pais, s.capacidad, s.huso_horario,
       DATENAME(TZOFFSET, i.inicio AT TIME ZONE s.huso_horario) AS utc_al_inicio,
       s.partidos
FROM Reportes.vw_Sedes AS s
CROSS JOIN (SELECT MIN(fecha_hora_utc) AS inicio FROM Torneo.PARTIDO) AS i
ORDER BY s.pais, s.ciudad;

SELECT COUNT(*) AS sedes, COUNT(DISTINCT huso_horario) AS husos_horarios_distintos
FROM Torneo.SEDE;
GO

SELECT N'A2. Fixture completo: horario local y UTC, fase, sede, selecciones, resultado y asistencia' AS consulta;
SELECT numero_partido, fase, grupo, fecha_hora_local, fecha_hora_utc, nombre_estadio, ciudad, pais_sede,
       seleccion_local, seleccion_visitante, resultado, asistencia, estado
FROM Torneo.fn_Fixture(NULL, NULL, NULL, NULL)
ORDER BY fecha_hora_utc;
GO

-- La sede con más partidos, el campeón (ganador del último partido) y el día con más partidos.
DECLARE @id_sede INT = (SELECT TOP (1) id_sede
                        FROM Torneo.PARTIDO
                        GROUP BY id_sede
                        ORDER BY COUNT(*) DESC, id_sede);
DECLARE @id_seleccion INT = (SELECT TOP (1) IIF(goles_local > goles_visitante OR penales_local > penales_visitante,
                                                id_seleccion_local, id_seleccion_visitante)
                             FROM Torneo.PARTIDO
                             WHERE estado = 'FINALIZADO'
                             ORDER BY fecha_hora_utc DESC);
DECLARE @fecha DATE = (SELECT TOP (1) CAST(fecha_hora_local AS DATE)
                       FROM Torneo.PARTIDO
                       GROUP BY CAST(fecha_hora_local AS DATE)
                       ORDER BY COUNT(*) DESC, CAST(fecha_hora_local AS DATE));

SELECT CONCAT(N'A3. Fixture filtrado por sede: ', nombre_estadio, N' (', ciudad, N')') AS consulta
FROM Torneo.SEDE WHERE id_sede = @id_sede;
SELECT numero_partido, fase, fecha_hora_local, seleccion_local, seleccion_visitante, resultado, asistencia
FROM Torneo.fn_Fixture(@id_sede, NULL, NULL, NULL)
ORDER BY fecha_hora_utc;

SELECT N'A3. Fixture filtrado por fase: CUARTOS' AS consulta;
SELECT numero_partido, fecha_hora_local, nombre_estadio, seleccion_local, seleccion_visitante, resultado
FROM Torneo.fn_Fixture(NULL, 'CUARTOS', NULL, NULL)
ORDER BY fecha_hora_utc;

SELECT CONCAT(N'A3. Fixture filtrado por selección: ', pa.nombre, N' (el campeón)') AS consulta
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE s.id_seleccion = @id_seleccion;
SELECT numero_partido, fase, fecha_hora_local, nombre_estadio, seleccion_local, seleccion_visitante, resultado
FROM Torneo.fn_Fixture(NULL, NULL, @id_seleccion, NULL)
ORDER BY fecha_hora_utc;

SELECT CONCAT(N'A3. Fixture filtrado por fecha (local): ', CONVERT(VARCHAR(10), @fecha, 103)) AS consulta;
SELECT numero_partido, fase, grupo, fecha_hora_local, nombre_estadio, seleccion_local, seleccion_visitante, resultado
FROM Torneo.fn_Fixture(NULL, NULL, NULL, @fecha)
ORDER BY fecha_hora_utc;

SELECT N'A3. Filtros combinados: fase de grupos del campeón' AS consulta;
SELECT numero_partido, grupo, fecha_hora_local, seleccion_local, seleccion_visitante, resultado
FROM Torneo.fn_Fixture(NULL, 'GRUPOS', @id_seleccion, NULL)
ORDER BY fecha_hora_utc;
GO

-- La segunda corrida de los partidos es el reproceso de los rechazados (ver 31): lo que ya
-- estaba cargado queda sin cambios, no se duplica.
SELECT N'A4. Importación del fixture, las sedes y los resultados oficiales (openfootball)' AS consulta;
SELECT id_importacion, proceso, origen, fecha_hora, leidos, insertados, actualizados, sin_cambios, omitidos, rechazados
FROM DatosGenerales.IMPORTACION
WHERE proceso IN ('Torneo.usp_ImportarSedesJSON', 'Torneo.usp_ImportarSeleccionesJSON', 'Torneo.usp_ImportarPartidosJSON')
ORDER BY id_importacion;
GO


/* ============================================================================
   B. Selecciones y convocatoria
   ============================================================================ */

SELECT N'B1. Selecciones: país, confederación, grupo y cuerpo técnico' AS consulta;
SELECT pa.nombre AS seleccion, pa.codigo_fifa, s.confederacion, s.grupo,
       dt.director_tecnico, ct.ayudantes
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
OUTER APPLY (SELECT CONCAT(p.nombre, N' ', p.apellido) AS director_tecnico
             FROM Seguridad.vw_PersonaCuerpoTecnico AS p
             WHERE p.id_seleccion = s.id_seleccion AND p.rol = 'DIRECTOR_TECNICO') AS dt
OUTER APPLY (SELECT STRING_AGG(CONCAT(p.nombre, N' ', p.apellido, N' (', LOWER(REPLACE(p.rol, '_', ' ')), N')'), N'; ')
                        WITHIN GROUP (ORDER BY p.rol, p.apellido) AS ayudantes
             FROM Seguridad.vw_PersonaCuerpoTecnico AS p
             WHERE p.id_seleccion = s.id_seleccion AND p.rol <> 'DIRECTOR_TECNICO') AS ct
ORDER BY s.grupo, pa.nombre;
GO

-- Mínimo y máximo de convocados y mínimo de arqueros según PARAMETRO_REGLAMENTO.
SELECT N'B2. Convocados de cada selección contra el reglamento vigente' AS consulta;
WITH reglamento AS (
    SELECT MAX(IIF(codigo = 'MIN_CONVOCADOS', valor, NULL))          AS minimo,
           MAX(IIF(codigo = 'MAX_CONVOCADOS', valor, NULL))          AS maximo,
           MAX(IIF(codigo = 'MIN_ARQUEROS_CONVOCADOS', valor, NULL)) AS min_arqueros
    FROM DatosGenerales.PARAMETRO_REGLAMENTO
),
plantillas AS (
    SELECT seleccion,
           SUM(IIF(activo = 1, 1, 0))                                  AS convocados,
           SUM(IIF(activo = 1 AND posicion_habitual = 'ARQUERO', 1, 0)) AS arqueros,
           SUM(IIF(activo = 0, 1, 0))                                  AS bajas
    FROM Reportes.vw_Plantillas
    GROUP BY seleccion
)
SELECT p.seleccion, p.convocados, p.arqueros, p.bajas, r.minimo, r.maximo, r.min_arqueros,
       IIF(p.convocados BETWEEN r.minimo AND r.maximo AND p.arqueros >= r.min_arqueros, N'CUMPLE', N'NO CUMPLE') AS reglamento
FROM plantillas AS p
CROSS JOIN reglamento AS r
ORDER BY p.seleccion;
GO

DECLARE @id_seleccion INT = (SELECT TOP (1) IIF(goles_local > goles_visitante OR penales_local > penales_visitante,
                                                id_seleccion_local, id_seleccion_visitante)
                             FROM Torneo.PARTIDO
                             WHERE estado = 'FINALIZADO'
                             ORDER BY fecha_hora_utc DESC);

SELECT CONCAT(N'B3. Lista de convocados de ', pa.nombre, N': datos personales, club, posición y dorsal') AS consulta
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE s.id_seleccion = @id_seleccion;
-- La fecha de nacimiento no está en Reportes.vw_Plantillas (la leen roles que no la
-- necesitan): se lee de Seguridad.vw_Jugador.
SELECT p.dorsal, p.apellido, p.nombre, j.fecha_nacimiento, p.posicion_habitual, p.club_origen,
       IIF(p.activo = 1, N'ACTIVO', N'BAJA') AS situacion
FROM Reportes.vw_Plantillas AS p
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = p.id_jugador
WHERE p.id_seleccion = @id_seleccion
ORDER BY CHARINDEX(LEFT(p.posicion_habitual, 3), 'ARQ DEF MED DEL'), p.dorsal;
GO

-- El reemplazante hereda el dorsal salvo que se informe otro (usp_ReemplazarJugador): se
-- busca primero el del mismo dorsal dado de alta desde la baja.
SELECT N'B4. Altas y bajas de último momento: motivo y fecha de cada cambio en la convocatoria' AS consulta;
SELECT pa.nombre AS seleccion,
       b.dorsal,
       CONCAT(b.nombre, N' ', b.apellido) AS jugador_baja,
       b.fecha_baja,
       b.motivo_baja,
       CONCAT(r.nombre, N' ', r.apellido) AS jugador_alta,
       r.fecha_alta,
       r.motivo_alta,
       r.posicion_habitual
FROM Seguridad.vw_Jugador AS b
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = b.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
OUTER APPLY (SELECT TOP (1) j.nombre, j.apellido, j.fecha_alta, j.motivo_alta, j.posicion_habitual
             FROM Seguridad.vw_Jugador AS j
             WHERE j.id_lista = b.id_lista
               AND j.fecha_baja IS NULL
               AND j.fecha_alta >= b.fecha_baja
             ORDER BY IIF(j.dorsal = b.dorsal, 0, 1), j.fecha_alta) AS r
WHERE b.fecha_baja IS NOT NULL
ORDER BY b.fecha_baja, pa.nombre;
GO


/* ============================================================================
   C. Formaciones y alineaciones
   ============================================================================ */

-- El último partido jugado (la final).
DECLARE @id_partido INT = (SELECT TOP (1) id_partido
                           FROM Torneo.PARTIDO
                           WHERE estado = 'FINALIZADO'
                           ORDER BY fecha_hora_utc DESC);

SELECT CONCAT(N'C1. Formación titular del partido ', numero_partido, N' (', fase, N'): ',
              seleccion_local, N' vs ', seleccion_visitante) AS consulta
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
SELECT pa.nombre AS seleccion, f.esquema_tactico, j.dorsal, CONCAT(j.nombre, N' ', j.apellido) AS jugador,
       a.posicion_en_cancha
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE f.id_partido = @id_partido AND a.es_titular = 1
ORDER BY pa.nombre, CHARINDEX(LEFT(j.posicion_habitual, 3), 'ARQ DEF MED DEL'), j.dorsal;

SELECT N'C2. Banco de suplentes del mismo partido' AS consulta;
SELECT pa.nombre AS seleccion, j.dorsal, CONCAT(j.nombre, N' ', j.apellido) AS jugador, j.posicion_habitual
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE f.id_partido = @id_partido AND a.es_titular = 0
ORDER BY pa.nombre, CHARINDEX(LEFT(j.posicion_habitual, 3), 'ARQ DEF MED DEL'), j.dorsal;

-- Control: partidos jugados sin las dos formaciones (11 titulares cada una) o sin banco. Debe dar 0.
SELECT COUNT(*) AS partidos_sin_formacion_completa
FROM Torneo.PARTIDO AS p
WHERE p.estado = 'FINALIZADO'
  AND (SELECT COUNT(*)
       FROM DesarrolloPartido.FORMACION AS f
       WHERE f.id_partido = p.id_partido
         AND (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION AS a
              WHERE a.id_formacion = f.id_formacion AND a.es_titular = 1) = 11
         AND EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                     WHERE a.id_formacion = f.id_formacion AND a.es_titular = 0)) < 2;
GO

-- El máximo goleador del torneo.
DECLARE @id_jugador INT = (SELECT TOP (1) id_jugador
                           FROM DesarrolloPartido.vw_Goleadores
                           ORDER BY goles DESC, id_jugador);

SELECT CONCAT(N'C3. Historial de titularidad de ', nombre, N' ', apellido, N' (el máximo goleador)') AS consulta
FROM Seguridad.vw_Jugador WHERE id_jugador = @id_jugador;
SELECT numero_partido, fase, fecha_hora_local, rival, condicion, posicion_en_cancha,
       IIF(jugo = 1, N'SÍ', N'NO') AS jugo, minuto_ingreso, minuto_salida, minuto_expulsion
FROM DesarrolloPartido.vw_HistorialTitularidad
WHERE id_jugador = @id_jugador
ORDER BY fecha_hora_local;
GO

DECLARE @id_seleccion INT = (SELECT TOP (1) IIF(goles_local > goles_visitante OR penales_local > penales_visitante,
                                                id_seleccion_local, id_seleccion_visitante)
                             FROM Torneo.PARTIDO
                             WHERE estado = 'FINALIZADO'
                             ORDER BY fecha_hora_utc DESC);

SELECT CONCAT(N'C3. Resumen de titularidad de los jugadores de ', pa.nombre) AS consulta
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE s.id_seleccion = @id_seleccion;
SELECT h.dorsal, h.apellido, h.nombre,
       SUM(IIF(h.condicion = 'TITULAR', 1, 0))                AS partidos_titular,
       SUM(IIF(h.condicion = 'SUPLENTE' AND h.jugo = 1, 1, 0)) AS ingresos_desde_el_banco,
       SUM(IIF(h.jugo = 0, 1, 0))                             AS partidos_sin_jugar,
       COUNT(*)                                               AS partidos_en_la_formacion
FROM DesarrolloPartido.vw_HistorialTitularidad AS h
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = h.id_jugador
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE l.id_seleccion = @id_seleccion
GROUP BY h.id_jugador, h.dorsal, h.apellido, h.nombre
ORDER BY partidos_titular DESC, ingresos_desde_el_banco DESC, h.dorsal;
GO


/* ============================================================================
   D. Cambios (sustituciones)
   ============================================================================ */

-- El partido del cambio por lesión más temprano.
DECLARE @id_partido INT = (SELECT TOP (1) id_partido
                           FROM DesarrolloPartido.CAMBIO
                           WHERE motivo = 'LESION' AND en_entretiempo = 0
                           ORDER BY minuto, minuto_adicional, id_cambio);

SELECT CONCAT(N'D1. Cambios del partido ', numero_partido, N': ', seleccion_local, N' vs ', seleccion_visitante,
              N' (tiene el cambio por lesión más temprano)') AS consulta
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
SELECT pa.nombre AS seleccion,
       CONCAT(c.minuto, IIF(c.minuto_adicional > 0, CONCAT(N'+', c.minuto_adicional), N'')) AS minuto,
       IIF(c.en_entretiempo = 1, N'SÍ', N'NO')                                            AS en_entretiempo,
       CONCAT(js.dorsal, N'. ', js.nombre, N' ', js.apellido)                              AS sale,
       CONCAT(je.dorsal, N'. ', je.nombre, N' ', je.apellido)                              AS entra,
       c.motivo
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Seguridad.vw_Jugador AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Seguridad.vw_Jugador AS je ON je.id_jugador = c.id_jugador_entra
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = js.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE c.id_partido = @id_partido
ORDER BY pa.nombre, c.minuto, c.minuto_adicional;

SELECT N'D1. Cambios por lesión en los primeros 20 minutos (caso obligatorio)' AS consulta;
SELECT f.numero_partido, CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante) AS partido,
       c.minuto, CONCAT(js.nombre, N' ', js.apellido) AS sale, CONCAT(je.nombre, N' ', je.apellido) AS entra, c.motivo
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = c.id_partido
INNER JOIN Seguridad.vw_Jugador AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Seguridad.vw_Jugador AS je ON je.id_jugador = c.id_jugador_entra
WHERE c.motivo = 'LESION' AND c.minuto <= 20
ORDER BY c.minuto, f.numero_partido;
GO

-- Cada momento distinto con cambios es una ventana, salvo los entretiempos. Con alargue (partido
-- de eliminación empatado al terminar los 90) se suman CAMBIOS_EXTRA_ALARGUE y VENTANAS_EXTRA_ALARGUE.
SELECT N'D2. Cambios y ventanas usados por selección y partido, contra el máximo del reglamento' AS consulta;
WITH reglamento AS (
    SELECT MAX(IIF(codigo = 'MAX_CAMBIOS', valor, NULL))            AS max_cambios,
           MAX(IIF(codigo = 'MAX_VENTANAS', valor, NULL))           AS max_ventanas,
           MAX(IIF(codigo = 'CAMBIOS_EXTRA_ALARGUE', valor, NULL))  AS cambios_extra,
           MAX(IIF(codigo = 'VENTANAS_EXTRA_ALARGUE', valor, NULL)) AS ventanas_extra
    FROM DatosGenerales.PARAMETRO_REGLAMENTO
),
uso AS (
    SELECT c.id_partido,
           l.id_seleccion,
           COUNT(*)                                                                         AS cambios,
           COUNT(DISTINCT IIF(c.en_entretiempo = 0, c.minuto * 100 + c.minuto_adicional, NULL)) AS ventanas,
           SUM(IIF(c.en_entretiempo = 1, 1, 0))                                             AS en_entretiempo
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = c.id_jugador_sale
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    GROUP BY c.id_partido, l.id_seleccion
),
control AS (
    SELECT f.numero_partido, f.fase, pa.nombre AS seleccion, u.cambios, u.ventanas, u.en_entretiempo,
           IIF(f.fase <> 'GRUPOS' AND m.goles_local_90 = m.goles_visitante_90, 1, 0) AS alargue,
           r.max_cambios + IIF(f.fase <> 'GRUPOS' AND m.goles_local_90 = m.goles_visitante_90, r.cambios_extra, 0)   AS max_cambios,
           r.max_ventanas + IIF(f.fase <> 'GRUPOS' AND m.goles_local_90 = m.goles_visitante_90, r.ventanas_extra, 0) AS max_ventanas
    FROM uso AS u
    INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = u.id_partido
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = u.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(u.id_partido) AS m
    CROSS JOIN reglamento AS r
)
SELECT TOP (10) numero_partido, fase, seleccion, IIF(alargue = 1, N'SÍ', N'NO') AS alargue,
       cambios, max_cambios, ventanas, max_ventanas, en_entretiempo AS cambios_en_entretiempo,
       IIF(cambios <= max_cambios AND ventanas <= max_ventanas, N'CUMPLE', N'NO CUMPLE') AS reglamento
FROM control
ORDER BY IIF(cambios <= max_cambios AND ventanas <= max_ventanas, 1, 0), alargue DESC, cambios DESC, ventanas DESC;
GO

-- Selecciones que superaron los cambios o las ventanas en todo el torneo. Al registrar un
-- cambio, usp_RegistrarCambio lo impide (ver 62_Test_SP_Negocio_FormacionesYCambios.sql), pero
-- el torneo real se importó como carga histórica, que no repite las reglas del partido en vivo
-- (usp_ImportarDesarrolloPartidos, en 16): los que aparecen son cambios del partido real que el
-- reglamento cargado no contempla. Son las filas NO CUMPLE de la grilla anterior.
WITH uso AS (
    SELECT c.id_partido, l.id_seleccion, COUNT(*) AS cambios,
           COUNT(DISTINCT IIF(c.en_entretiempo = 0, c.minuto * 100 + c.minuto_adicional, NULL)) AS ventanas
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = c.id_jugador_sale
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    GROUP BY c.id_partido, l.id_seleccion
)
SELECT COUNT(*) AS selecciones_fuera_de_reglamento
FROM uso AS u
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = u.id_partido
CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(u.id_partido) AS m
CROSS APPLY (SELECT IIF(p.fase <> 'GRUPOS' AND m.goles_local_90 = m.goles_visitante_90, 1, 0) AS alargue) AS a
WHERE u.cambios  > (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CAMBIOS')
                 + a.alargue * (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'CAMBIOS_EXTRA_ALARGUE')
   OR u.ventanas > (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_VENTANAS')
                 + a.alargue * (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'VENTANAS_EXTRA_ALARGUE');
GO

-- El mismo cambio por lesión de D1: el equipo un minuto antes y en el minuto del cambio.
DECLARE @id_partido   INT;
DECLARE @id_seleccion INT;
DECLARE @minuto       TINYINT;
SELECT TOP (1) @id_partido = c.id_partido, @id_seleccion = l.id_seleccion, @minuto = c.minuto
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE c.motivo = 'LESION' AND c.en_entretiempo = 0
ORDER BY c.minuto, c.minuto_adicional, c.id_cambio;

SELECT CONCAT(N'D3. Equipo en cancha de ', pa.nombre, N' en el minuto ', @minuto - 1, N' y en el minuto ', @minuto,
              N' (el cambio por lesión)') AS consulta
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE s.id_seleccion = @id_seleccion;
SELECT dorsal, apellido, nombre, IIF(es_titular = 1, N'TITULAR', N'SUPLENTE') AS condicion, posicion_en_cancha
FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, @minuto - 1, 0)
ORDER BY dorsal;
SELECT dorsal, apellido, nombre, IIF(es_titular = 1, N'TITULAR', N'SUPLENTE') AS condicion, posicion_en_cancha,
       minuto_ingreso
FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, @minuto, 0)
ORDER BY dorsal;
GO

-- Al final del partido (minuto 120, adicional 99) el expulsado ya no está: quedan 10.
DECLARE @id_partido   INT;
DECLARE @id_seleccion INT;
SELECT TOP (1) @id_partido = a.id_partido, @id_seleccion = l.id_seleccion
FROM DesarrolloPartido.AMONESTACION AS a
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE a.tipo_tarjeta = 'ROJA'
ORDER BY a.id_partido;

SELECT CONCAT(N'D3. Equipo en cancha de ', pa.nombre, N' al final del partido ', p.numero_partido,
              N', en el que tuvo un expulsado') AS consulta
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
CROSS JOIN Torneo.PARTIDO AS p
WHERE s.id_seleccion = @id_seleccion AND p.id_partido = @id_partido;
SELECT dorsal, apellido, nombre, IIF(es_titular = 1, N'TITULAR', N'SUPLENTE') AS condicion, posicion_en_cancha,
       minuto_ingreso, COUNT(*) OVER () AS jugadores_en_cancha
FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 120, 99)
ORDER BY dorsal;
GO


/* ============================================================================
   E. Goles y eventos de partido
   ============================================================================ */

DECLARE @id_partido INT = (SELECT TOP (1) id_partido
                           FROM Torneo.PARTIDO
                           WHERE estado = 'FINALIZADO'
                           ORDER BY fecha_hora_utc DESC);

SELECT CONCAT(N'E1. Goles del partido ', numero_partido, N' (', fase, N'): ', seleccion_local, N' vs ',
              seleccion_visitante, N' ', resultado) AS consulta
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
SELECT g.periodo,
       CONCAT(g.minuto, IIF(g.minuto_adicional > 0, CONCAT(N'+', g.minuto_adicional), N'')) AS minuto,
       pa.nombre                                                                         AS seleccion_del_autor,
       CONCAT(ja.nombre, N' ', ja.apellido)                                              AS autor,
       tg.descripcion                                                                    AS tipo,
       IIF(tg.es_en_contra = 1, N'SÍ', N'NO')                                            AS en_contra,
       CONCAT(js.nombre, N' ', js.apellido)                                              AS asistencia
FROM DesarrolloPartido.GOL AS g
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
INNER JOIN Seguridad.vw_Jugador AS ja ON ja.id_jugador = g.id_jugador_autor
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = ja.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
LEFT JOIN Seguridad.vw_Jugador AS js ON js.id_jugador = g.id_jugador_asistencia
WHERE g.id_partido = @id_partido
ORDER BY IIF(g.periodo = 'PENALES', 1, 0), g.minuto, g.minuto_adicional, g.id_gol;
GO

SELECT N'E2. Tabla de goleadores del torneo (sin goles en contra ni penales de la definición)' AS consulta;
SELECT TOP (10) WITH TIES
       RANK() OVER (ORDER BY goles DESC) AS posicion, apellido, nombre, seleccion, goles, partidos_con_gol
FROM DesarrolloPartido.vw_Goleadores
ORDER BY goles DESC;

SELECT N'E2. Goleadores por selección: el máximo goleador de cada una' AS consulta;
SELECT seleccion, apellido, nombre, goles, goles_seleccion
FROM (SELECT seleccion, apellido, nombre, goles,
             RANK() OVER (PARTITION BY id_seleccion ORDER BY goles DESC) AS posicion,
             SUM(goles) OVER (PARTITION BY id_seleccion)                AS goles_seleccion
      FROM DesarrolloPartido.vw_Goleadores) AS g
WHERE posicion = 1
ORDER BY goles DESC, seleccion, apellido;
GO

SELECT N'E3. Goles por tipo y período' AS consulta;
SELECT tg.descripcion AS tipo,
       SUM(IIF(g.periodo = 'PRIMER_TIEMPO', 1, 0))  AS primer_tiempo,
       SUM(IIF(g.periodo = 'SEGUNDO_TIEMPO', 1, 0)) AS segundo_tiempo,
       SUM(IIF(g.periodo = 'ADICIONALES', 1, 0))    AS adicionales,
       SUM(IIF(g.periodo = 'ALARGUE', 1, 0))        AS alargue,
       SUM(IIF(g.periodo = 'PENALES', 1, 0))        AS definicion_por_penales,
       COUNT(*)                                     AS total
FROM DesarrolloPartido.GOL AS g
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
GROUP BY tg.descripcion
ORDER BY total DESC;
GO


/* ============================================================================
   F. Amonestaciones y expulsiones
   ============================================================================ */

SELECT N'F1. Criterios de suspensión parametrizables (PARAMETRO_REGLAMENTO)' AS consulta;
SELECT codigo, descripcion, valor, fecha_modificacion
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo LIKE '%SUSPENSION%' OR codigo LIKE 'LIMPIEZA[_]AMARILLAS%'
ORDER BY codigo;
GO

SELECT N'F2. Expulsiones: por doble amarilla o roja directa (caso obligatorio)' AS consulta;
SELECT f.numero_partido, CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante) AS partido,
       CONCAT(a.minuto, IIF(a.minuto_adicional > 0, CONCAT(N'+', a.minuto_adicional), N'')) AS minuto,
       pa.nombre AS seleccion,
       COALESCE(CONCAT(j.nombre, N' ', j.apellido), CONCAT(ct.nombre, N' ', ct.apellido, N' (cuerpo técnico)')) AS expulsado,
       IIF(a.es_doble_amarilla = 1, N'DOBLE AMARILLA', N'ROJA DIRECTA') AS tipo_expulsion,
       a.motivo
FROM DesarrolloPartido.AMONESTACION AS a
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = a.id_partido
LEFT JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
LEFT JOIN Seguridad.vw_PersonaCuerpoTecnico AS ct ON ct.id_persona_ct = a.id_persona_ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = COALESCE(l.id_seleccion, ct.id_seleccion)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE a.tipo_tarjeta = 'ROJA'
ORDER BY f.fecha_hora_utc, a.minuto;
GO

-- El primer partido con una expulsión por doble amarilla: se ven las dos amarillas y la roja.
DECLARE @id_partido INT = (SELECT TOP (1) a.id_partido
                           FROM DesarrolloPartido.AMONESTACION AS a
                           INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                           WHERE a.es_doble_amarilla = 1
                           ORDER BY p.fecha_hora_utc);

SELECT CONCAT(N'F3. Tarjetas del partido ', numero_partido, N': ', seleccion_local, N' vs ', seleccion_visitante) AS consulta
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
SELECT CONCAT(a.minuto, IIF(a.minuto_adicional > 0, CONCAT(N'+', a.minuto_adicional), N'')) AS minuto,
       pa.nombre AS seleccion,
       COALESCE(CONCAT(j.dorsal, N'. ', j.nombre, N' ', j.apellido), CONCAT(ct.nombre, N' ', ct.apellido, N' (cuerpo técnico)')) AS amonestado,
       a.tipo_tarjeta,
       IIF(a.tipo_tarjeta = 'ROJA', IIF(a.es_doble_amarilla = 1, N'DOBLE AMARILLA', N'ROJA DIRECTA'), NULL) AS tipo_expulsion,
       a.motivo
FROM DesarrolloPartido.AMONESTACION AS a
LEFT JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
LEFT JOIN Seguridad.vw_PersonaCuerpoTecnico AS ct ON ct.id_persona_ct = a.id_persona_ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = COALESCE(l.id_seleccion, ct.id_seleccion)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE a.id_partido = @id_partido
ORDER BY a.minuto, a.minuto_adicional, a.id_amonestacion;
GO

-- Cada sanción (fn_Sanciones) con el partido de su selección en que la cumple
-- (fn_JugadoresSuspendidos). figura_en_la_formacion es NO: la formación de un suspendido la
-- rechaza usp_RegistrarFormacion. La excepción es Balogun (Estados Unidos): la FIFA dejó sin
-- efecto su suspensión y el partido se importó tal como se jugó, como carga histórica que no
-- controla suspensiones (ver 16 y 32).
SELECT N'F4. Suspensiones calculadas y el partido en que se cumplen (incluye la acumulación de amarillas)' AS consulta;
SELECT pa.nombre AS seleccion,
       CONCAT(j.nombre, N' ', j.apellido) AS jugador,
       su.motivo,
       su.numero_partido_origen,
       x.numero_partido AS partido_que_no_juega,
       CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante) AS partido,
       CONCAT(su.partido_que_cumple, N' de ', su.partidos_de_suspension) AS fecha_de_la_suspension,
       IIF(EXISTS (SELECT 1
                   FROM DesarrolloPartido.FORMACION AS fo
                   INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = fo.id_formacion
                   WHERE fo.id_partido = x.id_partido AND a.id_jugador = su.id_jugador), N'SÍ', N'NO') AS figura_en_la_formacion
FROM Torneo.PARTIDO AS x
CROSS APPLY DesarrolloPartido.fn_JugadoresSuspendidos(x.id_partido) AS su
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = x.id_partido
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = su.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = su.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
ORDER BY x.fecha_hora_utc, pa.nombre, j.apellido;

-- Sanciones que no llegaron a cumplirse: la selección no volvió a jugar.
SELECT N'F4. Sanciones sin partido para cumplirlas (la selección quedó eliminada)' AS consulta;
SELECT pa.nombre AS seleccion, CONCAT(j.nombre, N' ', j.apellido) AS jugador, sa.motivo,
       o.numero_partido AS numero_partido_origen, sa.partidos_de_suspension
FROM DesarrolloPartido.fn_Sanciones() AS sa
INNER JOIN Torneo.PARTIDO AS o ON o.id_partido = sa.id_partido_origen
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = sa.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = sa.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE NOT EXISTS (SELECT 1
                  FROM Torneo.PARTIDO AS q
                  WHERE sa.id_seleccion IN (q.id_seleccion_local, q.id_seleccion_visitante)
                    AND q.fecha_hora_utc > o.fecha_hora_utc)
ORDER BY o.fecha_hora_utc, pa.nombre;
GO


/* ============================================================================
   G. Gestión de árbitros
   ============================================================================ */

SELECT N'G1. Árbitros habilitados: datos personales, país, categoría e idiomas' AS consulta;
SELECT a.apellido, a.nombre, a.fecha_nacimiento, pa.nombre AS pais, a.categoria,
       IIF(a.activo = 1, N'SÍ', N'NO') AS activo, i.idiomas, d.partidos_designado
FROM Seguridad.vw_Arbitro AS a
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
OUTER APPLY (SELECT STRING_AGG(id.nombre, ', ') WITHIN GROUP (ORDER BY id.nombre) AS idiomas
             FROM Arbitraje.ARBITRO_IDIOMA AS ai
             INNER JOIN DatosGenerales.IDIOMA AS id ON id.id_idioma = ai.id_idioma
             WHERE ai.id_arbitro = a.id_arbitro) AS i
OUTER APPLY (SELECT COUNT(*) AS partidos_designado
             FROM Arbitraje.DESIGNACION_ARBITRAL AS dd
             WHERE dd.id_arbitro = a.id_arbitro) AS d
ORDER BY pa.nombre, a.apellido, a.nombre;
GO

DECLARE @id_partido INT = (SELECT TOP (1) id_partido
                           FROM Torneo.PARTIDO
                           WHERE estado = 'FINALIZADO'
                           ORDER BY fecha_hora_utc DESC);

SELECT CONCAT(N'G2. Designación arbitral del partido ', numero_partido, N' (', fase, N'): ',
              seleccion_local, N' vs ', seleccion_visitante) AS consulta
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
SELECT d.rol, CONCAT(a.nombre, N' ', a.apellido) AS arbitro, pa.nombre AS pais, a.categoria, d.fecha_designacion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
INNER JOIN (VALUES ('PRINCIPAL', 1), ('ASISTENTE_1', 2), ('ASISTENTE_2', 3), ('CUARTO', 4), ('VAR', 5),
                   ('AVAR', 6), ('VAR_APOYO', 7), ('ASISTENTE_RESERVA', 8)) AS r (rol, orden) ON r.rol = d.rol
WHERE d.id_partido = @id_partido
ORDER BY r.orden;
GO

-- Controles sobre todos los partidos. Los dos deben dar 0.
SELECT N'G3. Controles: terna completa en cada partido y ningún árbitro del país de una selección del partido' AS consulta;
SELECT (SELECT COUNT(*)
        FROM Torneo.PARTIDO AS p
        WHERE p.estado = 'FINALIZADO'
          AND (SELECT COUNT(*)
               FROM Arbitraje.DESIGNACION_ARBITRAL AS d
               WHERE d.id_partido = p.id_partido
                 AND d.rol IN ('PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR')) < 5) AS partidos_sin_designacion_completa,
       (SELECT COUNT(*)
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = d.id_arbitro
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
        WHERE s.id_pais = a.id_pais) AS designaciones_con_conflicto_de_nacionalidad;
GO


/*
  G4 y G5 necesitan un partido PROGRAMADO sin árbitros, y el torneo cargado ya
  se jugó entero. Dan de alta un partido de octavos ficticio, 30 días después
  del último, entre dos selecciones que ya no siguen en competencia, y lo
  deshacen al terminar. Cada caso va en su propia transacción: el rechazo de
  G4 deja la transacción sin poder confirmarse (XACT_ABORT del SP).
*/
DECLARE @numero      TINYINT      = (SELECT MAX(numero_partido) + 1 FROM Torneo.PARTIDO);
DECLARE @fecha_utc   DATETIME2(0) = (SELECT DATEADD(DAY, 30, MAX(fecha_hora_utc)) FROM Torneo.PARTIDO);
DECLARE @id_sede     INT          = (SELECT MIN(id_sede) FROM Torneo.PARTIDO);
DECLARE @id_partido  INT;
DECLARE @local       INT;
DECLARE @visitante   INT;
DECLARE @conflicto   INT;
DECLARE @cruce       INT;
DECLARE @arbitro_1   INT;
DECLARE @arbitro_2   INT;
DECLARE @arbitro_3   INT;
DECLARE @arbitro_4   INT;

-- Local: una selección eliminada con árbitros FIFA de su país; visitante: otra eliminada.
SELECT TOP (1) @local = s.id_seleccion
FROM Torneo.SELECCION AS s
WHERE s.id_seleccion NOT IN (SELECT id_seleccion FROM Torneo.fn_SeleccionesEnCompetencia())
  AND EXISTS (SELECT 1 FROM Seguridad.vw_Arbitro AS a
              WHERE a.id_pais = s.id_pais AND a.activo = 1 AND a.categoria = 'FIFA')
ORDER BY s.id_seleccion;
SELECT TOP (1) @visitante = s.id_seleccion
FROM Torneo.SELECCION AS s
WHERE s.id_seleccion NOT IN (SELECT id_seleccion FROM Torneo.fn_SeleccionesEnCompetencia())
  AND s.id_seleccion <> @local
ORDER BY s.id_seleccion;

-- El árbitro en conflicto (del país local), uno de un país que sigue en competencia (puede
-- cruzarse) y cuatro sin conflicto ni posible cruce.
SELECT TOP (1) @conflicto = a.id_arbitro
FROM Seguridad.vw_Arbitro AS a
INNER JOIN Torneo.SELECCION AS s ON s.id_pais = a.id_pais
WHERE s.id_seleccion = @local AND a.activo = 1 AND a.categoria = 'FIFA'
ORDER BY a.id_arbitro;
SELECT TOP (1) @cruce = a.id_arbitro
FROM Seguridad.vw_Arbitro AS a
INNER JOIN Torneo.fn_SeleccionesEnCompetencia() AS sc ON sc.id_pais = a.id_pais
WHERE a.activo = 1
ORDER BY a.id_arbitro;
SELECT @arbitro_1 = MAX(IIF(x.orden = 1, x.id_arbitro, NULL)),
       @arbitro_2 = MAX(IIF(x.orden = 2, x.id_arbitro, NULL)),
       @arbitro_3 = MAX(IIF(x.orden = 3, x.id_arbitro, NULL)),
       @arbitro_4 = MAX(IIF(x.orden = 4, x.id_arbitro, NULL))
FROM (SELECT TOP (4) ROW_NUMBER() OVER (ORDER BY a.id_arbitro) AS orden, a.id_arbitro
      FROM Seguridad.vw_Arbitro AS a
      WHERE a.activo = 1 AND a.categoria = 'FIFA'
        AND a.id_pais NOT IN (SELECT s.id_pais FROM Torneo.SELECCION AS s WHERE s.id_seleccion IN (@local, @visitante))
        AND a.id_pais NOT IN (SELECT id_pais FROM Torneo.fn_SeleccionesEnCompetencia())
      ORDER BY a.id_arbitro) AS x;

SELECT N'G4. Designación rechazada por conflicto de nacionalidad (caso obligatorio)' AS consulta;
BEGIN TRY
    BEGIN TRANSACTION;

    EXEC Torneo.usp_PARTIDO_Alta @numero_partido = @numero, @id_sede = @id_sede, @fase = 'OCTAVOS',
                                 @fecha_hora_utc = @fecha_utc, @id_seleccion_local = @local,
                                 @id_seleccion_visitante = @visitante, @id_partido = @id_partido OUTPUT;

    SELECT N'Partido ficticio' AS partido, f.numero_partido, f.fase, f.seleccion_local, f.seleccion_visitante,
           CONCAT(a.nombre, N' ', a.apellido, N' (', pa.nombre, N')') AS arbitro_principal_propuesto
    FROM Torneo.vw_Fixture AS f
    CROSS JOIN Seguridad.vw_Arbitro AS a
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
    WHERE f.id_partido = @id_partido AND a.id_arbitro = @conflicto;

    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @conflicto,
                                             @id_asistente_1 = @arbitro_1, @id_asistente_2 = @arbitro_2,
                                             @id_cuarto = @arbitro_3, @id_var = @arbitro_4;

    ROLLBACK TRANSACTION;
    SELECT N'ATENCIÓN: la designación con conflicto de nacionalidad no fue rechazada.' AS resultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT N'Rechazada (esperado)' AS resultado, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS motivo;
END CATCH;

-- La advertencia también sale en la pestaña Mensajes (PRINT del SP).
SELECT N'G5. Advertencia desde dieciseisavos: árbitro de un país que puede cruzarse con los del partido' AS consulta;
IF @cruce IS NULL
    SELECT N'Ninguna selección sigue en competencia con árbitros de su país: no hay advertencia para mostrar.' AS resultado;
ELSE
BEGIN TRY
    BEGIN TRANSACTION;

    EXEC Torneo.usp_PARTIDO_Alta @numero_partido = @numero, @id_sede = @id_sede, @fase = 'OCTAVOS',
                                 @fecha_hora_utc = @fecha_utc, @id_seleccion_local = @local,
                                 @id_seleccion_visitante = @visitante, @id_partido = @id_partido OUTPUT;

    -- Devuelve la terna designada; la columna advertencia marca al que PUEDE CRUZARSE.
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @arbitro_1,
                                             @id_asistente_1 = @arbitro_2, @id_asistente_2 = @arbitro_3,
                                             @id_cuarto = @cruce, @id_var = @arbitro_4;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT N'Error inesperado' AS resultado, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS motivo;
END CATCH;
GO

-- El árbitro principal del último partido (la final).
DECLARE @id_arbitro INT = (SELECT TOP (1) d.id_arbitro
                           FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                           INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                           WHERE d.rol = 'PRINCIPAL'
                           ORDER BY p.fecha_hora_utc DESC);

SELECT CONCAT(N'G6. Historial de partidos de ', nombre, N' ', apellido, N' (principal de la final), con informes y sanciones') AS consulta
FROM Seguridad.vw_Arbitro WHERE id_arbitro = @id_arbitro;
SELECT rol, numero_partido, fase, fecha_hora_local, seleccion_local, seleccion_visitante, resultado,
       amarillas_del_partido, rojas_del_partido, informe_postpartido, sancion
FROM Arbitraje.vw_HistorialArbitro
WHERE id_arbitro = @id_arbitro
ORDER BY fecha_hora_local;

SELECT N'G6. Sanciones post-partido recibidas por los árbitros' AS consulta;
SELECT CONCAT(nombre, N' ', apellido) AS arbitro, pais, rol, numero_partido,
       CONCAT(seleccion_local, N' vs ', seleccion_visitante) AS partido, resultado, sancion
FROM Arbitraje.vw_HistorialArbitro
WHERE sancion IS NOT NULL
ORDER BY fecha_hora_local, rol;
GO


/* ============================================================================
   H. Gestión de publicidad
   ============================================================================ */

SELECT N'H1. Espacios publicitarios de cada sede (exactamente 4) con su tarifa' AS consulta;
SELECT CONCAT(s.nombre_estadio, N' (', s.ciudad, N')') AS sede,
       COUNT(ep.id_espacio) AS espacios,
       STRING_AGG(CONCAT(ep.numero_espacio, N'. ', ep.descripcion, N': USD ', ep.tarifa_usd), N' | ')
           WITHIN GROUP (ORDER BY ep.numero_espacio) AS espacios_y_tarifas
FROM Torneo.SEDE AS s
LEFT JOIN Publicidad.ESPACIO_PUBLICITARIO AS ep ON ep.id_sede = s.id_sede
GROUP BY s.id_sede, s.nombre_estadio, s.ciudad
ORDER BY sede;
GO

SELECT N'H2. Anunciantes por país (caso obligatorio: al menos 6 países), con sus campañas y piezas' AS consulta;
SELECT pa.nombre AS pais,
       COUNT(DISTINCT an.id_anunciante) AS anunciantes,
       COUNT(DISTINCT c.id_campania)    AS campanias,
       COUNT(DISTINCT pz.id_pieza)      AS piezas,
       MIN(c.fecha_inicio)              AS primera_campania,
       MAX(c.fecha_fin)                 AS ultima_campania
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
LEFT JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
LEFT JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
GROUP BY pa.nombre
ORDER BY anunciantes DESC, pa.nombre;

SELECT N'H2. Campañas y piezas: idioma y países de interés (mercados) de cada pieza' AS consulta;
SELECT an.razon_social AS anunciante, c.nombre AS campania, c.fecha_inicio, c.fecha_fin,
       pz.titulo AS pieza, i.nombre AS idioma, pz.duracion_segundos, m.mercados
FROM Publicidad.PIEZA_PUBLICITARIA AS pz
INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
INNER JOIN Publicidad.ANUNCIANTE AS an ON an.id_anunciante = c.id_anunciante
LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
OUTER APPLY (SELECT STRING_AGG(pa.nombre, ', ') WITHIN GROUP (ORDER BY pa.nombre) AS mercados
             FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
             INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = ppi.id_pais
             WHERE ppi.id_pieza = pz.id_pieza) AS m
ORDER BY an.razon_social, c.fecha_inicio, pz.titulo;
GO

-- El partido con más mercados publicitarios (países de interés de alguna pieza) en prime time.
DECLARE @id_partido INT = (SELECT TOP (1) id_partido
                           FROM Reportes.vw_PrimeTimePorMercado
                           WHERE en_prime_time = 1 AND es_mercado_publicitario = 1
                           GROUP BY id_partido
                           ORDER BY COUNT(*) DESC, id_partido);

SELECT CONCAT(N'H3. Simulación de prime time del partido ', numero_partido, N': ', seleccion_local, N' vs ',
              seleccion_visitante, N', ', CONVERT(VARCHAR(16), fecha_hora_utc, 120), N' UTC') AS consulta
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
SELECT m.mercado, m.huso_horario, m.hora_local,
       IIF(m.juega_el_partido = 1, N'SÍ', N'NO') AS juega_el_partido,
       IIF(EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi WHERE ppi.id_pais = m.id_pais),
           N'SÍ', N'NO') AS mercado_publicitario,
       m.feriado
FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido) AS m
WHERE m.en_prime_time = 1
ORDER BY mercado_publicitario DESC, m.hora_local, m.mercado;

-- Más de cuatro piezas candidatas con mercados en prime time: el criterio elige solo cuatro.
SELECT N'H4. Propuesta de piezas para los 4 espacios, en orden de prioridad (caso obligatorio)' AS consulta;
SELECT pp.prioridad, pp.anunciante, pp.campania, pp.titulo AS pieza,
       IIF(pp.dirigida_a_seleccion = 1, N'SÍ', N'NO') AS dirigida_a_seleccion,
       pp.franja_pbi, pp.pbi_per_capita_max, pp.mercados_en_prime_time, pp.mercados_de_interes,
       IIF(EXISTS (SELECT 1 FROM Publicidad.EXHIBICION AS ex
                   WHERE ex.id_partido = @id_partido AND ex.id_pieza = pp.id_pieza), N'SÍ', N'NO') AS exhibida
FROM Publicidad.fn_PrioridadPiezas(@id_partido) AS pp
ORDER BY pp.prioridad;

SELECT N'H4. Lo que se exhibió en ese partido: los 4 espacios de la sede' AS consulta;
SELECT numero_espacio, espacio, anunciante, campania, pieza, costo, codigo_moneda, costo_usd
FROM Reportes.vw_OcupacionPublicitaria
WHERE id_partido = @id_partido
ORDER BY numero_espacio;
GO

SELECT N'H5. Histórico de exhibiciones para facturar a cada anunciante (en dólares)' AS consulta;
SELECT o.anunciante, pa.nombre AS pais, COUNT(DISTINCT o.id_partido) AS partidos, COUNT(*) AS exhibiciones,
       SUM(o.costo_usd) AS a_facturar_usd, MIN(o.fecha_hora_local) AS primera_exhibicion,
       MAX(o.fecha_hora_local) AS ultima_exhibicion
FROM Reportes.vw_OcupacionPublicitaria AS o
INNER JOIN Publicidad.ANUNCIANTE AS an ON an.id_anunciante = o.id_anunciante
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
WHERE o.ocupado = 1
GROUP BY o.id_anunciante, o.anunciante, pa.nombre
ORDER BY a_facturar_usd DESC, o.anunciante;

-- Control: partidos jugados sin sus 4 espacios ocupados. Debe dar 0.
SELECT COUNT(*) AS partidos_sin_los_4_espacios
FROM Torneo.PARTIDO AS p
WHERE p.estado = 'FINALIZADO'
  AND (SELECT COUNT(*) FROM Publicidad.EXHIBICION AS ex WHERE ex.id_partido = p.id_partido) <> 4;
GO


/* ============================================================================
   I. Importación de datos externos
   ============================================================================ */

-- Upsert y sin duplicados: el PBI per cápita entra primero por XML (26) y después por la
-- API del Banco Mundial (29), que encuentra los mismos registros y los deja sin cambios.
SELECT N'I1. Procesos de importación: registros leídos, insertados, actualizados, sin cambios, omitidos y rechazados' AS consulta;
SELECT proceso, COUNT(*) AS corridas, SUM(leidos) AS leidos, SUM(insertados) AS insertados,
       SUM(actualizados) AS actualizados, SUM(sin_cambios) AS sin_cambios, SUM(omitidos) AS omitidos,
       SUM(rechazados) AS rechazados, MIN(fecha_hora) AS primera_corrida, MAX(fecha_hora) AS ultima_corrida
FROM DatosGenerales.IMPORTACION
GROUP BY proceso
ORDER BY MIN(id_importacion);
GO

-- Los CSV de jugadores, cuerpos técnicos y designaciones salen del scraping de Wikipedia
-- (scraping/Scraping_Jugadores.py y scraping/Scraping_Arbitros.py; técnica en scraping/README.md).
SELECT N'I2. Importaciones de datos obtenidos por scraping de Wikipedia' AS consulta;
SELECT id_importacion, proceso, origen, fecha_hora, leidos, insertados, rechazados
FROM DatosGenerales.IMPORTACION
WHERE proceso IN ('Torneo.usp_ImportarJugadoresCSV', 'Torneo.usp_ImportarCuerpoTecnicoCSV',
                  'Arbitraje.usp_ImportarDesignacionesCSV')
ORDER BY id_importacion;
GO

SELECT N'I3. Importación con errores parciales (caso obligatorio): registros rechazados por tabla' AS consulta;
SELECT tabla, rechazados
FROM (SELECT N'Torneo.ERRORES_SEDE' AS tabla, COUNT(*) AS rechazados FROM Torneo.ERRORES_SEDE
      UNION ALL SELECT N'Torneo.ERRORES_SELECCION', COUNT(*) FROM Torneo.ERRORES_SELECCION
      UNION ALL SELECT N'Torneo.ERRORES_JUGADOR', COUNT(*) FROM Torneo.ERRORES_JUGADOR
      UNION ALL SELECT N'Torneo.ERRORES_CUERPO_TECNICO', COUNT(*) FROM Torneo.ERRORES_CUERPO_TECNICO
      UNION ALL SELECT N'Torneo.ERRORES_PARTIDO', COUNT(*) FROM Torneo.ERRORES_PARTIDO
      UNION ALL SELECT N'DesarrolloPartido.ERRORES_EVENTO', COUNT(*) FROM DesarrolloPartido.ERRORES_EVENTO
      UNION ALL SELECT N'Arbitraje.ERRORES_DESIGNACION', COUNT(*) FROM Arbitraje.ERRORES_DESIGNACION
      UNION ALL SELECT N'Publicidad.ERRORES_CAMPANIA', COUNT(*) FROM Publicidad.ERRORES_CAMPANIA
      UNION ALL SELECT N'DatosGenerales.ERRORES_INDICADOR_ECONOMICO', COUNT(*) FROM DatosGenerales.ERRORES_INDICADOR_ECONOMICO
      UNION ALL SELECT N'DatosGenerales.ERRORES_COTIZACION', COUNT(*) FROM DatosGenerales.ERRORES_COTIZACION
      UNION ALL SELECT N'DatosGenerales.ERRORES_FERIADO', COUNT(*) FROM DatosGenerales.ERRORES_FERIADO) AS e
ORDER BY rechazados DESC, tabla;

-- Los partidos y eventos rechazados en la primera corrida, con todos sus motivos. Los válidos
-- del mismo archivo se cargaron igual.
SELECT N'I3. Detalle: partidos rechazados de la importación del fixture' AS consulta;
SELECT e.id_importacion, e.registro, e.ronda, e.fecha, e.equipo_1, e.equipo_2, e.estadio, e.resultado, e.motivos
FROM Torneo.ERRORES_PARTIDO AS e
ORDER BY e.id_importacion, e.registro;

SELECT N'I3. Detalle: primeros eventos (goles, tarjetas, cambios) rechazados' AS consulta;
SELECT TOP (20) e.id_importacion, e.registro, e.numero_partido, e.tipo, e.codigo_fifa, e.jugador, e.minuto, e.motivos
FROM DesarrolloPartido.ERRORES_EVENTO AS e
ORDER BY e.id_importacion, e.registro;
GO

-- Un archivo que no se puede leer no carga nada: el proceso lo informa con THROW y no se
-- registra en IMPORTACION.
SELECT N'I4. Error de formato o de archivo manejado con THROW' AS consulta;
BEGIN TRY
    EXEC Torneo.usp_ImportarPartidosJSON @ruta_archivo = N'C:\no_existe\worldcup.json';
    SELECT N'ATENCIÓN: la importación de un archivo inexistente no falló.' AS resultado;
END TRY
BEGIN CATCH
    SELECT N'Rechazada (esperado)' AS resultado, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS motivo;
END CATCH;
GO

SELECT N'I5. Datos de las APIs consumidas' AS consulta;
SELECT N'Frankfurter: cotizaciones' AS fuente, COUNT(*) AS registros,
       CONCAT(COUNT(DISTINCT codigo_moneda), N' monedas, del ', MIN(fecha), N' al ', MAX(fecha)) AS alcance
FROM DatosGenerales.COTIZACION
UNION ALL
SELECT N'Nager.Date: feriados', COUNT(*),
       CONCAT(COUNT(DISTINCT id_pais), N' países, del ', MIN(fecha), N' al ', MAX(fecha))
FROM DatosGenerales.FERIADO
UNION ALL
SELECT N'Banco Mundial: PBI per cápita (NY.GDP.PCAP.CD)', COUNT(*),
       CONCAT(COUNT(DISTINCT id_pais), N' países, años ', MIN(anio), N' a ', MAX(anio))
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE codigo_indicador = 'NY.GDP.PCAP.CD'
UNION ALL
SELECT N'Dossier Mundial: campañas publicitarias', SUM(leidos),
       CONCAT(SUM(insertados), N' insertados, ', SUM(actualizados + sin_cambios), N' ya cargados')
FROM DatosGenerales.IMPORTACION
WHERE proceso = 'Publicidad.usp_ImportarCampaniasAPI';
GO

SET NOEXEC OFF;
GO
