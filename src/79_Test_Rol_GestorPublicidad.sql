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
 Archivo: 79_Test_Rol_GestorPublicidad.sql
 Objetivo: Demostrar los permisos que tiene y que no tiene el usuario
           usr_test_gestor_publicidad (rol_GestorPublicidad).
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
 Este rol no trabaja con datos personales: aunque tuviera los bytes cifrados
 de un nombre, no puede descifrarlos.
 Si algún caso no da lo esperado, el script termina con error.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los índices filtrados y los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_gestor_publicidad') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 27_SP_Roles.sql (lo incluye 00_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR)
    THROW 51013, N'No hay datos del torneo cargados. Ejecute primero las importaciones (30 a 35).', 1;
GO

/* 1. Permisos declarados. */
DECLARE @permisos TABLE (
    control     NVARCHAR(180) NOT NULL,
    permitido   BIT           NULL,
    esperado    BIT           NOT NULL
);

EXECUTE AS USER = N'usr_test_gestor_publicidad';
INSERT INTO @permisos (control, permitido, esperado)
VALUES
    (N'Administrar piezas publicitarias', HAS_PERMS_BY_NAME(N'Publicidad.usp_RegistrarPiezaPublicitaria', N'OBJECT', N'EXECUTE'), 1),
    (N'Asignar publicidad a partidos', HAS_PERMS_BY_NAME(N'Publicidad.usp_AsignarPublicidadPartido', N'OBJECT', N'EXECUTE'), 1),
    (N'Consultar ocupación publicitaria', HAS_PERMS_BY_NAME(N'Reportes.usp_OcupacionPublicitaria', N'OBJECT', N'EXECUTE'), 1),
    (N'Leer la vista de ingresos por moneda', HAS_PERMS_BY_NAME(N'Reportes.vw_IngresosPublicitariosPorMoneda', N'OBJECT', N'SELECT'), 1),
    (N'Consultar reportes deportivos', HAS_PERMS_BY_NAME(N'Reportes.usp_Goleadores', N'OBJECT', N'EXECUTE'), 0),
    (N'Leer las plantillas', HAS_PERMS_BY_NAME(N'Reportes.vw_Plantillas', N'OBJECT', N'SELECT'), 0),
    (N'Leer anunciantes directamente', HAS_PERMS_BY_NAME(N'Publicidad.ANUNCIANTE', N'OBJECT', N'SELECT'), 0),
    (N'Modificar exhibiciones directamente', HAS_PERMS_BY_NAME(N'Publicidad.EXHIBICION', N'OBJECT', N'UPDATE'), 0),
    (N'Ver la clave de cifrado', HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', N'SYMMETRIC KEY', N'VIEW DEFINITION'), 0),
    (N'Usar el certificado (para descifrar)', HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'CONTROL'), 0);
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

/* 2. Ejecución real. Los datos de prueba los busca dbo: el rol no puede leer las tablas. */
DECLARE @usuario SYSNAME = N'usr_test_gestor_publicidad';
DECLARE @p1 INT, @p2 INT, @p3 INT, @cifrado VARBINARY(256);

SELECT TOP (1) @p1 = id_partido FROM Torneo.PARTIDO ORDER BY id_partido;
SELECT TOP (1) @cifrado = apellido FROM Torneo.JUGADOR ORDER BY id_jugador;   -- el apellido guardado (cifrado) de un jugador

DECLARE @casos TABLE (n INT IDENTITY, control NVARCHAR(200), esperado VARCHAR(12), sentencia NVARCHAR(MAX));
INSERT INTO @casos (control, esperado, sentencia) VALUES
 (N'Alta de un anunciante', 'PERMITIDO',
  N'EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = NULL, @id_pais = NULL;'),
 (N'Asignar la publicidad de un partido', 'PERMITIDO',
  N'EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @p1, @mostrar = 0;'),
 (N'Leer la ocupación publicitaria', 'PERMITIDO',
  N'SELECT @dato = CONCAT(COUNT(*), N'' filas'') FROM Reportes.vw_OcupacionPublicitaria;'),
 (N'Leer los ingresos por moneda', 'PERMITIDO',
  N'SELECT @dato = CONCAT(COUNT(*), N'' filas'') FROM Reportes.vw_IngresosPublicitariosPorMoneda;'),
 (N'Leer Reportes.vw_Plantillas (datos personales)', 'DENEGADO',
  N'SELECT TOP (1) @dato = apellido FROM Reportes.vw_Plantillas;'),
 (N'Leer Reportes.vw_Goles', 'DENEGADO',
  N'SELECT TOP (1) @dato = jugador FROM Reportes.vw_Goles;'),
 (N'Dar de alta un jugador', 'DENEGADO',
  N'EXEC Torneo.usp_JUGADOR_Alta @id_lista = NULL, @nombre = NULL, @apellido = NULL, @posicion_habitual = NULL, @dorsal = NULL;'),
 (N'Leer la tabla Publicidad.ANUNCIANTE directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = razon_social FROM Publicidad.ANUNCIANTE;'),
 (N'Descifrar el apellido cifrado de un jugador (con los bytes en mano)', 'NO DESCIFRA',
  N'SELECT @dato = CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N''CertDatosPersonales''), NULL, @cifrado));'),
 (N'Abrir la clave de cifrado', 'DENEGADO',
  N'OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;');

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
IF EXISTS (SELECT 1 FROM sys.openkeys) CLOSE ALL SYMMETRIC KEYS;

SELECT n, control, esperado, obtenido,
       IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado,
       detalle
FROM @res
ORDER BY n;

IF EXISTS (SELECT 1 FROM @res WHERE esperado <> obtenido)
    THROW 51013, N'La ejecución real no coincide con lo esperado para este rol.', 1;
GO
