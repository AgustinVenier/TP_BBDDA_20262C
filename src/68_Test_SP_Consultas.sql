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
 Archivo: 68_Test_SP_Consultas.sql
 Objetivo: Probar los SP de consulta de 18_SP_Consultas.sql y que funcionan con
           un usuario de rol_AdministradorOperativo, que no puede leer las
           tablas directamente. Requiere haber ejecutado 00 a 20 y 40 (roles);
           no depende del juego de datos.
           Usa una sede de prueba ("Estadio Prueba Consultas", con foto) que
           se borra al empezar y al terminar, así que se puede ejecutar más de
           una vez.
================================================================================

 Cómo leer los resultados:
   - Cada caso muestra lo que devuelve el SP (columna "caso" cuando hace falta).
   - Casos de permisos: en Mensajes se imprime "OK" si el permiso es el
     esperado y "FALLÓ" si no.
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_ConsultarSedes', N'P') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'usr_test_administrador') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG')
BEGIN
    RAISERROR(N'Faltan los SP de consulta, los roles o los datos iniciales: ejecutar 00 a 20 y 40.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Limpieza previa y sede de prueba con su foto.
DECLARE @id INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Consultas');
IF @id IS NOT NULL
    EXEC Torneo.usp_EliminarSede @id_sede = @id, @mostrar = 0;

DECLARE @arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
EXEC Torneo.usp_RegistrarSede
    @nombre_estadio = 'Estadio Prueba Consultas', @ciudad = 'Mar del Plata', @id_pais = @arg, @capacidad = 35000,
    @huso_horario = 'Argentina Standard Time', @tarifa_espacio_1 = 4000, @tarifa_espacio_2 = 3000,
    @tarifa_espacio_3 = 2000, @tarifa_espacio_4 = 1000, @latitud = -38.016667, @longitud = -57.583333,
    @id_sede = @id OUTPUT, @mostrar = 0;
EXEC Torneo.usp_SEDE_IMAGEN_Alta @id_sede = @id, @imagen = 0xFFD8FFE000104A464946;
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
EXEC DatosGenerales.usp_ConsultarParametroReglamento @codigo = 'MAX_CONVOCADOS', @valor = @valor OUTPUT, @mostrar = 0;
EXEC DatosGenerales.usp_ConsultarParametroReglamento @codigo = 'NO_EXISTE', @valor = @inexistente OUTPUT, @mostrar = 0;
SELECT 'CO2' AS caso, @valor AS max_convocados, @inexistente AS codigo_inexistente;
GO

/* CO3 Sedes con búsqueda.
   Esperado: buscando "Mar del Plata" (la ciudad) aparece solo la sede de
   prueba, con sus 4 espacios; buscando "Prueba Consultas" (el estadio), lo
   mismo; una búsqueda sin coincidencias devuelve 0 filas. */
EXEC Torneo.usp_ConsultarSedes @buscar = N'Mar del Plata';
EXEC Torneo.usp_ConsultarSedes @buscar = N'Prueba Consultas';
EXEC Torneo.usp_ConsultarSedes @buscar = N'zzz sin coincidencias';
GO

/* CO4 Una sede y su foto.
   Esperado: la sede de prueba con tarifas 4000, 3000, 2000 y 1000; su foto
   JPEG de 10 bytes; una sede que no existe devuelve 0 filas, sin error. */
DECLARE @id INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Consultas');
EXEC Torneo.usp_ConsultarSede @id_sede = @id;
EXEC Torneo.usp_ConsultarImagenSede @id_sede = @id;
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


/* CO6 Permisos.
   Esperado:
     usr_test_administrador (rol_AdministradorOperativo): SELECT directo sobre
       Torneo.SEDE denegado; usp_ConsultarSedes y usp_ConsultarSede permitidos
       (encadenamiento de propiedad).
     usr_test_consulta (rol_ConsultaReportes): usp_ConsultarSedes denegado (solo
       tiene el esquema Reportes). */
DECLARE @id INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Consultas');
DECLARE @filas INT;
DROP TABLE IF EXISTS #sedes;
CREATE TABLE #sedes (id_sede INT, nombre_estadio VARCHAR(100), ciudad VARCHAR(80), pais VARCHAR(60),
                     capacidad INT, huso_horario VARCHAR(50), espacios INT);

EXECUTE AS USER = 'usr_test_administrador';
BEGIN TRY
    SELECT @filas = COUNT(*) FROM Torneo.SEDE;
    PRINT N'CO6a: FALLÓ, el administrador leyó la tabla Torneo.SEDE directamente.';
END TRY
BEGIN CATCH
    PRINT N'CO6a: OK, SELECT directo denegado al administrador: ' + ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    INSERT INTO #sedes EXEC Torneo.usp_ConsultarSedes @buscar = N'Prueba Consultas';
    EXEC Torneo.usp_ConsultarSede @id_sede = @id;
    SELECT @filas = COUNT(*) FROM #sedes;
    PRINT CONCAT(N'CO6b: OK, el administrador consulta las sedes con los SP (', @filas, N' sede).');
END TRY
BEGIN CATCH
    PRINT N'CO6b: FALLÓ, ' + ERROR_MESSAGE();
END CATCH;
REVERT;

EXECUTE AS USER = 'usr_test_consulta';
BEGIN TRY
    EXEC Torneo.usp_ConsultarSedes;
    PRINT N'CO6c: FALLÓ, el usuario de consulta ejecutó usp_ConsultarSedes.';
END TRY
BEGIN CATCH
    PRINT N'CO6c: OK, usp_ConsultarSedes denegado al usuario de consulta: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
DROP TABLE #sedes;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 sedes de prueba.
   ============================================================================ */
DECLARE @id INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Consultas');
IF @id IS NOT NULL
    EXEC Torneo.usp_EliminarSede @id_sede = @id, @mostrar = 0;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Consultas') AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
