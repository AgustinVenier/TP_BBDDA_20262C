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
 Archivo: 08_SP_ABM_Publicidad.sql
 Objetivo: Crear los stored procedures de alta, baja y modificación de las
           tablas del esquema Publicidad: ANUNCIANTE, CAMPANIA,
           PIEZA_PUBLICITARIA, PIEZA_PAIS_INTERES, ESPACIO_PUBLICITARIO y
           EXHIBICION. Siguen las convenciones descriptas en
           04_SP_ABM_DatosGenerales.sql. Requiere haber ejecutado 00 a 07.
           Su script de testing es 58_Test_SP_ABM_Publicidad.sql.
================================================================================

 Particularidades de este esquema:
   - PIEZA_PAIS_INTERES solo tiene alta y baja: sus dos columnas son la clave.
   - ESPACIO_PUBLICITARIO: número del 1 al 4 por sede. El espacio no cambia
     de sede (así ninguna exhibición queda en un espacio de otra sede). Los
     cuatro espacios de una sede nueva los crea Torneo.usp_RegistrarSede.
   - EXHIBICION: es el registro para facturar. Se carga, modifica o quita
     solo con el partido PROGRAMADO; después queda como historial. El costo
     se guarda en el momento (si no se informa, es la tarifa del espacio en
     dólares), porque la tarifa puede cambiar después.
   - La asignación automática de las cuatro piezas de un partido está en
     Publicidad.usp_AsignarPublicidadPartido (15_SP_Negocio_Publicidad.sql).
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   ANUNCIANTE
   ============================================================================ */

/*
  usp_ANUNCIANTE_Alta
  Valida: razón social obligatoria, de hasta 150 caracteres y no repetida;
  país existente.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ANUNCIANTE_Alta
    @razon_social   NVARCHAR(300),
    @id_pais        SMALLINT,
    @id_anunciante  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @razon_social = NULLIF(TRIM(@razon_social), N'');

    IF @razon_social IS NULL
        SET @errores += @nl + N'- La razón social es obligatoria.';
    ELSE IF LEN(@razon_social) > 150
        SET @errores += @nl + N'- La razón social no puede superar los 150 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE WHERE razon_social = @razon_social)
        SET @errores += @nl + N'- Ya existe el anunciante "' + @razon_social + N'".';

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ANUNCIANTE_Alta: no se pudo dar de alta el anunciante.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais)
    VALUES (@razon_social, @id_pais);

    SET @id_anunciante = SCOPE_IDENTITY();
END;
GO


/*
  usp_ANUNCIANTE_Modificacion
  Valida: que el anunciante exista y que se informe al menos un dato; para
  cada dato informado, las mismas reglas del alta.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ANUNCIANTE_Modificacion
    @id_anunciante  INT,
    @razon_social   NVARCHAR(300) = NULL,
    @id_pais        SMALLINT      = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @razon_social = NULLIF(TRIM(@razon_social), N'');

    IF @id_anunciante IS NULL
        SET @errores += @nl + N'- El id del anunciante es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE WHERE id_anunciante = @id_anunciante)
        SET @errores += @nl + N'- No existe un anunciante con id ' + CAST(@id_anunciante AS NVARCHAR(10)) + N'.';

    IF @razon_social IS NULL AND @id_pais IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@razon_social) > 150
        SET @errores += @nl + N'- La razón social no puede superar los 150 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE
                    WHERE razon_social = @razon_social AND id_anunciante <> @id_anunciante)
        SET @errores += @nl + N'- Ya existe otro anunciante "' + @razon_social + N'".';

    IF @id_pais IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ANUNCIANTE_Modificacion: no se pudo modificar el anunciante.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.ANUNCIANTE
    SET razon_social = ISNULL(@razon_social, razon_social),
        id_pais      = ISNULL(@id_pais, id_pais)
    WHERE id_anunciante = @id_anunciante;
END;
GO


/*
  usp_ANUNCIANTE_Baja
  Valida: que el anunciante exista y que no tenga campañas.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ANUNCIANTE_Baja
    @id_anunciante INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores   NVARCHAR(2048) = N'';
    DECLARE @nl        NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @campanias INT;

    IF @id_anunciante IS NULL
        SET @errores += @nl + N'- El id del anunciante es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE WHERE id_anunciante = @id_anunciante)
        SET @errores += @nl + N'- No existe un anunciante con id ' + CAST(@id_anunciante AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @campanias = COUNT(*) FROM Publicidad.CAMPANIA WHERE id_anunciante = @id_anunciante;
        IF @campanias > 0
            SET @errores += @nl + N'- Lo referencian ' + CAST(@campanias AS NVARCHAR(10))
                          + N' registro(s) de Publicidad.CAMPANIA.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ANUNCIANTE_Baja: no se pudo dar de baja el anunciante.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.ANUNCIANTE WHERE id_anunciante = @id_anunciante;
END;
GO


/* ============================================================================
   CAMPANIA
   ============================================================================ */

/*
  usp_CAMPANIA_Alta
  Valida: anunciante existente; nombre obligatorio, de hasta 150 caracteres y
  no repetido para el anunciante; fechas de inicio y fin obligatorias, con el
  fin no anterior al inicio.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_CAMPANIA_Alta
    @id_anunciante  INT,
    @nombre         NVARCHAR(300),
    @fecha_inicio   DATE,
    @fecha_fin      DATE,
    @id_campania    INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre = NULLIF(TRIM(@nombre), N'');

    IF @id_anunciante IS NULL
        SET @errores += @nl + N'- El anunciante es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE WHERE id_anunciante = @id_anunciante)
        SET @errores += @nl + N'- No existe un anunciante con id ' + CAST(@id_anunciante AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 150
        SET @errores += @nl + N'- El nombre no puede superar los 150 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.CAMPANIA WHERE id_anunciante = @id_anunciante AND nombre = @nombre)
        SET @errores += @nl + N'- El anunciante ya tiene una campaña "' + @nombre + N'".';

    IF @fecha_inicio IS NULL OR @fecha_fin IS NULL
        SET @errores += @nl + N'- Las fechas de inicio y de fin son obligatorias.';
    ELSE IF @fecha_fin < @fecha_inicio
        SET @errores += @nl + N'- La fecha de fin no puede ser anterior a la de inicio.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_CAMPANIA_Alta: no se pudo dar de alta la campaña.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin)
    VALUES (@id_anunciante, @nombre, @fecha_inicio, @fecha_fin);

    SET @id_campania = SCOPE_IDENTITY();
END;
GO


/*
  usp_CAMPANIA_Modificacion
  Valida: que la campaña exista y que se informe al menos un dato; nombre y
  fechas con las reglas del alta; que con las fechas nuevas no quede afuera
  ningún partido en el que ya se exhibió una pieza de la campaña. El
  anunciante no se modifica.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_CAMPANIA_Modificacion
    @id_campania    INT,
    @nombre         NVARCHAR(300) = NULL,
    @fecha_inicio   DATE          = NULL,
    @fecha_fin      DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_anunciante INT;
    DECLARE @inicio_final  DATE;
    DECLARE @fin_final     DATE;
    DECLARE @partido       TINYINT;

    SET @nombre = NULLIF(TRIM(@nombre), N'');

    SELECT @id_anunciante = id_anunciante,
           @inicio_final  = ISNULL(@fecha_inicio, fecha_inicio),
           @fin_final     = ISNULL(@fecha_fin, fecha_fin)
    FROM Publicidad.CAMPANIA
    WHERE id_campania = @id_campania;

    IF @id_campania IS NULL
        SET @errores += @nl + N'- El id de la campaña es obligatorio.';
    ELSE IF @id_anunciante IS NULL
        SET @errores += @nl + N'- No existe una campaña con id ' + CAST(@id_campania AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL AND @fecha_inicio IS NULL AND @fecha_fin IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@nombre) > 150
        SET @errores += @nl + N'- El nombre no puede superar los 150 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.CAMPANIA
                    WHERE id_anunciante = @id_anunciante AND nombre = @nombre AND id_campania <> @id_campania)
        SET @errores += @nl + N'- El anunciante ya tiene otra campaña "' + @nombre + N'".';

    IF @fin_final < @inicio_final
        SET @errores += @nl + N'- La fecha de fin no puede ser anterior a la de inicio.';
    ELSE IF @fecha_inicio IS NOT NULL OR @fecha_fin IS NOT NULL
    BEGIN
        SELECT TOP (1) @partido = p.numero_partido
        FROM Publicidad.EXHIBICION AS e
        INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = e.id_pieza
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = e.id_partido
        WHERE pz.id_campania = @id_campania
          AND CAST(p.fecha_hora_local AS DATE) NOT BETWEEN @inicio_final AND @fin_final;
        IF @partido IS NOT NULL
            SET @errores += @nl + N'- Con esas fechas quedaría afuera el partido '
                          + CAST(@partido AS NVARCHAR(3)) + N', en el que ya se exhibe una pieza de la campaña.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_CAMPANIA_Modificacion: no se pudo modificar la campaña.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.CAMPANIA
    SET nombre       = ISNULL(@nombre, nombre),
        fecha_inicio = @inicio_final,
        fecha_fin    = @fin_final
    WHERE id_campania = @id_campania;
END;
GO


/*
  usp_CAMPANIA_Baja
  Valida: que la campaña exista y que no tenga piezas.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_CAMPANIA_Baja
    @id_campania INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @piezas  INT;

    IF @id_campania IS NULL
        SET @errores += @nl + N'- El id de la campaña es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania)
        SET @errores += @nl + N'- No existe una campaña con id ' + CAST(@id_campania AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @piezas = COUNT(*) FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_campania = @id_campania;
        IF @piezas > 0
            SET @errores += @nl + N'- La referencian ' + CAST(@piezas AS NVARCHAR(10))
                          + N' registro(s) de Publicidad.PIEZA_PUBLICITARIA.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_CAMPANIA_Baja: no se pudo dar de baja la campaña.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;
END;
GO


/* ============================================================================
   PIEZA_PUBLICITARIA
   ============================================================================ */

/*
  usp_PIEZA_PUBLICITARIA_Alta
  Valida: campaña existente; título obligatorio, de hasta 150 caracteres y no
  repetido en la campaña; idioma existente; duración mayor que cero.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_PIEZA_PUBLICITARIA_Alta
    @id_campania        INT,
    @titulo             NVARCHAR(300),
    @id_idioma          SMALLINT = NULL,
    @duracion_segundos  TINYINT  = NULL,
    @id_pieza           INT      = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @titulo = NULLIF(TRIM(@titulo), N'');

    IF @id_campania IS NULL
        SET @errores += @nl + N'- La campaña es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania)
        SET @errores += @nl + N'- No existe una campaña con id ' + CAST(@id_campania AS NVARCHAR(10)) + N'.';

    IF @titulo IS NULL
        SET @errores += @nl + N'- El título es obligatorio.';
    ELSE IF LEN(@titulo) > 150
        SET @errores += @nl + N'- El título no puede superar los 150 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_campania = @id_campania AND titulo = @titulo)
        SET @errores += @nl + N'- La campaña ya tiene una pieza "' + @titulo + N'".';

    IF @id_idioma IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE id_idioma = @id_idioma)
        SET @errores += @nl + N'- No existe un idioma con id ' + CAST(@id_idioma AS NVARCHAR(10)) + N'.';

    IF @duracion_segundos = 0
        SET @errores += @nl + N'- La duración debe ser mayor que cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_PIEZA_PUBLICITARIA_Alta: no se pudo dar de alta la pieza.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo, duracion_segundos)
    VALUES (@id_campania, @id_idioma, @titulo, @duracion_segundos);

    SET @id_pieza = SCOPE_IDENTITY();
END;
GO


/*
  usp_PIEZA_PUBLICITARIA_Modificacion
  Valida: que la pieza exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta. La campaña no se modifica.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_PIEZA_PUBLICITARIA_Modificacion
    @id_pieza           INT,
    @titulo             NVARCHAR(300) = NULL,
    @id_idioma          SMALLINT      = NULL,
    @duracion_segundos  TINYINT       = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_campania INT;

    SET @titulo = NULLIF(TRIM(@titulo), N'');

    SELECT @id_campania = id_campania FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza;

    IF @id_pieza IS NULL
        SET @errores += @nl + N'- El id de la pieza es obligatorio.';
    ELSE IF @id_campania IS NULL
        SET @errores += @nl + N'- No existe una pieza con id ' + CAST(@id_pieza AS NVARCHAR(10)) + N'.';

    IF @titulo IS NULL AND @id_idioma IS NULL AND @duracion_segundos IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF LEN(@titulo) > 150
        SET @errores += @nl + N'- El título no puede superar los 150 caracteres.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA
                    WHERE id_campania = @id_campania AND titulo = @titulo AND id_pieza <> @id_pieza)
        SET @errores += @nl + N'- La campaña ya tiene otra pieza "' + @titulo + N'".';

    IF @id_idioma IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE id_idioma = @id_idioma)
        SET @errores += @nl + N'- No existe un idioma con id ' + CAST(@id_idioma AS NVARCHAR(10)) + N'.';

    IF @duracion_segundos = 0
        SET @errores += @nl + N'- La duración debe ser mayor que cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_PIEZA_PUBLICITARIA_Modificacion: no se pudo modificar la pieza.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.PIEZA_PUBLICITARIA
    SET titulo            = ISNULL(@titulo, titulo),
        id_idioma         = ISNULL(@id_idioma, id_idioma),
        duracion_segundos = ISNULL(@duracion_segundos, duracion_segundos)
    WHERE id_pieza = @id_pieza;
END;
GO


/*
  usp_PIEZA_PUBLICITARIA_Baja
  Valida: que la pieza exista y que no tenga mercados de interés ni
  exhibiciones.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_PIEZA_PUBLICITARIA_Baja
    @id_pieza INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_pieza IS NULL
        SET @errores += @nl + N'- El id de la pieza es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza)
        SET @errores += @nl + N'- No existe una pieza con id ' + CAST(@id_pieza AS NVARCHAR(10)) + N'.';
    ELSE
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- La referencian ' + CAST(r.cantidad AS NVARCHAR(10))
                              + N' registro(s) de ' + r.tabla + N'.', N'')
            FROM (
                SELECT N'Publicidad.PIEZA_PAIS_INTERES', COUNT(*)
                FROM Publicidad.PIEZA_PAIS_INTERES WHERE id_pieza = @id_pieza
                UNION ALL
                SELECT N'Publicidad.EXHIBICION', COUNT(*)
                FROM Publicidad.EXHIBICION WHERE id_pieza = @id_pieza
            ) AS r (tabla, cantidad)
            WHERE r.cantidad > 0), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_PIEZA_PUBLICITARIA_Baja: no se pudo dar de baja la pieza.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza;
END;
GO


/* ============================================================================
   PIEZA_PAIS_INTERES
   ============================================================================ */

/*
  usp_PIEZA_PAIS_INTERES_Alta
  Valida: pieza y país existentes, y que la pieza no tenga ya ese mercado.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_PIEZA_PAIS_INTERES_Alta
    @id_pieza  INT,
    @id_pais   SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_pieza IS NULL
        SET @errores += @nl + N'- La pieza es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza)
        SET @errores += @nl + N'- No existe una pieza con id ' + CAST(@id_pieza AS NVARCHAR(10)) + N'.';

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES WHERE id_pieza = @id_pieza AND id_pais = @id_pais)
        SET @errores += @nl + N'- La pieza ya tiene ese país como mercado de interés.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_PIEZA_PAIS_INTERES_Alta: no se pudo agregar el mercado de interés.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
    VALUES (@id_pieza, @id_pais);
END;
GO


/*
  usp_PIEZA_PAIS_INTERES_Baja
  Valida: que la pieza tenga ese mercado de interés.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_PIEZA_PAIS_INTERES_Baja
    @id_pieza  INT,
    @id_pais   SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    IF @id_pieza IS NULL OR @id_pais IS NULL
        SET @errores += @nl + N'- La pieza y el país son obligatorios.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES WHERE id_pieza = @id_pieza AND id_pais = @id_pais)
        SET @errores += @nl + N'- La pieza no tiene ese país como mercado de interés.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_PIEZA_PAIS_INTERES_Baja: no se pudo quitar el mercado de interés.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.PIEZA_PAIS_INTERES WHERE id_pieza = @id_pieza AND id_pais = @id_pais;
END;
GO


/* ============================================================================
   ESPACIO_PUBLICITARIO
   ============================================================================ */

/*
  usp_ESPACIO_PUBLICITARIO_Alta
  Valida: sede existente y con menos de 4 espacios; número de espacio entre 1
  y 4 y libre en la sede; tarifa obligatoria; descripción de hasta 100
  caracteres.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ESPACIO_PUBLICITARIO_Alta
    @id_sede         INT,
    @numero_espacio  TINYINT,
    @tarifa_usd      DECIMAL(9,2),
    @descripcion     VARCHAR(200) = NULL,
    @id_espacio      INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores  NVARCHAR(2048) = N'';
    DECLARE @nl       NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @espacios INT;

    SET @descripcion = NULLIF(TRIM(@descripcion), '');

    IF @id_sede IS NULL
        SET @errores += @nl + N'- La sede es obligatoria.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Torneo.SEDE WHERE id_sede = @id_sede)
        SET @errores += @nl + N'- No existe una sede con id ' + CAST(@id_sede AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @espacios = COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id_sede;
        IF @espacios >= 4
            SET @errores += @nl + N'- La sede ya tiene sus 4 espacios publicitarios.';
    END;

    IF @numero_espacio IS NULL
        SET @errores += @nl + N'- El número de espacio es obligatorio.';
    ELSE IF @numero_espacio NOT BETWEEN 1 AND 4
        SET @errores += @nl + N'- El número de espacio debe estar entre 1 y 4.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO
                    WHERE id_sede = @id_sede AND numero_espacio = @numero_espacio)
        SET @errores += @nl + N'- La sede ya tiene el espacio número ' + CAST(@numero_espacio AS NVARCHAR(1)) + N'.';

    IF @tarifa_usd IS NULL
        SET @errores += @nl + N'- La tarifa es obligatoria.';
    ELSE IF @tarifa_usd < 0
        SET @errores += @nl + N'- La tarifa no puede ser negativa.';

    IF LEN(@descripcion) > 100
        SET @errores += @nl + N'- La descripción no puede superar los 100 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ESPACIO_PUBLICITARIO_Alta: no se pudo dar de alta el espacio publicitario.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, descripcion, tarifa_usd)
    VALUES (@id_sede, @numero_espacio, @descripcion, @tarifa_usd);

    SET @id_espacio = SCOPE_IDENTITY();
END;
GO


/*
  usp_ESPACIO_PUBLICITARIO_Modificacion
  Valida: que el espacio exista y que se informe al menos un dato; tarifa no
  negativa; descripción de hasta 100 caracteres. Cambiar la tarifa no altera
  el costo de las exhibiciones ya registradas.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion
    @id_espacio   INT,
    @tarifa_usd   DECIMAL(9,2) = NULL,
    @descripcion  VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @descripcion = NULLIF(TRIM(@descripcion), '');

    IF @id_espacio IS NULL
        SET @errores += @nl + N'- El id del espacio es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id_espacio)
        SET @errores += @nl + N'- No existe un espacio publicitario con id ' + CAST(@id_espacio AS NVARCHAR(10)) + N'.';

    IF @tarifa_usd IS NULL AND @descripcion IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @tarifa_usd < 0
        SET @errores += @nl + N'- La tarifa no puede ser negativa.';

    IF LEN(@descripcion) > 100
        SET @errores += @nl + N'- La descripción no puede superar los 100 caracteres.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion: no se pudo modificar el espacio publicitario.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.ESPACIO_PUBLICITARIO
    SET tarifa_usd  = ISNULL(@tarifa_usd, tarifa_usd),
        descripcion = ISNULL(@descripcion, descripcion)
    WHERE id_espacio = @id_espacio;
END;
GO


/*
  usp_ESPACIO_PUBLICITARIO_Baja
  Valida: que el espacio exista y que no tenga exhibiciones registradas.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ESPACIO_PUBLICITARIO_Baja
    @id_espacio INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @exhibiciones  INT;

    IF @id_espacio IS NULL
        SET @errores += @nl + N'- El id del espacio es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id_espacio)
        SET @errores += @nl + N'- No existe un espacio publicitario con id ' + CAST(@id_espacio AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        SELECT @exhibiciones = COUNT(*) FROM Publicidad.EXHIBICION WHERE id_espacio = @id_espacio;
        IF @exhibiciones > 0
            SET @errores += @nl + N'- Lo referencian ' + CAST(@exhibiciones AS NVARCHAR(10))
                          + N' registro(s) de Publicidad.EXHIBICION.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ESPACIO_PUBLICITARIO_Baja: no se pudo dar de baja el espacio publicitario.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id_espacio;
END;
GO


/* ============================================================================
   EXHIBICION
   ============================================================================ */

/*
  usp_EXHIBICION_Alta
  Valida: partido existente y PROGRAMADO; espacio existente, de la sede del
  partido y libre en ese partido; pieza existente, de una campaña vigente en
  la fecha local del partido y que no se exhiba ya en otro espacio del mismo
  partido; costo no negativo y moneda de 3 letras. Sin costo, se usa la
  tarifa del espacio en USD.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_EXHIBICION_Alta
    @id_partido     INT,
    @id_espacio     INT,
    @id_pieza       INT,
    @costo          DECIMAL(19,4) = NULL,
    @codigo_moneda  VARCHAR(10)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado         VARCHAR(12);
    DECLARE @sede_partido   INT;
    DECLARE @fecha_partido  DATE;
    DECLARE @sede_espacio   INT;
    DECLARE @tarifa         DECIMAL(9,2);
    DECLARE @inicio         DATE;
    DECLARE @fin            DATE;

    SET @codigo_moneda = UPPER(NULLIF(TRIM(@codigo_moneda), ''));

    SELECT @estado = estado, @sede_partido = id_sede, @fecha_partido = CAST(fecha_hora_local AS DATE)
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    SELECT @sede_espacio = id_sede, @tarifa = tarifa_usd
    FROM Publicidad.ESPACIO_PUBLICITARIO
    WHERE id_espacio = @id_espacio;

    SELECT @inicio = c.fecha_inicio, @fin = c.fecha_fin
    FROM Publicidad.PIEZA_PUBLICITARIA AS pz
    INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
    WHERE pz.id_pieza = @id_pieza;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- La publicidad se asigna antes de que empiece el partido (estado actual: '
                      + @estado + N').';

    IF @id_espacio IS NULL
        SET @errores += @nl + N'- El espacio es obligatorio.';
    ELSE IF @sede_espacio IS NULL
        SET @errores += @nl + N'- No existe un espacio publicitario con id ' + CAST(@id_espacio AS NVARCHAR(10)) + N'.';
    ELSE IF @sede_espacio <> @sede_partido
        SET @errores += @nl + N'- El espacio no es de la sede del partido.';
    ELSE IF EXISTS (SELECT 1 FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_espacio = @id_espacio)
        SET @errores += @nl + N'- El espacio ya tiene una pieza asignada en ese partido.';

    IF @id_pieza IS NULL
        SET @errores += @nl + N'- La pieza es obligatoria.';
    ELSE IF @inicio IS NULL
        SET @errores += @nl + N'- No existe una pieza con id ' + CAST(@id_pieza AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @fecha_partido NOT BETWEEN @inicio AND @fin
            SET @errores += @nl + N'- La campaña de la pieza no está vigente en la fecha del partido.';
        IF EXISTS (SELECT 1 FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_pieza = @id_pieza)
            SET @errores += @nl + N'- La pieza ya ocupa otro espacio en ese partido.';
    END;

    IF @costo < 0
        SET @errores += @nl + N'- El costo no puede ser negativo.';

    IF @codigo_moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código de moneda debe tener 3 letras (ISO 4217).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_EXHIBICION_Alta: no se pudo registrar la exhibición.' + @errores;
        THROW 50001, @errores, 1;
    END;

    IF @costo IS NULL
        SELECT @costo = @tarifa, @codigo_moneda = 'USD';

    INSERT INTO Publicidad.EXHIBICION (id_partido, id_espacio, id_pieza, costo, codigo_moneda)
    VALUES (@id_partido, @id_espacio, @id_pieza, @costo, ISNULL(@codigo_moneda, 'USD'));
END;
GO


/*
  usp_EXHIBICION_Modificacion
  Valida: que la exhibición exista, que el partido esté PROGRAMADO y que se
  informe al menos un dato; la pieza nueva con las reglas del alta; costo no
  negativo y moneda de 3 letras.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_EXHIBICION_Modificacion
    @id_partido     INT,
    @id_espacio     INT,
    @id_pieza       INT           = NULL,
    @costo          DECIMAL(19,4) = NULL,
    @codigo_moneda  VARCHAR(10)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado         VARCHAR(12);
    DECLARE @fecha_partido  DATE;
    DECLARE @inicio         DATE;
    DECLARE @fin            DATE;

    SET @codigo_moneda = UPPER(NULLIF(TRIM(@codigo_moneda), ''));

    SELECT @estado = p.estado, @fecha_partido = CAST(p.fecha_hora_local AS DATE)
    FROM Publicidad.EXHIBICION AS e
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = e.id_partido
    WHERE e.id_partido = @id_partido AND e.id_espacio = @id_espacio;

    IF @id_partido IS NULL OR @id_espacio IS NULL
        SET @errores += @nl + N'- El partido y el espacio son obligatorios.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No hay una exhibición en ese espacio para ese partido.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- El partido está ' + @estado + N': la exhibición ya es parte del historial para facturar.';

    IF @id_pieza IS NULL AND @costo IS NULL AND @codigo_moneda IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @id_pieza IS NOT NULL
    BEGIN
        SELECT @inicio = c.fecha_inicio, @fin = c.fecha_fin
        FROM Publicidad.PIEZA_PUBLICITARIA AS pz
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        WHERE pz.id_pieza = @id_pieza;

        IF @inicio IS NULL
            SET @errores += @nl + N'- No existe una pieza con id ' + CAST(@id_pieza AS NVARCHAR(10)) + N'.';
        ELSE
        BEGIN
            IF @fecha_partido NOT BETWEEN @inicio AND @fin
                SET @errores += @nl + N'- La campaña de la pieza no está vigente en la fecha del partido.';
            IF EXISTS (SELECT 1 FROM Publicidad.EXHIBICION
                       WHERE id_partido = @id_partido AND id_pieza = @id_pieza AND id_espacio <> @id_espacio)
                SET @errores += @nl + N'- La pieza ya ocupa otro espacio en ese partido.';
        END;
    END;

    IF @costo < 0
        SET @errores += @nl + N'- El costo no puede ser negativo.';

    IF @codigo_moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código de moneda debe tener 3 letras (ISO 4217).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_EXHIBICION_Modificacion: no se pudo modificar la exhibición.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.EXHIBICION
    SET id_pieza       = ISNULL(@id_pieza, id_pieza),
        costo          = ISNULL(@costo, costo),
        codigo_moneda  = ISNULL(@codigo_moneda, codigo_moneda),
        fecha_registro = SYSDATETIME()
    WHERE id_partido = @id_partido AND id_espacio = @id_espacio;
END;
GO


/*
  usp_EXHIBICION_Baja
  Valida: que la exhibición exista y que el partido esté PROGRAMADO.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_EXHIBICION_Baja
    @id_partido  INT,
    @id_espacio  INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado  VARCHAR(12);

    SELECT @estado = p.estado
    FROM Publicidad.EXHIBICION AS e
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = e.id_partido
    WHERE e.id_partido = @id_partido AND e.id_espacio = @id_espacio;

    IF @id_partido IS NULL OR @id_espacio IS NULL
        SET @errores += @nl + N'- El partido y el espacio son obligatorios.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No hay una exhibición en ese espacio para ese partido.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- El partido está ' + @estado + N': la exhibición ya es parte del historial para facturar.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_EXHIBICION_Baja: no se pudo quitar la exhibición.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_espacio = @id_espacio;
END;
GO


-- Evidencia: SP creados en el esquema Publicidad.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Publicidad'
ORDER BY p.name;
GO
