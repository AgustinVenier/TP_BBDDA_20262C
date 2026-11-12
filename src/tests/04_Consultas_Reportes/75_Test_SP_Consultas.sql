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

 Fecha: 09/11/2026
 Archivo: 75_Test_SP_Consultas.sql
 Objetivo: Probar los SP de consulta de 25_SP_Consultas.sql y que funcionan con
           un usuario de rol_AdministradorOperativo, que no puede leer las
           tablas directamente. Requiere haber ejecutado 01 a 28 (el 27 crea los roles);
           no depende del juego de datos.
           Usa una sede de prueba ("Estadio José María Minella1", con sus 4
           espacios y su foto), cargada con INSERT directos. Corre dentro de
           una transacción que se deshace al final, así que no deja datos y
           se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Cada caso muestra lo que devuelve el SP (columna "caso" cuando hace falta).
   - Casos de permisos: en Mensajes se imprime "OK" si el permiso es el
     esperado y "FALLÓ" si no.
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_ConsultarSedes', N'P') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'usr_administrador') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG')
BEGIN
    RAISERROR(N'Faltan los SP de consulta, los roles o los datos iniciales: ejecutar 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
BEGIN TRANSACTION;
GO

-- Sede de prueba con sus 4 espacios y su foto (los primeros bytes de un JPG).
DECLARE @id_pais_arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
DECLARE @id_sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario, latitud, longitud)
VALUES ('Estadio José María Minella1', 'Mar del Plata', @id_pais_arg, 35000, 'Argentina Standard Time', -38.016667, -57.583333);
SET @id_sede = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES
    (@id_sede, 1, 4000), (@id_sede, 2, 3000), (@id_sede, 3, 2000), (@id_sede, 4, 1000);
INSERT INTO Torneo.SEDE_IMAGEN (id_sede, imagen, formato) VALUES (@id_sede, 0xFFD8FFE000104A464946, 'JPEG');
GO


/* CO1 Países y husos horarios.
   Esperado: la Argentina con su huso; los husos con su desfase, ordenados por
   desfase (el primero, el de menor desfase). */
DROP TABLE IF EXISTS #paises;
CREATE TABLE #paises (id_pais SMALLINT, nombre VARCHAR(60), codigo_fifa VARCHAR(3), huso_horario VARCHAR(50));
INSERT INTO #paises EXEC DatosGenerales.usp_ConsultarPaises;
SELECT 'CO1 países' AS caso, COUNT(*) AS paises,
       MAX(IIF(codigo_fifa = 'ARG', huso_horario, NULL)) AS huso_argentina
FROM #paises;
DROP TABLE #paises;

DROP TABLE IF EXISTS #husos;
CREATE TABLE #husos (huso_horario SYSNAME, desfase_utc NVARCHAR(12));
INSERT INTO #husos EXEC DatosGenerales.usp_ConsultarHusosHorarios;
SELECT TOP (1) 'CO1 husos' AS caso, (SELECT COUNT(*) FROM #husos) AS husos, huso_horario AS primero, desfase_utc
FROM #husos;
DROP TABLE #husos;
GO

/* CO2 Parámetro del reglamento.
   Esperado: MAX_CONVOCADOS con su valor (26 con los datos iniciales); un código
   que no existe devuelve NULL, sin error. */
DECLARE @valor TINYINT, @inexistente TINYINT;
EXEC DatosGenerales.usp_ConsultarParametroReglamento @codigo = 'MAX_CONVOCADOS', @valor = @valor OUTPUT, @mostrar_resultados = 0;
EXEC DatosGenerales.usp_ConsultarParametroReglamento @codigo = 'NO_EXISTE', @valor = @inexistente OUTPUT, @mostrar_resultados = 0;
SELECT 'CO2' AS caso, @valor AS max_convocados, @inexistente AS codigo_inexistente;
GO

/* CO3 Sedes con búsqueda.
   Esperado: buscando "Mar del Plata" (la ciudad) aparece solo la sede de
   prueba, con sus 4 espacios; buscando "Minella1" (el estadio), lo
   mismo; una búsqueda sin coincidencias devuelve 0 filas. */
EXEC Torneo.usp_ConsultarSedes @buscar = N'Mar del Plata';
EXEC Torneo.usp_ConsultarSedes @buscar = N'Minella1';
EXEC Torneo.usp_ConsultarSedes @buscar = N'zzz sin coincidencias';
GO

/* CO4 Una sede y su foto.
   Esperado: la sede de prueba con tarifas 4000, 3000, 2000 y 1000; su foto
   JPEG de 10 bytes; una sede que no existe devuelve 0 filas, sin error. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio José María Minella1');
EXEC Torneo.usp_ConsultarSede @id_sede = @id_sede;
EXEC Torneo.usp_ConsultarImagenSede @id_sede = @id_sede;
EXEC Torneo.usp_ConsultarSede @id_sede = -1;
GO

/* CO5 Selecciones.
   Esperado: una fila por selección cargada (0 sin el torneo), sin error. */
DROP TABLE IF EXISTS #selecciones;
CREATE TABLE #selecciones (id_seleccion INT, pais VARCHAR(60), confederacion VARCHAR(10), grupo CHAR(1),
                           id_lista INT, id_pais SMALLINT, codigo_fifa VARCHAR(3));
INSERT INTO #selecciones EXEC Torneo.usp_ConsultarSelecciones;
SELECT 'CO5' AS caso, COUNT(*) AS selecciones,
       (SELECT COUNT(*) FROM Torneo.SELECCION) AS selecciones_en_la_tabla
FROM #selecciones;
DROP TABLE #selecciones;
GO


/* CO6 Idiomas y tipos de gol.
   Esperado: los idiomas ordenados por nombre y los tipos de gol por id, los
   mismos que tienen sus tablas. */
DROP TABLE IF EXISTS #idiomas;
CREATE TABLE #idiomas (id_idioma SMALLINT, nombre VARCHAR(40), codigo_iso CHAR(2));
INSERT INTO #idiomas EXEC DatosGenerales.usp_ConsultarIdiomas;
SELECT 'CO6 idiomas' AS caso, COUNT(*) AS idiomas,
       (SELECT COUNT(*) FROM DatosGenerales.IDIOMA) AS idiomas_en_la_tabla
FROM #idiomas;
DROP TABLE #idiomas;

DROP TABLE IF EXISTS #tipos_gol;
CREATE TABLE #tipos_gol (id_tipo_gol TINYINT, descripcion VARCHAR(40), es_en_contra BIT);
INSERT INTO #tipos_gol EXEC DesarrolloPartido.usp_ConsultarTiposGol;
SELECT 'CO6 tipos de gol' AS caso, COUNT(*) AS tipos_de_gol,
       (SELECT COUNT(*) FROM DesarrolloPartido.TIPO_GOL) AS tipos_en_la_tabla
FROM #tipos_gol;
DROP TABLE #tipos_gol;
GO


/* CO7 Permisos.
   Esperado:
     usr_administrador (rol_AdministradorOperativo): SELECT directo sobre
       Torneo.SEDE denegado; usp_ConsultarSedes y usp_ConsultarSede permitidos
       (encadenamiento de propiedad).
     usr_consulta (rol_ConsultaReportes): usp_ConsultarSedes denegado (las
       sedes las lee en Reportes.vw_Sedes); usp_ConsultarPaises permitido, y
       SELECT directo sobre DatosGenerales.PAIS denegado. */
DECLARE @id_sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio José María Minella1');
DECLARE @filas INT;
DROP TABLE IF EXISTS #sedes;
CREATE TABLE #sedes (id_sede INT, nombre_estadio VARCHAR(100), ciudad VARCHAR(80), pais VARCHAR(60),
                     capacidad INT, huso_horario VARCHAR(50), espacios INT);

EXECUTE AS USER = 'usr_administrador';
BEGIN TRY
    SELECT @filas = COUNT(*) FROM Torneo.SEDE;
    PRINT N'CO7a: FALLÓ, el administrador leyó la tabla Torneo.SEDE directamente.';
END TRY
BEGIN CATCH
    PRINT N'CO7a: OK, SELECT directo denegado al administrador: ' + ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    INSERT INTO #sedes EXEC Torneo.usp_ConsultarSedes @buscar = N'Minella1';
    EXEC Torneo.usp_ConsultarSede @id_sede = @id_sede;
    SELECT @filas = COUNT(*) FROM #sedes;
    PRINT CONCAT(N'CO7b: OK, el administrador consulta las sedes con los SP (', @filas, N' sede).');
END TRY
BEGIN CATCH
    PRINT N'CO7b: FALLÓ, ' + ERROR_MESSAGE();
END CATCH;
REVERT;

EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    EXEC Torneo.usp_ConsultarSedes;
    PRINT N'CO7c: FALLÓ, el usuario de consulta ejecutó usp_ConsultarSedes.';
END TRY
BEGIN CATCH
    PRINT N'CO7c: OK, usp_ConsultarSedes denegado al usuario de consulta: ' + ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    EXEC DatosGenerales.usp_ConsultarPaises;
    PRINT N'CO7d: OK, el usuario de consulta consulta los países con el SP.';
END TRY
BEGIN CATCH
    PRINT N'CO7d: FALLÓ, ' + ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    SELECT @filas = COUNT(*) FROM DatosGenerales.PAIS;
    PRINT N'CO7e: FALLÓ, el usuario de consulta leyó la tabla DatosGenerales.PAIS directamente.';
END TRY
BEGIN CATCH
    PRINT N'CO7e: OK, SELECT directo sobre DatosGenerales.PAIS denegado al usuario de consulta: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
DROP TABLE #sedes;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 sedes de prueba.
   ============================================================================ */
ROLLBACK TRANSACTION;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio José María Minella1') AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
