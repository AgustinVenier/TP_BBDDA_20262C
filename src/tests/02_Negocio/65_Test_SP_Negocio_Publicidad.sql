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
 Archivo: 65_Test_SP_Negocio_Publicidad.sql
 Objetivo: Probar los SP de 15_SP_Negocio_Publicidad.sql
           (usp_RegistrarPiezaPublicitaria y usp_AsignarPublicidadPartido),
           la simulación de prime time (fn_MercadosEnPrimeTime) y la
           prioridad de piezas (fn_PrioridadPiezas), incluido el caso
           obligatorio de un partido en prime time en más de cuatro mercados,
           en el que el sistema elige solo cuatro piezas.
           Requiere haber ejecutado 01 a 28; no depende del juego de datos.
           Cada caso arma sus propios datos con INSERT directos a las tablas
           (ver PREPARACIÓN): nueve países de prueba con su huso horario y su
           PBI per cápita 2024 (mercados), el anunciante "Adidas1" con cinco
           campañas de febrero y marzo de 2027, las sedes "Mercedes-Benz
           Stadium1" (con sus 4 espacios) y "Empower Field1" (sin espacios) y
           los partidos 250 a 253. Los partidos son de 2027 para que las
           únicas piezas candidatas sean las del test; si hay otras campañas
           vigentes en febrero o marzo de 2027, el test lo avisa al empezar.
           Los deshace al terminar, así que se puede ejecutar más de una vez.
           Los casos obligatorios se prueban acá con datos propios.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.

 Mercados de prueba (partido 250: 20/02/2027 a las 19:00 UTC; prime time de
 19 a 23 hs y franjas de PBI de 10.000 USD, según 28_Cargar_DatosIniciales.sql):
   Código  País             Huso                      Hora local  Prime time  PBI 2024  Franja
   XPA     Islandia1        Greenwich Standard Time   19:00       sí          20000     2
   XPB     Senegal1         Greenwich Standard Time   19:00       sí          -         -   (no es mercado de ninguna pieza)
   XPC     Inglaterra1      GMT Standard Time         19:00       sí          95000     9
   XPD     Francia1         Romance Standard Time     20:00       sí          52000     5
   XPE     Alemania1        W. Europe Standard Time   20:00       sí          45000     4
   XPF     Moldavia1        E. Europe Standard Time   21:00       sí          15000     1
   XPG     Finlandia1       FLE Standard Time         21:00       sí          41000     4
   XPH     Japón1           Tokyo Standard Time       04:00       no          88000     8
   XPI     Estados Unidos1  Eastern Standard Time     14:00       no          93000     9
 Los países de prueba se llaman como uno real con un 1 al final y usan
 códigos FIFA que empiezan con X, que no tiene ningún miembro de la FIFA: los
 mercados de una pieza se informan por código.

 Cada caso corre en su propia transacción (BEGIN TRANSACTION ... ROLLBACK)
 y en un solo lote: estos SP usan SET XACT_ABORT ON, así que un error deja
 la transacción sin poder confirmarse y SQL Server la deshace al terminar el
 lote. Por eso no hay una sola transacción para todo el test, y en un mismo
 lote puede haber casos OK pero un solo caso de error, al final. Cada lote
 vuelve a cargar con INSERT lo que dejaron los casos OK anteriores.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Publicidad.usp_AsignarPublicidadPartido', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO
                  WHERE codigo IN ('PRIME_TIME_DESDE', 'PRIME_TIME_HASTA', 'PBI_FRANJA_MILES_USD',
                                   'RECARGO_PRIME_TIME_PCT', 'RECARGO_PRIME_TIME_MAX_PCT', 'RECARGO_FASE_PCT')
                  HAVING COUNT(*) = 6)
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Las piezas de otras campañas vigentes en febrero o marzo de 2027 competirían
-- con las de prueba, y la asignación podría elegirlas: si las hay, se avisa.
DECLARE @otras INT = (SELECT COUNT(*)
                      FROM Publicidad.CAMPANIA AS c
                      INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                      WHERE a.razon_social <> N'Adidas1'
                        AND c.fecha_inicio <= '2027-03-31' AND c.fecha_fin >= '2027-02-01');
IF @otras > 0
    PRINT CONCAT(N'ADVERTENCIA: hay ', @otras, N' campaña(s) ajenas a este test vigentes en febrero o marzo ',
                 N'de 2027. Sus piezas compiten con las de prueba, así que la asignación puede no dar el ',
                 N'resultado esperado.');
GO

/* ============================================================================
   PREPARACIÓN de todos los casos, con INSERT directos (no se usan los SP de
   otros scripts):
   - Los nueve países de la tabla del encabezado, con su PBI per cápita 2024.
     Islandia1 (XPA) y Senegal1 (XPB) tienen selección, sin jugadores.
   - El anunciante "Adidas1" con cinco campañas: la 1 a la 3, del 01/02/2027
     al 31/03/2027; la 4 y la 5, del 01/02/2027 al 28/02/2027. Las piezas de
     las campañas 2 a 5: "Adidas Europa" (XPC, XPD y XPE), "Adidas Mixta"
     (XPI y XPF), "Adidas Asia" (XPH) y "Adidas Sur" (XPG y XPE). La de la
     campaña 1, "Adidas Islandia", la registra PP1.
   - Partido 250: Islandia1 - Senegal1, de octavos, el 20/02/2027 a las
     19:00 UTC, en "Mercedes-Benz Stadium1" (espacios 1 a 4 a 70000, 60000,
     50000 y 40000 USD).
   - Partido 251: el 21/02/2027 en "Empower Field1", sin espacios.
   - Partido 252: el 15/03/2027, cuando solo siguen vigentes las campañas 1 a 3.
   - Partido 253: Islandia1 - Senegal1, de cuartos, el 25/02/2027 en la misma
     sede que el 250.
   ============================================================================ */


/* ============================================================================
   usp_RegistrarPiezaPublicitaria
   ============================================================================ */

/* PP1 (OK) Pieza dirigida a una selección, con mercados repetidos y en minúsculas.
   Esperado: la consulta del SP muestra la pieza "Adidas Islandia", en
   español y de 20 segundos, con dos mercados: Islandia1 y Finlandia1 (el
   repetido se registra una sola vez).
   PP4 (ERROR) Título repetido: falla el alta de la pieza y no se registra ningún mercado.
   Esperado: el error 50001 lo informa Publicidad.usp_PIEZA_PUBLICITARIA_Alta;
   la cantidad de mercados de interés no cambia. */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');

EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania_1, @titulo = N'Adidas Islandia',
    @mercados = 'xpa, XPG,XPA', @codigo_idioma = 'ES', @duracion_segundos = 20;

DECLARE @antes INT = (SELECT COUNT(*) FROM Publicidad.PIEZA_PAIS_INTERES);
BEGIN TRY
    EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania_1, @titulo = N'Adidas Islandia',
        @mercados = 'XPC,XPD', @mostrar_resultados = 0;
    PRINT N'PP4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PP4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PP4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'PP4 después' AS caso, @antes AS mercados_antes, COUNT(*) AS mercados_despues FROM Publicidad.PIEZA_PAIS_INTERES;
ROLLBACK TRANSACTION;
GO

/* PP2 (ERROR) Pieza sin mercados.
   Esperado: error 50001 con 1 condición: hay que informar al menos un
   mercado de interés. */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');

BEGIN TRY
    EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania_1, @titulo = N'Adidas Islandia', @mercados = ',';
    PRINT N'PP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PP2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PP2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* PP3 (ERROR) Mercados e idioma que no existen.
   Esperado: error 50001 con 2 condiciones: los códigos de país XXX y YYY no
   existen y no existe el idioma "qq". */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');

BEGIN TRY
    EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania_1, @titulo = N'Adidas Islandia',
        @mercados = 'XPA,XXX,YYY', @codigo_idioma = 'qq';
    PRINT N'PP3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PP3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PP3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   Caso obligatorio: prime time en más de cuatro mercados y elección de cuatro piezas
   La preparación de estos casos incluye además la pieza de PP1.
   ============================================================================ */

/* SIM (OK) Simulación de prime time del partido 250 (19:00 UTC del 20/02/2027).
   Esperado: 7 países de prueba en prime time (de 19 a 23 hs locales): XPA,
   XPB y XPC a las 19, XPD y XPE a las 20, XPF y XPG a las 21; XPH (04:00) y
   XPI (14:00) quedan afuera. De ellos, 6 son mercados de interés de las
   piezas (todos menos XPB).
   PRI (OK) Piezas candidatas del partido 250, en orden de prioridad.
   Esperado: 5 candidatas (una por campaña vigente), con los mercados de las
   piezas en prime time en 6 países (más de 4), en este orden:
     1. "Adidas Islandia": dirigida a Islandia1, que juega el partido (franja 4).
     2. "Adidas Europa": franja 9 (XPC), 3 mercados en prime time.
     3. "Adidas Mixta": franja 9 (XPI), 1 mercado en prime time.
     4. "Adidas Asia": franja 8 (XPH).
     5. "Adidas Sur": franja 4 (XPE).
   La 2 y la 3 muestran el desempate por prime time dentro de la misma franja.
   REC (OK) Recargos de las piezas candidatas del partido 250 (OCTAVOS).
   Esperado: las mismas 5 piezas del PRI, con recargo por fase 20 % en todas
   (nivel 2 × RECARGO_FASE_PCT 10) y por prime time RECARGO_PRIME_TIME_PCT
   (5 %) por cada mercado de la pieza en prime time, con tope 50 %: 10 % para
   "Adidas Islandia" (XPA y XPG), 15 % para "Europa" (XPC, XPD y XPE), 5 %
   para "Mixta" (XPF), 0 para "Asia" (XPH no está en prime time) y 10 % para
   "Sur" (XPG y XPE). Total: 30, 35, 25, 20 y 30 %.
   AP1 (OK) Asignación de las cuatro piezas.
   Esperado: de las 5 candidatas se registran solo las 4 de mayor prioridad:
   la pieza de prioridad 1 en el espacio de mayor tarifa (espacio 1, 70000) y
   así sucesivamente; "Adidas Sur" queda afuera. El costo de cada una es la
   tarifa de su espacio más el recargo del REC, en USD (costo_correcto = 1 en
   las 4 filas).
   AP3 (OK) Reasignación después de cambiar la tarifa de un espacio.
   Preparación: con un UPDATE, el espacio 4 pasa a ser el más caro (999999).
   Esperado: se reemplazan las 4 exhibiciones en la misma transacción; la
   pieza de prioridad 1 queda ahora en el espacio 4, con su tarifa nueva más
   su recargo.
   AP7 (OK) Registro histórico: publicidad para un partido ya jugado que no tiene.
   Preparación: con un UPDATE, el partido 253 terminó 2 - 0, sin publicidad.
   Esperado: se registran sus 4 piezas, como en el AP1 (el 25/02/2027 siguen
   vigentes las 5 campañas).
   AP8 (OK) Todos los partidos que no tienen publicidad (si la base tiene
   otros partidos sin publicidad, también se les asigna, y se deshace con el
   resto del caso).
   Esperado: en la grilla del SP, el 251 y el 252 sin asignar, con los
   mismos motivos que el AP5 y el AP6; los demás partidos sin publicidad,
   asignados. En la de los partidos de prueba: 4 exhibiciones en el 250 y el
   253 (las que ya tenían) y 0 en el 251 y el 252.
   AP2 (ERROR) Asignar otra vez sin pedir reasignación.
   Esperado: error 50001 con 1 condición: el partido ya tiene publicidad
   asignada (para reemplazarla, @reasignar = 1). */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');
-- Pieza de PP1: "Adidas Islandia", dirigida a Islandia1 (XPA) y Finlandia1 (XPG).
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo, duracion_segundos)
SELECT @campania_1, id_idioma, N'Adidas Islandia', 20 FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es';
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT SCOPE_IDENTITY(), id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPG');

SELECT 'SIM' AS caso, pa.codigo_fifa, m.mercado, m.huso_horario, m.hora_local, m.en_prime_time, m.juega_el_partido
FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido_250) AS m
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
WHERE pa.codigo_fifa LIKE 'XP_'
ORDER BY m.en_prime_time DESC, m.hora_local, pa.codigo_fifa;
SELECT 'SIM conteo' AS caso, COUNT(*) AS paises_de_prueba_en_prime_time
FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido_250) AS m
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
WHERE pa.codigo_fifa LIKE 'XP_' AND m.en_prime_time = 1;

SELECT 'PRI' AS caso, prioridad, campania, titulo, dirigida_a_seleccion, franja_pbi,
       mercados_en_prime_time, pbi_per_capita_max, mercados_de_interes
FROM Publicidad.fn_PrioridadPiezas(@id_partido_250)
ORDER BY prioridad;

SELECT 'REC' AS caso, re.prioridad, pr.titulo, re.fase, re.nivel_fase, re.recargo_fase_pct,
       re.mercados_en_prime_time, re.recargo_prime_time_pct, re.recargo_total_pct
FROM Publicidad.fn_RecargosPublicidad(@id_partido_250) AS re
INNER JOIN Publicidad.fn_PrioridadPiezas(@id_partido_250) AS pr ON pr.id_pieza = re.id_pieza
ORDER BY re.prioridad;

SELECT 'AP1 antes' AS caso, COUNT(*) AS candidatas,
       (SELECT COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido_250) AS exhibiciones
FROM Publicidad.fn_PrioridadPiezas(@id_partido_250);
EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_250;
SELECT 'AP1 costos' AS caso, ep.numero_espacio, ep.tarifa_usd, re.recargo_total_pct, ex.costo, ex.codigo_moneda,
       IIF(ex.costo = ROUND(ep.tarifa_usd * (100 + re.recargo_total_pct) / 100.0, 2), 1, 0) AS costo_correcto
FROM Publicidad.EXHIBICION AS ex
INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS ep ON ep.id_espacio = ex.id_espacio
INNER JOIN Publicidad.fn_RecargosPublicidad(@id_partido_250) AS re ON re.id_pieza = ex.id_pieza
WHERE ex.id_partido = @id_partido_250
ORDER BY ep.numero_espacio;

UPDATE Publicidad.ESPACIO_PUBLICITARIO SET tarifa_usd = 999999 WHERE id_sede = @sede AND numero_espacio = 4;
EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_250, @reasignar = 1;

UPDATE Publicidad.ESPACIO_PUBLICITARIO SET tarifa_usd = 40000 WHERE id_sede = @sede AND numero_espacio = 4;
UPDATE Torneo.PARTIDO SET goles_local = 2, goles_visitante = 0, estado = 'FINALIZADO' WHERE id_partido = @id_partido_253;
SELECT 'AP7 antes' AS caso, estado, (SELECT COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido_253) AS exhibiciones
FROM Torneo.PARTIDO WHERE id_partido = @id_partido_253;
EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_253;

EXEC Publicidad.usp_AsignarPublicidadPartido;
SELECT 'AP8' AS caso, p.numero_partido, COUNT(ex.id_espacio) AS exhibiciones
FROM Torneo.PARTIDO AS p
LEFT JOIN Publicidad.EXHIBICION AS ex ON ex.id_partido = p.id_partido
WHERE p.numero_partido BETWEEN 250 AND 253
GROUP BY p.numero_partido
ORDER BY p.numero_partido;

BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_250;
    PRINT N'AP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* AP4 (ERROR) Reasignar la publicidad de un partido ya jugado.
   Preparación: además, el partido 250 terminó 1 - 0 con sus 4 exhibiciones
   (las piezas de las campañas 2 a 5, una por espacio, a la tarifa del espacio).
   Esperado: error 50001 con 1 condición: el partido ya empezó (FINALIZADO) y
   tiene su publicidad, que no se cambia (aunque se pida reasignar). */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');
-- Pieza de PP1: "Adidas Islandia", dirigida a Islandia1 (XPA) y Finlandia1 (XPG).
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo, duracion_segundos)
SELECT @campania_1, id_idioma, N'Adidas Islandia', 20 FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es';
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT SCOPE_IDENTITY(), id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPG');
UPDATE Torneo.PARTIDO SET goles_local = 1, goles_visitante = 0, estado = 'FINALIZADO' WHERE id_partido = @id_partido_250;
INSERT INTO Publicidad.EXHIBICION (id_partido, id_espacio, id_pieza, costo, codigo_moneda)
SELECT @id_partido_250, e.id_espacio, pz.id_pieza, e.tarifa_usd, 'USD'
FROM Publicidad.ESPACIO_PUBLICITARIO AS e
INNER JOIN (VALUES (1, N'Adidas Europa'), (2, N'Adidas Mixta'), (3, N'Adidas Asia'), (4, N'Adidas Sur')) AS v (numero_espacio, titulo)
        ON v.numero_espacio = e.numero_espacio
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
WHERE e.id_sede = @sede;

BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_250, @reasignar = 1;
    PRINT N'AP4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* AP5 (ERROR) Partido en una sede sin espacios publicitarios.
   Esperado: error 50001 con 1 condición: la sede tiene 0 espacios
   publicitarios y tienen que ser 4. */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');
-- Pieza de PP1: "Adidas Islandia", dirigida a Islandia1 (XPA) y Finlandia1 (XPG).
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo, duracion_segundos)
SELECT @campania_1, id_idioma, N'Adidas Islandia', 20 FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es';
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT SCOPE_IDENTITY(), id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPG');

BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_251;
    PRINT N'AP5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* AP6 (ERROR) Menos de cuatro piezas candidatas.
   El 15/03/2027 solo siguen vigentes las campañas 1 a 3.
   Esperado: error 50001 con 1 condición: hay 3 piezas candidatas y hacen
   falta 4. */
BEGIN TRANSACTION;
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Islandia1',       'XPA', 'Greenwich Standard Time'),
    ('Senegal1',        'XPB', 'Greenwich Standard Time'),
    ('Inglaterra1',     'XPC', 'GMT Standard Time'),
    ('Francia1',        'XPD', 'Romance Standard Time'),
    ('Alemania1',       'XPE', 'W. Europe Standard Time'),
    ('Moldavia1',       'XPF', 'E. Europe Standard Time'),
    ('Finlandia1',      'XPG', 'FLE Standard Time'),
    ('Japón1',          'XPH', 'Tokyo Standard Time'),
    ('Estados Unidos1', 'XPI', 'Eastern Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT pa.id_pais, 'NY.GDP.PCAP.CD', 2024, v.pbi
FROM (VALUES ('XPA', 20000), ('XPC', 95000), ('XPD', 52000), ('XPE', 45000), ('XPF', 15000),
             ('XPG', 41000), ('XPH', 88000), ('XPI', 93000)) AS v (codigo_fifa, pbi)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, IIF(codigo_fifa = 'XPA', 'UEFA', 'CAF') FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPB');
DECLARE @id_seleccion_isl INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPA');
DECLARE @id_seleccion_sen INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa
                        ON pa.id_pais = s.id_pais WHERE pa.codigo_fifa = 'XPB');

-- Anunciante con cinco campañas y las piezas de las campañas 2 a 5 (la de la campaña 1 la registra PP1).
DECLARE @id_pais_alemania SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPE');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Adidas1', @id_pais_alemania);
SET @anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES
    (@anunciante, N'Adidas1 Campaña 1', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 2', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 3', '2027-02-01', '2027-03-31'),
    (@anunciante, N'Adidas1 Campaña 4', '2027-02-01', '2027-02-28'),
    (@anunciante, N'Adidas1 Campaña 5', '2027-02-01', '2027-02-28');
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT c.id_campania, @id_idioma_en, v.titulo
FROM (VALUES (N'Adidas1 Campaña 2', N'Adidas Europa'), (N'Adidas1 Campaña 3', N'Adidas Mixta'),
             (N'Adidas1 Campaña 4', N'Adidas Asia'),   (N'Adidas1 Campaña 5', N'Adidas Sur')) AS v (campania, titulo)
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = v.campania;
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT pz.id_pieza, pa.id_pais
FROM (VALUES (N'Adidas Europa', 'XPC'), (N'Adidas Europa', 'XPD'), (N'Adidas Europa', 'XPE'),
             (N'Adidas Mixta', 'XPI'),  (N'Adidas Mixta', 'XPF'),  (N'Adidas Asia', 'XPH'),
             (N'Adidas Sur', 'XPG'),    (N'Adidas Sur', 'XPE')) AS v (titulo, codigo_fifa)
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.titulo = v.titulo
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa;

-- Sedes y partidos.
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @sin_espacios INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 71000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@sede, 1, 70000), (@sede, 2, 60000), (@sede, 3, 50000), (@sede, 4, 40000);
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Empower Field1', 'Denver', @id_pais_usa, 76000, 'Mountain Standard Time');
SET @sin_espacios = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (250, @sede,         'OCTAVOS', '2027-02-20 14:00', '2027-02-20 19:00', @id_seleccion_isl, @id_seleccion_sen),
    (251, @sin_espacios, 'OCTAVOS', '2027-02-21 12:00', '2027-02-21 19:00', NULL,     NULL),
    (252, @sede,         'OCTAVOS', '2027-03-15 15:00', '2027-03-15 19:00', NULL,     NULL),
    (253, @sede,         'CUARTOS', '2027-02-25 14:00', '2027-02-25 19:00', @id_seleccion_isl, @id_seleccion_sen);
DECLARE @id_partido_250 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @id_partido_251 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
DECLARE @id_partido_252 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
DECLARE @id_partido_253 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 253);
DECLARE @campania_1 INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Adidas1 Campaña 1');
-- Pieza de PP1: "Adidas Islandia", dirigida a Islandia1 (XPA) y Finlandia1 (XPG).
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo, duracion_segundos)
SELECT @campania_1, id_idioma, N'Adidas Islandia', 20 FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es';
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT SCOPE_IDENTITY(), id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XPA', 'XPG');

BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido_252;
    PRINT N'AP6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AP6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AP6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Adidas1')                AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 250 AND 253)              AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio IN ('Mercedes-Benz Stadium1', 'Empower Field1')) AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XP_')                     AS paises_de_prueba,
       @@TRANCOUNT                                                                                 AS transacciones_abiertas;
GO

SET NOEXEC OFF;
GO
