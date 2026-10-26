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

 Fecha: 25/10/2026
 Archivo: 05_SP_ABM_Torneo.sql
 Objetivo: Crear los stored procedures de alta, baja y modificación de las
           tablas del esquema Torneo: SEDE, SELECCION, LISTA_CONVOCADOS,
           JUGADOR, PERSONA_CUERPO_TECNICO y PARTIDO. Siguen las convenciones
           descriptas en 04_SP_ABM_DatosGenerales.sql. Requiere haber
           ejecutado 00 a 04. Su script de testing es 55_Test_SP_ABM_Torneo.sql.
================================================================================

 Particularidades de este esquema:
   - JUGADOR: la baja es lógica (fecha y motivo de baja), como piden las
     bajas de último momento. Con @eliminar_registro = 1 se borra el
     registro, solo si el jugador no figura en ningún partido.
   - PARTIDO: se informa la fecha y hora UTC o la local de la sede, y el SP
     calcula la otra con AT TIME ZONE y el huso de la sede, para que nunca
     queden inconsistentes. Estados posibles y pasos permitidos:
       PROGRAMADO -> EN_JUEGO, SUSPENDIDO o FINALIZADO (carga histórica)
       EN_JUEGO   -> FINALIZADO, SUSPENDIDO o PROGRAMADO (sin eventos)
       SUSPENDIDO -> PROGRAMADO
       FINALIZADO -> EN_JUEGO (reapertura para corregir eventos: borra el
                     resultado, que se vuelve a cargar al finalizar)
   - Las altas completas de una sede (con sus 4 espacios) y de una selección
     (con su lista y su director técnico) están en los SP de negocio de los
     scripts 10 y 11.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   SEDE
   ============================================================================ */

/*
  usp_SEDE_Alta
  Valida: nombre del estadio obligatorio, de hasta 100 caracteres y no
  repetido; ciudad obligatoria, de hasta 80; país existente; capacidad mayor
  que cero; huso horario existente en sys.time_zone_info; latitud y longitud
  juntas y dentro de rango.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_SEDE_Alta
    @nombre_estadio VARCHAR(200),
    @ciudad         VARCHAR(200),
    @id_pais        SMALLINT,
    @capacidad      INT,
    @huso_horario   VARCHAR(100),
    @latitud        DECIMAL(9,6) = NULL,
    @longitud       DECIMAL(9,6) = NULL,
    @id_sede        INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre_estadio = NULLIF(TRIM(@nombre_estadio), '');
    SET @ciudad         = NULLIF(TRIM(@ciudad), '');
    SET @huso_horario   = NULLIF(TRIM(@huso_horario), '');

    IF @nombre_estadio IS NULL
        SET @errores += @nl + N'- El nombre del estadio es obligatorio.';
    ELSE IF LEN(@nombre_estadio) > 100
        SET @errores += @nl + N'- El nombre del estadio no puede superar los 100 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio = @nombre_estadio)
        SET @errores += @nl + N'- Ya existe la sede "' + @nombre_estadio + N'".';

    IF @ciudad IS NULL
        SET @errores += @nl + N'- La ciudad es obligatoria.';
    ELSE IF LEN(@ciudad) > 80
        SET @errores += @nl + N'- La ciudad no puede superar los 80 caracteres.';

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @capacidad IS NULL
        SET @errores += @nl + N'- La capacidad es obligatoria.';
    ELSE IF @capacidad <= 0
        SET @errores += @nl + N'- La capacidad debe ser mayor que cero.';

    IF @huso_horario IS NULL
        SET @errores += @nl + N'- El huso horario es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @huso_horario)
        SET @errores += @nl + N'- El huso horario "' + @huso_horario + N'" no existe en sys.time_zone_info.';

    IF (@latitud IS NULL AND @longitud IS NOT NULL) OR (@latitud IS NOT NULL AND @longitud IS NULL)
        SET @errores += @nl + N'- La latitud y la longitud se informan juntas.';
    IF @latitud NOT BETWEEN -90 AND 90
        SET @errores += @nl + N'- La latitud debe estar entre -90 y 90.';
    IF @longitud NOT BETWEEN -180 AND 180
        SET @errores += @nl + N'- La longitud debe estar entre -180 y 180.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_SEDE_Alta: no se pudo dar de alta la sede.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @huso_horario = name FROM sys.time_zone_info WHERE name = @huso_horario;

    INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario, latitud, longitud)
    VALUES (@nombre_estadio, @ciudad, @id_pais, @capacidad, @huso_horario, @latitud, @longitud);

    SET @id_sede = SCOPE_IDENTITY();
END;
GO


/*
  usp_SEDE_Modificacion
  Valida: que la sede exista y que se informe al menos un dato; para cada dato
  informado, las mismas reglas del alta; que la capacidad nueva no quede por
  debajo de la asistencia de un partido ya jugado en la sede.
  Si cambia el huso horario, recalcula en la misma transacción la hora local
  de los partidos de la sede a partir de su hora UTC.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_SEDE_Modificacion
    @id_sede        INT,
    @nombre_estadio VARCHAR(200) = NULL,
    @ciudad         VARCHAR(200) = NULL,
    @id_pais        SMALLINT     = NULL,
    @capacidad      INT          = NULL,
    @huso_horario   VARCHAR(100) = NULL,
    @latitud        DECIMAL(9,6) = NULL,
    @longitud       DECIMAL(9,6) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @max_asistencia INT;
    DECLARE @tran_propia    BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    SET @nombre_estadio = NULLIF(TRIM(@nombre_estadio), '');
    SET @ciudad         = NULLIF(TRIM(@ciudad), '');
    SET @huso_horario   = NULLIF(TRIM(@huso_horario), '');

    IF @id_sede IS NULL
        SET @errores += @nl + N'- El id de la sede es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SEDE WHERE id_sede = @id_sede)
        SET @errores += @nl + N'- No existe una sede con id ' + CAST(@id_sede AS NVARCHAR(10)) + N'.';

    IF @nombre_estadio IS NULL AND @ciudad IS NULL AND @id_pais IS NULL AND @capacidad IS NULL
       AND @huso_horario IS NULL AND @latitud IS NULL AND @longitud IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@nombre_estadio) > 100
        SET @errores += @nl + N'- El nombre del estadio no puede superar los 100 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio = @nombre_estadio AND id_sede <> @id_sede)
        SET @errores += @nl + N'- Ya existe otra sede "' + @nombre_estadio + N'".';

    IF LEN(@ciudad) > 80
        SET @errores += @nl + N'- La ciudad no puede superar los 80 caracteres.';

    IF @id_pais IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @capacidad <= 0
        SET @errores += @nl + N'- La capacidad debe ser mayor que cero.';
    ELSE IF @capacidad IS NOT NULL
    BEGIN
        SELECT @max_asistencia = MAX(asistencia)
        FROM Torneo.PARTIDO
        WHERE id_sede = @id_sede AND asistencia IS NOT NULL;
        IF @capacidad < @max_asistencia
            SET @errores += @nl + N'- La capacidad no puede ser menor que la asistencia ya registrada en la sede ('
                          + CAST(@max_asistencia AS NVARCHAR(10)) + N').';
    END;

    IF @huso_horario IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @huso_horario)
        SET @errores += @nl + N'- El huso horario "' + @huso_horario + N'" no existe en sys.time_zone_info.';

    IF (@latitud IS NULL AND @longitud IS NOT NULL) OR (@latitud IS NOT NULL AND @longitud IS NULL)
        SET @errores += @nl + N'- La latitud y la longitud se informan juntas.';
    IF @latitud NOT BETWEEN -90 AND 90
        SET @errores += @nl + N'- La latitud debe estar entre -90 y 90.';
    IF @longitud NOT BETWEEN -180 AND 180
        SET @errores += @nl + N'- La longitud debe estar entre -180 y 180.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_SEDE_Modificacion: no se pudo modificar la sede.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @huso_horario = name FROM sys.time_zone_info WHERE name = @huso_horario;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE Torneo.SEDE
        SET nombre_estadio = ISNULL(@nombre_estadio, nombre_estadio),
            ciudad         = ISNULL(@ciudad, ciudad),
            id_pais        = ISNULL(@id_pais, id_pais),
            capacidad      = ISNULL(@capacidad, capacidad),
            huso_horario   = ISNULL(@huso_horario, huso_horario),
            latitud        = ISNULL(@latitud, latitud),
            longitud       = ISNULL(@longitud, longitud)
        WHERE id_sede = @id_sede;

        IF @huso_horario IS NOT NULL
            UPDATE Torneo.PARTIDO
            SET fecha_hora_local = CONVERT(DATETIME2(0), (fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE @huso_horario)
            WHERE id_sede = @id_sede;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_SEDE_Baja
  Valida: que la sede exista y que no tenga partidos ni espacios publicitarios.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_SEDE_Baja
    @id_sede INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_sede IS NULL
        SET @errores += @nl + N'- El id de la sede es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SEDE WHERE id_sede = @id_sede)
        SET @errores += @nl + N'- No existe una sede con id ' + CAST(@id_sede AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- La referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'Torneo.PARTIDO', COUNT(*)
                FROM Torneo.PARTIDO WHERE id_sede = @id_sede
                UNION ALL
                SELECT N'Publicidad.ESPACIO_PUBLICITARIO', COUNT(*)
                FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id_sede
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_SEDE_Baja: no se pudo dar de baja la sede.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.SEDE WHERE id_sede = @id_sede;
END;
GO


/* ============================================================================
   SELECCION
   ============================================================================ */

/*
  usp_SELECCION_Alta
  Valida: país obligatorio, existente y sin otra selección; confederación
  obligatoria y válida; grupo opcional, una letra de la A a la L, que no tenga
  ya SELECCIONES_POR_GRUPO selecciones.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_SELECCION_Alta
    @id_pais        SMALLINT,
    @confederacion  VARCHAR(20),
    @grupo          VARCHAR(5) = NULL,
    @id_seleccion   INT        = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @nl              NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @cupo_grupo      TINYINT        = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                               WHERE codigo = 'SELECCIONES_POR_GRUPO');
    DECLARE @en_grupo        INT;

    SET @confederacion = UPPER(NULLIF(TRIM(@confederacion), ''));
    SET @grupo         = UPPER(NULLIF(TRIM(@grupo), ''));

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- Ese país ya tiene una selección registrada.';

    IF @confederacion IS NULL
        SET @errores += @nl + N'- La confederación es obligatoria.';
    ELSE IF @confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')
        SET @errores += @nl + N'- La confederación debe ser AFC, CAF, CONCACAF, CONMEBOL, OFC o UEFA.';

    IF @grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]'
        SET @errores += @nl + N'- El grupo debe ser una letra de la A a la L.';
    ELSE IF @grupo IS NOT NULL
    BEGIN
        SELECT @en_grupo = COUNT(*) FROM Torneo.SELECCION WHERE grupo = @grupo;
        IF @en_grupo >= @cupo_grupo
            SET @errores += @nl + N'- El grupo ' + @grupo + N' ya tiene sus '
                          + CAST(@cupo_grupo AS NVARCHAR(3)) + N' selecciones (SELECCIONES_POR_GRUPO).';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_SELECCION_Alta: no se pudo dar de alta la selección.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo)
    VALUES (@id_pais, @confederacion, @grupo);

    SET @id_seleccion = SCOPE_IDENTITY();
END;
GO


/*
  usp_SELECCION_Modificacion
  Valida: que la selección exista y que se informe al menos un dato; la
  confederación y el grupo con las reglas del alta; que no se cambie el grupo
  de una selección que ya tiene partidos de la fase de grupos. El país no se
  modifica: identifica a la selección.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_SELECCION_Modificacion
    @id_seleccion   INT,
    @confederacion  VARCHAR(20) = NULL,
    @grupo          VARCHAR(5)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @cupo_grupo  TINYINT        = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                           WHERE codigo = 'SELECCIONES_POR_GRUPO');
    DECLARE @grupo_actual CHAR(1);
    DECLARE @existe       BIT = 0;
    DECLARE @en_grupo     INT;

    SET @confederacion = UPPER(NULLIF(TRIM(@confederacion), ''));
    SET @grupo         = UPPER(NULLIF(TRIM(@grupo), ''));

    SELECT @existe = 1, @grupo_actual = grupo FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion;

    IF @id_seleccion IS NULL
        SET @errores += @nl + N'- El id de la selección es obligatorio.';
    ELSE IF @existe = 0
        SET @errores += @nl + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

    IF @confederacion IS NULL AND @grupo IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')
        SET @errores += @nl + N'- La confederación debe ser AFC, CAF, CONCACAF, CONMEBOL, OFC o UEFA.';

    IF @grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]'
        SET @errores += @nl + N'- El grupo debe ser una letra de la A a la L.';
    ELSE IF @grupo IS NOT NULL AND @grupo <> ISNULL(@grupo_actual, '')
    BEGIN
        SELECT @en_grupo = COUNT(*) FROM Torneo.SELECCION WHERE grupo = @grupo;
        IF @en_grupo >= @cupo_grupo
            SET @errores += @nl + N'- El grupo ' + @grupo + N' ya tiene sus '
                          + CAST(@cupo_grupo AS NVARCHAR(3)) + N' selecciones (SELECCIONES_POR_GRUPO).';
        IF EXISTS (SELECT 1 FROM Torneo.PARTIDO
                   WHERE fase = 'GRUPOS'
                     AND @id_seleccion IN (id_seleccion_local, id_seleccion_visitante))
            SET @errores += @nl + N'- La selección ya tiene partidos de la fase de grupos: no se puede cambiar su grupo.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_SELECCION_Modificacion: no se pudo modificar la selección.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.SELECCION
    SET confederacion = ISNULL(@confederacion, confederacion),
        grupo         = ISNULL(@grupo, grupo)
    WHERE id_seleccion = @id_seleccion;
END;
GO


/*
  usp_SELECCION_Baja
  Valida: que la selección exista y que no tenga lista de convocados, cuerpo
  técnico, partidos ni formaciones.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_SELECCION_Baja
    @id_seleccion INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_seleccion IS NULL
        SET @errores += @nl + N'- El id de la selección es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- La referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'Torneo.LISTA_CONVOCADOS', COUNT(*)
                FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @id_seleccion
                UNION ALL
                SELECT N'Torneo.PERSONA_CUERPO_TECNICO', COUNT(*)
                FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion
                UNION ALL
                SELECT N'Torneo.PARTIDO', COUNT(*)
                FROM Torneo.PARTIDO WHERE @id_seleccion IN (id_seleccion_local, id_seleccion_visitante)
                UNION ALL
                SELECT N'DesarrolloPartido.FORMACION', COUNT(*)
                FROM DesarrolloPartido.FORMACION WHERE id_seleccion = @id_seleccion
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_SELECCION_Baja: no se pudo dar de baja la selección.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion;
END;
GO


/* ============================================================================
   LISTA_CONVOCADOS
   ============================================================================ */

/*
  usp_LISTA_CONVOCADOS_Alta
  Valida: selección obligatoria, existente y sin lista; fecha de presentación
  obligatoria, no futura y no posterior al primer partido de la selección.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_LISTA_CONVOCADOS_Alta
    @id_seleccion        INT,
    @fecha_presentacion  DATE,
    @id_lista            INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @primer_partido DATE;

    IF @id_seleccion IS NULL
        SET @errores += @nl + N'- La selección es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- La selección ya tiene su lista de convocados.';

    SELECT @primer_partido = MIN(CAST(fecha_hora_local AS DATE))
    FROM Torneo.PARTIDO
    WHERE @id_seleccion IN (id_seleccion_local, id_seleccion_visitante);

    IF @fecha_presentacion IS NULL
        SET @errores += @nl + N'- La fecha de presentación es obligatoria.';
    ELSE IF @fecha_presentacion > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de presentación no puede ser futura.';
    ELSE IF @fecha_presentacion > @primer_partido
        SET @errores += @nl + N'- La lista se presenta antes del primer partido de la selección ('
                      + CONVERT(NVARCHAR(10), @primer_partido, 103) + N').';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_LISTA_CONVOCADOS_Alta: no se pudo dar de alta la lista de convocados.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion)
    VALUES (@id_seleccion, @fecha_presentacion);

    SET @id_lista = SCOPE_IDENTITY();
END;
GO


/*
  usp_LISTA_CONVOCADOS_Modificacion
  Valida: que la lista exista; la fecha con las reglas del alta y que no quede
  posterior al alta de alguno de sus jugadores. La selección no se modifica.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_LISTA_CONVOCADOS_Modificacion
    @id_lista            INT,
    @fecha_presentacion  DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_seleccion   INT;
    DECLARE @primer_partido DATE;
    DECLARE @primer_alta    DATE;

    SELECT @id_seleccion = id_seleccion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;

    IF @id_lista IS NULL
        SET @errores += @nl + N'- El id de la lista es obligatorio.';
    ELSE IF @id_seleccion IS NULL
        SET @errores += @nl + N'- No existe una lista con id ' + CAST(@id_lista AS NVARCHAR(10)) + N'.';

    SELECT @primer_partido = MIN(CAST(fecha_hora_local AS DATE))
    FROM Torneo.PARTIDO
    WHERE @id_seleccion IN (id_seleccion_local, id_seleccion_visitante);

    SELECT @primer_alta = MIN(fecha_alta) FROM Torneo.JUGADOR WHERE id_lista = @id_lista;

    IF @fecha_presentacion IS NULL
        SET @errores += @nl + N'- La fecha de presentación es obligatoria.';
    ELSE
    BEGIN
        IF @fecha_presentacion > CONVERT(DATE, GETDATE())
            SET @errores += @nl + N'- La fecha de presentación no puede ser futura.';
        IF @fecha_presentacion > @primer_partido
            SET @errores += @nl + N'- La lista se presenta antes del primer partido de la selección ('
                          + CONVERT(NVARCHAR(10), @primer_partido, 103) + N').';
        IF @fecha_presentacion > @primer_alta
            SET @errores += @nl + N'- Hay jugadores dados de alta antes de esa fecha ('
                          + CONVERT(NVARCHAR(10), @primer_alta, 103) + N').';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_LISTA_CONVOCADOS_Modificacion: no se pudo modificar la lista de convocados.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.LISTA_CONVOCADOS
    SET fecha_presentacion = @fecha_presentacion
    WHERE id_lista = @id_lista;
END;
GO


/*
  usp_LISTA_CONVOCADOS_Baja
  Valida: que la lista exista y que no tenga jugadores.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_LISTA_CONVOCADOS_Baja
    @id_lista INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores   NVARCHAR(2048) = N'';
    DECLARE @nl        NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @jugadores INT;

    IF @id_lista IS NULL
        SET @errores += @nl + N'- El id de la lista es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista)
        SET @errores += @nl + N'- No existe una lista con id ' + CAST(@id_lista AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @jugadores = COUNT(*) FROM Torneo.JUGADOR WHERE id_lista = @id_lista;
        IF @jugadores > 0
            SET @errores += @nl + N'- La referencian ' + CAST(@jugadores AS NVARCHAR(10))
                          + N' registro(s) de Torneo.JUGADOR.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_LISTA_CONVOCADOS_Baja: no se pudo dar de baja la lista de convocados.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
END;
GO


/* ============================================================================
   JUGADOR
   ============================================================================ */

/*
  usp_JUGADOR_Alta
  Valida: lista existente; nombre y apellido obligatorios, de hasta 60
  caracteres, y que el jugador no figure ya en la lista; posición válida;
  dorsal entre 1 y 99 y libre entre los convocados activos; fecha de
  nacimiento no futura; club de hasta 100 caracteres; país de nacimiento
  existente; fecha de alta no futura ni anterior a la presentación de la
  lista (si no se informa, es la de hoy); motivo de hasta 200 caracteres; que
  la lista no tenga ya MAX_CONVOCADOS jugadores activos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_JUGADOR_Alta
    @id_lista            INT,
    @nombre              NVARCHAR(120),
    @apellido            NVARCHAR(120),
    @posicion_habitual   VARCHAR(30),
    @dorsal              TINYINT,
    @fecha_nacimiento    DATE          = NULL,
    @club_origen         NVARCHAR(200) = NULL,
    @id_pais_nacimiento  SMALLINT      = NULL,
    @fecha_alta          DATE          = NULL,
    @motivo_alta         VARCHAR(400)  = NULL,
    @id_jugador          INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores            NVARCHAR(2048) = N'';
    DECLARE @nl                 NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @fecha_presentacion DATE;
    DECLARE @max_convocados     TINYINT        = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                                  WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @activos            INT;
    DECLARE @dueno_dorsal       NVARCHAR(130);

    SET @nombre            = NULLIF(TRIM(@nombre), N'');
    SET @apellido          = NULLIF(TRIM(@apellido), N'');
    SET @posicion_habitual = UPPER(NULLIF(TRIM(@posicion_habitual), ''));
    SET @club_origen       = NULLIF(TRIM(@club_origen), N'');
    SET @motivo_alta       = NULLIF(TRIM(@motivo_alta), '');
    SET @fecha_alta        = ISNULL(@fecha_alta, CONVERT(DATE, GETDATE()));

    IF @id_lista IS NULL
        SET @errores += @nl + N'- La lista de convocados es obligatoria.';
    ELSE
    BEGIN
        SELECT @fecha_presentacion = fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
        IF @fecha_presentacion IS NULL
            SET @errores += @nl + N'- No existe una lista con id ' + CAST(@id_lista AS NVARCHAR(10)) + N'.';
    END;

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';

    IF @apellido IS NULL
        SET @errores += @nl + N'- El apellido es obligatorio.';
    ELSE IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';

    IF EXISTS (SELECT 1 FROM Torneo.JUGADOR
               WHERE id_lista = @id_lista AND apellido = @apellido AND nombre = @nombre)
        SET @errores += @nl + N'- ' + @nombre + N' ' + @apellido
                      + N' ya figura en la lista (activo o dado de baja).';

    IF @posicion_habitual IS NULL
        SET @errores += @nl + N'- La posición habitual es obligatoria.';
    ELSE IF @posicion_habitual NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')
        SET @errores += @nl + N'- La posición debe ser ARQUERO, DEFENSOR, MEDIOCAMPISTA o DELANTERO.';

    IF @dorsal IS NULL
        SET @errores += @nl + N'- El dorsal es obligatorio.';
    ELSE IF @dorsal NOT BETWEEN 1 AND 99
        SET @errores += @nl + N'- El dorsal debe estar entre 1 y 99.';
    ELSE
    BEGIN
        SELECT @dueno_dorsal = nombre + N' ' + apellido
        FROM Torneo.JUGADOR
        WHERE id_lista = @id_lista AND dorsal = @dorsal AND fecha_baja IS NULL;
        IF @dueno_dorsal IS NOT NULL
            SET @errores += @nl + N'- El dorsal ' + CAST(@dorsal AS NVARCHAR(3)) + N' ya lo usa ' + @dueno_dorsal + N'.';
    END;

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF LEN(@club_origen) > 100
        SET @errores += @nl + N'- El club de origen no puede superar los 100 caracteres.';

    IF @id_pais_nacimiento IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais_nacimiento)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais_nacimiento AS NVARCHAR(10)) + N'.';

    IF @fecha_alta > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de alta no puede ser futura.';
    ELSE IF @fecha_alta < @fecha_presentacion
        SET @errores += @nl + N'- La fecha de alta no puede ser anterior a la presentación de la lista ('
                      + CONVERT(NVARCHAR(10), @fecha_presentacion, 103) + N').';

    IF LEN(@motivo_alta) > 200
        SET @errores += @nl + N'- El motivo de alta no puede superar los 200 caracteres.';

    SELECT @activos = COUNT(*) FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND fecha_baja IS NULL;
    IF @activos >= @max_convocados
        SET @errores += @nl + N'- La lista ya tiene ' + CAST(@activos AS NVARCHAR(3))
                      + N' convocados activos, el máximo permitido (MAX_CONVOCADOS).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_JUGADOR_Alta: no se pudo dar de alta el jugador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.JUGADOR
        (id_lista, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, club_origen,
         posicion_habitual, dorsal, fecha_alta, motivo_alta)
    VALUES
        (@id_lista, @id_pais_nacimiento, @nombre, @apellido, @fecha_nacimiento, @club_origen,
         @posicion_habitual, @dorsal, @fecha_alta, @motivo_alta);

    SET @id_jugador = SCOPE_IDENTITY();
END;
GO


/*
  usp_JUGADOR_Modificacion
  Valida: que el jugador exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta (sin contar al propio jugador).
  La lista y las fechas de alta y baja no se modifican acá: la baja tiene su
  propio SP y el reemplazo es Torneo.usp_ReemplazarJugador.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_JUGADOR_Modificacion
    @id_jugador          INT,
    @nombre              NVARCHAR(120) = NULL,
    @apellido            NVARCHAR(120) = NULL,
    @posicion_habitual   VARCHAR(30)   = NULL,
    @dorsal              TINYINT       = NULL,
    @fecha_nacimiento    DATE          = NULL,
    @club_origen         NVARCHAR(200) = NULL,
    @id_pais_nacimiento  SMALLINT      = NULL,
    @motivo_alta         VARCHAR(400)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_lista       INT;
    DECLARE @activo         BIT;
    DECLARE @nombre_final   NVARCHAR(60);
    DECLARE @apellido_final NVARCHAR(60);
    DECLARE @dueno_dorsal   NVARCHAR(130);

    SET @nombre            = NULLIF(TRIM(@nombre), N'');
    SET @apellido          = NULLIF(TRIM(@apellido), N'');
    SET @posicion_habitual = UPPER(NULLIF(TRIM(@posicion_habitual), ''));
    SET @club_origen       = NULLIF(TRIM(@club_origen), N'');
    SET @motivo_alta       = NULLIF(TRIM(@motivo_alta), '');

    SELECT @id_lista       = id_lista,
           @activo         = IIF(fecha_baja IS NULL, 1, 0),
           @nombre_final   = ISNULL(@nombre, nombre),
           @apellido_final = ISNULL(@apellido, apellido)
    FROM Torneo.JUGADOR
    WHERE id_jugador = @id_jugador;

    IF @id_jugador IS NULL
        SET @errores += @nl + N'- El id del jugador es obligatorio.';
    ELSE IF @id_lista IS NULL
        SET @errores += @nl + N'- No existe un jugador con id ' + CAST(@id_jugador AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL AND @apellido IS NULL AND @posicion_habitual IS NULL AND @dorsal IS NULL
       AND @fecha_nacimiento IS NULL AND @club_origen IS NULL AND @id_pais_nacimiento IS NULL
       AND @motivo_alta IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';
    IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';
    IF (@nombre IS NOT NULL OR @apellido IS NOT NULL)
       AND EXISTS (SELECT 1 FROM Torneo.JUGADOR
                   WHERE id_lista = @id_lista AND apellido = @apellido_final AND nombre = @nombre_final
                     AND id_jugador <> @id_jugador)
        SET @errores += @nl + N'- Ya hay otro ' + @nombre_final + N' ' + @apellido_final + N' en la lista.';

    IF @posicion_habitual NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')
        SET @errores += @nl + N'- La posición debe ser ARQUERO, DEFENSOR, MEDIOCAMPISTA o DELANTERO.';

    IF @dorsal NOT BETWEEN 1 AND 99
        SET @errores += @nl + N'- El dorsal debe estar entre 1 y 99.';
    ELSE IF @dorsal IS NOT NULL AND @activo = 1
    BEGIN
        SELECT @dueno_dorsal = nombre + N' ' + apellido
        FROM Torneo.JUGADOR
        WHERE id_lista = @id_lista AND dorsal = @dorsal AND fecha_baja IS NULL AND id_jugador <> @id_jugador;
        IF @dueno_dorsal IS NOT NULL
            SET @errores += @nl + N'- El dorsal ' + CAST(@dorsal AS NVARCHAR(3)) + N' ya lo usa ' + @dueno_dorsal + N'.';
    END;

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF LEN(@club_origen) > 100
        SET @errores += @nl + N'- El club de origen no puede superar los 100 caracteres.';

    IF @id_pais_nacimiento IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais_nacimiento)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais_nacimiento AS NVARCHAR(10)) + N'.';

    IF LEN(@motivo_alta) > 200
        SET @errores += @nl + N'- El motivo de alta no puede superar los 200 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_JUGADOR_Modificacion: no se pudo modificar el jugador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.JUGADOR
    SET nombre             = ISNULL(@nombre, nombre),
        apellido           = ISNULL(@apellido, apellido),
        posicion_habitual  = ISNULL(@posicion_habitual, posicion_habitual),
        dorsal             = ISNULL(@dorsal, dorsal),
        fecha_nacimiento   = ISNULL(@fecha_nacimiento, fecha_nacimiento),
        club_origen        = ISNULL(@club_origen, club_origen),
        id_pais_nacimiento = ISNULL(@id_pais_nacimiento, id_pais_nacimiento),
        motivo_alta        = ISNULL(@motivo_alta, motivo_alta)
    WHERE id_jugador = @id_jugador;
END;
GO


/*
  usp_JUGADOR_Baja
  Baja lógica (por defecto): registra la fecha y el motivo de la baja, y el
  jugador conserva su historial. Valida: que el jugador exista y esté activo;
  motivo obligatorio de hasta 200 caracteres; fecha (hoy si no se informa)
  no futura ni anterior al alta; que no figure en la formación de un partido
  que todavía no terminó. La baja puede dejar la lista por debajo del
  mínimo: el reemplazo se registra con Torneo.usp_ReemplazarJugador, que hace
  las dos cosas en una transacción.
  Con @eliminar_registro = 1 borra el registro (alta cargada por error):
  valida que el jugador no figure en formaciones, cambios, goles ni tarjetas.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_JUGADOR_Baja
    @id_jugador         INT,
    @motivo_baja        VARCHAR(400) = NULL,
    @fecha_baja         DATE         = NULL,
    @eliminar_registro  BIT          = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @fecha_alta     DATE;
    DECLARE @fecha_baja_act DATE;
    DECLARE @partido        TINYINT;

    SET @motivo_baja = NULLIF(TRIM(@motivo_baja), '');
    SET @fecha_baja  = ISNULL(@fecha_baja, CONVERT(DATE, GETDATE()));

    SELECT @fecha_alta = fecha_alta, @fecha_baja_act = fecha_baja
    FROM Torneo.JUGADOR
    WHERE id_jugador = @id_jugador;

    IF @id_jugador IS NULL
        SET @errores += @nl + N'- El id del jugador es obligatorio.';
    ELSE IF @fecha_alta IS NULL
        SET @errores += @nl + N'- No existe un jugador con id ' + CAST(@id_jugador AS NVARCHAR(10)) + N'.';
    ELSE IF ISNULL(@eliminar_registro, 0) = 0
    BEGIN
        IF @fecha_baja_act IS NOT NULL
            SET @errores += @nl + N'- El jugador ya fue dado de baja el '
                          + CONVERT(NVARCHAR(10), @fecha_baja_act, 103) + N'.';

        IF @motivo_baja IS NULL
            SET @errores += @nl + N'- El motivo de la baja es obligatorio.';
        ELSE IF LEN(@motivo_baja) > 200
            SET @errores += @nl + N'- El motivo de la baja no puede superar los 200 caracteres.';

        IF @fecha_baja > CONVERT(DATE, GETDATE())
            SET @errores += @nl + N'- La fecha de baja no puede ser futura.';
        ELSE IF @fecha_baja < @fecha_alta
            SET @errores += @nl + N'- La fecha de baja no puede ser anterior al alta ('
                          + CONVERT(NVARCHAR(10), @fecha_alta, 103) + N').';

        SELECT TOP (1) @partido = p.numero_partido
        FROM DesarrolloPartido.ALINEACION AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
        WHERE a.id_jugador = @id_jugador AND p.estado IN ('PROGRAMADO', 'EN_JUEGO');
        IF @partido IS NOT NULL
            SET @errores += @nl + N'- El jugador figura en la formación del partido '
                          + CAST(@partido AS NVARCHAR(3)) + N', que todavía no terminó.';
    END
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- Lo referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'DesarrolloPartido.ALINEACION', COUNT(*)
                FROM DesarrolloPartido.ALINEACION WHERE id_jugador = @id_jugador
                UNION ALL
                SELECT N'DesarrolloPartido.CAMBIO', COUNT(*)
                FROM DesarrolloPartido.CAMBIO WHERE @id_jugador IN (id_jugador_sale, id_jugador_entra)
                UNION ALL
                SELECT N'DesarrolloPartido.GOL', COUNT(*)
                FROM DesarrolloPartido.GOL WHERE @id_jugador IN (id_jugador_autor, id_jugador_asistencia)
                UNION ALL
                SELECT N'DesarrolloPartido.AMONESTACION', COUNT(*)
                FROM DesarrolloPartido.AMONESTACION WHERE id_jugador = @id_jugador
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_JUGADOR_Baja: no se pudo dar de baja el jugador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    IF @eliminar_registro = 1
        DELETE FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;
    ELSE
        UPDATE Torneo.JUGADOR
        SET fecha_baja  = @fecha_baja,
            motivo_baja = @motivo_baja
        WHERE id_jugador = @id_jugador;
END;
GO


/* ============================================================================
   PERSONA_CUERPO_TECNICO
   ============================================================================ */

/*
  usp_PERSONA_CUERPO_TECNICO_Alta
  Valida: selección existente; nombre y apellido obligatorios, de hasta 60
  caracteres, y que la persona no figure ya en el cuerpo técnico; rol válido
  y un solo director técnico por selección; fecha de nacimiento no futura;
  país de nacimiento existente.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_PERSONA_CUERPO_TECNICO_Alta
    @id_seleccion        INT,
    @nombre              NVARCHAR(120),
    @apellido            NVARCHAR(120),
    @rol                 VARCHAR(40),
    @fecha_nacimiento    DATE     = NULL,
    @id_pais_nacimiento  SMALLINT = NULL,
    @id_persona_ct       INT      = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre   = NULLIF(TRIM(@nombre), N'');
    SET @apellido = NULLIF(TRIM(@apellido), N'');
    SET @rol      = UPPER(NULLIF(TRIM(@rol), ''));

    IF @id_seleccion IS NULL
        SET @errores += @nl + N'- La selección es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';

    IF @apellido IS NULL
        SET @errores += @nl + N'- El apellido es obligatorio.';
    ELSE IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';

    IF EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO
               WHERE id_seleccion = @id_seleccion AND apellido = @apellido AND nombre = @nombre)
        SET @errores += @nl + N'- ' + @nombre + N' ' + @apellido + N' ya integra el cuerpo técnico.';

    IF @rol IS NULL
        SET @errores += @nl + N'- El rol es obligatorio.';
    ELSE IF @rol NOT IN ('DIRECTOR_TECNICO', 'AYUDANTE_CAMPO', 'PREPARADOR_FISICO',
                         'ENTRENADOR_ARQUEROS', 'MEDICO', 'OTRO')
        SET @errores += @nl + N'- El rol debe ser DIRECTOR_TECNICO, AYUDANTE_CAMPO, PREPARADOR_FISICO, '
                      + N'ENTRENADOR_ARQUEROS, MEDICO u OTRO.';
    ELSE IF @rol = 'DIRECTOR_TECNICO'
            AND EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO
                        WHERE id_seleccion = @id_seleccion AND rol = 'DIRECTOR_TECNICO')
        SET @errores += @nl + N'- La selección ya tiene director técnico.';

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF @id_pais_nacimiento IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais_nacimiento)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais_nacimiento AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_PERSONA_CUERPO_TECNICO_Alta: no se pudo dar de alta la persona del cuerpo técnico.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.PERSONA_CUERPO_TECNICO
        (id_seleccion, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, rol)
    VALUES
        (@id_seleccion, @id_pais_nacimiento, @nombre, @apellido, @fecha_nacimiento, @rol);

    SET @id_persona_ct = SCOPE_IDENTITY();
END;
GO


/*
  usp_PERSONA_CUERPO_TECNICO_Modificacion
  Valida: que la persona exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta. La selección no se modifica.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion
    @id_persona_ct       INT,
    @nombre              NVARCHAR(120) = NULL,
    @apellido            NVARCHAR(120) = NULL,
    @rol                 VARCHAR(40)   = NULL,
    @fecha_nacimiento    DATE          = NULL,
    @id_pais_nacimiento  SMALLINT      = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_seleccion   INT;
    DECLARE @nombre_final   NVARCHAR(60);
    DECLARE @apellido_final NVARCHAR(60);

    SET @nombre   = NULLIF(TRIM(@nombre), N'');
    SET @apellido = NULLIF(TRIM(@apellido), N'');
    SET @rol      = UPPER(NULLIF(TRIM(@rol), ''));

    SELECT @id_seleccion   = id_seleccion,
           @nombre_final   = ISNULL(@nombre, nombre),
           @apellido_final = ISNULL(@apellido, apellido)
    FROM Torneo.PERSONA_CUERPO_TECNICO
    WHERE id_persona_ct = @id_persona_ct;

    IF @id_persona_ct IS NULL
        SET @errores += @nl + N'- El id de la persona es obligatorio.';
    ELSE IF @id_seleccion IS NULL
        SET @errores += @nl + N'- No existe una persona del cuerpo técnico con id '
                      + CAST(@id_persona_ct AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL AND @apellido IS NULL AND @rol IS NULL AND @fecha_nacimiento IS NULL
       AND @id_pais_nacimiento IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';
    IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';
    IF (@nombre IS NOT NULL OR @apellido IS NOT NULL)
       AND EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO
                   WHERE id_seleccion = @id_seleccion AND apellido = @apellido_final
                     AND nombre = @nombre_final AND id_persona_ct <> @id_persona_ct)
        SET @errores += @nl + N'- Ya hay otro ' + @nombre_final + N' ' + @apellido_final + N' en el cuerpo técnico.';

    IF @rol NOT IN ('DIRECTOR_TECNICO', 'AYUDANTE_CAMPO', 'PREPARADOR_FISICO',
                    'ENTRENADOR_ARQUEROS', 'MEDICO', 'OTRO')
        SET @errores += @nl + N'- El rol debe ser DIRECTOR_TECNICO, AYUDANTE_CAMPO, PREPARADOR_FISICO, '
                      + N'ENTRENADOR_ARQUEROS, MEDICO u OTRO.';
    ELSE IF @rol = 'DIRECTOR_TECNICO'
            AND EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO
                        WHERE id_seleccion = @id_seleccion AND rol = 'DIRECTOR_TECNICO'
                          AND id_persona_ct <> @id_persona_ct)
        SET @errores += @nl + N'- La selección ya tiene director técnico.';

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF @id_pais_nacimiento IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais_nacimiento)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais_nacimiento AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion: no se pudo modificar la persona del cuerpo técnico.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.PERSONA_CUERPO_TECNICO
    SET nombre             = ISNULL(@nombre, nombre),
        apellido           = ISNULL(@apellido, apellido),
        rol                = ISNULL(@rol, rol),
        fecha_nacimiento   = ISNULL(@fecha_nacimiento, fecha_nacimiento),
        id_pais_nacimiento = ISNULL(@id_pais_nacimiento, id_pais_nacimiento)
    WHERE id_persona_ct = @id_persona_ct;
END;
GO


/*
  usp_PERSONA_CUERPO_TECNICO_Baja
  Valida: que la persona exista y que no tenga tarjetas registradas.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_PERSONA_CUERPO_TECNICO_Baja
    @id_persona_ct INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores  NVARCHAR(2048) = N'';
    DECLARE @nl       NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tarjetas INT;

    IF @id_persona_ct IS NULL
        SET @errores += @nl + N'- El id de la persona es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id_persona_ct)
        SET @errores += @nl + N'- No existe una persona del cuerpo técnico con id '
                      + CAST(@id_persona_ct AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @tarjetas = COUNT(*) FROM DesarrolloPartido.AMONESTACION WHERE id_persona_ct = @id_persona_ct;
        IF @tarjetas > 0
            SET @errores += @nl + N'- La referencian ' + CAST(@tarjetas AS NVARCHAR(10))
                          + N' registro(s) de DesarrolloPartido.AMONESTACION.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_PERSONA_CUERPO_TECNICO_Baja: no se pudo dar de baja la persona del cuerpo técnico.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id_persona_ct;
END;
GO


/* ============================================================================
   PARTIDO
   ============================================================================ */

/*
  usp_PARTIDO_Alta
  Valida: número de partido mayor que cero y no repetido; sede existente;
  fase válida; que se informe la fecha y hora UTC o la local (si vienen las
  dos, tienen que coincidir en el huso de la sede); selecciones existentes y
  distintas; en la fase de grupos, las dos selecciones y del mismo grupo; que
  ninguna selección tenga otro partido a menos de 24 horas; que la sede no
  tenga otro partido ese día. El partido queda PROGRAMADO.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_PARTIDO_Alta
    @numero_partido         TINYINT,
    @id_sede                INT,
    @fase                   VARCHAR(30),
    @fecha_hora_utc         DATETIME2(0) = NULL,
    @fecha_hora_local       DATETIME2(0) = NULL,
    @id_seleccion_local     INT          = NULL,
    @id_seleccion_visitante INT          = NULL,
    @id_partido             INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @huso           VARCHAR(50);
    DECLARE @local_segun_utc DATETIME2(0);

    SET @fase = UPPER(NULLIF(TRIM(@fase), ''));

    IF @numero_partido IS NULL
        SET @errores += @nl + N'- El número de partido es obligatorio.';
    ELSE IF @numero_partido = 0
        SET @errores += @nl + N'- El número de partido debe ser mayor que cero.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE numero_partido = @numero_partido)
        SET @errores += @nl + N'- Ya existe el partido número ' + CAST(@numero_partido AS NVARCHAR(3)) + N'.';

    IF @id_sede IS NULL
        SET @errores += @nl + N'- La sede es obligatoria.';
    ELSE
    BEGIN
        SELECT @huso = huso_horario FROM Torneo.SEDE WHERE id_sede = @id_sede;
        IF @huso IS NULL
            SET @errores += @nl + N'- No existe una sede con id ' + CAST(@id_sede AS NVARCHAR(10)) + N'.';
    END;

    IF @fase IS NULL
        SET @errores += @nl + N'- La fase es obligatoria.';
    ELSE IF @fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')
        SET @errores += @nl + N'- La fase debe ser GRUPOS, DIECISEISAVOS, OCTAVOS, CUARTOS, SEMIFINAL, '
                      + N'TERCER_PUESTO o FINAL.';

    -- Se informa una de las dos horas y la otra se calcula con el huso de la sede.
    IF @fecha_hora_utc IS NULL AND @fecha_hora_local IS NULL
        SET @errores += @nl + N'- Hay que informar la fecha y hora UTC o la local de la sede.';
    ELSE IF @huso IS NOT NULL
    BEGIN
        IF @fecha_hora_utc IS NULL
            SET @fecha_hora_utc = CONVERT(DATETIME2(0), (@fecha_hora_local AT TIME ZONE @huso) AT TIME ZONE 'UTC');

        SET @local_segun_utc = CONVERT(DATETIME2(0), (@fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE @huso);

        IF @fecha_hora_local IS NOT NULL AND @fecha_hora_local <> @local_segun_utc
            SET @errores += @nl + N'- La hora local no coincide con la UTC en el huso de la sede (según la UTC es '
                          + CONVERT(NVARCHAR(16), @local_segun_utc, 120) + N').';

        SET @fecha_hora_local = @local_segun_utc;
    END;

    IF @id_seleccion_local IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion_local)
        SET @errores += @nl + N'- No existe la selección local (id ' + CAST(@id_seleccion_local AS NVARCHAR(10)) + N').';

    IF @id_seleccion_visitante IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion_visitante)
        SET @errores += @nl + N'- No existe la selección visitante (id ' + CAST(@id_seleccion_visitante AS NVARCHAR(10)) + N').';

    IF @id_seleccion_local = @id_seleccion_visitante
        SET @errores += @nl + N'- La selección local y la visitante tienen que ser distintas.';

    IF @fase = 'GRUPOS'
    BEGIN
        IF @id_seleccion_local IS NULL OR @id_seleccion_visitante IS NULL
            SET @errores += @nl + N'- En la fase de grupos hay que informar las dos selecciones.';
        ELSE IF NOT EXISTS (SELECT 1
                            FROM Torneo.SELECCION AS sl
                            INNER JOIN Torneo.SELECCION AS sv ON sv.grupo = sl.grupo
                            WHERE sl.id_seleccion = @id_seleccion_local
                              AND sv.id_seleccion = @id_seleccion_visitante)
            SET @errores += @nl + N'- En la fase de grupos las dos selecciones tienen que ser del mismo grupo.';
    END;

    IF @fecha_hora_utc IS NOT NULL
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- ' + pa.nombre + N' ya juega el partido '
                              + CAST(p.numero_partido AS NVARCHAR(3)) + N' a menos de 24 horas.', N'')
            FROM Torneo.PARTIDO AS p
            INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
            INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
            WHERE s.id_seleccion IN (@id_seleccion_local, @id_seleccion_visitante)
              AND ABS(DATEDIFF(MINUTE, p.fecha_hora_utc, @fecha_hora_utc)) < 1440), N'');

    IF @huso IS NOT NULL AND @fecha_hora_local IS NOT NULL
        SET @errores += ISNULL((
            SELECT TOP (1) @nl + N'- La sede ya tiene el partido ' + CAST(p.numero_partido AS NVARCHAR(3)) + N' ese día.'
            FROM Torneo.PARTIDO AS p
            WHERE p.id_sede = @id_sede
              AND CAST(p.fecha_hora_local AS DATE) = CAST(@fecha_hora_local AS DATE)), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_PARTIDO_Alta: no se pudo dar de alta el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.PARTIDO
        (numero_partido, id_sede, id_seleccion_local, id_seleccion_visitante, fase,
         fecha_hora_local, fecha_hora_utc)
    VALUES
        (@numero_partido, @id_sede, @id_seleccion_local, @id_seleccion_visitante, @fase,
         @fecha_hora_local, @fecha_hora_utc);

    SET @id_partido = SCOPE_IDENTITY();
END;
GO


/*
  usp_PARTIDO_Modificacion
  Valida, sobre los valores que va a tener el partido después del cambio:
    - Programación (número, sede, fase, fecha y selecciones): solo antes de
      que empiece; las mismas reglas del alta; que no se cambie la sede de un
      partido con publicidad asignada (los espacios son de la sede) ni una
      selección que ya cargó su formación. Si cambia la sede y no la fecha,
      se mantiene la hora UTC y se recalcula la local.
    - Estado: que sea válido y que el paso esté permitido (ver encabezado);
      que estén las dos selecciones para empezar o terminar; que no vuelva a
      PROGRAMADO un partido con eventos.
    - Resultado: solo al quedar FINALIZADO; goles de las dos selecciones;
      penales solo en eliminación directa con empate, y sin empate en los
      penales; un empate de eliminación directa necesita penales; si hay
      goles cargados en GOL, el resultado tiene que coincidir con ellos.
    - Asistencia: no negativa, no mayor que la capacidad de la sede y solo
      con el partido empezado o terminado.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_PARTIDO_Modificacion
    @id_partido             INT,
    @numero_partido         TINYINT      = NULL,
    @id_sede                INT          = NULL,
    @fase                   VARCHAR(30)  = NULL,
    @fecha_hora_utc         DATETIME2(0) = NULL,
    @fecha_hora_local       DATETIME2(0) = NULL,
    @id_seleccion_local     INT          = NULL,
    @id_seleccion_visitante INT          = NULL,
    @goles_local            TINYINT      = NULL,
    @goles_visitante        TINYINT      = NULL,
    @penales_local          TINYINT      = NULL,
    @penales_visitante      TINYINT      = NULL,
    @asistencia             INT          = NULL,
    @estado                 VARCHAR(30)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    -- Valores actuales
    DECLARE @estado_actual     VARCHAR(12),
            @sede_actual       INT,
            @fase_actual       VARCHAR(15),
            @utc_actual        DATETIME2(0),
            @local_actual      INT,
            @visitante_actual  INT,
            @gl_actual         TINYINT,
            @gv_actual         TINYINT,
            @pl_actual         TINYINT,
            @pv_actual         TINYINT,
            @asistencia_actual INT;
    -- Valores después del cambio
    DECLARE @estado_final      VARCHAR(12),
            @sede_final        INT,
            @fase_final        VARCHAR(15),
            @utc_final         DATETIME2(0),
            @hora_local_final  DATETIME2(0),
            @local_final       INT,
            @visitante_final   INT,
            @gl_final          TINYINT,
            @gv_final          TINYINT,
            @pl_final          TINYINT,
            @pv_final          TINYINT,
            @asistencia_final  INT,
            @huso_final        VARCHAR(50),
            @capacidad_final   INT;
    DECLARE @cambia_programacion BIT = 0,
            @cambia_resultado    BIT = 0;
    -- Marcador según los goles cargados
    DECLARE @goles_registrados   INT,
            @gl_segun_goles      INT,
            @gv_segun_goles      INT,
            @penales_registrados INT,
            @pl_segun_goles      INT,
            @pv_segun_goles      INT;

    SET @fase   = UPPER(NULLIF(TRIM(@fase), ''));
    SET @estado = UPPER(NULLIF(TRIM(@estado), ''));

    SELECT @estado_actual     = estado,
           @sede_actual       = id_sede,
           @fase_actual       = fase,
           @utc_actual        = fecha_hora_utc,
           @local_actual      = id_seleccion_local,
           @visitante_actual  = id_seleccion_visitante,
           @gl_actual         = goles_local,
           @gv_actual         = goles_visitante,
           @pl_actual         = penales_local,
           @pv_actual         = penales_visitante,
           @asistencia_actual = asistencia
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El id del partido es obligatorio.';
    ELSE IF @estado_actual IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';

    IF @numero_partido IS NULL AND @id_sede IS NULL AND @fase IS NULL AND @fecha_hora_utc IS NULL
       AND @fecha_hora_local IS NULL AND @id_seleccion_local IS NULL AND @id_seleccion_visitante IS NULL
       AND @goles_local IS NULL AND @goles_visitante IS NULL AND @penales_local IS NULL
       AND @penales_visitante IS NULL AND @asistencia IS NULL AND @estado IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @estado_actual IS NOT NULL
    BEGIN
        SET @cambia_programacion = IIF(@numero_partido IS NOT NULL OR @id_sede IS NOT NULL OR @fase IS NOT NULL
                                       OR @fecha_hora_utc IS NOT NULL OR @fecha_hora_local IS NOT NULL
                                       OR @id_seleccion_local IS NOT NULL OR @id_seleccion_visitante IS NOT NULL, 1, 0);
        SET @cambia_resultado    = IIF(@goles_local IS NOT NULL OR @goles_visitante IS NOT NULL
                                       OR @penales_local IS NOT NULL OR @penales_visitante IS NOT NULL, 1, 0);

        SET @estado_final     = ISNULL(@estado, @estado_actual);
        SET @sede_final       = ISNULL(@id_sede, @sede_actual);
        SET @fase_final       = ISNULL(@fase, @fase_actual);
        SET @local_final      = ISNULL(@id_seleccion_local, @local_actual);
        SET @visitante_final  = ISNULL(@id_seleccion_visitante, @visitante_actual);
        SET @asistencia_final = ISNULL(@asistencia, @asistencia_actual);

        -- Al reabrir un partido finalizado se borra el resultado.
        IF @estado_actual = 'FINALIZADO' AND @estado_final = 'EN_JUEGO'
            SELECT @gl_final = @goles_local, @gv_final = @goles_visitante,
                   @pl_final = @penales_local, @pv_final = @penales_visitante;
        ELSE
            SELECT @gl_final = ISNULL(@goles_local, @gl_actual),
                   @gv_final = ISNULL(@goles_visitante, @gv_actual),
                   @pl_final = ISNULL(@penales_local, @pl_actual),
                   @pv_final = ISNULL(@penales_visitante, @pv_actual);

        SELECT @huso_final = huso_horario, @capacidad_final = capacidad
        FROM Torneo.SEDE
        WHERE id_sede = @sede_final;

        /* Programación */
        IF @cambia_programacion = 1 AND @estado_actual NOT IN ('PROGRAMADO', 'SUSPENDIDO')
            SET @errores += @nl + N'- El partido está ' + @estado_actual
                          + N': el número, la sede, la fase, la fecha y las selecciones se cambian antes de que empiece.';

        IF @numero_partido = 0
            SET @errores += @nl + N'- El número de partido debe ser mayor que cero.';
        ELSE IF EXISTS (SELECT 1 FROM Torneo.PARTIDO
                        WHERE numero_partido = @numero_partido AND id_partido <> @id_partido)
            SET @errores += @nl + N'- Ya existe otro partido número ' + CAST(@numero_partido AS NVARCHAR(3)) + N'.';

        IF @id_sede IS NOT NULL AND @huso_final IS NULL
            SET @errores += @nl + N'- No existe una sede con id ' + CAST(@id_sede AS NVARCHAR(10)) + N'.';
        ELSE IF @id_sede <> @sede_actual
                AND EXISTS (SELECT 1 FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido)
            SET @errores += @nl + N'- El partido tiene publicidad asignada en los espacios de su sede actual: '
                          + N'hay que quitarla antes de cambiar la sede.';

        IF @fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')
            SET @errores += @nl + N'- La fase debe ser GRUPOS, DIECISEISAVOS, OCTAVOS, CUARTOS, SEMIFINAL, '
                          + N'TERCER_PUESTO o FINAL.';

        IF @huso_final IS NOT NULL
        BEGIN
            IF @fecha_hora_utc IS NULL AND @fecha_hora_local IS NOT NULL
                SET @utc_final = CONVERT(DATETIME2(0), (@fecha_hora_local AT TIME ZONE @huso_final) AT TIME ZONE 'UTC');
            ELSE
                SET @utc_final = ISNULL(@fecha_hora_utc, @utc_actual);

            SET @hora_local_final = CONVERT(DATETIME2(0), (@utc_final AT TIME ZONE 'UTC') AT TIME ZONE @huso_final);

            IF @fecha_hora_utc IS NOT NULL AND @fecha_hora_local IS NOT NULL
               AND @fecha_hora_local <> @hora_local_final
                SET @errores += @nl + N'- La hora local no coincide con la UTC en el huso de la sede (según la UTC es '
                              + CONVERT(NVARCHAR(16), @hora_local_final, 120) + N').';
        END;

        IF @id_seleccion_local IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion_local)
            SET @errores += @nl + N'- No existe la selección local (id ' + CAST(@id_seleccion_local AS NVARCHAR(10)) + N').';

        IF @id_seleccion_visitante IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion_visitante)
            SET @errores += @nl + N'- No existe la selección visitante (id ' + CAST(@id_seleccion_visitante AS NVARCHAR(10)) + N').';

        IF @local_final = @visitante_final
            SET @errores += @nl + N'- La selección local y la visitante tienen que ser distintas.';

        IF EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION
                   WHERE id_partido = @id_partido
                     AND id_seleccion <> ISNULL(@local_final, -1)
                     AND id_seleccion <> ISNULL(@visitante_final, -1))
            SET @errores += @nl + N'- La selección que se quiere reemplazar ya cargó su formación para este partido.';

        IF @fase_final = 'GRUPOS'
        BEGIN
            IF @local_final IS NULL OR @visitante_final IS NULL
                SET @errores += @nl + N'- En la fase de grupos hay que informar las dos selecciones.';
            ELSE IF NOT EXISTS (SELECT 1
                                FROM Torneo.SELECCION AS sl
                                INNER JOIN Torneo.SELECCION AS sv ON sv.grupo = sl.grupo
                                WHERE sl.id_seleccion = @local_final
                                  AND sv.id_seleccion = @visitante_final)
                SET @errores += @nl + N'- En la fase de grupos las dos selecciones tienen que ser del mismo grupo.';
        END;

        IF @cambia_programacion = 1 AND @utc_final IS NOT NULL
            SET @errores += ISNULL((
                SELECT STRING_AGG(@nl + N'- ' + pa.nombre + N' ya juega el partido '
                                  + CAST(p.numero_partido AS NVARCHAR(3)) + N' a menos de 24 horas.', N'')
                FROM Torneo.PARTIDO AS p
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
                INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
                WHERE s.id_seleccion IN (@local_final, @visitante_final)
                  AND p.id_partido <> @id_partido
                  AND ABS(DATEDIFF(MINUTE, p.fecha_hora_utc, @utc_final)) < 1440), N'');

        IF @cambia_programacion = 1 AND @hora_local_final IS NOT NULL
            SET @errores += ISNULL((
                SELECT TOP (1) @nl + N'- La sede ya tiene el partido ' + CAST(p.numero_partido AS NVARCHAR(3)) + N' ese día.'
                FROM Torneo.PARTIDO AS p
                WHERE p.id_sede = @sede_final
                  AND p.id_partido <> @id_partido
                  AND CAST(p.fecha_hora_local AS DATE) = CAST(@hora_local_final AS DATE)), N'');

        /* Estado */
        IF @estado NOT IN ('PROGRAMADO', 'EN_JUEGO', 'FINALIZADO', 'SUSPENDIDO')
            SET @errores += @nl + N'- El estado debe ser PROGRAMADO, EN_JUEGO, FINALIZADO o SUSPENDIDO.';
        ELSE IF @estado <> @estado_actual
                AND NOT (   (@estado_actual = 'PROGRAMADO' AND @estado IN ('EN_JUEGO', 'SUSPENDIDO', 'FINALIZADO'))
                         OR (@estado_actual = 'EN_JUEGO'   AND @estado IN ('FINALIZADO', 'SUSPENDIDO', 'PROGRAMADO'))
                         OR (@estado_actual = 'SUSPENDIDO' AND @estado = 'PROGRAMADO')
                         OR (@estado_actual = 'FINALIZADO' AND @estado = 'EN_JUEGO'))
            SET @errores += @nl + N'- Un partido no puede pasar de ' + @estado_actual + N' a ' + @estado + N'.';
        ELSE IF @estado_actual = 'EN_JUEGO' AND @estado = 'PROGRAMADO'
                AND (   EXISTS (SELECT 1 FROM DesarrolloPartido.GOL WHERE id_partido = @id_partido)
                     OR EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido)
                     OR EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido))
            SET @errores += @nl + N'- El partido tiene goles, cambios o tarjetas registrados: no puede volver a PROGRAMADO.';

        IF @estado_final IN ('EN_JUEGO', 'FINALIZADO') AND (@local_final IS NULL OR @visitante_final IS NULL)
            SET @errores += @nl + N'- Para que el partido empiece o termine tienen que estar definidas las dos selecciones.';

        /* Resultado */
        IF @cambia_resultado = 1 AND @estado_final <> 'FINALIZADO'
            SET @errores += @nl + N'- El resultado solo se carga con el partido FINALIZADO.';

        IF @estado_final = 'FINALIZADO'
        BEGIN
            IF @gl_final IS NULL OR @gv_final IS NULL
                SET @errores += @nl + N'- Un partido finalizado tiene que tener los goles de las dos selecciones.';
            ELSE
            BEGIN
                IF (@pl_final IS NULL AND @pv_final IS NOT NULL) OR (@pl_final IS NOT NULL AND @pv_final IS NULL)
                    SET @errores += @nl + N'- Los penales se informan para las dos selecciones.';
                ELSE IF @pl_final IS NOT NULL AND @fase_final = 'GRUPOS'
                    SET @errores += @nl + N'- En la fase de grupos no hay definición por penales.';
                ELSE IF @pl_final IS NOT NULL AND @gl_final <> @gv_final
                    SET @errores += @nl + N'- Solo hay definición por penales si el partido terminó empatado.';
                ELSE IF @pl_final IS NOT NULL AND @pl_final = @pv_final
                    SET @errores += @nl + N'- La definición por penales no puede terminar empatada.';
                ELSE IF @pl_final IS NULL AND @fase_final <> 'GRUPOS' AND @gl_final = @gv_final
                    SET @errores += @nl + N'- Un empate en eliminación directa se define por penales: faltan los penales.';

                SELECT @goles_registrados   = goles_registrados,
                       @gl_segun_goles      = goles_local,
                       @gv_segun_goles      = goles_visitante,
                       @penales_registrados = penales_registrados,
                       @pl_segun_goles      = penales_local,
                       @pv_segun_goles      = penales_visitante
                FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);

                IF @goles_registrados - @penales_registrados > 0
                   AND (@gl_final <> @gl_segun_goles OR @gv_final <> @gv_segun_goles)
                    SET @errores += @nl + N'- El resultado no coincide con los goles registrados ('
                                  + CAST(@gl_segun_goles AS NVARCHAR(3)) + N' - '
                                  + CAST(@gv_segun_goles AS NVARCHAR(3)) + N').';

                IF @penales_registrados > 0
                   AND (ISNULL(@pl_final, 255) <> @pl_segun_goles OR ISNULL(@pv_final, 255) <> @pv_segun_goles)
                    SET @errores += @nl + N'- Los penales no coinciden con los registrados ('
                                  + CAST(@pl_segun_goles AS NVARCHAR(3)) + N' - '
                                  + CAST(@pv_segun_goles AS NVARCHAR(3)) + N').';
            END;
        END;

        /* Asistencia */
        IF @asistencia < 0
            SET @errores += @nl + N'- La asistencia no puede ser negativa.';
        ELSE IF @asistencia_final > @capacidad_final
            SET @errores += @nl + N'- La asistencia (' + CAST(@asistencia_final AS NVARCHAR(10))
                          + N') supera la capacidad de la sede (' + CAST(@capacidad_final AS NVARCHAR(10)) + N').';

        IF @asistencia IS NOT NULL AND @estado_final NOT IN ('EN_JUEGO', 'FINALIZADO')
            SET @errores += @nl + N'- La asistencia se carga con el partido empezado o terminado.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_PARTIDO_Modificacion: no se pudo modificar el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.PARTIDO
    SET numero_partido         = ISNULL(@numero_partido, numero_partido),
        id_sede                = @sede_final,
        fase                   = @fase_final,
        fecha_hora_utc         = @utc_final,
        fecha_hora_local       = @hora_local_final,
        id_seleccion_local     = @local_final,
        id_seleccion_visitante = @visitante_final,
        goles_local            = @gl_final,
        goles_visitante        = @gv_final,
        penales_local          = @pl_final,
        penales_visitante      = @pv_final,
        asistencia             = @asistencia_final,
        estado                 = @estado_final
    WHERE id_partido = @id_partido;
END;
GO


/*
  usp_PARTIDO_Baja
  Valida: que el partido exista y que no tenga formaciones, eventos,
  designaciones arbitrales ni publicidad.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_PARTIDO_Baja
    @id_partido INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El id del partido es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE id_partido = @id_partido)
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- Lo referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'DesarrolloPartido.FORMACION', COUNT(*)
                FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido
                UNION ALL
                SELECT N'DesarrolloPartido.CAMBIO', COUNT(*)
                FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido
                UNION ALL
                SELECT N'DesarrolloPartido.GOL', COUNT(*)
                FROM DesarrolloPartido.GOL WHERE id_partido = @id_partido
                UNION ALL
                SELECT N'DesarrolloPartido.AMONESTACION', COUNT(*)
                FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido
                UNION ALL
                SELECT N'Arbitraje.DESIGNACION_ARBITRAL', COUNT(*)
                FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido
                UNION ALL
                SELECT N'Publicidad.EXHIBICION', COUNT(*)
                FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_PARTIDO_Baja: no se pudo dar de baja el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
END;
GO


-- Evidencia: SP creados en el esquema Torneo.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo'
ORDER BY p.name;
GO
