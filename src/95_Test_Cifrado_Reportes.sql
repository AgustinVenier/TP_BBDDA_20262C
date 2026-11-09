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

 Fecha: 09/11/2026
 Archivo: 95_Test_Cifrado_Reportes.sql
 Objetivo: Probar las vistas y el SP de Reportes que modifica
           45_Cifrado_Reportes.sql: que devuelvan los nombres de jugadores,
           cuerpos técnicos y árbitros descifrados (vw_Goles, vw_Tarjetas,
           vw_SuspensionesActivas, vw_DesignacionesArbitrales, vw_Plantillas,
           vw_Resultados y usp_SeleccionesYPlantillasXML), y que un jugador
           dado de alta por SP aparezca descifrado en vw_Plantillas.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql y tener cargado el torneo
 (32). Ejecutar como dueño de la base (dbo). El alta de prueba se hace dentro
 de una transacción que se deshace, así no queda nada. Si algún control no da
 lo esperado, el script termina con error.

 Si una persona no se descifrara, su nombre y su apellido serían NULL, y los
 textos armados con CONCAT quedarían sin ellos (", " en lugar de
 "Apellido, Nombre"). Eso es lo que buscan los controles.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.GOL)
    THROW 51013, N'No hay partidos jugados cargados. Ejecute primero las importaciones (30 a 35).', 1;
GO

DECLARE @controles TABLE (n INT IDENTITY, control NVARCHAR(200), esperado NVARCHAR(200), obtenido NVARCHAR(400));
DECLARE @xml TABLE (reporte XML);
DECLARE @id_lista INT, @id_seleccion INT, @libre INT, @id INT, @texto NVARCHAR(MAX),
        @un_nombre NVARCHAR(130), @dt NVARCHAR(130);

/* 1. Vistas: ninguna fila sin el nombre de su persona. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_Goles: filas y filas sin autor', N'con filas, 0 sin autor',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              ISNULL(SUM(IIF(apellido IS NULL OR nombre IS NULL OR jugador = N', ', 1, 0)), 0), N' sin autor')
FROM Reportes.vw_Goles;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_Tarjetas: filas, filas sin persona y filas sin árbitro', N'con filas, 0 sin persona, 0 sin árbitro',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              ISNULL(SUM(IIF(apellido IS NULL OR nombre IS NULL OR persona = N', ', 1, 0)), 0), N' sin persona, ',
              ISNULL(SUM(IIF(arbitro_principal = N', ', 1, 0)), 0), N' sin árbitro')
FROM Reportes.vw_Tarjetas;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_SuspensionesActivas: filas sin jugador', N'0',
       CAST(COUNT(*) AS NVARCHAR(10))
FROM Reportes.vw_SuspensionesActivas
WHERE jugador = N', ' OR jugador IS NULL;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_DesignacionesArbitrales: filas y filas sin árbitro', N'con filas, 0 sin árbitro',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              ISNULL(SUM(IIF(arbitro = N', ' OR arbitro IS NULL, 1, 0)), 0), N' sin árbitro')
FROM Reportes.vw_DesignacionesArbitrales;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_Plantillas: filas y filas sin nombre', N'con filas, 0 sin nombre',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              ISNULL(SUM(IIF(apellido IS NULL OR nombre IS NULL, 1, 0)), 0), N' sin nombre')
FROM Reportes.vw_Plantillas;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_Plantillas: nombres distintos de Seguridad.vw_Jugador', N'0', CAST(COUNT(*) AS NVARCHAR(10))
FROM Reportes.vw_Plantillas AS p
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = p.id_jugador
WHERE p.apellido <> j.apellido OR p.nombre <> j.nombre;

-- En vw_Resultados, un goleador sin apellido deja el detalle empezando con espacio o con ",  ".
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Reportes.vw_Resultados: partidos con un goleador sin apellido', N'0', CAST(COUNT(*) AS NVARCHAR(10))
FROM Reportes.vw_Resultados
WHERE LEFT(goles_del_local, 1) = N' ' OR goles_del_local LIKE N'%,  %'
   OR LEFT(goles_del_visitante, 1) = N' ' OR goles_del_visitante LIKE N'%,  %';

/* 2. usp_SeleccionesYPlantillasXML: los jugadores y el director técnico salen
      con su nombre descifrado. */
SELECT TOP (1) @id_lista = id_lista, @id_seleccion = id_seleccion FROM Torneo.LISTA_CONVOCADOS ORDER BY id_lista;
SELECT TOP (1) @un_nombre = CONCAT(nombre, N' ', apellido) FROM Seguridad.vw_Jugador
WHERE id_lista = @id_lista AND fecha_baja IS NULL ORDER BY dorsal;
SELECT TOP (1) @dt = CONCAT(nombre, N' ', apellido) FROM Seguridad.vw_PersonaCuerpoTecnico
WHERE id_seleccion = @id_seleccion AND rol = 'DIRECTOR_TECNICO';

INSERT INTO @xml (reporte)
EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = @id_seleccion;
SELECT @texto = CONVERT(NVARCHAR(MAX), reporte) FROM @xml;

INSERT INTO @controles (control, esperado, obtenido)
VALUES (N'usp_SeleccionesYPlantillasXML: jugadores sin nombre (<Nombre> </Nombre>)', N'0',
        CAST((LEN(@texto) - LEN(REPLACE(@texto, N'<Nombre> </Nombre>', N''))) / LEN(N'<Nombre> </Nombre>') AS NVARCHAR(10))),
       (N'usp_SeleccionesYPlantillasXML: incluye a un jugador de la lista descifrado', N'sí',
        IIF(CHARINDEX(N'<Nombre>' + @un_nombre + N'</Nombre>', @texto) > 0, N'sí', N'no')),
       (N'usp_SeleccionesYPlantillasXML: director técnico descifrado (si la selección tiene)', N'sí',
        IIF(@dt IS NULL OR CHARINDEX(N'<DirectorTecnico>' + @dt + N'</DirectorTecnico>', @texto) > 0, N'sí', N'no'));

/* 3. Un jugador dado de alta por SP aparece descifrado en vw_Plantillas. */
SELECT TOP (1) @libre = id_jugador FROM Torneo.JUGADOR
WHERE id_lista = @id_lista AND fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY dorsal;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @libre, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @fecha_nacimiento = '2001-02-03', @id_jugador = @id OUTPUT;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'Alta con usp_JUGADOR_Alta: leído en Reportes.vw_Plantillas', N'Ñandú Pérez Cifrado',
           ISNULL(CONCAT(MAX(nombre), N' ', MAX(apellido)), N'no aparece')
    FROM Reportes.vw_Plantillas WHERE id_jugador = @id;
END TRY
BEGIN CATCH
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'Error inesperado', N'ninguno', CONCAT(N'error ', ERROR_NUMBER(), N': ', LEFT(ERROR_MESSAGE(), 350)));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* 4. Al terminar, ninguna clave queda abierta en la sesión. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Claves abiertas en la sesión', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;

SELECT n, control, esperado, obtenido, IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado
FROM @controles
ORDER BY n;

IF EXISTS (SELECT 1 FROM @controles WHERE esperado <> obtenido)
    THROW 51014, N'Los reportes con cifrado (45) no dan lo esperado.', 1;
GO
