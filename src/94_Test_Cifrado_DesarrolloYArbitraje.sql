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
 Archivo: 94_Test_Cifrado_DesarrolloYArbitraje.sql
 Objetivo: Probar los objetos de DesarrolloPartido y Arbitraje que modifica
           44_Cifrado_DesarrolloYArbitraje.sql: que el alta y la modificación
           de árbitros (usp_ARBITRO_Alta y usp_ARBITRO_Modificacion) guarden
           cifrado lo que escriben, que se lea descifrado y que controlen los
           duplicados comparando los datos descifrados; y que las vistas y la
           función que muestran personas (vw_Goleadores,
           vw_HistorialTitularidad, vw_HistorialArbitro y fn_EquipoEnCancha)
           devuelvan los nombres descifrados.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql y tener cargado el torneo
 (32), con goles, formaciones y designaciones. Ejecutar como dueño de la base
 (dbo). Las altas de prueba se hacen dentro de una transacción que se deshace,
 así no queda nada. Si algún control no da lo esperado, el script termina con
 error.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los índices filtrados y los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.GOL) OR NOT EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL)
    THROW 51013, N'No hay partidos jugados cargados. Ejecute primero las importaciones (30 a 35).', 1;
GO

DECLARE @controles TABLE (n INT IDENTITY, control NVARCHAR(200), esperado NVARCHAR(200), obtenido NVARCHAR(400));
DECLARE @id_pais SMALLINT, @id1 INT, @id2 INT, @id_partido INT, @id_seleccion INT;

/* 1. Vistas y función: los nombres salen descifrados (si una persona no se
      descifrara, nombre y apellido serían NULL) y coinciden con las vistas de
      Seguridad. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'DesarrolloPartido.vw_Goleadores: filas y filas sin nombre', N'con filas, 0 sin nombre',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              SUM(IIF(apellido IS NULL OR nombre IS NULL, 1, 0)), N' sin nombre')
FROM DesarrolloPartido.vw_Goleadores;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'DesarrolloPartido.vw_Goleadores: nombres distintos de Seguridad.vw_Jugador', N'0', CAST(COUNT(*) AS NVARCHAR(10))
FROM DesarrolloPartido.vw_Goleadores AS g
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = g.id_jugador
WHERE g.apellido <> j.apellido OR g.nombre <> j.nombre;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'DesarrolloPartido.vw_HistorialTitularidad: filas y filas sin nombre', N'con filas, 0 sin nombre',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              SUM(IIF(apellido IS NULL OR nombre IS NULL, 1, 0)), N' sin nombre')
FROM DesarrolloPartido.vw_HistorialTitularidad;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Arbitraje.vw_HistorialArbitro: filas y filas sin nombre', N'con filas, 0 sin nombre',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              SUM(IIF(apellido IS NULL OR nombre IS NULL, 1, 0)), N' sin nombre')
FROM Arbitraje.vw_HistorialArbitro;

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Arbitraje.vw_HistorialArbitro: nombres distintos de Seguridad.vw_Arbitro', N'0', CAST(COUNT(*) AS NVARCHAR(10))
FROM Arbitraje.vw_HistorialArbitro AS h
INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = h.id_arbitro
WHERE h.apellido <> a.apellido OR h.nombre <> a.nombre;

-- Un partido con formación, para la función.
SELECT TOP (1) @id_partido = id_partido, @id_seleccion = id_seleccion FROM DesarrolloPartido.FORMACION ORDER BY id_partido;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'DesarrolloPartido.fn_EquipoEnCancha al minuto 1: filas y filas sin nombre', N'con filas, 0 sin nombre',
       CONCAT(IIF(COUNT(*) > 0, N'con filas', N'sin filas'), N', ',
              ISNULL(SUM(IIF(apellido IS NULL OR nombre IS NULL, 1, 0)), 0), N' sin nombre')
FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 1, 0);

/* 2. Árbitros: el alta y la modificación cifran lo que guardan y controlan
      los duplicados sobre los datos descifrados. */
SELECT TOP (1) @id_pais = id_pais FROM DatosGenerales.PAIS ORDER BY id_pais;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado',
         @categoria = 'FIFA', @fecha_nacimiento = '1984-10-11', @id_arbitro = @id1 OUTPUT;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_ARBITRO_Alta: apellido y fecha guardados', N'cifrados',
           IIF(apellido IS NULL OR fecha_nacimiento IS NULL, N'NULL',
               IIF(CONVERT(NVARCHAR(60), apellido) = N'Árbitro Cifrado', N'en texto', N'cifrados'))
    FROM Arbitraje.ARBITRO WHERE id_arbitro = @id1;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_ARBITRO_Alta: leído en Seguridad.vw_Arbitro', N'Ñuño Árbitro Cifrado 1984-10-11',
           CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento)
    FROM Seguridad.vw_Arbitro WHERE id_arbitro = @id1;

    BEGIN TRY
        EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado',
             @categoria = 'FIFA';
        INSERT INTO @controles (control, esperado, obtenido) VALUES (N'usp_ARBITRO_Alta del mismo árbitro', N'rechazada', N'aceptada');
    END TRY
    BEGIN CATCH
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_ARBITRO_Alta del mismo árbitro', N'rechazada',
                IIF(ERROR_MESSAGE() LIKE N'%Ya hay un árbitro%', N'rechazada', LEFT(ERROR_MESSAGE(), 400)));
    END CATCH;

    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Otro', @apellido = N'Árbitro Prueba',
         @categoria = 'FIFA', @id_arbitro = @id2 OUTPUT;
    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id2, @apellido = N'Árbitro Modificado',
         @fecha_nacimiento = '1990-12-13';
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_ARBITRO_Modificacion: leído en Seguridad.vw_Arbitro', N'Otro Árbitro Modificado 1990-12-13',
           CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento)
    FROM Seguridad.vw_Arbitro WHERE id_arbitro = @id2;

    BEGIN TRY
        EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id2, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado';
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_ARBITRO_Modificacion con el nombre de otro árbitro del país', N'rechazada', N'aceptada');
    END TRY
    BEGIN CATCH
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_ARBITRO_Modificacion con el nombre de otro árbitro del país', N'rechazada',
                IIF(ERROR_MESSAGE() LIKE N'%Ya hay otro árbitro%', N'rechazada', LEFT(ERROR_MESSAGE(), 400)));
    END CATCH;

    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'Claves abiertas al terminar los SP', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;
END TRY
BEGIN CATCH
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'Error inesperado', N'ninguno', CONCAT(N'error ', ERROR_NUMBER(), N': ', LEFT(ERROR_MESSAGE(), 350)));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* 3. Después del ROLLBACK no queda nada de prueba. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Árbitros de prueba que quedaron', N'0', CAST(COUNT(*) AS NVARCHAR(10))
FROM Seguridad.vw_Arbitro
WHERE apellido IN (N'Árbitro Cifrado', N'Árbitro Prueba', N'Árbitro Modificado');

SELECT n, control, esperado, obtenido, IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado
FROM @controles
ORDER BY n;

IF EXISTS (SELECT 1 FROM @controles WHERE esperado <> obtenido)
    THROW 51014, N'Los objetos de DesarrolloPartido y Arbitraje con cifrado (44) no dan lo esperado.', 1;
GO
