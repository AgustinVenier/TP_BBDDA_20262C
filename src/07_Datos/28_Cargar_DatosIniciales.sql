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
           gol. Cada dato se da de alta con el SP de alta de su tabla
           (05_SP_ABM_DatosGenerales.sql y 07_SP_ABM_DesarrolloPartido.sql),
           que aplica sus validaciones; nunca con INSERT directo sobre las
           tablas. Requiere haber ejecutado 01 a 09.
           Se cargan todos o ninguno: van en una transacción y, si un SP
           rechaza un dato, el script se detiene con el motivo y no queda
           nada cargado. Si la base ya tiene los datos iniciales, avisa y no
           hace nada.
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

-- Si ya están cargados no se ejecuta el resto del script (SET NOEXEC, como en 02).
IF EXISTS (SELECT 1 FROM DatosGenerales.PAIS)
   OR EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO)
BEGIN
    PRINT N'28_Cargar_DatosIniciales.sql: la base ya tiene los datos iniciales; no se cargó nada.';
    SET NOEXEC ON;
END;
GO

-- Con XACT_ABORT, un error de cualquiera de los SP corta el lote y deshace la transacción.
SET XACT_ABORT ON;
BEGIN TRANSACTION;

/* ============================================================================
   1. PARÁMETROS DEL REGLAMENTO
   Código, descripción y valor.
   ============================================================================ */
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'AMARILLAS_PARA_SUSPENSION',        'Amarillas en partidos distintos que generan una suspensión', 2;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'FECHAS_SUSPENSION_ACUMULACION',    'Partidos de suspensión por acumulación de amarillas', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'FECHAS_SUSPENSION_DOBLE_AMARILLA', 'Partidos de suspensión por expulsión con doble amarilla', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'FECHAS_SUSPENSION_ROJA_DIRECTA',   'Partidos de suspensión por roja directa (mínimo)', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'LIMPIEZA_AMARILLAS_TRAS_GRUPOS',   '1 = las amarillas sueltas se anulan al terminar la fase de grupos', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'LIMPIEZA_AMARILLAS_TRAS_CUARTOS',  '1 = las amarillas sueltas se anulan al terminar los cuartos de final', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'MAX_CAMBIOS',                      'Cambios por equipo en el tiempo reglamentario', 5;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'MAX_VENTANAS',                     'Ventanas de cambio por equipo en el tiempo reglamentario, sin contar el entretiempo', 3;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'CAMBIOS_EXTRA_ALARGUE',            'Cambios adicionales por equipo en el tiempo suplementario', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'VENTANAS_EXTRA_ALARGUE',           'Ventanas adicionales por equipo en el tiempo suplementario', 1;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'MIN_CONVOCADOS',                   'Mínimo de jugadores en la lista de convocados', 23;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'MAX_CONVOCADOS',                   'Máximo de jugadores en la lista de convocados', 26;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'MIN_ARQUEROS_CONVOCADOS',          'Mínimo de arqueros en la lista de convocados', 3;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'SELECCIONES_POR_GRUPO',            'Selecciones por grupo en la fase de grupos', 4;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'PRIME_TIME_DESDE',                 'Hora local en que empieza el prime time de un mercado (inclusive)', 19;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'PRIME_TIME_HASTA',                 'Hora local en que termina el prime time de un mercado (exclusive)', 23;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'PBI_FRANJA_MILES_USD',             'Ancho, en miles de USD, de las franjas de PBI per cápita para priorizar publicidad', 10;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'RECARGO_PRIME_TIME_PCT',           '% de recargo sobre la tarifa por cada mercado de la pieza que ve el partido en prime time', 5;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'RECARGO_PRIME_TIME_MAX_PCT',       'Tope del % de recargo por prime time', 50;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta 'RECARGO_FASE_PCT',                 '% de recargo sobre la tarifa por cada ronda eliminatoria (1 dieciseisavos ... 5 final)', 10;

/* ============================================================================
   2. IDIOMAS
   Nombre y código ISO 639-1.
   ============================================================================ */
EXEC DatosGenerales.usp_IDIOMA_Alta 'Español',    'es';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Inglés',     'en';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Francés',    'fr';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Portugués',  'pt';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Alemán',     'de';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Italiano',   'it';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Neerlandés', 'nl';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Árabe',      'ar';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Japonés',    'ja';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Coreano',    'ko';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Chino',      'zh';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Persa',      'fa';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Croata',     'hr';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Noruego',    'no';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Polaco',     'pl';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Rumano',     'ro';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Esloveno',   'sl';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Sueco',      'sv';
EXEC DatosGenerales.usp_IDIOMA_Alta 'Uzbeko',     'uz';

/* ============================================================================
   3. PAÍSES
   Nombre, huso horario (nombre de zona de Windows, sys.time_zone_info),
   código FIFA, código ISO alfa-2, código ISO alfa-3 y moneda (ISO 4217).
   ============================================================================ */
-- Sedes del torneo
EXEC DatosGenerales.usp_PAIS_Alta 'Estados Unidos',                    'Eastern Standard Time',           'USA', 'US', 'USA', 'USD';
EXEC DatosGenerales.usp_PAIS_Alta 'México',                            'Central Standard Time (Mexico)',  'MEX', 'MX', 'MEX', 'MXN';
EXEC DatosGenerales.usp_PAIS_Alta 'Canadá',                            'Eastern Standard Time',           'CAN', 'CA', 'CAN', 'CAD';
-- CONMEBOL
EXEC DatosGenerales.usp_PAIS_Alta 'Argentina',                         'Argentina Standard Time',         'ARG', 'AR', 'ARG', 'ARS';
EXEC DatosGenerales.usp_PAIS_Alta 'Brasil',                            'E. South America Standard Time',  'BRA', 'BR', 'BRA', 'BRL';
EXEC DatosGenerales.usp_PAIS_Alta 'Uruguay',                           'Montevideo Standard Time',        'URU', 'UY', 'URY', 'UYU';
EXEC DatosGenerales.usp_PAIS_Alta 'Colombia',                          'SA Pacific Standard Time',        'COL', 'CO', 'COL', 'COP';
EXEC DatosGenerales.usp_PAIS_Alta 'Ecuador',                           'SA Pacific Standard Time',        'ECU', 'EC', 'ECU', 'USD';
EXEC DatosGenerales.usp_PAIS_Alta 'Paraguay',                          'Paraguay Standard Time',          'PAR', 'PY', 'PRY', 'PYG';
EXEC DatosGenerales.usp_PAIS_Alta 'Chile',                             'Pacific SA Standard Time',        'CHI', 'CL', 'CHL', 'CLP';
EXEC DatosGenerales.usp_PAIS_Alta 'Perú',                              'SA Pacific Standard Time',        'PER', 'PE', 'PER', 'PEN';
EXEC DatosGenerales.usp_PAIS_Alta 'Bolivia',                           'SA Western Standard Time',        'BOL', 'BO', 'BOL', 'BOB';
-- UEFA
EXEC DatosGenerales.usp_PAIS_Alta 'España',                            'Romance Standard Time',           'ESP', 'ES', 'ESP', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Francia',                           'Romance Standard Time',           'FRA', 'FR', 'FRA', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Alemania',                          'W. Europe Standard Time',         'GER', 'DE', 'DEU', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Inglaterra',                        'GMT Standard Time',               'ENG', 'GB', 'GBR', 'GBP';
EXEC DatosGenerales.usp_PAIS_Alta 'Escocia',                           'GMT Standard Time',               'SCO', 'GB', 'GBR', 'GBP';
EXEC DatosGenerales.usp_PAIS_Alta 'Portugal',                          'GMT Standard Time',               'POR', 'PT', 'PRT', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Países Bajos',                      'W. Europe Standard Time',         'NED', 'NL', 'NLD', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Bélgica',                           'Romance Standard Time',           'BEL', 'BE', 'BEL', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Croacia',                           'Central European Standard Time',  'CRO', 'HR', 'HRV', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Suiza',                             'W. Europe Standard Time',         'SUI', 'CH', 'CHE', 'CHF';
EXEC DatosGenerales.usp_PAIS_Alta 'Austria',                           'W. Europe Standard Time',         'AUT', 'AT', 'AUT', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Noruega',                           'W. Europe Standard Time',         'NOR', 'NO', 'NOR', 'NOK';
EXEC DatosGenerales.usp_PAIS_Alta 'Italia',                            'W. Europe Standard Time',         'ITA', 'IT', 'ITA', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Dinamarca',                         'Romance Standard Time',           'DEN', 'DK', 'DNK', 'DKK';
-- AFC
EXEC DatosGenerales.usp_PAIS_Alta 'Japón',                             'Tokyo Standard Time',             'JPN', 'JP', 'JPN', 'JPY';
EXEC DatosGenerales.usp_PAIS_Alta 'Corea del Sur',                     'Korea Standard Time',             'KOR', 'KR', 'KOR', 'KRW';
EXEC DatosGenerales.usp_PAIS_Alta 'Irán',                              'Iran Standard Time',              'IRN', 'IR', 'IRN', 'IRR';
EXEC DatosGenerales.usp_PAIS_Alta 'Australia',                         'AUS Eastern Standard Time',       'AUS', 'AU', 'AUS', 'AUD';
EXEC DatosGenerales.usp_PAIS_Alta 'Arabia Saudita',                    'Arab Standard Time',              'KSA', 'SA', 'SAU', 'SAR';
EXEC DatosGenerales.usp_PAIS_Alta 'Catar',                             'Arab Standard Time',              'QAT', 'QA', 'QAT', 'QAR';
EXEC DatosGenerales.usp_PAIS_Alta 'Uzbekistán',                        'West Asia Standard Time',         'UZB', 'UZ', 'UZB', 'UZS';
EXEC DatosGenerales.usp_PAIS_Alta 'Jordania',                          'Jordan Standard Time',            'JOR', 'JO', 'JOR', 'JOD';
EXEC DatosGenerales.usp_PAIS_Alta 'China',                             'China Standard Time',             'CHN', 'CN', 'CHN', 'CNY';
EXEC DatosGenerales.usp_PAIS_Alta 'India',                             'India Standard Time',             'IND', 'IN', 'IND', 'INR';
EXEC DatosGenerales.usp_PAIS_Alta 'Emiratos Árabes Unidos',            'Arabian Standard Time',           'UAE', 'AE', 'ARE', 'AED';
-- CAF
EXEC DatosGenerales.usp_PAIS_Alta 'Marruecos',                         'Morocco Standard Time',           'MAR', 'MA', 'MAR', 'MAD';
EXEC DatosGenerales.usp_PAIS_Alta 'Senegal',                           'Greenwich Standard Time',         'SEN', 'SN', 'SEN', 'XOF';
EXEC DatosGenerales.usp_PAIS_Alta 'Egipto',                            'Egypt Standard Time',             'EGY', 'EG', 'EGY', 'EGP';
EXEC DatosGenerales.usp_PAIS_Alta 'Argelia',                           'W. Central Africa Standard Time', 'ALG', 'DZ', 'DZA', 'DZD';
EXEC DatosGenerales.usp_PAIS_Alta 'Túnez',                             'W. Central Africa Standard Time', 'TUN', 'TN', 'TUN', 'TND';
EXEC DatosGenerales.usp_PAIS_Alta 'Ghana',                             'Greenwich Standard Time',         'GHA', 'GH', 'GHA', 'GHS';
EXEC DatosGenerales.usp_PAIS_Alta 'Costa de Marfil',                   'Greenwich Standard Time',         'CIV', 'CI', 'CIV', 'XOF';
EXEC DatosGenerales.usp_PAIS_Alta 'Sudáfrica',                         'South Africa Standard Time',      'RSA', 'ZA', 'ZAF', 'ZAR';
EXEC DatosGenerales.usp_PAIS_Alta 'Cabo Verde',                        'Cape Verde Standard Time',        'CPV', 'CV', 'CPV', 'CVE';
EXEC DatosGenerales.usp_PAIS_Alta 'Nigeria',                           'W. Central Africa Standard Time', 'NGA', 'NG', 'NGA', 'NGN';
-- CONCACAF (además de las sedes)
EXEC DatosGenerales.usp_PAIS_Alta 'Panamá',                            'SA Pacific Standard Time',        'PAN', 'PA', 'PAN', 'PAB';
EXEC DatosGenerales.usp_PAIS_Alta 'Haití',                             'Haiti Standard Time',             'HAI', 'HT', 'HTI', 'HTG';
EXEC DatosGenerales.usp_PAIS_Alta 'Costa Rica',                        'Central America Standard Time',   'CRC', 'CR', 'CRI', 'CRC';
-- OFC
EXEC DatosGenerales.usp_PAIS_Alta 'Nueva Zelanda',                     'New Zealand Standard Time',       'NZL', 'NZ', 'NZL', 'NZD';
-- Selecciones del Mundial 2026 que no están en las listas de arriba
EXEC DatosGenerales.usp_PAIS_Alta 'Bosnia y Herzegovina',              'Central European Standard Time',  'BIH', 'BA', 'BIH', 'BAM';
EXEC DatosGenerales.usp_PAIS_Alta 'República Checa',                   'Central Europe Standard Time',    'CZE', 'CZ', 'CZE', 'CZK';
EXEC DatosGenerales.usp_PAIS_Alta 'Suecia',                            'W. Europe Standard Time',         'SWE', 'SE', 'SWE', 'SEK';
EXEC DatosGenerales.usp_PAIS_Alta 'Turquía',                           'Turkey Standard Time',            'TUR', 'TR', 'TUR', 'TRY';
EXEC DatosGenerales.usp_PAIS_Alta 'Irak',                              'Arabic Standard Time',            'IRQ', 'IQ', 'IRQ', 'IQD';
EXEC DatosGenerales.usp_PAIS_Alta 'República Democrática del Congo',   'W. Central Africa Standard Time', 'COD', 'CD', 'COD', 'CDF';
EXEC DatosGenerales.usp_PAIS_Alta 'Curazao',                           'SA Western Standard Time',        'CUW', 'CW', 'CUW', 'XCG';
-- Países de los árbitros y directores técnicos del Mundial 2026 que no están en las listas de arriba
EXEC DatosGenerales.usp_PAIS_Alta 'Venezuela',                         'Venezuela Standard Time',         'VEN', 'VE', 'VEN', 'VES';
EXEC DatosGenerales.usp_PAIS_Alta 'Eslovenia',                         'Central Europe Standard Time',    'SVN', 'SI', 'SVN', 'EUR';
EXEC DatosGenerales.usp_PAIS_Alta 'Polonia',                           'Central European Standard Time',  'POL', 'PL', 'POL', 'PLN';
EXEC DatosGenerales.usp_PAIS_Alta 'Rumania',                           'GTB Standard Time',               'ROU', 'RO', 'ROU', 'RON';
EXEC DatosGenerales.usp_PAIS_Alta 'Honduras',                          'Central America Standard Time',   'HON', 'HN', 'HND', 'HNL';
EXEC DatosGenerales.usp_PAIS_Alta 'El Salvador',                       'Central America Standard Time',   'SLV', 'SV', 'SLV', 'USD';
EXEC DatosGenerales.usp_PAIS_Alta 'Nicaragua',                         'Central America Standard Time',   'NCA', 'NI', 'NIC', 'NIO';
EXEC DatosGenerales.usp_PAIS_Alta 'Jamaica',                           'SA Pacific Standard Time',        'JAM', 'JM', 'JAM', 'JMD';
EXEC DatosGenerales.usp_PAIS_Alta 'Trinidad y Tobago',                 'SA Western Standard Time',        'TRI', 'TT', 'TTO', 'TTD';
EXEC DatosGenerales.usp_PAIS_Alta 'Gabón',                             'W. Central Africa Standard Time', 'GAB', 'GA', 'GAB', 'XAF';
EXEC DatosGenerales.usp_PAIS_Alta 'Camerún',                           'W. Central Africa Standard Time', 'CMR', 'CM', 'CMR', 'XAF';
EXEC DatosGenerales.usp_PAIS_Alta 'Angola',                            'W. Central Africa Standard Time', 'ANG', 'AO', 'AGO', 'AOA';
EXEC DatosGenerales.usp_PAIS_Alta 'Mauritania',                        'Greenwich Standard Time',         'MTN', 'MR', 'MRT', 'MRU';
EXEC DatosGenerales.usp_PAIS_Alta 'Grecia',                            'GTB Standard Time',               'GRE', 'GR', 'GRC', 'EUR';

/* ============================================================================
   4. TIPOS DE GOL
   Descripción y si es en contra.
   ============================================================================ */
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta 'JUGADA',     0;
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta 'CABEZAZO',   0;
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta 'TIRO LIBRE', 0;
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta 'PENAL',      0;
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta 'EN CONTRA',  1;

COMMIT TRANSACTION;
SET XACT_ABORT OFF;

PRINT N'Datos iniciales cargados.';
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
