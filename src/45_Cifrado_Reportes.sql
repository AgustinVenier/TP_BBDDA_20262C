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

 Fecha: 08/11/2026
 Archivo: 45_Cifrado_Reportes.sql
 Objetivo: Modificar las vistas y los SP de Reportes que leen el nombre, el
           apellido o la fecha de nacimiento de jugadores, cuerpos técnicos y
           árbitros, para que los lean descifrados.
================================================================================

 Orden: lo ejecuta 38_Ejecutar_Cifrado.sql, después de 42_Cifrado_Tablas.sql.

 Cada objeto es el de 30_SP_Reportes.sql con un solo cambio: lee las personas
 de las vistas descifradas de 42 (Seguridad.vw_Jugador,
 Seguridad.vw_PersonaCuerpoTecnico, Seguridad.vw_Arbitro) en lugar de las
 tablas. Las vistas descifradas tienen las mismas columnas que las tablas, con
 el mismo nombre y tipo, así que el resto del código y el resultado no cambian,
 y lo que lee estos objetos (los otros SP de Reportes, Power BI, las consultas
 de la Entrega 9) tampoco.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
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
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = g.id_jugador_autor
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
WHERE tg.es_en_contra = 0
  AND g.periodo <> 'PENALES';
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
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
LEFT JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
LEFT JOIN Seguridad.vw_PersonaCuerpoTecnico AS ct ON ct.id_persona_ct = a.id_persona_ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = COALESCE(l.id_seleccion, ct.id_seleccion)
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
LEFT JOIN Arbitraje.DESIGNACION_ARBITRAL AS d ON d.id_partido = a.id_partido AND d.rol = 'PRINCIPAL'
LEFT JOIN Seguridad.vw_Arbitro AS ar ON ar.id_arbitro = d.id_arbitro;
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
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
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = sa.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = sa.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais;
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
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
INNER JOIN Seguridad.vw_Arbitro AS ar ON ar.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = ar.id_pais
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = d.id_partido
OUTER APPLY (SELECT SUM(IIF(am.tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
                    SUM(IIF(am.tipo_tarjeta = 'ROJA', 1, 0))     AS rojas
             FROM DesarrolloPartido.AMONESTACION AS am
             WHERE am.id_partido = d.id_partido
               AND d.rol = 'PRINCIPAL') AS t;
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
/*
  vw_Plantillas
  Un convocado por fila con su selección. activo = 0 son los dados de baja
  (reemplazados).
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
       j.fecha_nacimiento,
       CAST(IIF(j.fecha_baja IS NULL, 1, 0) AS BIT) AS activo,
       j.fecha_baja,
       j.motivo_baja
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_lista = l.id_lista;
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
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
OUTER APPLY (SELECT STRING_AGG(gs.detalle, N', ') WITHIN GROUP (ORDER BY gs.minuto, gs.minuto_adicional, gs.id_gol) AS detalle
             FROM (SELECT g.id_gol, g.minuto, g.minuto_adicional,
                          CONCAT(j.apellido, N' ', g.minuto,
                                 IIF(g.minuto_adicional > 0, CONCAT(N'+', g.minuto_adicional), N''), N'''',
                                 IIF(tg.es_en_contra = 1, N' (e/c)', N'')) AS detalle,
                          IIF(tg.es_en_contra = 1,
                              IIF(l.id_seleccion = f.id_seleccion_local, f.id_seleccion_visitante, f.id_seleccion_local),
                              l.id_seleccion) AS id_seleccion_que_suma
                   FROM DesarrolloPartido.GOL AS g
                   INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
                   INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = g.id_jugador_autor
                   INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                   WHERE g.id_partido = f.id_partido
                     AND g.periodo <> 'PENALES') AS gs
             WHERE gs.id_seleccion_que_suma = f.id_seleccion_local) AS gl
OUTER APPLY (SELECT STRING_AGG(gs.detalle, N', ') WITHIN GROUP (ORDER BY gs.minuto, gs.minuto_adicional, gs.id_gol) AS detalle
             FROM (SELECT g.id_gol, g.minuto, g.minuto_adicional,
                          CONCAT(j.apellido, N' ', g.minuto,
                                 IIF(g.minuto_adicional > 0, CONCAT(N'+', g.minuto_adicional), N''), N'''',
                                 IIF(tg.es_en_contra = 1, N' (e/c)', N'')) AS detalle,
                          IIF(tg.es_en_contra = 1,
                              IIF(l.id_seleccion = f.id_seleccion_local, f.id_seleccion_visitante, f.id_seleccion_local),
                              l.id_seleccion) AS id_seleccion_que_suma
                   FROM DesarrolloPartido.GOL AS g
                   INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
                   INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = g.id_jugador_autor
                   INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                   WHERE g.id_partido = f.id_partido
                     AND g.periodo <> 'PENALES') AS gs
             WHERE gs.id_seleccion_que_suma = f.id_seleccion_visitante) AS gv;
GO


-- Original en 30_SP_Reportes.sql. Cambio: lee las personas de las vistas descifradas de Seguridad.
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

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @incluir_bajas = ISNULL(@incluir_bajas, 0);

    IF @id_seleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- No existe la selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

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
                        FROM Seguridad.vw_Jugador AS j
                        WHERE j.id_lista = l.id_lista
                          AND (@incluir_bajas = 1 OR j.fecha_baja IS NULL)
                        ORDER BY CASE j.posicion_habitual WHEN 'ARQUERO' THEN 1 WHEN 'DEFENSOR' THEN 2
                                                          WHEN 'MEDIOCAMPISTA' THEN 3 ELSE 4 END,
                                 j.dorsal, j.fecha_baja
                        FOR XML PATH('Jugador'), TYPE)
                FROM Seguridad.vw_Jugador AS j
                WHERE j.id_lista = l.id_lista
                  AND (@incluir_bajas = 1 OR j.fecha_baja IS NULL)
                FOR XML PATH('Convocados'), TYPE)
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
        LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
        OUTER APPLY (SELECT TOP (1) CONCAT(ct.nombre, N' ', ct.apellido) AS director_tecnico
                     FROM Seguridad.vw_PersonaCuerpoTecnico AS ct
                     WHERE ct.id_seleccion = s.id_seleccion
                       AND ct.rol = 'DIRECTOR_TECNICO') AS dt
        WHERE @id_seleccion IS NULL OR s.id_seleccion = @id_seleccion
        ORDER BY s.grupo, pa.nombre
        FOR XML PATH('Seleccion'), ROOT('Selecciones'), TYPE
    ) AS reporte_selecciones;
END;
GO
