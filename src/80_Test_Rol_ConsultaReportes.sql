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

 Fecha: 10/11/2026
 Archivo: 80_Test_Rol_ConsultaReportes.sql
 Objetivo: Probar lo que puede y lo que no puede hacer el usuario
           usr_test_consulta (rol_ConsultaReportes).
================================================================================

 Requiere haber ejecutado 00_Ejecutar_PrepararBase.sql (roles), las
 importaciones y 40_Ejecutar_Cifrado.sql.

 usr_test_consulta es un usuario SIN LOGIN: nadie puede iniciar sesión con él.
 Cada caso se ejecuta "como" ese usuario con EXECUTE AS USER y vuelve a dbo
 con REVERT.

 Cada caso imprime una línea en la pestaña Mensajes:
   OK     el usuario pudo hacer lo que debe poder, o fue rechazado en lo
          que no debe poder (se muestra el mensaje de SQL Server).
   ERROR  pasó lo contrario de lo esperado.
 El test está bien si ninguna línea empieza con ERROR.

 Lo que PUEDE hacer: leer las vistas y ejecutar los SP de Reportes, con los
 nombres de las personas descifrados; y consultar los países
 (DatosGenerales.usp_ConsultarPaises).
 Lo que NO PUEDE hacer: leer o modificar las tablas, ejecutar SP que cargan
 datos, ni usar directamente los objetos de cifrado (esquema Seguridad).

 Los casos que no debe poder hacer no cambian nada aunque el permiso
 estuviera mal dado: los SP reciben datos vacíos (los rechaza su validación)
 y el DELETE no borra ninguna fila (WHERE 1 = 0).
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_consulta') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 27_SP_Roles.sql (lo incluye 00_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
GO

PRINT N'=== Lo que PUEDE hacer usr_test_consulta ===';
GO


/* Caso 1: PUEDE leer la vista de sedes. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    SELECT TOP (5) * FROM Reportes.vw_Sedes;
    PRINT N'OK     1. Puede leer Reportes.vw_Sedes.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  1. No pudo leer Reportes.vw_Sedes: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 2: PUEDE leer las plantillas, con nombre y apellido descifrados.
   Si no tuviera permiso sobre la clave, la vista se lee igual pero los
   nombres salen NULL. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    SELECT TOP (5) seleccion, dorsal, apellido, nombre
    FROM Reportes.vw_Plantillas
    ORDER BY id_seleccion, dorsal;

    IF EXISTS (SELECT 1 FROM Reportes.vw_Plantillas WHERE apellido IS NULL OR nombre IS NULL)
        PRINT N'ERROR  2. Lee Reportes.vw_Plantillas, pero los nombres salen NULL: no descifra.';
    ELSE
        PRINT N'OK     2. Puede leer Reportes.vw_Plantillas con los nombres descifrados.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  2. No pudo leer Reportes.vw_Plantillas: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 3: PUEDE leer las designaciones arbitrales, con el árbitro descifrado.
   La vista arma "apellido, nombre": si no descifra, queda solo ", ". */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    SELECT TOP (5) numero_partido, partido, rol, arbitro
    FROM Reportes.vw_DesignacionesArbitrales
    ORDER BY numero_partido, rol;

    IF EXISTS (SELECT 1 FROM Reportes.vw_DesignacionesArbitrales WHERE arbitro = N', ')
        PRINT N'ERROR  3. Lee Reportes.vw_DesignacionesArbitrales, pero los árbitros salen vacíos: no descifra.';
    ELSE
        PRINT N'OK     3. Puede leer Reportes.vw_DesignacionesArbitrales con los árbitros descifrados.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  3. No pudo leer Reportes.vw_DesignacionesArbitrales: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 4: PUEDE ejecutar un SP de reportes. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    EXEC Reportes.usp_Goleadores;
    PRINT N'OK     4. Puede ejecutar Reportes.usp_Goleadores.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  4. No pudo ejecutar Reportes.usp_Goleadores: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 5: PUEDE consultar los países, con el SP de consulta. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    EXEC DatosGenerales.usp_ConsultarPaises;
    PRINT N'OK     5. Puede ejecutar DatosGenerales.usp_ConsultarPaises.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  5. No pudo ejecutar DatosGenerales.usp_ConsultarPaises: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


PRINT N'';
PRINT N'=== Lo que NO PUEDE hacer usr_test_consulta ===';
GO


/* Caso 6: NO PUEDE leer una tabla directamente. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    SELECT TOP (5) * FROM Torneo.JUGADOR;
    PRINT N'ERROR  6. Pudo leer la tabla Torneo.JUGADOR y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229   -- 229: permiso denegado
        PRINT N'OK     6. No puede leer Torneo.JUGADOR: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  6. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 7: NO PUEDE borrar en una tabla directamente. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    DELETE FROM DesarrolloPartido.GOL WHERE 1 = 0;
    PRINT N'ERROR  7. Pudo borrar en DesarrolloPartido.GOL y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     7. No puede borrar en DesarrolloPartido.GOL: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  7. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 8: NO PUEDE dar de alta un jugador. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = NULL, @nombre = NULL, @apellido = NULL,
                                 @posicion_habitual = NULL, @dorsal = NULL;
    PRINT N'ERROR  8. Pudo ejecutar Torneo.usp_JUGADOR_Alta y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     8. No puede ejecutar Torneo.usp_JUGADOR_Alta: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  8. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 9: NO PUEDE registrar un gol. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = NULL, @id_jugador_autor = NULL,
                                            @id_tipo_gol = NULL, @periodo = NULL;
    PRINT N'ERROR  9. Pudo ejecutar DesarrolloPartido.usp_RegistrarGol y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     9. No puede ejecutar DesarrolloPartido.usp_RegistrarGol: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  9. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 10: NO PUEDE dar de alta un anunciante. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = NULL, @id_pais = NULL;
    PRINT N'ERROR 10. Pudo ejecutar Publicidad.usp_ANUNCIANTE_Alta y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    10. No puede ejecutar Publicidad.usp_ANUNCIANTE_Alta: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 10. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 11: NO PUEDE leer la vista descifrada de jugadores directamente: los
   datos personales los ve solo a través de los reportes. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    SELECT TOP (5) id_jugador, apellido, nombre FROM Seguridad.vw_Jugador;
    PRINT N'ERROR 11. Pudo leer Seguridad.vw_Jugador y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    11. No puede leer Seguridad.vw_Jugador: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 11. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 12: NO PUEDE abrir la clave de cifrado por su cuenta. */
EXECUTE AS USER = N'usr_test_consulta';
BEGIN TRY
    EXEC Seguridad.usp_AbrirClave;
    PRINT N'ERROR 12. Pudo ejecutar Seguridad.usp_AbrirClave y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    12. No puede ejecutar Seguridad.usp_AbrirClave: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 12. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 13: NO PUEDE modificar el certificado (por ejemplo, quitarle la clave
   privada). No se intenta el ALTER: se pregunta si tiene el permiso. */
EXECUTE AS USER = N'usr_test_consulta';
IF HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'ALTER') = 0
    PRINT N'OK    13. No tiene permiso para modificar el certificado CertDatosPersonales.';
ELSE
    PRINT N'ERROR 13. Tiene permiso para modificar el certificado CertDatosPersonales y no debería.';
REVERT;
GO