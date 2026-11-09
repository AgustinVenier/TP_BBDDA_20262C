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

 Fecha: 08/11/2026
 Archivo: 43_Cifrado_Torneo.sql
 Objetivo: Modificar los SP de Torneo que leen o escriben el nombre, el
           apellido o la fecha de nacimiento de jugadores y cuerpos técnicos
           (ABM, convocatoria, inicio de partido e importación), para que los
           lean descifrados y los guarden cifrados.
================================================================================

 Orden: lo ejecuta 38_Ejecutar_Cifrado.sql, después de 42_Cifrado_Tablas.sql.

 Cada objeto es el de su script original (indicado arriba de cada uno), con
 estos cambios:
   - Lectura: las consultas que usan esos datos leen las vistas descifradas de
     42 (Seguridad.vw_Jugador, Seguridad.vw_PersonaCuerpoTecnico) en lugar de
     las tablas. Tienen las mismas columnas, así que el resto de la consulta no
     cambia.
   - Búsquedas y controles de duplicados: comparan sobre las vistas
     descifradas. El control de jugador repetido en la lista reemplaza a
     UQ_JUGADOR_lista_apellido_nombre, que se eliminó porque el mismo nombre
     cifrado dos veces da bytes distintos. Las importaciones reconocen así a
     las personas ya cargadas (upsert sin duplicados).
   - Escritura: el INSERT o UPDATE sigue sobre la tabla. El SP abre la clave
     (Seguridad.usp_AbrirClave), cifra con Seguridad.fn_CifrarTexto y
     Seguridad.fn_CifrarFecha, y la cierra (Seguridad.usp_CerrarClave), también
     si hay un error.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO


-- Original en 05_SP_ABM_Torneo.sql. Cambio: el control de jugador repetido en la lista y el del dorsal ocupado leen
-- Seguridad.vw_Jugador (reemplaza a UQ_JUGADOR_lista_apellido_nombre); el INSERT cifra nombre, apellido y
-- fecha de nacimiento.
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

    IF EXISTS (SELECT 1 FROM Seguridad.vw_Jugador
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
        FROM Seguridad.vw_Jugador
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

    DECLARE @abierta_aca BIT;
    BEGIN TRY
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        INSERT INTO Torneo.JUGADOR
            (id_lista, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, club_origen,
             posicion_habitual, dorsal, fecha_alta, motivo_alta)
        VALUES
            (@id_lista, @id_pais_nacimiento, Seguridad.fn_CifrarTexto(@nombre), Seguridad.fn_CifrarTexto(@apellido),
             Seguridad.fn_CifrarFecha(@fecha_nacimiento), @club_origen,
             @posicion_habitual, @dorsal, @fecha_alta, @motivo_alta);

        SET @id_jugador = SCOPE_IDENTITY();
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 05_SP_ABM_Torneo.sql. Cambio: lee los datos actuales y hace los controles sobre Seguridad.vw_Jugador; el UPDATE
-- cifra los datos informados.
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
    FROM Seguridad.vw_Jugador
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
       AND EXISTS (SELECT 1 FROM Seguridad.vw_Jugador
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
        FROM Seguridad.vw_Jugador
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

    -- Un dato que no se informa conserva el valor guardado (ya cifrado); el informado se cifra.
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        UPDATE Torneo.JUGADOR
        SET nombre             = IIF(@nombre IS NULL, nombre, Seguridad.fn_CifrarTexto(@nombre)),
            apellido           = IIF(@apellido IS NULL, apellido, Seguridad.fn_CifrarTexto(@apellido)),
            posicion_habitual  = ISNULL(@posicion_habitual, posicion_habitual),
            dorsal             = ISNULL(@dorsal, dorsal),
            fecha_nacimiento   = IIF(@fecha_nacimiento IS NULL, fecha_nacimiento, Seguridad.fn_CifrarFecha(@fecha_nacimiento)),
            club_origen        = ISNULL(@club_origen, club_origen),
            id_pais_nacimiento = ISNULL(@id_pais_nacimiento, id_pais_nacimiento),
            motivo_alta        = ISNULL(@motivo_alta, motivo_alta)
        WHERE id_jugador = @id_jugador;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 05_SP_ABM_Torneo.sql. Cambio: el control de persona repetida lee Seguridad.vw_PersonaCuerpoTecnico; el INSERT
-- cifra nombre, apellido y fecha de nacimiento.
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

    IF EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico
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

    DECLARE @abierta_aca BIT;
    BEGIN TRY
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        INSERT INTO Torneo.PERSONA_CUERPO_TECNICO
            (id_seleccion, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, rol)
        VALUES
            (@id_seleccion, @id_pais_nacimiento, Seguridad.fn_CifrarTexto(@nombre), Seguridad.fn_CifrarTexto(@apellido),
             Seguridad.fn_CifrarFecha(@fecha_nacimiento), @rol);

        SET @id_persona_ct = SCOPE_IDENTITY();
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 05_SP_ABM_Torneo.sql. Cambio: lee los datos actuales y controla la persona repetida sobre
-- Seguridad.vw_PersonaCuerpoTecnico; el UPDATE cifra los datos informados.
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
    FROM Seguridad.vw_PersonaCuerpoTecnico
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
       AND EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico
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

    -- Un dato que no se informa conserva el valor guardado (ya cifrado); el informado se cifra.
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        UPDATE Torneo.PERSONA_CUERPO_TECNICO
        SET nombre             = IIF(@nombre IS NULL, nombre, Seguridad.fn_CifrarTexto(@nombre)),
            apellido           = IIF(@apellido IS NULL, apellido, Seguridad.fn_CifrarTexto(@apellido)),
            rol                = ISNULL(@rol, rol),
            fecha_nacimiento   = IIF(@fecha_nacimiento IS NULL, fecha_nacimiento, Seguridad.fn_CifrarFecha(@fecha_nacimiento)),
            id_pais_nacimiento = ISNULL(@id_pais_nacimiento, id_pais_nacimiento)
        WHERE id_persona_ct = @id_persona_ct;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 10_SP_Negocio_SedesYPartidos.sql. Cambio: lee los jugadores suspendidos del mensaje de Seguridad.vw_Jugador.
/*
  usp_IniciarPartido
  Pasa un partido a EN_JUEGO, que es el estado en que se registran goles,
  cambios y tarjetas. Valida: partido existente y PROGRAMADO; las dos
  selecciones definidas; cada una con su formación de 11 titulares; la
  designación arbitral completa (principal, dos asistentes, cuarto árbitro y
  VAR); que ningún jugador de las formaciones esté suspendido. Si el partido
  no tiene asignados sus 4 espacios publicitarios, avisa pero no lo impide.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_IniciarPartido
    @id_partido INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado       VARCHAR(12);
    DECLARE @local        INT;
    DECLARE @visitante    INT;
    DECLARE @exhibiciones INT;

    SELECT @estado = estado, @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @estado <> 'PROGRAMADO'
            SET @errores += @nl + N'- El partido está ' + @estado + N': solo empieza un partido PROGRAMADO.';

        IF @local IS NULL OR @visitante IS NULL
            SET @errores += @nl + N'- Las dos selecciones tienen que estar definidas.';
        ELSE
            -- Selecciones sin formación o sin sus 11 titulares.
            SET @errores += ISNULL((
                SELECT STRING_AGG(@nl + N'- ' + pa.nombre + N' tiene ' + CAST(t.titulares AS NVARCHAR(3))
                                  + N' titulares cargados (tienen que ser 11).', N'')
                FROM (VALUES (@local), (@visitante)) AS v (id_seleccion)
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = v.id_seleccion
                INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
                CROSS APPLY (SELECT COUNT(a.id_jugador) AS titulares
                             FROM DesarrolloPartido.FORMACION AS f
                             LEFT JOIN DesarrolloPartido.ALINEACION AS a
                                    ON a.id_formacion = f.id_formacion AND a.es_titular = 1
                             WHERE f.id_partido = @id_partido AND f.id_seleccion = v.id_seleccion) AS t
                WHERE t.titulares <> 11), N'');

        -- Roles sin designar.
        SET @errores += ISNULL((
            SELECT @nl + N'- Falta designar: ' + STRING_AGG(r.rol, ', ') + N'.'
            FROM (VALUES ('PRINCIPAL'), ('ASISTENTE_1'), ('ASISTENTE_2'), ('CUARTO'), ('VAR')) AS r (rol)
            WHERE NOT EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                              WHERE d.id_partido = @id_partido AND d.rol = r.rol)), N'');

        -- Jugadores alineados que están suspendidos.
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- ' + j.apellido + N', ' + j.nombre + N' está suspendido ('
                              + s.motivo + N' en el partido ' + CAST(s.numero_partido_origen AS NVARCHAR(3)) + N').', N'')
            FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido) AS s
            INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = s.id_jugador
            WHERE EXISTS (SELECT 1
                          FROM DesarrolloPartido.ALINEACION AS a
                          INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                          WHERE f.id_partido = @id_partido AND a.id_jugador = s.id_jugador)), N'');
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_IniciarPartido: no se pudo iniciar el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @exhibiciones = COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
    IF @exhibiciones < 4
        PRINT CONCAT(N'Advertencia: el partido empieza con ', @exhibiciones,
                     N' de sus 4 espacios publicitarios asignados.');

    -- Una sola sentencia: no hace falta abrir una transacción.
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
END;
GO


-- Original en 11_SP_Negocio_Convocatoria.sql. Cambio: lee el director técnico del resultado de Seguridad.vw_PersonaCuerpoTecnico (el alta la
-- hace usp_PERSONA_CUERPO_TECNICO_Alta, que cifra).
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
        INNER JOIN Seguridad.vw_PersonaCuerpoTecnico AS ct
                ON ct.id_seleccion = s.id_seleccion AND ct.rol = 'DIRECTOR_TECNICO'
        WHERE s.id_seleccion = @id_seleccion;
END;
GO


-- Original en 11_SP_Negocio_Convocatoria.sql. Cambio: el INSERT de la lista cifra nombre, apellido y fecha de nacimiento.
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
  Torneo.usp_JUGADOR_Alta y carga a todos con un solo INSERT, sin recorrer la
  lista fila por fila (las reglas del alta de jugador quedan en los dos SP).
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

    SET @errores += ISNULL((
        SELECT @nl + N'- Dorsales fuera de rango (1 a 99): ' + STRING_AGG(CAST(dorsal AS NVARCHAR(3)), ', ') + N'.'
        FROM @lista WHERE dorsal NOT BETWEEN 1 AND 99), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Fecha de nacimiento futura (dorsal): ' + STRING_AGG(ISNULL(CAST(dorsal AS NVARCHAR(3)), N'sin dorsal'), ', ') + N'.'
        FROM @lista WHERE fecha_nacimiento > CONVERT(DATE, GETDATE())), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- No existen los países de nacimiento con id: '
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

    DECLARE @abierta_aca BIT;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        INSERT INTO Torneo.JUGADOR
            (id_lista, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, club_origen,
             posicion_habitual, dorsal, fecha_alta, motivo_alta)
        SELECT @id_lista, id_pais_nacimiento, Seguridad.fn_CifrarTexto(nombre), Seguridad.fn_CifrarTexto(apellido),
               Seguridad.fn_CifrarFecha(fecha_nacimiento), club_origen,
               posicion_habitual, dorsal, @fecha_presentacion, 'Lista inicial'
        FROM @lista
        ORDER BY dorsal, apellido, nombre;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
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


-- Original en 11_SP_Negocio_Convocatoria.sql. Cambio: lee el jugador que sale y el resultado de Seguridad.vw_Jugador (el alta la hace
-- usp_JUGADOR_Alta, que cifra).
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
    FROM Seguridad.vw_Jugador AS j
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
        FROM Seguridad.vw_Jugador
        WHERE id_jugador IN (@id_jugador_baja, @id_jugador_alta)
        ORDER BY fecha_alta;
END;
GO


-- Original en 16_SP_Importacion.sql. Cambio: reconoce a los jugadores ya cargados sobre Seguridad.vw_Jugador (lista, apellido
-- y nombre) y compara su fecha de nacimiento descifrada; cifra lo que carga.
/*
  usp_ImportarJugadores
  Upsert de jugadores de las listas de convocados, por selección (código FIFA
  de su país), apellido y nombre, desde #staging_jugadores. Columnas que usa:
  id_registro (distinto en cada fila), codigo_fifa, nombre, apellido,
  posicion, dorsal, fecha_nacimiento, club_origen, errores y accion.
  Acepta las posiciones en español, abreviadas (GK, DF, MF, FW) o en inglés.
  Un jugador nuevo se da de alta en la fecha de presentación de la lista,
  con motivo "Importación"; en uno existente, la fecha de nacimiento y el
  club que no vienen no se borran. Los jugadores de la lista que no vienen
  quedan como están.
  Valida cada jugador pendiente: selección con lista de convocados; nombre,
  apellido, posición y dorsal obligatorios; nombre y apellido de hasta 60
  caracteres y club de hasta 100; posición válida; dorsal entre 1 y 99;
  fecha de nacimiento no futura; que no venga dos veces. Y con los válidos,
  cada lista como quedaría: un dorsal repetido entre los activos rechaza a
  los que lo traen; una lista con más de MAX_CONVOCADOS activos o, si es la
  inicial (estaba vacía), sin entre MIN_CONVOCADOS y MAX_CONVOCADOS
  jugadores con al menos MIN_ARQUEROS_CONVOCADOS arqueros, rechaza a todos
  los de esa selección. Con eso cubre las reglas de usp_JUGADOR_Alta,
  usp_JUGADOR_Modificacion y usp_RegistrarConvocatoria.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarJugadores
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl              NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia     BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @min_convocados  TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados  TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros    TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');

    -- La lista y el jugador ya registrados de cada fila pendiente.
    DECLARE @registrados TABLE (
        id_registro         INT PRIMARY KEY,
        id_lista            INT,
        fecha_presentacion  DATE,
        lista_vacia         BIT,
        id_jugador          INT,
        activo              BIT
    );

    IF OBJECT_ID(N'tempdb..#staging_jugadores') IS NULL
        THROW 50001, N'Torneo.usp_ImportarJugadores: no se importó nada, falta la tabla #staging_jugadores con los jugadores.', 1;

    UPDATE #staging_jugadores
    SET codigo_fifa = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre      = NULLIF(TRIM(nombre), N''),
        apellido    = NULLIF(TRIM(apellido), N''),
        club_origen = NULLIF(TRIM(club_origen), N''),
        posicion    = CASE UPPER(NULLIF(TRIM(posicion), ''))
                          WHEN 'GK' THEN 'ARQUERO'       WHEN 'GOALKEEPER' THEN 'ARQUERO'
                          WHEN 'DF' THEN 'DEFENSOR'      WHEN 'DEFENDER'   THEN 'DEFENSOR'
                          WHEN 'MF' THEN 'MEDIOCAMPISTA' WHEN 'MIDFIELDER' THEN 'MEDIOCAMPISTA'
                          WHEN 'FW' THEN 'DELANTERO'     WHEN 'FORWARD'    THEN 'DELANTERO'
                          ELSE UPPER(NULLIF(TRIM(posicion), ''))
                      END
    WHERE accion IS NULL;

    INSERT INTO @registrados (id_registro, id_lista, fecha_presentacion, lista_vacia)
    SELECT st.id_registro, lc.id_lista, lc.fecha_presentacion,
           IIF(lc.id_lista IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j WHERE j.id_lista = lc.id_lista), 1, 0)
    FROM #staging_jugadores AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_seleccion = s.id_seleccion
    WHERE st.accion IS NULL;

    UPDATE r SET id_jugador = j.id_jugador, activo = IIF(j.fecha_baja IS NULL, 1, 0)
    FROM @registrados AS r
    INNER JOIN #staging_jugadores AS st ON st.id_registro = r.id_registro
    INNER JOIN Seguridad.vw_Jugador AS j ON j.id_lista = r.id_lista AND j.apellido = st.apellido AND j.nombre = st.nombre;

    /* 1. Las reglas de cada jugador. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- El código FIFA de la selección es obligatorio.'
                 WHEN r.id_lista IS NULL     THEN @nl + N'- No hay una selección con lista de convocados con código FIFA "'
                                                       + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @nl + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @nl + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.posicion IS NULL THEN @nl + N'- La posición es obligatoria.'
                 WHEN st.posicion NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')
                     THEN @nl + N'- La posición "' + st.posicion + N'" no es ARQUERO, DEFENSOR, MEDIOCAMPISTA ni DELANTERO '
                              + N'(ni GK, DF, MF o FW).'
            END,
            CASE WHEN st.dorsal IS NULL THEN @nl + N'- El dorsal es obligatorio.'
                 WHEN st.dorsal NOT BETWEEN 1 AND 99
                     THEN @nl + N'- El dorsal ' + CAST(st.dorsal AS NVARCHAR(3)) + N' no está entre 1 y 99.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @nl + N'- La fecha de nacimiento no puede ser futura.', NULL),
            IIF(LEN(st.club_origen) > 100, @nl + N'- El club no puede superar los 100 caracteres.', NULL)), N'')
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Este jugador viene ', r.veces, N' veces.')
    FROM #staging_jugadores AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_jugadores
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido
    WHERE st.accion IS NULL;

    /* 2. Cada lista como quedaría con los jugadores válidos (los activos que no vienen, más
          los que vienen). Un dorsal repetido entre los activos rechaza a los que lo traen. */
    WITH validos AS (
        SELECT st.id_registro, r.id_lista, r.lista_vacia, r.id_jugador, st.dorsal, st.posicion
        FROM #staging_jugadores AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL AND ISNULL(r.activo, 1) = 1
    ),
    plantel AS (
        SELECT id_lista, dorsal FROM validos
        UNION ALL
        SELECT j.id_lista, j.dorsal
        FROM Torneo.JUGADOR AS j
        WHERE j.fecha_baja IS NULL
          AND j.id_lista IN (SELECT id_lista FROM @registrados)
          AND NOT EXISTS (SELECT 1 FROM validos AS v WHERE v.id_jugador = j.id_jugador)
    ),
    repetidos AS (
        SELECT id_lista, dorsal, COUNT(*) AS veces FROM plantel GROUP BY id_lista, dorsal HAVING COUNT(*) > 1
    )
    UPDATE st
    SET errores = CONCAT(@nl, N'- El dorsal ', st.dorsal, N' lo tendrían ', rp.veces, N' convocados activos de la selección.')
    FROM #staging_jugadores AS st
    INNER JOIN validos AS v ON v.id_registro = st.id_registro
    INNER JOIN repetidos AS rp ON rp.id_lista = v.id_lista AND rp.dorsal = v.dorsal;

    -- Una lista que no cumple el reglamento rechaza a todos los jugadores de esa selección.
    WITH validos AS (
        SELECT st.id_registro, r.id_lista, r.lista_vacia, r.id_jugador, st.posicion
        FROM #staging_jugadores AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL AND ISNULL(r.activo, 1) = 1
    ),
    plantel AS (
        SELECT id_lista, lista_vacia, posicion FROM validos
        UNION ALL
        SELECT j.id_lista, 0, j.posicion_habitual
        FROM Torneo.JUGADOR AS j
        WHERE j.fecha_baja IS NULL
          AND j.id_lista IN (SELECT id_lista FROM @registrados)
          AND NOT EXISTS (SELECT 1 FROM validos AS v WHERE v.id_jugador = j.id_jugador)
    ),
    listas AS (
        SELECT id_lista, MAX(CAST(lista_vacia AS TINYINT)) AS vacia, COUNT(*) AS jugadores,
               SUM(IIF(posicion = 'ARQUERO', 1, 0)) AS arqueros
        FROM plantel
        GROUP BY id_lista
    )
    UPDATE st
    SET errores = CONCAT(st.errores, @nl,
                         IIF(l.jugadores > @max_convocados,
                             CONCAT(N'- La lista de la selección quedaría con ', l.jugadores, N' convocados activos y el máximo es ',
                                    @max_convocados, N' (MAX_CONVOCADOS).'),
                             CONCAT(N'- La lista inicial de la selección tendría ', l.jugadores, N' jugadores y ', l.arqueros,
                                    N' arqueros: tienen que ser entre ', @min_convocados, N' y ', @max_convocados,
                                    N', con al menos ', @min_arqueros, N' arqueros.')))
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    INNER JOIN listas AS l ON l.id_lista = r.id_lista
    WHERE l.jugadores > @max_convocados
       OR (l.vacia = 1 AND (l.jugadores < @min_convocados OR l.arqueros < @min_arqueros));

    UPDATE #staging_jugadores SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 3. Lo que le pasa a cada jugador válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_jugador IS NULL THEN 'INSERTADO'
                      WHEN st.posicion <> j.posicion_habitual OR st.dorsal <> j.dorsal
                        OR st.fecha_nacimiento <> ISNULL(j.fecha_nacimiento, '19000101')
                        OR st.club_origen <> ISNULL(j.club_origen, N'')
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    LEFT JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = r.id_jugador
    WHERE st.accion IS NULL;

    /* 4. Carga, todos juntos. */
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        -- La fecha que no viene conserva la guardada (ya cifrada); la que viene se cifra.
        UPDATE j
        SET posicion_habitual = st.posicion,
            dorsal            = st.dorsal,
            fecha_nacimiento  = IIF(st.fecha_nacimiento IS NULL, j.fecha_nacimiento, Seguridad.fn_CifrarFecha(st.fecha_nacimiento)),
            club_origen       = ISNULL(st.club_origen, j.club_origen)
        FROM Torneo.JUGADOR AS j
        INNER JOIN @registrados AS r ON r.id_jugador = j.id_jugador
        INNER JOIN #staging_jugadores AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.JUGADOR
            (id_lista, nombre, apellido, fecha_nacimiento, club_origen, posicion_habitual, dorsal,
             fecha_alta, motivo_alta)
        SELECT r.id_lista, Seguridad.fn_CifrarTexto(st.nombre), Seguridad.fn_CifrarTexto(st.apellido),
               Seguridad.fn_CifrarFecha(st.fecha_nacimiento), st.club_origen, st.posicion, st.dorsal,
               r.fecha_presentacion, 'Importación'
        FROM #staging_jugadores AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO'
        ORDER BY r.id_lista, st.dorsal;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 16_SP_Importacion.sql. Cambio: reconoce a las personas ya cargadas sobre Seguridad.vw_PersonaCuerpoTecnico
-- (selección, apellido y nombre) y compara su fecha de nacimiento descifrada; cifra lo que carga.
/*
  usp_ImportarCuerpoTecnico
  Upsert de las personas del cuerpo técnico de las selecciones por
  selección, apellido y nombre, desde #staging_cuerpo_tecnico. Columnas que
  usa: id_registro (distinto en cada fila), codigo_fifa (de la selección),
  nombre, apellido, rol, fecha_nacimiento, codigo_fifa_nacimiento (del país
  de nacimiento), errores y accion. Los directores técnicos los importa
  usp_ImportarCuerpoTecnicoCSV (24) del scraping de Wikipedia; el resto del
  cuerpo técnico lo carga 32_Ejecutar_DatosComplementarios.sql. En una persona
  existente, la fecha y el país de nacimiento que no vienen no se borran.
  Valida cada persona pendiente: selección registrada; nombre y apellido
  obligatorios y de hasta 60 caracteres; rol DIRECTOR_TECNICO,
  AYUDANTE_CAMPO, PREPARADOR_FISICO, ENTRENADOR_ARQUEROS, MEDICO u OTRO;
  fecha de nacimiento no futura; país de nacimiento registrado; que no venga
  dos veces. Y con las válidas, cada cuerpo técnico como quedaría (las
  personas registradas que no vienen, más las que vienen): un solo director
  técnico por selección; los directores técnicos que lo rompen se rechazan.
  Con eso cubre las reglas de usp_PERSONA_CUERPO_TECNICO_Alta y
  _Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarCuerpoTecnico
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- La selección, el país de nacimiento y la persona ya registrada de cada fila pendiente.
    DECLARE @registradas TABLE (
        id_registro         INT PRIMARY KEY,
        id_seleccion        INT,
        id_pais_nacimiento  SMALLINT,
        id_persona_ct       INT
    );

    IF OBJECT_ID(N'tempdb..#staging_cuerpo_tecnico') IS NULL
        THROW 50001, N'Torneo.usp_ImportarCuerpoTecnico: no se importó nada, falta la tabla #staging_cuerpo_tecnico con el cuerpo técnico.', 1;

    UPDATE #staging_cuerpo_tecnico
    SET codigo_fifa            = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre                 = NULLIF(TRIM(nombre), N''),
        apellido               = NULLIF(TRIM(apellido), N''),
        rol                    = UPPER(NULLIF(TRIM(rol), '')),
        codigo_fifa_nacimiento = UPPER(NULLIF(TRIM(codigo_fifa_nacimiento), ''))
    WHERE accion IS NULL;

    INSERT INTO @registradas (id_registro, id_seleccion, id_pais_nacimiento, id_persona_ct)
    SELECT st.id_registro, s.id_seleccion, pn.id_pais, ct.id_persona_ct
    FROM #staging_cuerpo_tecnico AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    LEFT JOIN DatosGenerales.PAIS AS pn ON pn.codigo_fifa = st.codigo_fifa_nacimiento
    LEFT JOIN Seguridad.vw_PersonaCuerpoTecnico AS ct
           ON ct.id_seleccion = s.id_seleccion AND ct.apellido = st.apellido AND ct.nombre = st.nombre
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada persona. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL  THEN @nl + N'- El código FIFA de la selección es obligatorio.'
                 WHEN r.id_seleccion IS NULL THEN @nl + N'- No hay una selección registrada con código FIFA "'
                                                       + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @nl + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @nl + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.rol IS NULL THEN @nl + N'- El rol es obligatorio.'
                 WHEN st.rol NOT IN ('DIRECTOR_TECNICO', 'AYUDANTE_CAMPO', 'PREPARADOR_FISICO',
                                     'ENTRENADOR_ARQUEROS', 'MEDICO', 'OTRO')
                     THEN @nl + N'- El rol "' + st.rol + N'" no es DIRECTOR_TECNICO, AYUDANTE_CAMPO, '
                              + N'PREPARADOR_FISICO, ENTRENADOR_ARQUEROS, MEDICO ni OTRO.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @nl + N'- La fecha de nacimiento no puede ser futura.', NULL),
            IIF(st.codigo_fifa_nacimiento IS NOT NULL AND r.id_pais_nacimiento IS NULL,
                @nl + N'- No hay un país registrado con código FIFA "' + st.codigo_fifa_nacimiento
                    + N'" (país de nacimiento).', NULL)), N'')
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Esta persona viene ', r.veces, N' veces para la selección.')
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_cuerpo_tecnico
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido
    WHERE st.accion IS NULL;

    /* 2. Cada cuerpo técnico como quedaría con las personas válidas: un solo director técnico
          por selección. Se rechazan los directores técnicos que vienen para una selección que
          quedaría con más de uno. */
    WITH validas AS (
        SELECT st.id_registro, r.id_seleccion, r.id_persona_ct, st.rol
        FROM #staging_cuerpo_tecnico AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL
    ),
    directores AS (
        SELECT e.id_seleccion, COUNT(*) AS cantidad
        FROM (SELECT id_seleccion, rol FROM validas
              UNION ALL
              SELECT ct.id_seleccion, ct.rol
              FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
              WHERE ct.id_seleccion IN (SELECT id_seleccion FROM validas)
                AND NOT EXISTS (SELECT 1 FROM validas AS v WHERE v.id_persona_ct = ct.id_persona_ct)) AS e
        WHERE e.rol = 'DIRECTOR_TECNICO'
        GROUP BY e.id_seleccion
        HAVING COUNT(*) > 1
    )
    UPDATE st
    SET errores = CONCAT(@nl, N'- La selección quedaría con ', d.cantidad, N' directores técnicos: puede tener uno solo.')
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN validas AS v ON v.id_registro = st.id_registro
    INNER JOIN directores AS d ON d.id_seleccion = v.id_seleccion
    WHERE v.rol = 'DIRECTOR_TECNICO';

    UPDATE #staging_cuerpo_tecnico SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 3. Lo que le pasa a cada persona válida, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_persona_ct IS NULL THEN 'INSERTADO'
                      WHEN st.rol <> ct.rol
                        OR st.fecha_nacimiento <> ISNULL(ct.fecha_nacimiento, '19000101')
                        OR r.id_pais_nacimiento <> ISNULL(ct.id_pais_nacimiento, 0)
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
    LEFT JOIN Seguridad.vw_PersonaCuerpoTecnico AS ct ON ct.id_persona_ct = r.id_persona_ct
    WHERE st.accion IS NULL;

    /* 4. Carga, todos juntos. Los cambios de rol van antes que las altas: el director técnico
          nuevo de una selección puede reemplazar al que pasa a otro rol. */
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        -- La fecha que no viene conserva la guardada (ya cifrada); la que viene se cifra.
        UPDATE ct
        SET rol                = st.rol,
            fecha_nacimiento   = IIF(st.fecha_nacimiento IS NULL, ct.fecha_nacimiento, Seguridad.fn_CifrarFecha(st.fecha_nacimiento)),
            id_pais_nacimiento = ISNULL(r.id_pais_nacimiento, ct.id_pais_nacimiento)
        FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
        INNER JOIN @registradas AS r ON r.id_persona_ct = ct.id_persona_ct
        INNER JOIN #staging_cuerpo_tecnico AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.PERSONA_CUERPO_TECNICO
            (id_seleccion, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, rol)
        SELECT r.id_seleccion, r.id_pais_nacimiento, Seguridad.fn_CifrarTexto(st.nombre), Seguridad.fn_CifrarTexto(st.apellido),
               Seguridad.fn_CifrarFecha(st.fecha_nacimiento), st.rol
        FROM #staging_cuerpo_tecnico AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO'
        ORDER BY st.id_registro;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 16_SP_Importacion.sql. Cambio: reconoce al jugador que sale y al que entra sobre Seguridad.vw_Jugador; cifra el
-- jugador que agrega.
/*
  usp_ImportarReemplazos
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
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarReemplazos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

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
        THROW 50001, N'Torneo.usp_ImportarReemplazos: no se importó nada, falta la tabla #staging_reemplazos con los reemplazos.', 1;

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
    LEFT JOIN Seguridad.vw_Jugador AS e
           ON e.id_lista = l.id_lista AND e.nombre = st.nombre_entra AND e.apellido = st.apellido_entra
    LEFT JOIN Seguridad.vw_Jugador AS s
           ON s.id_lista = l.id_lista AND s.nombre = st.nombre_sale AND s.apellido = st.apellido_sale
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada reemplazo. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- La selección es obligatoria.'
                 WHEN r.id_lista IS NULL     THEN @nl + N'- No hay una selección con lista de convocados con código '
                                                     + st.codigo_fifa + N'.'
            END,
            IIF(st.nombre_sale IS NULL OR st.apellido_sale IS NULL,
                @nl + N'- El nombre y el apellido del jugador que sale son obligatorios.', NULL),
            IIF(st.nombre_entra IS NULL OR st.apellido_entra IS NULL,
                @nl + N'- El nombre y el apellido del reemplazante son obligatorios.', NULL),
            IIF(LEN(st.nombre_sale) > 60 OR LEN(st.apellido_sale) > 60,
                @nl + N'- El nombre y el apellido del jugador que sale no pueden superar los 60 caracteres.', NULL),
            IIF(st.fecha_baja IS NULL OR st.fecha_alta IS NULL, @nl + N'- Las fechas de la baja y del alta son obligatorias.', NULL),
            IIF(st.motivo_baja IS NULL OR st.motivo_alta IS NULL, @nl + N'- Los motivos de la baja y del alta son obligatorios.', NULL),
            IIF(LEN(st.motivo_baja) > 200 OR LEN(st.motivo_alta) > 200,
                @nl + N'- Los motivos no pueden superar los 200 caracteres.', NULL),
            IIF(st.fecha_baja < r.fecha_presentacion,
                @nl + N'- La baja no puede ser anterior a la presentación de la lista ('
                    + CONVERT(NVARCHAR(10), r.fecha_presentacion, 23) + N').', NULL),
            IIF(st.fecha_alta < st.fecha_baja, @nl + N'- El alta del reemplazante no puede ser anterior a la baja.', NULL),
            CASE WHEN r.id_lista IS NOT NULL AND st.nombre_entra IS NOT NULL AND r.id_entra IS NULL
                     THEN @nl + N'- ' + st.nombre_entra + N' ' + ISNULL(st.apellido_entra, N'') + N' no está en la lista.'
                 WHEN r.entra_activo = 0
                     THEN @nl + N'- ' + st.nombre_entra + N' ' + st.apellido_entra + N' está dado de baja en la lista.'
            END,
            IIF(r.sale_activo = 1,
                @nl + N'- ' + st.nombre_sale + N' ' + st.apellido_sale
                    + N' está activo en la lista: esa baja se hace con usp_ReemplazarJugador.', NULL),
            IIF(r.id_sale = r.id_entra, @nl + N'- El jugador que sale y el reemplazante son la misma persona.', NULL),
            IIF(st.fecha_alta > r.primer_partido AND r.entra_posicion <> 'ARQUERO',
                @nl + N'- La selección ya jugó su primer partido: solo se puede reemplazar a un arquero por otro arquero.',
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
    SET errores = @nl + N'- El jugador que sale o el reemplazante viene en más de un reemplazo.'
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
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_alta, motivo_alta,
                                    fecha_baja, motivo_baja)
        SELECT r.id_lista, Seguridad.fn_CifrarTexto(st.nombre_sale), Seguridad.fn_CifrarTexto(st.apellido_sale),
               r.entra_posicion, r.entra_dorsal, r.fecha_presentacion,
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

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 23_SP_Importar_Mundial2026.sql. Cambio: toma los candidatos de Seguridad.vw_Jugador.
/*
  usp_IdentificarJugadores
  Reconoce a los jugadores que nombra un archivo. Trabaja sobre la tabla
  temporal #nombres_fuente que crea quien lo llama (codigo_fifa, nombre_fuente,
  id_jugador, paso, error): completa id_jugador con el jugador de esa
  selección que corresponde a nombre_fuente, o error con el motivo.
  El nombre de la fuente se separa en nombre y apellido: las palabras en
  mayúsculas son el apellido ("Julian QUINONES"); si está todo en mayúsculas,
  la primera palabra es el nombre ("MOUSA ALTAMARI"). Se prueba por pasos, en
  orden, entre los jugadores de la lista de esa selección (activos o no), y
  vale el primer paso que encuentra a alguien:
    0. Un nombre alternativo registrado para el jugador (NOMBRE_ALTERNATIVO).
    1. Nombre completo igual, en cualquier orden (Torneo.fn_ClaveNombre, sin
       distinguir tildes).
    2. Mismo apellido y primer nombre parecido (mismas tres primeras letras, o
       uno empieza con el otro): Maxi / Maximiliano.
    3. Mismo primer nombre y apellido parecido (uno empieza con el otro, o
       suenan igual según SOUNDEX): Zico / Ziko.
    4. Primer nombre y apellido que suenan igual (SOUNDEX): Mousa Altamari /
       Musa Al-Taamari.
    5. Jugadores conocidos por un solo nombre (nombre igual al apellido en la
       lista): Neymar, Casemiro.
  Si en ese paso hay más de un jugador posible, no se elige ninguno: el
  nombre se rechaza como ambiguo. Si ningún paso encuentra a nadie, el error
  sugiere hasta tres jugadores de apellido parecido. En los dos casos se
  resuelve registrando el nombre alternativo del jugador.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_IdentificarJugadores
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #partes (
        id_nombre       INT PRIMARY KEY,
        nombre          NVARCHAR(200) COLLATE DATABASE_DEFAULT,
        apellido        NVARCHAR(200) COLLATE DATABASE_DEFAULT,
        clave_completa  NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_nombre    NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_apellido  NVARCHAR(400) COLLATE DATABASE_DEFAULT
    );

    CREATE TABLE #candidatos (
        id_jugador      INT PRIMARY KEY,
        codigo_fifa     VARCHAR(10)   COLLATE DATABASE_DEFAULT,
        id_seleccion    INT,
        nombre          NVARCHAR(60)  COLLATE DATABASE_DEFAULT,
        apellido        NVARCHAR(60)  COLLATE DATABASE_DEFAULT,
        clave_completa  NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_inversa   NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_nombre    NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_apellido  NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        un_nombre       BIT
    );

    CREATE TABLE #coincidencias (id_nombre INT, paso TINYINT, id_jugador INT);

    -- Nombre y apellido según las mayúsculas.
    WITH palabras AS (
        SELECT n.id_nombre, w.ordinal, w.value AS palabra,
               IIF(w.value COLLATE Latin1_General_CS_AS = UPPER(w.value) AND LEN(w.value) > 1, 1, 0) AS mayuscula,
               COUNT(*) OVER (PARTITION BY n.id_nombre) AS palabras,
               SUM(IIF(w.value COLLATE Latin1_General_CS_AS = UPPER(w.value) AND LEN(w.value) > 1, 0, 1))
                   OVER (PARTITION BY n.id_nombre) AS minusculas
        FROM #nombres_fuente AS n
        CROSS APPLY STRING_SPLIT(TRIM(n.nombre_fuente), N' ', 1) AS w
        WHERE w.value <> N''
    ),
    partes AS (
        SELECT id_nombre,
               STRING_AGG(IIF(minusculas > 0, IIF(mayuscula = 0, palabra, NULL), IIF(ordinal = 1, palabra, NULL)), N' ')
                   WITHIN GROUP (ORDER BY ordinal) AS nombre,
               STRING_AGG(IIF(minusculas > 0, IIF(mayuscula = 1, palabra, NULL),
                              IIF(ordinal > 1 OR palabras = 1, palabra, NULL)), N' ')
                   WITHIN GROUP (ORDER BY ordinal) AS apellido
        FROM palabras
        GROUP BY id_nombre
    )
    INSERT INTO #partes (id_nombre, nombre, apellido)
    SELECT id_nombre, nombre, apellido FROM partes;

    UPDATE p
    SET clave_completa = Torneo.fn_ClaveNombre(n.nombre_fuente),
        clave_nombre   = Torneo.fn_ClaveNombre(LEFT(p.nombre, CHARINDEX(N' ', p.nombre + N' ') - 1)),
        clave_apellido = Torneo.fn_ClaveNombre(p.apellido)
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre;

    INSERT INTO #candidatos (id_jugador, codigo_fifa, id_seleccion, nombre, apellido, un_nombre)
    SELECT j.id_jugador, pa.codigo_fifa, s.id_seleccion, j.nombre, j.apellido, IIF(j.nombre = j.apellido, 1, 0)
    FROM Seguridad.vw_Jugador AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa IN (SELECT codigo_fifa FROM #nombres_fuente);

    UPDATE #candidatos
    SET clave_completa = Torneo.fn_ClaveNombre(nombre + apellido),
        clave_inversa  = Torneo.fn_ClaveNombre(apellido + nombre),
        clave_nombre   = Torneo.fn_ClaveNombre(LEFT(nombre, CHARINDEX(N' ', nombre + N' ') - 1)),
        clave_apellido = Torneo.fn_ClaveNombre(apellido);

    -- 0. Nombre alternativo registrado.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT n.id_nombre, 0, c.id_jugador
    FROM #nombres_fuente AS n
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    INNER JOIN Torneo.NOMBRE_ALTERNATIVO AS na ON na.id_jugador = c.id_jugador
    WHERE na.nombre COLLATE Latin1_General_CI_AI = n.nombre_fuente COLLATE Latin1_General_CI_AI;

    -- 1. Nombre completo, en cualquier orden.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 1, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.clave_completa COLLATE Latin1_General_CI_AI IN (c.clave_completa COLLATE Latin1_General_CI_AI,
                                                             c.clave_inversa COLLATE Latin1_General_CI_AI);

    -- 2. Mismo apellido y primer nombre parecido.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 2, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.nombre IS NOT NULL AND p.apellido IS NOT NULL AND p.nombre <> p.apellido
      AND p.clave_apellido COLLATE Latin1_General_CI_AI = c.clave_apellido COLLATE Latin1_General_CI_AI
      AND (LEFT(p.clave_nombre, 3) COLLATE Latin1_General_CI_AI = LEFT(c.clave_nombre, 3) COLLATE Latin1_General_CI_AI
           OR p.clave_nombre COLLATE Latin1_General_CI_AI LIKE c.clave_nombre + N'%' COLLATE Latin1_General_CI_AI
           OR c.clave_nombre COLLATE Latin1_General_CI_AI LIKE p.clave_nombre + N'%' COLLATE Latin1_General_CI_AI);

    -- 3. Mismo primer nombre y apellido parecido.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 3, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.nombre IS NOT NULL AND p.apellido IS NOT NULL AND p.nombre <> p.apellido
      AND p.clave_nombre COLLATE Latin1_General_CI_AI = c.clave_nombre COLLATE Latin1_General_CI_AI
      AND (p.clave_apellido COLLATE Latin1_General_CI_AI LIKE c.clave_apellido + N'%' COLLATE Latin1_General_CI_AI
           OR c.clave_apellido COLLATE Latin1_General_CI_AI LIKE p.clave_apellido + N'%' COLLATE Latin1_General_CI_AI
           OR SOUNDEX(p.clave_apellido) = SOUNDEX(c.clave_apellido));

    -- 4. Primer nombre y apellido que suenan igual.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 4, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.nombre IS NOT NULL AND p.apellido IS NOT NULL AND p.nombre <> p.apellido
      AND SOUNDEX(p.clave_nombre) = SOUNDEX(c.clave_nombre)
      AND SOUNDEX(p.clave_apellido) = SOUNDEX(c.clave_apellido);

    -- 5. Jugadores de un solo nombre: alguna palabra de la fuente es ese nombre.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT DISTINCT n.id_nombre, 5, c.id_jugador
    FROM #nombres_fuente AS n
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa AND c.un_nombre = 1
    CROSS APPLY STRING_SPLIT(TRIM(n.nombre_fuente), N' ') AS w
    WHERE Torneo.fn_ClaveNombre(w.value) COLLATE Latin1_General_CI_AI = c.clave_nombre COLLATE Latin1_General_CI_AI;

    -- Vale el primer paso con coincidencias: con un solo jugador, es ese; con más, es ambiguo.
    WITH primer_paso AS (
        SELECT id_nombre, MIN(paso) AS paso FROM #coincidencias GROUP BY id_nombre
    ),
    resultado AS (
        SELECT c.id_nombre, c.paso, COUNT(DISTINCT c.id_jugador) AS jugadores, MIN(c.id_jugador) AS id_jugador
        FROM #coincidencias AS c
        INNER JOIN primer_paso AS pp ON pp.id_nombre = c.id_nombre AND pp.paso = c.paso
        GROUP BY c.id_nombre, c.paso
    )
    UPDATE n
    SET id_jugador = IIF(r.jugadores = 1, r.id_jugador, NULL),
        paso       = r.paso,
        error      = IIF(r.jugadores = 1, NULL,
                         CONCAT(N'"', n.nombre_fuente, N'" puede ser ', r.jugadores, N' jugadores de la lista de ',
                                n.codigo_fifa, N': ',
                                (SELECT STRING_AGG(CONCAT(c.nombre, N' ', c.apellido), N', ')
                                 FROM (SELECT DISTINCT id_jugador FROM #coincidencias AS x
                                       WHERE x.id_nombre = r.id_nombre AND x.paso = r.paso) AS x
                                 INNER JOIN #candidatos AS c ON c.id_jugador = x.id_jugador),
                                N'. Hay que registrar el nombre alternativo del que corresponde.'))
    FROM #nombres_fuente AS n
    INNER JOIN resultado AS r ON r.id_nombre = n.id_nombre;

    UPDATE n
    SET error = CONCAT(N'"', n.nombre_fuente, N'" no coincide con ningún jugador de la lista de ', n.codigo_fifa,
                       ISNULL(N'. Parecidos: ' + (SELECT STRING_AGG(CONCAT(c.nombre, N' ', c.apellido), N', ')
                                                  FROM (SELECT TOP (3) c.nombre, c.apellido
                                                        FROM #candidatos AS c
                                                        WHERE c.codigo_fifa = n.codigo_fifa
                                                          AND DIFFERENCE(c.clave_apellido, p.clave_apellido) >= 3
                                                        ORDER BY DIFFERENCE(c.clave_apellido, p.clave_apellido) DESC,
                                                                 DIFFERENCE(c.clave_nombre, p.clave_nombre) DESC) AS c), N''),
                       N'. Si es uno de ellos, hay que registrar su nombre alternativo.')
    FROM #nombres_fuente AS n
    LEFT JOIN #partes AS p ON p.id_nombre = n.id_nombre
    WHERE n.paso IS NULL;
END;
GO
