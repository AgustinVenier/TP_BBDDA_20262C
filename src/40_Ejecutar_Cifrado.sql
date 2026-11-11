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
 Archivo: 40_Ejecutar_Cifrado.sql
 Objetivo: Entrega 8. Aplicar el cifrado de los datos personales sobre la base
           ya cargada: crea los objetos de cifrado y las claves, cifra las
           columnas de jugadores, cuerpos técnicos y árbitros con los datos que
           tienen, y modifica los SP, funciones y vistas que las usan.
================================================================================

 Orden: después de 00_Ejecutar_PrepararBase.sql y de las importaciones (30 a
 35). Ejecuta 41 a 47. Después van los tests 77 a 80 y 91 a 97, y 48. Se puede
 ejecutar más de una vez: lo que ya está cifrado no se vuelve a cifrar.

 Los tests de las entregas anteriores (54 a 76) se ejecutan ANTES que este
 script: después del cifrado, los que buscan personas por nombre en las
 tablas no las encuentran y su limpieza deja datos de prueba.

 Antes de ejecutar:
   - En SSMS, activar el modo SQLCMD: menú Query > SQLCMD Mode.
   - CAMBIAR la ruta de :setvar src por la carpeta src\ del repositorio en tu
     máquina, terminada en \.
   - CAMBIAR la contraseña de :setvar ClaveMaestra por una propia y guardarla
     fuera del repositorio. Protege a la clave maestra de la base; solo se usa
     la primera vez (si la clave maestra ya existe, no se pide).
   - Después de la primera ejecución, respaldar el certificado
     CertDatosPersonales con su clave privada (ver 41_SP_Cifrado.sql): sin él,
     los datos cifrados no se pueden recuperar.
   Si un script falla, se detiene ahí (:on error exit).
*/

-- CAMBIAR: ruta de la carpeta src\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
:setvar src "C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\src\"
-- CAMBIAR: contraseña de la clave maestra de la base (ver "Antes de ejecutar").
:setvar ClaveMaestra "CAMBIAR_por_una_contraseña_robusta"
:on error exit

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_ID(N'MundialFutbol') IS NULL
    THROW 50001, N'40_Ejecutar_Cifrado.sql: no existe la base MundialFutbol. Ejecutá primero 00_Ejecutar_PrepararBase.sql.', 1;
GO
USE MundialFutbol;
GO
IF SCHEMA_ID(N'Seguridad') IS NULL
    THROW 50001, N'40_Ejecutar_Cifrado.sql: falta el esquema Seguridad. Ejecutá primero 00_Ejecutar_PrepararBase.sql.', 1;
GO

-- Objetos de cifrado y claves.
:r $(src)41_SP_Cifrado.sql
GO
USE MundialFutbol;
EXEC Seguridad.usp_ConfigurarCifrado @contrasenia_clave_maestra = N'$(ClaveMaestra)';
GO

-- Permisos de los roles sobre la clave recién creada (Seguridad.usp_ConfigurarRoles, de 27).
EXEC Seguridad.usp_ConfigurarRoles;
GO

-- Tablas: columnas cifradas, datos existentes y vista descifrada de cada una.
:r $(src)42_Cifrado_Tabla_Jugador.sql
GO
:r $(src)43_Cifrado_Tabla_PersonaCuerpoTecnico.sql
GO
:r $(src)44_Cifrado_Tabla_Arbitro.sql
GO

-- SP, funciones y vistas que usan las columnas cifradas.
:r $(src)45_Cifrado_Torneo.sql
GO
:r $(src)46_Cifrado_DesarrolloYArbitraje.sql
GO
:r $(src)47_Cifrado_Reportes.sql
GO

-- Evidencia: los datos guardados están cifrados y las vistas los muestran descifrados.
USE MundialFutbol;
SET NOCOUNT ON;

SELECT N'Cifrado aplicado' AS estado,
       (SELECT COUNT(*) FROM Torneo.JUGADOR)                       AS jugadores,
       (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO)        AS cuerpo_tecnico,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO)                    AS arbitros;

SELECT TOP (3) j.id_jugador, j.apellido AS apellido_guardado, p.apellido AS apellido_en_vw_Plantillas
FROM Torneo.JUGADOR AS j
INNER JOIN Reportes.vw_Plantillas AS p ON p.id_jugador = j.id_jugador
ORDER BY j.id_jugador;
GO
