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
 Archivo: 24_SP_Importar_ImagenesSedes.sql
 Objetivo: Crear los SP que cargan la foto de cada sede desde los archivos
           prebajados del repositorio:
             Torneo.usp_ImportarImagenSede     la foto de una sede, desde un archivo
             Torneo.usp_ImportarImagenesSedes  las 24 fotos de datos\fuentes\sedes
           El segundo lo ejecutan 35_Importar_ImagenesSedes.sql y la aplicación
           abm_sedes.py. Las fotos se guardan con los SP de ABM de SEDE_IMAGEN
           (06_SP_ABM_Torneo.sql), que también usa la aplicación para cargar,
           reemplazar o quitar una foto suelta.
           Requiere haber ejecutado 01 a 06. Su script de testing es
           74_Test_SP_Importar_ImagenesSedes.sql.
================================================================================

 Las fotos son la imagen principal del artículo de Wikipedia de cada estadio,
 con licencia libre, achicadas a 1280 px.
 Se bajaron una vez y quedan en el repositorio, así la carga no depende de
 internet y da siempre el mismo resultado.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ImportarImagenSede
  Carga la foto de la sede @nombre_estadio desde el archivo @archivo de
  @carpeta y anota cómo le fue en #fotos, la tabla temporal que crea
  usp_ImportarImagenesSedes:
    OMITIDA      la sede no está cargada (por ejemplo, sin ejecutar 34)
    RECHAZADA    falta el archivo, no se pudo leer, o usp_SEDE_IMAGEN_Alta o
                 _Modificacion lo rechazó (no es PNG ni JPEG, o supera los
                 2 MB); el motivo es el mensaje del error
    SIN CAMBIOS  la sede ya tenía esa misma foto
    CARGADA      no tenía foto y se cargó
    ACTUALIZADA  tenía otra foto y se reemplazó
  La lectura es SQL dinámico porque OPENROWSET(BULK) solo acepta la ruta como
  literal (con las comillas duplicadas).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarImagenSede
    @carpeta         NVARCHAR(400),
    @nombre_estadio  VARCHAR(100),
    @archivo         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_sede  INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = @nombre_estadio);
    DECLARE @sql      NVARCHAR(MAX);
    DECLARE @imagen   VARBINARY(MAX);
    DECLARE @estado   VARCHAR(12);
    DECLARE @motivo   NVARCHAR(2048);
    DECLARE @leida    TABLE (imagen VARBINARY(MAX));

    IF OBJECT_ID(N'tempdb..#fotos') IS NULL
        THROW 50001, N'Torneo.usp_ImportarImagenSede: no se cargó nada, falta la tabla #fotos (la crea usp_ImportarImagenesSedes).', 1;

    IF @id_sede IS NULL
    BEGIN
        SET @estado = 'OMITIDA';
        SET @motivo = N'La sede no está cargada.';
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.dm_os_file_exists(@carpeta + @archivo) WHERE file_exists = 1)
    BEGIN
        SET @estado = 'RECHAZADA';
        SET @motivo = N'No existe el archivo ' + @archivo + N' en la carpeta.';
    END
    ELSE
    BEGIN TRY
        SET @sql = N'SELECT BulkColumn FROM OPENROWSET(BULK N'''
                 + REPLACE(@carpeta + @archivo, N'''', N'''''') + N''', SINGLE_BLOB) AS archivo;';
        INSERT INTO @leida (imagen)
        EXEC sp_executesql @sql;
        SELECT @imagen = imagen FROM @leida;

        IF EXISTS (SELECT 1 FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede AND imagen = @imagen)
            SET @estado = 'SIN CAMBIOS';
        ELSE IF EXISTS (SELECT 1 FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede)
        BEGIN
            EXEC Torneo.usp_SEDE_IMAGEN_Modificacion @id_sede = @id_sede, @imagen = @imagen;
            SET @estado = 'ACTUALIZADA';
        END
        ELSE
        BEGIN
            EXEC Torneo.usp_SEDE_IMAGEN_Alta @id_sede = @id_sede, @imagen = @imagen;
            SET @estado = 'CARGADA';
        END;
    END TRY
    BEGIN CATCH
        -- El archivo no se pudo leer o el SP de ABM rechazó la imagen: las demás fotos siguen.
        SET @estado = 'RECHAZADA';
        SET @motivo = REPLACE(ERROR_MESSAGE(), NCHAR(13) + NCHAR(10), N' ');
    END CATCH;

    INSERT INTO #fotos (nombre_estadio, archivo, estado, formato, kb, motivo)
    SELECT @nombre_estadio, @archivo, @estado,
           IIF(@estado IN ('OMITIDA', 'RECHAZADA'), NULL,
               (SELECT formato FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede)),
           CAST(CEILING(DATALENGTH(@imagen) / 1024.0) AS INT), @motivo;
END;
GO


/*
  usp_ImportarImagenesSedes
  Carga la foto de cada sede de una lista fija (las 16 sedes del Mundial 2026
  y las 8 propias del juego de datos) desde @carpeta, la carpeta
  datos\fuentes\sedes\ del repositorio en el servidor: una llamada a
  usp_ImportarImagenSede por sede. Cada foto se guarda por separado, así que
  una que falta o no es válida queda RECHAZADA y no frena a las demás.
  Devuelve el estado de cada sede (si @mostrar_resultados = 1) y los totales por estado.
  Las sedes que no están en la lista (las que se agregan a mano) no se tocan.
  Valida: carpeta obligatoria y existente en el servidor.
  Se puede ejecutar más de una vez: las fotos ya cargadas quedan SIN CAMBIOS.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarImagenesSedes
    @carpeta      NVARCHAR(400),
    @mostrar_resultados      BIT = 1,
    @cargadas     INT = NULL OUTPUT,
    @actualizadas INT = NULL OUTPUT,
    @sin_cambios  INT = NULL OUTPUT,
    @omitidas     INT = NULL OUTPUT,
    @rechazadas   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @carpeta = NULLIF(TRIM(@carpeta), N'');
    IF @carpeta IS NOT NULL AND RIGHT(@carpeta, 1) <> N'\'
        SET @carpeta += N'\';

    IF @carpeta IS NULL
        SET @errores += @salto_linea + N'- La carpeta de las fotos es obligatoria (ej. C:\...\datos\fuentes\sedes\).';
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.dm_os_file_exists(@carpeta) WHERE file_is_a_directory = 1)
        SET @errores += @salto_linea + N'- La carpeta "' + @carpeta + N'" no existe en el servidor o SQL Server no la puede ver.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarImagenesSedes: no se pudieron cargar las fotos.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Una fila por sede de la lista, que anota usp_ImportarImagenSede.
    CREATE TABLE #fotos (
        id_registro     INT            IDENTITY(1, 1) PRIMARY KEY,
        nombre_estadio  VARCHAR(100)   COLLATE DATABASE_DEFAULT NOT NULL,
        archivo         NVARCHAR(100)  COLLATE DATABASE_DEFAULT NOT NULL,
        estado          VARCHAR(12)    COLLATE DATABASE_DEFAULT NOT NULL,
        formato         VARCHAR(4)     COLLATE DATABASE_DEFAULT NULL,
        kb              INT            NULL,
        motivo          NVARCHAR(2048) COLLATE DATABASE_DEFAULT NULL
    );

    -- Las 16 sedes del Mundial 2026.
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'BC Place',                N'bc_place.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Lumen Field',             N'lumen_field.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Levi''s Stadium',         N'levis_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'SoFi Stadium',            N'sofi_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Akron',           N'estadio_akron.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Azteca',          N'estadio_azteca.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio BBVA',            N'estadio_bbva.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'NRG Stadium',             N'nrg_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'AT&T Stadium',            N'att_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Arrowhead Stadium',       N'arrowhead_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Mercedes-Benz Stadium',   N'mercedes_benz_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Hard Rock Stadium',       N'hard_rock_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'BMO Field',               N'bmo_field.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Gillette Stadium',        N'gillette_stadium.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Lincoln Financial Field', N'lincoln_financial_field.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'MetLife Stadium',         N'metlife_stadium.jpg';

    -- Las 8 sedes propias del juego de datos (34_Cargar_SedesAdicionales.sql).
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Alberto J. Armando (La Bombonera)',            N'la_bombonera.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Monumental Antonio Vespucio Liberti',          N'estadio_monumental.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Libertadores de América - Ricardo E. Bochini', N'estadio_libertadores_de_america.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Jornalista Mário Filho (Maracaná)',            N'maracana.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Nacional Julio Martínez Prádanos',             N'estadio_nacional_chile.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Metropolitano Roberto Meléndez',               N'estadio_metropolitano_barranquilla.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Nacional del Perú',                            N'estadio_nacional_peru.jpg';
    EXEC Torneo.usp_ImportarImagenSede @carpeta, 'Estadio Hernando Siles',                               N'estadio_hernando_siles.jpg';

    SELECT @cargadas     = SUM(IIF(estado = 'CARGADA',     1, 0)),
           @actualizadas = SUM(IIF(estado = 'ACTUALIZADA', 1, 0)),
           @sin_cambios  = SUM(IIF(estado = 'SIN CAMBIOS', 1, 0)),
           @omitidas     = SUM(IIF(estado = 'OMITIDA',     1, 0)),
           @rechazadas   = SUM(IIF(estado = 'RECHAZADA',   1, 0))
    FROM #fotos;

    -- Primero las rechazadas y las omitidas, que son las que hay que mirar.
    IF @mostrar_resultados = 1
        SELECT nombre_estadio, archivo, estado, formato, kb, motivo
        FROM #fotos
        ORDER BY CASE estado WHEN 'RECHAZADA' THEN 1 WHEN 'OMITIDA' THEN 2 ELSE 3 END, id_registro;
END;
GO


-- Evidencia: SP de importación de fotos de sedes creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo' AND p.name IN (N'usp_ImportarImagenSede', N'usp_ImportarImagenesSedes')
ORDER BY p.name;
GO
