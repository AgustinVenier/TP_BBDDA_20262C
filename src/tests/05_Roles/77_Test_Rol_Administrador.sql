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
 Archivo: 77_Test_Rol_Administrador.sql
 Objetivo: Probar lo que puede y lo que no puede hacer el usuario
           usr_administrador (rol_AdministradorOperativo).
================================================================================

 Requiere haber ejecutado 00_Ejecutar_PrepararBase.sql (roles), las
 importaciones y 40_Ejecutar_Cifrado.sql.

 usr_administrador es un usuario SIN LOGIN: nadie puede iniciar sesión
 con él. Cada caso se ejecuta "como" ese usuario con EXECUTE AS USER y vuelve
 a dbo con REVERT.

 Cada caso imprime una línea en la pestaña Mensajes:
   OK     el usuario pudo hacer lo que debe poder, o fue rechazado en lo
          que no debe poder (se muestra el mensaje de SQL Server).
   ERROR  pasó lo contrario de lo esperado.
 El test está bien si ninguna línea empieza con ERROR.

 Lo que PUEDE hacer: los ABM y los SP de negocio de todos los módulos, y los
 reportes, con los nombres de las personas descifrados. Al dar de alta o
 modificar personas, los SP cifran sus datos personales. También consulta
 los catálogos (países, idiomas, tipos de gol...) con los SP de consulta,
 para elegir los valores que piden los SP.
 Lo que NO PUEDE hacer: leer o modificar las tablas directamente (tampoco
 las de los catálogos), las
 importaciones que leen archivos del servidor, ni usar directamente los
 objetos de cifrado, ni modificar el certificado o la clave.

 Los SP que puede ejecutar se prueban de dos formas:
   - El alta de un árbitro se hace de verdad, dentro de una transacción que
     el mismo usuario deshace al final del caso: no queda guardada.
   - Los demás reciben datos vacíos: pasan el control de permisos y los
     rechaza la validación del SP (error 50000 o mayor), sin guardar nada.
     Si el rechazo fuera por permisos (error 229), el caso da ERROR.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_administrador') IS NULL
    THROW 51010, N'Falta el usuario del rol. Ejecute primero 27_SP_Roles.sql (lo incluye 00_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR)
    THROW 51013, N'No hay datos del torneo cargados. Ejecute primero las importaciones (31 a 35).', 1;
GO

PRINT N'=== Lo que PUEDE hacer usr_administrador ===';
GO


/* Caso 1: PUEDE leer las plantillas, con nombre y apellido descifrados.
   Si no tuviera permiso sobre la clave, la vista se lee igual pero los
   nombres salen NULL. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    SELECT TOP (5) seleccion, dorsal, apellido, nombre
    FROM Reportes.vw_Plantillas
    ORDER BY id_seleccion, dorsal;

    IF EXISTS (SELECT 1 FROM Reportes.vw_Plantillas WHERE apellido IS NULL OR nombre IS NULL)
        PRINT N'ERROR  1. Lee Reportes.vw_Plantillas, pero los nombres salen NULL: no descifra.';
    ELSE
        PRINT N'OK     1. Puede leer Reportes.vw_Plantillas con los nombres descifrados.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  1. No pudo leer Reportes.vw_Plantillas: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 2: PUEDE ejecutar un SP de reportes. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    EXEC Reportes.usp_Goleadores;
    PRINT N'OK     2. Puede ejecutar Reportes.usp_Goleadores.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  2. No pudo ejecutar Reportes.usp_Goleadores: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 3: PUEDE consultar los países (DatosGenerales.usp_ConsultarPaises)
   para elegir el del árbitro, y registrar un árbitro; el SP cifra sus datos
   personales y lo muestra con el nombre descifrado. Se registra de verdad y
   el mismo usuario lo deshace al final. Nombre y apellido no admiten NULL:
   si el usuario no pudiera cifrar, el cifrado daría NULL y el alta
   fallaría. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT, @id_arbitro INT;
    DECLARE @paises TABLE (id_pais SMALLINT, nombre VARCHAR(60), codigo_fifa CHAR(3), huso_horario VARCHAR(50));

    INSERT INTO @paises EXEC DatosGenerales.usp_ConsultarPaises;
    SELECT TOP (1) @id_pais = id_pais FROM @paises ORDER BY nombre;

    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @id_pais, @nombre = N'Prueba', @apellido = N'Administrador',
                                        @categoria = 'FIFA', @idiomas = 'es', @fecha_nacimiento = '1985-01-01',
                                        @id_arbitro = @id_arbitro OUTPUT;
    PRINT CONCAT(N'OK     3. Puede consultar los países y registrar un árbitro con Arbitraje.usp_RegistrarArbitro, con sus datos cifrados (id ', @id_arbitro, N'; se deshace).');
END TRY
BEGIN CATCH
    PRINT N'ERROR  3. No pudo consultar los países o registrar el árbitro: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- deshace el árbitro de prueba
REVERT;
GO


/* Caso 4: PUEDE registrar una convocatoria. Para eso también necesita usar
   el tipo tabla Torneo.TT_CONVOCADO (declarar la variable). */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    DECLARE @jugadores Torneo.TT_CONVOCADO;
    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = NULL, @jugadores = @jugadores;
    PRINT N'OK     4. Puede ejecutar Torneo.usp_RegistrarConvocatoria.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000   -- lo rechazó la validación del SP: el permiso está
        PRINT N'OK     4. Puede usar TT_CONVOCADO y ejecutar Torneo.usp_RegistrarConvocatoria (con datos vacíos lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  4. No pudo ejecutar Torneo.usp_RegistrarConvocatoria: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 5: PUEDE registrar un gol (módulo DesarrolloPartido). */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = NULL, @id_jugador_autor = NULL,
                                            @id_tipo_gol = NULL, @periodo = NULL;
    PRINT N'OK     5. Puede ejecutar DesarrolloPartido.usp_RegistrarGol.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000
        PRINT N'OK     5. Puede ejecutar DesarrolloPartido.usp_RegistrarGol (con datos vacíos lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  5. No pudo ejecutar DesarrolloPartido.usp_RegistrarGol: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 6: PUEDE dar de alta un anunciante (módulo Publicidad). */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = NULL, @id_pais = NULL;
    PRINT N'OK     6. Puede ejecutar Publicidad.usp_ANUNCIANTE_Alta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000
        PRINT N'OK     6. Puede ejecutar Publicidad.usp_ANUNCIANTE_Alta (con datos vacíos lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  6. No pudo ejecutar Publicidad.usp_ANUNCIANTE_Alta: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


PRINT N'';
PRINT N'=== Lo que NO PUEDE hacer usr_administrador ===';
GO


/* Caso 7: NO PUEDE leer una tabla directamente. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    SELECT TOP (5) * FROM Torneo.JUGADOR;
    PRINT N'ERROR  7. Pudo leer la tabla Torneo.JUGADOR y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229   -- 229: permiso denegado
        PRINT N'OK     7. No puede leer Torneo.JUGADOR: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  7. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 8: NO PUEDE borrar en una tabla directamente. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    DELETE FROM DesarrolloPartido.GOL;
    PRINT N'ERROR  8. Pudo borrar en DesarrolloPartido.GOL y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     8. No puede borrar en DesarrolloPartido.GOL: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  8. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 9: NO PUEDE importar un archivo del servidor: las importaciones con
   BULK quedan para el DBA. Se pasa un archivo que no existe. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    EXEC Torneo.usp_ImportarJugadoresCSV @ruta_archivo = N'C:\no\existe.csv';
    PRINT N'ERROR  9. Pudo ejecutar Torneo.usp_ImportarJugadoresCSV y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     9. No puede ejecutar Torneo.usp_ImportarJugadoresCSV: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  9. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 10: NO PUEDE leer la vista descifrada de jugadores directamente: los
   datos personales los ve a través de los reportes y los SP. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    SELECT TOP (5) id_jugador, apellido, nombre, fecha_nacimiento FROM Seguridad.vw_Jugador;
    PRINT N'ERROR 10. Pudo leer Seguridad.vw_Jugador y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    10. No puede leer Seguridad.vw_Jugador: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 10. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 11: NO PUEDE usar la función de cifrado directamente: cifra solo a
   través de los SP de alta y modificación. */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    SELECT Seguridad.fn_CifrarTexto(N'Prueba') AS texto_cifrado;
    PRINT N'ERROR 11. Pudo ejecutar Seguridad.fn_CifrarTexto y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    11. No puede ejecutar Seguridad.fn_CifrarTexto: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 11. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 12: NO PUEDE abrir la clave de cifrado por su cuenta. */
EXECUTE AS USER = N'usr_administrador';
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


/* Casos 13 y 14: NO PUEDE modificar el certificado (por ejemplo, quitarle
   la clave privada) ni la clave de cifrado. No se intenta el ALTER: se
   pregunta si tiene el permiso. */
EXECUTE AS USER = N'usr_administrador';
IF HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'ALTER') = 0
    PRINT N'OK    13. No tiene permiso para modificar el certificado CertDatosPersonales.';
ELSE
    PRINT N'ERROR 13. Tiene permiso para modificar el certificado CertDatosPersonales y no debería.';

IF HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', N'SYMMETRIC KEY', N'ALTER') = 0
    PRINT N'OK    14. No tiene permiso para modificar la clave ClaveDatosPersonales.';
ELSE
    PRINT N'ERROR 14. Tiene permiso para modificar la clave ClaveDatosPersonales y no debería.';
REVERT;
GO


/* Caso 15: NO PUEDE leer la tabla de países directamente: los consulta con
   el SP (caso 3). */
EXECUTE AS USER = N'usr_administrador';
BEGIN TRY
    SELECT TOP (5) * FROM DatosGenerales.PAIS;
    PRINT N'ERROR 15. Pudo leer la tabla DatosGenerales.PAIS y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    15. No puede leer DatosGenerales.PAIS: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 15. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO
