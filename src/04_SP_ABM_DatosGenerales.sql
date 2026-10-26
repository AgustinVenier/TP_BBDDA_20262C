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
 Archivo: 04_SP_ABM_DatosGenerales.sql
 Objetivo: Crear los stored procedures de alta, baja y modificación de las
           tablas del esquema DatosGenerales: PAIS, IDIOMA, INDICADOR_ECONOMICO
           y PARAMETRO_REGLAMENTO. Requiere haber ejecutado 00 a 03.
           Su script de testing es 54_Test_SP_ABM_DatosGenerales.sql.
================================================================================

 Convenciones de los SP de ABM (las siguen los scripts 04 a 08):
   - Un SP por tabla y operación: usp_<TABLA>_Alta, usp_<TABLA>_Modificacion
     y usp_<TABLA>_Baja.
   - Las validaciones no se cortan en la primera falla: cada condición que no
     se cumple se agrega a @errores y al final se lanza un único THROW 50001
     con el SP, la operación y todas las condiciones incumplidas.
   - Los parámetros tienen el mismo tipo que su columna. Los de texto se
     declaran más largos, para poder avisar que el valor es demasiado largo en
     vez de que SQL Server lo trunque sin avisar.
   - Los textos se guardan sin espacios al principio ni al final, y un texto
     vacío cuenta como no informado.
   - En las modificaciones, un parámetro en NULL conserva el valor actual.
   - El alta devuelve el id generado en un parámetro OUTPUT.
   - Una baja se rechaza mientras otra tabla haga referencia al registro, y
     el mensaje informa todas las tablas que todavía lo usan.
*/

USE MundialFutbol;
GO

-- Los SP guardan estas dos opciones al crearse. QUOTED_IDENTIFIER ON es
-- obligatorio para modificar tablas con índices filtrados, como PAIS.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   PAIS
   ============================================================================ */

/*
  usp_PAIS_Alta
  Valida: nombre obligatorio, de hasta 60 caracteres y no repetido; huso
  horario obligatorio y existente en sys.time_zone_info; códigos FIFA, ISO
  alfa-2, ISO alfa-3 y de moneda con su formato, y código FIFA no repetido.
  Los códigos se guardan en mayúsculas y el huso con el nombre exacto que
  tiene en sys.time_zone_info.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_PAIS_Alta
    @nombre         VARCHAR(100),
    @huso_horario   VARCHAR(100),
    @codigo_fifa    VARCHAR(10) = NULL,
    @codigo_iso2    VARCHAR(10) = NULL,
    @codigo_iso3    VARCHAR(10) = NULL,
    @codigo_moneda  VARCHAR(10) = NULL,
    @id_pais        SMALLINT    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre        = NULLIF(TRIM(@nombre), '');
    SET @huso_horario  = NULLIF(TRIM(@huso_horario), '');
    SET @codigo_fifa   = UPPER(NULLIF(TRIM(@codigo_fifa), ''));
    SET @codigo_iso2   = UPPER(NULLIF(TRIM(@codigo_iso2), ''));
    SET @codigo_iso3   = UPPER(NULLIF(TRIM(@codigo_iso3), ''));
    SET @codigo_moneda = UPPER(NULLIF(TRIM(@codigo_moneda), ''));

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE nombre = @nombre)
        SET @errores += @nl + N'- Ya existe un país llamado "' + @nombre + N'".';

    IF @huso_horario IS NULL
        SET @errores += @nl + N'- El huso horario es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @huso_horario)
        SET @errores += @nl + N'- El huso horario "' + @huso_horario
                      + N'" no existe en sys.time_zone_info (ej. "Argentina Standard Time").';

    -- Con la intercalación binaria, [A-Z] acepta solo letras sin acentos.
    IF @codigo_fifa COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código FIFA debe tener 3 letras.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa = @codigo_fifa)
        SET @errores += @nl + N'- El código FIFA "' + @codigo_fifa + N'" ya lo tiene otro país.';

    IF @codigo_iso2 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z]'
        SET @errores += @nl + N'- El código ISO alfa-2 debe tener 2 letras.';

    IF @codigo_iso3 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código ISO alfa-3 debe tener 3 letras.';

    IF @codigo_moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código de moneda debe tener 3 letras (ISO 4217).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_PAIS_Alta: no se pudo dar de alta el país.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @huso_horario = name FROM sys.time_zone_info WHERE name = @huso_horario;

    INSERT INTO DatosGenerales.PAIS
        (nombre, codigo_fifa, codigo_iso2, codigo_iso3, huso_horario, codigo_moneda)
    VALUES
        (@nombre, @codigo_fifa, @codigo_iso2, @codigo_iso3, @huso_horario, @codigo_moneda);

    SET @id_pais = SCOPE_IDENTITY();
END;
GO


/*
  usp_PAIS_Modificacion
  Valida: que el país exista y que se informe al menos un dato; para cada dato
  informado, las mismas reglas del alta (sin contar al propio país en los
  controles de repetidos). Si cambia el huso, cambia la hora local que ven
  los mercados de ese país (prime time), no la de los partidos, que depende
  del huso de cada sede.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_PAIS_Modificacion
    @id_pais        SMALLINT,
    @nombre         VARCHAR(100) = NULL,
    @huso_horario   VARCHAR(100) = NULL,
    @codigo_fifa    VARCHAR(10)  = NULL,
    @codigo_iso2    VARCHAR(10)  = NULL,
    @codigo_iso3    VARCHAR(10)  = NULL,
    @codigo_moneda  VARCHAR(10)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre        = NULLIF(TRIM(@nombre), '');
    SET @huso_horario  = NULLIF(TRIM(@huso_horario), '');
    SET @codigo_fifa   = UPPER(NULLIF(TRIM(@codigo_fifa), ''));
    SET @codigo_iso2   = UPPER(NULLIF(TRIM(@codigo_iso2), ''));
    SET @codigo_iso3   = UPPER(NULLIF(TRIM(@codigo_iso3), ''));
    SET @codigo_moneda = UPPER(NULLIF(TRIM(@codigo_moneda), ''));

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El id del país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF COALESCE(@nombre, @huso_horario, @codigo_fifa, @codigo_iso2, @codigo_iso3, @codigo_moneda) IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE nombre = @nombre AND id_pais <> @id_pais)
        SET @errores += @nl + N'- Ya existe otro país llamado "' + @nombre + N'".';

    IF @huso_horario IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @huso_horario)
        SET @errores += @nl + N'- El huso horario "' + @huso_horario
                      + N'" no existe en sys.time_zone_info (ej. "Argentina Standard Time").';

    IF @codigo_fifa COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código FIFA debe tener 3 letras.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.PAIS
                    WHERE codigo_fifa = @codigo_fifa AND id_pais <> @id_pais)
        SET @errores += @nl + N'- El código FIFA "' + @codigo_fifa + N'" ya lo tiene otro país.';

    IF @codigo_iso2 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z]'
        SET @errores += @nl + N'- El código ISO alfa-2 debe tener 2 letras.';

    IF @codigo_iso3 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código ISO alfa-3 debe tener 3 letras.';

    IF @codigo_moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código de moneda debe tener 3 letras (ISO 4217).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_PAIS_Modificacion: no se pudo modificar el país.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Si no se informó huso, la consulta no encuentra filas y queda en NULL.
    SELECT @huso_horario = name FROM sys.time_zone_info WHERE name = @huso_horario;

    UPDATE DatosGenerales.PAIS
    SET nombre        = ISNULL(@nombre, nombre),
        huso_horario  = ISNULL(@huso_horario, huso_horario),
        codigo_fifa   = ISNULL(@codigo_fifa, codigo_fifa),
        codigo_iso2   = ISNULL(@codigo_iso2, codigo_iso2),
        codigo_iso3   = ISNULL(@codigo_iso3, codigo_iso3),
        codigo_moneda = ISNULL(@codigo_moneda, codigo_moneda)
    WHERE id_pais = @id_pais;
END;
GO


/*
  usp_PAIS_Baja
  Valida: que el país exista y que ninguna tabla lo referencie. Informa en el
  mismo mensaje todas las tablas que todavía lo usan.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_PAIS_Baja
    @id_pais SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El id del país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- Lo referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'Torneo.SEDE', COUNT(*)
                FROM Torneo.SEDE WHERE id_pais = @id_pais
                UNION ALL
                SELECT N'Torneo.SELECCION', COUNT(*)
                FROM Torneo.SELECCION WHERE id_pais = @id_pais
                UNION ALL
                SELECT N'Torneo.JUGADOR', COUNT(*)
                FROM Torneo.JUGADOR WHERE id_pais_nacimiento = @id_pais
                UNION ALL
                SELECT N'Torneo.PERSONA_CUERPO_TECNICO', COUNT(*)
                FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_pais_nacimiento = @id_pais
                UNION ALL
                SELECT N'Arbitraje.ARBITRO', COUNT(*)
                FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais
                UNION ALL
                SELECT N'Publicidad.ANUNCIANTE', COUNT(*)
                FROM Publicidad.ANUNCIANTE WHERE id_pais = @id_pais
                UNION ALL
                SELECT N'Publicidad.PIEZA_PAIS_INTERES', COUNT(*)
                FROM Publicidad.PIEZA_PAIS_INTERES WHERE id_pais = @id_pais
                UNION ALL
                SELECT N'DatosGenerales.INDICADOR_ECONOMICO', COUNT(*)
                FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_pais = @id_pais
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_PAIS_Baja: no se pudo dar de baja el país.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DatosGenerales.PAIS WHERE id_pais = @id_pais;
END;
GO


/* ============================================================================
   IDIOMA
   ============================================================================ */

/*
  usp_IDIOMA_Alta
  Valida: nombre obligatorio, de hasta 40 caracteres y no repetido; código
  ISO 639-1 opcional, de 2 letras y no repetido. El código se guarda en
  minúsculas.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_IDIOMA_Alta
    @nombre      VARCHAR(100),
    @codigo_iso  VARCHAR(10) = NULL,
    @id_idioma   SMALLINT    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre     = NULLIF(TRIM(@nombre), '');
    SET @codigo_iso = LOWER(NULLIF(TRIM(@codigo_iso), ''));

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 40
        SET @errores += @nl + N'- El nombre no puede superar los 40 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE nombre = @nombre)
        SET @errores += @nl + N'- Ya existe un idioma llamado "' + @nombre + N'".';

    IF @codigo_iso COLLATE Latin1_General_BIN NOT LIKE '[a-z][a-z]'
        SET @errores += @nl + N'- El código ISO 639-1 debe tener 2 letras (ej. "es").';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso = @codigo_iso)
        SET @errores += @nl + N'- El código ISO "' + @codigo_iso + N'" ya lo tiene otro idioma.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_IDIOMA_Alta: no se pudo dar de alta el idioma.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DatosGenerales.IDIOMA (nombre, codigo_iso)
    VALUES (@nombre, @codigo_iso);

    SET @id_idioma = SCOPE_IDENTITY();
END;
GO


/*
  usp_IDIOMA_Modificacion
  Valida: que el idioma exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_IDIOMA_Modificacion
    @id_idioma   SMALLINT,
    @nombre      VARCHAR(100) = NULL,
    @codigo_iso  VARCHAR(10)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre     = NULLIF(TRIM(@nombre), '');
    SET @codigo_iso = LOWER(NULLIF(TRIM(@codigo_iso), ''));

    IF @id_idioma IS NULL
        SET @errores += @nl + N'- El id del idioma es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE id_idioma = @id_idioma)
        SET @errores += @nl + N'- No existe un idioma con id ' + CAST(@id_idioma AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL AND @codigo_iso IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@nombre) > 40
        SET @errores += @nl + N'- El nombre no puede superar los 40 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE nombre = @nombre AND id_idioma <> @id_idioma)
        SET @errores += @nl + N'- Ya existe otro idioma llamado "' + @nombre + N'".';

    IF @codigo_iso COLLATE Latin1_General_BIN NOT LIKE '[a-z][a-z]'
        SET @errores += @nl + N'- El código ISO 639-1 debe tener 2 letras (ej. "es").';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA
                    WHERE codigo_iso = @codigo_iso AND id_idioma <> @id_idioma)
        SET @errores += @nl + N'- El código ISO "' + @codigo_iso + N'" ya lo tiene otro idioma.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_IDIOMA_Modificacion: no se pudo modificar el idioma.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DatosGenerales.IDIOMA
    SET nombre     = ISNULL(@nombre, nombre),
        codigo_iso = ISNULL(@codigo_iso, codigo_iso)
    WHERE id_idioma = @id_idioma;
END;
GO


/*
  usp_IDIOMA_Baja
  Valida: que el idioma exista y que no lo usen árbitros ni piezas publicitarias.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_IDIOMA_Baja
    @id_idioma SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_idioma IS NULL
        SET @errores += @nl + N'- El id del idioma es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE id_idioma = @id_idioma)
        SET @errores += @nl + N'- No existe un idioma con id ' + CAST(@id_idioma AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- Lo referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'Arbitraje.ARBITRO_IDIOMA', COUNT(*)
                FROM Arbitraje.ARBITRO_IDIOMA WHERE id_idioma = @id_idioma
                UNION ALL
                SELECT N'Publicidad.PIEZA_PUBLICITARIA', COUNT(*)
                FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_idioma = @id_idioma
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_IDIOMA_Baja: no se pudo dar de baja el idioma.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DatosGenerales.IDIOMA WHERE id_idioma = @id_idioma;
END;
GO


/* ============================================================================
   INDICADOR_ECONOMICO
   ============================================================================ */

/*
  usp_INDICADOR_ECONOMICO_Alta
  Valida: país obligatorio y existente; código del indicador obligatorio, de
  hasta 30 caracteres y con formato de código (ej. NY.GDP.PCAP.CD); año
  obligatorio entre 1960 y el año actual; valor obligatorio; que el país no
  tenga ya un valor de ese indicador para ese año.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
    @id_pais            SMALLINT,
    @codigo_indicador   VARCHAR(60),
    @anio               SMALLINT,
    @valor              DECIMAL(18,4),
    @id_indicador       INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @anio_actual SMALLINT       = YEAR(GETDATE());

    SET @codigo_indicador = UPPER(NULLIF(TRIM(@codigo_indicador), ''));

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @codigo_indicador IS NULL
        SET @errores += @nl + N'- El código del indicador es obligatorio (ej. NY.GDP.PCAP.CD).';
    ELSE IF LEN(@codigo_indicador) > 30
        SET @errores += @nl + N'- El código del indicador no puede superar los 30 caracteres.';
    ELSE IF @codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
        SET @errores += @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.';

    IF @anio IS NULL
        SET @errores += @nl + N'- El año es obligatorio.';
    ELSE IF @anio NOT BETWEEN 1960 AND @anio_actual
        SET @errores += @nl + N'- El año debe estar entre 1960 y ' + CAST(@anio_actual AS NVARCHAR(4)) + N'.';

    IF @valor IS NULL
        SET @errores += @nl + N'- El valor es obligatorio.';

    IF EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO
               WHERE id_pais = @id_pais AND codigo_indicador = @codigo_indicador AND anio = @anio)
        SET @errores += @nl + N'- Ese país ya tiene un valor de ' + @codigo_indicador + N' para '
                      + CAST(@anio AS NVARCHAR(4)) + N' (para cambiarlo se usa la modificación).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_INDICADOR_ECONOMICO_Alta: no se pudo dar de alta el indicador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
    VALUES (@id_pais, @codigo_indicador, @anio, @valor);

    SET @id_indicador = SCOPE_IDENTITY();
END;
GO


/*
  usp_INDICADOR_ECONOMICO_Modificacion
  Valida: que el indicador exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta; y que con los cambios no quede
  repetido el país, indicador y año. Actualiza fecha_actualizacion.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion
    @id_indicador       INT,
    @id_pais            SMALLINT      = NULL,
    @codigo_indicador   VARCHAR(60)   = NULL,
    @anio               SMALLINT      = NULL,
    @valor              DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @anio_actual   SMALLINT       = YEAR(GETDATE());
    -- Valores que va a tener el registro después del cambio, para controlar repetidos.
    DECLARE @id_pais_final SMALLINT;
    DECLARE @codigo_final  VARCHAR(60);
    DECLARE @anio_final    SMALLINT;

    SET @codigo_indicador = UPPER(NULLIF(TRIM(@codigo_indicador), ''));

    IF @id_indicador IS NULL
        SET @errores += @nl + N'- El id del indicador es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_indicador = @id_indicador)
        SET @errores += @nl + N'- No existe un indicador con id ' + CAST(@id_indicador AS NVARCHAR(10)) + N'.';

    IF @id_pais IS NULL AND @codigo_indicador IS NULL AND @anio IS NULL AND @valor IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @id_pais IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF LEN(@codigo_indicador) > 30
        SET @errores += @nl + N'- El código del indicador no puede superar los 30 caracteres.';
    ELSE IF @codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
        SET @errores += @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.';

    IF @anio NOT BETWEEN 1960 AND @anio_actual
        SET @errores += @nl + N'- El año debe estar entre 1960 y ' + CAST(@anio_actual AS NVARCHAR(4)) + N'.';

    SELECT @id_pais_final = ISNULL(@id_pais, id_pais),
           @codigo_final  = ISNULL(@codigo_indicador, codigo_indicador),
           @anio_final    = ISNULL(@anio, anio)
    FROM DatosGenerales.INDICADOR_ECONOMICO
    WHERE id_indicador = @id_indicador;

    IF EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO
               WHERE id_pais = @id_pais_final AND codigo_indicador = @codigo_final
                 AND anio = @anio_final AND id_indicador <> @id_indicador)
        SET @errores += @nl + N'- Ese país ya tiene otro valor de ' + @codigo_final + N' para '
                      + CAST(@anio_final AS NVARCHAR(4)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion: no se pudo modificar el indicador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DatosGenerales.INDICADOR_ECONOMICO
    SET id_pais             = ISNULL(@id_pais, id_pais),
        codigo_indicador    = ISNULL(@codigo_indicador, codigo_indicador),
        anio                = ISNULL(@anio, anio),
        valor               = ISNULL(@valor, valor),
        fecha_actualizacion = SYSDATETIME()
    WHERE id_indicador = @id_indicador;
END;
GO


/*
  usp_INDICADOR_ECONOMICO_Baja
  Valida: que el indicador exista.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_INDICADOR_ECONOMICO_Baja
    @id_indicador INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_indicador IS NULL
        SET @errores += @nl + N'- El id del indicador es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_indicador = @id_indicador)
        SET @errores += @nl + N'- No existe un indicador con id ' + CAST(@id_indicador AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_INDICADOR_ECONOMICO_Baja: no se pudo dar de baja el indicador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_indicador = @id_indicador;
END;
GO


/* ============================================================================
   PARAMETRO_REGLAMENTO
   ============================================================================ */

/*
  usp_PARAMETRO_REGLAMENTO_Alta
  Valida: código obligatorio, de hasta 50 caracteres, solo con letras sin
  acentos, números y guiones bajos, y no repetido; descripción obligatoria de
  hasta 200 caracteres; valor obligatorio y, si es un parámetro del sistema,
  dentro de su rango (DatosGenerales.fn_ParametrosDelSistema); y que los
  parámetros que van de a pares sigan siendo coherentes. El valor es TINYINT,
  así que el tipo ya impide negativos. El código se guarda en mayúsculas.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta
    @codigo       VARCHAR(100),
    @descripcion  VARCHAR(400),
    @valor        TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @codigo      = UPPER(NULLIF(TRIM(@codigo), ''));
    SET @descripcion = NULLIF(TRIM(@descripcion), '');

    IF @codigo IS NULL
        SET @errores += @nl + N'- El código es obligatorio.';
    ELSE IF LEN(@codigo) > 50
        SET @errores += @nl + N'- El código no puede superar los 50 caracteres.';
    ELSE IF @codigo COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9_]%'
        SET @errores += @nl + N'- El código solo admite letras sin acentos, números y guiones bajos.';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = @codigo)
        SET @errores += @nl + N'- Ya existe el parámetro "' + @codigo + N'".';

    IF @descripcion IS NULL
        SET @errores += @nl + N'- La descripción es obligatoria.';
    ELSE IF LEN(@descripcion) > 200
        SET @errores += @nl + N'- La descripción no puede superar los 200 caracteres.';

    IF @valor IS NULL
        SET @errores += @nl + N'- El valor es obligatorio.';
    ELSE
    BEGIN
        SET @errores += ISNULL((
            SELECT @nl + N'- ' + ps.codigo + N' admite valores entre '
                   + CAST(ps.valor_minimo AS NVARCHAR(3)) + N' y ' + CAST(ps.valor_maximo AS NVARCHAR(3)) + N'.'
            FROM DatosGenerales.fn_ParametrosDelSistema() AS ps
            WHERE ps.codigo = @codigo
              AND @valor NOT BETWEEN ps.valor_minimo AND ps.valor_maximo), N'');

        -- Parámetros que van de a pares: el primero no puede superar al segundo.
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- ' + par.codigo_menor + N' ('
                              + CAST(v.valor_menor AS NVARCHAR(10)) + N') no puede superar a '
                              + par.codigo_mayor + N' (' + CAST(v.valor_mayor AS NVARCHAR(10)) + N').', N'')
            FROM (VALUES ('MIN_CONVOCADOS',         'MAX_CONVOCADOS'),
                         ('MAX_VENTANAS',           'MAX_CAMBIOS'),
                         ('VENTANAS_EXTRA_ALARGUE', 'CAMBIOS_EXTRA_ALARGUE')) AS par (codigo_menor, codigo_mayor)
            CROSS APPLY (
                SELECT IIF(par.codigo_menor = @codigo, @valor,
                           (SELECT p.valor FROM DatosGenerales.PARAMETRO_REGLAMENTO AS p
                            WHERE p.codigo = par.codigo_menor)),
                       IIF(par.codigo_mayor = @codigo, @valor,
                           (SELECT p.valor FROM DatosGenerales.PARAMETRO_REGLAMENTO AS p
                            WHERE p.codigo = par.codigo_mayor))
            ) AS v (valor_menor, valor_mayor)
            WHERE @codigo IN (par.codigo_menor, par.codigo_mayor)
              AND v.valor_menor > v.valor_mayor), N'');

        -- La franja de prime time no puede empezar y terminar a la misma hora.
        IF @codigo IN ('PRIME_TIME_DESDE', 'PRIME_TIME_HASTA')
           AND EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO AS p
                       WHERE p.codigo = IIF(@codigo = 'PRIME_TIME_DESDE', 'PRIME_TIME_HASTA', 'PRIME_TIME_DESDE')
                         AND p.valor = @valor)
            SET @errores += @nl + N'- PRIME_TIME_DESDE y PRIME_TIME_HASTA no pueden tener el mismo valor.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta: no se pudo dar de alta el parámetro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DatosGenerales.PARAMETRO_REGLAMENTO (codigo, descripcion, valor)
    VALUES (@codigo, @descripcion, @valor);
END;
GO


/*
  usp_PARAMETRO_REGLAMENTO_Modificacion
  Valida: que el parámetro exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta. Actualiza fecha_modificacion.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion
    @codigo       VARCHAR(100),
    @descripcion  VARCHAR(400) = NULL,
    @valor        TINYINT      = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @codigo      = UPPER(NULLIF(TRIM(@codigo), ''));
    SET @descripcion = NULLIF(TRIM(@descripcion), '');

    IF @codigo IS NULL
        SET @errores += @nl + N'- El código es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = @codigo)
        SET @errores += @nl + N'- No existe el parámetro "' + @codigo + N'".';

    IF @descripcion IS NULL AND @valor IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@descripcion) > 200
        SET @errores += @nl + N'- La descripción no puede superar los 200 caracteres.';

    IF @valor IS NOT NULL
    BEGIN
        SET @errores += ISNULL((
            SELECT @nl + N'- ' + ps.codigo + N' admite valores entre '
                   + CAST(ps.valor_minimo AS NVARCHAR(3)) + N' y ' + CAST(ps.valor_maximo AS NVARCHAR(3)) + N'.'
            FROM DatosGenerales.fn_ParametrosDelSistema() AS ps
            WHERE ps.codigo = @codigo
              AND @valor NOT BETWEEN ps.valor_minimo AND ps.valor_maximo), N'');

        -- Parámetros que van de a pares: el primero no puede superar al segundo.
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- ' + par.codigo_menor + N' ('
                              + CAST(v.valor_menor AS NVARCHAR(10)) + N') no puede superar a '
                              + par.codigo_mayor + N' (' + CAST(v.valor_mayor AS NVARCHAR(10)) + N').', N'')
            FROM (VALUES ('MIN_CONVOCADOS',         'MAX_CONVOCADOS'),
                         ('MAX_VENTANAS',           'MAX_CAMBIOS'),
                         ('VENTANAS_EXTRA_ALARGUE', 'CAMBIOS_EXTRA_ALARGUE')) AS par (codigo_menor, codigo_mayor)
            CROSS APPLY (
                SELECT IIF(par.codigo_menor = @codigo, @valor,
                           (SELECT p.valor FROM DatosGenerales.PARAMETRO_REGLAMENTO AS p
                            WHERE p.codigo = par.codigo_menor)),
                       IIF(par.codigo_mayor = @codigo, @valor,
                           (SELECT p.valor FROM DatosGenerales.PARAMETRO_REGLAMENTO AS p
                            WHERE p.codigo = par.codigo_mayor))
            ) AS v (valor_menor, valor_mayor)
            WHERE @codigo IN (par.codigo_menor, par.codigo_mayor)
              AND v.valor_menor > v.valor_mayor), N'');

        IF @codigo IN ('PRIME_TIME_DESDE', 'PRIME_TIME_HASTA')
           AND EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO AS p
                       WHERE p.codigo = IIF(@codigo = 'PRIME_TIME_DESDE', 'PRIME_TIME_HASTA', 'PRIME_TIME_DESDE')
                         AND p.valor = @valor)
            SET @errores += @nl + N'- PRIME_TIME_DESDE y PRIME_TIME_HASTA no pueden tener el mismo valor.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion: no se pudo modificar el parámetro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE DatosGenerales.PARAMETRO_REGLAMENTO
    SET descripcion        = ISNULL(@descripcion, descripcion),
        valor              = ISNULL(@valor, valor),
        fecha_modificacion = SYSDATETIME()
    WHERE codigo = @codigo;
END;
GO


/*
  usp_PARAMETRO_REGLAMENTO_Baja
  Valida: que el parámetro exista y que no sea uno de los que usa el sistema
  (fn_ParametrosDelSistema): esos se pueden modificar, pero no eliminar.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja
    @codigo VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @codigo = UPPER(NULLIF(TRIM(@codigo), ''));

    IF @codigo IS NULL
        SET @errores += @nl + N'- El código es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = @codigo)
        SET @errores += @nl + N'- No existe el parámetro "' + @codigo + N'".';
    ELSE IF EXISTS (SELECT 1 FROM DatosGenerales.fn_ParametrosDelSistema() WHERE codigo = @codigo)
        SET @errores += @nl + N'- "' + @codigo + N'" lo usa el sistema: se puede modificar, pero no eliminar.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja: no se pudo dar de baja el parámetro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = @codigo;
END;
GO


-- Evidencia: SP creados en el esquema DatosGenerales.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DatosGenerales'
ORDER BY p.name;
GO
