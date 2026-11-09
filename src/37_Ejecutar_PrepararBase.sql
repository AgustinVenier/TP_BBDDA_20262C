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
 Archivo: 37_Ejecutar_PrepararBase.sql
 Objetivo: Dejar la base lista para importar en vivo: la recrea desde cero, crea
           todos los objetos y carga los datos iniciales, sin importar nada. Es
           el primer script que se ejecuta, aunque tenga este número: ejecuta 00
           a 25, 27, 28, 30 y 40 (roles); deja afuera 26, 29, 31, 32, 33, 36,
           el cifrado (38) y los tests 81 a 85.
================================================================================

 ATENCIÓN: ELIMINA LA BASE MundialFutbol, con todos sus datos (lo hace
 00_CrearBaseDeDatos.sql), y cierra las conexiones que tenga abiertas.

 Antes de ejecutar:
   - En SSMS, activar el modo SQLCMD: menú Query > SQLCMD Mode. Sin él, las
     líneas que empiezan con dos puntos dan error de sintaxis y no se ejecuta
     ninguno de los scripts.
   - CAMBIAR la ruta de :setvar src por la carpeta src\ del repositorio en tu
     máquina, terminada en \.
   Si un script falla, se detiene ahí (:on error exit).

 Después de este script, en este orden:
   1. 26_Ejecutar_ImportarIndicadores.sql   PBI per cápita (API)
   2. 29_Ejecutar_ImportarAPIs.sql          campañas, cotizaciones y feriados (APIs)
   3. El scraping, en una terminal, desde la carpeta del repositorio:
        python scraping/Scraping_Jugadores.py
        python scraping/Scraping_Arbitros.py
   4. 31_Ejecutar_ImportarMundial2026.sql   el torneo, con errores parciales
   5. 32_Ejecutar_DatosComplementarios.sql  lo que las fuentes no traen
   6. 33_Ejecutar_SedesAdicionales.sql      sedes propias del juego de datos
   7. 36_Ejecutar_ImportarImagenesSedes.sql la foto de cada sede (datos\fuentes\sedes)
   8. 53 a 80_Test_*.sql                    tests de las entregas 5 a 7, antes de cifrar
   9. 38_Ejecutar_Cifrado.sql               cifrado de los datos personales
  10. 81 a 85_Test_*.sql                    permisos por rol y cifrado
  11. 35_Ejecutar_Entrega9_ConsultasToBe.sql  lee las vistas descifradas que crea 38

 Los tests 53 a 80 van antes del cifrado: después, los que buscan personas por
 nombre en las tablas no las encuentran y su limpieza deja datos de prueba.
*/

-- CAMBIAR: ruta de la carpeta src\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
:setvar src "C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\src\"
:on error exit

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Base, esquemas, tablas, funciones y vistas.
:r $(src)00_CrearBaseDeDatos.sql
GO
:r $(src)01_CrearEsquemas.sql
GO
:r $(src)02_CrearTablas.sql
GO
:r $(src)03_CrearFuncionesYVistas.sql
GO

-- SP de ABM.
:r $(src)04_SP_ABM_DatosGenerales.sql
GO
:r $(src)05_SP_ABM_Torneo.sql
GO
:r $(src)06_SP_ABM_DesarrolloPartido.sql
GO
:r $(src)07_SP_ABM_Arbitraje.sql
GO
:r $(src)08_SP_ABM_Publicidad.sql
GO

-- SP de negocio y SP masivos de la importación.
:r $(src)10_SP_Negocio_SedesYPartidos.sql
GO
:r $(src)11_SP_Negocio_Convocatoria.sql
GO
:r $(src)12_SP_Negocio_FormacionesYCambios.sql
GO
:r $(src)13_SP_Negocio_GolesYTarjetas.sql
GO
:r $(src)14_SP_Negocio_Arbitraje.sql
GO
:r $(src)15_SP_Negocio_Publicidad.sql
GO
:r $(src)16_SP_Importacion.sql
GO
:r $(src)17_SP_Importar_ImagenesSedes.sql
GO
:r $(src)18_SP_Consultas.sql
GO

-- Datos iniciales (países, idiomas, parámetros del reglamento).
:r $(src)20_Ejecutar_DatosIniciales.sql
GO

-- SP que leen los archivos y consultan las APIs, y reportes.
:r $(src)21_SP_Importar_Publicidad.sql
GO
:r $(src)22_SP_ConsumirAPI.sql
GO
:r $(src)23_SP_Importar_Mundial2026.sql
GO
:r $(src)24_SP_Importar_Jugadores.sql
GO
:r $(src)25_SP_Importar_Indicadores.sql
GO
:r $(src)27_SP_Importar_Cotizaciones.sql
GO
:r $(src)28_SP_Importar_Feriados.sql
GO
:r $(src)30_SP_Reportes.sql
GO


-- Roles de aplicación.
:r $(src)40_Seguridad.sql
GO

-- Evidencia: los objetos creados, los datos iniciales y nada importado.
SET NOCOUNT ON;

SELECT N'Base lista para importar' AS estado,
       (SELECT COUNT(*) FROM sys.tables)                       AS tablas,
       (SELECT COUNT(*) FROM sys.procedures)                   AS procedimientos,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS)              AS paises,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION)       AS importaciones,
       (SELECT COUNT(*) FROM Torneo.SEDE)                      AS sedes,
       (SELECT COUNT(*) FROM Torneo.JUGADOR)                   AS jugadores,
       (SELECT COUNT(*) FROM Torneo.PARTIDO)                   AS partidos;
GO






