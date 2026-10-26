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
 Archivo: 06_SP_ABM_DesarrolloPartido.sql
 Objetivo: Crear los stored procedures de alta, baja y modificación de las
           tablas del esquema DesarrolloPartido: TIPO_GOL, FORMACION,
           ALINEACION, CAMBIO, GOL y AMONESTACION. Siguen las convenciones
           descriptas en 04_SP_ABM_DatosGenerales.sql. Requiere haber
           ejecutado 00 a 05. Su script de testing es
           56_Test_SP_ABM_DesarrolloPartido.sql.
================================================================================

 Qué valida cada capa:
   - Estos SP validan la integridad de cada fila: que el jugador figure en la
     formación del partido y sea de la selección que corresponde, que el
     minuto sea coherente con el período y con la fase (no hay alargue ni
     penales en la fase de grupos), que el partido esté en el estado que
     corresponde y que no haya tarjetas después de una expulsión.
   - Las reglas del reglamento que dependen del desarrollo del partido (que
     el jugador esté en cancha en ese minuto, el máximo de cambios y
     ventanas, la doble amarilla automática y el cálculo de suspensiones)
     están en los SP de negocio de los scripts 12 y 13, que son los que se
     usan para registrar el partido.
   - Estados: la formación y la alineación se cargan con el partido
     PROGRAMADO; los goles, con el partido EN_JUEGO (el resultado se cierra
     al finalizar); los cambios y las tarjetas, EN_JUEGO o FINALIZADO (se
     pueden cargar después, desde el informe del árbitro).
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   TIPO_GOL
   ============================================================================ */

/*
  usp_TIPO_GOL_Alta
  Valida: descripción obligatoria, de hasta 40 caracteres y no repetida. La
  descripción se guarda en mayúsculas.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_TIPO_GOL_Alta
    @descripcion   VARCHAR(80),
    @es_en_contra  BIT     = 0,
    @id_tipo_gol   TINYINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @descripcion = UPPER(NULLIF(TRIM(@descripcion), ''));

    IF @descripcion IS NULL
        SET @errores += @nl + N'- La descripción es obligatoria.';
    ELSE IF LEN(@descripcion) > 40
        SET @errores += @nl + N'- La descripción no puede superar los 40 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = @descripcion)
        SET @errores += @nl + N'- Ya existe el tipo de gol "' + @descripcion + N'".';

    IF @es_en_contra IS NULL
        SET @errores += @nl + N'- Hay que indicar si el tipo es un gol en contra (0 o 1).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_TIPO_GOL_Alta: no se pudo dar de alta el tipo de gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DesarrolloPartido.TIPO_GOL (descripcion, es_en_contra)
    VALUES (@descripcion, @es_en_contra);

    SET @id_tipo_gol = SCOPE_IDENTITY();
END;
GO


/*
  usp_TIPO_GOL_Modificacion
  Valida: que el tipo exista y que se informe al menos un dato; la descripción
  con las reglas del alta; que no cambie si es en contra cuando ya hay goles
  de ese tipo (cambiaría el resultado de esos partidos).
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_TIPO_GOL_Modificacion
    @id_tipo_gol   TINYINT,
    @descripcion   VARCHAR(80) = NULL,
    @es_en_contra  BIT         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @en_contra_act  BIT;

    SET @descripcion = UPPER(NULLIF(TRIM(@descripcion), ''));

    SELECT @en_contra_act = es_en_contra FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol;

    IF @id_tipo_gol IS NULL
        SET @errores += @nl + N'- El id del tipo de gol es obligatorio.';
    ELSE IF @en_contra_act IS NULL
        SET @errores += @nl + N'- No existe un tipo de gol con id ' + CAST(@id_tipo_gol AS NVARCHAR(3)) + N'.';

    IF @descripcion IS NULL AND @es_en_contra IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@descripcion) > 40
        SET @errores += @nl + N'- La descripción no puede superar los 40 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL
                    WHERE descripcion = @descripcion AND id_tipo_gol <> @id_tipo_gol)
        SET @errores += @nl + N'- Ya existe otro tipo de gol "' + @descripcion + N'".';

    IF @es_en_contra <> @en_contra_act
       AND EXISTS (SELECT 1 FROM DesarrolloPartido.GOL WHERE id_tipo_gol = @id_tipo_gol)
        SET @errores += @nl + N'- Hay goles de este tipo: cambiar si es en contra alteraría sus resultados.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_TIPO_GOL_Modificacion: no se pudo modificar el tipo de gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DesarrolloPartido.TIPO_GOL
    SET descripcion  = ISNULL(@descripcion, descripcion),
        es_en_contra = ISNULL(@es_en_contra, es_en_contra)
    WHERE id_tipo_gol = @id_tipo_gol;
END;
GO


/*
  usp_TIPO_GOL_Baja
  Valida: que el tipo exista y que no haya goles de ese tipo.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_TIPO_GOL_Baja
    @id_tipo_gol TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @goles   INT;

    IF @id_tipo_gol IS NULL
        SET @errores += @nl + N'- El id del tipo de gol es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol)
        SET @errores += @nl + N'- No existe un tipo de gol con id ' + CAST(@id_tipo_gol AS NVARCHAR(3)) + N'.';
    ELSE
    BEGIN
        SELECT @goles = COUNT(*) FROM DesarrolloPartido.GOL WHERE id_tipo_gol = @id_tipo_gol;
        IF @goles > 0
            SET @errores += @nl + N'- Lo referencian ' + CAST(@goles AS NVARCHAR(10))
                          + N' registro(s) de DesarrolloPartido.GOL.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_TIPO_GOL_Baja: no se pudo dar de baja el tipo de gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol;
END;
GO


/* ============================================================================
   FORMACION
   ============================================================================ */

/*
  usp_FORMACION_Alta
  Valida: partido existente y PROGRAMADO; selección existente, que juegue ese
  partido y que todavía no tenga formación; esquema táctico obligatorio, de
  hasta 10 caracteres, con líneas de 1 a 9 jugadores separadas por guiones
  (ej. 4-3-3 o 4-2-3-1) que sumen los 10 jugadores de campo.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_FORMACION_Alta
    @id_partido       INT,
    @id_seleccion     INT,
    @esquema_tactico  VARCHAR(20),
    @id_formacion     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores   NVARCHAR(2048) = N'';
    DECLARE @nl        NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado    VARCHAR(12);
    DECLARE @local     INT;
    DECLARE @visitante INT;

    SET @esquema_tactico = NULLIF(TRIM(@esquema_tactico), '');

    SELECT @estado = estado, @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- La formación se registra antes de que empiece el partido (estado actual: '
                      + @estado + N').';

    IF @id_seleccion IS NULL
        SET @errores += @nl + N'- La selección es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- No existe una selección con id ' + CAST(@id_seleccion AS NVARCHAR(10)) + N'.';
    ELSE IF @estado IS NOT NULL AND @id_seleccion <> ISNULL(@local, -1) AND @id_seleccion <> ISNULL(@visitante, -1)
        SET @errores += @nl + N'- La selección no juega ese partido.';
    ELSE IF EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION
                    WHERE id_partido = @id_partido AND id_seleccion = @id_seleccion)
        SET @errores += @nl + N'- La selección ya tiene formación para ese partido.';

    IF @esquema_tactico IS NULL
        SET @errores += @nl + N'- El esquema táctico es obligatorio.';
    ELSE IF LEN(@esquema_tactico) > 10
            OR @esquema_tactico NOT LIKE '[1-9]-[1-9]%'
            OR EXISTS (SELECT 1 FROM STRING_SPLIT(@esquema_tactico, '-') WHERE value NOT LIKE '[1-9]')
            OR (SELECT SUM(CAST(value AS INT)) FROM STRING_SPLIT(@esquema_tactico, '-')
                WHERE value LIKE '[1-9]') <> 10
        SET @errores += @nl + N'- El esquema táctico son líneas de 1 a 9 jugadores separadas por guiones '
                      + N'que suman 10 jugadores de campo (ej. 4-3-3 o 4-2-3-1).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_FORMACION_Alta: no se pudo dar de alta la formación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
    VALUES (@id_partido, @id_seleccion, @esquema_tactico);

    SET @id_formacion = SCOPE_IDENTITY();
END;
GO


/*
  usp_FORMACION_Modificacion
  Valida: que la formación exista, que el partido no haya terminado y el
  esquema táctico con las reglas del alta. El partido y la selección no se
  modifican.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_FORMACION_Modificacion
    @id_formacion     INT,
    @esquema_tactico  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado  VARCHAR(12);

    SET @esquema_tactico = NULLIF(TRIM(@esquema_tactico), '');

    SELECT @estado = p.estado
    FROM DesarrolloPartido.FORMACION AS f
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
    WHERE f.id_formacion = @id_formacion;

    IF @id_formacion IS NULL
        SET @errores += @nl + N'- El id de la formación es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe una formación con id ' + CAST(@id_formacion AS NVARCHAR(10)) + N'.';
    ELSE IF @estado = 'FINALIZADO'
        SET @errores += @nl + N'- El partido ya terminó.';

    IF @esquema_tactico IS NULL
        SET @errores += @nl + N'- El esquema táctico es obligatorio.';
    ELSE IF LEN(@esquema_tactico) > 10
            OR @esquema_tactico NOT LIKE '[1-9]-[1-9]%'
            OR EXISTS (SELECT 1 FROM STRING_SPLIT(@esquema_tactico, '-') WHERE value NOT LIKE '[1-9]')
            OR (SELECT SUM(CAST(value AS INT)) FROM STRING_SPLIT(@esquema_tactico, '-')
                WHERE value LIKE '[1-9]') <> 10
        SET @errores += @nl + N'- El esquema táctico son líneas de 1 a 9 jugadores separadas por guiones '
                      + N'que suman 10 jugadores de campo (ej. 4-3-3 o 4-2-3-1).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_FORMACION_Modificacion: no se pudo modificar la formación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DesarrolloPartido.FORMACION
    SET esquema_tactico = @esquema_tactico
    WHERE id_formacion = @id_formacion;
END;
GO


/*
  usp_FORMACION_Baja
  Valida: que la formación exista y que no tenga jugadores alineados.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_FORMACION_Baja
    @id_formacion INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores   NVARCHAR(2048) = N'';
    DECLARE @nl        NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @alineados INT;

    IF @id_formacion IS NULL
        SET @errores += @nl + N'- El id de la formación es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion)
        SET @errores += @nl + N'- No existe una formación con id ' + CAST(@id_formacion AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @alineados = COUNT(*) FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;
        IF @alineados > 0
            SET @errores += @nl + N'- La referencian ' + CAST(@alineados AS NVARCHAR(10))
                          + N' registro(s) de DesarrolloPartido.ALINEACION.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_FORMACION_Baja: no se pudo dar de baja la formación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
END;
GO


/* ============================================================================
   ALINEACION
   ============================================================================ */

/*
  usp_ALINEACION_Alta
  Valida: formación existente y partido PROGRAMADO; jugador existente, de la
  selección de la formación, convocado a la fecha del partido (dado de alta
  antes y no dado de baja) y que no figure ya en la formación; que no esté
  suspendido para ese partido (fn_JugadoresSuspendidos), ni de titular ni de
  suplente; titular o suplente obligatorio; un titular necesita su posición
  en cancha (hasta 30 caracteres) y no puede haber más de 11 titulares.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_ALINEACION_Alta
    @id_formacion        INT,
    @id_jugador          INT,
    @es_titular          BIT,
    @posicion_en_cancha  VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_partido     INT;
    DECLARE @id_seleccion   INT;
    DECLARE @estado         VARCHAR(12);
    DECLARE @fecha_partido  DATE;
    DECLARE @sel_jugador    INT;
    DECLARE @fecha_alta     DATE;
    DECLARE @fecha_baja     DATE;
    DECLARE @titulares      INT;
    DECLARE @suspension     VARCHAR(200);

    SET @posicion_en_cancha = UPPER(NULLIF(TRIM(@posicion_en_cancha), ''));

    SELECT @id_partido    = f.id_partido,
           @id_seleccion  = f.id_seleccion,
           @estado        = p.estado,
           @fecha_partido = CAST(p.fecha_hora_local AS DATE)
    FROM DesarrolloPartido.FORMACION AS f
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
    WHERE f.id_formacion = @id_formacion;

    SELECT @sel_jugador = l.id_seleccion, @fecha_alta = j.fecha_alta, @fecha_baja = j.fecha_baja
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE j.id_jugador = @id_jugador;

    IF @id_formacion IS NULL
        SET @errores += @nl + N'- La formación es obligatoria.';
    ELSE IF @id_partido IS NULL
        SET @errores += @nl + N'- No existe una formación con id ' + CAST(@id_formacion AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- La alineación se registra antes de que empiece el partido (estado actual: '
                      + @estado + N').';

    IF @id_jugador IS NULL
        SET @errores += @nl + N'- El jugador es obligatorio.';
    ELSE IF @sel_jugador IS NULL
        SET @errores += @nl + N'- No existe un jugador con id ' + CAST(@id_jugador AS NVARCHAR(10)) + N'.';
    ELSE IF @id_seleccion IS NOT NULL
    BEGIN
        IF @sel_jugador <> @id_seleccion
            SET @errores += @nl + N'- El jugador no es de la selección de la formación.';
        ELSE IF @fecha_alta > @fecha_partido OR @fecha_baja <= @fecha_partido
            SET @errores += @nl + N'- El jugador no estaba convocado en la fecha del partido.';

        IF EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION
                   WHERE id_formacion = @id_formacion AND id_jugador = @id_jugador)
            SET @errores += @nl + N'- El jugador ya figura en la formación.';

        SELECT TOP (1) @suspension = motivo + ' en el partido ' + CAST(numero_partido_origen AS VARCHAR(3))
        FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido)
        WHERE id_jugador = @id_jugador;
        IF @suspension IS NOT NULL
            SET @errores += @nl + N'- El jugador está suspendido para este partido (' + @suspension + N').';
    END;

    IF @es_titular IS NULL
        SET @errores += @nl + N'- Hay que indicar si es titular (1) o suplente (0).';
    ELSE IF @es_titular = 1
    BEGIN
        IF @posicion_en_cancha IS NULL
            SET @errores += @nl + N'- Un titular necesita su posición en cancha.';
        SELECT @titulares = COUNT(*)
        FROM DesarrolloPartido.ALINEACION
        WHERE id_formacion = @id_formacion AND es_titular = 1;
        IF @titulares >= 11
            SET @errores += @nl + N'- La formación ya tiene sus 11 titulares.';
    END;

    IF LEN(@posicion_en_cancha) > 30
        SET @errores += @nl + N'- La posición en cancha no puede superar los 30 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_ALINEACION_Alta: no se pudo dar de alta la alineación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
    VALUES (@id_formacion, @id_jugador, @es_titular, @posicion_en_cancha);
END;
GO


/*
  usp_ALINEACION_Modificacion
  Valida: que la alineación exista, que el partido esté PROGRAMADO y que se
  informe al menos un dato; que un titular tenga posición y que no queden más
  de 11 titulares.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_ALINEACION_Modificacion
    @id_formacion        INT,
    @id_jugador          INT,
    @es_titular          BIT         = NULL,
    @posicion_en_cancha  VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado         VARCHAR(12);
    DECLARE @titular_final  BIT;
    DECLARE @posicion_final VARCHAR(30);
    DECLARE @titulares      INT;

    SET @posicion_en_cancha = UPPER(NULLIF(TRIM(@posicion_en_cancha), ''));

    SELECT @estado         = p.estado,
           @titular_final  = ISNULL(@es_titular, a.es_titular),
           @posicion_final = ISNULL(LEFT(@posicion_en_cancha, 30), a.posicion_en_cancha)
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
    WHERE a.id_formacion = @id_formacion AND a.id_jugador = @id_jugador;

    IF @id_formacion IS NULL OR @id_jugador IS NULL
        SET @errores += @nl + N'- La formación y el jugador son obligatorios.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- El jugador no figura en esa formación.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- La alineación se modifica antes de que empiece el partido (estado actual: '
                      + @estado + N'); durante el partido se registran cambios.';

    IF @es_titular IS NULL AND @posicion_en_cancha IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@posicion_en_cancha) > 30
        SET @errores += @nl + N'- La posición en cancha no puede superar los 30 caracteres.';

    IF @titular_final = 1
    BEGIN
        IF @posicion_final IS NULL
            SET @errores += @nl + N'- Un titular necesita su posición en cancha.';
        SELECT @titulares = COUNT(*)
        FROM DesarrolloPartido.ALINEACION
        WHERE id_formacion = @id_formacion AND es_titular = 1 AND id_jugador <> @id_jugador;
        IF @titulares >= 11
            SET @errores += @nl + N'- La formación ya tiene sus 11 titulares.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_ALINEACION_Modificacion: no se pudo modificar la alineación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DesarrolloPartido.ALINEACION
    SET es_titular         = @titular_final,
        posicion_en_cancha = @posicion_final
    WHERE id_formacion = @id_formacion AND id_jugador = @id_jugador;
END;
GO


/*
  usp_ALINEACION_Baja
  Valida: que la alineación exista y que el jugador no tenga cambios, goles
  ni tarjetas en ese partido.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_ALINEACION_Baja
    @id_formacion INT,
    @id_jugador   INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores    NVARCHAR(2048) = N'';
    DECLARE @nl         NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_partido INT;

    SELECT @id_partido = f.id_partido
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE a.id_formacion = @id_formacion AND a.id_jugador = @id_jugador;

    IF @id_formacion IS NULL OR @id_jugador IS NULL
        SET @errores += @nl + N'- La formación y el jugador son obligatorios.';
    ELSE IF @id_partido IS NULL
        SET @errores += @nl + N'- El jugador no figura en esa formación.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- El jugador tiene ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N' en el partido.', N'')
            FROM (
                SELECT N'DesarrolloPartido.CAMBIO', COUNT(*)
                FROM DesarrolloPartido.CAMBIO
                WHERE id_partido = @id_partido AND @id_jugador IN (id_jugador_sale, id_jugador_entra)
                UNION ALL
                SELECT N'DesarrolloPartido.GOL', COUNT(*)
                FROM DesarrolloPartido.GOL
                WHERE id_partido = @id_partido AND @id_jugador IN (id_jugador_autor, id_jugador_asistencia)
                UNION ALL
                SELECT N'DesarrolloPartido.AMONESTACION', COUNT(*)
                FROM DesarrolloPartido.AMONESTACION
                WHERE id_partido = @id_partido AND id_jugador = @id_jugador
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_ALINEACION_Baja: no se pudo dar de baja la alineación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DesarrolloPartido.ALINEACION
    WHERE id_formacion = @id_formacion AND id_jugador = @id_jugador;
END;
GO


/* ============================================================================
   CAMBIO
   ============================================================================ */

/*
  usp_CAMBIO_Alta
  Valida: partido existente, EN_JUEGO o FINALIZADO; los dos jugadores en la
  formación del partido, de la misma selección y distintos; el que entra es
  suplente y no había entrado; el que sale no había salido y, si es suplente,
  había entrado antes; minuto entre 1 y 120, mayor que 90 solo en eliminación
  directa; adicional entre 0 y 30; un cambio en el entretiempo va en el
  minuto 46, 91 o 106 y sin adicional; motivo TACTICO, LESION o PRECAUCION.
  Que el que sale esté en cancha y los topes de cambios y ventanas los valida
  DesarrolloPartido.usp_RegistrarCambio.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_CAMBIO_Alta
    @id_partido        INT,
    @id_jugador_sale   INT,
    @id_jugador_entra  INT,
    @minuto            TINYINT,
    @motivo            VARCHAR(30),
    @minuto_adicional  TINYINT = 0,
    @en_entretiempo    BIT     = 0,
    @id_cambio         INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado        VARCHAR(12);
    DECLARE @fase          VARCHAR(15);
    DECLARE @sel_sale      INT;
    DECLARE @titular_sale  BIT;
    DECLARE @sel_entra     INT;
    DECLARE @titular_entra BIT;

    SET @motivo           = UPPER(NULLIF(TRIM(@motivo), ''));
    SET @minuto_adicional = ISNULL(@minuto_adicional, 0);
    SET @en_entretiempo   = ISNULL(@en_entretiempo, 0);

    SELECT @estado = estado, @fase = fase FROM Torneo.PARTIDO WHERE id_partido = @id_partido;

    SELECT @sel_sale = f.id_seleccion, @titular_sale = a.es_titular
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_sale;

    SELECT @sel_entra = f.id_seleccion, @titular_entra = a.es_titular
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_entra;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado NOT IN ('EN_JUEGO', 'FINALIZADO')
        SET @errores += @nl + N'- Los cambios se registran con el partido EN_JUEGO o FINALIZADO (estado actual: '
                      + @estado + N').';

    IF @id_jugador_sale IS NULL OR @id_jugador_entra IS NULL
        SET @errores += @nl + N'- El jugador que sale y el que entra son obligatorios.';
    ELSE IF @id_jugador_sale = @id_jugador_entra
        SET @errores += @nl + N'- El jugador que sale y el que entra tienen que ser distintos.';
    ELSE IF @estado IS NOT NULL
    BEGIN
        IF @sel_sale IS NULL
            SET @errores += @nl + N'- El jugador que sale no figura en la formación del partido.';
        IF @sel_entra IS NULL
            SET @errores += @nl + N'- El jugador que entra no figura en la formación del partido.';
        IF @sel_sale <> @sel_entra
            SET @errores += @nl + N'- Los dos jugadores tienen que ser de la misma selección.';
        IF @titular_entra = 1
            SET @errores += @nl + N'- El jugador que entra es titular: tiene que ser un suplente.';
        IF EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO
                   WHERE id_partido = @id_partido AND id_jugador_entra = @id_jugador_entra)
            SET @errores += @nl + N'- El jugador que entra ya había entrado en este partido.';
        IF EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO
                   WHERE id_partido = @id_partido AND id_jugador_sale = @id_jugador_sale)
            SET @errores += @nl + N'- El jugador que sale ya había salido en este partido.';
        IF @titular_sale = 0
           AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO
                           WHERE id_partido = @id_partido AND id_jugador_entra = @id_jugador_sale)
            SET @errores += @nl + N'- El jugador que sale es suplente y no había entrado.';
    END;

    IF @minuto IS NULL
        SET @errores += @nl + N'- El minuto es obligatorio.';
    ELSE IF @minuto NOT BETWEEN 1 AND 120
        SET @errores += @nl + N'- El minuto debe estar entre 1 y 120.';
    ELSE IF @minuto > 90 AND @fase = 'GRUPOS'
        SET @errores += @nl + N'- En la fase de grupos no hay tiempo suplementario (minuto mayor que 90).';

    IF @minuto_adicional > 30
        SET @errores += @nl + N'- El tiempo adicional no puede superar los 30 minutos.';

    IF @en_entretiempo = 1 AND (@minuto NOT IN (46, 91, 106) OR @minuto_adicional <> 0)
        SET @errores += @nl + N'- Un cambio en el entretiempo se registra en el minuto 46, 91 o 106, sin adicional.';

    IF @motivo IS NULL
        SET @errores += @nl + N'- El motivo es obligatorio.';
    ELSE IF @motivo NOT IN ('TACTICO', 'LESION', 'PRECAUCION')
        SET @errores += @nl + N'- El motivo debe ser TACTICO, LESION o PRECAUCION.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_CAMBIO_Alta: no se pudo dar de alta el cambio.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DesarrolloPartido.CAMBIO
        (id_partido, id_jugador_sale, id_jugador_entra, minuto, minuto_adicional, en_entretiempo, motivo)
    VALUES
        (@id_partido, @id_jugador_sale, @id_jugador_entra, @minuto, @minuto_adicional, @en_entretiempo, @motivo);

    SET @id_cambio = SCOPE_IDENTITY();
END;
GO


/*
  usp_CAMBIO_Modificacion
  Valida: que el cambio exista y que se informe al menos un dato; minuto,
  adicional, entretiempo y motivo con las reglas del alta, sobre los valores
  que va a tener el cambio. Los jugadores no se modifican: se da de baja el
  cambio y se registra otro.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_CAMBIO_Modificacion
    @id_cambio         INT,
    @minuto            TINYINT     = NULL,
    @minuto_adicional  TINYINT     = NULL,
    @en_entretiempo    BIT         = NULL,
    @motivo            VARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores           NVARCHAR(2048) = N'';
    DECLARE @nl                NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @fase              VARCHAR(15);
    DECLARE @minuto_final      TINYINT;
    DECLARE @adicional_final   TINYINT;
    DECLARE @entretiempo_final BIT;

    SET @motivo = UPPER(NULLIF(TRIM(@motivo), ''));

    SELECT @fase              = p.fase,
           @minuto_final      = ISNULL(@minuto, c.minuto),
           @adicional_final   = ISNULL(@minuto_adicional, c.minuto_adicional),
           @entretiempo_final = ISNULL(@en_entretiempo, c.en_entretiempo)
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
    WHERE c.id_cambio = @id_cambio;

    IF @id_cambio IS NULL
        SET @errores += @nl + N'- El id del cambio es obligatorio.';
    ELSE IF @fase IS NULL
        SET @errores += @nl + N'- No existe un cambio con id ' + CAST(@id_cambio AS NVARCHAR(10)) + N'.';

    IF @minuto IS NULL AND @minuto_adicional IS NULL AND @en_entretiempo IS NULL AND @motivo IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @minuto_final NOT BETWEEN 1 AND 120
        SET @errores += @nl + N'- El minuto debe estar entre 1 y 120.';
    ELSE IF @minuto_final > 90 AND @fase = 'GRUPOS'
        SET @errores += @nl + N'- En la fase de grupos no hay tiempo suplementario (minuto mayor que 90).';

    IF @adicional_final > 30
        SET @errores += @nl + N'- El tiempo adicional no puede superar los 30 minutos.';

    IF @entretiempo_final = 1 AND (@minuto_final NOT IN (46, 91, 106) OR @adicional_final <> 0)
        SET @errores += @nl + N'- Un cambio en el entretiempo se registra en el minuto 46, 91 o 106, sin adicional.';

    IF @motivo NOT IN ('TACTICO', 'LESION', 'PRECAUCION')
        SET @errores += @nl + N'- El motivo debe ser TACTICO, LESION o PRECAUCION.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_CAMBIO_Modificacion: no se pudo modificar el cambio.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DesarrolloPartido.CAMBIO
    SET minuto           = @minuto_final,
        minuto_adicional = @adicional_final,
        en_entretiempo   = @entretiempo_final,
        motivo           = ISNULL(@motivo, motivo)
    WHERE id_cambio = @id_cambio;
END;
GO


/*
  usp_CAMBIO_Baja
  Valida: que el cambio exista y que el jugador que entró no tenga goles,
  asistencias, tarjetas ni un cambio posterior en ese partido.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_CAMBIO_Baja
    @id_cambio INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores    NVARCHAR(2048) = N'';
    DECLARE @nl         NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_partido INT;
    DECLARE @entra      INT;

    SELECT @id_partido = id_partido, @entra = id_jugador_entra
    FROM DesarrolloPartido.CAMBIO
    WHERE id_cambio = @id_cambio;

    IF @id_cambio IS NULL
        SET @errores += @nl + N'- El id del cambio es obligatorio.';
    ELSE IF @id_partido IS NULL
        SET @errores += @nl + N'- No existe un cambio con id ' + CAST(@id_cambio AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- El jugador que entró tiene ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N' en el partido.', N'')
            FROM (
                SELECT N'DesarrolloPartido.CAMBIO', COUNT(*)
                FROM DesarrolloPartido.CAMBIO
                WHERE id_partido = @id_partido AND id_jugador_sale = @entra
                UNION ALL
                SELECT N'DesarrolloPartido.GOL', COUNT(*)
                FROM DesarrolloPartido.GOL
                WHERE id_partido = @id_partido AND @entra IN (id_jugador_autor, id_jugador_asistencia)
                UNION ALL
                SELECT N'DesarrolloPartido.AMONESTACION', COUNT(*)
                FROM DesarrolloPartido.AMONESTACION
                WHERE id_partido = @id_partido AND id_jugador = @entra
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_CAMBIO_Baja: no se pudo dar de baja el cambio.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id_cambio;
END;
GO


/* ============================================================================
   GOL
   ============================================================================ */

/*
  usp_GOL_Alta
  Valida: partido existente y EN_JUEGO; autor en la formación del partido;
  tipo de gol existente; período válido y minuto coherente con el período
  (ver 02_CrearTablas.sql); ALARGUE, PENALES y los adicionales del alargue
  (105 y 120) solo en eliminación directa; un gol en contra no puede ser de
  la definición por penales ni tener asistencia; la asistencia es de otro
  jugador de la misma selección que figure en la formación.
  Que el autor y el asistente estén en cancha lo valida
  DesarrolloPartido.usp_RegistrarGol.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_GOL_Alta
    @id_partido             INT,
    @id_jugador_autor       INT,
    @id_tipo_gol            TINYINT,
    @periodo                VARCHAR(30),
    @minuto                 TINYINT = NULL,
    @minuto_adicional       TINYINT = 0,
    @id_jugador_asistencia  INT     = NULL,
    @id_gol                 INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores    NVARCHAR(2048) = N'';
    DECLARE @nl         NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado     VARCHAR(12);
    DECLARE @fase       VARCHAR(15);
    DECLARE @sel_autor  INT;
    DECLARE @sel_asist  INT;
    DECLARE @en_contra  BIT;

    SET @periodo          = UPPER(NULLIF(TRIM(@periodo), ''));
    SET @minuto_adicional = ISNULL(@minuto_adicional, 0);

    SELECT @estado = estado, @fase = fase FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
    SELECT @en_contra = es_en_contra FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id_tipo_gol;

    SELECT @sel_autor = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_autor;

    SELECT @sel_asist = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_asistencia;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'EN_JUEGO'
        SET @errores += @nl + N'- Los goles se registran con el partido EN_JUEGO (estado actual: ' + @estado + N').';

    IF @id_jugador_autor IS NULL
        SET @errores += @nl + N'- El autor es obligatorio.';
    ELSE IF @estado IS NOT NULL AND @sel_autor IS NULL
        SET @errores += @nl + N'- El autor no figura en la formación del partido.';

    IF @id_tipo_gol IS NULL
        SET @errores += @nl + N'- El tipo de gol es obligatorio.';
    ELSE IF @en_contra IS NULL
        SET @errores += @nl + N'- No existe un tipo de gol con id ' + CAST(@id_tipo_gol AS NVARCHAR(3)) + N'.';

    IF @periodo IS NULL
        SET @errores += @nl + N'- El período es obligatorio.';
    ELSE IF @periodo NOT IN ('PRIMER_TIEMPO', 'SEGUNDO_TIEMPO', 'ALARGUE', 'ADICIONALES', 'PENALES')
        SET @errores += @nl + N'- El período debe ser PRIMER_TIEMPO, SEGUNDO_TIEMPO, ALARGUE, ADICIONALES o PENALES.';
    ELSE
    BEGIN
        IF NOT (   (@periodo = 'PENALES'        AND @minuto IS NULL AND @minuto_adicional = 0)
                OR (@periodo = 'PRIMER_TIEMPO'  AND @minuto BETWEEN 1  AND 45  AND @minuto_adicional = 0)
                OR (@periodo = 'SEGUNDO_TIEMPO' AND @minuto BETWEEN 46 AND 90  AND @minuto_adicional = 0)
                OR (@periodo = 'ALARGUE'        AND @minuto BETWEEN 91 AND 120 AND @minuto_adicional = 0)
                OR (@periodo = 'ADICIONALES'    AND @minuto IN (45, 90, 105, 120)
                                                AND @minuto_adicional BETWEEN 1 AND 30))
            SET @errores += @nl + N'- El minuto no corresponde al período: PRIMER_TIEMPO 1 a 45, SEGUNDO_TIEMPO 46 a 90, '
                          + N'ALARGUE 91 a 120, ADICIONALES minuto 45, 90, 105 o 120 con adicional de 1 a 30, '
                          + N'PENALES sin minuto.';

        IF @fase = 'GRUPOS'
           AND (@periodo IN ('ALARGUE', 'PENALES') OR (@periodo = 'ADICIONALES' AND @minuto IN (105, 120)))
            SET @errores += @nl + N'- En la fase de grupos no hay alargue ni definición por penales.';
    END;

    IF @en_contra = 1 AND @periodo = 'PENALES'
        SET @errores += @nl + N'- Un gol en contra no puede ser de la definición por penales.';

    IF @id_jugador_asistencia IS NOT NULL
    BEGIN
        IF @id_jugador_asistencia = @id_jugador_autor
            SET @errores += @nl + N'- El autor no puede ser también el que asiste.';
        ELSE IF @en_contra = 1 OR @periodo = 'PENALES'
            SET @errores += @nl + N'- Un gol en contra o de la definición por penales no tiene asistencia.';
        ELSE IF @sel_asist IS NULL
            SET @errores += @nl + N'- El jugador que asiste no figura en la formación del partido.';
        ELSE IF @sel_asist <> @sel_autor
            SET @errores += @nl + N'- El que asiste tiene que ser de la misma selección que el autor.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_GOL_Alta: no se pudo dar de alta el gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DesarrolloPartido.GOL
        (id_partido, id_jugador_autor, id_jugador_asistencia, id_tipo_gol, periodo, minuto, minuto_adicional)
    VALUES
        (@id_partido, @id_jugador_autor, @id_jugador_asistencia, @id_tipo_gol, @periodo, @minuto, @minuto_adicional);

    SET @id_gol = SCOPE_IDENTITY();
END;
GO


/*
  usp_GOL_Modificacion
  Valida: que el gol exista y que se informe al menos un dato; las reglas del
  alta sobre los valores que va a tener el gol. Con el partido EN_JUEGO se
  puede cambiar cualquier dato; con el partido FINALIZADO solo los que no
  alteran el resultado (minuto, período dentro del juego, asistencia o un
  tipo con el mismo valor de "en contra").
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_GOL_Modificacion
    @id_gol                 INT,
    @id_tipo_gol            TINYINT     = NULL,
    @periodo                VARCHAR(30) = NULL,
    @minuto                 TINYINT     = NULL,
    @minuto_adicional       TINYINT     = NULL,
    @id_jugador_asistencia  INT         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores          NVARCHAR(2048) = N'';
    DECLARE @nl               NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_partido       INT;
    DECLARE @estado           VARCHAR(12);
    DECLARE @fase             VARCHAR(15);
    DECLARE @autor            INT;
    DECLARE @sel_autor        INT;
    DECLARE @sel_asist        INT;
    DECLARE @tipo_final       TINYINT;
    DECLARE @periodo_actual   VARCHAR(15);
    DECLARE @periodo_final    VARCHAR(15);
    DECLARE @minuto_final     TINYINT;
    DECLARE @adicional_final  TINYINT;
    DECLARE @asist_final      INT;
    DECLARE @en_contra_actual BIT;
    DECLARE @en_contra_final  BIT;

    SET @periodo = UPPER(NULLIF(TRIM(@periodo), ''));

    SELECT @id_partido       = g.id_partido,
           @estado           = p.estado,
           @fase             = p.fase,
           @autor            = g.id_jugador_autor,
           @tipo_final       = ISNULL(@id_tipo_gol, g.id_tipo_gol),
           @periodo_actual   = g.periodo,
           @periodo_final    = ISNULL(LEFT(@periodo, 15), g.periodo),
           @minuto_final     = IIF(@periodo = 'PENALES', NULL, ISNULL(@minuto, g.minuto)),
           @adicional_final  = ISNULL(@minuto_adicional, g.minuto_adicional),
           @asist_final      = ISNULL(@id_jugador_asistencia, g.id_jugador_asistencia),
           @en_contra_actual = tg.es_en_contra
    FROM DesarrolloPartido.GOL AS g
    INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
    WHERE g.id_gol = @id_gol;

    SELECT @en_contra_final = es_en_contra FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @tipo_final;

    SELECT @sel_autor = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @autor;

    SELECT @sel_asist = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @asist_final;

    IF @id_gol IS NULL
        SET @errores += @nl + N'- El id del gol es obligatorio.';
    ELSE IF @id_partido IS NULL
        SET @errores += @nl + N'- No existe un gol con id ' + CAST(@id_gol AS NVARCHAR(10)) + N'.';
    ELSE IF @estado NOT IN ('EN_JUEGO', 'FINALIZADO')
        SET @errores += @nl + N'- El partido no está EN_JUEGO ni FINALIZADO.';
    ELSE IF @estado = 'FINALIZADO'
            AND (@en_contra_final <> @en_contra_actual
                 OR (@periodo_final = 'PENALES' AND @periodo_actual <> 'PENALES')
                 OR (@periodo_final <> 'PENALES' AND @periodo_actual = 'PENALES'))
        SET @errores += @nl + N'- El partido ya finalizó y ese cambio alteraría el resultado: hay que reabrirlo.';

    IF @id_tipo_gol IS NULL AND @periodo IS NULL AND @minuto IS NULL AND @minuto_adicional IS NULL
       AND @id_jugador_asistencia IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @id_tipo_gol IS NOT NULL AND @en_contra_final IS NULL
        SET @errores += @nl + N'- No existe un tipo de gol con id ' + CAST(@id_tipo_gol AS NVARCHAR(3)) + N'.';

    IF @periodo NOT IN ('PRIMER_TIEMPO', 'SEGUNDO_TIEMPO', 'ALARGUE', 'ADICIONALES', 'PENALES')
        SET @errores += @nl + N'- El período debe ser PRIMER_TIEMPO, SEGUNDO_TIEMPO, ALARGUE, ADICIONALES o PENALES.';
    ELSE IF @id_partido IS NOT NULL
    BEGIN
        IF NOT (   (@periodo_final = 'PENALES'        AND @minuto_final IS NULL AND @adicional_final = 0)
                OR (@periodo_final = 'PRIMER_TIEMPO'  AND @minuto_final BETWEEN 1  AND 45  AND @adicional_final = 0)
                OR (@periodo_final = 'SEGUNDO_TIEMPO' AND @minuto_final BETWEEN 46 AND 90  AND @adicional_final = 0)
                OR (@periodo_final = 'ALARGUE'        AND @minuto_final BETWEEN 91 AND 120 AND @adicional_final = 0)
                OR (@periodo_final = 'ADICIONALES'    AND @minuto_final IN (45, 90, 105, 120)
                                                      AND @adicional_final BETWEEN 1 AND 30))
            SET @errores += @nl + N'- El minuto no corresponde al período: PRIMER_TIEMPO 1 a 45, SEGUNDO_TIEMPO 46 a 90, '
                          + N'ALARGUE 91 a 120, ADICIONALES minuto 45, 90, 105 o 120 con adicional de 1 a 30, '
                          + N'PENALES sin minuto.';

        IF @fase = 'GRUPOS'
           AND (@periodo_final IN ('ALARGUE', 'PENALES')
                OR (@periodo_final = 'ADICIONALES' AND @minuto_final IN (105, 120)))
            SET @errores += @nl + N'- En la fase de grupos no hay alargue ni definición por penales.';
    END;

    IF @en_contra_final = 1 AND @periodo_final = 'PENALES'
        SET @errores += @nl + N'- Un gol en contra no puede ser de la definición por penales.';

    IF @asist_final IS NOT NULL
    BEGIN
        IF @asist_final = @autor
            SET @errores += @nl + N'- El autor no puede ser también el que asiste.';
        ELSE IF @en_contra_final = 1 OR @periodo_final = 'PENALES'
            SET @errores += @nl + N'- Un gol en contra o de la definición por penales no tiene asistencia.';
        ELSE IF @sel_asist IS NULL
            SET @errores += @nl + N'- El jugador que asiste no figura en la formación del partido.';
        ELSE IF @sel_asist <> @sel_autor
            SET @errores += @nl + N'- El que asiste tiene que ser de la misma selección que el autor.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_GOL_Modificacion: no se pudo modificar el gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DesarrolloPartido.GOL
    SET id_tipo_gol           = @tipo_final,
        periodo               = @periodo_final,
        minuto                = @minuto_final,
        minuto_adicional      = @adicional_final,
        id_jugador_asistencia = @asist_final
    WHERE id_gol = @id_gol;
END;
GO


/*
  usp_GOL_Baja
  Valida: que el gol exista y que el partido esté EN_JUEGO. Para quitar un
  gol de un partido finalizado hay que reabrirlo, porque cambia el resultado.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_GOL_Baja
    @id_gol INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado  VARCHAR(12);

    SELECT @estado = p.estado
    FROM DesarrolloPartido.GOL AS g
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
    WHERE g.id_gol = @id_gol;

    IF @id_gol IS NULL
        SET @errores += @nl + N'- El id del gol es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un gol con id ' + CAST(@id_gol AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'EN_JUEGO'
        SET @errores += @nl + N'- El partido está ' + @estado
                      + N': un gol solo se quita con el partido EN_JUEGO (si terminó, hay que reabrirlo).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_GOL_Baja: no se pudo dar de baja el gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DesarrolloPartido.GOL WHERE id_gol = @id_gol;
END;
GO


/* ============================================================================
   AMONESTACION
   ============================================================================ */

/*
  usp_AMONESTACION_Alta
  Valida: partido existente, EN_JUEGO o FINALIZADO; exactamente un receptor:
  un jugador de la formación del partido o una persona del cuerpo técnico de
  una de las dos selecciones; tipo AMARILLA o ROJA; que el receptor no haya
  sido expulsado antes en el partido ni tenga ya dos amarillas; una roja por
  doble amarilla necesita las dos amarillas previas; minuto entre 0 y 120,
  mayor que 90 solo en eliminación directa; adicional entre 0 y 30; motivo
  obligatorio de hasta 200 caracteres.
  La roja automática por segunda amarilla y el cálculo de la suspensión los
  hace DesarrolloPartido.usp_RegistrarAmonestacion.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_AMONESTACION_Alta
    @id_partido         INT,
    @tipo_tarjeta       VARCHAR(20),
    @minuto             TINYINT,
    @motivo             VARCHAR(400),
    @id_jugador         INT     = NULL,
    @id_persona_ct      INT     = NULL,
    @minuto_adicional   TINYINT = 0,
    @es_doble_amarilla  BIT     = 0,
    @id_amonestacion    INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores    NVARCHAR(2048) = N'';
    DECLARE @nl         NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado     VARCHAR(12);
    DECLARE @fase       VARCHAR(15);
    DECLARE @local      INT;
    DECLARE @visitante  INT;
    DECLARE @amarillas  INT;
    DECLARE @roja_antes BIT = 0;

    SET @tipo_tarjeta      = UPPER(NULLIF(TRIM(@tipo_tarjeta), ''));
    SET @motivo            = NULLIF(TRIM(@motivo), '');
    SET @minuto_adicional  = ISNULL(@minuto_adicional, 0);
    SET @es_doble_amarilla = ISNULL(@es_doble_amarilla, 0);

    SELECT @estado = estado, @fase = fase, @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado NOT IN ('EN_JUEGO', 'FINALIZADO')
        SET @errores += @nl + N'- Las tarjetas se registran con el partido EN_JUEGO o FINALIZADO (estado actual: '
                      + @estado + N').';

    IF (@id_jugador IS NULL AND @id_persona_ct IS NULL) OR (@id_jugador IS NOT NULL AND @id_persona_ct IS NOT NULL)
        SET @errores += @nl + N'- La tarjeta la recibe un jugador o una persona del cuerpo técnico (exactamente uno).';
    ELSE IF @estado IS NOT NULL
    BEGIN
        IF @id_jugador IS NOT NULL
           AND NOT EXISTS (SELECT 1
                           FROM DesarrolloPartido.ALINEACION AS a
                           INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                           WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador)
            SET @errores += @nl + N'- El jugador no figura en la formación del partido.';

        IF @id_persona_ct IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO
                           WHERE id_persona_ct = @id_persona_ct
                             AND id_seleccion IN (@local, @visitante))
            SET @errores += @nl + N'- La persona no es del cuerpo técnico de una de las selecciones del partido.';

        SELECT @amarillas  = SUM(IIF(tipo_tarjeta = 'AMARILLA', 1, 0)),
               @roja_antes = MAX(IIF(tipo_tarjeta = 'ROJA'
                                     AND minuto * 100 + minuto_adicional <= @minuto * 100 + @minuto_adicional, 1, 0))
        FROM DesarrolloPartido.AMONESTACION
        WHERE id_partido = @id_partido
          AND (id_jugador = @id_jugador OR id_persona_ct = @id_persona_ct);

        IF @roja_antes = 1
            SET @errores += @nl + N'- El receptor ya había sido expulsado en este partido.';
        ELSE IF @tipo_tarjeta = 'AMARILLA' AND @amarillas >= 2
            SET @errores += @nl + N'- El receptor ya tiene dos amarillas en este partido.';
        ELSE IF @es_doble_amarilla = 1 AND ISNULL(@amarillas, 0) < 2
            SET @errores += @nl + N'- Una roja por doble amarilla necesita las dos amarillas registradas antes.';
    END;

    IF @tipo_tarjeta IS NULL
        SET @errores += @nl + N'- El tipo de tarjeta es obligatorio.';
    ELSE IF @tipo_tarjeta NOT IN ('AMARILLA', 'ROJA')
        SET @errores += @nl + N'- El tipo de tarjeta debe ser AMARILLA o ROJA.';
    ELSE IF @es_doble_amarilla = 1 AND @tipo_tarjeta <> 'ROJA'
        SET @errores += @nl + N'- Solo una ROJA puede ser por doble amarilla.';

    IF @minuto IS NULL
        SET @errores += @nl + N'- El minuto es obligatorio.';
    ELSE IF @minuto > 120
        SET @errores += @nl + N'- El minuto debe estar entre 0 y 120.';
    ELSE IF @minuto > 90 AND @fase = 'GRUPOS'
        SET @errores += @nl + N'- En la fase de grupos no hay tiempo suplementario (minuto mayor que 90).';

    IF @minuto_adicional > 30
        SET @errores += @nl + N'- El tiempo adicional no puede superar los 30 minutos.';

    IF @motivo IS NULL
        SET @errores += @nl + N'- El motivo es obligatorio.';
    ELSE IF LEN(@motivo) > 200
        SET @errores += @nl + N'- El motivo no puede superar los 200 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_AMONESTACION_Alta: no se pudo dar de alta la tarjeta.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DesarrolloPartido.AMONESTACION
        (id_partido, id_jugador, id_persona_ct, tipo_tarjeta, es_doble_amarilla, minuto, minuto_adicional, motivo)
    VALUES
        (@id_partido, @id_jugador, @id_persona_ct, @tipo_tarjeta, @es_doble_amarilla, @minuto, @minuto_adicional, @motivo);

    SET @id_amonestacion = SCOPE_IDENTITY();
END;
GO


/*
  usp_AMONESTACION_Modificacion
  Valida: que la tarjeta exista y que se informe al menos un dato; minuto,
  adicional y motivo con las reglas del alta. El receptor y el tipo no se
  modifican: se da de baja la tarjeta y se registra otra.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_AMONESTACION_Modificacion
    @id_amonestacion   INT,
    @minuto            TINYINT      = NULL,
    @minuto_adicional  TINYINT      = NULL,
    @motivo            VARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @fase    VARCHAR(15);

    SET @motivo = NULLIF(TRIM(@motivo), '');

    SELECT @fase = p.fase
    FROM DesarrolloPartido.AMONESTACION AS a
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
    WHERE a.id_amonestacion = @id_amonestacion;

    IF @id_amonestacion IS NULL
        SET @errores += @nl + N'- El id de la tarjeta es obligatorio.';
    ELSE IF @fase IS NULL
        SET @errores += @nl + N'- No existe una tarjeta con id ' + CAST(@id_amonestacion AS NVARCHAR(10)) + N'.';

    IF @minuto IS NULL AND @minuto_adicional IS NULL AND @motivo IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @minuto > 120
        SET @errores += @nl + N'- El minuto debe estar entre 0 y 120.';
    ELSE IF @minuto > 90 AND @fase = 'GRUPOS'
        SET @errores += @nl + N'- En la fase de grupos no hay tiempo suplementario (minuto mayor que 90).';

    IF @minuto_adicional > 30
        SET @errores += @nl + N'- El tiempo adicional no puede superar los 30 minutos.';

    IF LEN(@motivo) > 200
        SET @errores += @nl + N'- El motivo no puede superar los 200 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_AMONESTACION_Modificacion: no se pudo modificar la tarjeta.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DesarrolloPartido.AMONESTACION
    SET minuto           = ISNULL(@minuto, minuto),
        minuto_adicional = ISNULL(@minuto_adicional, minuto_adicional),
        motivo           = ISNULL(@motivo, motivo)
    WHERE id_amonestacion = @id_amonestacion;
END;
GO


/*
  usp_AMONESTACION_Baja
  Valida: que la tarjeta exista y que no sea una amarilla que forma parte de
  una expulsión por doble amarilla (primero se da de baja la roja).
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_AMONESTACION_Baja
    @id_amonestacion INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores    NVARCHAR(2048) = N'';
    DECLARE @nl         NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_partido INT;
    DECLARE @tipo       VARCHAR(8);
    DECLARE @jugador    INT;
    DECLARE @persona    INT;

    SELECT @id_partido = id_partido, @tipo = tipo_tarjeta, @jugador = id_jugador, @persona = id_persona_ct
    FROM DesarrolloPartido.AMONESTACION
    WHERE id_amonestacion = @id_amonestacion;

    IF @id_amonestacion IS NULL
        SET @errores += @nl + N'- El id de la tarjeta es obligatorio.';
    ELSE IF @id_partido IS NULL
        SET @errores += @nl + N'- No existe una tarjeta con id ' + CAST(@id_amonestacion AS NVARCHAR(10)) + N'.';
    ELSE IF @tipo = 'AMARILLA'
            AND EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION
                        WHERE id_partido = @id_partido AND es_doble_amarilla = 1
                          AND (id_jugador = @jugador OR id_persona_ct = @persona))
        SET @errores += @nl + N'- La amarilla es parte de una expulsión por doble amarilla: primero hay que dar de baja la roja.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_AMONESTACION_Baja: no se pudo dar de baja la tarjeta.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_amonestacion;
END;
GO


-- Evidencia: SP creados en el esquema DesarrolloPartido.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DesarrolloPartido'
ORDER BY p.name;
GO
