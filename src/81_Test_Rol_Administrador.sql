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
 Archivo: 81_Test_Rol_Administrador.sql
 Objetivo: Demostrar los permisos que tiene y que no tiene el usuario
           usr_test_administrador (rol_AdministradorOperativo).
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

IF DATABASE_PRINCIPAL_ID(N'usr_test_administrador') IS NULL
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

EXECUTE AS USER = N'usr_test_administrador';
INSERT INTO @permisos (control, permitido, esperado)
VALUES
    (N'Ejecutar ABM de jugadores', HAS_PERMS_BY_NAME(N'Torneo.usp_JUGADOR_Alta', N'OBJECT', N'EXECUTE'), 1),
    (N'Ejecutar asignación de publicidad', HAS_PERMS_BY_NAME(N'Publicidad.usp_AsignarPublicidadPartido', N'OBJECT', N'EXECUTE'), 1),
    (N'Leer vista de resultados', HAS_PERMS_BY_NAME(N'Reportes.vw_Resultados', N'OBJECT', N'SELECT'), 1),
    (N'Invocar loader de archivos', HAS_PERMS_BY_NAME(N'Torneo.usp_ImportarPartidosJSON', N'OBJECT', N'EXECUTE'), 0),
    (N'Leer tabla de jugadores directamente', HAS_PERMS_BY_NAME(N'Torneo.JUGADOR', N'OBJECT', N'SELECT'), 0),
    (N'Insertar en tabla de jugadores directamente', HAS_PERMS_BY_NAME(N'Torneo.JUGADOR', N'OBJECT', N'INSERT'), 0),
    (N'Actualizar árbitros directamente', HAS_PERMS_BY_NAME(N'Arbitraje.ARBITRO', N'OBJECT', N'UPDATE'), 0),
    (N'Usar las funciones de cifrado directamente', HAS_PERMS_BY_NAME(N'Seguridad.fn_CifrarTexto', N'OBJECT', N'EXECUTE'), 0),
    (N'Leer la vista descifrada de jugadores directamente', HAS_PERMS_BY_NAME(N'Seguridad.vw_Jugador', N'OBJECT', N'SELECT'), 0),
    (N'Ver la clave de cifrado (para cifrar)', HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', N'SYMMETRIC KEY', N'VIEW DEFINITION'), 1),
    (N'Usar el certificado (para descifrar)', HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'CONTROL'), 1),
    (N'Modificar el certificado (quitarle la clave privada)', HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'ALTER'), 0),
    (N'Modificar o borrar la clave de cifrado', HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', N'SYMMETRIC KEY', N'ALTER'), 0);
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
DECLARE @usuario SYSNAME = N'usr_test_administrador';
DECLARE @p1 INT, @p2 INT, @p3 INT, @cifrado VARBINARY(256);

SELECT TOP (1) @p1 = l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l ORDER BY l.id_lista;           -- una lista
SELECT TOP (1) @p2 = j.id_jugador FROM Torneo.JUGADOR AS j                                        -- un convocado activo que no es arquero
WHERE j.id_lista = @p1 AND j.fecha_baja IS NULL AND j.posicion_habitual <> 'ARQUERO' ORDER BY j.dorsal;
SELECT TOP (1) @p3 = l.id_seleccion FROM Torneo.LISTA_CONVOCADOS AS l WHERE l.id_lista = @p1;

DECLARE @casos TABLE (n INT IDENTITY, control NVARCHAR(200), esperado VARCHAR(12), sentencia NVARCHAR(MAX));
INSERT INTO @casos (control, esperado, sentencia) VALUES
 (N'Baja y alta de un jugador con los SP de ABM; el alta se lee descifrada en Reportes.vw_Plantillas', 'DESCIFRA',
  N'DECLARE @id INT;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @p2, @motivo_baja = ''Prueba de rol'', @fecha_baja = ''2026-06-02'';
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @p1, @nombre = N''Prueba'', @apellido = N''Administrador'',
         @posicion_habitual = ''DEFENSOR'', @dorsal = 99, @fecha_nacimiento = ''2000-01-01'', @id_jugador = @id OUTPUT;
    SELECT @dato = nombre + N'' '' + apellido FROM Reportes.vw_Plantillas WHERE id_jugador = @id;'),
 (N'Alta de una persona del cuerpo técnico', 'PERMITIDO',
  N'DECLARE @id INT;
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @p3, @nombre = N''Prueba'', @apellido = N''Administrador'',
         @rol = ''MEDICO'', @id_persona_ct = @id OUTPUT;
    SET @dato = CONCAT(N''Alta con id_persona_ct '', @id);'),
 (N'Registrar una convocatoria (tipo tabla Torneo.TT_CONVOCADO)', 'PERMITIDO',
  N'DECLARE @t Torneo.TT_CONVOCADO; EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @p3, @jugadores = @t, @mostrar = 0;'),
 (N'Alta de un anunciante (Publicidad)', 'PERMITIDO',
  N'EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = NULL, @id_pais = NULL;'),
 (N'Leer Reportes.vw_Plantillas: nombres descifrados', 'DESCIFRA',
  N'SELECT TOP (1) @dato = nombre + N'' '' + apellido FROM Reportes.vw_Plantillas ORDER BY id_jugador;'),
 (N'Reporte XML de selecciones y plantillas: nombres descifrados', 'DESCIFRA',
  N'DECLARE @x TABLE (r XML); INSERT INTO @x EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = @p3;
    SELECT @dato = LEFT(CONVERT(NVARCHAR(MAX), r.query(''(//Jugador)[1]'')), 300) FROM @x;'),
 (N'Leer la tabla Torneo.JUGADOR directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = CAST(id_jugador AS NVARCHAR(10)) FROM Torneo.JUGADOR;'),
 (N'Borrar goles directamente', 'DENEGADO',
  N'DELETE FROM DesarrolloPartido.GOL WHERE 1 = 0;'),
 (N'Importar un archivo (loader con BULK)', 'DENEGADO',
  N'EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = N''C:\no\existe.csv'';'),
 (N'Leer la vista descifrada Seguridad.vw_Jugador directamente', 'DENEGADO',
  N'SELECT TOP (1) @dato = apellido FROM Seguridad.vw_Jugador;'),
 (N'Cifrar con Seguridad.fn_CifrarTexto directamente', 'DENEGADO',
  N'SELECT @dato = CONVERT(NVARCHAR(400), Seguridad.fn_CifrarTexto(N''x''), 1);'),
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
