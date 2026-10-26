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
 Archivo: 07_SP_ABM_Arbitraje.sql
 Objetivo: Crear los stored procedures de alta, baja y modificación de las
           tablas del esquema Arbitraje: ARBITRO, ARBITRO_IDIOMA y
           DESIGNACION_ARBITRAL. Siguen las convenciones descriptas en
           04_SP_ABM_DatosGenerales.sql. Requiere haber ejecutado 00 a 06.
           Su script de testing es 57_Test_SP_ABM_Arbitraje.sql.
================================================================================

 Particularidades de este esquema:
   - ARBITRO: la baja es lógica (activo = 0), porque el árbitro conserva su
     historial. Con @eliminar_registro = 1 se borra el registro, solo si no
     tiene idiomas ni designaciones.
   - ARBITRO_IDIOMA solo tiene alta y baja: sus dos columnas son la clave.
   - DESIGNACION_ARBITRAL: el conflicto de nacionalidad se valida acá, para
     que no haya forma de designar a un árbitro del país de una de las
     selecciones. La designación completa (los cinco roles juntos) y la
     advertencia por posible cruce desde dieciseisavos están en
     Arbitraje.usp_DesignarTernaArbitral (14_SP_Negocio_Arbitraje.sql).
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   ARBITRO
   ============================================================================ */

/*
  usp_ARBITRO_Alta
  Valida: país existente; nombre y apellido obligatorios, de hasta 60
  caracteres, y que no haya otro árbitro con el mismo nombre del mismo país;
  categoría FIFA o CONFEDERACION; fecha de nacimiento no futura.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_Alta
    @id_pais           SMALLINT,
    @nombre            NVARCHAR(120),
    @apellido          NVARCHAR(120),
    @categoria         VARCHAR(30),
    @fecha_nacimiento  DATE = NULL,
    @id_arbitro        INT  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre    = NULLIF(TRIM(@nombre), N'');
    SET @apellido  = NULLIF(TRIM(@apellido), N'');
    SET @categoria = UPPER(NULLIF(TRIM(@categoria), ''));

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';

    IF @apellido IS NULL
        SET @errores += @nl + N'- El apellido es obligatorio.';
    ELSE IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';

    IF EXISTS (SELECT 1 FROM Arbitraje.ARBITRO
               WHERE id_pais = @id_pais AND apellido = @apellido AND nombre = @nombre)
        SET @errores += @nl + N'- Ya hay un árbitro ' + @nombre + N' ' + @apellido + N' de ese país.';

    IF @categoria IS NULL
        SET @errores += @nl + N'- La categoría es obligatoria.';
    ELSE IF @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @nl + N'- La categoría debe ser FIFA o CONFEDERACION.';

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_Alta: no se pudo dar de alta el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, fecha_nacimiento, categoria)
    VALUES (@id_pais, @nombre, @apellido, @fecha_nacimiento, @categoria);

    SET @id_arbitro = SCOPE_IDENTITY();
END;
GO


/*
  usp_ARBITRO_Modificacion
  Valida: que el árbitro exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta; que con el país nuevo no quede
  designado en un partido de una selección de ese país; que no se desactive a
  un árbitro designado en un partido que todavía no se jugó.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_Modificacion
    @id_arbitro        INT,
    @id_pais           SMALLINT      = NULL,
    @nombre            NVARCHAR(120) = NULL,
    @apellido          NVARCHAR(120) = NULL,
    @categoria         VARCHAR(30)   = NULL,
    @fecha_nacimiento  DATE          = NULL,
    @activo            BIT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @pais_final     SMALLINT;
    DECLARE @nombre_final   NVARCHAR(60);
    DECLARE @apellido_final NVARCHAR(60);
    DECLARE @partido        TINYINT;

    SET @nombre    = NULLIF(TRIM(@nombre), N'');
    SET @apellido  = NULLIF(TRIM(@apellido), N'');
    SET @categoria = UPPER(NULLIF(TRIM(@categoria), ''));

    SELECT @pais_final     = ISNULL(@id_pais, id_pais),
           @nombre_final   = ISNULL(@nombre, nombre),
           @apellido_final = ISNULL(@apellido, apellido)
    FROM Arbitraje.ARBITRO
    WHERE id_arbitro = @id_arbitro;

    IF @id_arbitro IS NULL
        SET @errores += @nl + N'- El id del árbitro es obligatorio.';
    ELSE IF @pais_final IS NULL
        SET @errores += @nl + N'- No existe un árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';

    IF @id_pais IS NULL AND @nombre IS NULL AND @apellido IS NULL AND @categoria IS NULL
       AND @fecha_nacimiento IS NULL AND @activo IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @id_pais IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';
    ELSE IF @id_pais IS NOT NULL
    BEGIN
        SELECT TOP (1) @partido = p.numero_partido
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
        WHERE d.id_arbitro = @id_arbitro AND s.id_pais = @id_pais;
        IF @partido IS NOT NULL
            SET @errores += @nl + N'- Con ese país quedaría en conflicto de nacionalidad en el partido '
                          + CAST(@partido AS NVARCHAR(3)) + N', que tiene designado.';
    END;

    IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';
    IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';
    IF (@id_pais IS NOT NULL OR @nombre IS NOT NULL OR @apellido IS NOT NULL)
       AND EXISTS (SELECT 1 FROM Arbitraje.ARBITRO
                   WHERE id_pais = @pais_final AND apellido = @apellido_final AND nombre = @nombre_final
                     AND id_arbitro <> @id_arbitro)
        SET @errores += @nl + N'- Ya hay otro árbitro ' + @nombre_final + N' ' + @apellido_final + N' de ese país.';

    IF @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @nl + N'- La categoría debe ser FIFA o CONFEDERACION.';

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF @activo = 0
       AND EXISTS (SELECT 1
                   FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                   INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                   WHERE d.id_arbitro = @id_arbitro AND p.estado IN ('PROGRAMADO', 'EN_JUEGO'))
        SET @errores += @nl + N'- El árbitro está designado en un partido que todavía no se jugó: no se puede desactivar.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_Modificacion: no se pudo modificar el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Arbitraje.ARBITRO
    SET id_pais          = ISNULL(@id_pais, id_pais),
        nombre           = ISNULL(@nombre, nombre),
        apellido         = ISNULL(@apellido, apellido),
        categoria        = ISNULL(@categoria, categoria),
        fecha_nacimiento = ISNULL(@fecha_nacimiento, fecha_nacimiento),
        activo           = ISNULL(@activo, activo)
    WHERE id_arbitro = @id_arbitro;
END;
GO


/*
  usp_ARBITRO_Baja
  Baja lógica (por defecto): deja al árbitro inactivo. Valida que exista, que
  esté activo y que no esté designado en un partido que todavía no se jugó.
  Con @eliminar_registro = 1 borra el registro: valida que no tenga idiomas
  ni designaciones.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_Baja
    @id_arbitro         INT,
    @eliminar_registro  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @activo  BIT;

    SELECT @activo = activo FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;

    IF @id_arbitro IS NULL
        SET @errores += @nl + N'- El id del árbitro es obligatorio.';
    ELSE IF @activo IS NULL
        SET @errores += @nl + N'- No existe un árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';
    ELSE IF ISNULL(@eliminar_registro, 0) = 0
    BEGIN
        IF @activo = 0
            SET @errores += @nl + N'- El árbitro ya está inactivo.';
        IF EXISTS (SELECT 1
                   FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                   INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                   WHERE d.id_arbitro = @id_arbitro AND p.estado IN ('PROGRAMADO', 'EN_JUEGO'))
            SET @errores += @nl + N'- El árbitro está designado en un partido que todavía no se jugó.';
    END
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- Lo referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'Arbitraje.ARBITRO_IDIOMA', COUNT(*)
                FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro
                UNION ALL
                SELECT N'Arbitraje.DESIGNACION_ARBITRAL', COUNT(*)
                FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id_arbitro
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_Baja: no se pudo dar de baja el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    IF @eliminar_registro = 1
        DELETE FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
    ELSE
        UPDATE Arbitraje.ARBITRO SET activo = 0 WHERE id_arbitro = @id_arbitro;
END;
GO


/* ============================================================================
   ARBITRO_IDIOMA
   ============================================================================ */

/*
  usp_ARBITRO_IDIOMA_Alta
  Valida: árbitro e idioma existentes, y que el árbitro no tenga ya ese idioma.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_IDIOMA_Alta
    @id_arbitro  INT,
    @id_idioma   SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_arbitro IS NULL
        SET @errores += @nl + N'- El árbitro es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro)
        SET @errores += @nl + N'- No existe un árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';

    IF @id_idioma IS NULL
        SET @errores += @nl + N'- El idioma es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE id_idioma = @id_idioma)
        SET @errores += @nl + N'- No existe un idioma con id ' + CAST(@id_idioma AS NVARCHAR(10)) + N'.';

    IF EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro AND id_idioma = @id_idioma)
        SET @errores += @nl + N'- El árbitro ya tiene registrado ese idioma.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_IDIOMA_Alta: no se pudo registrar el idioma del árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma)
    VALUES (@id_arbitro, @id_idioma);
END;
GO


/*
  usp_ARBITRO_IDIOMA_Baja
  Valida: que el árbitro tenga registrado ese idioma.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_IDIOMA_Baja
    @id_arbitro  INT,
    @id_idioma   SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_arbitro IS NULL OR @id_idioma IS NULL
        SET @errores += @nl + N'- El árbitro y el idioma son obligatorios.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro AND id_idioma = @id_idioma)
        SET @errores += @nl + N'- El árbitro no tiene registrado ese idioma.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_IDIOMA_Baja: no se pudo quitar el idioma del árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro AND id_idioma = @id_idioma;
END;
GO


/* ============================================================================
   DESIGNACION_ARBITRAL
   ============================================================================ */

/*
  usp_DESIGNACION_ARBITRAL_Alta
  Valida: partido existente y PROGRAMADO; árbitro existente y activo; rol
  válido y libre en el partido; que el árbitro no esté ya designado en el
  partido; que su país no sea el de ninguna de las dos selecciones (conflicto
  de nacionalidad); que no tenga otro partido a menos de 24 horas.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_DESIGNACION_ARBITRAL_Alta
    @id_partido  INT,
    @id_arbitro  INT,
    @rol         VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado         VARCHAR(12);
    DECLARE @utc            DATETIME2(0);
    DECLARE @local          INT;
    DECLARE @visitante      INT;
    DECLARE @activo         BIT;
    DECLARE @id_pais        SMALLINT;
    DECLARE @arbitro        NVARCHAR(130);
    DECLARE @pais_conflicto VARCHAR(60);
    DECLARE @otro_partido   TINYINT;

    SET @rol = UPPER(NULLIF(TRIM(@rol), ''));

    SELECT @estado = estado, @utc = fecha_hora_utc, @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    SELECT @activo = activo, @id_pais = id_pais, @arbitro = nombre + N' ' + apellido
    FROM Arbitraje.ARBITRO
    WHERE id_arbitro = @id_arbitro;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- Las designaciones se hacen antes de que empiece el partido (estado actual: '
                      + @estado + N').';

    IF @id_arbitro IS NULL
        SET @errores += @nl + N'- El árbitro es obligatorio.';
    ELSE IF @activo IS NULL
        SET @errores += @nl + N'- No existe un árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';
    ELSE IF @activo = 0
        SET @errores += @nl + N'- El árbitro ' + @arbitro + N' no está activo.';

    IF @rol IS NULL
        SET @errores += @nl + N'- El rol es obligatorio.';
    ELSE IF @rol NOT IN ('PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR')
        SET @errores += @nl + N'- El rol debe ser PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO o VAR.';
    ELSE IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND rol = @rol)
        SET @errores += @nl + N'- El rol ' + @rol + N' ya está cubierto en ese partido.';

    IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id_arbitro)
        SET @errores += @nl + N'- El árbitro ya está designado en ese partido.';

    IF @id_pais IS NOT NULL
    BEGIN
        SELECT TOP (1) @pais_conflicto = pa.nombre
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
        WHERE s.id_seleccion IN (@local, @visitante) AND s.id_pais = @id_pais;
        IF @pais_conflicto IS NOT NULL
            SET @errores += @nl + N'- Conflicto de nacionalidad: ' + @arbitro + N' es de ' + @pais_conflicto
                          + N', que juega este partido.';

        SELECT TOP (1) @otro_partido = p.numero_partido
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        WHERE d.id_arbitro = @id_arbitro
          AND d.id_partido <> @id_partido
          AND ABS(DATEDIFF(MINUTE, p.fecha_hora_utc, @utc)) < 1440;
        IF @otro_partido IS NOT NULL
            SET @errores += @nl + N'- ' + @arbitro + N' ya está designado en el partido '
                          + CAST(@otro_partido AS NVARCHAR(3)) + N', a menos de 24 horas.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_DESIGNACION_ARBITRAL_Alta: no se pudo designar al árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
    VALUES (@id_partido, @id_arbitro, @rol);
END;
GO


/*
  usp_DESIGNACION_ARBITRAL_Modificacion
  Valida: que la designación exista y que se informe al menos un dato; el rol
  solo se cambia con el partido PROGRAMADO y si el nuevo está libre; el
  informe y la sanción post-partido solo con el partido FINALIZADO; la
  sanción tiene hasta 500 caracteres.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion
    @id_partido           INT,
    @id_arbitro           INT,
    @rol                  VARCHAR(30)   = NULL,
    @informe_postpartido  VARCHAR(MAX)  = NULL,
    @sancion              VARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado  VARCHAR(12);

    SET @rol                 = UPPER(NULLIF(TRIM(@rol), ''));
    SET @informe_postpartido = NULLIF(TRIM(@informe_postpartido), '');
    SET @sancion             = NULLIF(TRIM(@sancion), '');

    SELECT @estado = p.estado
    FROM Arbitraje.DESIGNACION_ARBITRAL AS d
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
    WHERE d.id_partido = @id_partido AND d.id_arbitro = @id_arbitro;

    IF @id_partido IS NULL OR @id_arbitro IS NULL
        SET @errores += @nl + N'- El partido y el árbitro son obligatorios.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- El árbitro no está designado en ese partido.';

    IF @rol IS NULL AND @informe_postpartido IS NULL AND @sancion IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @rol IS NOT NULL
    BEGIN
        IF @rol NOT IN ('PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR')
            SET @errores += @nl + N'- El rol debe ser PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO o VAR.';
        ELSE IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL
                        WHERE id_partido = @id_partido AND rol = @rol AND id_arbitro <> @id_arbitro)
            SET @errores += @nl + N'- El rol ' + @rol + N' ya está cubierto en ese partido.';
        IF @estado <> 'PROGRAMADO'
            SET @errores += @nl + N'- El rol se cambia antes de que empiece el partido.';
    END;

    IF (@informe_postpartido IS NOT NULL OR @sancion IS NOT NULL) AND @estado <> 'FINALIZADO'
        SET @errores += @nl + N'- El informe y la sanción post-partido se registran con el partido FINALIZADO.';

    IF LEN(@sancion) > 500
        SET @errores += @nl + N'- La sanción no puede superar los 500 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion: no se pudo modificar la designación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Arbitraje.DESIGNACION_ARBITRAL
    SET rol                 = ISNULL(@rol, rol),
        informe_postpartido = ISNULL(@informe_postpartido, informe_postpartido),
        sancion             = ISNULL(@sancion, sancion)
    WHERE id_partido = @id_partido AND id_arbitro = @id_arbitro;
END;
GO


/*
  usp_DESIGNACION_ARBITRAL_Baja
  Valida: que la designación exista y que el partido esté PROGRAMADO (la
  designación de un partido jugado es parte del historial del árbitro).
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_DESIGNACION_ARBITRAL_Baja
    @id_partido  INT,
    @id_arbitro  INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado  VARCHAR(12);

    SELECT @estado = p.estado
    FROM Arbitraje.DESIGNACION_ARBITRAL AS d
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
    WHERE d.id_partido = @id_partido AND d.id_arbitro = @id_arbitro;

    IF @id_partido IS NULL OR @id_arbitro IS NULL
        SET @errores += @nl + N'- El partido y el árbitro son obligatorios.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- El árbitro no está designado en ese partido.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- El partido está ' + @estado + N': la designación queda en el historial del árbitro.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_DESIGNACION_ARBITRAL_Baja: no se pudo dar de baja la designación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id_arbitro;
END;
GO


-- Evidencia: SP creados en el esquema Arbitraje.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Arbitraje'
ORDER BY p.name;
GO
