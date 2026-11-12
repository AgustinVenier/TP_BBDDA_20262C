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
 Archivo: 64_Test_SP_Negocio_Arbitraje.sql
 Objetivo: Probar los SP de 14_SP_Negocio_Arbitraje.sql (usp_RegistrarArbitro
           y usp_DesignarTernaArbitral): alta de árbitros con sus idiomas,
           designación de los cinco roles, rechazo por conflicto de
           nacionalidad (caso obligatorio) y advertencia por posible cruce
           desde dieciseisavos. Requiere haber ejecutado 01 a 28; no depende del
           juego de datos.
           Cada caso arma sus propios datos con INSERT directos a las tablas
           (ver PREPARACIÓN) y los deshace al terminar, así que se puede
           ejecutar más de una vez.
           Los casos obligatorios se prueban acá con datos propios.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
     Las advertencias de posible cruce aparecen en Mensajes y en la columna
     "advertencia" de la consulta del SP.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
 Los países de prueba se llaman como uno real con un 1 al final: así el test
 no choca con las selecciones ni los árbitros reales que se importen.

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

IF OBJECT_ID(N'Arbitraje.usp_DesignarTernaArbitral', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso IN ('en', 'fr', 'es', 'de') HAVING COUNT(*) = 4)
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ============================================================================
   PREPARACIÓN de todos los casos, con INSERT directos (no se usan los SP de
   otros scripts):
   - La sede "BC Place1" y las selecciones Argentina1, Brasil1, Francia1 e
     Inglaterra1 (sin jugadores).
   - Árbitros: Facundo Tello (de Argentina1), Wilton Sampaio (de Brasil1),
     Clément Turpin (de Francia1) y diez de Italia1, país sin selección:
     Orsato, Massa, Di Bello (de CONFEDERACION; los demás son FIFA), Mariani,
     Sozza, Chiffi, Guida, La Penna, Maresca e Irrati.
   - Partido 248 (dieciseisavos, 30/08/2026, Francia1 - Inglaterra1): con la
     terna de Chiffi, Guida, La Penna, Maresca e Irrati, terminó 1 - 0.
     Francia1 sigue en competencia.
   - Partidos 245 (Argentina1 - Brasil1) y, 18 horas después, 246 (Francia1
     - Inglaterra1), de octavos; 247, de octavos, sin selecciones definidas.
   ============================================================================ */


/* ============================================================================
   usp_RegistrarArbitro
   ============================================================================ */

/* RA1 (OK) Alta de un árbitro con dos idiomas.
   Esperado: la consulta del SP muestra a Gianluca Rocchi, de Italia1,
   categoría FIFA, con los idiomas francés e inglés.
   RA4 (ERROR) Árbitro repetido: falla el alta y no se registra ningún idioma.
   Esperado: el error 50001 lo informa Arbitraje.usp_ARBITRO_Alta; la
   cantidad de idiomas registrados de árbitros no cambia. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @id_pais_ita, @nombre = N'Gianluca', @apellido = N'Rocchi', @categoria = 'FIFA',
    @idiomas = 'en, FR', @fecha_nacimiento = '1973-08-25';

DECLARE @antes INT = (SELECT COUNT(*) FROM Arbitraje.ARBITRO_IDIOMA);
BEGIN TRY
    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @id_pais_ita, @nombre = N'Gianluca', @apellido = N'Rocchi', @categoria = 'FIFA',
        @idiomas = 'es,de', @mostrar_resultados = 0;
    PRINT N'RA4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RA4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RA4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'RA4 después' AS caso, @antes AS idiomas_antes, COUNT(*) AS idiomas_despues FROM Arbitraje.ARBITRO_IDIOMA;
ROLLBACK TRANSACTION;
GO

/* RA2 (ERROR) Sin idiomas.
   Esperado: error 50001 con 1 condición: hay que informar al menos un idioma. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

BEGIN TRY
    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @id_pais_ita, @nombre = N'Paolo', @apellido = N'Valeri',
        @categoria = 'FIFA', @idiomas = ' , ';
    PRINT N'RA2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RA2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RA2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RA3 (ERROR) Idiomas que no existen.
   Esperado: error 50001 con 1 condición que lista los códigos xx y zz. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

BEGIN TRY
    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @id_pais_ita, @nombre = N'Paolo', @apellido = N'Valeri',
        @categoria = 'FIFA', @idiomas = 'en,xx,zz';
    PRINT N'RA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RA3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RA3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_DesignarTernaArbitral
   ============================================================================ */

/* DT1 (ERROR) Caso obligatorio: designación descartada por conflicto de nacionalidad.
   En Argentina1 - Brasil1 se propone a Tello (de Argentina1) como principal
   y a Sampaio (de Brasil1) como cuarto árbitro, y a Di Bello (categoría de
   confederación) como VAR.
   Esperado: error 50001 con 3 condiciones: dos conflictos de nacionalidad y
   que el VAR tiene que ser de categoría FIFA. No queda ningún árbitro
   designado. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_245, @id_principal = @tello,
        @id_asistente_1 = @orsato, @id_asistente_2 = @massa, @id_cuarto = @sampaio, @id_var = @di_bello;
    PRINT N'DT1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'DT1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'DT1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'DT1 después' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido_245;
ROLLBACK TRANSACTION;
GO

/* DT2 (ERROR) Un árbitro en dos roles, un rol sin árbitro y un id que no existe.
   Esperado: error 50001 con 3 condiciones. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_245, @id_principal = @mariani,
        @id_asistente_1 = @mariani, @id_asistente_2 = NULL, @id_cuarto = -1, @id_var = @mariani;
    PRINT N'DT2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'DT2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'DT2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* DT3 (OK) Designación completa con una advertencia de posible cruce.
   Turpin es de Francia1, que sigue en competencia (ganó el partido 248 y
   juega el 246), así que en un partido de octavos puede cruzarse con
   Argentina1 o Brasil1.
   Esperado: se designan los cinco árbitros; en Mensajes aparece la
   advertencia y la consulta del SP marca a Turpin con "PUEDE CRUZARSE".
   DT4 (ERROR) Segunda designación para el mismo partido.
   Esperado: error 50001 con 1 condición: el partido ya tiene árbitros designados. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_245, @id_principal = @mariani,
    @id_asistente_1 = @turpin, @id_asistente_2 = @orsato, @id_cuarto = @di_bello, @id_var = @sozza;

BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_245, @id_principal = @chiffi,
        @id_asistente_1 = @guida, @id_asistente_2 = @la_penna, @id_cuarto = @maresca, @id_var = @irrati;
    PRINT N'DT4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'DT4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'DT4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* DT5 (OK) Árbitros que dirigen otro partido 18 horas antes: no hay un
   descanso mínimo entre partidos (la consigna no lo pide).
   Preparación: además, la terna del 245 que designó DT3.
   Mariani y Sozza dirigen el 245 y se designan también en el 246, 18 horas
   después.
   Esperado: la consulta del SP muestra los cinco árbitros del 246. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);
-- Terna del 245 que designó DT3.
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_245, @mariani, 'PRINCIPAL'), (@id_partido_245, @turpin, 'ASISTENTE_1'), (@id_partido_245, @orsato, 'ASISTENTE_2'),
    (@id_partido_245, @di_bello, 'CUARTO'), (@id_partido_245, @sozza, 'VAR');

EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_246, @id_principal = @mariani,
    @id_asistente_1 = @guida, @id_asistente_2 = @la_penna, @id_cuarto = @maresca, @id_var = @sozza;
ROLLBACK TRANSACTION;
GO

/* DT6a (ERROR) Partido ya jugado.
   Esperado: error 50001 con 2 condiciones: el partido 248 está FINALIZADO y
   ya tiene su terna. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_248, @id_principal = @chiffi,
        @id_asistente_1 = @guida, @id_asistente_2 = @la_penna, @id_cuarto = @maresca, @id_var = @irrati;
    PRINT N'DT6a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'DT6a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'DT6a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* DT6b (ERROR) Partido sin selecciones definidas.
   Esperado: error 50001 con 1 condición: en el 247 las dos selecciones
   tienen que estar definidas para controlar la nacionalidad. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);

BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_247, @id_principal = @chiffi,
        @id_asistente_1 = @guida, @id_asistente_2 = @la_penna, @id_cuarto = @maresca, @id_var = @irrati;
    PRINT N'DT6b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'DT6b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'DT6b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* DT7 (ERROR) Un árbitro inactivo.
   Preparación: además, Gianluca Rocchi, de Italia1, dado de baja (activo = 0).
   Se lo propone como cuarto árbitro del partido 246.
   Esperado: error 50001 con 1 condición: el árbitro no está activo. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_pais_fra SMALLINT, @id_pais_ing SMALLINT, @id_pais_ita SMALLINT;
DECLARE @id_seleccion_arg INT, @id_seleccion_bra INT, @id_seleccion_fra INT, @id_seleccion_ing INT, @sede INT, @id_partido_248 INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Francia1', 'Romance Standard Time');
SET @id_pais_fra = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Inglaterra1', 'GMT Standard Time');
SET @id_pais_ing = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Italia1', 'W. Europe Standard Time');
SET @id_pais_ita = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_arg, 'CONMEBOL');
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_bra, 'CONMEBOL');
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_fra, 'UEFA');
SET @id_seleccion_fra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_ing, 'UEFA');
SET @id_seleccion_ing = SCOPE_IDENTITY();

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo',      N'Tello',     'FIFA'),
    (@id_pais_bra, N'Wilton',       N'Sampaio',   'FIFA'),
    (@id_pais_fra, N'Clément',      N'Turpin',    'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Orsato',    'FIFA'),
    (@id_pais_ita, N'Davide',       N'Massa',     'FIFA'),
    (@id_pais_ita, N'Marco',        N'Di Bello',  'CONFEDERACION'),
    (@id_pais_ita, N'Maurizio',     N'Mariani',   'FIFA'),
    (@id_pais_ita, N'Simone',       N'Sozza',     'FIFA'),
    (@id_pais_ita, N'Daniele',      N'Chiffi',    'FIFA'),
    (@id_pais_ita, N'Marco',        N'Guida',     'FIFA'),
    (@id_pais_ita, N'Federico',     N'La Penna',  'FIFA'),
    (@id_pais_ita, N'Fabio',        N'Maresca',   'FIFA'),
    (@id_pais_ita, N'Massimiliano', N'Irrati',    'FIFA');
DECLARE @tello    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_arg);
DECLARE @sampaio  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_bra);
DECLARE @turpin   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_fra);
DECLARE @orsato   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Orsato');
DECLARE @massa    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Massa');
DECLARE @di_bello INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Di Bello');
DECLARE @mariani  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Mariani');
DECLARE @sozza    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Sozza');
DECLARE @chiffi   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Chiffi');
DECLARE @guida    INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Guida');
DECLARE @la_penna INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'La Penna');
DECLARE @maresca  INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Maresca');
DECLARE @irrati   INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @id_pais_ita AND apellido = N'Irrati');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('BC Place1', 'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (248, @sede, 'DIECISEISAVOS', '2026-08-29 19:00', '2026-08-30 02:00', @id_seleccion_fra, @id_seleccion_ing, 1, 0, 'FINALIZADO');
SET @id_partido_248 = SCOPE_IDENTITY();
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES
    (@id_partido_248, @chiffi, 'PRINCIPAL'), (@id_partido_248, @guida, 'ASISTENTE_1'), (@id_partido_248, @la_penna, 'ASISTENTE_2'),
    (@id_partido_248, @maresca, 'CUARTO'), (@id_partido_248, @irrati, 'VAR');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (245, @sede, 'OCTAVOS', '2026-09-04 19:00', '2026-09-05 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (246, @sede, 'OCTAVOS', '2026-09-05 13:00', '2026-09-05 20:00', @id_seleccion_fra, @id_seleccion_ing);
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (247, @sede, 'OCTAVOS', '2026-09-10 13:00', '2026-09-10 20:00');
DECLARE @id_partido_245 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @id_partido_246 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @id_partido_247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);
INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria, activo)
VALUES (@id_pais_ita, N'Gianluca', N'Rocchi', 'FIFA', 0);
DECLARE @rocchi INT = SCOPE_IDENTITY();

BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido_246, @id_principal = @chiffi,
        @id_asistente_1 = @guida, @id_asistente_2 = @la_penna, @id_cuarto = @rocchi, @id_var = @irrati;
    PRINT N'DT7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'DT7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'DT7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 245 AND 248)      AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS
        WHERE nombre IN ('Argentina1', 'Brasil1', 'Francia1', 'Inglaterra1', 'Italia1'))   AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'BC Place1')               AS sedes_de_prueba,
       @@TRANCOUNT                                                                         AS transacciones_abiertas;
GO

SET NOEXEC OFF;
GO
