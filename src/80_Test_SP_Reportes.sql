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
 Archivo: 80_Test_SP_Reportes.sql
 Objetivo: Probar las vistas y los SP de 30_SP_Reportes.sql. Trabaja sobre
           los datos que haya cargados (31_DatosDePrueba.sql o los datos
           reales): muestra cada reporte y verifica que sus totales coincidan
           con las tablas base, sin depender de valores fijos.
           Requiere haber ejecutado 00 a 20 y 30, y tener partidos jugados.
           Para probar la conversión de monedas usa su propia cotización: la
           moneda XTS (código ISO 4217 reservado para pruebas), que se borra
           al empezar y al terminar.
================================================================================

 Cómo leer los resultados:
   - Reportes (R): la grilla muestra lo que devuelve cada SP.
   - Verificaciones (V): en Mensajes se imprime "OK" o "FALLÓ" con los dos
     valores comparados.
   - Casos ERROR (E): en Mensajes se imprime "OK" y el mensaje que devolvió el
     SP. Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;   -- los métodos de XML (value, query) lo requieren
GO

IF OBJECT_ID(N'Reportes.usp_Goleadores', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE estado = 'FINALIZADO')
BEGIN
    RAISERROR(N'Faltan los reportes o los datos: ejecutar 00 a 20 y 30, y cargar partidos (por ejemplo, con 31).', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'tempdb..#usp_MostrarError', N'P') IS NOT NULL
    DROP PROCEDURE #usp_MostrarError;
GO
CREATE PROCEDURE #usp_MostrarError
    @caso VARCHAR(10)
AS
BEGIN
    PRINT CONCAT(@caso, N': ',
                 IIF(ERROR_NUMBER() = 50001, N'OK, falló la validación como se esperaba.',
                     CONCAT(N'FALLÓ, error inesperado ', ERROR_NUMBER(), N'.')),
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END;
GO

IF OBJECT_ID(N'tempdb..#usp_Verificar', N'P') IS NOT NULL
    DROP PROCEDURE #usp_Verificar;
GO
CREATE PROCEDURE #usp_Verificar
    @caso         VARCHAR(10),
    @descripcion  NVARCHAR(200),
    @obtenido     DECIMAL(19,2),
    @esperado     DECIMAL(19,2)
AS
BEGIN
    PRINT CONCAT(@caso, N' ', @descripcion, N': ',
                 IIF(@obtenido = @esperado, N'OK', N'FALLÓ'),
                 N' (reporte ', ISNULL(CAST(@obtenido AS NVARCHAR(30)), N'NULL'),
                 N', esperado ', ISNULL(CAST(@esperado AS NVARCHAR(30)), N'NULL'), N')');
END;
GO

-- Limpieza previa: la cotización de prueba de una ejecución anterior.
DECLARE @id_cotizacion INT = (SELECT id_cotizacion FROM DatosGenerales.COTIZACION
                              WHERE codigo_moneda = 'XTS' AND fecha = '2000-01-01');
IF @id_cotizacion IS NOT NULL
    EXEC DatosGenerales.usp_COTIZACION_Baja @id_cotizacion = @id_cotizacion;
GO


/* ============================================================================
   Reportes
   ============================================================================ */

-- R1. Goleadores del torneo y de la fase de grupos.
EXEC Reportes.usp_Goleadores;
EXEC Reportes.usp_Goleadores @fase = 'GRUPOS';
GO

-- R2. Tarjetas (XML) a hoy y al corte con más suspensiones activas: así se
-- ve un <SuspensionActiva> aunque el torneo ya haya terminado.
DECLARE @corte DATETIME2(0) = (
    SELECT TOP (1) DATEADD(SECOND, -1, p.fecha_hora_utc)
    FROM Torneo.PARTIDO AS p
    CROSS APPLY (SELECT COUNT(*) AS cantidad
                 FROM Reportes.fn_SuspensionesActivas(DATEADD(SECOND, -1, p.fecha_hora_utc))) AS s
    ORDER BY s.cantidad DESC, p.fecha_hora_utc);
EXEC Reportes.usp_TarjetasXML;
EXEC Reportes.usp_TarjetasXML @fecha_corte = @corte;
GO

-- R3. Designaciones arbitrales (todas) y partidos dirigidos.
EXEC Reportes.usp_DesignacionesArbitrales;
EXEC Reportes.usp_DesignacionesArbitrales @solo_principal = 1;
GO

-- R4. Ocupación publicitaria en dólares.
EXEC Reportes.usp_OcupacionPublicitaria;
GO

-- R5. Matriz de prime time de los mercados publicitarios.
EXEC Reportes.usp_MatrizPrimeTime;
GO

-- R6. Selecciones y plantillas (XML), con y sin las bajas.
EXEC Reportes.usp_SeleccionesYPlantillasXML;
EXEC Reportes.usp_SeleccionesYPlantillasXML @incluir_bajas = 1;
GO

-- R7. Resultados: posiciones de los grupos y partidos.
EXEC Reportes.usp_Resultados;
GO


/* ============================================================================
   Verificaciones contra las tablas base
   ============================================================================ */

-- V1. Goleadores: la suma de la tabla son los goles del marcador menos los
-- goles en contra (los penales de la definición no están en el marcador).
DECLARE @reporte INT, @esperado INT;
CREATE TABLE #goleadores (
    posicion_torneo INT, seleccion VARCHAR(60), posicion_en_seleccion INT, jugador NVARCHAR(130),
    dorsal TINYINT, goles INT, partidos_con_gol INT, grupos INT, dieciseisavos INT, octavos INT,
    cuartos INT, semifinal INT, tercer_puesto INT, final INT);
INSERT INTO #goleadores EXEC Reportes.usp_Goleadores;

SET @reporte = (SELECT SUM(goles) FROM #goleadores);
SET @esperado = (SELECT SUM(goles_local + goles_visitante) FROM Torneo.PARTIDO WHERE goles_local IS NOT NULL)
              - (SELECT COUNT(*) FROM DesarrolloPartido.GOL AS g
                 INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
                 WHERE tg.es_en_contra = 1);
EXEC #usp_Verificar 'V1a', N'goles de la tabla de goleadores', @reporte, @esperado;

SET @reporte = (SELECT SUM(grupos + dieciseisavos + octavos + cuartos + semifinal + tercer_puesto + final)
                FROM #goleadores);
EXEC #usp_Verificar 'V1b', N'goles por fase suman los del torneo', @reporte, @esperado;
DROP TABLE #goleadores;
GO

-- V2. Tarjetas (XML): una <Tarjeta> por tarjeta a jugadores, las del cuerpo
-- técnico en <Persona>, y una <SuspensionActiva> por fila de
-- fn_SuspensionesActivas, al mismo corte.
DECLARE @corte DATETIME2(0) = (
    SELECT TOP (1) DATEADD(SECOND, -1, p.fecha_hora_utc)
    FROM Torneo.PARTIDO AS p
    CROSS APPLY (SELECT COUNT(*) AS cantidad
                 FROM Reportes.fn_SuspensionesActivas(DATEADD(SECOND, -1, p.fecha_hora_utc))) AS s
    ORDER BY s.cantidad DESC, p.fecha_hora_utc);
DECLARE @x XML, @reporte INT, @esperado INT;
CREATE TABLE #xml (x XML);
INSERT INTO #xml EXEC Reportes.usp_TarjetasXML @fecha_corte = @corte;
SET @x = (SELECT x FROM #xml);

SET @reporte = @x.value('count(//Tarjeta)', 'INT');
SET @esperado = (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION AS a
                 INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                 WHERE a.id_jugador IS NOT NULL AND p.fecha_hora_utc <= @corte);
EXEC #usp_Verificar 'V2a', N'tarjetas a jugadores en el XML', @reporte, @esperado;

SET @reporte = @x.value('sum(//Persona/@amarillas) + sum(//Persona/@rojas)', 'INT');
SET @esperado = (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION AS a
                 INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                 WHERE a.id_persona_ct IS NOT NULL AND p.fecha_hora_utc <= @corte);
EXEC #usp_Verificar 'V2b', N'tarjetas al cuerpo técnico en el XML', @reporte, @esperado;

SET @reporte = @x.value('count(//SuspensionActiva)', 'INT');
SET @esperado = (SELECT COUNT(*) FROM Reportes.fn_SuspensionesActivas(@corte));
EXEC #usp_Verificar 'V2c', N'suspensiones activas en el XML', @reporte, @esperado;
DROP TABLE #xml;
GO

-- V3. Suspensiones activas: un segundo antes de cada partido, las activas de
-- sus dos selecciones son exactamente los jugadores suspendidos para ese
-- partido según DesarrolloPartido.fn_JugadoresSuspendidos. Se cuentan las
-- diferencias en los dos sentidos.
DECLARE @diferencias INT;
WITH segun_reporte AS (
    SELECT p.id_partido, sa.id_jugador, sa.id_partido_origen
    FROM Torneo.PARTIDO AS p
    CROSS APPLY Reportes.fn_SuspensionesActivas(DATEADD(SECOND, -1, p.fecha_hora_utc)) AS sa
    WHERE sa.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
      AND p.estado <> 'SUSPENDIDO'
),
segun_negocio AS (
    SELECT p.id_partido, js.id_jugador, js.id_partido_origen
    FROM Torneo.PARTIDO AS p
    CROSS APPLY DesarrolloPartido.fn_JugadoresSuspendidos(p.id_partido) AS js
    WHERE p.estado <> 'SUSPENDIDO'
)
SELECT @diferencias = (SELECT COUNT(*) FROM (SELECT * FROM segun_reporte EXCEPT SELECT * FROM segun_negocio) AS a)
                    + (SELECT COUNT(*) FROM (SELECT * FROM segun_negocio EXCEPT SELECT * FROM segun_reporte) AS b);
EXEC #usp_Verificar 'V3', N'diferencias con fn_JugadoresSuspendidos', @diferencias, 0;
GO

-- V4. Designaciones: las tarjetas señaladas por los principales son todas las
-- de los partidos que tienen árbitro principal.
DECLARE @reporte INT = (SELECT SUM(amarillas_senaladas + rojas_senaladas)
                        FROM Reportes.vw_DesignacionesArbitrales);
DECLARE @esperado INT = (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION AS a
                         WHERE EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                                       WHERE d.id_partido = a.id_partido AND d.rol = 'PRINCIPAL'));
EXEC #usp_Verificar 'V4', N'tarjetas señaladas por los árbitros principales', @reporte, @esperado;
GO

-- V5. Ocupación: cuatro espacios por partido, uno ocupado por exhibición, y
-- los ingresos en dólares de las exhibiciones en dólares.
DECLARE @reporte DECIMAL(19,2), @esperado DECIMAL(19,2);

SET @reporte = (SELECT COUNT(*) FROM Reportes.vw_OcupacionPublicitaria);
SET @esperado = (SELECT COUNT(*) FROM Torneo.PARTIDO AS p
                 INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS ep ON ep.id_sede = p.id_sede);
EXEC #usp_Verificar 'V5a', N'espacios por partido', @reporte, @esperado;

SET @reporte = (SELECT COUNT(*) FROM Reportes.vw_OcupacionPublicitaria WHERE ocupado = 1);
SET @esperado = (SELECT COUNT(*) FROM Publicidad.EXHIBICION);
EXEC #usp_Verificar 'V5b', N'espacios ocupados', @reporte, @esperado;

SET @reporte = (SELECT SUM(costo_usd) FROM Reportes.vw_OcupacionPublicitaria WHERE codigo_moneda = 'USD');
SET @esperado = (SELECT SUM(costo) FROM Publicidad.EXHIBICION WHERE codigo_moneda = 'USD');
EXEC #usp_Verificar 'V5c', N'ingresos de las exhibiciones en dólares', @reporte, @esperado;
GO

-- V6. Conversión de monedas: con la cotización de prueba (1 USD = 2,5 XTS
-- desde el 01/01/2000), los ingresos en XTS son 2,5 veces los en dólares.
EXEC DatosGenerales.usp_COTIZACION_Alta @codigo_moneda = 'XTS', @fecha = '2000-01-01', @unidades_por_usd = 2.5;

DECLARE @reporte DECIMAL(19,2) = (SELECT SUM(ingresos_en_moneda) FROM Reportes.vw_IngresosPublicitariosPorMoneda
                                  WHERE codigo_moneda = 'XTS');
DECLARE @esperado DECIMAL(19,2) = (SELECT SUM(ingresos_usd) * 2.5 FROM Reportes.vw_IngresosPublicitariosPorMoneda
                                   WHERE codigo_moneda = 'USD');
EXEC #usp_Verificar 'V6', N'ingresos en XTS (vista para el BI)', @reporte, @esperado;

-- El SP muestra la misma conversión en sus columnas moneda e ingresos_moneda.
EXEC Reportes.usp_OcupacionPublicitaria @codigo_moneda = 'XTS';
GO

-- V7. Prime time: un partido y mercado por fila (todos los países).
DECLARE @reporte INT = (SELECT COUNT(*) FROM Reportes.vw_PrimeTimePorMercado);
DECLARE @esperado INT = (SELECT COUNT(*) FROM Torneo.PARTIDO) * (SELECT COUNT(*) FROM DatosGenerales.PAIS);
EXEC #usp_Verificar 'V7', N'filas partido x mercado', @reporte, @esperado;
GO

-- V8. Plantillas (XML): un <Jugador> por convocado activo y, con las bajas,
-- por cada jugador.
DECLARE @reporte INT, @esperado INT;
CREATE TABLE #xml (x XML);

INSERT INTO #xml EXEC Reportes.usp_SeleccionesYPlantillasXML;
SET @reporte = (SELECT x.value('count(//Jugador)', 'INT') FROM #xml);
SET @esperado = (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE fecha_baja IS NULL);
EXEC #usp_Verificar 'V8a', N'convocados activos en el XML', @reporte, @esperado;

TRUNCATE TABLE #xml;
INSERT INTO #xml EXEC Reportes.usp_SeleccionesYPlantillasXML @incluir_bajas = 1;
SET @reporte = (SELECT x.value('count(//Jugador)', 'INT') FROM #xml);
SET @esperado = (SELECT COUNT(*) FROM Torneo.JUGADOR);
EXEC #usp_Verificar 'V8b', N'convocados con las bajas en el XML', @reporte, @esperado;
DROP TABLE #xml;
GO

-- V9. Resultados: en cada partido, la cantidad de goles del detalle de cada
-- lado coincide con el marcador (un gol en contra va del lado que lo suma).
DECLARE @diferencias INT = (
    SELECT COUNT(*)
    FROM Reportes.vw_Resultados
    WHERE goles_local IS NOT NULL
      AND (goles_local <> IIF(goles_del_local IS NULL, 0,
                              LEN(goles_del_local) - LEN(REPLACE(goles_del_local, N', ', N'.')) + 1)
           OR goles_visitante <> IIF(goles_del_visitante IS NULL, 0,
                                     LEN(goles_del_visitante) - LEN(REPLACE(goles_del_visitante, N', ', N'.')) + 1)));
EXEC #usp_Verificar 'V9', N'partidos cuyo detalle de goles no coincide con el marcador', @diferencias, 0;
GO

-- V10. Tabla de posiciones: cada partido de grupos finalizado suma un PJ a
-- cada selección, los goles a favor son los en contra, y reparte 3 puntos
-- (o 2 si es empate).
DECLARE @reporte INT, @esperado INT;

SET @reporte = (SELECT SUM(pj) FROM Reportes.vw_TablaPosiciones);
SET @esperado = 2 * (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE fase = 'GRUPOS' AND estado = 'FINALIZADO');
EXEC #usp_Verificar 'V10a', N'partidos jugados', @reporte, @esperado;

SET @reporte = (SELECT SUM(gf) - SUM(gc) FROM Reportes.vw_TablaPosiciones);
EXEC #usp_Verificar 'V10b', N'goles a favor menos goles en contra', @reporte, 0;

SET @reporte = (SELECT SUM(pts) FROM Reportes.vw_TablaPosiciones);
SET @esperado = (SELECT SUM(IIF(goles_local = goles_visitante, 2, 3)) FROM Torneo.PARTIDO
                 WHERE fase = 'GRUPOS' AND estado = 'FINALIZADO');
EXEC #usp_Verificar 'V10c', N'puntos repartidos', @reporte, @esperado;
GO


/* ============================================================================
   Casos ERROR: validación de los parámetros
   ============================================================================ */

-- E1. Fase inexistente.
BEGIN TRY
    EXEC Reportes.usp_Goleadores @fase = 'OCTAVO';
    PRINT N'E1: FALLÓ, el SP no rechazó la fase.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E1';
END CATCH;
GO

-- E2. Selección inexistente.
BEGIN TRY
    EXEC Reportes.usp_TarjetasXML @id_seleccion = -1;
    PRINT N'E2: FALLÓ, el SP no rechazó la selección.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E2';
END CATCH;
GO

-- E3. Árbitro inexistente.
BEGIN TRY
    EXEC Reportes.usp_DesignacionesArbitrales @id_arbitro = -1;
    PRINT N'E3: FALLÓ, el SP no rechazó el árbitro.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E3';
END CATCH;
GO

-- E4. Sede y partido inexistentes y moneda sin cotizaciones: informa los tres
-- errores juntos. XXX es el código ISO 4217 de "sin moneda".
BEGIN TRY
    EXEC Reportes.usp_OcupacionPublicitaria @id_sede = -1, @id_partido = -1, @codigo_moneda = 'XXX';
    PRINT N'E4: FALLÓ, el SP no rechazó los parámetros.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E4';
END CATCH;
GO

-- E5. Fase inexistente en la matriz de prime time.
BEGIN TRY
    EXEC Reportes.usp_MatrizPrimeTime @fase = 'REPECHAJE';
    PRINT N'E5: FALLÓ, el SP no rechazó la fase.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E5';
END CATCH;
GO

-- E6. Selección inexistente en las plantillas.
BEGIN TRY
    EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = -1;
    PRINT N'E6: FALLÓ, el SP no rechazó la selección.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E6';
END CATCH;
GO

-- E7. Fase y selección inexistentes en los resultados: los dos errores juntos.
BEGIN TRY
    EXEC Reportes.usp_Resultados @fase = 'REPECHAJE', @id_seleccion = -1;
    PRINT N'E7: FALLÓ, el SP no rechazó los parámetros.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError 'E7';
END CATCH;
GO


/* ============================================================================
   Limpieza y verificación final
   ============================================================================ */

DECLARE @id_cotizacion INT = (SELECT id_cotizacion FROM DatosGenerales.COTIZACION
                              WHERE codigo_moneda = 'XTS' AND fecha = '2000-01-01');
IF @id_cotizacion IS NOT NULL
    EXEC DatosGenerales.usp_COTIZACION_Baja @id_cotizacion = @id_cotizacion;
GO

SELECT 'Datos de prueba que quedaron (tiene que ser 0)' AS verificacion,
       (SELECT COUNT(*) FROM DatosGenerales.COTIZACION WHERE codigo_moneda = 'XTS') AS cantidad;
GO

DROP PROCEDURE #usp_MostrarError;
DROP PROCEDURE #usp_Verificar;
GO

SET NOEXEC OFF;
GO
