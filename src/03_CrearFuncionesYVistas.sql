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

 Fecha: 25/10/2026
 Archivo: 03_CrearFuncionesYVistas.sql
 Objetivo: Crear las funciones y vistas que usan los SP y las consultas del
           sistema: parámetros del sistema, fixture filtrable, equipo en
           cancha en cualquier minuto, marcador según los goles cargados,
           sanciones y suspensiones, selecciones en competencia, simulación
           de prime time, prioridad de piezas publicitarias, historial de
           titularidad, goleadores e historial de árbitros.
           Requiere haber ejecutado 00, 01 y 02. Su script de testing es
           53_Test_FuncionesYVistas.sql.
================================================================================

 Convenciones:
   - Todas las funciones son de tabla en línea (RETURNS TABLE): el optimizador
     las expande dentro de la consulta que las usa, como si fueran una vista
     con parámetros.
   - Un parámetro en NULL en fn_Fixture significa "sin filtrar".
   - Instante de un evento: minuto * 100 + minuto_adicional. Así 45+2 (4502)
     queda antes que 46 (4600) y 90+5 (9005) antes que 91 (9100). Un evento
     en el mismo instante que un cambio se considera posterior al cambio.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   DatosGenerales
   ============================================================================ */

/*
  fn_ParametrosDelSistema
  Códigos de PARAMETRO_REGLAMENTO que usan los SP y las funciones, con el rango
  de valores que admite cada uno. Los SP de ABM de parámetros validan contra
  esta lista y no permiten borrar estos códigos.
*/
CREATE OR ALTER FUNCTION DatosGenerales.fn_ParametrosDelSistema ()
RETURNS TABLE
AS
RETURN
    SELECT p.codigo, p.valor_minimo, p.valor_maximo
    FROM (VALUES
        ('AMARILLAS_PARA_SUSPENSION',         1,  10),
        ('FECHAS_SUSPENSION_ACUMULACION',     0,  10),
        ('FECHAS_SUSPENSION_DOBLE_AMARILLA',  0,  10),
        ('FECHAS_SUSPENSION_ROJA_DIRECTA',    0,  10),
        ('LIMPIEZA_AMARILLAS_TRAS_GRUPOS',    0,   1),
        ('LIMPIEZA_AMARILLAS_TRAS_CUARTOS',   0,   1),
        ('MAX_CAMBIOS',                       1,  11),
        ('MAX_VENTANAS',                      1,  11),
        ('CAMBIOS_EXTRA_ALARGUE',             0,   5),
        ('VENTANAS_EXTRA_ALARGUE',            0,   5),
        ('MIN_CONVOCADOS',                   11,  99),
        ('MAX_CONVOCADOS',                   11,  99),
        ('MIN_ARQUEROS_CONVOCADOS',           1,   5),
        ('SELECCIONES_POR_GRUPO',             2,   8),
        ('PRIME_TIME_DESDE',                  0,  23),
        ('PRIME_TIME_HASTA',                  0,  23),
        ('PBI_FRANJA_MILES_USD',              1, 255)
    ) AS p (codigo, valor_minimo, valor_maximo);
GO


/* ============================================================================
   Torneo
   ============================================================================ */

/*
  vw_Fixture
  Fixture completo con sede, selecciones y resultado. Las selecciones que
  todavía no se conocen (cruces de eliminatorias) se muestran como "A definir".
*/
CREATE OR ALTER VIEW Torneo.vw_Fixture
AS
SELECT p.id_partido,
       p.numero_partido,
       p.fase,
       IIF(p.fase = 'GRUPOS', sl.grupo, NULL)              AS grupo,
       p.fecha_hora_local,
       p.fecha_hora_utc,
       s.id_sede,
       s.nombre_estadio,
       s.ciudad,
       ps.nombre                                           AS pais_sede,
       s.huso_horario,
       p.id_seleccion_local,
       ISNULL(pl.nombre, 'A definir')                      AS seleccion_local,
       p.id_seleccion_visitante,
       ISNULL(pv.nombre, 'A definir')                      AS seleccion_visitante,
       p.goles_local,
       p.goles_visitante,
       p.penales_local,
       p.penales_visitante,
       CASE WHEN p.goles_local IS NULL THEN NULL
            ELSE CONCAT(p.goles_local, ' - ', p.goles_visitante,
                        IIF(p.penales_local IS NULL, '',
                            CONCAT(' (', p.penales_local, ' - ', p.penales_visitante, ' por penales)')))
       END                                                 AS resultado,
       p.asistencia,
       p.estado
FROM Torneo.PARTIDO AS p
INNER JOIN Torneo.SEDE AS s ON s.id_sede = p.id_sede
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
LEFT JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
LEFT JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
LEFT JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
LEFT JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais;
GO


/*
  fn_Fixture
  Fixture filtrado por sede, fase, selección o fecha local del partido. Cada
  filtro en NULL no se aplica, así que fn_Fixture(NULL, NULL, NULL, NULL)
  devuelve el fixture completo.
  Ej.: SELECT * FROM Torneo.fn_Fixture(NULL, 'GRUPOS', 3, NULL) ORDER BY fecha_hora_utc;
*/
CREATE OR ALTER FUNCTION Torneo.fn_Fixture
(
    @id_sede      INT,
    @fase         VARCHAR(15),
    @id_seleccion INT,
    @fecha        DATE
)
RETURNS TABLE
AS
RETURN
    SELECT f.id_partido, f.numero_partido, f.fase, f.grupo, f.fecha_hora_local, f.fecha_hora_utc,
           f.nombre_estadio, f.ciudad, f.pais_sede, f.seleccion_local, f.seleccion_visitante,
           f.resultado, f.asistencia, f.estado
    FROM Torneo.vw_Fixture AS f
    WHERE (@id_sede IS NULL OR f.id_sede = @id_sede)
      AND (@fase IS NULL OR f.fase = @fase)
      AND (@id_seleccion IS NULL OR @id_seleccion IN (f.id_seleccion_local, f.id_seleccion_visitante))
      AND (@fecha IS NULL OR CAST(f.fecha_hora_local AS DATE) = @fecha);
GO


/*
  fn_SeleccionesEnCompetencia
  Selecciones que pasaron a la eliminación directa y todavía no perdieron un
  partido de esa etapa. Es el criterio de "país que puede cruzarse" para la
  advertencia de designación arbitral: el cuadro de eliminatorias no está
  modelado, así que se considera que puede cruzarse cualquier selección que
  siga en competencia.
*/
CREATE OR ALTER FUNCTION Torneo.fn_SeleccionesEnCompetencia ()
RETURNS TABLE
AS
RETURN
    SELECT s.id_seleccion, s.id_pais
    FROM Torneo.SELECCION AS s
    WHERE EXISTS (SELECT 1
                  FROM Torneo.PARTIDO AS p
                  WHERE p.fase <> 'GRUPOS'
                    AND s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante))
      AND NOT EXISTS (SELECT 1
                      FROM Torneo.PARTIDO AS p
                      WHERE p.fase <> 'GRUPOS'
                        AND p.estado = 'FINALIZADO'
                        AND ((p.id_seleccion_local = s.id_seleccion
                              AND (p.goles_local < p.goles_visitante
                                   OR (p.goles_local = p.goles_visitante AND p.penales_local < p.penales_visitante)))
                          OR (p.id_seleccion_visitante = s.id_seleccion
                              AND (p.goles_visitante < p.goles_local
                                   OR (p.goles_local = p.goles_visitante AND p.penales_visitante < p.penales_local)))));
GO


/* ============================================================================
   DesarrolloPartido
   ============================================================================ */

/*
  fn_EquipoEnCancha
  Reconstruye los jugadores de una selección que estaban en cancha en un
  instante del partido: los titulares que no salieron, más los suplentes que
  entraron y no salieron, menos los expulsados.
  Ej.: SELECT * FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 90, 3);
  Para el final del partido (definición por penales) se usa minuto 120 y
  adicional 99.
*/
CREATE OR ALTER FUNCTION DesarrolloPartido.fn_EquipoEnCancha
(
    @id_partido       INT,
    @id_seleccion     INT,
    @minuto           TINYINT,
    @minuto_adicional TINYINT
)
RETURNS TABLE
AS
RETURN
    SELECT j.id_jugador,
           j.dorsal,
           j.apellido,
           j.nombre,
           a.es_titular,
           a.posicion_en_cancha,
           ingreso.minuto           AS minuto_ingreso,
           ingreso.minuto_adicional AS adicional_ingreso
    FROM DesarrolloPartido.FORMACION AS f
    INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
    OUTER APPLY (SELECT c.minuto, c.minuto_adicional
                 FROM DesarrolloPartido.CAMBIO AS c
                 WHERE c.id_partido = f.id_partido
                   AND c.id_jugador_entra = a.id_jugador) AS ingreso
    WHERE f.id_partido = @id_partido
      AND f.id_seleccion = @id_seleccion
      AND (a.es_titular = 1
           OR ingreso.minuto * 100 + ingreso.minuto_adicional <= @minuto * 100 + @minuto_adicional)
      AND NOT EXISTS (SELECT 1
                      FROM DesarrolloPartido.CAMBIO AS c
                      WHERE c.id_partido = f.id_partido
                        AND c.id_jugador_sale = a.id_jugador
                        AND c.minuto * 100 + c.minuto_adicional <= @minuto * 100 + @minuto_adicional)
      AND NOT EXISTS (SELECT 1
                      FROM DesarrolloPartido.AMONESTACION AS r
                      WHERE r.id_partido = f.id_partido
                        AND r.id_jugador = a.id_jugador
                        AND r.tipo_tarjeta = 'ROJA'
                        AND r.minuto * 100 + r.minuto_adicional <= @minuto * 100 + @minuto_adicional);
GO


/*
  fn_MarcadorSegunGoles
  Marcador que resulta de los goles cargados en GOL. Un gol en contra suma
  para el rival del autor. Los goles del período PENALES son los penales
  convertidos en la definición y no suman al marcador. goles_*_90 son los del
  tiempo reglamentario (incluidos sus adicionales), para saber si hubo alargue.
*/
CREATE OR ALTER FUNCTION DesarrolloPartido.fn_MarcadorSegunGoles (@id_partido INT)
RETURNS TABLE
AS
RETURN
    WITH goles AS (
        SELECT g.periodo,
               g.minuto,
               p.id_seleccion_local,
               p.id_seleccion_visitante,
               IIF(tg.es_en_contra = 1,
                   IIF(l.id_seleccion = p.id_seleccion_local, p.id_seleccion_visitante, p.id_seleccion_local),
                   l.id_seleccion) AS id_seleccion_que_suma
        FROM DesarrolloPartido.GOL AS g
        INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
        INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
        WHERE g.id_partido = @id_partido
    )
    SELECT COUNT(*) AS goles_registrados,
           ISNULL(SUM(IIF(periodo <> 'PENALES' AND id_seleccion_que_suma = id_seleccion_local, 1, 0)), 0)     AS goles_local,
           ISNULL(SUM(IIF(periodo <> 'PENALES' AND id_seleccion_que_suma = id_seleccion_visitante, 1, 0)), 0) AS goles_visitante,
           ISNULL(SUM(IIF((periodo IN ('PRIMER_TIEMPO', 'SEGUNDO_TIEMPO') OR (periodo = 'ADICIONALES' AND minuto IN (45, 90)))
                          AND id_seleccion_que_suma = id_seleccion_local, 1, 0)), 0)                          AS goles_local_90,
           ISNULL(SUM(IIF((periodo IN ('PRIMER_TIEMPO', 'SEGUNDO_TIEMPO') OR (periodo = 'ADICIONALES' AND minuto IN (45, 90)))
                          AND id_seleccion_que_suma = id_seleccion_visitante, 1, 0)), 0)                      AS goles_visitante_90,
           ISNULL(SUM(IIF(periodo = 'PENALES' AND id_seleccion_que_suma = id_seleccion_local, 1, 0)), 0)      AS penales_local,
           ISNULL(SUM(IIF(periodo = 'PENALES' AND id_seleccion_que_suma = id_seleccion_visitante, 1, 0)), 0)  AS penales_visitante,
           ISNULL(SUM(IIF(periodo = 'PENALES', 1, 0)), 0)                                                    AS penales_registrados
    FROM goles;
GO


/*
  fn_Sanciones
  Sanciones de partidos de suspensión que generaron las tarjetas de cada
  jugador, una fila por jugador y partido de origen. Los criterios salen de
  PARAMETRO_REGLAMENTO:
    - Acumulación: cada AMARILLAS_PARA_SUSPENSION partidos distintos con
      amarilla, el jugador recibe FECHAS_SUSPENSION_ACUMULACION partidos. No
      cuentan las dos amarillas que terminaron en expulsión por doble amarilla.
      Las amarillas se cuentan por tramo: si LIMPIEZA_AMARILLAS_TRAS_GRUPOS
      vale 1 se anulan al terminar la fase de grupos, y si
      LIMPIEZA_AMARILLAS_TRAS_CUARTOS vale 1, al terminar los cuartos de final.
      Las suspensiones ya generadas no se anulan.
    - Expulsión: FECHAS_SUSPENSION_DOBLE_AMARILLA o FECHAS_SUSPENSION_ROJA_DIRECTA.
  Si en un mismo partido se juntan dos sanciones (por ejemplo, la segunda
  amarilla acumulada y una roja directa), los partidos se suman.
*/
CREATE OR ALTER FUNCTION DesarrolloPartido.fn_Sanciones ()
RETURNS TABLE
AS
RETURN
    WITH parametros AS (
        SELECT (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                WHERE codigo = 'AMARILLAS_PARA_SUSPENSION')                      AS amarillas_para_suspension,
               (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                WHERE codigo = 'FECHAS_SUSPENSION_ACUMULACION')                  AS fechas_acumulacion,
               (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                WHERE codigo = 'FECHAS_SUSPENSION_DOBLE_AMARILLA')               AS fechas_doble_amarilla,
               (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                WHERE codigo = 'FECHAS_SUSPENSION_ROJA_DIRECTA')                 AS fechas_roja_directa,
               ISNULL((SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                       WHERE codigo = 'LIMPIEZA_AMARILLAS_TRAS_GRUPOS'), 0)      AS limpieza_grupos,
               ISNULL((SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                       WHERE codigo = 'LIMPIEZA_AMARILLAS_TRAS_CUARTOS'), 0)     AS limpieza_cuartos
    ),
    partidos_con_amarilla AS (
        SELECT DISTINCT
               a.id_jugador,
               a.id_partido,
               p.fecha_hora_utc,
               CASE WHEN p.fase = 'GRUPOS' THEN 1
                    WHEN p.fase IN ('DIECISEISAVOS', 'OCTAVOS', 'CUARTOS') THEN 1 + prm.limpieza_grupos
                    ELSE 1 + prm.limpieza_grupos + prm.limpieza_cuartos
               END AS tramo
        FROM DesarrolloPartido.AMONESTACION AS a
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
        CROSS JOIN parametros AS prm
        WHERE a.tipo_tarjeta = 'AMARILLA'
          AND a.id_jugador IS NOT NULL
          AND NOT EXISTS (SELECT 1
                          FROM DesarrolloPartido.AMONESTACION AS r
                          WHERE r.id_partido = a.id_partido
                            AND r.id_jugador = a.id_jugador
                            AND r.es_doble_amarilla = 1)
    ),
    acumuladas AS (
        SELECT id_jugador,
               id_partido,
               ROW_NUMBER() OVER (PARTITION BY id_jugador, tramo
                                  ORDER BY fecha_hora_utc, id_partido) AS amarillas_acumuladas
        FROM partidos_con_amarilla
    ),
    sanciones AS (
        SELECT ac.id_jugador,
               ac.id_partido,
               'ACUMULACION DE AMARILLAS' AS motivo,
               prm.fechas_acumulacion     AS partidos
        FROM acumuladas AS ac
        CROSS JOIN parametros AS prm
        WHERE ac.amarillas_acumuladas % prm.amarillas_para_suspension = 0
        UNION ALL
        SELECT r.id_jugador,
               r.id_partido,
               IIF(r.es_doble_amarilla = 1, 'DOBLE AMARILLA', 'ROJA DIRECTA'),
               IIF(r.es_doble_amarilla = 1, prm.fechas_doble_amarilla, prm.fechas_roja_directa)
        FROM DesarrolloPartido.AMONESTACION AS r
        CROSS JOIN parametros AS prm
        WHERE r.tipo_tarjeta = 'ROJA'
          AND r.id_jugador IS NOT NULL
    )
    SELECT s.id_jugador,
           l.id_seleccion,
           s.id_partido                AS id_partido_origen,
           STRING_AGG(s.motivo, ' + ') AS motivo,
           SUM(s.partidos)             AS partidos_de_suspension
    FROM sanciones AS s
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    GROUP BY s.id_jugador, l.id_seleccion, s.id_partido
    HAVING SUM(s.partidos) > 0;
GO


/*
  fn_JugadoresSuspendidos
  Jugadores de las dos selecciones de un partido que están suspendidos para
  ese partido: los que tienen una sanción de un partido anterior que todavía
  no terminaron de cumplir. Cada partido posterior de su selección (que no
  esté SUSPENDIDO) cuenta como una fecha cumplida.
  partido_que_cumple indica qué fecha de la suspensión es este partido.
*/
CREATE OR ALTER FUNCTION DesarrolloPartido.fn_JugadoresSuspendidos (@id_partido INT)
RETURNS TABLE
AS
RETURN
    SELECT s.id_jugador,
           s.id_seleccion,
           s.motivo,
           s.id_partido_origen,
           o.numero_partido       AS numero_partido_origen,
           s.partidos_de_suspension,
           c.fechas               AS partido_que_cumple
    FROM DesarrolloPartido.fn_Sanciones() AS s
    INNER JOIN Torneo.PARTIDO AS o ON o.id_partido = s.id_partido_origen
    INNER JOIN Torneo.PARTIDO AS x ON x.id_partido = @id_partido
                                  AND s.id_seleccion IN (x.id_seleccion_local, x.id_seleccion_visitante)
    CROSS APPLY (SELECT COUNT(*) AS fechas
                 FROM Torneo.PARTIDO AS q
                 WHERE s.id_seleccion IN (q.id_seleccion_local, q.id_seleccion_visitante)
                   AND q.estado <> 'SUSPENDIDO'
                   AND q.fecha_hora_utc > o.fecha_hora_utc
                   AND q.fecha_hora_utc <= x.fecha_hora_utc) AS c
    WHERE o.fecha_hora_utc < x.fecha_hora_utc
      AND c.fechas BETWEEN 1 AND s.partidos_de_suspension;
GO


/*
  vw_HistorialTitularidad
  Una fila por jugador y partido en el que figuró en la formación: si fue
  titular o suplente, en qué minuto entró o salió y si fue expulsado.
*/
CREATE OR ALTER VIEW DesarrolloPartido.vw_HistorialTitularidad
AS
SELECT j.id_jugador,
       j.apellido,
       j.nombre,
       j.dorsal,
       ps.nombre                                              AS seleccion,
       p.id_partido,
       p.numero_partido,
       p.fase,
       p.fecha_hora_local,
       ISNULL(pr.nombre, 'A definir')                         AS rival,
       IIF(a.es_titular = 1, 'TITULAR', 'SUPLENTE')           AS condicion,
       a.posicion_en_cancha,
       IIF(a.es_titular = 1 OR ce.id_cambio IS NOT NULL, 1, 0) AS jugo,
       CASE WHEN ce.id_cambio IS NULL THEN NULL
            ELSE CONCAT(ce.minuto, IIF(ce.minuto_adicional > 0, CONCAT('+', ce.minuto_adicional), ''))
       END                                                    AS minuto_ingreso,
       CASE WHEN cs.id_cambio IS NULL THEN NULL
            ELSE CONCAT(cs.minuto, IIF(cs.minuto_adicional > 0, CONCAT('+', cs.minuto_adicional), ''))
       END                                                    AS minuto_salida,
       CASE WHEN roja.minuto IS NULL THEN NULL
            ELSE CONCAT(roja.minuto, IIF(roja.minuto_adicional > 0, CONCAT('+', roja.minuto_adicional), ''))
       END                                                    AS minuto_expulsion
FROM DesarrolloPartido.ALINEACION AS a
INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
LEFT JOIN Torneo.SELECCION AS sr
       ON sr.id_seleccion = IIF(p.id_seleccion_local = f.id_seleccion, p.id_seleccion_visitante, p.id_seleccion_local)
LEFT JOIN DatosGenerales.PAIS AS pr ON pr.id_pais = sr.id_pais
LEFT JOIN DesarrolloPartido.CAMBIO AS ce ON ce.id_partido = p.id_partido AND ce.id_jugador_entra = a.id_jugador
LEFT JOIN DesarrolloPartido.CAMBIO AS cs ON cs.id_partido = p.id_partido AND cs.id_jugador_sale = a.id_jugador
OUTER APPLY (SELECT TOP (1) r.minuto, r.minuto_adicional
             FROM DesarrolloPartido.AMONESTACION AS r
             WHERE r.id_partido = p.id_partido
               AND r.id_jugador = a.id_jugador
               AND r.tipo_tarjeta = 'ROJA') AS roja;
GO


/*
  vw_Goleadores
  Goles por jugador. No cuentan los goles en contra ni los penales de la
  definición por penales. Para la tabla del torneo se ordena por goles; para
  la de una selección se filtra por id_seleccion.
*/
CREATE OR ALTER VIEW DesarrolloPartido.vw_Goleadores
AS
SELECT j.id_jugador,
       j.apellido,
       j.nombre,
       s.id_seleccion,
       ps.nombre                    AS seleccion,
       COUNT(*)                     AS goles,
       COUNT(DISTINCT g.id_partido) AS partidos_con_gol
FROM DesarrolloPartido.GOL AS g
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
WHERE tg.es_en_contra = 0
  AND g.periodo <> 'PENALES'
GROUP BY j.id_jugador, j.apellido, j.nombre, s.id_seleccion, ps.nombre;
GO


/* ============================================================================
   Arbitraje
   ============================================================================ */

/*
  vw_HistorialArbitro
  Partidos de cada árbitro con su rol, el resultado, las tarjetas del partido
  y el informe y la sanción post-partido que haya recibido.
*/
CREATE OR ALTER VIEW Arbitraje.vw_HistorialArbitro
AS
SELECT ar.id_arbitro,
       ar.apellido,
       ar.nombre,
       pa.nombre                           AS pais,
       ar.categoria,
       d.rol,
       f.id_partido,
       f.numero_partido,
       f.fase,
       f.fecha_hora_local,
       f.seleccion_local,
       f.seleccion_visitante,
       f.resultado,
       f.estado,
       ISNULL(t.amarillas, 0)              AS amarillas_del_partido,
       ISNULL(t.rojas, 0)                  AS rojas_del_partido,
       d.informe_postpartido,
       d.sancion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Arbitraje.ARBITRO AS ar ON ar.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = ar.id_pais
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = d.id_partido
OUTER APPLY (SELECT SUM(IIF(am.tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
                    SUM(IIF(am.tipo_tarjeta = 'ROJA', 1, 0))     AS rojas
             FROM DesarrolloPartido.AMONESTACION AS am
             WHERE am.id_partido = d.id_partido) AS t;
GO


/* ============================================================================
   Publicidad
   ============================================================================ */

/*
  fn_MercadosEnPrimeTime
  Simulación de prime time: para cada país (mercado) muestra la hora local en
  que se juega el partido, a partir de la hora UTC y del huso del país, e
  indica si cae en prime time (de PRIME_TIME_DESDE inclusive a
  PRIME_TIME_HASTA exclusive; si DESDE es mayor que HASTA, la franja cruza la
  medianoche). AT TIME ZONE aplica el horario de verano de cada país.
  Ej.: SELECT * FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido) WHERE en_prime_time = 1;
*/
CREATE OR ALTER FUNCTION Publicidad.fn_MercadosEnPrimeTime (@id_partido INT)
RETURNS TABLE
AS
RETURN
    WITH parametros AS (
        SELECT (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRIME_TIME_DESDE') AS desde,
               (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRIME_TIME_HASTA') AS hasta
    )
    SELECT pa.id_pais,
           pa.nombre AS mercado,
           pa.huso_horario,
           hl.hora_local,
           CAST(CASE WHEN prm.desde < prm.hasta
                         THEN IIF(DATEPART(HOUR, hl.hora_local) >= prm.desde
                                  AND DATEPART(HOUR, hl.hora_local) < prm.hasta, 1, 0)
                     ELSE IIF(DATEPART(HOUR, hl.hora_local) >= prm.desde
                              OR DATEPART(HOUR, hl.hora_local) < prm.hasta, 1, 0)
                END AS BIT) AS en_prime_time,
           CAST(IIF(pa.id_pais IN (sl.id_pais, sv.id_pais), 1, 0) AS BIT) AS juega_el_partido
    FROM Torneo.PARTIDO AS p
    CROSS JOIN DatosGenerales.PAIS AS pa
    CROSS JOIN parametros AS prm
    LEFT JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
    LEFT JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
    CROSS APPLY (SELECT CONVERT(DATETIME2(0),
                                (p.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE pa.huso_horario) AS hora_local) AS hl
    WHERE p.id_partido = @id_partido;
GO


/*
  fn_PrioridadPiezas
  Propuesta de piezas para los espacios de un partido, en orden de prioridad.
  Son candidatas las piezas de campañas vigentes en la fecha local del
  partido que tengan al menos un mercado de interés. Criterio (documentado
  para el grupo), en este orden:
    1. dirigida_a_seleccion: la pieza apunta al país de alguna de las dos
       selecciones del partido.
    2. franja_pbi: franja de PBI per cápita (indicador NY.GDP.PCAP.CD, último
       año cargado) del mercado de la pieza con mayor poder adquisitivo. Las
       franjas son de PBI_FRANJA_MILES_USD miles de dólares, para que una
       diferencia chica de PBI no tape el criterio siguiente.
    3. mercados_en_prime_time: cuántos mercados de la pieza ven el partido en
       prime time (ver fn_MercadosEnPrimeTime).
    4. Desempate: PBI exacto y, por último, la pieza más antigua.
  De cada campaña se propone solo su mejor pieza, para que los cuatro
  espacios no los ocupe una misma campaña.
*/
CREATE OR ALTER FUNCTION Publicidad.fn_PrioridadPiezas (@id_partido INT)
RETURNS TABLE
AS
RETURN
    WITH parametros AS (
        SELECT ISNULL((SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                       WHERE codigo = 'PBI_FRANJA_MILES_USD'), 1) AS franja_miles
    ),
    partido AS (
        SELECT CAST(p.fecha_hora_local AS DATE) AS fecha_partido
        FROM Torneo.PARTIDO AS p
        WHERE p.id_partido = @id_partido
    ),
    pbi AS (
        SELECT ie.id_pais,
               ie.valor,
               ROW_NUMBER() OVER (PARTITION BY ie.id_pais ORDER BY ie.anio DESC) AS orden
        FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
        WHERE ie.codigo_indicador = 'NY.GDP.PCAP.CD'
    ),
    mercados AS (
        SELECT pz.id_pieza,
               pz.id_campania,
               CAST(m.juega_el_partido AS INT) AS juega,
               CAST(m.en_prime_time AS INT)    AS en_prime_time,
               ISNULL(pbi.valor, 0)            AS pbi_per_capita
        FROM partido AS pt
        INNER JOIN Publicidad.CAMPANIA AS c
                ON pt.fecha_partido BETWEEN c.fecha_inicio AND c.fecha_fin
        INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
        INNER JOIN Publicidad.PIEZA_PAIS_INTERES AS ppi ON ppi.id_pieza = pz.id_pieza
        INNER JOIN Publicidad.fn_MercadosEnPrimeTime(@id_partido) AS m ON m.id_pais = ppi.id_pais
        LEFT JOIN pbi ON pbi.id_pais = ppi.id_pais AND pbi.orden = 1
    ),
    piezas AS (
        SELECT m.id_pieza,
               m.id_campania,
               MAX(m.juega)          AS dirigida_a_seleccion,
               MAX(m.pbi_per_capita) AS pbi_per_capita_max,
               SUM(m.en_prime_time)  AS mercados_en_prime_time,
               COUNT(*)              AS mercados_de_interes
        FROM mercados AS m
        GROUP BY m.id_pieza, m.id_campania
    ),
    puntuadas AS (
        SELECT pz.id_pieza,
               pz.id_campania,
               pz.dirigida_a_seleccion,
               pz.pbi_per_capita_max,
               CAST(FLOOR(pz.pbi_per_capita_max / (prm.franja_miles * 1000.0)) AS INT) AS franja_pbi,
               pz.mercados_en_prime_time,
               pz.mercados_de_interes
        FROM piezas AS pz
        CROSS JOIN parametros AS prm
    ),
    mejor_de_cada_campania AS (
        SELECT pu.*,
               ROW_NUMBER() OVER (PARTITION BY pu.id_campania
                                  ORDER BY pu.dirigida_a_seleccion DESC, pu.franja_pbi DESC,
                                           pu.mercados_en_prime_time DESC, pu.pbi_per_capita_max DESC,
                                           pu.id_pieza) AS orden_en_campania
        FROM puntuadas AS pu
    )
    SELECT ROW_NUMBER() OVER (ORDER BY mc.dirigida_a_seleccion DESC, mc.franja_pbi DESC,
                                       mc.mercados_en_prime_time DESC, mc.pbi_per_capita_max DESC,
                                       mc.id_pieza) AS prioridad,
           mc.id_pieza,
           pz.titulo,
           c.nombre       AS campania,
           an.razon_social AS anunciante,
           mc.dirigida_a_seleccion,
           mc.franja_pbi,
           mc.mercados_en_prime_time,
           mc.pbi_per_capita_max,
           mc.mercados_de_interes
    FROM mejor_de_cada_campania AS mc
    INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = mc.id_pieza
    INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = mc.id_campania
    INNER JOIN Publicidad.ANUNCIANTE AS an ON an.id_anunciante = c.id_anunciante
    WHERE mc.orden_en_campania = 1;
GO


-- Evidencia: funciones y vistas creadas.
SELECT s.name AS esquema, o.name AS objeto, o.type_desc AS tipo, o.modify_date AS ultima_modificacion
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.type IN ('IF', 'FN', 'TF', 'V')
  AND s.name IN (N'DatosGenerales', N'Torneo', N'DesarrolloPartido', N'Arbitraje', N'Publicidad')
ORDER BY s.name, o.type_desc, o.name;
GO
