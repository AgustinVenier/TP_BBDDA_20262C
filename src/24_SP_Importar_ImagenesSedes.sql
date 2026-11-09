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
 Objetivo: Crear el SP que carga la foto de cada sede desde los archivos
           prebajados del repositorio:
             Torneo.usp_ImportarImagenesSedes  las 24 fotos de datos\fuentes\sedes
           Lo ejecuta 35_Importar_ImagenesSedes.sql. Una foto suelta
           se carga, reemplaza o quita con los SP de ABM de SEDE_IMAGEN
           (06_SP_ABM_Torneo.sql), que usa la aplicación abm_sedes.py.
           Requiere haber ejecutado 01 a 06. Su script de testing es
           74_Test_SP_Importar_ImagenesSedes.sql.
================================================================================

 Las fotos son la imagen principal del artículo de Wikipedia de cada estadio,
 con licencia libre, achicadas a 1280 px (ver datos\fuentes\sedes\README.md).
 Se bajaron una vez y quedan en el repositorio, así la carga no depende de
 internet y da siempre el mismo resultado.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ImportarImagenesSedes
  Carga la foto de cada sede de una lista fija (las 16 sedes del Mundial 2026
  y las 8 propias del juego de datos) desde @carpeta, la carpeta
  datos\fuentes\sedes\ del repositorio en el servidor.
  Por conjuntos, sin recorrer los archivos de a uno:
    1. Cruza la lista fija con las sedes cargadas y comprueba con
       sys.dm_os_file_exists qué archivos existen.
    2. Lee todos los archivos que existen con una sola sentencia: un
       OPENROWSET(BULK, SINGLE_BLOB) por archivo unidos con UNION ALL, armada
       con STRING_AGG. Es SQL dinámico porque OPENROWSET(BULK) solo acepta la
       ruta como literal; la ruta se arma con la carpeta validada y los nombres
       fijos de la lista, con las comillas duplicadas.
    3. Valida lo mismo que usp_SEDE_IMAGEN_Alta (PNG o JPEG por la firma, hasta
       2 MB) y da de alta o reemplaza las fotos válidas en una transacción.
  Cada sede de la lista queda en uno de estos estados:
    CARGADA      no tenía foto y se cargó
    ACTUALIZADA  tenía otra foto y se reemplazó
    SIN CAMBIOS  ya tenía esa misma foto (se comparan los hashes SHA-256)
    OMITIDA      la sede no está cargada (por ejemplo, sin ejecutar 34)
    RECHAZADA    falta el archivo, no es PNG ni JPEG o supera los 2 MB
  Las sedes que no están en la lista (las que se agregan a mano) no se tocan.
  Valida: carpeta obligatoria y existente en el servidor. Si la lectura de los
  archivos falla (por ejemplo, porque el servicio de SQL Server no tiene
  permiso sobre la carpeta), no se carga nada (THROW 50002).
  Se puede ejecutar más de una vez.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarImagenesSedes
    @carpeta      NVARCHAR(400),
    @mostrar      BIT = 1,
    @cargadas     INT = NULL OUTPUT,
    @actualizadas INT = NULL OUTPUT,
    @sin_cambios  INT = NULL OUTPUT,
    @omitidas     INT = NULL OUTPUT,
    @rechazadas   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @sql         NVARCHAR(MAX);
    DECLARE @mensaje     NVARCHAR(2048);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    SET @carpeta = NULLIF(TRIM(@carpeta), N'');
    IF @carpeta IS NOT NULL AND RIGHT(@carpeta, 1) <> N'\'
        SET @carpeta += N'\';

    IF @carpeta IS NULL
        SET @errores += @nl + N'- La carpeta de las fotos es obligatoria (ej. C:\...\datos\fuentes\sedes\).';
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.dm_os_file_exists(@carpeta) WHERE file_is_a_directory = 1)
        SET @errores += @nl + N'- La carpeta "' + @carpeta + N'" no existe en el servidor o SQL Server no la puede ver.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarImagenesSedes: no se pudieron cargar las fotos.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DECLARE @fotos TABLE (
        id_registro     INT            PRIMARY KEY,
        nombre_estadio  VARCHAR(100)   NOT NULL,
        archivo         NVARCHAR(100)  NOT NULL,
        id_sede         INT            NULL,
        existe_archivo  BIT            NULL,
        imagen          VARBINARY(MAX) NULL,
        formato         VARCHAR(4)     NULL,
        estado          VARCHAR(12)    NULL,
        motivo          NVARCHAR(400)  NULL
    );

    DECLARE @leidas TABLE (id_registro INT PRIMARY KEY, imagen VARBINARY(MAX));

    -- 1. La lista fija, cruzada con las sedes cargadas y con los archivos que existen.
    INSERT INTO @fotos (id_registro, nombre_estadio, archivo, id_sede, existe_archivo)
    SELECT f.id_registro, f.nombre_estadio, f.archivo, s.id_sede, e.file_exists
    FROM (VALUES
            ( 1, 'BC Place',                                              N'bc_place.jpg'),
            ( 2, 'Lumen Field',                                           N'lumen_field.jpg'),
            ( 3, 'Levi''s Stadium',                                       N'levis_stadium.jpg'),
            ( 4, 'SoFi Stadium',                                          N'sofi_stadium.jpg'),
            ( 5, 'Estadio Akron',                                         N'estadio_akron.jpg'),
            ( 6, 'Estadio Azteca',                                        N'estadio_azteca.jpg'),
            ( 7, 'Estadio BBVA',                                          N'estadio_bbva.jpg'),
            ( 8, 'NRG Stadium',                                           N'nrg_stadium.jpg'),
            ( 9, 'AT&T Stadium',                                          N'att_stadium.jpg'),
            (10, 'Arrowhead Stadium',                                     N'arrowhead_stadium.jpg'),
            (11, 'Mercedes-Benz Stadium',                                 N'mercedes_benz_stadium.jpg'),
            (12, 'Hard Rock Stadium',                                     N'hard_rock_stadium.jpg'),
            (13, 'BMO Field',                                             N'bmo_field.jpg'),
            (14, 'Gillette Stadium',                                      N'gillette_stadium.jpg'),
            (15, 'Lincoln Financial Field',                               N'lincoln_financial_field.jpg'),
            (16, 'MetLife Stadium',                                       N'metlife_stadium.jpg'),
            (17, 'Estadio Alberto J. Armando (La Bombonera)',             N'la_bombonera.jpg'),
            (18, 'Estadio Monumental Antonio Vespucio Liberti',           N'estadio_monumental.jpg'),
            (19, 'Estadio Libertadores de América - Ricardo E. Bochini',  N'estadio_libertadores_de_america.jpg'),
            (20, 'Estadio Jornalista Mário Filho (Maracaná)',             N'maracana.jpg'),
            (21, 'Estadio Nacional Julio Martínez Prádanos',              N'estadio_nacional_chile.jpg'),
            (22, 'Estadio Metropolitano Roberto Meléndez',                N'estadio_metropolitano_barranquilla.jpg'),
            (23, 'Estadio Nacional del Perú',                             N'estadio_nacional_peru.jpg'),
            (24, 'Estadio Hernando Siles',                                N'estadio_hernando_siles.jpg')
         ) AS f (id_registro, nombre_estadio, archivo)
    LEFT JOIN Torneo.SEDE AS s ON s.nombre_estadio = f.nombre_estadio
    CROSS APPLY sys.dm_os_file_exists(@carpeta + f.archivo) AS e;

    -- 2. Una sola lectura de todos los archivos que existen, de las sedes cargadas.
    SELECT @sql = STRING_AGG(CAST(
                      N'SELECT ' + CAST(id_registro AS NVARCHAR(10)) + N', BulkColumn FROM OPENROWSET(BULK N'''
                      + REPLACE(@carpeta + archivo, N'''', N'''''') + N''', SINGLE_BLOB) AS b'
                  AS NVARCHAR(MAX)), NCHAR(10) + N'UNION ALL ')
    FROM @fotos
    WHERE id_sede IS NOT NULL AND existe_archivo = 1;

    IF @sql IS NOT NULL
    BEGIN
        BEGIN TRY
            INSERT INTO @leidas (id_registro, imagen)
            EXEC sp_executesql @sql;
        END TRY
        BEGIN CATCH
            SET @mensaje = N'Torneo.usp_ImportarImagenesSedes: no se cargó ninguna foto, falló la lectura de los archivos de '
                         + @carpeta + N' (' + ERROR_MESSAGE() + N').';
            THROW 50002, @mensaje, 1;
        END CATCH;
    END;

    -- 3. Validación (las reglas de usp_SEDE_IMAGEN_Alta) y estado de cada sede.
    UPDATE f
    SET imagen  = l.imagen,
        formato = CASE
                      WHEN SUBSTRING(l.imagen, 1, 8) = 0x89504E470D0A1A0A THEN 'PNG'
                      WHEN SUBSTRING(l.imagen, 1, 3) = 0xFFD8FF THEN 'JPEG'
                  END
    FROM @fotos AS f
    INNER JOIN @leidas AS l ON l.id_registro = f.id_registro;

    UPDATE f
    SET estado = CASE
                     WHEN f.id_sede IS NULL THEN 'OMITIDA'
                     WHEN f.existe_archivo = 0 OR f.formato IS NULL
                          OR DATALENGTH(f.imagen) NOT BETWEEN 1 AND 2097152 THEN 'RECHAZADA'
                     WHEN si.id_sede IS NULL THEN 'CARGADA'
                     WHEN HASHBYTES('SHA2_256', si.imagen) = HASHBYTES('SHA2_256', f.imagen) THEN 'SIN CAMBIOS'
                     ELSE 'ACTUALIZADA'
                 END,
        motivo = CASE
                     WHEN f.id_sede IS NULL THEN N'La sede no está cargada.'
                     WHEN f.existe_archivo = 0 THEN N'No existe el archivo ' + f.archivo + N' en la carpeta.'
                     WHEN f.formato IS NULL THEN N'El archivo ' + f.archivo + N' no es PNG ni JPEG.'
                     WHEN DATALENGTH(f.imagen) > 2097152 THEN
                          N'El archivo ' + f.archivo + N' pesa ' + CAST(CEILING(DATALENGTH(f.imagen) / 1024.0) AS NVARCHAR(10))
                          + N' KB y el máximo es 2048 KB (2 MB).'
                 END
    FROM @fotos AS f
    LEFT JOIN Torneo.SEDE_IMAGEN AS si ON si.id_sede = f.id_sede;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        INSERT INTO Torneo.SEDE_IMAGEN (id_sede, imagen, formato)
        SELECT id_sede, imagen, formato
        FROM @fotos
        WHERE estado = 'CARGADA';

        UPDATE si
        SET imagen = f.imagen, formato = f.formato, fecha_carga = SYSDATETIME()
        FROM Torneo.SEDE_IMAGEN AS si
        INNER JOIN @fotos AS f ON f.id_sede = si.id_sede
        WHERE f.estado = 'ACTUALIZADA';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @cargadas     = SUM(IIF(estado = 'CARGADA',     1, 0)),
           @actualizadas = SUM(IIF(estado = 'ACTUALIZADA', 1, 0)),
           @sin_cambios  = SUM(IIF(estado = 'SIN CAMBIOS', 1, 0)),
           @omitidas     = SUM(IIF(estado = 'OMITIDA',     1, 0)),
           @rechazadas   = SUM(IIF(estado = 'RECHAZADA',   1, 0))
    FROM @fotos;

    IF @mostrar = 1
        SELECT f.nombre_estadio, f.archivo, f.estado, f.formato,
               CAST(CEILING(DATALENGTH(f.imagen) / 1024.0) AS INT) AS kb, f.motivo
        FROM @fotos AS f
        ORDER BY CASE f.estado WHEN 'RECHAZADA' THEN 1 WHEN 'OMITIDA' THEN 2 ELSE 3 END, f.id_registro;
END;
GO


-- Evidencia: SP de importación de fotos de sedes creado.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo' AND p.name = N'usp_ImportarImagenesSedes';
GO
