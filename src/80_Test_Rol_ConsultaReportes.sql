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

 Fecha: 08/11/2026
 Archivo: 80_Test_Rol_ConsultaReportes.sql
 Objetivo: Demostrar los permisos que tiene y que no tiene el usuario
           usr_test_consulta (rol_ConsultaReportes).
================================================================================

 Requiere haber ejecutado 00_Ejecutar_PrepararBase.sql (roles), las
 importaciones y 40_Ejecutar_Cifrado.sql. Los usuarios usr_test_* son
 principals SIN LOGIN; solo sirven para impersonación de prueba.

 Dos partes:
   1. Permisos declarados (HAS_PERMS_BY_NAME), incluidos los de la clave de
      cifrado.
   2. Ejecución real: cada caso se ejecuta como el usuario (EXECUTE AS USER)
      dentro de una transacción que se deshace, así no queda nada. Resultados:
        PERMITIDO    se ejecutó, o pasó el control de permisos y lo rechazó la
                     validación del SP (se ve el mensaje).
        DENEGADO     SQL Server lo rechazó por permisos.
        DESCIFRA     lee los datos personales legibles.
        NO DESCIFRA  los lee como NULL (sin permiso sobre la clave).
 Si algún caso no da lo esperado, el script termina con error.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los índices filtrados y los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_consulta') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 27_SP_Roles.sql (lo incluye 00_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
GO

/* 1. Permisos declarados. */
DECLARE @permisos TABLE (
    control     NVARCHAR(180) NOT NULL,
    permitido   BIT           NULL,
    esperado    BIT           NOT NULL
);

EXECUTE AS USER = N'usr_test_consulta';
INSERT INTO @permisos (control, permitido, esperado)
VALUES
    (N'Leer vista de sedes', HAS_PERMS_BY_NAME(N'Reportes.vw_Sedes', N'OBJECT', N'SELECT'), 1),
    (N'Leer vista de plantillas', HAS_PERMS_BY_NAME(N'Reportes.vw_Plantillas', N'OBJECT', N'SELECT'), 1),
    (N'Ejecutar reporte de goleadores', HAS_PERMS_BY_NAME(N'Reportes.usp_Goleadores', N'OBJECT', N'EXECUTE'), 1),
    (N'Ejecutar reporte de publicidad', HAS_PERMS_BY_NAME(N'Reportes.usp_OcupacionPublicitaria', N'OBJECT', N'EXECUTE'), 1),
    (N'Finalizar un partido', HAS_PERMS_BY_NAME(N'Torneo.usp_FinalizarPartido', N'OBJECT', N'EXECUTE'), 0),
    (N'Asignar publicidad', HAS_PERMS_BY_NAME(N'Publicidad.usp_AsignarPublicidadPartido', N'OBJECT', N'EXECUTE'), 0),
    (N'Leer jugadores directamente', HAS_PERMS_BY_NAME(N'Torneo.JUGADOR', N'OBJECT', N'SELECT'), 0),
    (N'Actualizar una vista de reportes', HAS_PERMS_BY_NAME(N'Reportes.vw_Resultados', N'OBJECT', N'UPDATE'), 0),
    (N'Leer la vista descifrada de árbitros directamente', HAS_PERMS_BY_NAME(N'Seguridad.vw_Arbitro', N'OBJECT', N'SELECT'), 0),
    (N'Ver la clave de cifrado', HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', N'SYMMETRIC KEY', N'VIEW DEFINITION'), 1),
    (N'Usar el certificado (para descifrar)', HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'CONTROL'), 1),
    (N'Modificar el certificado (quitarle la clave privada)', HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'ALTER'), 0);
REVERT;

SELECT control,
       permitido AS permiso_efectivo,
       esperado AS permiso_esperado,
       CASE WHEN ISNULL(permitido, 0) = esperado THEN N'OK' ELSE N'FALLÓ' END AS resultado
FROM @permisos
ORDER BY control;

IF EXISTS (SELECT 1 FROM @permisos WHERE ISNULL(permitido, 0) <> esperado)
    THROW 51011, N'La matriz de permisos no coincide con lo esperado para este rol.', 1;
GO

/* 2. Ejecución real. Los ids de prueba los busca dbo: el rol no puede leer las tablas. */
DECLARE @usuario SYSNAME = N'usr_test_consulta';
DECLARE @p1 INT, @p2 INT, @p3 INT, @cifrado VARBINARY(256);

SELECT TOP (1) @p1 = id_seleccion FROM Torneo.SELECCION ORDER BY id_seleccion;

DECLARE @casos TABLE (n INT IDENTITY, control NVARCHAR(200), esperado VARCHAR(12), sentencia NVARCHAR(MAX));
INSERT INTO @casos (control, esperado, sentencia) VALUES
 (N'Leer Reportes.vw_Plantillas: nombre y apellido descifrados', 'DESCIFRA',
  N'SELECT TOP (1) @dato = nombre + N'' '' + apellido FROM Reportes.vw_Plantillas ORDER BY id_jugador;'),
 (N'Leer Reportes.vw_Tarjetas: persona amonestada descifrada', 'DESCIFRA',
  N'SELECT TOP (1) @dato = persona FROM Reportes.vw_Tarjetas ORDER BY id_amonestacion;'),
 (N'Leer Reportes.vw_DesignacionesArbitrales: árbitro descifrado', 'DESCIFRA',
  N'SELECT TOP (1) @dato = arbitro FROM Reportes.vw_DesignacionesArbitrales ORDER BY id_partido, rol;'),
 (N'Reporte XML de selecciones y plantillas: nombres descifrados', 'DESCIFRA',
  N'DECLARE @x TABLE (r XML); INSERT INTO @x EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = @p1;
    SELECT @dato = LEFT(CONVERT(NVARCHAR(MAX), r.query(''(//DirectorTecnico)[1]'')), 300) FROM @x;'),
 (N'Leer Reportes.vw_Sedes', 'PERMITIDO',
  N'SELECT @dato = CONCAT(COUNT(*), N'' sedes'') FROM Reportes.vw_Sedes;'),
 (N'Dar de alta un jugador', 'DENEGADO',
  N'EXEC Torneo.usp_JUGADOR_Alta @id_lista = NULL, @nombre = NULL, @apellido = NULL, @posicion_habitual = NULL, @dorsal = NULL;'),
 (N'Registrar un gol', 'DENEGADO',
  N'EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = NULL, @id_jugador_autor = NULL, @id_tipo_gol = NULL,
         @periodo = NULL, @minuto = NULL, @minuto_adicional = NULL, @id_jugador_asistencia = NULL;'),
 (N'Alta de un anunciante', 'DENEGADO',
  N'EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = NULL, @id_pais = NULL;'),
 (N'Leer la tabla Torneo.JUGADOR directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = CAST(id_jugador AS NVARCHAR(10)) FROM Torneo.JUGADOR;'),
 (N'Leer la vista descifrada Seguridad.vw_Arbitro directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = apellido FROM Seguridad.vw_Arbitro;'),
 (N'Abrir la clave con Seguridad.usp_AbrirClave directamente', 'DENEGADO',
  N'EXEC Seguridad.usp_AbrirClave;');

DECLARE @res TABLE (n INT, control NVARCHAR(200), esperado VARCHAR(12), obtenido VARCHAR(12), detalle NVARCHAR(400));
DECLARE @i INT = 1, @sql NVARCHAR(MAX), @dato NVARCHAR(400), @err INT, @msg NVARCHAR(400);
WHILE @i <= (SELECT MAX(n) FROM @casos)
BEGIN
    SELECT @sql = sentencia FROM @casos WHERE n = @i;
    SELECT @dato = NULL, @err = 0, @msg = NULL;
    BEGIN TRANSACTION;
    EXECUTE AS USER = @usuario;
    BEGIN TRY
        EXEC sys.sp_executesql @sql,
             N'@dato NVARCHAR(400) OUTPUT, @p1 INT, @p2 INT, @p3 INT, @cifrado VARBINARY(256)',
             @dato = @dato OUTPUT, @p1 = @p1, @p2 = @p2, @p3 = @p3, @cifrado = @cifrado;
    END TRY
    BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = LEFT(ERROR_MESSAGE(), 400);
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- antes de REVERT: deshace lo que hizo el caso
    REVERT;
    INSERT INTO @res (n, control, esperado, obtenido, detalle)
    SELECT n, control, esperado,
           CASE WHEN @err IN (229, 230, 262, 297, 300, 15151, 15247) THEN 'DENEGADO'
                WHEN esperado IN ('DESCIFRA', 'NO DESCIFRA') AND @err = 0 THEN IIF(@dato IS NULL, 'NO DESCIFRA', 'DESCIFRA')
                ELSE 'PERMITIDO' END,
           REPLACE(REPLACE(ISNULL(@dato, @msg), CHAR(13), N' '), CHAR(10), N'')
    FROM @casos WHERE n = @i;
    SET @i += 1;
END;

SELECT n, control, esperado, obtenido,
       IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado,
       detalle
FROM @res
ORDER BY n;

IF EXISTS (SELECT 1 FROM @res WHERE esperado <> obtenido)
    THROW 51013, N'La ejecución real no coincide con lo esperado para este rol.', 1;
GO
