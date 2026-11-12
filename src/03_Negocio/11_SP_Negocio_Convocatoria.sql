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
             Torneo.usp_CargarReemplazos       reemplazos ya ocurridos, todos juntos (lo usa el 33)
           y el tipo de tabla Torneo.TT_CONVOCADO, con el que se pasa la lista.
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 01 a 09. Su script de testing es
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
    @mostrar_resultados                 BIT      = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    IF @fecha_presentacion IS NULL
        SET @errores += @salto_linea + N'- La fecha de presentación de la lista es obligatoria.';

    IF NULLIF(TRIM(@dt_nombre), N'') IS NULL OR NULLIF(TRIM(@dt_apellido), N'') IS NULL
        SET @errores += @salto_linea + N'- El nombre y el apellido del director técnico son obligatorios.';

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

    IF @mostrar_resultados = 1
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
  repetidos; dorsales entre 1 y 99; sin fechas de nacimiento futuras;
  países de nacimiento existentes. Con eso cubre las reglas de
  Torneo.usp_JUGADOR_Alta y carga a todos con un solo INSERT (las reglas del
  alta de jugador quedan en los dos SP).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_RegistrarConvocatoria
    @id_seleccion  INT,
    @jugadores     Torneo.TT_CONVOCADO READONLY,
    @mostrar_resultados       BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores            NVARCHAR(2048) = N'';
    DECLARE @salto_linea        NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia        BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_lista           INT;
    DECLARE @fecha_presentacion DATE;
    DECLARE @min_convocados     TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados     TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros       TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');
    DECLARE @cantidad           INT     = (SELECT COUNT(*) FROM @jugadores);
    DECLARE @arqueros           INT;
    DECLARE @incompletas        INT;

    -- Copia normalizada de la lista, la que se valida y se inserta.
    DECLARE @lista TABLE (
        nombre              NVARCHAR(60),
        apellido            NVARCHAR(60),
        posicion_habitual   VARCHAR(15),
        dorsal              TINYINT,
        fecha_nacimiento    DATE,
        club_origen         NVARCHAR(100),
        id_pais_nacimiento  SMALLINT
    );

    INSERT INTO @lista
    SELECT TRIM(nombre), TRIM(apellido), UPPER(TRIM(posicion_habitual)), dorsal,
           fecha_nacimiento, NULLIF(TRIM(club_origen), N''), id_pais_nacimiento
    FROM @jugadores;

    SELECT @id_lista = l.id_lista, @fecha_presentacion = l.fecha_presentacion
    FROM Torneo.LISTA_CONVOCADOS AS l
    WHERE l.id_seleccion = @id_seleccion;

    IF @id_seleccion IS NULL
        SET @errores += @salto_linea + N'- La selección es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @salto_linea + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';
    ELSE IF @id_lista IS NULL
        SET @errores += @salto_linea + N'- La selección no tiene lista de convocados (se crea con usp_RegistrarSeleccion).';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.JUGADOR WHERE id_lista = @id_lista)
        SET @errores += @salto_linea + N'- La lista ya tiene jugadores: los cambios se registran con usp_ReemplazarJugador.';

    IF @cantidad NOT BETWEEN @min_convocados AND @max_convocados
        SET @errores += @salto_linea + N'- La lista tiene ' + CAST(@cantidad AS NVARCHAR(3)) + N' jugadores: tienen que ser entre '
                      + CAST(@min_convocados AS NVARCHAR(3)) + N' y ' + CAST(@max_convocados AS NVARCHAR(3)) + N'.';

    SELECT @arqueros = COUNT(*) FROM @lista WHERE posicion_habitual = 'ARQUERO';
    IF @arqueros < @min_arqueros
        SET @errores += @salto_linea + N'- La lista tiene ' + CAST(@arqueros AS NVARCHAR(3)) + N' arqueros y el mínimo es '
                      + CAST(@min_arqueros AS NVARCHAR(3)) + N'.';

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE NULLIF(nombre, N'') IS NULL OR NULLIF(apellido, N'') IS NULL
       OR posicion_habitual IS NULL OR dorsal IS NULL;
    IF @incompletas > 0
        SET @errores += @salto_linea + N'- Hay ' + CAST(@incompletas AS NVARCHAR(3))
                      + N' fila(s) sin nombre, apellido, posición o dorsal.';

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Posiciones no válidas: ' + STRING_AGG(posicion_habitual, ', ')
               + N' (ARQUERO, DEFENSOR, MEDIOCAMPISTA o DELANTERO).'
        FROM (SELECT DISTINCT posicion_habitual FROM @lista
              WHERE posicion_habitual NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')) AS x), N'');

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Dorsales repetidos: ' + STRING_AGG(CAST(dorsal AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT dorsal FROM @lista WHERE dorsal IS NOT NULL GROUP BY dorsal HAVING COUNT(*) > 1) AS x), N'');

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Jugadores repetidos: ' + STRING_AGG(nombre + N' ' + apellido, ', ') + N'.'
        FROM (SELECT nombre, apellido FROM @lista
              WHERE nombre IS NOT NULL AND apellido IS NOT NULL
              GROUP BY nombre, apellido HAVING COUNT(*) > 1) AS x), N'');

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Dorsales fuera de rango (1 a 99): ' + STRING_AGG(CAST(dorsal AS NVARCHAR(3)), ', ') + N'.'
        FROM @lista WHERE dorsal NOT BETWEEN 1 AND 99), N'');

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Fecha de nacimiento futura (dorsal): ' + STRING_AGG(ISNULL(CAST(dorsal AS NVARCHAR(3)), N'sin dorsal'), ', ') + N'.'
        FROM @lista WHERE fecha_nacimiento > CONVERT(DATE, GETDATE())), N'');

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- No existen los países de nacimiento con id: '
               + STRING_AGG(CAST(id_pais_nacimiento AS NVARCHAR(10)), ', ') + N'.'
        FROM (SELECT DISTINCT l.id_pais_nacimiento FROM @lista AS l
              WHERE l.id_pais_nacimiento IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p
                                WHERE p.id_pais = l.id_pais_nacimiento)) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_RegistrarConvocatoria: no se pudo registrar la convocatoria.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        INSERT INTO Torneo.JUGADOR
            (id_lista, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, club_origen,
             posicion_habitual, dorsal, fecha_alta, motivo_alta)
        SELECT @id_lista, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, club_origen,
               posicion_habitual, dorsal, @fecha_presentacion, 'Lista inicial'
        FROM @lista
        ORDER BY dorsal, apellido, nombre;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar_resultados = 1
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
    @mostrar_resultados             BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @salto_linea    NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia    BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_lista       INT;
    DECLARE @id_seleccion   INT;
    DECLARE @activo         BIT;
    DECLARE @posicion_baja  VARCHAR(15);
    DECLARE @dorsal_baja    TINYINT;
    DECLARE @jugador_baja   NVARCHAR(130);
    DECLARE @primer_partido DATE;
    DECLARE @motivo_alta    VARCHAR(200);

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
        SET @errores += @salto_linea + N'- El jugador que se da de baja es obligatorio.';
    ELSE IF @id_lista IS NULL
        SET @errores += @salto_linea + N'- No existe un jugador con id ' + CAST(@id_jugador_baja AS NVARCHAR(10)) + N'.';
    ELSE IF @activo = 0
        SET @errores += @salto_linea + N'- El jugador ya estaba dado de baja.';

    IF @motivo IS NULL
        SET @errores += @salto_linea + N'- El motivo del cambio es obligatorio.';

    IF @fecha_cambio IS NULL
        SET @errores += @salto_linea + N'- La fecha del cambio es obligatoria.';
    ELSE IF @fecha_cambio >= @primer_partido
    BEGIN
        IF @posicion_baja <> 'ARQUERO'
            SET @errores += @salto_linea + N'- La selección ya jugó su primer partido ('
                          + CONVERT(NVARCHAR(10), @primer_partido, 103)
                          + N'): desde entonces solo se puede reemplazar a un arquero.';
        ELSE IF @posicion_habitual <> 'ARQUERO'
            SET @errores += @salto_linea + N'- Un arquero reemplazado después del primer partido se reemplaza por otro arquero.';
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

    IF @mostrar_resultados = 1
        SELECT id_jugador, dorsal, apellido, nombre, posicion_habitual,
               fecha_alta, motivo_alta, fecha_baja, motivo_baja
        FROM Torneo.JUGADOR
        WHERE id_jugador IN (@id_jugador_baja, @id_jugador_alta)
        ORDER BY fecha_alta;
END;
GO


/*
  usp_CargarReemplazos
  Altas y bajas de último momento en las listas de convocados (un jugador
  que se lesiona y otro que lo reemplaza), desde #staging_reemplazos. Es una
  carga histórica: el reemplazante ya está en la lista (vino en la lista
  final) y el que sale no (por eso no se usa usp_ReemplazarJugador, que da
  de alta al reemplazante). Columnas que usa: id_registro (distinto en cada
  fila), codigo_fifa (de la selección), nombre_sale, apellido_sale,
  fecha_baja, motivo_baja, nombre_entra, apellido_entra, fecha_alta,
  motivo_alta, errores y accion.
  El que sale se registra dado de baja, con el dorsal y la posición del
  reemplazante (que hereda su dorsal, como en usp_ReemplazarJugador) y alta
  en la fecha de presentación de la lista; al reemplazante se le pone la
  fecha y el motivo de su alta.
  Valida cada reemplazo pendiente: selección con lista de convocados;
  nombres y apellidos obligatorios y de hasta 60 caracteres; fechas y
  motivos obligatorios, motivos de hasta 200 caracteres; la baja no antes de
  la presentación de la lista y el alta no antes de la baja; el reemplazante
  activo en la lista; que el que sale no esté activo (esa baja se hace con
  usp_ReemplazarJugador); que no sean la misma persona; que, si el alta es
  después del primer partido de la selección, el reemplazante sea arquero
  (como permite el reglamento ante una lesión); que no venga dos veces el
  mismo jugador. Con eso cubre las reglas de usp_JUGADOR_Alta, _Baja y
  usp_ReemplazarJugador.
  Un reemplazo queda INSERTADO si el que sale no estaba; ACTUALIZADO si
  estaba dado de baja pero cambió alguna fecha o motivo; si no, SIN CAMBIOS.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_CargarReemplazos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- La lista, el reemplazante y el que sale ya registrados de cada fila pendiente.
    DECLARE @registrados TABLE (
        id_registro         INT PRIMARY KEY,
        id_lista            INT,
        fecha_presentacion  DATE,
        primer_partido      DATE,
        id_entra            INT,
        entra_activo        BIT,
        entra_posicion      VARCHAR(15),
        entra_dorsal        TINYINT,
        entra_fecha_alta    DATE,
        entra_motivo_alta   VARCHAR(200),
        id_sale             INT,
        sale_activo         BIT,
        sale_fecha_baja     DATE,
        sale_motivo_baja    VARCHAR(200)
    );

    IF OBJECT_ID(N'tempdb..#staging_reemplazos') IS NULL
        THROW 50001, N'Torneo.usp_CargarReemplazos: no se importó nada, falta la tabla #staging_reemplazos con los reemplazos.', 1;

    UPDATE #staging_reemplazos
    SET codigo_fifa    = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre_sale    = NULLIF(TRIM(nombre_sale), N''),
        apellido_sale  = NULLIF(TRIM(apellido_sale), N''),
        motivo_baja    = NULLIF(TRIM(motivo_baja), ''),
        nombre_entra   = NULLIF(TRIM(nombre_entra), N''),
        apellido_entra = NULLIF(TRIM(apellido_entra), N''),
        motivo_alta    = NULLIF(TRIM(motivo_alta), '')
    WHERE accion IS NULL;

    INSERT INTO @registrados (id_registro, id_lista, fecha_presentacion, primer_partido, id_entra, entra_activo,
                              entra_posicion, entra_dorsal, entra_fecha_alta, entra_motivo_alta,
                              id_sale, sale_activo, sale_fecha_baja, sale_motivo_baja)
    SELECT st.id_registro, l.id_lista, l.fecha_presentacion,
           (SELECT MIN(CAST(p.fecha_hora_local AS DATE)) FROM Torneo.PARTIDO AS p
            WHERE l.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)),
           e.id_jugador, IIF(e.id_jugador IS NULL, NULL, IIF(e.fecha_baja IS NULL, 1, 0)), e.posicion_habitual, e.dorsal, e.fecha_alta, e.motivo_alta,
           s.id_jugador, IIF(s.id_jugador IS NULL, NULL, IIF(s.fecha_baja IS NULL, 1, 0)), s.fecha_baja, s.motivo_baja
    FROM #staging_reemplazos AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS se ON se.id_pais = pa.id_pais
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = se.id_seleccion
    LEFT JOIN Torneo.JUGADOR AS e
           ON e.id_lista = l.id_lista AND e.nombre = st.nombre_entra AND e.apellido = st.apellido_entra
    LEFT JOIN Torneo.JUGADOR AS s
           ON s.id_lista = l.id_lista AND s.nombre = st.nombre_sale AND s.apellido = st.apellido_sale
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada reemplazo. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @salto_linea + N'- La selección es obligatoria.'
                 WHEN r.id_lista IS NULL     THEN @salto_linea + N'- No hay una selección con lista de convocados con código '
                                                     + st.codigo_fifa + N'.'
            END,
            IIF(st.nombre_sale IS NULL OR st.apellido_sale IS NULL,
                @salto_linea + N'- El nombre y el apellido del jugador que sale son obligatorios.', NULL),
            IIF(st.nombre_entra IS NULL OR st.apellido_entra IS NULL,
                @salto_linea + N'- El nombre y el apellido del reemplazante son obligatorios.', NULL),
            IIF(LEN(st.nombre_sale) > 60 OR LEN(st.apellido_sale) > 60,
                @salto_linea + N'- El nombre y el apellido del jugador que sale no pueden superar los 60 caracteres.', NULL),
            IIF(st.fecha_baja IS NULL OR st.fecha_alta IS NULL, @salto_linea + N'- Las fechas de la baja y del alta son obligatorias.', NULL),
            IIF(st.motivo_baja IS NULL OR st.motivo_alta IS NULL, @salto_linea + N'- Los motivos de la baja y del alta son obligatorios.', NULL),
            IIF(LEN(st.motivo_baja) > 200 OR LEN(st.motivo_alta) > 200,
                @salto_linea + N'- Los motivos no pueden superar los 200 caracteres.', NULL),
            IIF(st.fecha_baja < r.fecha_presentacion,
                @salto_linea + N'- La baja no puede ser anterior a la presentación de la lista ('
                    + CONVERT(NVARCHAR(10), r.fecha_presentacion, 23) + N').', NULL),
            IIF(st.fecha_alta < st.fecha_baja, @salto_linea + N'- El alta del reemplazante no puede ser anterior a la baja.', NULL),
            CASE WHEN r.id_lista IS NOT NULL AND st.nombre_entra IS NOT NULL AND r.id_entra IS NULL
                     THEN @salto_linea + N'- ' + st.nombre_entra + N' ' + ISNULL(st.apellido_entra, N'') + N' no está en la lista.'
                 WHEN r.entra_activo = 0
                     THEN @salto_linea + N'- ' + st.nombre_entra + N' ' + st.apellido_entra + N' está dado de baja en la lista.'
            END,
            IIF(r.sale_activo = 1,
                @salto_linea + N'- ' + st.nombre_sale + N' ' + st.apellido_sale
                    + N' está activo en la lista: esa baja se hace con usp_ReemplazarJugador.', NULL),
            IIF(r.id_sale = r.id_entra, @salto_linea + N'- El jugador que sale y el reemplazante son la misma persona.', NULL),
            IIF(st.fecha_alta > r.primer_partido AND r.entra_posicion <> 'ARQUERO',
                @salto_linea + N'- La selección ya jugó su primer partido: solo se puede reemplazar a un arquero por otro arquero.',
                NULL)), N'')
    FROM #staging_reemplazos AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    -- Que no venga dos veces el mismo jugador (como el que sale o como el reemplazante).
    WITH validos AS (
        SELECT st.id_registro, r.id_lista, st.nombre_sale, st.apellido_sale, st.nombre_entra, st.apellido_entra
        FROM #staging_reemplazos AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL
    )
    UPDATE st
    SET errores = @salto_linea + N'- El jugador que sale o el reemplazante viene en más de un reemplazo.'
    FROM #staging_reemplazos AS st
    INNER JOIN validos AS v ON v.id_registro = st.id_registro
    WHERE EXISTS (SELECT 1 FROM validos AS o
                  WHERE o.id_registro <> v.id_registro AND o.id_lista = v.id_lista
                    AND ((o.nombre_sale = v.nombre_sale AND o.apellido_sale = v.apellido_sale)
                      OR (o.nombre_entra = v.nombre_entra AND o.apellido_entra = v.apellido_entra)));

    UPDATE #staging_reemplazos SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada reemplazo válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_sale IS NULL THEN 'INSERTADO'
                      WHEN r.sale_fecha_baja = st.fecha_baja AND r.sale_motivo_baja = st.motivo_baja
                           AND r.entra_fecha_alta = st.fecha_alta AND ISNULL(r.entra_motivo_alta, '') = st.motivo_alta
                          THEN 'SIN CAMBIOS'
                      ELSE 'ACTUALIZADO'
                 END
    FROM #staging_reemplazos AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    WHERE st.accion IS NULL;

    /* 3. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_alta, motivo_alta,
                                    fecha_baja, motivo_baja)
        SELECT r.id_lista, st.nombre_sale, st.apellido_sale, r.entra_posicion, r.entra_dorsal, r.fecha_presentacion,
               'Importación', st.fecha_baja, st.motivo_baja
        FROM #staging_reemplazos AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO';

        UPDATE j
        SET fecha_baja = st.fecha_baja, motivo_baja = st.motivo_baja
        FROM Torneo.JUGADOR AS j
        INNER JOIN @registrados AS r ON r.id_sale = j.id_jugador
        INNER JOIN #staging_reemplazos AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        UPDATE j
        SET fecha_alta = st.fecha_alta, motivo_alta = st.motivo_alta
        FROM Torneo.JUGADOR AS j
        INNER JOIN @registrados AS r ON r.id_entra = j.id_jugador
        INNER JOIN #staging_reemplazos AS st ON st.id_registro = r.id_registro
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO');

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- Evidencia: SP de negocio y tipo de tabla creados.
SELECT s.name AS esquema, p.name AS objeto, 'PROCEDIMIENTO' AS tipo
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo'
  AND p.name IN (N'usp_RegistrarSeleccion', N'usp_RegistrarConvocatoria', N'usp_ReemplazarJugador',
                 N'usp_CargarReemplazos')
UNION ALL
SELECT s.name, t.name, 'TIPO DE TABLA'
FROM sys.table_types AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'Torneo'
ORDER BY tipo, objeto;
GO
