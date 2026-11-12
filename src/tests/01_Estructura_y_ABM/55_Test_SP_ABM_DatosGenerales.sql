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
 Archivo: 55_Test_SP_ABM_DatosGenerales.sql
 Objetivo: Probar los SP de 05_SP_ABM_DatosGenerales.sql. Para cada tabla hay
           casos exitosos, con la evidencia de los datos antes y después, y
           casos que no cumplen las validaciones, que deben fallar con un único
           mensaje que liste todas las condiciones incumplidas.
           Requiere haber ejecutado 01 a 28: los casos de parámetros usan los
           valores del reglamento de 28_Cargar_DatosIniciales.sql, e I6, el idioma
           inglés que carga ese script. No depende del juego de
           datos: crea sus propios datos de prueba (dos países, un
           idioma, un parámetro, una cotización, un feriado y, para las bajas
           rechazadas por referencias, un árbitro y una sede). Corre dentro
           de una transacción que se deshace al final, así que no deja datos
           y se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba y los
     parámetros del reglamento sin cambios. Si no da 0, quedó algo sin
     deshacer.
   - El árbitro de prueba es Yoshimi Yamashita, de Japón1, y la sede, el
     "Estadio Nacional1" de Tokio; se cargan con INSERT directos (no son de
     este script).
 Los datos de prueba usan códigos que no son de ningún país real: XA y XAA son
 de uso privado en ISO 3166 y XTS es el código de prueba de ISO 4217; xx y xy
 no están asignados en ISO 639-1.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

-- Si faltan los SP o los datos iniciales no se ejecuta el resto del script.
IF OBJECT_ID(N'DatosGenerales.usp_PAIS_Alta', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_SEDE_Alta', N'P') IS NULL
   OR OBJECT_ID(N'Arbitraje.usp_ARBITRO_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS')
BEGIN
    RAISERROR(N'Faltan los SP de ABM o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Procedimiento temporal (dura lo que la sesión) que se llama desde los CATCH
-- de los casos que tienen que fallar: informa si el error fue el de validación.
-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
BEGIN TRANSACTION;
GO


/* ============================================================================
   PAIS
   ============================================================================ */

/* P1 (OK) Alta de dos países de prueba.
   Esperado: 0 países de prueba antes y 2 después. En "Argentina1" el nombre
   queda sin los espacios de los costados, los códigos en mayúsculas (ZZA, XA,
   XAA, XTS) y el huso como "Argentina Standard Time". */
DECLARE @id_pais_arg SMALLINT, @id_pais_jpn SMALLINT;

SELECT 'P1 antes' AS caso, COUNT(*) AS paises_de_prueba
FROM DatosGenerales.PAIS
WHERE nombre IN ('Argentina1', 'República Argentina1', 'Japón1');

EXEC DatosGenerales.usp_PAIS_Alta
    @nombre = '  Argentina1  ', @huso_horario = 'argentina standard time',
    @codigo_fifa = 'zza', @codigo_iso2 = 'xa', @codigo_iso3 = 'xaa', @codigo_moneda = 'xts',
    @id_pais = @id_pais_arg OUTPUT;

EXEC DatosGenerales.usp_PAIS_Alta
    @nombre = 'Japón1', @huso_horario = 'Tokyo Standard Time', @codigo_fifa = 'ZZB',
    @id_pais = @id_pais_jpn OUTPUT;

SELECT 'P1 después' AS caso, id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
       huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
WHERE id_pais IN (@id_pais_arg, @id_pais_jpn);
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
    IF ERROR_NUMBER() = 50001
        PRINT N'P2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* P3 (ERROR) Alta con nombre y código FIFA que ya existen.
   Esperado: error 50001 con 2 condiciones: ya existe "Argentina1" y el
   código FIFA ZZB ya lo tiene otro país. */
BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Alta
        @nombre = 'Argentina1', @huso_horario = 'Argentina Standard Time', @codigo_fifa = 'ZZB';
    PRINT N'P3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'P3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* P4 (OK) Modificación parcial de "Argentina1".
   Esperado: cambian el nombre (a "República Argentina1"), el huso (a
   "Romance Standard Time") y la moneda (a EUR). Los códigos FIFA e ISO, que
   no se pasan, quedan como estaban. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Argentina1');

SELECT 'P4 antes' AS caso, id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
       huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_PAIS_Modificacion
    @id_pais = @id_pais, @nombre = 'República Argentina1', @huso_horario = 'romance standard time',
    @codigo_moneda = 'eur';

SELECT 'P4 después' AS caso, id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
       huso_horario, codigo_moneda
FROM DatosGenerales.PAIS
WHERE id_pais = @id_pais;
GO

/* P5 (ERROR) Modificación de un país que no existe y sin datos.
   Esperado: error 50001 con 2 condiciones: no existe un país con id -1 y no
   se indicó ningún dato para modificar. */
BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Modificacion @id_pais = -1;
    PRINT N'P5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'P5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* P6 (ERROR) Modificación de "Japón1" con datos que chocan con otro país.
   Esperado: error 50001 con 3 condiciones: ya existe otro país llamado
   "República Argentina1", el código FIFA ZZA ya lo tiene otro país y el huso no
   existe. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Japón1');

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Modificacion
        @id_pais = @id_pais, @nombre = 'República Argentina1', @codigo_fifa = 'ZZA',
        @huso_horario = 'Hora de Marte';
    PRINT N'P6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'P6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   IDIOMA
   ============================================================================ */

/* I1 (OK) Alta de un idioma de prueba.
   Esperado: 0 idiomas de prueba antes y una fila nueva después, con el código
   en minúsculas ("xx"). */
DECLARE @id_idioma SMALLINT;

SELECT 'I1 antes' AS caso, COUNT(*) AS idiomas_de_prueba
FROM DatosGenerales.IDIOMA
WHERE nombre LIKE 'Guaraní1%';

EXEC DatosGenerales.usp_IDIOMA_Alta
    @nombre = 'Guaraní1', @codigo_iso = 'XX', @id_idioma = @id_idioma OUTPUT;

SELECT 'I1 después' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id_idioma;
GO

/* I2 (ERROR) Alta con nombre demasiado largo y código de 3 letras.
   Esperado: error 50001 con 2 condiciones: el nombre supera los 40
   caracteres y el código ISO 639-1 no tiene 2 letras. */
BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Alta
        @nombre = 'Guaraní1 con un nombre que supera el máximo', @codigo_iso = 'spa';
    PRINT N'I2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'I2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'I2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* I3 (ERROR) Alta repetida.
   Esperado: error 50001 con 2 condiciones: ya existe "Guaraní1" y el
   código "xx" ya lo tiene otro idioma. */
BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Alta @nombre = 'Guaraní1', @codigo_iso = 'xx';
    PRINT N'I3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'I3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'I3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* I4 (OK) Modificación del código.
   Esperado: el código pasa de "xx" a "xy" y el nombre no cambia. */
DECLARE @id_idioma SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Guaraní1');

SELECT 'I4 antes' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id_idioma;

EXEC DatosGenerales.usp_IDIOMA_Modificacion @id_idioma = @id_idioma, @codigo_iso = 'XY';

SELECT 'I4 después' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id_idioma;
GO

/* I5 (ERROR) Modificación sin datos: un nombre en blanco cuenta como no informado.
   Esperado: error 50001 con 1 condición: no se indicó ningún dato para
   modificar. */
DECLARE @id_idioma SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Guaraní1');

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Modificacion @id_idioma = @id_idioma, @nombre = '   ';
    PRINT N'I5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'I5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'I5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* I6 (ERROR) Modificación con el nombre y el código de otro idioma.
   Esperado: error 50001 con 2 condiciones: ya existe otro idioma llamado
   "Inglés" y el código "en" ya lo tiene otro idioma. "Guaraní1" no
   cambia. */
DECLARE @id_idioma SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Guaraní1');

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Modificacion @id_idioma = @id_idioma, @nombre = 'Inglés', @codigo_iso = 'en';
    PRINT N'I6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'I6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'I6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT 'I6 después' AS caso, id_idioma, nombre, codigo_iso
FROM DatosGenerales.IDIOMA
WHERE id_idioma = @id_idioma;
GO

/* I7 (ERROR) Baja de un idioma que habla un árbitro.
   Preparación: con INSERT, la árbitra Yoshimi Yamashita (de Japón1),
   que habla "Guaraní1".
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   Arbitraje.ARBITRO_IDIOMA. El idioma de prueba sigue existiendo. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Japón1');
DECLARE @id_idioma SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Guaraní1');
DECLARE @id_arbitro INT;

INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES (@id_pais, N'Yoshimi', N'Yamashita', 'FIFA');
SET @id_arbitro = SCOPE_IDENTITY();
INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma) VALUES (@id_arbitro, @id_idioma);

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id_idioma;
    PRINT N'I7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'I7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'I7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT 'I7 después' AS caso, i.id_idioma, i.nombre, COUNT(ai.id_arbitro) AS arbitros_que_lo_hablan
FROM DatosGenerales.IDIOMA AS i
LEFT JOIN Arbitraje.ARBITRO_IDIOMA AS ai ON ai.id_idioma = i.id_idioma
WHERE i.id_idioma = @id_idioma
GROUP BY i.id_idioma, i.nombre;
GO

/* I8 (OK) Baja del idioma de prueba, después de quitárselo al árbitro de prueba.
   Esperado: 1 idioma de prueba antes y 0 después.
   I9 (ERROR) Baja del mismo idioma otra vez.
   Esperado: error 50001 con 1 condición: no existe un idioma con ese id. */
DECLARE @id_idioma SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE nombre = 'Guaraní1');
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Yoshimi' AND apellido = N'Yamashita');

DELETE FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro AND id_idioma = @id_idioma;

SELECT 'I8 antes' AS caso, COUNT(*) AS idiomas_de_prueba
FROM DatosGenerales.IDIOMA
WHERE nombre LIKE 'Guaraní1%';

EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id_idioma;

SELECT 'I8 después' AS caso, COUNT(*) AS idiomas_de_prueba
FROM DatosGenerales.IDIOMA
WHERE nombre LIKE 'Guaraní1%';

BEGIN TRY
    EXEC DatosGenerales.usp_IDIOMA_Baja @id_idioma = @id_idioma;
    PRINT N'I9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'I9: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'I9: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   INDICADOR_ECONOMICO
   ============================================================================ */

/* E1 (OK) Alta del PBI per cápita 2024 de "República Argentina1".
   Esperado: 0 indicadores del país antes y una fila nueva después, con el
   código en mayúsculas (NY.GDP.PCAP.CD). */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');
DECLARE @id_indicador INT;

SELECT 'E1 antes' AS caso, COUNT(*) AS indicadores_del_pais
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
    @id_pais = @id_pais, @codigo_indicador = 'ny.gdp.pcap.cd', @anio = 2024, @valor = 12345.6789,
    @id_indicador = @id_indicador OUTPUT;

SELECT 'E1 después' AS caso, ie.id_indicador, p.nombre AS pais, ie.codigo_indicador,
       ie.anio, ie.valor, ie.fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE ie.id_indicador = @id_indicador;
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
    IF ERROR_NUMBER() = 50001
        PRINT N'E2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'E2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* E3 (ERROR) Alta repetida: mismo país, indicador y año.
   Esperado: error 50001 con 1 condición: ese país ya tiene un valor de
   NY.GDP.PCAP.CD para 2024. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
        @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2024, @valor = 1;
    PRINT N'E3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'E3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'E3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* E4 (OK) Modificación del valor.
   Esperado: el valor pasa de 12345.6789 a 13000.5000; país, código y año no
   cambian y fecha_actualizacion se renueva. */
DECLARE @id_indicador INT = (SELECT ie.id_indicador
                   FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
                   WHERE p.nombre = 'República Argentina1');

SELECT 'E4 antes' AS caso, id_indicador, id_pais, codigo_indicador, anio, valor, fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_indicador = @id_indicador;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion @id_indicador = @id_indicador, @valor = 13000.5;

SELECT 'E4 después' AS caso, id_indicador, id_pais, codigo_indicador, anio, valor, fecha_actualizacion
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_indicador = @id_indicador;
GO

/* E5 (ERROR) Modificación con código demasiado largo y año futuro.
   Esperado: error 50001 con 2 condiciones: el código supera los 30
   caracteres y el año está fuera de rango. */
DECLARE @id_indicador INT = (SELECT ie.id_indicador
                   FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
                   WHERE p.nombre = 'República Argentina1');
DECLARE @anio_futuro SMALLINT = YEAR(GETDATE()) + 1;

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion
        @id_indicador = @id_indicador, @codigo_indicador = 'NY.GDP.PCAP.CD.CODIGO.DEMASIADO.LARGO',
        @anio = @anio_futuro;
    PRINT N'E5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'E5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'E5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* E6 (ERROR) Modificación que dejaría dos valores para el mismo año.
   Preparación: el PBI per cápita 2023 de "República Argentina1".
   Esperado: error 50001 con 1 condición: ese país ya tiene otro valor de
   NY.GDP.PCAP.CD para 2024. El valor de 2023 queda como estaba; después se
   borra, y el país vuelve a tener solo el de 2024. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');
DECLARE @id_indicador INT;
EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
    @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2023, @valor = 11850.25,
    @id_indicador = @id_indicador OUTPUT;

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Modificacion @id_indicador = @id_indicador, @anio = 2024;
    PRINT N'E6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'E6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'E6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT 'E6 después' AS caso, id_indicador, anio, valor
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais
ORDER BY anio;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id_indicador;
GO

/* P7 (ERROR) Baja de un país que todavía tiene indicadores.
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   DatosGenerales.INDICADOR_ECONOMICO. El país sigue existiendo. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_pais;
    PRINT N'P7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'P7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT 'P7 después' AS caso, id_pais, nombre
FROM DatosGenerales.PAIS
WHERE id_pais = @id_pais;
GO

/* E7 (OK) Baja del indicador.
   Esperado: 1 indicador del país de prueba antes y 0 después.
   E8 (ERROR) Baja del mismo indicador otra vez.
   Esperado: error 50001 con 1 condición: no existe un indicador con ese id. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');
DECLARE @id_indicador INT = (SELECT id_indicador FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_pais = @id_pais);

SELECT 'E7 antes' AS caso, COUNT(*) AS indicadores_del_pais
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id_indicador;

SELECT 'E7 después' AS caso, COUNT(*) AS indicadores_del_pais
FROM DatosGenerales.INDICADOR_ECONOMICO
WHERE id_pais = @id_pais;

BEGIN TRY
    EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id_indicador;
    PRINT N'E8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'E8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'E8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   COTIZACION
   Usa XTS, el código de prueba de ISO 4217.
   ============================================================================ */

/* C1 (OK) Alta de la cotización de XTS del 11/06/2026.
   Esperado: 0 cotizaciones de XTS antes y una fila nueva después, con la
   moneda en mayúsculas y 1234.500000 unidades por dólar. */
DECLARE @id_cotizacion INT;

SELECT 'C1 antes' AS caso, COUNT(*) AS cotizaciones_de_prueba
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda = 'XTS';

EXEC DatosGenerales.usp_COTIZACION_Alta
    @codigo_moneda = ' xts ', @fecha = '2026-06-11', @unidades_por_usd = 1234.5, @id_cotizacion = @id_cotizacion OUTPUT;

SELECT 'C1 después' AS caso, id_cotizacion, codigo_moneda, fecha, unidades_por_usd, fecha_actualizacion
FROM DatosGenerales.COTIZACION
WHERE id_cotizacion = @id_cotizacion;
GO

/* C2 (ERROR) Alta con todos los datos mal, y alta del dólar.
   Esperado: dos errores 50001. C2a con 3 condiciones: la moneda no tiene 3
   letras, la fecha es futura y las unidades por dólar no son mayores que
   cero. C2b con 1 condición: el dólar no lleva cotización. */
DECLARE @manana DATE = DATEADD(DAY, 1, CONVERT(DATE, GETDATE()));

BEGIN TRY
    EXEC DatosGenerales.usp_COTIZACION_Alta @codigo_moneda = 'US1', @fecha = @manana, @unidades_por_usd = 0;
    PRINT N'C2a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C2a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C2a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_COTIZACION_Alta @codigo_moneda = 'usd', @fecha = '2026-06-11', @unidades_por_usd = 1;
    PRINT N'C2b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C2b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C2b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* C3 (ERROR) Alta repetida: misma moneda y fecha.
   Esperado: error 50001 con 1 condición: XTS ya tiene una cotización para el
   11/06/2026. */
BEGIN TRY
    EXEC DatosGenerales.usp_COTIZACION_Alta @codigo_moneda = 'XTS', @fecha = '2026-06-11', @unidades_por_usd = 1;
    PRINT N'C3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* C4 (OK) Modificación de las unidades por dólar.
   Esperado: pasan de 1234.500000 a 1250.750000; la moneda y la fecha no
   cambian y fecha_actualizacion se renueva. */
DECLARE @id_cotizacion INT = (SELECT id_cotizacion FROM DatosGenerales.COTIZACION WHERE codigo_moneda = 'XTS');

SELECT 'C4 antes' AS caso, id_cotizacion, codigo_moneda, fecha, unidades_por_usd, fecha_actualizacion
FROM DatosGenerales.COTIZACION
WHERE id_cotizacion = @id_cotizacion;

EXEC DatosGenerales.usp_COTIZACION_Modificacion @id_cotizacion = @id_cotizacion, @unidades_por_usd = 1250.75;

SELECT 'C4 después' AS caso, id_cotizacion, codigo_moneda, fecha, unidades_por_usd, fecha_actualizacion
FROM DatosGenerales.COTIZACION
WHERE id_cotizacion = @id_cotizacion;
GO

/* C5 (ERROR) Modificación de una cotización que no existe y sin datos.
   Esperado: error 50001 con 2 condiciones: no existe una cotización con id
   -1 y no se indicó ningún dato para modificar. */
BEGIN TRY
    EXEC DatosGenerales.usp_COTIZACION_Modificacion @id_cotizacion = -1;
    PRINT N'C5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* C6 (OK) Baja de la cotización.
   Esperado: 1 cotización de XTS antes y 0 después.
   C7 (ERROR) Baja de la misma cotización otra vez.
   Esperado: error 50001 con 1 condición: no existe una cotización con ese id. */
DECLARE @id_cotizacion INT = (SELECT id_cotizacion FROM DatosGenerales.COTIZACION WHERE codigo_moneda = 'XTS');

SELECT 'C6 antes' AS caso, COUNT(*) AS cotizaciones_de_prueba
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda = 'XTS';

EXEC DatosGenerales.usp_COTIZACION_Baja @id_cotizacion = @id_cotizacion;

SELECT 'C6 después' AS caso, COUNT(*) AS cotizaciones_de_prueba
FROM DatosGenerales.COTIZACION
WHERE codigo_moneda = 'XTS';

BEGIN TRY
    EXEC DatosGenerales.usp_COTIZACION_Baja @id_cotizacion = @id_cotizacion;
    PRINT N'C7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   FERIADO
   ============================================================================ */

/* F1 (OK) Alta de un feriado de "República Argentina1" el 20/06/2026.
   Esperado: 0 feriados del país antes y una fila nueva después, con el
   nombre sin los espacios de los costados. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');
DECLARE @id_feriado INT;

SELECT 'F1 antes' AS caso, COUNT(*) AS feriados_del_pais
FROM DatosGenerales.FERIADO
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_FERIADO_Alta
    @id_pais = @id_pais, @fecha = '2026-06-20', @nombre = N'  Día de la Bandera  ', @id_feriado = @id_feriado OUTPUT;

SELECT 'F1 después' AS caso, f.id_feriado, p.nombre AS pais, f.fecha, f.nombre, f.fecha_actualizacion
FROM DatosGenerales.FERIADO AS f
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
WHERE f.id_feriado = @id_feriado;
GO

/* F2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 3 condiciones: no existe un país con id -1, la
   fecha es obligatoria y el nombre supera los 200 caracteres. */
DECLARE @nombre_largo NVARCHAR(400) = REPLICATE(N'x', 201);

BEGIN TRY
    EXEC DatosGenerales.usp_FERIADO_Alta @id_pais = -1, @fecha = NULL, @nombre = @nombre_largo;
    PRINT N'F2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* F3 (ERROR) Alta repetida: mismo país y fecha, con otro nombre.
   Esperado: error 50001 con 1 condición: ese país ya tiene un feriado el
   20/06/2026. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');

BEGIN TRY
    EXEC DatosGenerales.usp_FERIADO_Alta @id_pais = @id_pais, @fecha = '2026-06-20', @nombre = N'Otro feriado';
    PRINT N'F3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* F4 (OK) Modificación del nombre, para registrar dos feriados del mismo día.
   Esperado: el nombre pasa a "Día de la Bandera / Paso a la Inmortalidad de Belgrano"; el país y la
   fecha no cambian y fecha_actualizacion se renueva. */
DECLARE @id_feriado INT = (SELECT f.id_feriado
                   FROM DatosGenerales.FERIADO AS f
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
                   WHERE p.nombre = 'República Argentina1');

SELECT 'F4 antes' AS caso, id_feriado, id_pais, fecha, nombre, fecha_actualizacion
FROM DatosGenerales.FERIADO
WHERE id_feriado = @id_feriado;

EXEC DatosGenerales.usp_FERIADO_Modificacion @id_feriado = @id_feriado, @nombre = N'Día de la Bandera / Paso a la Inmortalidad de Belgrano';

SELECT 'F4 después' AS caso, id_feriado, id_pais, fecha, nombre, fecha_actualizacion
FROM DatosGenerales.FERIADO
WHERE id_feriado = @id_feriado;
GO

/* F5 (ERROR) Modificación de un feriado que no existe, a un país que no
   existe y con nombre en blanco (cuenta como no informado).
   Esperado: error 50001 con 2 condiciones: no existe un feriado con id -1 y
   no existe un país con id -1. */
BEGIN TRY
    EXEC DatosGenerales.usp_FERIADO_Modificacion @id_feriado = -1, @id_pais = -1, @nombre = N'   ';
    PRINT N'F5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* P10 (ERROR) Baja de un país que todavía tiene feriados.
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   DatosGenerales.FERIADO. El país sigue existiendo. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_pais;
    PRINT N'P10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'P10: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P10: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT 'P10 después' AS caso, id_pais, nombre
FROM DatosGenerales.PAIS
WHERE id_pais = @id_pais;
GO

/* F6 (OK) Baja del feriado.
   Esperado: 1 feriado del país de prueba antes y 0 después.
   F7 (ERROR) Baja del mismo feriado otra vez.
   Esperado: error 50001 con 1 condición: no existe un feriado con ese id. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');
DECLARE @id_feriado INT = (SELECT id_feriado FROM DatosGenerales.FERIADO WHERE id_pais = @id_pais);

SELECT 'F6 antes' AS caso, COUNT(*) AS feriados_del_pais
FROM DatosGenerales.FERIADO
WHERE id_pais = @id_pais;

EXEC DatosGenerales.usp_FERIADO_Baja @id_feriado = @id_feriado;

SELECT 'F6 después' AS caso, COUNT(*) AS feriados_del_pais
FROM DatosGenerales.FERIADO
WHERE id_pais = @id_pais;

BEGIN TRY
    EXEC DatosGenerales.usp_FERIADO_Baja @id_feriado = @id_feriado;
    PRINT N'F7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'F7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'F7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* P8 (ERROR) Baja de un país referenciado desde varias tablas.
   Preparación: con un INSERT, la sede "Estadio Nacional1" en Japón1, que
   ya tiene la árbitra de I7.
   Esperado: error 50001 que lista, en un solo mensaje, 2 condiciones: lo
   referencian 1 registro de Torneo.SEDE y 1 de Arbitraje.ARBITRO. El país
   sigue existiendo. Después se borran la sede y la árbitra con DELETE. */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Japón1');
DECLARE @id_sede INT;
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Yoshimi' AND apellido = N'Yamashita');

INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Estadio Nacional1', 'Tokio', @id_pais, 68000, 'Tokyo Standard Time');
SET @id_sede = SCOPE_IDENTITY();

BEGIN TRY
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_pais;
    PRINT N'P8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'P8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'P8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT 'P8 después' AS caso, id_pais, nombre
FROM DatosGenerales.PAIS
WHERE id_pais = @id_pais;

DELETE FROM Torneo.SEDE WHERE id_sede = @id_sede;
DELETE FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
GO

/* P9 (OK) Baja de los dos países de prueba, que ya no tienen referencias.
   Esperado: 2 países de prueba antes y 0 después. */
DECLARE @id_pais_arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'República Argentina1');
DECLARE @id_pais_jpn SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Japón1');

SELECT 'P9 antes' AS caso, COUNT(*) AS paises_de_prueba
FROM DatosGenerales.PAIS
WHERE nombre IN ('Argentina1', 'República Argentina1', 'Japón1');

EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_pais_arg;
EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_pais_jpn;

SELECT 'P9 después' AS caso, COUNT(*) AS paises_de_prueba
FROM DatosGenerales.PAIS
WHERE nombre IN ('Argentina1', 'República Argentina1', 'Japón1');
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R7a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R7a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'PRIME_TIME_DESDE', @valor = 23;
    PRINT N'R7b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'R7b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R7b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
    IF ERROR_NUMBER() = 50001
        PRINT N'R9: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'R9: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
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
   Esperado: 0 en las siete columnas de datos de prueba, y los parámetros del
   reglamento con sus valores originales (MAX_CAMBIOS 5, MAX_CONVOCADOS 26,
   MAX_VENTANAS 3, MIN_CONVOCADOS 23, PRIME_TIME_DESDE 19).
   ============================================================================ */
ROLLBACK TRANSACTION;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'República Argentina1', 'Japón1'))     AS paises_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IDIOMA WHERE nombre LIKE 'Guaraní1%') AS idiomas_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PARAMETRO_REGLAMENTO
        WHERE codigo = 'TEST_PARAMETRO')                                              AS parametros_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO
        WHERE nombre = N'Yoshimi' AND apellido = N'Yamashita')                                    AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE
        WHERE nombre_estadio = 'Estadio Nacional1')                       AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.COTIZACION WHERE codigo_moneda = 'XTS')    AS cotizaciones_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.FERIADO AS f
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = f.id_pais
        WHERE p.nombre IN ('Argentina1', 'República Argentina1', 'Japón1'))                                           AS feriados_de_prueba;

SELECT 'Final' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('MIN_CONVOCADOS', 'MAX_CONVOCADOS', 'MAX_CAMBIOS', 'MAX_VENTANAS', 'PRIME_TIME_DESDE')
ORDER BY codigo;
GO

SET NOEXEC OFF;
GO
