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
 Archivo: 11_SP_Negocio_Convocatoria.sql
 Objetivo: Crear los SP de lógica de negocio para el registro de selecciones,
           la convocatoria y las altas y bajas de último momento:
             Torneo.usp_RegistrarSeleccion     selección, lista y director técnico
             Torneo.usp_RegistrarConvocatoria  lista inicial completa de jugadores
             Torneo.usp_ReemplazarJugador      baja con motivo y alta del reemplazante
           y el tipo de tabla Torneo.TT_CONVOCADO, con el que se pasa la lista.
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 00 a 08. Su script de testing es
           61_Test_SP_Negocio_Convocatoria.sql.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  TT_CONVOCADO
  Una fila por jugador de la lista. Las columnas admiten NULL para que el SP
  pueda informar qué filas vienen incompletas. Un tipo no se puede modificar
  mientras un SP lo use: se borran el SP y el tipo, y se vuelven a crear.
*/
DROP PROCEDURE IF EXISTS Torneo.usp_RegistrarConvocatoria;
DROP TYPE IF EXISTS Torneo.TT_CONVOCADO;
GO

CREATE TYPE Torneo.TT_CONVOCADO AS TABLE (
    nombre              NVARCHAR(60)  NULL,
    apellido            NVARCHAR(60)  NULL,
    posicion_habitual   VARCHAR(15)   NULL,
    dorsal              TINYINT       NULL,
    fecha_nacimiento    DATE          NULL,
    club_origen         NVARCHAR(100) NULL,
    id_pais_nacimiento  SMALLINT      NULL
);
GO


/*
  usp_RegistrarSeleccion
  Registra una selección con su lista de convocados (todavía vacía) y su
  director técnico, en una sola transacción. Valida: que se informen la
  fecha de presentación de la lista y el nombre y apellido del director
  técnico. El resto lo validan los SP de ABM de cada tabla.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_RegistrarSeleccion
    @id_pais                 SMALLINT,
    @confederacion           VARCHAR(20),
    @grupo                   VARCHAR(5),
    @fecha_presentacion      DATE,
    @dt_nombre               NVARCHAR(120),
    @dt_apellido             NVARCHAR(120),
    @dt_fecha_nacimiento     DATE     = NULL,
    @dt_id_pais_nacimiento   SMALLINT = NULL,
    @id_seleccion            INT      = NULL OUTPUT,
    @mostrar                 BIT      = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    IF @fecha_presentacion IS NULL
        SET @errores += @nl + N'- La fecha de presentación de la lista es obligatoria.';

    IF NULLIF(TRIM(@dt_nombre), N'') IS NULL OR NULLIF(TRIM(@dt_apellido), N'') IS NULL
        SET @errores += @nl + N'- El nombre y el apellido del director técnico son obligatorios.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_RegistrarSeleccion: no se pudo registrar la selección.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_SELECCION_Alta
            @id_pais = @id_pais, @confederacion = @confederacion, @grupo = @grupo,
            @id_seleccion = @id_seleccion OUTPUT;

        EXEC Torneo.usp_LISTA_CONVOCADOS_Alta
            @id_seleccion = @id_seleccion, @fecha_presentacion = @fecha_presentacion;

        EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta
            @id_seleccion = @id_seleccion, @nombre = @dt_nombre, @apellido = @dt_apellido,
            @rol = 'DIRECTOR_TECNICO', @fecha_nacimiento = @dt_fecha_nacimiento,
            @id_pais_nacimiento = @dt_id_pais_nacimiento;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT s.id_seleccion, pa.nombre AS seleccion, s.confederacion, s.grupo,
               l.id_lista, l.fecha_presentacion, ct.apellido + N', ' + ct.nombre AS director_tecnico
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
        INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
        INNER JOIN Torneo.PERSONA_CUERPO_TECNICO AS ct
                ON ct.id_seleccion = s.id_seleccion AND ct.rol = 'DIRECTOR_TECNICO'
        WHERE s.id_seleccion = @id_seleccion;
END;
GO


/*
  usp_RegistrarConvocatoria
  Carga la lista inicial completa de una selección en una sola transacción:
  todos los jugadores entran o no entra ninguno. Cada jugador queda dado de
  alta en la fecha de presentación de la lista, con motivo "Lista inicial".
  Valida, sobre la lista recibida: que la selección exista, tenga su lista y
  que la lista todavía esté vacía (los cambios posteriores son reemplazos);
  entre MIN_CONVOCADOS y MAX_CONVOCADOS jugadores; al menos
  MIN_ARQUEROS_CONVOCADOS arqueros; filas completas (nombre, apellido,
  posición y dorsal); posiciones válidas; sin dorsales ni jugadores
  repetidos. Cada jugador lo valida además Torneo.usp_JUGADOR_Alta.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_RegistrarConvocatoria
    @id_seleccion  INT,
    @jugadores     Torneo.TT_CONVOCADO READONLY,
    @mostrar       BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores            NVARCHAR(2048) = N'';
    DECLARE @nl                 NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia        BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_lista           INT;
    DECLARE @fecha_presentacion DATE;
    DECLARE @min_convocados     TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados     TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros       TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');
    DECLARE @cantidad           INT     = (SELECT COUNT(*) FROM @jugadores);
    DECLARE @arqueros           INT;
    DECLARE @incompletas        INT;
    DECLARE @i                  INT     = 1;

    -- Copia numerada de la lista, para recorrerla fila por fila.
    DECLARE @lista TABLE (
        fila                INT PRIMARY KEY,
        nombre              NVARCHAR(60),
        apellido            NVARCHAR(60),
        posicion_habitual   VARCHAR(15),
        dorsal              TINYINT,
        fecha_nacimiento    DATE,
        club_origen         NVARCHAR(100),
        id_pais_nacimiento  SMALLINT
    );

    INSERT INTO @lista
    SELECT ROW_NUMBER() OVER (ORDER BY dorsal, apellido, nombre),
           TRIM(nombre), TRIM(apellido), UPPER(TRIM(posicion_habitual)), dorsal,
           fecha_nacimiento, TRIM(club_origen), id_pais_nacimiento
    FROM @jugadores;

    SELECT @id_lista = l.id_lista, @fecha_presentacion = l.fecha_presentacion
    FROM Torneo.LISTA_CONVOCADOS AS l
    WHERE l.id_seleccion = @id_seleccion;

    IF @id_seleccion IS NULL
        SET @errores += @nl + N'- La selección es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';
    ELSE IF @id_lista IS NULL
        SET @errores += @nl + N'- La selección no tiene lista de convocados (se crea con usp_RegistrarSeleccion).';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.JUGADOR WHERE id_lista = @id_lista)
        SET @errores += @nl + N'- La lista ya tiene jugadores: los cambios se registran con usp_ReemplazarJugador.';

    IF @cantidad NOT BETWEEN @min_convocados AND @max_convocados
        SET @errores += @nl + N'- La lista tiene ' + CAST(@cantidad AS NVARCHAR(3)) + N' jugadores: tienen que ser entre '
                      + CAST(@min_convocados AS NVARCHAR(3)) + N' y ' + CAST(@max_convocados AS NVARCHAR(3)) + N'.';

    SELECT @arqueros = COUNT(*) FROM @lista WHERE posicion_habitual = 'ARQUERO';
    IF @arqueros < @min_arqueros
        SET @errores += @nl + N'- La lista tiene ' + CAST(@arqueros AS NVARCHAR(3)) + N' arqueros y el mínimo es '
                      + CAST(@min_arqueros AS NVARCHAR(3)) + N'.';

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE NULLIF(nombre, N'') IS NULL OR NULLIF(apellido, N'') IS NULL
       OR posicion_habitual IS NULL OR dorsal IS NULL;
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(3))
                      + N' fila(s) sin nombre, apellido, posición o dorsal.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Posiciones no válidas: ' + STRING_AGG(posicion_habitual, ', ')
               + N' (ARQUERO, DEFENSOR, MEDIOCAMPISTA o DELANTERO).'
        FROM (SELECT DISTINCT posicion_habitual FROM @lista
              WHERE posicion_habitual NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Dorsales repetidos: ' + STRING_AGG(CAST(dorsal AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT dorsal FROM @lista WHERE dorsal IS NOT NULL GROUP BY dorsal HAVING COUNT(*) > 1) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Jugadores repetidos: ' + STRING_AGG(nombre + N' ' + apellido, ', ') + N'.'
        FROM (SELECT nombre, apellido FROM @lista
              WHERE nombre IS NOT NULL AND apellido IS NOT NULL
              GROUP BY nombre, apellido HAVING COUNT(*) > 1) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_RegistrarConvocatoria: no se pudo registrar la convocatoria.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DECLARE @nombre NVARCHAR(60), @apellido NVARCHAR(60), @posicion VARCHAR(15), @dorsal TINYINT,
            @fecha_nacimiento DATE, @club NVARCHAR(100), @id_pais_nacimiento SMALLINT;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        WHILE @i <= @cantidad
        BEGIN
            SELECT @nombre = nombre, @apellido = apellido, @posicion = posicion_habitual, @dorsal = dorsal,
                   @fecha_nacimiento = fecha_nacimiento, @club = club_origen,
                   @id_pais_nacimiento = id_pais_nacimiento
            FROM @lista
            WHERE fila = @i;

            EXEC Torneo.usp_JUGADOR_Alta
                @id_lista = @id_lista, @nombre = @nombre, @apellido = @apellido,
                @posicion_habitual = @posicion, @dorsal = @dorsal,
                @fecha_nacimiento = @fecha_nacimiento, @club_origen = @club,
                @id_pais_nacimiento = @id_pais_nacimiento,
                @fecha_alta = @fecha_presentacion, @motivo_alta = 'Lista inicial';

            SET @i += 1;
        END;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT pa.nombre AS seleccion, j.posicion_habitual, COUNT(*) AS jugadores
        FROM Torneo.JUGADOR AS j
        INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
        WHERE l.id_lista = @id_lista
        GROUP BY pa.nombre, j.posicion_habitual;
END;
GO


/*
  usp_ReemplazarJugador
  Alta o baja de último momento: da de baja al jugador (con motivo y fecha) y
  da de alta al reemplazante en la misma transacción. El reemplazante hereda
  el dorsal si no se informa otro. Valida: jugador existente y activo; motivo
  y fecha del cambio obligatorios; que, si la selección ya jugó su primer
  partido, solo se reemplace a un arquero y por otro arquero (como permite el
  reglamento ante una lesión). La baja y el alta las validan además
  Torneo.usp_JUGADOR_Baja y Torneo.usp_JUGADOR_Alta.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ReemplazarJugador
    @id_jugador_baja     INT,
    @motivo              VARCHAR(400),
    @fecha_cambio        DATE,
    @nombre              NVARCHAR(120),
    @apellido            NVARCHAR(120),
    @posicion_habitual   VARCHAR(30),
    @dorsal              TINYINT       = NULL,
    @fecha_nacimiento    DATE          = NULL,
    @club_origen         NVARCHAR(200) = NULL,
    @id_pais_nacimiento  SMALLINT      = NULL,
    @id_jugador_alta     INT           = NULL OUTPUT,
    @mostrar             BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @nl              NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia     BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_lista        INT;
    DECLARE @id_seleccion    INT;
    DECLARE @activo          BIT;
    DECLARE @posicion_baja   VARCHAR(15);
    DECLARE @dorsal_baja     TINYINT;
    DECLARE @jugador_baja    NVARCHAR(130);
    DECLARE @primer_partido  DATE;
    DECLARE @motivo_alta     VARCHAR(200);

    SET @motivo            = NULLIF(TRIM(@motivo), '');
    SET @posicion_habitual = UPPER(NULLIF(TRIM(@posicion_habitual), ''));

    SELECT @id_lista      = j.id_lista,
           @id_seleccion  = l.id_seleccion,
           @activo        = IIF(j.fecha_baja IS NULL, 1, 0),
           @posicion_baja = j.posicion_habitual,
           @dorsal_baja   = j.dorsal,
           @jugador_baja  = j.apellido + N', ' + j.nombre
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE j.id_jugador = @id_jugador_baja;

    SELECT @primer_partido = MIN(CAST(fecha_hora_local AS DATE))
    FROM Torneo.PARTIDO
    WHERE @id_seleccion IN (id_seleccion_local, id_seleccion_visitante);

    IF @id_jugador_baja IS NULL
        SET @errores += @nl + N'- El jugador que se da de baja es obligatorio.';
    ELSE IF @id_lista IS NULL
        SET @errores += @nl + N'- No existe un jugador con id ' + CAST(@id_jugador_baja AS NVARCHAR(10)) + N'.';
    ELSE IF @activo = 0
        SET @errores += @nl + N'- El jugador ya estaba dado de baja.';

    IF @motivo IS NULL
        SET @errores += @nl + N'- El motivo del cambio es obligatorio.';

    IF @fecha_cambio IS NULL
        SET @errores += @nl + N'- La fecha del cambio es obligatoria.';
    ELSE IF @fecha_cambio >= @primer_partido
    BEGIN
        IF @posicion_baja <> 'ARQUERO'
            SET @errores += @nl + N'- La selección ya jugó su primer partido ('
                          + CONVERT(NVARCHAR(10), @primer_partido, 103)
                          + N'): desde entonces solo se puede reemplazar a un arquero.';
        ELSE IF @posicion_habitual <> 'ARQUERO'
            SET @errores += @nl + N'- Un arquero reemplazado después del primer partido se reemplaza por otro arquero.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ReemplazarJugador: no se pudo registrar el reemplazo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @motivo_alta = LEFT('Reemplazo de ' + CAST(@jugador_baja AS VARCHAR(130)) + ': ' + @motivo, 200);
    SET @dorsal      = ISNULL(@dorsal, @dorsal_baja);

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_JUGADOR_Baja
            @id_jugador = @id_jugador_baja, @motivo_baja = @motivo, @fecha_baja = @fecha_cambio;

        EXEC Torneo.usp_JUGADOR_Alta
            @id_lista = @id_lista, @nombre = @nombre, @apellido = @apellido,
            @posicion_habitual = @posicion_habitual, @dorsal = @dorsal,
            @fecha_nacimiento = @fecha_nacimiento, @club_origen = @club_origen,
            @id_pais_nacimiento = @id_pais_nacimiento,
            @fecha_alta = @fecha_cambio, @motivo_alta = @motivo_alta,
            @id_jugador = @id_jugador_alta OUTPUT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT id_jugador, dorsal, apellido, nombre, posicion_habitual,
               fecha_alta, motivo_alta, fecha_baja, motivo_baja
        FROM Torneo.JUGADOR
        WHERE id_jugador IN (@id_jugador_baja, @id_jugador_alta)
        ORDER BY fecha_alta;
END;
GO


-- Evidencia: SP de negocio y tipo de tabla creados.
SELECT s.name AS esquema, p.name AS objeto, 'PROCEDIMIENTO' AS tipo
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo'
  AND p.name IN (N'usp_RegistrarSeleccion', N'usp_RegistrarConvocatoria', N'usp_ReemplazarJugador')
UNION ALL
SELECT s.name, t.name, 'TIPO DE TABLA'
FROM sys.table_types AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'Torneo'
ORDER BY tipo, objeto;
GO
