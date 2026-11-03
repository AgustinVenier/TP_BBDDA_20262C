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
 Archivo: 34_SedesAdicionales.sql
 Objetivo: Cargar 8 sedes propias del juego de datos, además de las 16 que
           importa el 31, para el criterio de aceptación "al menos 8 sedes,
           con huso horario distinto entre al menos tres de ellas (además de
           las que pudieran importar)". Son estadios de Sudamérica con cinco
           husos distintos: Argentina (UTC-3), Brasil (UTC-3, otro huso),
           Chile (UTC-4 en junio y julio), Bolivia (UTC-4) y Colombia y Perú
           (UTC-5). Cada sede se registra con sus 4 espacios publicitarios.
           No es obligatorio ejecutarlo: el torneo real no juega en estas
           sedes y nada de lo demás depende de ellas.
           Requiere haber ejecutado 00 a 20 (usa los países de
           20_DatosIniciales.sql y el SP de 16_SP_Importacion.sql). Se puede
           ejecutar más de una vez: las sedes ya cargadas quedan SIN CAMBIOS.
================================================================================

 Se cargan con Torneo.usp_ImportarSedes (16_SP_Importacion.sql), que valida
 por conjuntos las reglas de usp_SEDE_Alta y usp_RegistrarSede y da de alta
 cada sede con sus 4 espacios, en una sola transacción. No es una importación,
 así que no se registra en DatosGenerales.IMPORTACION: si alguna sede se
 rechaza, se muestran los motivos y no se carga ninguna.

 Capacidad y coordenadas: las publicadas para cada estadio (capacidad
 habilitada, coordenadas del centro del campo). Las tarifas de los espacios
 son menores que las de las sedes del Mundial (120.000, 100.000, 90.000 y
 80.000 USD): 60.000, 50.000, 45.000 y 40.000 USD.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_ImportarSedes', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa = 'BOL')
BEGIN
    PRINT N'34_SedesAdicionales.sql: la base tiene que tener los SP de importación (16) y los datos '
        + N'iniciales (20). Ejecutá los scripts 00 a 20 y volvé a ejecutar este.';
    SET NOEXEC ON;
END;
GO

DROP TABLE IF EXISTS #staging_sedes;
GO

-- La tabla que lee usp_ImportarSedes, con las columnas que usa.
CREATE TABLE #staging_sedes (
    id_registro     INT           PRIMARY KEY,
    nombre_estadio  VARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    ciudad          VARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    codigo_fifa     VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    capacidad       INT           NULL,
    huso_horario    VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    latitud         DECIMAL(12,6) NULL,
    longitud        DECIMAL(12,6) NULL,
    tarifa_1        DECIMAL(9,2)  NULL,
    tarifa_2        DECIMAL(9,2)  NULL,
    tarifa_3        DECIMAL(9,2)  NULL,
    tarifa_4        DECIMAL(9,2)  NULL,
    errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_sedes (id_registro, nombre_estadio, ciudad, codigo_fifa, capacidad, huso_horario, latitud, longitud,
                            tarifa_1, tarifa_2, tarifa_3, tarifa_4)
SELECT s.id_registro, s.nombre_estadio, s.ciudad, s.codigo_fifa, s.capacidad, s.huso_horario, s.latitud, s.longitud,
       60000, 50000, 45000, 40000
FROM (VALUES
        (1, 'Estadio Alberto J. Armando (La Bombonera)',              'Buenos Aires',   'ARG', 54000, 'Argentina Standard Time',        -34.635556, -58.364722),
        (2, 'Estadio Monumental Antonio Vespucio Liberti',            'Buenos Aires',   'ARG', 85018, 'Argentina Standard Time',        -34.545278, -58.449722),
        (3, 'Estadio Libertadores de América - Ricardo E. Bochini',   'Avellaneda',     'ARG', 42069, 'Argentina Standard Time',        -34.670278, -58.371111),
        (4, 'Estadio Jornalista Mário Filho (Maracaná)',              'Río de Janeiro', 'BRA', 78838, 'E. South America Standard Time', -22.912167, -43.230164),
        (5, 'Estadio Nacional Julio Martínez Prádanos',               'Santiago',       'CHI', 48665, 'Pacific SA Standard Time',       -33.464722, -70.610556),
        (6, 'Estadio Metropolitano Roberto Meléndez',                 'Barranquilla',   'COL', 46692, 'SA Pacific Standard Time',        10.927139, -74.800139),
        (7, 'Estadio Nacional del Perú',                              'Lima',           'PER', 50086, 'SA Pacific Standard Time',       -12.067222, -77.033611),
        (8, 'Estadio Hernando Siles',                                 'La Paz',         'BOL', 41143, 'SA Western Standard Time',       -16.499722, -68.122778)
     ) AS s (id_registro, nombre_estadio, ciudad, codigo_fifa, capacidad, huso_horario, latitud, longitud);

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Torneo.usp_ImportarSedes;

    IF EXISTS (SELECT 1 FROM #staging_sedes WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT nombre_estadio, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_sedes WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        ROLLBACK TRANSACTION;
        PRINT N'Sedes adicionales: hay sedes rechazadas (ver la grilla); no se cargó ninguna.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @insertadas INT = (SELECT COUNT(*) FROM #staging_sedes WHERE accion = 'INSERTADO');
        DECLARE @sin_cambios INT = (SELECT COUNT(*) FROM #staging_sedes WHERE accion = 'SIN CAMBIOS');
        PRINT CONCAT(N'Sedes adicionales: ', @insertadas, N' cargadas y ', @sin_cambios, N' que ya estaban.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar las sedes adicionales: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


-- Las sedes adicionales, con su huso, su desfase actual y sus espacios publicitarios.
SELECT s.nombre_estadio, s.ciudad, pa.nombre AS pais, s.capacidad, s.huso_horario,
       DATENAME(TZOFFSET, SYSDATETIMEOFFSET() AT TIME ZONE s.huso_horario) AS desfase_utc,
       s.latitud, s.longitud,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS espacios,
       (SELECT SUM(e.tarifa_usd) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS tarifas_usd
FROM Torneo.SEDE AS s
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio
ORDER BY st.id_registro;

-- El criterio de aceptación: al menos 8 sedes propias con al menos 3 husos distintos.
SELECT COUNT(*) AS sedes_adicionales, COUNT(DISTINCT s.huso_horario) AS husos_distintos,
       IIF(COUNT(*) >= 8 AND COUNT(DISTINCT s.huso_horario) >= 3, 'CUMPLE', 'NO CUMPLE') AS criterio
FROM Torneo.SEDE AS s
INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio;

DROP TABLE #staging_sedes;
GO

SET NOEXEC OFF;
GO
