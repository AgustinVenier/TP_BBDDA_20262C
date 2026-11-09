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
 Archivo: 82_Test_Rol_CargadorResultados.sql
 Objetivo: Demostrar los permisos que tiene y que no tiene el usuario
           usr_test_cargador_resultados (rol_CargadorResultados).
================================================================================

 Requiere haber ejecutado 37_Ejecutar_PrepararBase.sql (roles), las
 importaciones y 38_Ejecutar_Cifrado.sql. Los usuarios usr_test_* son
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
GO

SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_cargador_resultados') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 40_Seguridad.sql (lo incluye 37_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 38_Ejecutar_Cifrado.sql.', 1;
GO

/* 1. Permisos declarados. */
DECLARE @permisos TABLE (
    control     NVARCHAR(180) NOT NULL,
    permitido   BIT           NULL,
    esperado    BIT           NOT NULL
);

EXECUTE AS USER = N'usr_test_cargador_resultados';
INSERT INTO @permisos (control, permitido, esperado)
VALUES
    (N'Iniciar un partido', HAS_PERMS_BY_NAME(N'Torneo.usp_IniciarPartido', N'OBJECT', N'EXECUTE'), 1),
    (N'Finalizar un partido', HAS_PERMS_BY_NAME(N'Torneo.usp_FinalizarPartido', N'OBJECT', N'EXECUTE'), 1),
    (N'Registrar formaciones', HAS_PERMS_BY_NAME(N'DesarrolloPartido.usp_RegistrarFormacion', N'OBJECT', N'EXECUTE'), 1),
    (N'Usar el tipo tabla de la formación', HAS_PERMS_BY_NAME(N'DesarrolloPartido.TT_ALINEACION', N'TYPE', N'EXECUTE'), 1),
    (N'Registrar goles', HAS_PERMS_BY_NAME(N'DesarrolloPartido.usp_RegistrarGol', N'OBJECT', N'EXECUTE'), 1),
    (N'Registrar amonestaciones', HAS_PERMS_BY_NAME(N'DesarrolloPartido.usp_RegistrarAmonestacion', N'OBJECT', N'EXECUTE'), 1),
    (N'Asignar publicidad', HAS_PERMS_BY_NAME(N'Publicidad.usp_AsignarPublicidadPartido', N'OBJECT', N'EXECUTE'), 0),
    (N'Dar de alta jugadores', HAS_PERMS_BY_NAME(N'Torneo.usp_JUGADOR_Alta', N'OBJECT', N'EXECUTE'), 0),
    (N'Consultar reportes', HAS_PERMS_BY_NAME(N'Reportes.usp_Goleadores', N'OBJECT', N'EXECUTE'), 0),
    (N'Leer los partidos (Reportes.vw_Resultados)', HAS_PERMS_BY_NAME(N'Reportes.vw_Resultados', N'OBJECT', N'SELECT'), 1),
    (N'Leer las plantillas (Reportes.vw_Plantillas)', HAS_PERMS_BY_NAME(N'Reportes.vw_Plantillas', N'OBJECT', N'SELECT'), 1),
    (N'Leer otro reporte (Reportes.vw_Tarjetas)', HAS_PERMS_BY_NAME(N'Reportes.vw_Tarjetas', N'OBJECT', N'SELECT'), 0),
    (N'Leer tabla de jugadores directamente', HAS_PERMS_BY_NAME(N'Torneo.JUGADOR', N'OBJECT', N'SELECT'), 0),
    (N'Insertar tarjetas directamente', HAS_PERMS_BY_NAME(N'DesarrolloPartido.AMONESTACION', N'OBJECT', N'INSERT'), 0),
    (N'Leer la vista descifrada de jugadores directamente', HAS_PERMS_BY_NAME(N'Seguridad.vw_Jugador', N'OBJECT', N'SELECT'), 0),
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
DECLARE @usuario SYSNAME = N'usr_test_cargador_resultados';
DECLARE @p1 INT, @p2 INT, @p3 INT, @cifrado VARBINARY(256);

-- Un partido finalizado y un titular de ese partido sin tarjetas (para registrarle una amarilla).
SELECT TOP (1) @p1 = f.id_partido, @p2 = a.id_jugador
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
WHERE p.estado = 'FINALIZADO' AND a.es_titular = 1
  AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS am
                  WHERE am.id_partido = f.id_partido AND am.id_jugador = a.id_jugador)
ORDER BY f.id_partido, a.id_jugador;

DECLARE @casos TABLE (n INT IDENTITY, control NVARCHAR(200), esperado VARCHAR(12), sentencia NVARCHAR(MAX));
INSERT INTO @casos (control, esperado, sentencia) VALUES
 (N'Registrar una amarilla; el resultado muestra al jugador descifrado', 'DESCIFRA',
  N'DECLARE @x TABLE (dorsal TINYINT, apellido NVARCHAR(60), nombre NVARCHAR(60), amarillas INT, rojas INT,
                     suspension VARCHAR(100), partidos INT);
    INSERT INTO @x EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @p1, @tipo_tarjeta = ''AMARILLA'',
         @minuto = 10, @motivo = ''Prueba de rol'', @id_jugador = @p2;
    SELECT @dato = CONCAT(dorsal, N''. '') + apellido + N'', '' + nombre + CONCAT(N'' - amarillas: '', amarillas) FROM @x;'),
 (N'Registrar una formación (tipo tabla DesarrolloPartido.TT_ALINEACION)', 'PERMITIDO',
  N'DECLARE @t DesarrolloPartido.TT_ALINEACION;
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @p1, @id_seleccion = NULL, @esquema_tactico = NULL,
         @jugadores = @t, @mostrar = 0;'),
 (N'Iniciar un partido', 'PERMITIDO',
  N'EXEC Torneo.usp_IniciarPartido @id_partido = @p1;'),
 (N'Registrar un gol', 'PERMITIDO',
  N'EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = NULL, @id_jugador_autor = NULL, @id_tipo_gol = NULL,
         @periodo = NULL, @minuto = NULL, @minuto_adicional = NULL, @id_jugador_asistencia = NULL;'),
 (N'Finalizar un partido', 'PERMITIDO',
  N'EXEC Torneo.usp_FinalizarPartido @id_partido = NULL, @asistencia = NULL, @goles_local = NULL, @goles_visitante = NULL;'),
 (N'Dar de alta un jugador', 'DENEGADO',
  N'EXEC Torneo.usp_JUGADOR_Alta @id_lista = NULL, @nombre = NULL, @apellido = NULL, @posicion_habitual = NULL, @dorsal = NULL;'),
 (N'Asignar la publicidad de un partido', 'DENEGADO',
  N'EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @p1;'),
 (N'Leer Reportes.vw_Resultados: los partidos para cargar', 'PERMITIDO',
  N'SELECT TOP (1) @dato = CONCAT(N''Partido '', id_partido, N'': '', estado) FROM Reportes.vw_Resultados ORDER BY id_partido;'),
 (N'Leer Reportes.vw_Plantillas: los jugadores para cargar, con el nombre descifrado', 'DESCIFRA',
  N'SELECT TOP (1) @dato = CONCAT(id_jugador, N'' - '', dorsal, N''. '') + apellido + N'', '' + nombre
    FROM Reportes.vw_Plantillas ORDER BY id_jugador;'),
 (N'Leer otro reporte (Reportes.vw_Tarjetas)', 'DENEGADO',
  N'SELECT TOP (1) @dato = persona FROM Reportes.vw_Tarjetas;'),
 (N'Leer la tabla Torneo.JUGADOR directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = CAST(id_jugador AS NVARCHAR(10)) FROM Torneo.JUGADOR;'),
 (N'Insertar una tarjeta directamente', 'DENEGADO',
  N'INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto) VALUES (@p1, @p2, ''AMARILLA'', 1);'),
 (N'Leer la vista descifrada Seguridad.vw_Jugador directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = apellido FROM Seguridad.vw_Jugador;');

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
