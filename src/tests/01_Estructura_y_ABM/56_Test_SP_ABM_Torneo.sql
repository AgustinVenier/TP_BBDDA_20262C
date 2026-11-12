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
 Archivo: 56_Test_SP_ABM_Torneo.sql
 Objetivo: Probar los SP de 06_SP_ABM_Torneo.sql (SEDE, SEDE_IMAGEN, SELECCION,
           LISTA_CONVOCADOS, JUGADOR, PERSONA_CUERPO_TECNICO y PARTIDO), con
           casos exitosos y su evidencia y casos que no cumplen las
           validaciones. Requiere haber ejecutado 01 a 28 y no depende del
           juego de datos.
           Crea sus propios datos de prueba (las sedes "Estadio Monumental1" y
           "La Bombonera1", los países Argentina1, Brasil1, Uruguay1,
           Colombia1 y Ecuador1 con sus selecciones en los grupos K y L, una
           lista completa para Brasil1 y los partidos 201 a 209). Lo que no
           prueba este script se carga con INSERT directos a las tablas. Corre dentro de una transacción que se deshace
           al final, así que no deja datos y se puede ejecutar más de una vez.
           Las bajas rechazadas por historial usan el partido 204 (Argentina1 -
           Uruguay1), con una formación y una tarjeta al director técnico, que se
           arma y se borra en la sección HISTORIAL.
           SE1 y SE3 prueban el cupo de un grupo, así que el grupo L tiene que
           quedar completo con las 4 selecciones de prueba. Si el grupo ya tiene
           selecciones (por ejemplo, con las 48 del Mundial cargadas), el test
           ajusta SELECCIONES_POR_GRUPO dentro de la transacción.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba y
     SELECCIONES_POR_GRUPO con su valor original. Si no, quedó algo sin
     deshacer.
 Los países y sedes de prueba se llaman como uno real con un 1 al final: así
 no chocan con los datos reales que se importen.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_PARTIDO_Alta', N'P') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_AMONESTACION_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS')
BEGIN
    RAISERROR(N'Faltan los SP de ABM o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
BEGIN TRANSACTION;
GO

-- Preparación, con INSERT directos: los países de prueba, todavía sin selección.
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES
    ('Argentina1', 'Argentina Standard Time'),
    ('Brasil1',    'E. South America Standard Time'),
    ('Uruguay1',   'Montevideo Standard Time'),
    ('Colombia1',  'SA Pacific Standard Time'),
    ('Ecuador1',   'SA Pacific Standard Time');
GO


/* ============================================================================
   SEDE
   ============================================================================ */

/* S1 (OK) Alta de una sede.
   Esperado: 0 sedes de prueba antes y 1 después, con el huso guardado como
   "Argentina Standard Time". La sede se crea sin espacios publicitarios (los
   4 espacios los agrega Torneo.usp_RegistrarSede, que se prueba en 60). */
DECLARE @id_sede INT;

SELECT 'S1 antes' AS caso, COUNT(*) AS sedes_de_prueba FROM Torneo.SEDE WHERE nombre_estadio IN ('Estadio Monumental1', 'La Bombonera1');

DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
EXEC Torneo.usp_SEDE_Alta
    @nombre_estadio = 'Estadio Monumental1', @ciudad = 'Buenos Aires', @id_pais = @id_pais,
    @capacidad = 30000, @huso_horario = 'argentina standard time',
    @latitud = -34.545500, @longitud = -58.449700, @id_sede = @id_sede OUTPUT;

SELECT 'S1 después' AS caso, id_sede, nombre_estadio, ciudad, capacidad, huso_horario, latitud, longitud
FROM Torneo.SEDE
WHERE id_sede = @id_sede;
GO

/* S2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 7 condiciones: nombre y ciudad obligatorios, no
   existe el país -1, capacidad no positiva, huso inexistente, latitud sin
   longitud y latitud fuera de rango. */
BEGIN TRY
    EXEC Torneo.usp_SEDE_Alta
        @nombre_estadio = '', @ciudad = '  ', @id_pais = -1, @capacidad = 0,
        @huso_horario = 'Hora de Marte', @latitud = 95;
    PRINT N'S2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'S2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'S2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* S3 (ERROR) Alta de una sede que ya existe.
   Esperado: error 50001 con 1 condición: ya existe la sede "Estadio Monumental1". */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
BEGIN TRY
    EXEC Torneo.usp_SEDE_Alta
        @nombre_estadio = 'Estadio Monumental1', @ciudad = 'Rosario', @id_pais = @id_pais,
        @capacidad = 40000, @huso_horario = 'Argentina Standard Time';
    PRINT N'S3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'S3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'S3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* S4 (OK) Modificación parcial: capacidad y ciudad.
   Esperado: la capacidad pasa a 35000 y la ciudad a "Ciudad Autónoma de
   Buenos Aires"; el resto queda igual. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');

SELECT 'S4 antes' AS caso, id_sede, nombre_estadio, ciudad, capacidad, huso_horario FROM Torneo.SEDE WHERE id_sede = @id_sede;

EXEC Torneo.usp_SEDE_Modificacion @id_sede = @id_sede, @capacidad = 35000, @ciudad = 'Ciudad Autónoma de Buenos Aires';

SELECT 'S4 después' AS caso, id_sede, nombre_estadio, ciudad, capacidad, huso_horario FROM Torneo.SEDE WHERE id_sede = @id_sede;
GO

-- S5 necesita un partido jugado en la sede: se prueba al final del script.


/* ============================================================================
   SEDE_IMAGEN
   Los SP validan el formato por los primeros bytes del archivo (la firma), así
   que alcanza con datos que empiecen con la firma de PNG o de JPEG.
   ============================================================================ */

/* SI1 (OK) Alta de la imagen de una sede.
   Esperado: 0 imágenes antes; después, 1 imagen PNG de 12 bytes. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');

SELECT 'SI1 antes' AS caso, COUNT(*) AS imagenes FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede;

EXEC Torneo.usp_SEDE_IMAGEN_Alta @id_sede = @id_sede, @imagen = 0x89504E470D0A1A0A00000000;

SELECT 'SI1 después' AS caso, id_sede, formato, DATALENGTH(imagen) AS bytes FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede;
GO

/* SI2 (ERROR) Segunda imagen para la misma sede, y que no es PNG ni JPEG (es GIF).
   Esperado: error 50001 con 2 condiciones: la sede ya tiene imagen y la
   imagen tiene que ser PNG o JPEG. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
BEGIN TRY
    EXEC Torneo.usp_SEDE_IMAGEN_Alta @id_sede = @id_sede, @imagen = 0x474946383961;
    PRINT N'SI2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SI2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SI2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* SI3 (ERROR) Imagen para una sede que no existe y de más de 2 MB.
   Esperado: error 50001 con 2 condiciones: no existe la sede -1 y la imagen
   supera los 2 MB. */
DECLARE @grande VARBINARY(MAX) = 0x89504E470D0A1A0A
        + CAST(REPLICATE(CAST('x' AS VARCHAR(MAX)), 2097152) AS VARBINARY(MAX));
BEGIN TRY
    EXEC Torneo.usp_SEDE_IMAGEN_Alta @id_sede = -1, @imagen = @grande;
    PRINT N'SI3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SI3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SI3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* SI4 (OK) Reemplazo de la imagen por una JPEG.
   Esperado: el formato pasa de PNG a JPEG y cambian los bytes. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');

SELECT 'SI4 antes' AS caso, formato, DATALENGTH(imagen) AS bytes FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede;

EXEC Torneo.usp_SEDE_IMAGEN_Modificacion @id_sede = @id_sede, @imagen = 0xFFD8FFE000104A464946;

SELECT 'SI4 después' AS caso, formato, DATALENGTH(imagen) AS bytes FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede;
GO

/* SI5 (ERROR) Baja de una sede que tiene imagen.
   Esperado: error 50001 de Torneo.usp_SEDE_Baja con 1 condición: la
   referencia 1 registro de Torneo.SEDE_IMAGEN. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
BEGIN TRY
    EXEC Torneo.usp_SEDE_Baja @id_sede = @id_sede;
    PRINT N'SI5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SI5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SI5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* SI6 (OK) Baja de la imagen.
   Esperado: 1 imagen antes y 0 después; la sede sigue en la base. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');

SELECT 'SI6 antes' AS caso, COUNT(*) AS imagenes FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede;

EXEC Torneo.usp_SEDE_IMAGEN_Baja @id_sede = @id_sede;

SELECT 'SI6 después' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE_IMAGEN WHERE id_sede = @id_sede) AS imagenes,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE id_sede = @id_sede)        AS sedes;
GO

/* SI7 (ERROR) Quitar o reemplazar la imagen de una sede que no tiene.
   Esperado: dos errores 50001, uno de la baja y otro de la modificación: la
   sede no tiene imagen. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
BEGIN TRY
    EXEC Torneo.usp_SEDE_IMAGEN_Baja @id_sede = @id_sede;
    PRINT N'SI7a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SI7a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SI7a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    EXEC Torneo.usp_SEDE_IMAGEN_Modificacion @id_sede = @id_sede, @imagen = 0xFFD8FFE000104A464946;
    PRINT N'SI7b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SI7b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SI7b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   SELECCION
   ============================================================================ */

/* Preparación: el cupo del grupo L. SE1 da de alta 4 selecciones de prueba en
   el grupo L y SE3 comprueba que no entra una quinta, así que el cupo tiene que
   ser el de las selecciones que el grupo ya tiene más 4 (SE4 y PA4 usan además
   un lugar del grupo K). Con los datos iniciales el grupo está vacío y el cupo
   es 4, así que no cambia nada. Si el grupo ya tiene selecciones (por ejemplo,
   con las 48 del Mundial cargadas), se ajusta SELECCIONES_POR_GRUPO; el
   ROLLBACK del final lo devuelve a su valor.
   Esperado: cupo 4 y 0 selecciones en el grupo L con los datos iniciales; con
   las 48 selecciones del Mundial, cupo 8 y 4 selecciones. */
DECLARE @cupo TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO');
DECLARE @en_el_grupo TINYINT = (SELECT COUNT(*) FROM Torneo.SELECCION WHERE grupo = 'L');

IF @en_el_grupo + 4 <> @cupo
BEGIN
    SET @cupo = @en_el_grupo + 4;
    UPDATE DatosGenerales.PARAMETRO_REGLAMENTO SET valor = @cupo WHERE codigo = 'SELECCIONES_POR_GRUPO';
END;

SELECT 'Cupo del grupo L' AS caso, @cupo AS selecciones_por_grupo, @en_el_grupo AS selecciones_en_el_grupo_L;
GO

/* SE1 (OK) Alta de cuatro selecciones en el grupo L.
   Esperado: 0 selecciones de prueba antes y 4 después (Argentina1, Brasil1, Uruguay1
   y Colombia1), con la confederación y el grupo en mayúsculas. */
DECLARE @id_pais_xta SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Argentina1');
DECLARE @id_pais_xtb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Brasil1');
DECLARE @id_pais_xtc SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Uruguay1');
DECLARE @id_pais_xtd SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Colombia1');

SELECT 'SE1 antes' AS caso, COUNT(*) AS selecciones_de_prueba
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.nombre IN ('Argentina1', 'Brasil1', 'Uruguay1', 'Colombia1', 'Ecuador1');

EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xta, @confederacion = 'conmebol', @grupo = 'l';
EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xtb, @confederacion = 'CONMEBOL', @grupo = 'L';
EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xtc, @confederacion = 'CONMEBOL', @grupo = 'L';
EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xtd, @confederacion = 'CONMEBOL', @grupo = 'L';

SELECT 'SE1 después' AS caso, s.id_seleccion, p.nombre AS seleccion, s.confederacion, s.grupo
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.nombre IN ('Argentina1', 'Brasil1', 'Uruguay1', 'Colombia1', 'Ecuador1');
GO

/* SE2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 3 condiciones: Argentina1 ya tiene selección, la
   confederación FIFA no es válida y el grupo Z no existe. */
DECLARE @id_pais_xta SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xta, @confederacion = 'FIFA', @grupo = 'Z';
    PRINT N'SE2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SE2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SE2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* SE3 (ERROR) Una quinta selección de prueba en el grupo L.
   Esperado: error 50001 con 1 condición: el grupo L ya completó su cupo
   (SELECCIONES_POR_GRUPO: 4 con los datos iniciales, o el que fijó la
   preparación si el grupo ya tenía selecciones). */
DECLARE @id_pais_xte SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Ecuador1');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xte, @confederacion = 'CONMEBOL', @grupo = 'L';
    PRINT N'SE3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SE3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SE3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* SE4 (OK) Cambio de grupo de una selección sin partidos.
   Esperado: Colombia1 pasa del grupo L al K. */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Colombia1');

SELECT 'SE4 antes' AS caso, id_seleccion, confederacion, grupo FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion;
EXEC Torneo.usp_SELECCION_Modificacion @id_seleccion = @id_seleccion, @grupo = 'K';
SELECT 'SE4 después' AS caso, id_seleccion, confederacion, grupo FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion;
GO

-- SE5 y SE6 necesitan una selección con partidos: se prueban en la sección HISTORIAL.

/* SE7 (OK) Baja de una selección sin referencias.
   Esperado: Colombia1 existe antes y no después. */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Colombia1');
SELECT 'SE7 antes' AS caso, COUNT(*) AS seleccion_xtd FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion;
EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id_seleccion;
SELECT 'SE7 después' AS caso, COUNT(*) AS seleccion_xtd FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion;
GO


/* ============================================================================
   LISTA_CONVOCADOS
   ============================================================================ */

/* L1 (OK) Alta de la lista de Argentina1.
   Esperado: una lista nueva con fecha de presentación 01/06/2026. */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                             INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_lista INT;
EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = @id_seleccion, @fecha_presentacion = '2026-06-01', @id_lista = @id_lista OUTPUT;
SELECT 'L1 después' AS caso, id_lista, id_seleccion, fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
GO

/* L2 (ERROR) Alta para una selección que no existe y con fecha futura.
   Esperado: error 50001 con 2 condiciones: no existe la selección -1 y la
   fecha no puede ser futura. */
DECLARE @futura DATE = DATEADD(DAY, 10, GETDATE());
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = -1, @fecha_presentacion = @futura;
    PRINT N'L2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'L2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'L2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* L3 (ERROR) Segunda lista para la misma selección.
   Esperado: error 50001 con 1 condición: la selección ya tiene su lista. */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                             INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = @id_seleccion, @fecha_presentacion = '2026-06-02';
    PRINT N'L3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'L3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'L3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* L4 (OK) Modificación de la fecha de presentación.
   Esperado: la fecha pasa de 01/06/2026 a 30/05/2026. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
SELECT 'L4 antes' AS caso, id_lista, fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
EXEC Torneo.usp_LISTA_CONVOCADOS_Modificacion @id_lista = @id_lista, @fecha_presentacion = '2026-05-30';
SELECT 'L4 después' AS caso, id_lista, fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
GO


/* ============================================================================
   JUGADOR (lista de Argentina1)
   ============================================================================ */

/* J1 (OK) Alta de dos jugadores.
   Esperado: 0 jugadores antes y 2 después. El primero, dado de alta el
   01/06/2026 con posición en mayúsculas; el segundo, sin fecha de alta, queda
   con la fecha de hoy. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_pais_xta SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Argentina1');

SELECT 'J1 antes' AS caso, COUNT(*) AS jugadores FROM Torneo.JUGADOR WHERE id_lista = @id_lista;

EXEC Torneo.usp_JUGADOR_Alta
    @id_lista = @id_lista, @nombre = N'Carlos', @apellido = N'Tevez', @posicion_habitual = 'delantero',
    @dorsal = 9, @fecha_nacimiento = '1998-02-10', @club_origen = N'Club Bolívar',
    @id_pais_nacimiento = @id_pais_xta, @fecha_alta = '2026-06-01', @motivo_alta = 'Lista inicial';
EXEC Torneo.usp_JUGADOR_Alta
    @id_lista = @id_lista, @nombre = N'Marcelo', @apellido = N'Barovero', @posicion_habitual = 'ARQUERO',
    @dorsal = 1, @club_origen = N'The Strongest';

SELECT 'J1 después' AS caso, id_jugador, dorsal, apellido, nombre, posicion_habitual, club_origen,
       fecha_alta, motivo_alta, fecha_baja
FROM Torneo.JUGADOR
WHERE id_lista = @id_lista;
GO

/* J2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 6 condiciones: nombre obligatorio, apellido de
   más de 60 caracteres, posición no válida, dorsal fuera de rango, fecha de
   nacimiento futura y alta anterior a la presentación de la lista. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @futura DATE = DATEADD(YEAR, 1, GETDATE());
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N' ', @apellido = N'Apellido larguísimo que supera holgadamente los sesenta caracteres',
        @posicion_habitual = 'LIBERO', @dorsal = 0, @fecha_nacimiento = @futura, @fecha_alta = '2026-01-01';
    PRINT N'J2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'J2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'J2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* J3 (ERROR) Alta con dorsal ocupado y nombre repetido.
   Esperado: error 50001 con 2 condiciones: Carlos Tevez ya figura en la
   lista y el dorsal 1 ya lo usa Marcelo Barovero. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N'Carlos', @apellido = N'Tevez',
        @posicion_habitual = 'DEFENSOR', @dorsal = 1;
    PRINT N'J3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'J3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'J3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* J4 (ERROR) Alta en una lista completa.
   Preparación, con INSERT: la lista de Brasil1 con MAX_CONVOCADOS (26)
   jugadores (su plantel).
   Esperado: 26 jugadores activos en la lista de Brasil1 y error 50001 con 1
   condición: la lista ya tiene 26 convocados activos, el máximo permitido
   (MAX_CONVOCADOS). */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                             INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Brasil1');
DECLARE @id_lista INT;

INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta) VALUES
    (@id_lista,  1, N'Alisson',     N'Becker',     'ARQUERO',       '2026-06-01'),
    (@id_lista, 12, N'Ederson',     N'Moraes',     'ARQUERO',       '2026-06-01'),
    (@id_lista, 23, N'Bento',       N'Krepski',    'ARQUERO',       '2026-06-01'),
    (@id_lista,  2, N'Danilo',      N'Luiz',       'DEFENSOR',      '2026-06-01'),
    (@id_lista,  3, N'Gabriel',     N'Magalhães',  'DEFENSOR',      '2026-06-01'),
    (@id_lista,  4, N'Marcos',      N'Aoás',       'DEFENSOR',      '2026-06-01'),
    (@id_lista,  5, N'Éder',        N'Militão',    'DEFENSOR',      '2026-06-01'),
    (@id_lista,  6, N'Alex',        N'Sandro',     'DEFENSOR',      '2026-06-01'),
    (@id_lista, 13, N'Wesley',      N'França',     'DEFENSOR',      '2026-06-01'),
    (@id_lista, 14, N'Lucas',       N'Beraldo',    'DEFENSOR',      '2026-06-01'),
    (@id_lista, 15, N'Douglas',     N'Santos',     'DEFENSOR',      '2026-06-01'),
    (@id_lista,  7, N'Lucas',       N'Paquetá',    'MEDIOCAMPISTA', '2026-06-01'),
    (@id_lista,  8, N'Bruno',       N'Guimarães',  'MEDIOCAMPISTA', '2026-06-01'),
    (@id_lista, 10, N'Rodrygo',     N'Goes',       'MEDIOCAMPISTA', '2026-06-01'),
    (@id_lista, 16, N'André',       N'Trindade',   'MEDIOCAMPISTA', '2026-06-01'),
    (@id_lista, 17, N'Joelinton',   N'Lira',       'MEDIOCAMPISTA', '2026-06-01'),
    (@id_lista, 18, N'Gerson',      N'Santos',     'MEDIOCAMPISTA', '2026-06-01'),
    (@id_lista,  9, N'Matheus',     N'Cunha',      'DELANTERO',     '2026-06-01'),
    (@id_lista, 11, N'Raphael',     N'Dias',       'DELANTERO',     '2026-06-01'),
    (@id_lista, 19, N'Vinícius',    N'Júnior',     'DELANTERO',     '2026-06-01'),
    (@id_lista, 20, N'Gabriel',     N'Martinelli', 'DELANTERO',     '2026-06-01'),
    (@id_lista, 21, N'Richarlison', N'Andrade',    'DELANTERO',     '2026-06-01'),
    (@id_lista, 22, N'Estêvão',     N'Willian',    'DELANTERO',     '2026-06-01'),
    (@id_lista, 24, N'Endrick',     N'Moreira',    'DELANTERO',     '2026-06-01'),
    (@id_lista, 25, N'Igor',        N'Jesus',      'DELANTERO',     '2026-06-01'),
    (@id_lista, 26, N'Andrey',      N'Santos',     'MEDIOCAMPISTA', '2026-06-01');

SELECT 'J4 lista de Brasil1' AS caso, COUNT(*) AS jugadores_activos
FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND fecha_baja IS NULL;

BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N'Jugador', @apellido = N'Número 27',
        @posicion_habitual = 'DELANTERO', @dorsal = 27, @fecha_alta = '2026-06-05';
    PRINT N'J4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'J4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'J4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* J5 (OK) Modificación de dorsal y club.
   Esperado: Carlos Tevez pasa del dorsal 9 al 10 y al club Wilstermann. */
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Tevez');
SELECT 'J5 antes' AS caso, id_jugador, dorsal, club_origen FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;
EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id_jugador, @dorsal = 10, @club_origen = N'Wilstermann';
SELECT 'J5 después' AS caso, id_jugador, dorsal, club_origen FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;
GO

/* J6 (ERROR) Modificación con dorsal ocupado y posición no válida.
   Esperado: error 50001 con 2 condiciones: la posición no es válida y el
   dorsal 1 ya lo usa Marcelo Barovero. */
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Tevez');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id_jugador, @dorsal = 1, @posicion_habitual = 'VOLANTE';
    PRINT N'J6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'J6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'J6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* L5 (ERROR) Presentación de la lista posterior al alta de un jugador.
   Esperado: error 50001 con 1 condición: hay jugadores dados de alta antes
   de esa fecha (01/06/2026). */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Modificacion @id_lista = @id_lista, @fecha_presentacion = '2026-06-02';
    PRINT N'L5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'L5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'L5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* L6 (ERROR) Baja de una lista con jugadores.
   Esperado: error 50001 con 1 condición: a la lista de Argentina1 la
   referencian 2 registros de Torneo.JUGADOR (Tevez y Barovero). La
   lista sigue existiendo. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id_lista;
    PRINT N'L6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'L6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'L6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'L6 después' AS caso, COUNT(*) AS listas FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
GO

/* J7 (OK) Baja lógica (baja de último momento).
   Esperado: Carlos Tevez sigue en la tabla, con fecha de baja
   05/06/2026 y el motivo informado. */
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Tevez');
SELECT 'J7 antes' AS caso, id_jugador, fecha_baja, motivo_baja FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_jugador, @motivo_baja = 'Desgarro en el isquiotibial', @fecha_baja = '2026-06-05';
SELECT 'J7 después' AS caso, id_jugador, fecha_baja, motivo_baja FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;
GO

/* J8 (ERROR) Segunda baja del mismo jugador y sin motivo.
   Esperado: error 50001 con 2 condiciones: el jugador ya fue dado de baja el
   05/06/2026 y el motivo es obligatorio. */
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Tevez');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_jugador;
    PRINT N'J8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'J8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'J8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

-- J9 necesita un jugador con historial: se prueba en la sección HISTORIAL.


/* ============================================================================
   PERSONA_CUERPO_TECNICO (Argentina1)
   ============================================================================ */

/* C1 (OK) Alta del director técnico y de un ayudante.
   Esperado: 0 antes y 2 personas después, con el rol en mayúsculas. */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                             INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
SELECT 'C1 antes' AS caso, COUNT(*) AS cuerpo_tecnico FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion;
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Óscar', @apellido = N'Tabárez',
    @rol = 'director_tecnico', @fecha_nacimiento = '1970-05-20';
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Julio', @apellido = N'Olarticoechea',
    @rol = 'AYUDANTE_CAMPO';
SELECT 'C1 después' AS caso, id_persona_ct, apellido, nombre, rol, fecha_nacimiento
FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion;
GO

/* C2 (ERROR) Un segundo director técnico.
   Esperado: error 50001 con 1 condición: la selección ya tiene director técnico. */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                             INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Otro', @apellido = N'Técnico',
        @rol = 'DIRECTOR_TECNICO';
    PRINT N'C2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* C3 (ERROR) Alta con rol no válido y sin nombre, para una selección que no existe.
   Esperado: error 50001 con 3 condiciones: no existe la selección -1, el
   nombre es obligatorio y el rol UTILERO no es válido. */
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = -1, @nombre = N'', @apellido = N'Sin Nombre',
        @rol = 'UTILERO';
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

/* C4 (OK) Modificación del rol del ayudante.
   Esperado: el ayudante pasa a PREPARADOR_FISICO. */
DECLARE @id_persona_ct INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido = N'Olarticoechea');
SELECT 'C4 antes' AS caso, id_persona_ct, apellido, rol FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id_persona_ct;
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id_persona_ct, @rol = 'PREPARADOR_FISICO';
SELECT 'C4 después' AS caso, id_persona_ct, apellido, rol FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id_persona_ct;
GO

/* C5 (ERROR) El ayudante como segundo director técnico.
   Esperado: error 50001 con 1 condición: la selección ya tiene director técnico. */
DECLARE @id_persona_ct INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido = N'Olarticoechea');
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id_persona_ct, @rol = 'DIRECTOR_TECNICO';
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

-- C6 necesita una tarjeta al director técnico: se prueba en la sección HISTORIAL.

/* C7 (OK) Baja del ayudante de prueba.
   Esperado: 2 personas antes y 1 después. */
DECLARE @id_persona_ct INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido = N'Olarticoechea');
DECLARE @id_seleccion INT = (SELECT id_seleccion FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id_persona_ct);
SELECT 'C7 antes' AS caso, COUNT(*) AS cuerpo_tecnico FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion;
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id_persona_ct;
SELECT 'C7 después' AS caso, COUNT(*) AS cuerpo_tecnico FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion;
GO


/* ============================================================================
   HISTORIAL (partido 204, Argentina1 - Uruguay1)
   Las bajas y los cambios que se rechazan porque hay historial necesitan un
   partido con formación y tarjetas. Se arma el partido 204 con los SP, se
   prueban esos casos y se borra todo antes de la sección PARTIDO.
   ============================================================================ */

/* Preparación (OK): partido 204 del 03/06/2026, de la fase de grupos, con la
   formación de Argentina1, el jugador "Rodrigo Palacio" (dorsal 8) de
   titular y, con el partido EN_JUEGO, una amarilla al director técnico de
   Argentina1.
   Esperado: el partido EN_JUEGO con 1 formación, 1 jugador alineado y 1
   tarjeta. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
DECLARE @id_seleccion_xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_seleccion_xtc INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Uruguay1');
DECLARE @id_lista INT = (SELECT id_lista FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @id_seleccion_xta);
DECLARE @id_persona_ct INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_seleccion_xta AND rol = 'DIRECTOR_TECNICO');
DECLARE @id_partido INT, @id_formacion INT, @id_jugador INT;

INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_alta)
VALUES (@id_lista, N'Rodrigo', N'Palacio', 'MEDIOCAMPISTA', 8, '2026-06-01');
SET @id_jugador = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, estado)
VALUES (204, @sede, 'GRUPOS', '2026-06-03 16:00', '2026-06-03 19:00', @id_seleccion_xta, @id_seleccion_xtc, 'EN_JUEGO');
SET @id_partido = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico) VALUES (@id_partido, @id_seleccion_xta, '4-4-2');
SET @id_formacion = SCOPE_IDENTITY();
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
VALUES (@id_formacion, @id_jugador, 1, 'MEDIOCAMPISTA');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_persona_ct, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido, @id_persona_ct, 'AMARILLA', 30, 'Protestas desde el banco');

SELECT 'Historial preparado' AS caso, p.numero_partido, p.estado,
       (SELECT COUNT(*) FROM DesarrolloPartido.FORMACION WHERE id_partido = p.id_partido)    AS formaciones,
       (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion) AS alineados,
       (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION WHERE id_partido = p.id_partido) AS tarjetas
FROM Torneo.PARTIDO AS p
WHERE p.id_partido = @id_partido;
GO

/* SE5 (ERROR) Cambio de grupo de una selección que ya jugó la fase de grupos.
   Esperado: error 50001 con 2 condiciones: la confederación no es válida y
   Argentina1 ya tiene partidos de la fase de grupos (el 204). */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Modificacion @id_seleccion = @id_seleccion, @confederacion = 'SUDAMERICA', @grupo = 'K';
    PRINT N'SE5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SE5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SE5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* SE6 (ERROR) Baja de una selección con historial.
   Esperado: error 50001 que lista lo que referencia a Argentina1: su lista, su
   cuerpo técnico, sus partidos y sus formaciones (4 condiciones). */
DECLARE @id_seleccion INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id_seleccion;
    PRINT N'SE6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SE6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SE6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* J9 (ERROR) Borrado físico de un jugador con historial.
   Esperado: error 50001 con 1 condición: "Palacio" figura en la
   formación del partido 204 (DesarrolloPartido.ALINEACION). El jugador no
   cambia. */
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Palacio');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_jugador, @eliminar_registro = 1;
    PRINT N'J9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'J9: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'J9: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'J9 después' AS caso, id_jugador, apellido, nombre, dorsal FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;
GO

/* C6 (ERROR) Baja de un director técnico con una tarjeta registrada.
   Esperado: error 50001 con 1 condición: al director técnico de Argentina1 lo
   referencia 1 registro de DesarrolloPartido.AMONESTACION (partido 204). */
DECLARE @id_persona_ct INT = (SELECT ct.id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                   WHERE p.nombre = 'Argentina1' AND ct.rol = 'DIRECTOR_TECNICO');
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id_persona_ct;
    PRINT N'C6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'C6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'C6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA12 (ERROR) Baja de un partido con formación y eventos.
   Esperado: error 50001 que lista la formación y la tarjeta del partido 204. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 204);
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id_partido;
    PRINT N'PA12: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA12: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA12: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* Limpieza del historial, con DELETE directos y en este orden: la tarjeta,
   la alineación, la formación, el partido y el jugador "Palacio".
   Esperado: 0 en todas las columnas. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 204);
DECLARE @id_formacion INT = (SELECT id_formacion FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Palacio');
DECLARE @id_tarjeta INT = (SELECT id_amonestacion FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido);

DELETE FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_tarjeta;
DELETE FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;
DELETE FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
DELETE FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
DELETE FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;

SELECT 'Historial borrado' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido = 204)          AS partidos,
       (SELECT COUNT(*) FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion) AS formaciones,
       (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_tarjeta) AS tarjetas,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido = N'Palacio')       AS jugadores;
GO


/* ============================================================================
   PARTIDO (sede de prueba, selecciones del grupo L)
   ============================================================================ */

/* PA1 (OK) Alta con la hora local de la sede.
   Esperado: el partido 201 (Argentina1 - Brasil1, grupo L) queda PROGRAMADO con
   hora local 01/08/2026 16:00 y hora UTC 19:00, calculada con el huso de la
   sede (UTC-3). */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
DECLARE @id_seleccion_xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_seleccion_xtb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Brasil1');
DECLARE @id_partido INT;

EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 201, @id_sede = @sede, @fase = 'grupos', @fecha_hora_local = '2026-08-01 16:00',
    @id_seleccion_local = @id_seleccion_xta, @id_seleccion_visitante = @id_seleccion_xtb, @id_partido = @id_partido OUTPUT;

SELECT 'PA1 después' AS caso, numero_partido, fase, seleccion_local, seleccion_visitante,
       fecha_hora_local, fecha_hora_utc, estado
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
GO

/* PA2 (OK) Alta con la hora UTC.
   Esperado: el partido 202 (Uruguay1 - Brasil1) queda con hora UTC 05/08/2026 22:00
   y hora local 19:00. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
DECLARE @id_seleccion_xtc INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Uruguay1');
DECLARE @id_seleccion_xtb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Brasil1');
DECLARE @id_partido INT;

EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 202, @id_sede = @sede, @fase = 'GRUPOS', @fecha_hora_utc = '2026-08-05 22:00',
    @id_seleccion_local = @id_seleccion_xtc, @id_seleccion_visitante = @id_seleccion_xtb, @id_partido = @id_partido OUTPUT;

SELECT 'PA2 después' AS caso, numero_partido, seleccion_local, seleccion_visitante, fecha_hora_local, fecha_hora_utc
FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
GO

/* PA3 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 5 condiciones: ya existe el partido 201, no
   existe la sede -1, la fase AMISTOSO no es válida, falta la fecha y hora, y
   la selección local y la visitante son la misma. */
DECLARE @id_seleccion_xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = 201, @id_sede = -1, @fase = 'AMISTOSO',
        @id_seleccion_local = @id_seleccion_xta, @id_seleccion_visitante = @id_seleccion_xta;
    PRINT N'PA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA4 (ERROR) Fase de grupos con selecciones de grupos distintos y descanso insuficiente.
   Preparación: la selección de Ecuador1 en el grupo K.
   Esperado: error 50001 con 2 condiciones: en la fase de grupos las dos
   selecciones tienen que ser del mismo grupo (Argentina1 es del L y Ecuador1
   del K) y Argentina1 ya juega el partido 201 a menos de 24 horas. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
DECLARE @id_seleccion_xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_pais_xte SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Ecuador1');
DECLARE @id_seleccion_xte INT;
EXEC Torneo.usp_SELECCION_Alta @id_pais = @id_pais_xte, @confederacion = 'CONMEBOL', @grupo = 'K', @id_seleccion = @id_seleccion_xte OUTPUT;
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = 203, @id_sede = @sede, @fase = 'GRUPOS', @fecha_hora_utc = '2026-08-02 10:00',
        @id_seleccion_local = @id_seleccion_xta, @id_seleccion_visitante = @id_seleccion_xte;
    PRINT N'PA4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA5 (ERROR) Hora local y UTC que no coinciden, en una sede ocupada ese día.
   Esperado: error 50001 con 2 condiciones: la hora local no coincide con la
   UTC en el huso de la sede y la sede ya tiene el partido 201 ese día. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = 203, @id_sede = @sede, @fase = 'OCTAVOS',
        @fecha_hora_utc = '2026-08-01 23:00', @fecha_hora_local = '2026-08-01 23:00';
    PRINT N'PA5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA6 (OK) Cambio de fecha con la hora local.
   Esperado: el partido 201 pasa al 02/08/2026 a las 16:00 locales, y la hora
   UTC se recalcula (19:00). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
SELECT 'PA6 antes' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @fecha_hora_local = '2026-08-02 16:00';
SELECT 'PA6 después' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO

/* PA7 (ERROR) Resultado y asistencia en un partido que no empezó.
   Esperado: error 50001 con 2 condiciones: el resultado solo se carga con el
   partido FINALIZADO y la asistencia se carga con el partido empezado o
   terminado. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @goles_local = 1, @goles_visitante = 0, @asistencia = 1000;
    PRINT N'PA7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA8 (OK) Carga histórica: un partido PROGRAMADO pasa a FINALIZADO con su resultado.
   Esperado: el partido 201 queda FINALIZADO, 2 a 1, con 28000 espectadores. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
SELECT 'PA8 antes' AS caso, numero_partido, resultado, asistencia, estado FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @goles_local = 2, @goles_visitante = 1,
    @asistencia = 28000, @estado = 'FINALIZADO';
SELECT 'PA8 después' AS caso, numero_partido, resultado, asistencia, estado FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
GO

-- S5 se prueba al final del script.

/* PA9 (ERROR) Cambios que no corresponden en un partido finalizado.
   Preparación: la sede "La Bombonera1", con capacidad para 20000.
   Esperado: error 50001 con 3 condiciones: el partido está FINALIZADO y ya
   no se puede cambiar la sede, en la fase de grupos no hay definición por
   penales y la asistencia supera la capacidad de la sede pedida (La
   Bombonera1, 20000). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
DECLARE @id_pais_arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
DECLARE @id_otra_sede INT;
EXEC Torneo.usp_SEDE_Alta
    @nombre_estadio = 'La Bombonera1', @ciudad = 'Córdoba', @id_pais = @id_pais_arg,
    @capacidad = 20000, @huso_horario = 'Argentina Standard Time', @id_sede = @id_otra_sede OUTPUT;
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @id_sede = @id_otra_sede,
        @penales_local = 4, @penales_visitante = 2, @asistencia = 60000;
    PRINT N'PA9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA9: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA9: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA10 (ERROR) Paso de estado no permitido.
   Esperado: error 50001 con 1 condición: un partido no puede pasar de
   FINALIZADO a SUSPENDIDO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'SUSPENDIDO';
    PRINT N'PA10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PA10: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PA10: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PA11 (OK) Reapertura de un partido finalizado y vuelta a PROGRAMADO.
   Esperado: al pasar a EN_JUEGO se borra el resultado (goles en NULL); como
   no tiene eventos, después puede volver a PROGRAMADO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
SELECT 'PA11 reabierto' AS caso, numero_partido, goles_local, goles_visitante, asistencia, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'PROGRAMADO';
SELECT 'PA11 después' AS caso, numero_partido, goles_local, goles_visitante, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO

/* S6 (OK) Cambio de huso de una sede con partidos.
   Esperado: la sede pasa a "Pacific SA Standard Time" (Chile, UTC-4 en
   agosto) y la hora local de los partidos 201 y 202 se recalcula una hora
   antes; la hora UTC no cambia. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
SELECT 'S6 antes' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_sede = @sede ORDER BY numero_partido;
EXEC Torneo.usp_SEDE_Modificacion @id_sede = @sede, @huso_horario = 'Pacific SA Standard Time';
SELECT 'S6 después' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_sede = @sede ORDER BY numero_partido;
GO

/* S7 (ERROR) Baja de una sede con partidos.
   Esperado: error 50001 con 1 condición: la referencian 2 registros de
   Torneo.PARTIDO. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
BEGIN TRY
    EXEC Torneo.usp_SEDE_Baja @id_sede = @sede;
    PRINT N'S7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'S7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'S7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* S8 (OK) Baja de una sede sin partidos.
   Esperado: "La Bombonera1" (la de PA9, que no tiene partidos ni
   espacios publicitarios) existe antes y no después. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'La Bombonera1');
SELECT 'S8 antes' AS caso, COUNT(*) AS sedes FROM Torneo.SEDE WHERE id_sede = @sede;
EXEC Torneo.usp_SEDE_Baja @id_sede = @sede;
SELECT 'S8 después' AS caso, COUNT(*) AS sedes FROM Torneo.SEDE WHERE id_sede = @sede;
GO

-- PA12 (baja de un partido con formación y eventos) se prueba en la sección HISTORIAL.

/* PA13 (OK) Baja de los partidos de prueba.
   Esperado: 2 partidos de prueba antes y 0 después. */
DECLARE @id_partido INT;
SELECT 'PA13 antes' AS caso, COUNT(*) AS partidos_de_prueba FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209;
SET @id_partido = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id_partido;
SET @id_partido = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 202);
EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id_partido;
SELECT 'PA13 después' AS caso, COUNT(*) AS partidos_de_prueba FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209;
GO

/* J10 (OK) Borrado físico de los jugadores de prueba (no tienen historial).
   Esperado: 2 jugadores antes y 0 después. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_jugador INT;
SELECT 'J10 antes' AS caso, COUNT(*) AS jugadores FROM Torneo.JUGADOR WHERE id_lista = @id_lista;
SET @id_jugador = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Tevez');
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_jugador, @eliminar_registro = 1;
SET @id_jugador = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Barovero');
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_jugador, @eliminar_registro = 1;
SELECT 'J10 después' AS caso, COUNT(*) AS jugadores FROM Torneo.JUGADOR WHERE id_lista = @id_lista;
GO

/* L7 (OK) Baja de la lista de Argentina1, que ya no tiene jugadores.
   Esperado: 1 lista antes y 0 después.
   L8 (ERROR) Baja de la misma lista otra vez.
   Esperado: error 50001 con 1 condición: no existe una lista con ese id. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
SELECT 'L7 antes' AS caso, COUNT(*) AS listas FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id_lista;
SELECT 'L7 después' AS caso, COUNT(*) AS listas FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;

BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id_lista;
    PRINT N'L8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'L8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'L8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* S5 (ERROR) Modificación de una sede con datos que no cierran.
   Va último, en el mismo lote que el ROLLBACK: usp_SEDE_Modificacion usa
   SET XACT_ABORT ON, y con eso su error deja la transacción del test sin
   poder seguir escribiendo.
   Preparación: los partidos de prueba ya se borraron (PA13), así que se vuelve
   a cargar el 201 como partido jugado en la sede, con 28000 espectadores.
   Esperado: error 50001 con 2 condiciones: la capacidad (1000) no puede ser
   menor que la asistencia ya registrada en la sede (28000, partido 201) y la
   longitud está fuera de rango. La sede no cambia. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Monumental1');
DECLARE @id_seleccion_xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Argentina1');
DECLARE @id_seleccion_xtb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.nombre = 'Brasil1');
DECLARE @id_partido INT;

EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 201, @id_sede = @id_sede, @fase = 'GRUPOS', @fecha_hora_local = '2026-08-01 16:00',
    @id_seleccion_local = @id_seleccion_xta, @id_seleccion_visitante = @id_seleccion_xtb, @id_partido = @id_partido OUTPUT;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @goles_local = 2, @goles_visitante = 1,
    @asistencia = 28000, @estado = 'FINALIZADO';

BEGIN TRY
    EXEC Torneo.usp_SEDE_Modificacion @id_sede = @id_sede, @capacidad = 1000, @latitud = -34.5, @longitud = -200;
    PRINT N'S5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'S5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'S5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'S5 después' AS caso, nombre_estadio, capacidad, latitud, longitud FROM Torneo.SEDE WHERE id_sede = @id_sede;

ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas de datos de prueba y
   SELECCIONES_POR_GRUPO con su valor original (4 con los datos iniciales).
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio IN ('Estadio Monumental1', 'La Bombonera1')) AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS
        WHERE nombre IN ('Argentina1', 'Brasil1', 'Uruguay1', 'Colombia1', 'Ecuador1'))        AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209)           AS partidos_de_prueba,
       (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO')    AS selecciones_por_grupo;
GO

SET NOEXEC OFF;
GO
