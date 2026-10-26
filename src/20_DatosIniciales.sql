/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - COMPLETAR
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier

 Fecha: 25/10/2026
 Archivo: 20_DatosIniciales.sql
 Objetivo: Cargar los datos que el sistema necesita para funcionar: los
           parámetros del reglamento, los idiomas, los países y los tipos de
           gol. Todo se carga con los SP de ABM, nunca con INSERT directo
           sobre las tablas. Requiere haber ejecutado 00 a 16.
           Es re-ejecutable: lo que ya existe no se vuelve a cargar. Si una
           fila no pasa las validaciones, se informa el motivo y se sigue con
           las demás.
================================================================================

 Criterios de los datos:
   - Parámetros: 5 cambios en 3 ventanas, más un cambio y una ventana extra en
     el alargue; suspensión de un partido por 2 amarillas en partidos
     distintos, por doble amarilla o por roja directa; las amarillas sueltas
     se anulan después de cuartos de final, como en el reglamento del
     Mundial 2022 (LIMPIEZA_AMARILLAS_TRAS_GRUPOS en 1 las anularía también
     al terminar la fase de grupos); listas de 23 a 26 jugadores con al menos
     3 arqueros; grupos de 4 selecciones; prime time de 19 a 23 hs; el PBI
     per cápita se compara por franjas de 10.000 USD. Se pueden cambiar con
     usp_PARAMETRO_REGLAMENTO_Modificacion sin tocar código.
   - Países: no es la lista de clasificados (las selecciones se cargan en el
     esquema Torneo). Incluye los países de las sedes, de selecciones, de
     árbitros y de mercados de interés para la publicidad. Para los países
     con más de un huso horario se toma el de la capital. Inglaterra y
     Escocia comparten los códigos ISO del Reino Unido.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Si faltan los SP de ABM no se ejecuta el resto del script (SET NOEXEC, como en 01).
IF OBJECT_ID(N'DatosGenerales.usp_PAIS_Alta', N'P') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_TIPO_GOL_Alta', N'P') IS NULL
BEGIN
    RAISERROR(N'Faltan los SP de ABM (scripts 04 a 08): no se cargó ningún dato.', 16, 1);
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   1. PARÁMETROS DEL REGLAMENTO
   ============================================================================ */
DECLARE @parametros TABLE (
    orden        INT IDENTITY(1,1) PRIMARY KEY,
    codigo       VARCHAR(50),
    descripcion  VARCHAR(200),
    valor        TINYINT
);

INSERT INTO @parametros (codigo, descripcion, valor)
VALUES
    ('AMARILLAS_PARA_SUSPENSION',        'Amarillas en partidos distintos que generan una suspensión', 2),
    ('FECHAS_SUSPENSION_ACUMULACION',    'Partidos de suspensión por acumulación de amarillas', 1),
    ('FECHAS_SUSPENSION_DOBLE_AMARILLA', 'Partidos de suspensión por expulsión con doble amarilla', 1),
    ('FECHAS_SUSPENSION_ROJA_DIRECTA',   'Partidos de suspensión por roja directa (mínimo)', 1),
    ('LIMPIEZA_AMARILLAS_TRAS_GRUPOS',   '1 = las amarillas sueltas se anulan al terminar la fase de grupos', 0),
    ('LIMPIEZA_AMARILLAS_TRAS_CUARTOS',  '1 = las amarillas sueltas se anulan al terminar los cuartos de final', 1),
    ('MAX_CAMBIOS',                      'Cambios por equipo en el tiempo reglamentario', 5),
    ('MAX_VENTANAS',                     'Ventanas de cambio por equipo en el tiempo reglamentario, sin contar el entretiempo', 3),
    ('CAMBIOS_EXTRA_ALARGUE',            'Cambios adicionales por equipo en el tiempo suplementario', 1),
    ('VENTANAS_EXTRA_ALARGUE',           'Ventanas adicionales por equipo en el tiempo suplementario', 1),
    ('MIN_CONVOCADOS',                   'Mínimo de jugadores en la lista de convocados', 23),
    ('MAX_CONVOCADOS',                   'Máximo de jugadores en la lista de convocados', 26),
    ('MIN_ARQUEROS_CONVOCADOS',          'Mínimo de arqueros en la lista de convocados', 3),
    ('SELECCIONES_POR_GRUPO',            'Selecciones por grupo en la fase de grupos', 4),
    ('PRIME_TIME_DESDE',                 'Hora local en que empieza el prime time de un mercado (inclusive)', 19),
    ('PRIME_TIME_HASTA',                 'Hora local en que termina el prime time de un mercado (exclusive)', 23),
    ('PBI_FRANJA_MILES_USD',             'Ancho, en miles de USD, de las franjas de PBI per cápita para priorizar publicidad', 10);

DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @parametros);
DECLARE @cargados INT = 0, @existentes INT = 0, @rechazados INT = 0;
DECLARE @codigo VARCHAR(50), @descripcion VARCHAR(200), @valor TINYINT;

WHILE @i <= @total
BEGIN
    SELECT @codigo = codigo, @descripcion = descripcion, @valor = valor
    FROM @parametros
    WHERE orden = @i;

    IF EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = @codigo)
        SET @existentes += 1;
    ELSE
    BEGIN
        BEGIN TRY
            EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta
                @codigo = @codigo, @descripcion = @descripcion, @valor = @valor;
            SET @cargados += 1;
        END TRY
        BEGIN CATCH
            SET @rechazados += 1;
            PRINT N'Rechazado ' + @codigo + N': ' + ERROR_MESSAGE();
        END CATCH;
    END;

    SET @i += 1;
END;

PRINT CONCAT(N'Parámetros: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


/* ============================================================================
   2. IDIOMAS (código ISO 639-1)
   ============================================================================ */
DECLARE @idiomas TABLE (
    orden       INT IDENTITY(1,1) PRIMARY KEY,
    nombre      VARCHAR(40),
    codigo_iso  CHAR(2)
);

INSERT INTO @idiomas (nombre, codigo_iso)
VALUES
    ('Español',    'es'),
    ('Inglés',     'en'),
    ('Francés',    'fr'),
    ('Portugués',  'pt'),
    ('Alemán',     'de'),
    ('Italiano',   'it'),
    ('Neerlandés', 'nl'),
    ('Árabe',      'ar'),
    ('Japonés',    'ja'),
    ('Coreano',    'ko'),
    ('Chino',      'zh'),
    ('Persa',      'fa'),
    ('Croata',     'hr'),
    ('Noruego',    'no');

DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @idiomas);
DECLARE @cargados INT = 0, @existentes INT = 0, @rechazados INT = 0;
DECLARE @nombre VARCHAR(40), @codigo_iso CHAR(2);

WHILE @i <= @total
BEGIN
    SELECT @nombre = nombre, @codigo_iso = codigo_iso
    FROM @idiomas
    WHERE orden = @i;

    IF EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE nombre = @nombre)
        SET @existentes += 1;
    ELSE
    BEGIN
        BEGIN TRY
            EXEC DatosGenerales.usp_IDIOMA_Alta @nombre = @nombre, @codigo_iso = @codigo_iso;
            SET @cargados += 1;
        END TRY
        BEGIN CATCH
            SET @rechazados += 1;
            PRINT N'Rechazado ' + @nombre + N': ' + ERROR_MESSAGE();
        END CATCH;
    END;

    SET @i += 1;
END;

PRINT CONCAT(N'Idiomas: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


/* ============================================================================
   3. PAÍSES
   Huso: nombre de zona de Windows (sys.time_zone_info). Moneda: ISO 4217.
   ============================================================================ */
DECLARE @paises TABLE (
    orden          INT IDENTITY(1,1) PRIMARY KEY,
    nombre         VARCHAR(60),
    codigo_fifa    CHAR(3),
    codigo_iso2    CHAR(2),
    codigo_iso3    CHAR(3),
    huso_horario   VARCHAR(50),
    codigo_moneda  CHAR(3)
);

INSERT INTO @paises (nombre, codigo_fifa, codigo_iso2, codigo_iso3, huso_horario, codigo_moneda)
VALUES
    -- Sedes del torneo
    ('Estados Unidos',         'USA', 'US', 'USA', 'Eastern Standard Time',           'USD'),
    ('México',                 'MEX', 'MX', 'MEX', 'Central Standard Time (Mexico)',  'MXN'),
    ('Canadá',                 'CAN', 'CA', 'CAN', 'Eastern Standard Time',           'CAD'),
    -- CONMEBOL
    ('Argentina',              'ARG', 'AR', 'ARG', 'Argentina Standard Time',         'ARS'),
    ('Brasil',                 'BRA', 'BR', 'BRA', 'E. South America Standard Time',  'BRL'),
    ('Uruguay',                'URU', 'UY', 'URY', 'Montevideo Standard Time',        'UYU'),
    ('Colombia',               'COL', 'CO', 'COL', 'SA Pacific Standard Time',        'COP'),
    ('Ecuador',                'ECU', 'EC', 'ECU', 'SA Pacific Standard Time',        'USD'),
    ('Paraguay',               'PAR', 'PY', 'PRY', 'Paraguay Standard Time',          'PYG'),
    ('Chile',                  'CHI', 'CL', 'CHL', 'Pacific SA Standard Time',        'CLP'),
    ('Perú',                   'PER', 'PE', 'PER', 'SA Pacific Standard Time',        'PEN'),
    ('Bolivia',                'BOL', 'BO', 'BOL', 'SA Western Standard Time',        'BOB'),
    -- UEFA
    ('España',                 'ESP', 'ES', 'ESP', 'Romance Standard Time',           'EUR'),
    ('Francia',                'FRA', 'FR', 'FRA', 'Romance Standard Time',           'EUR'),
    ('Alemania',               'GER', 'DE', 'DEU', 'W. Europe Standard Time',         'EUR'),
    ('Inglaterra',             'ENG', 'GB', 'GBR', 'GMT Standard Time',               'GBP'),
    ('Escocia',                'SCO', 'GB', 'GBR', 'GMT Standard Time',               'GBP'),
    ('Portugal',               'POR', 'PT', 'PRT', 'GMT Standard Time',               'EUR'),
    ('Países Bajos',           'NED', 'NL', 'NLD', 'W. Europe Standard Time',         'EUR'),
    ('Bélgica',                'BEL', 'BE', 'BEL', 'Romance Standard Time',           'EUR'),
    ('Croacia',                'CRO', 'HR', 'HRV', 'Central European Standard Time',  'EUR'),
    ('Suiza',                  'SUI', 'CH', 'CHE', 'W. Europe Standard Time',         'CHF'),
    ('Austria',                'AUT', 'AT', 'AUT', 'W. Europe Standard Time',         'EUR'),
    ('Noruega',                'NOR', 'NO', 'NOR', 'W. Europe Standard Time',         'NOK'),
    ('Italia',                 'ITA', 'IT', 'ITA', 'W. Europe Standard Time',         'EUR'),
    ('Dinamarca',              'DEN', 'DK', 'DNK', 'Romance Standard Time',           'DKK'),
    -- AFC
    ('Japón',                  'JPN', 'JP', 'JPN', 'Tokyo Standard Time',             'JPY'),
    ('Corea del Sur',          'KOR', 'KR', 'KOR', 'Korea Standard Time',             'KRW'),
    ('Irán',                   'IRN', 'IR', 'IRN', 'Iran Standard Time',              'IRR'),
    ('Australia',              'AUS', 'AU', 'AUS', 'AUS Eastern Standard Time',       'AUD'),
    ('Arabia Saudita',         'KSA', 'SA', 'SAU', 'Arab Standard Time',              'SAR'),
    ('Catar',                  'QAT', 'QA', 'QAT', 'Arab Standard Time',              'QAR'),
    ('Uzbekistán',             'UZB', 'UZ', 'UZB', 'West Asia Standard Time',         'UZS'),
    ('Jordania',               'JOR', 'JO', 'JOR', 'Jordan Standard Time',            'JOD'),
    ('China',                  'CHN', 'CN', 'CHN', 'China Standard Time',             'CNY'),
    ('India',                  'IND', 'IN', 'IND', 'India Standard Time',             'INR'),
    ('Emiratos Árabes Unidos', 'UAE', 'AE', 'ARE', 'Arabian Standard Time',           'AED'),
    -- CAF
    ('Marruecos',              'MAR', 'MA', 'MAR', 'Morocco Standard Time',           'MAD'),
    ('Senegal',                'SEN', 'SN', 'SEN', 'Greenwich Standard Time',         'XOF'),
    ('Egipto',                 'EGY', 'EG', 'EGY', 'Egypt Standard Time',             'EGP'),
    ('Argelia',                'ALG', 'DZ', 'DZA', 'W. Central Africa Standard Time', 'DZD'),
    ('Túnez',                  'TUN', 'TN', 'TUN', 'W. Central Africa Standard Time', 'TND'),
    ('Ghana',                  'GHA', 'GH', 'GHA', 'Greenwich Standard Time',         'GHS'),
    ('Costa de Marfil',        'CIV', 'CI', 'CIV', 'Greenwich Standard Time',         'XOF'),
    ('Sudáfrica',              'RSA', 'ZA', 'ZAF', 'South Africa Standard Time',      'ZAR'),
    ('Cabo Verde',             'CPV', 'CV', 'CPV', 'Cape Verde Standard Time',        'CVE'),
    ('Nigeria',                'NGA', 'NG', 'NGA', 'W. Central Africa Standard Time', 'NGN'),
    -- CONCACAF (además de las sedes)
    ('Panamá',                 'PAN', 'PA', 'PAN', 'SA Pacific Standard Time',        'PAB'),
    ('Haití',                  'HAI', 'HT', 'HTI', 'Haiti Standard Time',             'HTG'),
    ('Costa Rica',             'CRC', 'CR', 'CRI', 'Central America Standard Time',   'CRC'),
    -- OFC
    ('Nueva Zelanda',          'NZL', 'NZ', 'NZL', 'New Zealand Standard Time',       'NZD');

DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @paises);
DECLARE @cargados INT = 0, @existentes INT = 0, @rechazados INT = 0;
DECLARE @nombre VARCHAR(60), @codigo_fifa CHAR(3), @codigo_iso2 CHAR(2), @codigo_iso3 CHAR(3),
        @huso_horario VARCHAR(50), @codigo_moneda CHAR(3);

WHILE @i <= @total
BEGIN
    SELECT @nombre        = nombre,
           @codigo_fifa   = codigo_fifa,
           @codigo_iso2   = codigo_iso2,
           @codigo_iso3   = codigo_iso3,
           @huso_horario  = huso_horario,
           @codigo_moneda = codigo_moneda
    FROM @paises
    WHERE orden = @i;

    IF EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE nombre = @nombre)
        SET @existentes += 1;
    ELSE
    BEGIN
        BEGIN TRY
            EXEC DatosGenerales.usp_PAIS_Alta
                @nombre        = @nombre,
                @huso_horario  = @huso_horario,
                @codigo_fifa   = @codigo_fifa,
                @codigo_iso2   = @codigo_iso2,
                @codigo_iso3   = @codigo_iso3,
                @codigo_moneda = @codigo_moneda;
            SET @cargados += 1;
        END TRY
        BEGIN CATCH
            SET @rechazados += 1;
            PRINT N'Rechazado ' + @nombre + N': ' + ERROR_MESSAGE();
        END CATCH;
    END;

    SET @i += 1;
END;

PRINT CONCAT(N'Países: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


/* ============================================================================
   4. TIPOS DE GOL
   ============================================================================ */
DECLARE @tipos TABLE (
    orden         INT IDENTITY(1,1) PRIMARY KEY,
    descripcion   VARCHAR(40),
    es_en_contra  BIT
);

INSERT INTO @tipos (descripcion, es_en_contra)
VALUES
    ('JUGADA',     0),
    ('CABEZAZO',   0),
    ('TIRO LIBRE', 0),
    ('PENAL',      0),
    ('EN CONTRA',  1);

DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @tipos);
DECLARE @cargados INT = 0, @existentes INT = 0, @rechazados INT = 0;
DECLARE @descripcion VARCHAR(40), @es_en_contra BIT;

WHILE @i <= @total
BEGIN
    SELECT @descripcion = descripcion, @es_en_contra = es_en_contra
    FROM @tipos
    WHERE orden = @i;

    IF EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = @descripcion)
        SET @existentes += 1;
    ELSE
    BEGIN
        BEGIN TRY
            EXEC DesarrolloPartido.usp_TIPO_GOL_Alta @descripcion = @descripcion, @es_en_contra = @es_en_contra;
            SET @cargados += 1;
        END TRY
        BEGIN CATCH
            SET @rechazados += 1;
            PRINT N'Rechazado ' + @descripcion + N': ' + ERROR_MESSAGE();
        END CATCH;
    END;

    SET @i += 1;
END;

PRINT CONCAT(N'Tipos de gol: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


-- Evidencia: datos cargados.
SELECT codigo, valor, descripcion
FROM DatosGenerales.PARAMETRO_REGLAMENTO
ORDER BY codigo;

SELECT id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
ORDER BY nombre;

SELECT id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3, huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
ORDER BY nombre;

SELECT id_tipo_gol, descripcion, es_en_contra
FROM DesarrolloPartido.TIPO_GOL
ORDER BY id_tipo_gol;
GO

SET NOEXEC OFF;
GO
