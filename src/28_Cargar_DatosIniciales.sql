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
 Archivo: 28_Cargar_DatosIniciales.sql
 Objetivo: Cargar los datos que el sistema necesita para funcionar: los
           parámetros del reglamento, los idiomas, los países y los tipos de
           gol. Cada tabla se arma en una tabla de staging y se carga por
           conjuntos con su SP de 16_SP_CargaMasiva.sql, que aplica las
           mismas reglas que el SP de alta de la tabla; nunca con INSERT
           directo sobre las tablas. Requiere haber ejecutado 01 a 16.
           Es re-ejecutable: lo que ya existe no se vuelve a cargar (queda
           SIN CAMBIOS). Si una fila no pasa las validaciones, se informa el
           motivo y se cargan las demás.
================================================================================

 Criterios de los datos:
   - Parámetros: 5 cambios en 3 ventanas, más un cambio y una ventana extra en
     el alargue; suspensión de un partido por 2 amarillas en partidos
     distintos, por doble amarilla o por roja directa; las amarillas sueltas
     se anulan al terminar la fase de grupos y al terminar los cuartos de
     final, como en el reglamento del Mundial 2026 (en el de 2022 solo se
     anulaban después de cuartos: LIMPIEZA_AMARILLAS_TRAS_GRUPOS en 0);
     listas de 23 a 26 jugadores con al menos 3 arqueros; grupos de 4
     selecciones; prime time de 19 a 23 hs; el PBI
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

-- Si faltan los SP de carga no se ejecuta el resto del script (SET NOEXEC, como en 02).
IF OBJECT_ID(N'DatosGenerales.usp_CargarParametrosReglamento', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_CargarIdiomas', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_CargarPaises', N'P') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_CargarTiposGol', N'P') IS NULL
BEGIN
    RAISERROR(N'Faltan los SP de carga (16_SP_CargaMasiva.sql): no se cargó ningún dato.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Las tablas de staging de una ejecución anterior en esta sesión.
DROP TABLE IF EXISTS #staging_parametros, #staging_idiomas, #staging_paises, #staging_tipos_gol;
GO


/* ============================================================================
   1. PARÁMETROS DEL REGLAMENTO
   ============================================================================ */
CREATE TABLE #staging_parametros (
    codigo       VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    descripcion  VARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    valor        TINYINT       NULL,
    errores      NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion       VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_parametros (codigo, descripcion, valor)
VALUES
    ('AMARILLAS_PARA_SUSPENSION',        'Amarillas en partidos distintos que generan una suspensión', 2),
    ('FECHAS_SUSPENSION_ACUMULACION',    'Partidos de suspensión por acumulación de amarillas', 1),
    ('FECHAS_SUSPENSION_DOBLE_AMARILLA', 'Partidos de suspensión por expulsión con doble amarilla', 1),
    ('FECHAS_SUSPENSION_ROJA_DIRECTA',   'Partidos de suspensión por roja directa (mínimo)', 1),
    ('LIMPIEZA_AMARILLAS_TRAS_GRUPOS',   '1 = las amarillas sueltas se anulan al terminar la fase de grupos', 1),
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
    ('PBI_FRANJA_MILES_USD',             'Ancho, en miles de USD, de las franjas de PBI per cápita para priorizar publicidad', 10),
    ('RECARGO_PRIME_TIME_PCT',           '% de recargo sobre la tarifa por cada mercado de la pieza que ve el partido en prime time', 5),
    ('RECARGO_PRIME_TIME_MAX_PCT',       'Tope del % de recargo por prime time', 50),
    ('RECARGO_FASE_PCT',                 '% de recargo sobre la tarifa por cada ronda eliminatoria (1 dieciseisavos ... 5 final)', 10);

EXEC DatosGenerales.usp_CargarParametrosReglamento;

DECLARE @cargados INT, @existentes INT, @rechazados INT, @motivos NVARCHAR(MAX);
SELECT @cargados   = COUNT(CASE WHEN accion = 'INSERTADO'   THEN 1 END),
       @existentes = COUNT(CASE WHEN accion = 'SIN CAMBIOS' THEN 1 END),
       @rechazados = COUNT(CASE WHEN accion = 'RECHAZADO'   THEN 1 END),
       @motivos    = STRING_AGG(CASE WHEN accion = 'RECHAZADO' THEN CONCAT(N'Rechazado ', codigo, N':', errores) END,
                                NCHAR(13) + NCHAR(10))
FROM #staging_parametros;

IF @motivos IS NOT NULL PRINT @motivos;
PRINT CONCAT(N'Parámetros: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


/* ============================================================================
   2. IDIOMAS (código ISO 639-1)
   ============================================================================ */
CREATE TABLE #staging_idiomas (
    nombre      VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    codigo_iso  VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    errores     NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion      VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_idiomas (nombre, codigo_iso)
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
    ('Noruego',    'no'),
    ('Polaco',     'pl'),
    ('Rumano',     'ro'),
    ('Esloveno',   'sl'),
    ('Sueco',      'sv'),
    ('Uzbeko',     'uz');

EXEC DatosGenerales.usp_CargarIdiomas;

DECLARE @cargados INT, @existentes INT, @rechazados INT, @motivos NVARCHAR(MAX);
SELECT @cargados   = COUNT(CASE WHEN accion = 'INSERTADO'   THEN 1 END),
       @existentes = COUNT(CASE WHEN accion = 'SIN CAMBIOS' THEN 1 END),
       @rechazados = COUNT(CASE WHEN accion = 'RECHAZADO'   THEN 1 END),
       @motivos    = STRING_AGG(CASE WHEN accion = 'RECHAZADO' THEN CONCAT(N'Rechazado ', nombre, N':', errores) END,
                                NCHAR(13) + NCHAR(10))
FROM #staging_idiomas;

IF @motivos IS NOT NULL PRINT @motivos;
PRINT CONCAT(N'Idiomas: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


/* ============================================================================
   3. PAÍSES
   Huso: nombre de zona de Windows (sys.time_zone_info). Moneda: ISO 4217.
   ============================================================================ */
CREATE TABLE #staging_paises (
    nombre         VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    codigo_fifa    VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    codigo_iso2    VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    codigo_iso3    VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    huso_horario   VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    codigo_moneda  VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    errores        NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion         VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_paises (nombre, codigo_fifa, codigo_iso2, codigo_iso3, huso_horario, codigo_moneda)
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
    ('Nueva Zelanda',          'NZL', 'NZ', 'NZL', 'New Zealand Standard Time',       'NZD'),
    -- Selecciones del Mundial 2026 que no están en las listas de arriba
    ('Bosnia y Herzegovina',   'BIH', 'BA', 'BIH', 'Central European Standard Time',  'BAM'),
    ('República Checa',        'CZE', 'CZ', 'CZE', 'Central Europe Standard Time',    'CZK'),
    ('Suecia',                 'SWE', 'SE', 'SWE', 'W. Europe Standard Time',         'SEK'),
    ('Turquía',                'TUR', 'TR', 'TUR', 'Turkey Standard Time',            'TRY'),
    ('Irak',                   'IRQ', 'IQ', 'IRQ', 'Arabic Standard Time',            'IQD'),
    ('República Democrática del Congo', 'COD', 'CD', 'COD', 'W. Central Africa Standard Time', 'CDF'),
    ('Curazao',                'CUW', 'CW', 'CUW', 'SA Western Standard Time',        'XCG'),
    -- Países de los árbitros y directores técnicos del Mundial 2026 que no están en las listas de arriba
    ('Venezuela',              'VEN', 'VE', 'VEN', 'Venezuela Standard Time',         'VES'),
    ('Eslovenia',              'SVN', 'SI', 'SVN', 'Central Europe Standard Time',    'EUR'),
    ('Polonia',                'POL', 'PL', 'POL', 'Central European Standard Time',  'PLN'),
    ('Rumania',                'ROU', 'RO', 'ROU', 'GTB Standard Time',               'RON'),
    ('Honduras',               'HON', 'HN', 'HND', 'Central America Standard Time',   'HNL'),
    ('El Salvador',            'SLV', 'SV', 'SLV', 'Central America Standard Time',   'USD'),
    ('Nicaragua',              'NCA', 'NI', 'NIC', 'Central America Standard Time',   'NIO'),
    ('Jamaica',                'JAM', 'JM', 'JAM', 'SA Pacific Standard Time',        'JMD'),
    ('Trinidad y Tobago',      'TRI', 'TT', 'TTO', 'SA Western Standard Time',        'TTD'),
    ('Gabón',                  'GAB', 'GA', 'GAB', 'W. Central Africa Standard Time', 'XAF'),
    ('Camerún',                'CMR', 'CM', 'CMR', 'W. Central Africa Standard Time', 'XAF'),
    ('Angola',                 'ANG', 'AO', 'AGO', 'W. Central Africa Standard Time', 'AOA'),
    ('Mauritania',             'MTN', 'MR', 'MRT', 'Greenwich Standard Time',         'MRU'),
    ('Grecia',                 'GRE', 'GR', 'GRC', 'GTB Standard Time',               'EUR');

EXEC DatosGenerales.usp_CargarPaises;

DECLARE @cargados INT, @existentes INT, @rechazados INT, @motivos NVARCHAR(MAX);
SELECT @cargados   = COUNT(CASE WHEN accion = 'INSERTADO'   THEN 1 END),
       @existentes = COUNT(CASE WHEN accion = 'SIN CAMBIOS' THEN 1 END),
       @rechazados = COUNT(CASE WHEN accion = 'RECHAZADO'   THEN 1 END),
       @motivos    = STRING_AGG(CASE WHEN accion = 'RECHAZADO' THEN CONCAT(N'Rechazado ', nombre, N':', errores) END,
                                NCHAR(13) + NCHAR(10))
FROM #staging_paises;

IF @motivos IS NOT NULL PRINT @motivos;
PRINT CONCAT(N'Países: ', @cargados, N' cargados, ', @existentes, N' ya existían, ',
             @rechazados, N' rechazados.');
GO


/* ============================================================================
   4. TIPOS DE GOL
   ============================================================================ */
CREATE TABLE #staging_tipos_gol (
    descripcion   VARCHAR(80)   COLLATE DATABASE_DEFAULT NULL,
    es_en_contra  BIT           NULL,
    errores       NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion        VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_tipos_gol (descripcion, es_en_contra)
VALUES
    ('JUGADA',     0),
    ('CABEZAZO',   0),
    ('TIRO LIBRE', 0),
    ('PENAL',      0),
    ('EN CONTRA',  1);

EXEC DesarrolloPartido.usp_CargarTiposGol;

DECLARE @cargados INT, @existentes INT, @rechazados INT, @motivos NVARCHAR(MAX);
SELECT @cargados   = COUNT(CASE WHEN accion = 'INSERTADO'   THEN 1 END),
       @existentes = COUNT(CASE WHEN accion = 'SIN CAMBIOS' THEN 1 END),
       @rechazados = COUNT(CASE WHEN accion = 'RECHAZADO'   THEN 1 END),
       @motivos    = STRING_AGG(CASE WHEN accion = 'RECHAZADO' THEN CONCAT(N'Rechazado ', descripcion, N':', errores) END,
                                NCHAR(13) + NCHAR(10))
FROM #staging_tipos_gol;

IF @motivos IS NOT NULL PRINT @motivos;
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
