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
 Archivo: 74_Test_SP_Importar_ImagenesSedes.sql
 Objetivo: Probar Torneo.usp_ImportarImagenesSedes y, a través de él,
           Torneo.usp_ImportarImagenSede (24_SP_Importar_ImagenesSedes.sql),
           con casos exitosos y su evidencia y casos que no cumplen las
           validaciones.
           Requiere haber ejecutado 01 a 34: la lista fija del SP son las 16
           sedes del Mundial (32) y las 8 propias del juego de datos (34).
           Las cargas (IS3 a IS5) van dentro de una transacción que se deshace
           al final, así que las fotos de las sedes quedan como estaban y se
           puede ejecutar más de una vez.
================================================================================

 Antes de ejecutar: CAMBIAR @repositorio, en el primer lote, por la carpeta del
 repositorio en tu máquina. La cuenta del servicio de SQL Server tiene que
 poder leerla (ver "Antes de ejecutar" en 32_Importar_Mundial2026.sql).

 Archivos que usa:
   datos\fuentes\sedes\    las 24 fotos reales
   datos\pruebas\sedes\    lumen_field.jpg, un PNG chico con extensión .jpg
                           (el formato se deduce de la firma, no de la
                           extensión), y bc_place.jpg, que es un texto. Las
                           otras 22 fotos no están, a propósito.

 Cómo leer los resultados:
   - Casos OK: la grilla muestra el estado de cada sede y después las fotos
     que quedaron (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar las mismas fotos que antes.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

-- CAMBIAR: ruta de la carpeta del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @repositorio NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\';
EXEC sp_set_session_context @key = N'repositorio', @value = @repositorio;

IF OBJECT_ID(N'Torneo.usp_ImportarImagenesSedes', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio = 'BC Place')
   OR NOT EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Hernando Siles')
BEGIN
    RAISERROR(N'Faltan el SP o las sedes: ejecutar los scripts 01 a 34.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Las fotos antes de las pruebas, para comparar al final.
DROP TABLE IF EXISTS #antes;
SELECT id_sede, formato, HASHBYTES('SHA2_256', imagen) AS hash_imagen
INTO #antes
FROM Torneo.SEDE_IMAGEN;
SELECT 'Antes' AS caso, COUNT(*) AS sedes_con_foto FROM #antes;
GO


/* IS1 (ERROR) Carpeta vacía.
   Esperado: error 50001 con 1 condición: la carpeta es obligatoria. */
BEGIN TRY
    EXEC Torneo.usp_ImportarImagenesSedes @carpeta = N'   ';
    PRINT N'IS1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'IS1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'IS1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* IS2 (ERROR) Carpeta que no existe en el servidor.
   Esperado: error 50001 con 1 condición: la carpeta no existe. */
BEGIN TRY
    EXEC Torneo.usp_ImportarImagenesSedes @carpeta = N'C:\no_existe\sedes\';
    PRINT N'IS2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'IS2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'IS2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* IS3 a IS5 van en una sola transacción que se deshace al final.

   IS3 (OK) Carga de las 24 fotos reales.
   Esperado: 24 sedes, ninguna RECHAZADA ni OMITIDA; cada una CARGADA (si no
   tenía foto), SIN CAMBIOS (si ya tenía la del repositorio) o ACTUALIZADA (si
   tenía otra, cargada a mano). Después, 24 sedes de la lista con foto.

   IS4 (OK) Segunda carga de la misma carpeta.
   Esperado: las 24 SIN CAMBIOS.

   IS5 (OK, con rechazos) Carga desde la carpeta de prueba.
   Esperado: Lumen Field ACTUALIZADA, con formato PNG aunque el archivo se llame
   .jpg; BC Place RECHAZADA (no es PNG ni JPEG: el motivo es el mensaje de
   usp_SEDE_IMAGEN_Modificacion); las otras 22 RECHAZADA (no existe el archivo). Las rechazadas conservan su foto: BC Place sigue con la
   JPEG de IS3. */
DECLARE @reales  NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'datos\fuentes\sedes\';
DECLARE @pruebas NVARCHAR(400) = CAST(SESSION_CONTEXT(N'repositorio') AS NVARCHAR(400)) + N'datos\pruebas\sedes\';
DECLARE @cargadas INT, @actualizadas INT, @sin_cambios INT, @omitidas INT, @rechazadas INT;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC Torneo.usp_ImportarImagenesSedes @carpeta = @reales, @mostrar_resultados = 1,
         @cargadas = @cargadas OUTPUT, @actualizadas = @actualizadas OUTPUT, @sin_cambios = @sin_cambios OUTPUT,
         @omitidas = @omitidas OUTPUT, @rechazadas = @rechazadas OUTPUT;
    SELECT 'IS3 después' AS caso, @cargadas AS cargadas, @actualizadas AS actualizadas, @sin_cambios AS sin_cambios,
           @omitidas AS omitidas, @rechazadas AS rechazadas,
           (SELECT COUNT(*) FROM Torneo.SEDE_IMAGEN) AS sedes_con_foto;

    EXEC Torneo.usp_ImportarImagenesSedes @carpeta = @reales, @mostrar_resultados = 0,
         @cargadas = @cargadas OUTPUT, @actualizadas = @actualizadas OUTPUT, @sin_cambios = @sin_cambios OUTPUT,
         @omitidas = @omitidas OUTPUT, @rechazadas = @rechazadas OUTPUT;
    SELECT 'IS4 después' AS caso, @cargadas AS cargadas, @actualizadas AS actualizadas, @sin_cambios AS sin_cambios,
           @omitidas AS omitidas, @rechazadas AS rechazadas;

    EXEC Torneo.usp_ImportarImagenesSedes @carpeta = @pruebas, @mostrar_resultados = 1,
         @cargadas = @cargadas OUTPUT, @actualizadas = @actualizadas OUTPUT, @sin_cambios = @sin_cambios OUTPUT,
         @omitidas = @omitidas OUTPUT, @rechazadas = @rechazadas OUTPUT;
    SELECT 'IS5 después' AS caso, s.nombre_estadio, si.formato, DATALENGTH(si.imagen) AS bytes
    FROM Torneo.SEDE_IMAGEN AS si
    INNER JOIN Torneo.SEDE AS s ON s.id_sede = si.id_sede
    WHERE s.nombre_estadio IN ('BC Place', 'Lumen Field')
    ORDER BY s.nombre_estadio;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'IS3 a IS5: FALLÓ, error inesperado ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N'. ' + ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: las mismas fotos que antes (diferencias = 0).
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE_IMAGEN) AS sedes_con_foto,
       (SELECT COUNT(*)
        FROM #antes AS a
        FULL JOIN Torneo.SEDE_IMAGEN AS si ON si.id_sede = a.id_sede
        WHERE a.id_sede IS NULL OR si.id_sede IS NULL
           OR a.hash_imagen <> HASHBYTES('SHA2_256', si.imagen)) AS diferencias;

DROP TABLE #antes;
GO

SET NOEXEC OFF;
GO
