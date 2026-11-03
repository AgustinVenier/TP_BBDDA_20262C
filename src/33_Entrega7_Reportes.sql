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
 Archivo: 33_Entrega7_Reportes.sql
 Objetivo: Entrega 7. Ejecutar de punta a punta los reportes de
           30_SP_Reportes.sql para verlos a mano, sin verificaciones ni datos
           de prueba (para eso está 80_Test_SP_Reportes.sql).
           Requiere haber ejecutado 00 a 32: el torneo real
           (31_ImportarMundial2026.sql) con sus datos complementarios
           (32_DatosComplementarios.sql), que traen la publicidad.
================================================================================

 Cómo leer los resultados:
   - Cada reporte empieza con una grilla de una fila con su título (R1 a R7).
     Las grillas que siguen son el reporte.
   - Los reportes XML (R2 y R6) devuelven una celda: hacer clic en el XML para
     abrirlo en una ventana nueva.
   - Los parámetros no tienen valores fijos: se eligen de los datos cargados
     (el goleador, el corte con más suspensiones, un árbitro, una selección),
     así que el script sirve con cualquier juego de datos.
   - Sin publicidad cargada (sin el 32), R4 y R5 salen vacíos o con un aviso.

 Reportes:
   R1. Goleadores por selección, fase y torneo.            usp_Goleadores
   R2. Tarjetas por selección y jugador, con suspensiones  usp_TarjetasXML (XML)
       activas por acumulación.
   R3. Designaciones arbitrales y tarjetas que señalaron.  usp_DesignacionesArbitrales
   R4. Ocupación publicitaria por sede y partido, e        usp_OcupacionPublicitaria
       ingresos.
   R5. Matriz de prime time por mercado (pivot).           usp_MatrizPrimeTime
   R6. Selecciones con el vector anidado de convocados.    usp_SeleccionesYPlantillasXML (XML)
   R7. Resultados: posiciones de los grupos y partidos.    usp_Resultados
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Reportes.usp_Goleadores', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE estado = 'FINALIZADO')
BEGIN
    RAISERROR(N'Faltan los reportes o los datos: ejecutar 00 a 32.', 16, 1);
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   R1. Goleadores
   ============================================================================ */

SELECT N'R1. Goleadores del torneo (con los goles de cada fase)' AS reporte;
EXEC Reportes.usp_Goleadores;
GO

SELECT N'R1. Goleadores de la fase de grupos' AS reporte;
EXEC Reportes.usp_Goleadores @fase = 'GRUPOS';
GO

-- Los jugadores de la selección del máximo goleador; la posición del torneo se mantiene.
DECLARE @id_seleccion INT = (SELECT TOP (1) id_seleccion
                             FROM Reportes.vw_Goles
                             GROUP BY id_seleccion
                             ORDER BY COUNT(*) DESC, id_seleccion);
SELECT CONCAT(N'R1. Goleadores de ', seleccion_nombre) AS reporte
FROM (SELECT pa.nombre AS seleccion_nombre
      FROM Torneo.SELECCION AS s
      INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
      WHERE s.id_seleccion = @id_seleccion) AS x;
EXEC Reportes.usp_Goleadores @id_seleccion = @id_seleccion;
GO


/* ============================================================================
   R2. Tarjetas por selección y jugador, con suspensiones activas (XML)
   ============================================================================ */

SELECT N'R2. Tarjetas (XML) a hoy: cuenta todos los partidos jugados' AS reporte;
EXEC Reportes.usp_TarjetasXML;
GO

-- Un segundo antes del partido con más suspensiones activas: así se ve un
-- <SuspensionActiva> aunque el torneo ya haya terminado.
DECLARE @corte DATETIME2(0) = (
    SELECT TOP (1) DATEADD(SECOND, -1, p.fecha_hora_utc)
    FROM Torneo.PARTIDO AS p
    CROSS APPLY (SELECT COUNT(*) AS cantidad
                 FROM Reportes.fn_SuspensionesActivas(DATEADD(SECOND, -1, p.fecha_hora_utc))) AS s
    ORDER BY s.cantidad DESC, p.fecha_hora_utc);
SELECT CONCAT(N'R2. Tarjetas (XML) al corte con más suspensiones activas: ', CONVERT(VARCHAR(19), @corte, 120), N' UTC') AS reporte;
EXEC Reportes.usp_TarjetasXML @fecha_corte = @corte;
GO


/* ============================================================================
   R3. Designaciones arbitrales
   ============================================================================ */

SELECT N'R3. Designaciones arbitrales (todos los roles)' AS reporte;
EXEC Reportes.usp_DesignacionesArbitrales;
GO

SELECT N'R3. Solo los partidos dirigidos (árbitro principal)' AS reporte;
EXEC Reportes.usp_DesignacionesArbitrales @solo_principal = 1;
GO

-- El árbitro que señaló más tarjetas.
DECLARE @id_arbitro INT = (SELECT TOP (1) d.id_arbitro
                           FROM Reportes.vw_DesignacionesArbitrales AS d
                           GROUP BY d.id_arbitro
                           ORDER BY SUM(d.amarillas_senaladas + d.rojas_senaladas) DESC, d.id_arbitro);
IF @id_arbitro IS NOT NULL
BEGIN
    SELECT N'R3. Un solo árbitro: el que más tarjetas señaló' AS reporte;
    EXEC Reportes.usp_DesignacionesArbitrales @id_arbitro = @id_arbitro, @solo_principal = 1;
END
ELSE
    SELECT N'R3. La base no tiene árbitros designados: no hay detalle por árbitro.' AS reporte;
GO


/* ============================================================================
   R4. Ocupación publicitaria por sede y partido, e ingresos
   ============================================================================ */

-- Dos grillas: por partido (los cuatro espacios) y por sede (con el TOTAL).
SELECT N'R4. Ocupación publicitaria en dólares: por partido y, después, por sede' AS reporte;
EXEC Reportes.usp_OcupacionPublicitaria;
GO

-- Los mismos ingresos en pesos, con la cotización vigente en la fecha de cada partido.
IF EXISTS (SELECT 1 FROM DatosGenerales.COTIZACION WHERE codigo_moneda = 'ARS')
BEGIN
    SELECT N'R4. Ocupación publicitaria con los ingresos en pesos (ARS)' AS reporte;
    EXEC Reportes.usp_OcupacionPublicitaria @codigo_moneda = 'ARS';
END
ELSE
    SELECT N'R4. No hay cotizaciones de ARS cargadas (ver 29_ImportarAPIs.sql): no se muestran los ingresos en pesos.' AS reporte;
GO


/* ============================================================================
   R5. Matriz de prime time (tabla cruzada)
   ============================================================================ */

IF EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES)
BEGIN
    SELECT N'R5. Matriz de prime time de todos los partidos, por mercado publicitario' AS reporte;
    EXEC Reportes.usp_MatrizPrimeTime;

    SELECT N'R5. Matriz de prime time de la fase de grupos' AS reporte;
    EXEC Reportes.usp_MatrizPrimeTime @fase = 'GRUPOS';
END
ELSE
    SELECT N'R5. La base no tiene piezas publicitarias con mercados de interés: no hay matriz de prime time.' AS reporte;
GO


/* ============================================================================
   R6. Selecciones y plantillas (XML)
   ============================================================================ */

SELECT N'R6. Selecciones con sus convocados (XML)' AS reporte;
EXEC Reportes.usp_SeleccionesYPlantillasXML;
GO

-- Una selección con sus bajas: se ve el <Baja> de cada jugador dado de baja.
DECLARE @id_seleccion INT = (SELECT TOP (1) l.id_seleccion
                             FROM Torneo.JUGADOR AS j
                             INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                             WHERE j.fecha_baja IS NOT NULL
                             ORDER BY l.id_seleccion);
IF @id_seleccion IS NOT NULL
BEGIN
    SELECT N'R6. Una selección con bajas incluidas (XML)' AS reporte;
    EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = @id_seleccion, @incluir_bajas = 1;
END
ELSE
    SELECT N'R6. Ningún convocado tiene baja: no hay <Baja> para mostrar.' AS reporte;
GO


/* ============================================================================
   R7. Resultados
   ============================================================================ */

-- Dos grillas: posiciones de los grupos y resultados de los partidos.
SELECT N'R7. Resultados: tabla de posiciones de los grupos y, después, todos los partidos' AS reporte;
EXEC Reportes.usp_Resultados;
GO

SET NOEXEC OFF;
GO
