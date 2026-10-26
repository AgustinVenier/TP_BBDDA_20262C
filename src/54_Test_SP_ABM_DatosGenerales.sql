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
 Archivo: 54_Test_SP_ABM_DatosGenerales.sql
 Objetivo: Probar los SP de 04_SP_ABM_DatosGenerales.sql. Para cada tabla hay
           casos exitosos, con la evidencia de los datos antes y después, y
           casos que no cumplen las validaciones, que deben fallar con un único
           mensaje que liste todas las condiciones incumplidas.
           Requiere haber ejecutado 00 a 20: los casos de parámetros usan los
           valores del reglamento de 20_DatosIniciales.sql, e I6, el idioma
           inglés que carga ese script. No depende del juego de
           datos: crea sus propios datos de prueba (dos países, un
           idioma, un parámetro y, para las bajas rechazadas por referencias,
           un árbitro y una sede) y los borra al empezar y al terminar con los
           SP de baja, así que se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba y los
     parámetros del reglamento sin cambios.
   - El árbitro de prueba se llama "Arbitro Prueba DatosGenerales" y la sede,
     "Estadio Prueba DatosGenerales".
 Los datos de prueba usan códigos que no son de ningún país real: XA y XAA son
 de uso privado en ISO 3166 y XTS es el código de prueba de ISO 4217; xx y xy
 no están asignados en ISO 639-1.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Si faltan los SP o los datos iniciales no se ejecuta el resto del script.
IF OBJECT_ID(N'DatosGenerales.usp_PAIS_Alta', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_SEDE_Alta', N'P') IS NULL
   OR OBJECT_ID(N'Arbitraje.usp_ARBITRO_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS')
BEGIN
    RAISERROR(N'Faltan los SP de ABM o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Procedimiento temporal (dura lo que la sesión) que se llama desde los CATCH
-- de los casos que tienen que fallar: informa si el error fue el de validación.
IF OBJECT_ID(N'tempdb..#usp_MostrarError', N'P') IS NOT NULL
    DROP PROCEDURE #usp_MostrarError;
GO
CREATE PROCEDURE #usp_MostrarError
    @caso VARCHAR(10)
AS
BEGIN
    PRINT CONCAT(@caso, N': ',
                 IIF(ERROR_NUMBER() = 50001, N'OK, falló la validación como se esperaba.',
                     CONCAT(N'FALLÓ, error inesperado ', ERROR_NUMBER(), N'.')),
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END;
GO

-- Limpieza de datos de prueba de una corrida anterior que haya quedado a medias.
-- Se usan los SP de baja; el contador evita un ciclo infinito si una baja no borrara.
DECLARE @id INT, @id_idioma SMALLINT, @vuelta INT = 0;

-- Idiomas del árbitro de prueba, el árbitro y la sede de prueba (casos I7 y P8).
WHILE @vuelta < 20
BEGIN
    SET @vuelta += 1;
    SELECT TOP (1) @id = ai.id_arbitro, @id_idioma = ai.id_idioma
    FROM Arbitraje.ARBITRO_IDIOMA AS ai
    INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = ai.id_arbitro
    WHERE a.apellido = N'Prueba DatosGenerales';
    IF @@ROWCOUNT = 0 BREAK;
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id, @id_idioma = @id_idioma;
END;

SET @vuelta = 0;
WHILE @vuelta < 20
BEGIN
    SET @vuelta += 1;
    SET @id = (SELECT TOP (1) id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba DatosGenerales');
    IF @id IS NULL BREAK;
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id, @eliminar_registro = 1;
END;

SET @id = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba DatosGenerales');
IF @id IS NOT NULL
    EXEC Torneo.usp_SEDE_Baja @id_sede = @id;

SET @vuelta = 0;
WHILE @vuelta < 20
BEGIN
    SET @vuelta += 1;
    SET @id = (SELECT TOP (1) ie.id_indicador
               FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
               INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
               WHERE p.nombre LIKE 'Pais Prueba%');
    IF @id IS NULL BREAK;
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
END;

SET @vuelta = 0;
WHILE @vuelta < 20
BEGIN
    SET @vuelta += 1;
    SET @id = (SELECT TOP (1) id_pais FROM DatosGenerales.PAIS WHERE nombre LIKE 'Pais Prueba%');
    IF @id IS NULL BREAK;
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
END;

SET @vuelta = 0;
WHILE @vuelta < 20
BEGIN
    SET @vuelta += 1;
    SET @id = (SELECT TOP (1) id_idioma FROM DatosGenerales.IDIOMA WHERE nombre LIKE 'Idioma Prueba%');
    IF @id IS NULL BREAK;
    EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id;
END;

IF EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'TEST_PARAMETRO')
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja @codigo = 'TEST_PARAMETRO';
GO


/* ============================================================================
   PAIS
   ============================================================================ */

/* P1 (OK) Alta de dos países de prueba.
   Esperado: 0 países de prueba antes y 2 después. En "Pais Prueba A" el nombre
   queda sin los espacios de los costados, los códigos en mayúsculas (ZZA, XA,
   XAA, XTS) y el huso como "Argentina Standard Time". */
DECLARE @id_a SMALLINT, @id_b SMALLINT;

SELECT 'P1 antes' AS caso, COUNT(*) AS paises_de_prueba
FROM DatosGenerales.PAIS
WHERE nombre LIKE 'Pais Prueba%';

EXEC DatosGenerales.usp_PAIS_Alta
    @nombre = '  Pais Prueba A  ', @huso_horario = 'argentina standard time',
    @codigo_fifa = 'zza', @codigo_iso2 = 'xa', @codigo_iso3 = 'xaa', @codigo_moneda = 'xts',
    @id_pais = @id_a OUTPUT;

EXEC DatosGenerales.usp_PAIS_Alta
    @nombre = 'Pais Prueba B', @huso_horario = 'Tokyo Standard Time', @codigo_fifa = 'ZZB',
    @id_pais = @id_b OUTPUT;

SELECT 'P1 después' AS caso, id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
       huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
WHERE id_pais IN (@id_a, @id_b);
GO

/* P2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 6 condiciones en un solo mensaje: nombre
   obligatorio, huso inexistente y formato inválido en los códigos FIFA,
   ISO alfa-2, ISO alfa-3 y de moneda. */
BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Alta
        @nombre = '   ', @huso_horario = 'Hora de Marte',
        @codigo_fifa = 'Z1', @codigo_iso2 = 'XYZ', @codigo_iso3 = 'X1', @codigo_moneda = 'pesos';
    PRINT N'P2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'P2';
END CATCH;
GO

/* P3 (ERROR) Alta con nombre y código FIFA que ya existen.
   Esperado: error 50001 con 2 condiciones: ya existe "Pais Prueba A" y el
   código FIFA ZZB ya lo tiene otro país. */
BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Alta
        @nombre = 'Pais Prueba A', @huso_horario = 'Argentina Standard Time', @codigo_fifa = 'ZZB';
    PRINT N'P3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'P3';
END CATCH;
GO

/* P4 (OK) Modificación parcial de "Pais Prueba A".
   Esperado: cambian el nombre (a "Pais Prueba A2"), el huso (a
   "Romance Standard Time") y la moneda (a EUR). Los códigos FIFA e ISO, que
   no se pasan, quedan como estaban. */
DECLARE @id SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A');

SELECT 'P4 antes' AS caso, id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
       huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
WHERE id_pais = @id;

EXEC DatosGenerales.usp_PAIS_Modificacion
    @id_pais = @id, @nombre = 'Pais Prueba A2', @huso_horario = 'romance standard time',
    @codigo_moneda = 'eur';

SELECT 'P4 después' AS caso, id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
       huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
WHERE id_pais = @id;
GO

/* P5 (ERROR) Modificación de un país que no existe y sin datos.
   Esperado: error 50001 con 2 condiciones: no existe un país con id -1 y no
   se indicó ningún dato para modificar. */
BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Modificacion @id_pais = -1;
    PRINT N'P5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'P5';
END CATCH;
GO

/* P6 (ERROR) Modificación de "Pais Prueba B" con datos que chocan con otro país.
   Esperado: error 50001 con 3 condiciones: ya existe otro país llamado
   "Pais Prueba A2", el código FIFA ZZA ya lo tiene otro país y el huso no
   existe. */
DECLARE @id SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba B');

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Modificacion
        @id_pais = @id, @nombre = 'Pais Prueba A2', @codigo_fifa = 'ZZA',
        @huso_horario = 'Hora de Marte';
    PRINT N'P6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'P6';
END CATCH;
GO


/* ============================================================================
   IDIOMA
   ============================================================================ */

/* I1 (OK) Alta de un idioma de prueba.
   Esperado: 0 idiomas de prueba antes y una fila nueva después, con el código
   en minúsculas ("xx"). */
DECLARE @id SMALLINT;

SELECT 'I1 antes' AS caso, COUNT(*) AS idiomas_de_prueba
FROM DatosGenerales.IDIOMA
WHERE nombre LIKE 'Idioma Prueba%';

EXEC DatosGenerales.usp_IDIOMA_Alta
    @nombre = 'Idioma Prueba', @codigo_iso = 'XX', @id_idioma = @id OUTPUT;

SELECT 'I1 después' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id;
GO

/* I2 (ERROR) Alta con nombre demasiado largo y código de 3 letras.
   Esperado: error 50001 con 2 condiciones: el nombre supera los 40
   caracteres y el código ISO 639-1 no tiene 2 letras. */
BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Alta
        @nombre = 'Idioma Prueba con un nombre que supera el máximo', @codigo_iso = 'spa';
    PRINT N'I2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'I2';
END CATCH;
GO

/* I3 (ERROR) Alta repetida.
   Esperado: error 50001 con 2 condiciones: ya existe "Idioma Prueba" y el
   código "xx" ya lo tiene otro idioma. */
BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Alta @nombre = 'Idioma Prueba', @codigo_iso = 'xx';
    PRINT N'I3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'I3';
END CATCH;
GO

/* I4 (OK) Modificación del código.
   Esperado: el código pasa de "xx" a "xy" y el nombre no cambia. */
DECLARE @id SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Idioma Prueba');

SELECT 'I4 antes' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id;

EXEC DatosGenerales.usp_IDIOMA_Modificacion @id_idioma = @id, @codigo_iso = 'XY';

SELECT 'I4 después' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id;
GO

/* I5 (ERROR) Modificación sin datos: un nombre en blanco cuenta como no informado.
   Esperado: error 50001 con 1 condición: no se indicó ningún dato para
   modificar. */
DECLARE @id SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Idioma Prueba');

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Modificacion @id_idioma = @id, @nombre = '   ';
    PRINT N'I5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'I5';
END CATCH;
GO

/* I6 (ERROR) Modificación con el nombre y el código de otro idioma.
   Esperado: error 50001 con 2 condiciones: ya existe otro idioma llamado
   "Inglés" y el código "en" ya lo tiene otro idioma. "Idioma Prueba" no
   cambia. */
DECLARE @id SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Idioma Prueba');

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Modificacion @id_idioma = @id, @nombre = 'Inglés', @codigo_iso = 'en';
    PRINT N'I6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'I6';
END CATCH;

SELECT 'I6 después' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id;
GO

/* I7 (ERROR) Baja de un idioma que habla un árbitro.
   Preparación: se da de alta el árbitro "Arbitro Prueba DatosGenerales"
   (de "Pais Prueba B") y se le registra "Idioma Prueba".
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   Arbitraje.ARBITRO_IDIOMA. El idioma de prueba sigue existiendo. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba B');
DECLARE @id SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Idioma Prueba');
DECLARE @id_arbitro INT;

EXEC Arbitraje.usp_ARBITRO_Alta
    @id_pais = @id_pais, @nombre = N'Arbitro', @apellido = N'Prueba DatosGenerales',
    @categoria = 'FIFA', @id_arbitro = @id_arbitro OUTPUT;
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id_arbitro, @id_idioma = @id;

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id;
    PRINT N'I7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'I7';
END CATCH;

SELECT 'I7 después' AS caso, i.id_idioma, i.nombre, COUNT(ai.id_arbitro) AS arbitros_que_lo_hablan
FROM DatosGenerales.IDIOMA AS i
LEFT JOIN Arbitraje.ARBITRO_IDIOMA AS ai ON ai.id_idioma = i.id_idioma
WHERE i.id_idioma = @id
GROUP BY i.id_idioma, i.nombre;
GO

/* I8 (OK) Baja del idioma de prueba, después de quitárselo al árbitro de prueba.
   Esperado: 1 idioma de prueba antes y 0 después.
   I9 (ERROR) Baja del mismo idioma otra vez.
   Esperado: error 50001 con 1 condición: no existe un idioma con ese id. */
DECLARE @id SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Idioma Prueba');
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba DatosGenerales');

EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id_arbitro, @id_idioma = @id;

SELECT 'I8 antes' AS caso, COUNT(*) AS idiomas_de_prueba
FROM DatosGenerales.IDIOMA
WHERE nombre LIKE 'Idioma Prueba%';

EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id;

SELECT 'I8 después' AS caso, COUNT(*) AS idiomas_de_prueba
FROM DatosGenerales.IDIOMA
WHERE nombre LIKE 'Idioma Prueba%';

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id;
    PRINT N'I9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'I9';
END CATCH;
GO


/* ============================================================================
   INDICADOR_ECONOMICO
   ============================================================================ */

/* E1 (OK) Alta del PBI per cápita 2024 de "Pais Prueba A2".
   Esperado: 0 indicadores del país antes y una fila nueva después, con el
   código en mayúsculas (NY.GDP.PCAP.CD). */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A2');
DECLARE @id INT;

SELECT 'E1 antes' AS caso, COUNT(*) AS indicadores_del_pais
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
    @id_pais = @id_pais, @codigo_indicador = 'ny.gdp.pcap.cd', @anio = 2024, @valor = 12345.6789,
    @id_indicador = @id OUTPUT;

SELECT 'E1 después' AS caso, ie.id_indicador, p.nombre AS pais, ie.codigo_indicador,
       ie.anio, ie.valor, ie.fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.id_indicador = @id;
GO

/* E2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: no existe un país con id -1, el
   código tiene espacios y acentos, el año 1900 está fuera de rango y falta
   el valor. */
BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
        @id_pais = -1, @codigo_indicador = 'PBI per cápita', @anio = 1900, @valor = NULL;
    PRINT N'E2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'E2';
END CATCH;
GO

/* E3 (ERROR) Alta repetida: mismo país, indicador y año.
   Esperado: error 50001 con 1 condición: ese país ya tiene un valor de
   NY.GDP.PCAP.CD para 2024. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A2');

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
        @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2024, @valor = 1;
    PRINT N'E3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'E3';
END CATCH;
GO

/* E4 (OK) Modificación del valor.
   Esperado: el valor pasa de 12345.6789 a 13000.5000; país, código y año no
   cambian y fecha_actualizacion se renueva. */
DECLARE @id INT = (SELECT ie.id_indicador
                   FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
                   WHERE p.nombre = 'Pais Prueba A2');

SELECT 'E4 antes' AS caso, id_indicador, id_pais, codigo_indicador, anio, valor, fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_indicador = @id;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion @id_indicador = @id, @valor = 13000.5;

SELECT 'E4 después' AS caso, id_indicador, id_pais, codigo_indicador, anio, valor, fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_indicador = @id;
GO

/* E5 (ERROR) Modificación con código demasiado largo y año futuro.
   Esperado: error 50001 con 2 condiciones: el código supera los 30
   caracteres y el año está fuera de rango. */
DECLARE @id INT = (SELECT ie.id_indicador
                   FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
                   WHERE p.nombre = 'Pais Prueba A2');
DECLARE @anio_futuro SMALLINT = YEAR(GETDATE()) + 1;

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion
        @id_indicador = @id, @codigo_indicador = 'NY.GDP.PCAP.CD.CODIGO.DEMASIADO.LARGO',
        @anio = @anio_futuro;
    PRINT N'E5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'E5';
END CATCH;
GO

/* E6 (ERROR) Modificación que dejaría dos valores para el mismo año.
   Preparación: el PBI per cápita 2023 de "Pais Prueba A2".
   Esperado: error 50001 con 1 condición: ese país ya tiene otro valor de
   NY.GDP.PCAP.CD para 2024. El valor de 2023 queda como estaba; después se
   borra, y el país vuelve a tener solo el de 2024. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A2');
DECLARE @id INT;
EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
    @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2023, @valor = 11850.25,
    @id_indicador = @id OUTPUT;

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion @id_indicador = @id, @anio = 2024;
    PRINT N'E6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'E6';
END CATCH;

SELECT 'E6 después' AS caso, id_indicador, anio, valor
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais
ORDER BY anio;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
GO

/* P7 (ERROR) Baja de un país que todavía tiene indicadores.
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   DatosGenerales.INDICADOR_ECONOMICO. El país sigue existiendo. */
DECLARE @id SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A2');

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    PRINT N'P7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'P7';
END CATCH;

SELECT 'P7 después' AS caso, id_pais, nombre
FROM DatosGenerales.PAIS
WHERE id_pais = @id;
GO

/* E7 (OK) Baja del indicador.
   Esperado: 1 indicador del país de prueba antes y 0 después.
   E8 (ERROR) Baja del mismo indicador otra vez.
   Esperado: error 50001 con 1 condición: no existe un indicador con ese id. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A2');
DECLARE @id INT = (SELECT id_indicador FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_pais = @id_pais);

SELECT 'E7 antes' AS caso, COUNT(*) AS indicadores_del_pais
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;

SELECT 'E7 después' AS caso, COUNT(*) AS indicadores_del_pais
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais;

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
    PRINT N'E8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'E8';
END CATCH;
GO

/* P8 (ERROR) Baja de un país referenciado desde varias tablas.
   Preparación: se da de alta la sede "Estadio Prueba DatosGenerales" en
   "Pais Prueba B", que ya tiene el árbitro de prueba de I7.
   Esperado: error 50001 que lista, en un solo mensaje, 2 condiciones: lo
   referencian 1 registro de Torneo.SEDE y 1 de Arbitraje.ARBITRO. El país
   sigue existiendo. Después se borran la sede y el árbitro de prueba. */
DECLARE @id SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba B');
DECLARE @id_sede INT;
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba DatosGenerales');

EXEC Torneo.usp_SEDE_Alta
    @nombre_estadio = 'Estadio Prueba DatosGenerales', @ciudad = 'Ciudad Prueba', @id_pais = @id,
    @capacidad = 10000, @huso_horario = 'Tokyo Standard Time', @id_sede = @id_sede OUTPUT;

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    PRINT N'P8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'P8';
END CATCH;

SELECT 'P8 después' AS caso, id_pais, nombre
FROM DatosGenerales.PAIS
WHERE id_pais = @id;

EXEC Torneo.usp_SEDE_Baja @id_sede = @id_sede;
EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro, @eliminar_registro = 1;
GO

/* P9 (OK) Baja de los dos países de prueba, que ya no tienen referencias.
   Esperado: 2 países de prueba antes y 0 después. */
DECLARE @id_a SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba A2');
DECLARE @id_b SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Pais Prueba B');

SELECT 'P9 antes' AS caso, COUNT(*) AS paises_de_prueba
FROM DatosGenerales.PAIS
WHERE nombre LIKE 'Pais Prueba%';

EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_a;
EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_b;

SELECT 'P9 después' AS caso, COUNT(*) AS paises_de_prueba
FROM DatosGenerales.PAIS
WHERE nombre LIKE 'Pais Prueba%';
GO


/* ============================================================================
   PARAMETRO_REGLAMENTO
   ============================================================================ */

/* R1 (OK) Alta de un parámetro de prueba.
   Esperado: 0 antes y una fila nueva después, con el código en mayúsculas
   (TEST_PARAMETRO) y valor 3. */
SELECT 'R1 antes' AS caso, COUNT(*) AS parametros_de_prueba
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo = 'TEST_PARAMETRO';

EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta
    @codigo = 'test_parametro', @descripcion = 'Parámetro creado por el script de testing', @valor = 3;

SELECT 'R1 después' AS caso, codigo, descripcion, valor, fecha_modificacion
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo = 'TEST_PARAMETRO';
GO

/* R2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 3 condiciones: el código tiene un guion y un
   espacio, falta la descripción y falta el valor. */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta
        @codigo = 'TEST-PARAM X', @descripcion = '   ', @valor = NULL;
    PRINT N'R2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R2';
END CATCH;
GO

/* R3 (ERROR) Alta repetida.
   Esperado: error 50001 con 1 condición: ya existe el parámetro
   TEST_PARAMETRO. */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta
        @codigo = 'TEST_PARAMETRO', @descripcion = 'Otra descripción', @valor = 1;
    PRINT N'R3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R3';
END CATCH;
GO

/* R4 (OK) Modificación del valor.
   Esperado: el valor pasa de 3 a 5, la descripción no cambia y
   fecha_modificacion se renueva. */
SELECT 'R4 antes' AS caso, codigo, descripcion, valor, fecha_modificacion
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo = 'TEST_PARAMETRO';

EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'TEST_PARAMETRO', @valor = 5;

SELECT 'R4 después' AS caso, codigo, descripcion, valor, fecha_modificacion
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo = 'TEST_PARAMETRO';
GO

/* R5 (ERROR) MIN_CONVOCADOS mayor que MAX_CONVOCADOS.
   Esperado: error 50001 con 1 condición: MIN_CONVOCADOS (30) no puede
   superar a MAX_CONVOCADOS (26). Los dos parámetros quedan como estaban. */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'MIN_CONVOCADOS', @valor = 30;
    PRINT N'R5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R5';
END CATCH;

SELECT 'R5 después' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('MIN_CONVOCADOS', 'MAX_CONVOCADOS')
ORDER BY codigo;
GO

/* R6 (ERROR) MAX_CAMBIOS menor que MAX_VENTANAS: el control de pares también
   funciona cuando se modifica el segundo parámetro.
   Esperado: error 50001 con 1 condición: MAX_VENTANAS (3) no puede superar a
   MAX_CAMBIOS (2). */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'MAX_CAMBIOS', @valor = 2;
    PRINT N'R6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R6';
END CATCH;
GO

/* R7 (ERROR) Valores fuera del rango de los parámetros del sistema.
   Esperado: dos errores 50001. R7a con 1 condición: PRIME_TIME_DESDE admite
   valores entre 0 y 23. R7b con 1 condición: PRIME_TIME_DESDE y
   PRIME_TIME_HASTA no pueden tener el mismo valor (23). */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'PRIME_TIME_DESDE', @valor = 30;
    PRINT N'R7a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R7a';
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'PRIME_TIME_DESDE', @valor = 23;
    PRINT N'R7b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R7b';
END CATCH;
GO

/* R8 (ERROR) Modificación de un parámetro que no existe y sin datos.
   Esperado: error 50001 con 2 condiciones: no existe el parámetro NO_EXISTE
   y no se indicó ningún dato para modificar. */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'no_existe';
    PRINT N'R8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R8';
END CATCH;
GO

/* R9 (ERROR) Baja de un parámetro que usa el sistema.
   Esperado: error 50001 con 1 condición: MAX_CAMBIOS lo usa el sistema y se
   puede modificar, pero no eliminar. */
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja @codigo = 'MAX_CAMBIOS';
    PRINT N'R9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'R9';
END CATCH;
GO

/* R10 (OK) Baja del parámetro de prueba.
   Esperado: 1 antes y 0 después. */
SELECT 'R10 antes' AS caso, COUNT(*) AS parametros_de_prueba
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo = 'TEST_PARAMETRO';

EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja @codigo = 'TEST_PARAMETRO';

SELECT 'R10 después' AS caso, COUNT(*) AS parametros_de_prueba
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo = 'TEST_PARAMETRO';
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en las cinco columnas de datos de prueba, y los parámetros del
   reglamento con sus valores originales (MAX_CAMBIOS 5, MAX_CONVOCADOS 26,
   MAX_VENTANAS 3, MIN_CONVOCADOS 23, PRIME_TIME_DESDE 19).
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre LIKE 'Pais Prueba%')     AS paises_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IDIOMA WHERE nombre LIKE 'Idioma Prueba%') AS idiomas_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PARAMETRO_REGLAMENTO
        WHERE codigo = 'TEST_PARAMETRO')                                              AS parametros_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO
        WHERE apellido = N'Prueba DatosGenerales')                                    AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE
        WHERE nombre_estadio = 'Estadio Prueba DatosGenerales')                       AS sedes_de_prueba;

SELECT 'Final' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('MIN_CONVOCADOS', 'MAX_CONVOCADOS', 'MAX_CAMBIOS', 'MAX_VENTANAS', 'PRIME_TIME_DESDE')
ORDER BY codigo;
GO

SET NOEXEC OFF;
GO
