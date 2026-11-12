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
 Archivo: 26_SP_Reportes.sql
 Objetivo: Crear las vistas y los SP de reportes del esquema Reportes:
             Reportes.usp_Goleadores                 goleadores por selección, fase y torneo
             Reportes.usp_TarjetasXML                tarjetas por selección y jugador, con
                                                     suspensiones activas (XML)
             Reportes.usp_DesignacionesArbitrales    partidos de cada árbitro y tarjetas que señaló
             Reportes.usp_OcupacionPublicitaria      anunciantes por espacio, sede y partido, e
                                                     ingresos en dólares y en otra moneda
             Reportes.usp_MatrizPrimeTime            pivot partido x mercado en prime time
             Reportes.usp_SeleccionesYPlantillasXML  selecciones con sus convocados anidados (XML)
             Reportes.usp_Resultados                 tabla de posiciones y resultados
           Las vistas son la fuente de datos de Power BI: devuelven el detalle
           sin filtrar y los SP las filtran y les dan forma. Las suspensiones
           activas, que dependen de la fecha de corte, están para Power BI en
           Reportes.vw_SuspensionesActivas, una vez antes de cada partido. Las cotizaciones
           (22) y los feriados (23) de las APIs se usan para convertir los
           ingresos a otras monedas y para marcar los feriados de cada mercado.
           Requiere haber ejecutado 01 a 25. Su script de testing es
           76_Test_SP_Reportes.sql.
================================================================================

 Convenciones:
   - Los SP solo leen. Validan los parámetros y, si hay errores, los informan
     todos juntos con THROW 50001, como los SP de negocio.
   - Un parámetro en NULL significa "sin filtrar".
   - Los SP que devuelven XML lo muestran como una sola columna; no lo
     escriben en el sistema de archivos.
   - fecha_hora_utc es la referencia para comparar instantes (cortes, orden),
     y fecha_hora_local la fecha del partido para las cotizaciones.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   Vistas (fuente de datos de Power BI)
   ============================================================================ */

/*
  vw_Goles
  Un gol por fila con su autor, su selección y el partido. Igual que
  DesarrolloPartido.vw_Goleadores, no incluye los goles en contra ni los
  penales de la definición por penales. orden_fase sirve para ordenar las
  fases en el BI.
*/
CREATE OR ALTER VIEW Reportes.vw_Goles
AS
SELECT g.id_gol,
       f.id_partido,
       f.numero_partido,
       f.fase,
       CASE f.fase WHEN 'GRUPOS' THEN 1 WHEN 'DIECISEISAVOS' THEN 2 WHEN 'OCTAVOS' THEN 3
                   WHEN 'CUARTOS' THEN 4 WHEN 'SEMIFINAL' THEN 5 WHEN 'TERCER_PUESTO' THEN 6
                   ELSE 7 END                                            AS orden_fase,
       f.fecha_hora_local,
       CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante)          AS partido,
       s.id_seleccion,
       ps.nombre                                                          AS seleccion,
       j.id_jugador,
       j.apellido,
       j.nombre,
       CONCAT(j.apellido, N', ', j.nombre)                                AS jugador,
       j.dorsal,
       j.posicion_habitual,
       tg.descripcion                                                     AS tipo_gol,
       g.periodo,
       CONCAT(g.minuto, IIF(g.minuto_adicional > 0, CONCAT('+', g.minuto_adicional), '')) AS minuto
FROM DesarrolloPartido.GOL AS g
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = g.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
WHERE tg.es_en_contra = 0
  AND g.periodo <> 'PENALES';
GO


/*
  vw_Tarjetas
  Una tarjeta por fila, a un jugador o a un integrante del cuerpo técnico
  (receptor), con su selección, el partido y el árbitro principal, que es
  quien la señaló. instante es minuto * 100 + minuto_adicional, para ordenar.
*/
CREATE OR ALTER VIEW Reportes.vw_Tarjetas
AS
SELECT a.id_amonestacion,
       f.id_partido,
       f.numero_partido,
       f.fase,
       f.fecha_hora_local,
       f.fecha_hora_utc,
       CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante)          AS partido,
       s.id_seleccion,
       ps.nombre                                                          AS seleccion,
       IIF(a.id_jugador IS NULL, 'CUERPO TECNICO', 'JUGADOR')             AS receptor,
       a.id_jugador,
       a.id_persona_ct,
       COALESCE(j.apellido, ct.apellido)                                  AS apellido,
       COALESCE(j.nombre, ct.nombre)                                      AS nombre,
       CONCAT(COALESCE(j.apellido, ct.apellido), N', ', COALESCE(j.nombre, ct.nombre)) AS persona,
       j.dorsal,
       ct.rol                                                             AS rol_cuerpo_tecnico,
       a.tipo_tarjeta,
       a.es_doble_amarilla,
       a.minuto * 100 + a.minuto_adicional                                AS instante,
       CONCAT(a.minuto, IIF(a.minuto_adicional > 0, CONCAT('+', a.minuto_adicional), '')) AS minuto,
       a.motivo,
       ar.id_arbitro                                                      AS id_arbitro_principal,
       IIF(ar.id_arbitro IS NULL, NULL, CONCAT(ar.apellido, N', ', ar.nombre)) AS arbitro_principal
FROM DesarrolloPartido.AMONESTACION AS a
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = a.id_partido
LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
LEFT JOIN Torneo.PERSONA_CUERPO_TECNICO AS ct ON ct.id_persona_ct = a.id_persona_ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = COALESCE(l.id_seleccion, ct.id_seleccion)
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
LEFT JOIN Arbitraje.DESIGNACION_ARBITRAL AS d ON d.id_partido = a.id_partido AND d.rol = 'PRINCIPAL'
LEFT JOIN Arbitraje.ARBITRO AS ar ON ar.id_arbitro = d.id_arbitro;
GO


/*
  fn_SuspensionesActivas
  Sanciones (DesarrolloPartido.fn_Sanciones) que a la fecha y hora UTC de
  corte todavía no se terminaron de cumplir. Igual que en
  fn_JugadoresSuspendidos, cada partido posterior de la selección que no esté
  SUSPENDIDO cuenta como una fecha cumplida. proximo_partido es el partido en
  que el jugador no puede jugar; si es NULL, la selección no tiene más
  partidos cargados y la sanción queda pendiente.
  Ej.: SELECT * FROM Reportes.fn_SuspensionesActivas(SYSUTCDATETIME());
*/
CREATE OR ALTER FUNCTION Reportes.fn_SuspensionesActivas (@fecha_corte DATETIME2(0))
RETURNS TABLE
AS
RETURN
    SELECT s.id_jugador,
           s.id_seleccion,
           s.motivo,
           s.id_partido_origen,
           o.numero_partido                          AS numero_partido_origen,
           s.partidos_de_suspension,
           c.cumplidos                               AS partidos_cumplidos,
           s.partidos_de_suspension - c.cumplidos    AS partidos_pendientes,
           px.numero_partido                         AS proximo_partido,
           px.fecha_hora_utc                         AS fecha_proximo_partido_utc
    FROM DesarrolloPartido.fn_Sanciones() AS s
    INNER JOIN Torneo.PARTIDO AS o ON o.id_partido = s.id_partido_origen
    CROSS APPLY (SELECT COUNT(*) AS cumplidos
                 FROM Torneo.PARTIDO AS q
                 WHERE s.id_seleccion IN (q.id_seleccion_local, q.id_seleccion_visitante)
                   AND q.estado <> 'SUSPENDIDO'
                   AND q.fecha_hora_utc > o.fecha_hora_utc
                   AND q.fecha_hora_utc <= @fecha_corte) AS c
    OUTER APPLY (SELECT TOP (1) q.numero_partido, q.fecha_hora_utc
                 FROM Torneo.PARTIDO AS q
                 WHERE s.id_seleccion IN (q.id_seleccion_local, q.id_seleccion_visitante)
                   AND q.estado <> 'SUSPENDIDO'
                   AND q.fecha_hora_utc > @fecha_corte
                 ORDER BY q.fecha_hora_utc) AS px
    WHERE o.fecha_hora_utc <= @fecha_corte
      AND c.cumplidos < s.partidos_de_suspension;
GO


/*
  vw_SuspensionesActivas
  Las suspensiones activas (Reportes.fn_SuspensionesActivas) en cada momento
  del torneo en que importan: un segundo antes de cada partido, y hoy. Así
  Power BI, que no puede pasarle la fecha de corte a una función, muestra las
  de cualquier momento con un segmentador sobre "momento" (orden_momento lo
  ordena). Una fila por momento y suspensión activa: en ese momento el
  jugador no puede jugar su proximo_partido.
*/
CREATE OR ALTER VIEW Reportes.vw_SuspensionesActivas
AS
WITH momentos AS (
    SELECT CAST(f.numero_partido AS INT) AS orden_momento,
           CONCAT(N'Antes del partido ', f.numero_partido, N'. ', f.seleccion_local, N' vs ', f.seleccion_visitante) AS momento,
           DATEADD(SECOND, -1, p.fecha_hora_utc) AS fecha_corte_utc
    FROM Torneo.vw_Fixture AS f
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
    WHERE p.estado <> 'SUSPENDIDO'
    UNION ALL
    SELECT 1000, N'Hoy', CAST(SYSUTCDATETIME() AS DATETIME2(0))
)
SELECT m.orden_momento,
       m.momento,
       m.fecha_corte_utc,
       pa.nombre                                     AS seleccion,
       j.id_jugador,
       j.dorsal,
       CONCAT(j.apellido, N', ', j.nombre)           AS jugador,
       sa.motivo,
       sa.numero_partido_origen,
       sa.partidos_de_suspension,
       sa.partidos_cumplidos,
       sa.partidos_pendientes,
       sa.proximo_partido
FROM momentos AS m
CROSS APPLY Reportes.fn_SuspensionesActivas(m.fecha_corte_utc) AS sa
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = sa.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = sa.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais;
GO


/*
  vw_Arbitros
  Un árbitro designado por fila, para el segmentador de árbitros del BI
  (relacionado con vw_DesignacionesArbitrales y vw_Tarjetas).
*/
CREATE OR ALTER VIEW Reportes.vw_Arbitros
AS
SELECT ar.id_arbitro,
       CONCAT(ar.apellido, N', ', ar.nombre) AS arbitro
FROM Arbitraje.ARBITRO AS ar
WHERE EXISTS (SELECT 1
              FROM Arbitraje.DESIGNACION_ARBITRAL AS d
              WHERE d.id_arbitro = ar.id_arbitro);
GO


/*
  vw_DesignacionesArbitrales
  Una designación por fila: árbitro, rol y partido. Las tarjetas las señala
  el árbitro principal (AMONESTACION no guarda qué árbitro la mostró), así
  que amarillas_senaladas y rojas_senaladas valen 0 en los demás roles.
*/
CREATE OR ALTER VIEW Reportes.vw_DesignacionesArbitrales
AS
SELECT ar.id_arbitro,
       CONCAT(ar.apellido, N', ', ar.nombre)                      AS arbitro,
       pa.nombre                                                  AS pais,
       ar.categoria,
       d.rol,
       f.id_partido,
       f.numero_partido,
       f.fase,
       f.fecha_hora_local,
       f.nombre_estadio,
       CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante)  AS partido,
       f.resultado,
       f.estado,
       ISNULL(t.amarillas, 0)                                     AS amarillas_senaladas,
       ISNULL(t.rojas, 0)                                         AS rojas_senaladas
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Arbitraje.ARBITRO AS ar ON ar.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = ar.id_pais
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = d.id_partido
LEFT JOIN (SELECT am.id_partido,
                  SUM(IIF(am.tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
                  SUM(IIF(am.tipo_tarjeta = 'ROJA', 1, 0))     AS rojas
           FROM DesarrolloPartido.AMONESTACION AS am
           GROUP BY am.id_partido) AS t ON t.id_partido = d.id_partido AND d.rol = 'PRINCIPAL';
GO


/*
  vw_OcupacionPublicitaria
  Un espacio publicitario por partido: los cuatro espacios de la sede, con la
  pieza, la campaña y el anunciante exhibidos, o vacío (ocupado = 0) si el
  partido no tiene publicidad asignada en ese espacio. costo_usd pasa el
  costo de la exhibición a dólares con la cotización vigente en la fecha del
  partido; sin cotización de esa moneda queda en NULL.
*/
CREATE OR ALTER VIEW Reportes.vw_OcupacionPublicitaria
AS
SELECT f.id_partido,
       f.numero_partido,
       f.fase,
       f.fecha_hora_local,
       CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante)  AS partido,
       f.id_sede,
       CONCAT(f.nombre_estadio, N' (', f.ciudad, N')')            AS sede,
       ep.id_espacio,
       ep.numero_espacio,
       ep.descripcion                                             AS espacio,
       ep.tarifa_usd,
       CAST(IIF(ex.id_pieza IS NULL, 0, 1) AS BIT)                AS ocupado,
       an.id_anunciante,
       an.razon_social                                            AS anunciante,
       c.nombre                                                   AS campania,
       pz.titulo                                                  AS pieza,
       ex.costo,
       ex.codigo_moneda,
       CAST(ex.costo / co.unidades_por_usd AS DECIMAL(19,2))      AS costo_usd
FROM Torneo.vw_Fixture AS f
INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS ep ON ep.id_sede = f.id_sede
LEFT JOIN Publicidad.EXHIBICION AS ex ON ex.id_partido = f.id_partido AND ex.id_espacio = ep.id_espacio
LEFT JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ex.id_pieza
LEFT JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
LEFT JOIN Publicidad.ANUNCIANTE AS an ON an.id_anunciante = c.id_anunciante
OUTER APPLY DatosGenerales.fn_CotizacionVigente(ex.codigo_moneda, CAST(f.fecha_hora_local AS DATE)) AS co;
GO


/*
  vw_IngresosPublicitariosPorMoneda
  Ingresos por publicidad de cada partido convertidos a cada moneda con
  cotización cargada (y al dólar), con la cotización vigente en la fecha del
  partido. Una moneda sin cotización hasta esa fecha no aparece. En el BI se
  filtra por codigo_moneda.
*/
CREATE OR ALTER VIEW Reportes.vw_IngresosPublicitariosPorMoneda
AS
WITH ingresos AS (
    SELECT id_partido, numero_partido, fecha_hora_local, partido, id_sede, sede,
           SUM(costo_usd) AS ingresos_usd
    FROM Reportes.vw_OcupacionPublicitaria
    GROUP BY id_partido, numero_partido, fecha_hora_local, partido, id_sede, sede
),
monedas AS (
    SELECT codigo_moneda FROM DatosGenerales.COTIZACION
    UNION
    SELECT CAST('USD' AS CHAR(3))
)
SELECT i.id_partido,
       i.numero_partido,
       i.fecha_hora_local,
       i.partido,
       i.id_sede,
       i.sede,
       i.ingresos_usd,
       m.codigo_moneda,
       c.fecha_cotizacion,
       c.unidades_por_usd,
       CAST(i.ingresos_usd * c.unidades_por_usd AS DECIMAL(19,2)) AS ingresos_en_moneda
FROM ingresos AS i
CROSS JOIN monedas AS m
CROSS APPLY DatosGenerales.fn_CotizacionVigente(m.codigo_moneda, CAST(i.fecha_hora_local AS DATE)) AS c;
GO


/*
  vw_PrimeTimePorMercado
  Simulación de prime time (Publicidad.fn_MercadosEnPrimeTime) de todos los
  partidos: un partido y mercado por fila, con la hora local, si cae en prime
  time y si ese día es feriado en el mercado. es_mercado_publicitario indica
  si el país es mercado de interés de alguna pieza.
*/
CREATE OR ALTER VIEW Reportes.vw_PrimeTimePorMercado
AS
SELECT f.id_partido,
       f.numero_partido,
       f.fase,
       f.fecha_hora_utc,
       CONCAT(f.seleccion_local, N' vs ', f.seleccion_visitante)  AS partido,
       f.nombre_estadio,
       m.id_pais,
       m.mercado,
       m.hora_local,
       m.en_prime_time,
       m.es_feriado,
       m.feriado,
       m.juega_el_partido,
       CAST(IIF(EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
                        WHERE ppi.id_pais = m.id_pais), 1, 0) AS BIT) AS es_mercado_publicitario
FROM Torneo.vw_Fixture AS f
CROSS APPLY Publicidad.fn_MercadosEnPrimeTime(f.id_partido) AS m;
GO


/*
  vw_Sedes
  Una sede por fila con su ubicación (latitud y longitud, para el mapa del
  BI) y cuántos partidos tiene. sede tiene el mismo formato que en
  vw_OcupacionPublicitaria.
*/
CREATE OR ALTER VIEW Reportes.vw_Sedes
AS
SELECT s.id_sede,
       CONCAT(s.nombre_estadio, N' (', s.ciudad, N')')  AS sede,
       s.nombre_estadio,
       s.ciudad,
       pa.nombre                                        AS pais,
       s.capacidad,
       s.huso_horario,
       s.latitud,
       s.longitud,
       (SELECT COUNT(*) FROM Torneo.PARTIDO AS p WHERE p.id_sede = s.id_sede) AS partidos
FROM Torneo.SEDE AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais;
GO


/*
  vw_Plantillas
  Un convocado por fila con su selección. activo = 0 son los dados de baja
  (reemplazados). No incluye la fecha de nacimiento: el reporte no la pide y
  la vista la leen roles que no la necesitan (27_SP_Roles.sql).
*/
CREATE OR ALTER VIEW Reportes.vw_Plantillas
AS
SELECT s.id_seleccion,
       pa.nombre                                    AS seleccion,
       pa.codigo_fifa,
       s.confederacion,
       s.grupo,
       j.id_jugador,
       j.dorsal,
       j.apellido,
       j.nombre,
       j.posicion_habitual,
       j.club_origen,
       CAST(IIF(j.fecha_baja IS NULL, 1, 0) AS BIT) AS activo,
       j.fecha_baja,
       j.motivo_baja
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista;
GO


/*
  vw_Resultados
  Un partido por fila con el resultado, el ganador (también por penales; en
  grupos puede ser "Empate") y los goles de cada lado en el orden en que se
  hicieron. Un gol en contra figura del lado que lo suma, marcado (e/c).
  partido lleva el número, así es único aunque las selecciones de dos
  cruces todavía sean "A definir": el BI la usa como dimensión de partidos.
*/
CREATE OR ALTER VIEW Reportes.vw_Resultados
AS
WITH goles AS (
    -- Los goles del partido (sin la definición por penales), con la selección que los suma:
    -- un gol en contra suma para el rival.
    SELECT g.id_partido,
           IIF(tg.es_en_contra = 1,
               IIF(l.id_seleccion = p.id_seleccion_local, p.id_seleccion_visitante, p.id_seleccion_local),
               l.id_seleccion) AS id_seleccion,
           g.id_gol,
           g.minuto,
           g.minuto_adicional,
           CONCAT(j.apellido, N' ', g.minuto,
                  IIF(g.minuto_adicional > 0, CONCAT(N'+', g.minuto_adicional), N''), N'''',
                  IIF(tg.es_en_contra = 1, N' (e/c)', N'')) AS detalle
    FROM DesarrolloPartido.GOL AS g
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
    INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE g.periodo <> 'PENALES'
),
goles_por_seleccion AS (
    SELECT id_partido,
           id_seleccion,
           STRING_AGG(detalle, N', ') WITHIN GROUP (ORDER BY minuto, minuto_adicional, id_gol) AS detalle
    FROM goles
    GROUP BY id_partido, id_seleccion
)
SELECT f.id_partido,
       f.numero_partido,
       CONCAT(f.numero_partido, N'. ', f.seleccion_local, N' vs ', f.seleccion_visitante) AS partido,
       f.fase,
       CASE f.fase WHEN 'GRUPOS' THEN 1 WHEN 'DIECISEISAVOS' THEN 2 WHEN 'OCTAVOS' THEN 3
                   WHEN 'CUARTOS' THEN 4 WHEN 'SEMIFINAL' THEN 5 WHEN 'TERCER_PUESTO' THEN 6
                   ELSE 7 END                       AS orden_fase,
       f.grupo,
       f.fecha_hora_local,
       f.fecha_hora_utc,
       f.nombre_estadio,
       f.ciudad,
       f.id_seleccion_local,
       f.seleccion_local,
       f.id_seleccion_visitante,
       f.seleccion_visitante,
       f.goles_local,
       f.goles_visitante,
       f.penales_local,
       f.penales_visitante,
       f.resultado,
       CASE WHEN f.estado <> 'FINALIZADO'               THEN NULL
            WHEN f.goles_local > f.goles_visitante      THEN f.seleccion_local
            WHEN f.goles_visitante > f.goles_local      THEN f.seleccion_visitante
            WHEN f.penales_local > f.penales_visitante  THEN f.seleccion_local
            WHEN f.penales_visitante > f.penales_local  THEN f.seleccion_visitante
            ELSE 'Empate'
       END                                          AS ganador,
       gl.detalle                                   AS goles_del_local,
       gv.detalle                                   AS goles_del_visitante,
       f.asistencia,
       f.estado
FROM Torneo.vw_Fixture AS f
LEFT JOIN goles_por_seleccion AS gl ON gl.id_partido = f.id_partido AND gl.id_seleccion = f.id_seleccion_local
LEFT JOIN goles_por_seleccion AS gv ON gv.id_partido = f.id_partido AND gv.id_seleccion = f.id_seleccion_visitante;
GO


/*
  vw_TablaPosiciones
  Posiciones de cada grupo con los partidos de grupos FINALIZADOS: 3 puntos
  por partido ganado y 1 por empatado; desempatan la diferencia de gol y los
  goles a favor.
*/
CREATE OR ALTER VIEW Reportes.vw_TablaPosiciones
AS
WITH resultados AS (
    SELECT id_seleccion_local AS id_seleccion, goles_local AS gf, goles_visitante AS gc
    FROM Torneo.PARTIDO
    WHERE fase = 'GRUPOS' AND estado = 'FINALIZADO'
    UNION ALL
    SELECT id_seleccion_visitante, goles_visitante, goles_local
    FROM Torneo.PARTIDO
    WHERE fase = 'GRUPOS' AND estado = 'FINALIZADO'
),
totales AS (
    SELECT s.id_seleccion,
           s.grupo,
           pa.nombre                                  AS seleccion,
           COUNT(r.id_seleccion)                      AS pj,
           ISNULL(SUM(IIF(r.gf > r.gc, 1, 0)), 0)     AS pg,
           ISNULL(SUM(IIF(r.gf = r.gc, 1, 0)), 0)     AS pe,
           ISNULL(SUM(IIF(r.gf < r.gc, 1, 0)), 0)     AS pp,
           ISNULL(SUM(r.gf), 0)                       AS gf,
           ISNULL(SUM(r.gc), 0)                       AS gc
    FROM Torneo.SELECCION AS s
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    LEFT JOIN resultados AS r ON r.id_seleccion = s.id_seleccion
    WHERE s.grupo IS NOT NULL
    GROUP BY s.id_seleccion, s.grupo, pa.nombre
)
SELECT grupo,
       ROW_NUMBER() OVER (PARTITION BY grupo ORDER BY pg * 3 + pe DESC, gf - gc DESC, gf DESC, seleccion) AS posicion,
       id_seleccion,
       seleccion,
       pj, pg, pe, pp, gf, gc,
       gf - gc     AS dg,
       pg * 3 + pe AS pts
FROM totales;
GO


/*
  vw_CuadroEliminacion
  Partidos de eliminación directa ubicados en el cuadro, para dibujarlo en el
  BI: ronda (0 = la primera ronda de eliminación que tenga el torneo; la
  última, rondas - 1, es la final), posición dentro de la ronda (0 arriba) y
  qué selección ganó (gana_local: 1 la local, 0 la visitante, NULL sin
  definir). El tercer puesto va aparte, en la ronda de la final.
  El cuadro no está modelado (no se guarda qué partido alimenta a cuál), así
  que se reconstruye con los resultados, desde la final hacia atrás: el
  partido que ganó la selección local de un cruce va en la posición 2p y el
  que ganó la visitante, en la 2p + 1. Una ronda en la que no se pueden ubicar
  todos los partidos así (porque falta jugar el cruce siguiente) se ordena por
  número de partido.
*/
CREATE OR ALTER VIEW Reportes.vw_CuadroEliminacion
AS
WITH eliminacion AS (
    SELECT p.id_partido,
           p.numero_partido,
           p.fase,
           CASE p.fase WHEN 'DIECISEISAVOS' THEN 1 WHEN 'OCTAVOS' THEN 2 WHEN 'CUARTOS' THEN 3
                       WHEN 'SEMIFINAL' THEN 4 ELSE 5 END AS nivel,
           p.id_seleccion_local,
           p.id_seleccion_visitante,
           CASE WHEN p.estado <> 'FINALIZADO'               THEN NULL
                WHEN p.goles_local > p.goles_visitante      THEN p.id_seleccion_local
                WHEN p.goles_visitante > p.goles_local      THEN p.id_seleccion_visitante
                WHEN p.penales_local > p.penales_visitante  THEN p.id_seleccion_local
                WHEN p.penales_visitante > p.penales_local  THEN p.id_seleccion_visitante
           END AS id_ganador
    FROM Torneo.PARTIDO AS p
    WHERE p.fase IN ('DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'FINAL', 'TERCER_PUESTO')
),
-- Desde la final hacia atrás: cada partido ubica al anterior que ganó cada una de sus selecciones.
arbol AS (
    SELECT id_partido, nivel, 0 AS posicion
    FROM eliminacion
    WHERE fase = 'FINAL'
    UNION ALL
    SELECT h.id_partido, h.nivel, a.posicion * 2 + IIF(h.id_ganador = padre.id_seleccion_local, 0, 1)
    FROM arbol AS a
    INNER JOIN eliminacion AS padre ON padre.id_partido = a.id_partido
    INNER JOIN eliminacion AS h ON h.nivel = padre.nivel - 1
                               AND h.fase <> 'TERCER_PUESTO'
                               AND h.id_ganador IN (padre.id_seleccion_local, padre.id_seleccion_visitante)
),
ubicados AS (
    SELECT e.*,
           a.posicion                                                                   AS posicion_arbol,
           COUNT(a.id_partido) OVER (PARTITION BY e.nivel, IIF(e.fase = 'TERCER_PUESTO', 1, 0)) AS ubicados_en_ronda,
           COUNT(*) OVER (PARTITION BY e.nivel, IIF(e.fase = 'TERCER_PUESTO', 1, 0))           AS partidos_en_ronda,
           ROW_NUMBER() OVER (PARTITION BY e.nivel, IIF(e.fase = 'TERCER_PUESTO', 1, 0)
                              ORDER BY e.numero_partido) - 1                            AS posicion_numero
    FROM eliminacion AS e
    LEFT JOIN arbol AS a ON a.id_partido = e.id_partido
)
SELECT u.id_partido,
       u.numero_partido,
       u.fase,
       CASE u.fase WHEN 'DIECISEISAVOS' THEN 'Dieciseisavos de final' WHEN 'OCTAVOS' THEN 'Octavos de final'
                   WHEN 'CUARTOS' THEN 'Cuartos de final' WHEN 'SEMIFINAL' THEN 'Semifinales'
                   WHEN 'FINAL' THEN 'Final' ELSE 'Tercer puesto' END                  AS etiqueta,
       u.nivel - r.primera                                                              AS ronda,
       5 - r.primera + 1                                                                AS rondas,
       IIF(u.ubicados_en_ronda = u.partidos_en_ronda, u.posicion_arbol, u.posicion_numero) AS posicion,
       CAST(IIF(u.fase = 'TERCER_PUESTO', 1, 0) AS BIT)                                 AS es_tercer_puesto,
       f.seleccion_local,
       f.seleccion_visitante,
       f.goles_local,
       f.goles_visitante,
       f.penales_local,
       f.penales_visitante,
       CASE WHEN u.id_ganador IS NULL THEN NULL
            WHEN u.id_ganador = u.id_seleccion_local THEN 1
            ELSE 0 END                                                                  AS gana_local
FROM ubicados AS u
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = u.id_partido
CROSS JOIN (SELECT MIN(nivel) AS primera FROM eliminacion) AS r;
GO


/* ============================================================================
   Stored procedures
   ============================================================================ */

/*
  usp_Goleadores
  Tabla de goleadores: una fila por jugador con sus goles en el torneo, su
  posición en el torneo y dentro de su selección, y los goles de cada fase.
  Con @fase solo cuentan los goles de esa fase; con @id_seleccion se muestran
  solo sus jugadores, pero posicion_torneo sigue siendo la del torneo.
  Ej.: EXEC Reportes.usp_Goleadores @fase = 'GRUPOS';
*/
CREATE OR ALTER PROCEDURE Reportes.usp_Goleadores
    @id_seleccion  INT         = NULL,
    @fase          VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @fase = UPPER(NULLIF(TRIM(@fase), ''));

    IF @id_seleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @salto_linea + N'- No existe la selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

    IF @fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')
        SET @errores += @salto_linea + N'- La fase "' + @fase + N'" no existe.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_Goleadores: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    WITH goleadores AS (
        SELECT g.id_seleccion,
               g.seleccion,
               g.id_jugador,
               CONCAT(g.apellido, N', ', g.nombre)                            AS jugador,
               g.dorsal,
               COUNT(*)                                                       AS goles,
               COUNT(DISTINCT g.id_partido)                                   AS partidos_con_gol,
               SUM(IIF(g.fase = 'GRUPOS', 1, 0))                              AS grupos,
               SUM(IIF(g.fase = 'DIECISEISAVOS', 1, 0))                       AS dieciseisavos,
               SUM(IIF(g.fase = 'OCTAVOS', 1, 0))                             AS octavos,
               SUM(IIF(g.fase = 'CUARTOS', 1, 0))                             AS cuartos,
               SUM(IIF(g.fase = 'SEMIFINAL', 1, 0))                           AS semifinal,
               SUM(IIF(g.fase = 'TERCER_PUESTO', 1, 0))                       AS tercer_puesto,
               SUM(IIF(g.fase = 'FINAL', 1, 0))                               AS final,
               RANK() OVER (ORDER BY COUNT(*) DESC)                           AS posicion_torneo,
               RANK() OVER (PARTITION BY g.id_seleccion ORDER BY COUNT(*) DESC) AS posicion_en_seleccion
        FROM Reportes.vw_Goles AS g
        WHERE @fase IS NULL OR g.fase = @fase
        GROUP BY g.id_seleccion, g.seleccion, g.id_jugador, g.apellido, g.nombre, g.dorsal
    )
    SELECT posicion_torneo, seleccion, posicion_en_seleccion, jugador, dorsal, goles, partidos_con_gol,
           grupos, dieciseisavos, octavos, cuartos, semifinal, tercer_puesto, final
    FROM goleadores
    WHERE @id_seleccion IS NULL OR id_seleccion = @id_seleccion
    ORDER BY posicion_torneo, seleccion, jugador;
END;
GO


/*
  usp_TarjetasXML
  Tarjetas por selección y jugador en XML, a una fecha y hora UTC de corte
  (por defecto, ahora): solo cuentan los partidos jugados hasta el corte.
  Estructura:
    <Tarjetas fecha_corte_utc>
      <Seleccion id codigo_fifa nombre amarillas rojas>   (amarillas y rojas incluyen al cuerpo técnico)
        <Jugadores>
          <Jugador id dorsal apellido nombre amarillas rojas>
            <Tarjeta partido fase minuto tipo doble_amarilla motivo/>
            <SuspensionActiva motivo partido_origen partidos cumplidos pendientes proximo_partido/>
        <CuerpoTecnico>
          <Persona rol apellido nombre amarillas rojas/>
  Solo aparecen las selecciones con alguna tarjeta. Las suspensiones activas
  son las de Reportes.fn_SuspensionesActivas: por acumulación de amarillas,
  doble amarilla o roja directa (motivo).
  Ej.: EXEC Reportes.usp_TarjetasXML @fecha_corte = '2026-06-20';
*/
CREATE OR ALTER PROCEDURE Reportes.usp_TarjetasXML
    @id_seleccion  INT          = NULL,
    @fecha_corte   DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @fecha_corte = ISNULL(@fecha_corte, CAST(SYSUTCDATETIME() AS DATETIME2(0)));

    IF @id_seleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @salto_linea + N'- No existe la selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_TarjetasXML: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Las tarjetas y las suspensiones se calculan una sola vez y no por cada jugador.
    DECLARE @tarjetas TABLE (
        id_amonestacion     INT PRIMARY KEY,
        id_seleccion        INT,
        receptor            VARCHAR(15),
        id_jugador          INT,
        id_persona_ct       INT,
        apellido            NVARCHAR(60),
        nombre              NVARCHAR(60),
        dorsal              TINYINT,
        rol_cuerpo_tecnico  VARCHAR(20),
        numero_partido      TINYINT,
        fase                VARCHAR(15),
        fecha_hora_utc      DATETIME2(0),
        instante            INT,
        minuto              VARCHAR(10),
        tipo_tarjeta        VARCHAR(8),
        es_doble_amarilla   BIT,
        motivo              VARCHAR(200)
    );

    DECLARE @suspensiones TABLE (
        id_jugador              INT,
        motivo                  VARCHAR(200),
        numero_partido_origen   TINYINT,
        partidos_de_suspension  INT,
        partidos_cumplidos      INT,
        partidos_pendientes     INT,
        proximo_partido         TINYINT
    );

    INSERT INTO @tarjetas
    SELECT id_amonestacion, id_seleccion, receptor, id_jugador, id_persona_ct, apellido, nombre, dorsal,
           rol_cuerpo_tecnico, numero_partido, fase, fecha_hora_utc, instante, minuto, tipo_tarjeta,
           es_doble_amarilla, motivo
    FROM Reportes.vw_Tarjetas
    WHERE fecha_hora_utc <= @fecha_corte
      AND (@id_seleccion IS NULL OR id_seleccion = @id_seleccion);

    INSERT INTO @suspensiones
    SELECT id_jugador, motivo, numero_partido_origen, partidos_de_suspension, partidos_cumplidos,
           partidos_pendientes, proximo_partido
    FROM Reportes.fn_SuspensionesActivas(@fecha_corte)
    WHERE @id_seleccion IS NULL OR id_seleccion = @id_seleccion;

    SELECT (
        SELECT @fecha_corte AS [@fecha_corte_utc],
               (SELECT s.id_seleccion                               AS [@id],
                       pa.codigo_fifa                               AS [@codigo_fifa],
                       pa.nombre                                    AS [@nombre],
                       SUM(IIF(t.tipo_tarjeta = 'AMARILLA', 1, 0))  AS [@amarillas],
                       SUM(IIF(t.tipo_tarjeta = 'ROJA', 1, 0))      AS [@rojas],
                       (SELECT tj.id_jugador                                AS [@id],
                               tj.dorsal                                    AS [@dorsal],
                               tj.apellido                                  AS [@apellido],
                               tj.nombre                                    AS [@nombre],
                               SUM(IIF(tj.tipo_tarjeta = 'AMARILLA', 1, 0)) AS [@amarillas],
                               SUM(IIF(tj.tipo_tarjeta = 'ROJA', 1, 0))     AS [@rojas],
                               (SELECT d.numero_partido                          AS [@partido],
                                       d.fase                                    AS [@fase],
                                       d.minuto                                  AS [@minuto],
                                       d.tipo_tarjeta                            AS [@tipo],
                                       IIF(d.es_doble_amarilla = 1, 'SI', NULL)  AS [@doble_amarilla],
                                       d.motivo                                  AS [@motivo]
                                FROM @tarjetas AS d
                                WHERE d.id_jugador = tj.id_jugador
                                ORDER BY d.fecha_hora_utc, d.instante
                                FOR XML PATH('Tarjeta'), TYPE),
                               (SELECT su.motivo                  AS [@motivo],
                                       su.numero_partido_origen   AS [@partido_origen],
                                       su.partidos_de_suspension  AS [@partidos],
                                       su.partidos_cumplidos      AS [@cumplidos],
                                       su.partidos_pendientes     AS [@pendientes],
                                       su.proximo_partido         AS [@proximo_partido]
                                FROM @suspensiones AS su
                                WHERE su.id_jugador = tj.id_jugador
                                ORDER BY su.numero_partido_origen
                                FOR XML PATH('SuspensionActiva'), TYPE)
                        FROM @tarjetas AS tj
                        WHERE tj.id_seleccion = s.id_seleccion
                          AND tj.receptor = 'JUGADOR'
                        GROUP BY tj.id_jugador, tj.dorsal, tj.apellido, tj.nombre
                        ORDER BY tj.apellido, tj.nombre
                        FOR XML PATH('Jugador'), TYPE)              AS [Jugadores],
                       (SELECT tc.rol_cuerpo_tecnico                        AS [@rol],
                               tc.apellido                                  AS [@apellido],
                               tc.nombre                                    AS [@nombre],
                               SUM(IIF(tc.tipo_tarjeta = 'AMARILLA', 1, 0)) AS [@amarillas],
                               SUM(IIF(tc.tipo_tarjeta = 'ROJA', 1, 0))     AS [@rojas]
                        FROM @tarjetas AS tc
                        WHERE tc.id_seleccion = s.id_seleccion
                          AND tc.receptor = 'CUERPO TECNICO'
                        GROUP BY tc.id_persona_ct, tc.rol_cuerpo_tecnico, tc.apellido, tc.nombre
                        ORDER BY tc.apellido, tc.nombre
                        FOR XML PATH('Persona'), TYPE)              AS [CuerpoTecnico]
                FROM @tarjetas AS t
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = t.id_seleccion
                INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
                GROUP BY s.id_seleccion, pa.codigo_fifa, pa.nombre
                ORDER BY pa.nombre
                FOR XML PATH('Seleccion'), TYPE)
        FOR XML PATH('Tarjetas'), TYPE
    ) AS reporte_tarjetas;
END;
GO


/*
  usp_DesignacionesArbitrales
  Una fila por designación: el árbitro con su total de designaciones y de
  partidos dirigidos (como principal), el partido y, cuando fue el principal,
  las amarillas y rojas que señaló con el detalle de cada una. Con
  @solo_principal = 1 muestra solo los partidos dirigidos.
  Ej.: EXEC Reportes.usp_DesignacionesArbitrales @solo_principal = 1;
*/
CREATE OR ALTER PROCEDURE Reportes.usp_DesignacionesArbitrales
    @id_arbitro      INT = NULL,
    @solo_principal  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_arbitro IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro)
        SET @errores += @salto_linea + N'- No existe el árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_DesignacionesArbitrales: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT v.arbitro,
           v.pais,
           v.categoria,
           COUNT(*) OVER (PARTITION BY v.id_arbitro)                          AS designaciones,
           SUM(IIF(v.rol = 'PRINCIPAL', 1, 0)) OVER (PARTITION BY v.id_arbitro) AS partidos_dirigidos,
           v.rol,
           v.numero_partido,
           v.fase,
           v.fecha_hora_local,
           v.partido,
           v.resultado,
           v.amarillas_senaladas,
           v.rojas_senaladas,
           det.detalle                                                        AS tarjetas_senaladas
    FROM Reportes.vw_DesignacionesArbitrales AS v
    LEFT JOIN (SELECT t.id_partido,
                      STRING_AGG(CONCAT(t.minuto, N''' ', t.tipo_tarjeta,
                                        IIF(t.es_doble_amarilla = 1, N' (doble amarilla)', N''),
                                        N' a ', t.apellido, N' (', t.seleccion, N')'), N'; ')
                          WITHIN GROUP (ORDER BY t.instante, t.id_amonestacion) AS detalle
               FROM Reportes.vw_Tarjetas AS t
               GROUP BY t.id_partido) AS det ON det.id_partido = v.id_partido AND v.rol = 'PRINCIPAL'
    WHERE (@id_arbitro IS NULL OR v.id_arbitro = @id_arbitro)
      AND (@solo_principal = 0 OR v.rol = 'PRINCIPAL')
    ORDER BY v.arbitro, v.fecha_hora_local;
END;
GO


/*
  usp_OcupacionPublicitaria
  Dos resultados:
    1. Por partido: el anunciante exhibido en cada uno de los cuatro espacios
       ("(libre)" si no hay), los espacios ocupados, los ingresos en dólares y
       en @codigo_moneda (cotización vigente en la fecha del partido), y
       cuántos mercados publicitarios lo ven en prime time o con feriado,
       para comparar la ocupación con esas variables.
    2. Por sede, con una fila de TOTAL: partidos, espacios disponibles y
       ocupados, porcentaje de ocupación e ingresos.
  Valida que la sede y el partido existan y que la moneda sea USD o tenga
  alguna cotización cargada.
  Ej.: EXEC Reportes.usp_OcupacionPublicitaria @codigo_moneda = 'ARS';
*/
CREATE OR ALTER PROCEDURE Reportes.usp_OcupacionPublicitaria
    @id_sede        INT         = NULL,
    @id_partido     INT         = NULL,
    @codigo_moneda  VARCHAR(10) = 'USD'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @codigo_moneda = UPPER(ISNULL(NULLIF(TRIM(@codigo_moneda), ''), 'USD'));

    IF @id_sede IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.SEDE WHERE id_sede = @id_sede)
        SET @errores += @salto_linea + N'- No existe la sede con id ' + CAST(@id_sede AS NVARCHAR(10)) + N'.';

    IF @id_partido IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE id_partido = @id_partido)
        SET @errores += @salto_linea + N'- No existe el partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';

    IF @codigo_moneda <> 'USD'
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.COTIZACION WHERE codigo_moneda = @codigo_moneda)
        SET @errores += @salto_linea + N'- La moneda ' + @codigo_moneda + N' no tiene cotizaciones cargadas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_OcupacionPublicitaria: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DECLARE @por_partido TABLE (
        id_partido              INT PRIMARY KEY,
        id_sede                 INT,
        sede                    NVARCHAR(200),
        numero_partido          TINYINT,
        fase                    VARCHAR(15),
        fecha_hora_local        DATETIME2(0),
        partido                 NVARCHAR(200),
        espacio_1               NVARCHAR(150),
        espacio_2               NVARCHAR(150),
        espacio_3               NVARCHAR(150),
        espacio_4               NVARCHAR(150),
        espacios                INT,
        espacios_ocupados       INT,
        ingresos_usd            DECIMAL(19,2),
        ingresos_moneda         DECIMAL(19,2),
        mercados_en_prime_time  INT,
        mercados_con_feriado    INT
    );

    WITH por_partido AS (
        SELECT id_partido, id_sede, sede, numero_partido, fase, fecha_hora_local, partido,
               MAX(IIF(numero_espacio = 1, ISNULL(anunciante, N'(libre)'), N'')) AS espacio_1,
               MAX(IIF(numero_espacio = 2, ISNULL(anunciante, N'(libre)'), N'')) AS espacio_2,
               MAX(IIF(numero_espacio = 3, ISNULL(anunciante, N'(libre)'), N'')) AS espacio_3,
               MAX(IIF(numero_espacio = 4, ISNULL(anunciante, N'(libre)'), N'')) AS espacio_4,
               COUNT(*)                                                          AS espacios,
               SUM(CAST(ocupado AS INT))                                         AS espacios_ocupados,
               SUM(IIF(ocupado = 1, costo_usd, 0))                               AS ingresos_usd
        FROM Reportes.vw_OcupacionPublicitaria
        WHERE (@id_sede IS NULL OR id_sede = @id_sede)
          AND (@id_partido IS NULL OR id_partido = @id_partido)
        GROUP BY id_partido, id_sede, sede, numero_partido, fase, fecha_hora_local, partido
    )
    INSERT INTO @por_partido
    SELECT pp.id_partido, pp.id_sede, pp.sede, pp.numero_partido, pp.fase, pp.fecha_hora_local, pp.partido,
           pp.espacio_1, pp.espacio_2, pp.espacio_3, pp.espacio_4, pp.espacios, pp.espacios_ocupados,
           ISNULL(pp.ingresos_usd, 0),
           ISNULL(pp.ingresos_usd, 0) * c.unidades_por_usd,
           ISNULL(pt.en_prime_time, 0),
           ISNULL(pt.con_feriado, 0)
    FROM por_partido AS pp
    OUTER APPLY DatosGenerales.fn_CotizacionVigente(@codigo_moneda, CAST(pp.fecha_hora_local AS DATE)) AS c
    LEFT JOIN (SELECT v.id_partido,
                      SUM(CAST(v.en_prime_time AS INT)) AS en_prime_time,
                      SUM(CAST(v.es_feriado AS INT))    AS con_feriado
               FROM Reportes.vw_PrimeTimePorMercado AS v
               WHERE v.es_mercado_publicitario = 1
               GROUP BY v.id_partido) AS pt ON pt.id_partido = pp.id_partido;

    SELECT sede, numero_partido, fase, fecha_hora_local, partido,
           espacio_1, espacio_2, espacio_3, espacio_4, espacios_ocupados,
           ingresos_usd, @codigo_moneda AS moneda, ingresos_moneda,
           mercados_en_prime_time, mercados_con_feriado
    FROM @por_partido
    ORDER BY sede, fecha_hora_local;

    SELECT ISNULL(sede, N'TOTAL')                                                      AS sede,
           COUNT(*)                                                                    AS partidos,
           SUM(espacios)                                                               AS espacios_disponibles,
           SUM(espacios_ocupados)                                                      AS espacios_ocupados,
           CAST(100.0 * SUM(espacios_ocupados) / NULLIF(SUM(espacios), 0) AS DECIMAL(5,1)) AS porcentaje_ocupacion,
           SUM(ingresos_usd)                                                           AS ingresos_usd,
           @codigo_moneda                                                              AS moneda,
           SUM(ingresos_moneda)                                                        AS ingresos_moneda
    FROM @por_partido
    GROUP BY GROUPING SETS ((id_sede, sede), ())
    ORDER BY GROUPING(sede), sede;
END;
GO


/*
  usp_MatrizPrimeTime
  Tabla cruzada (PIVOT) con un partido por fila y un mercado por columna:
  "SI" si el horario del partido cae en prime time en ese mercado, "NO" si
  no, con " + FERIADO" si ese día es feriado allí. mercados_en_prime_time
  cuenta los SI de la fila. Los mercados son los países de interés de alguna
  pieza (@solo_mercados_publicitarios = 1) o todos los países.
  Las columnas dependen de los países cargados, por eso el PIVOT se arma con
  SQL dinámico; los nombres van con QUOTENAME y los filtros como parámetros
  de sp_executesql.
  Ej.: EXEC Reportes.usp_MatrizPrimeTime @fase = 'GRUPOS';
*/
CREATE OR ALTER PROCEDURE Reportes.usp_MatrizPrimeTime
    @fase                         VARCHAR(15) = NULL,
    @solo_mercados_publicitarios  BIT         = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @columnas    NVARCHAR(MAX);
    DECLARE @sql         NVARCHAR(MAX);

    SET @fase = UPPER(NULLIF(TRIM(@fase), ''));
    SET @solo_mercados_publicitarios = ISNULL(@solo_mercados_publicitarios, 1);

    IF @fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')
        SET @errores += @salto_linea + N'- La fase "' + @fase + N'" no existe.';

    SELECT @columnas = STRING_AGG(CAST(QUOTENAME(pa.nombre) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY pa.nombre)
    FROM DatosGenerales.PAIS AS pa
    WHERE @solo_mercados_publicitarios = 0
       OR EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi WHERE ppi.id_pais = pa.id_pais);

    IF @columnas IS NULL
        SET @errores += @salto_linea + N'- No hay mercados: ninguna pieza publicitaria tiene países de interés.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_MatrizPrimeTime: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @sql = N'
SELECT numero_partido, fase, fecha_hora_utc, partido, mercados_en_prime_time, ' + @columnas + N'
FROM (SELECT v.numero_partido,
             v.fase,
             v.fecha_hora_utc,
             v.partido,
             SUM(CAST(v.en_prime_time AS INT)) OVER (PARTITION BY v.id_partido) AS mercados_en_prime_time,
             v.mercado,
             CONCAT(IIF(v.en_prime_time = 1, N''SI'', N''NO''), IIF(v.es_feriado = 1, N'' + FERIADO'', N'''')) AS valor
      FROM Reportes.vw_PrimeTimePorMercado AS v
      WHERE (@fase IS NULL OR v.fase = @fase)
        AND (@solo_mercados_publicitarios = 0 OR v.es_mercado_publicitario = 1)) AS d
PIVOT (MAX(valor) FOR mercado IN (' + @columnas + N')) AS pv
ORDER BY fecha_hora_utc, numero_partido;';

    EXEC sp_executesql @sql, N'@fase VARCHAR(15), @solo_mercados_publicitarios BIT',
                       @fase = @fase, @solo_mercados_publicitarios = @solo_mercados_publicitarios;
END;
GO


/*
  usp_SeleccionesYPlantillasXML
  Selecciones con su director técnico y el vector anidado de convocados
  (nombre, posición, club y dorsal), ordenados por puesto y dorsal. Con
  @incluir_bajas = 1 también figuran los dados de baja, con su <Baja>.
  Estructura:
    <Selecciones>
      <Seleccion id codigo_fifa nombre confederacion grupo>
        <DirectorTecnico/>
        <Convocados cantidad fecha_presentacion>
          <Jugador dorsal><Nombre/><Posicion/><Club/><Baja fecha motivo/></Jugador>
  Ej.: EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = 1;
*/
CREATE OR ALTER PROCEDURE Reportes.usp_SeleccionesYPlantillasXML
    @id_seleccion   INT = NULL,
    @incluir_bajas  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @incluir_bajas = ISNULL(@incluir_bajas, 0);

    IF @id_seleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @salto_linea + N'- No existe la selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_SeleccionesYPlantillasXML: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT (
        SELECT s.id_seleccion                                AS [@id],
               pa.codigo_fifa                                AS [@codigo_fifa],
               pa.nombre                                     AS [@nombre],
               s.confederacion                               AS [@confederacion],
               s.grupo                                       AS [@grupo],
               dt.director_tecnico                           AS [DirectorTecnico],
               (SELECT COUNT(*)                              AS [@cantidad],
                       l.fecha_presentacion                  AS [@fecha_presentacion],
                       (SELECT j.dorsal                                AS [@dorsal],
                               CONCAT(j.nombre, N' ', j.apellido)      AS [Nombre],
                               j.posicion_habitual                     AS [Posicion],
                               j.club_origen                           AS [Club],
                               j.fecha_baja                            AS [Baja/@fecha],
                               j.motivo_baja                           AS [Baja/@motivo]
                        FROM Torneo.JUGADOR AS j
                        WHERE j.id_lista = l.id_lista
                          AND (@incluir_bajas = 1 OR j.fecha_baja IS NULL)
                        ORDER BY CASE j.posicion_habitual WHEN 'ARQUERO' THEN 1 WHEN 'DEFENSOR' THEN 2
                                                          WHEN 'MEDIOCAMPISTA' THEN 3 ELSE 4 END,
                                 j.dorsal, j.fecha_baja
                        FOR XML PATH('Jugador'), TYPE)
                FROM Torneo.JUGADOR AS j
                WHERE j.id_lista = l.id_lista
                  AND (@incluir_bajas = 1 OR j.fecha_baja IS NULL)
                FOR XML PATH('Convocados'), TYPE)
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
        LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
        OUTER APPLY (SELECT TOP (1) CONCAT(ct.nombre, N' ', ct.apellido) AS director_tecnico
                     FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                     WHERE ct.id_seleccion = s.id_seleccion
                       AND ct.rol = 'DIRECTOR_TECNICO') AS dt
        WHERE @id_seleccion IS NULL OR s.id_seleccion = @id_seleccion
        ORDER BY s.grupo, pa.nombre
        FOR XML PATH('Seleccion'), ROOT('Selecciones'), TYPE
    ) AS reporte_selecciones;
END;
GO


/*
  usp_Resultados
  Dos resultados:
    1. Tabla de posiciones de los grupos (Reportes.vw_TablaPosiciones). Con
       @id_seleccion, solo su grupo; con una @fase que no es GRUPOS, vacía.
    2. Resultados de los partidos, de la primera fase a la final: resultado,
       ganador y goles de cada lado con autor y minuto.
  Ej.: EXEC Reportes.usp_Resultados @fase = 'GRUPOS';
*/
CREATE OR ALTER PROCEDURE Reportes.usp_Resultados
    @fase          VARCHAR(15) = NULL,
    @id_seleccion  INT         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @fase = UPPER(NULLIF(TRIM(@fase), ''));

    IF @fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')
        SET @errores += @salto_linea + N'- La fase "' + @fase + N'" no existe.';

    IF @id_seleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @salto_linea + N'- No existe la selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Reportes.usp_Resultados: no se pudo generar el reporte.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT t.grupo, t.posicion, t.seleccion, t.pj, t.pg, t.pe, t.pp, t.gf, t.gc, t.dg, t.pts
    FROM Reportes.vw_TablaPosiciones AS t
    WHERE (@fase IS NULL OR @fase = 'GRUPOS')
      AND (@id_seleccion IS NULL
           OR t.grupo = (SELECT grupo FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion))
    ORDER BY t.grupo, t.posicion;

    SELECT r.fase, r.grupo, r.numero_partido, r.fecha_hora_local, r.nombre_estadio,
           r.seleccion_local, r.resultado, r.seleccion_visitante, r.ganador,
           r.goles_del_local, r.goles_del_visitante, r.asistencia, r.estado
    FROM Reportes.vw_Resultados AS r
    WHERE (@fase IS NULL OR r.fase = @fase)
      AND (@id_seleccion IS NULL OR @id_seleccion IN (r.id_seleccion_local, r.id_seleccion_visitante))
    ORDER BY r.orden_fase, r.fecha_hora_utc, r.numero_partido;
END;
GO
