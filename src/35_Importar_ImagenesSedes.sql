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
 Archivo: 35_Importar_ImagenesSedes.sql
 Objetivo: Cargar la foto de cada sede (las 16 del Mundial 2026 y las 8 propias
           del juego de datos) desde datos\fuentes\sedes\, con
           Torneo.usp_ImportarImagenesSedes (24_SP_Importar_ImagenesSedes.sql).
           Requiere haber ejecutado 01 a 34: las sedes que no estén cargadas
           quedan OMITIDAS. Va después de 34 y antes del cifrado (40), aunque
           no depende de él. Se puede ejecutar más de una vez: las fotos que
           ya están cargadas quedan SIN CAMBIOS.
================================================================================

 Antes de ejecutar: CAMBIAR @repositorio por la carpeta del repositorio en tu
 máquina, terminada en \. La cuenta del servicio de SQL Server tiene que poder
 leerla (ver "Antes de ejecutar" en 32_Importar_Mundial2026.sql).

 Una foto suelta se carga, reemplaza o quita desde la aplicación
 app_abm\abm_sedes.py, con los SP de ABM de SEDE_IMAGEN.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_ImportarImagenesSedes', N'P') IS NULL
BEGIN
    PRINT N'35_Importar_ImagenesSedes.sql: falta el SP de 24_SP_Importar_ImagenesSedes.sql. '
        + N'Ejecutá los scripts 01 a 34 y volvé a ejecutar este.';
    SET NOEXEC ON;
END;
GO

-- CAMBIAR: ruta de la carpeta del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @repositorio NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\';
DECLARE @carpeta     NVARCHAR(400) = @repositorio + N'datos\fuentes\sedes\';
DECLARE @cargadas INT, @actualizadas INT, @sin_cambios INT, @omitidas INT, @rechazadas INT;

BEGIN TRY
    EXEC Torneo.usp_ImportarImagenesSedes
        @carpeta      = @carpeta,
        @cargadas     = @cargadas     OUTPUT,
        @actualizadas = @actualizadas OUTPUT,
        @sin_cambios  = @sin_cambios  OUTPUT,
        @omitidas     = @omitidas     OUTPUT,
        @rechazadas   = @rechazadas   OUTPUT;

    PRINT CONCAT(N'Fotos de las sedes: ', @cargadas, N' cargadas, ', @actualizadas, N' actualizadas, ',
                 @sin_cambios, N' sin cambios, ', @omitidas, N' omitidas y ', @rechazadas, N' rechazadas.');
END TRY
BEGIN CATCH
    PRINT N'Error al cargar las fotos de las sedes: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Evidencia: las sedes con y sin foto.
SELECT s.id_sede, s.nombre_estadio, s.ciudad,
       ISNULL(si.formato, '-') AS formato,
       CAST(CEILING(DATALENGTH(si.imagen) / 1024.0) AS INT) AS kb,
       si.fecha_carga
FROM Torneo.SEDE AS s
LEFT JOIN Torneo.SEDE_IMAGEN AS si ON si.id_sede = s.id_sede
ORDER BY IIF(si.id_sede IS NULL, 0, 1), s.id_sede;
GO

SET NOEXEC OFF;
GO
