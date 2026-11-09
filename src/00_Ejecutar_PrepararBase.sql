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
 Archivo: 00_Ejecutar_PrepararBase.sql
 Objetivo: Dejar la base lista para importar en vivo: la recrea desde cero, crea
           todos los objetos y carga los datos iniciales, sin importar nada.
           Ejecuta, en orden, los scripts 01 a 29 (el 29 crea los roles). Las
           importaciones (30 a 35), los reportes (36), el cifrado (40 a 45),
           las consultas de la Entrega 9 (46) y los tests (53 a 95) se
           ejecutan aparte.
================================================================================

 ATENCIÓN: ELIMINA LA BASE MundialFutbol, con todos sus datos (lo hace
 01_CrearBaseDeDatos.sql), y cierra las conexiones que tenga abiertas.

 Antes de ejecutar:
   - En SSMS, activar el modo SQLCMD: menú Query > SQLCMD Mode. Sin él, las
     líneas que empiezan con dos puntos dan error de sintaxis y no se ejecuta
     ninguno de los scripts.
   - CAMBIAR la ruta de :setvar src por la carpeta src\ del repositorio en tu
     máquina, terminada en \.
   Si un script falla, se detiene ahí (:on error exit).

 Después de este script, en el orden de su número:
   30_Ejecutar_ImportarIndicadores.sql     PBI per cápita (API)
   31_Ejecutar_ImportarAPIs.sql            campañas, cotizaciones y feriados (APIs)
   el scraping, en una terminal, desde la carpeta del repositorio:
        python scraping/Scraping_Jugadores.py
        python scraping/Scraping_Arbitros.py
   32_Ejecutar_ImportarMundial2026.sql     el torneo, con errores parciales
   33_Ejecutar_DatosComplementarios.sql    lo que las fuentes no traen
   34_Ejecutar_SedesAdicionales.sql        sedes propias del juego de datos
   35_Ejecutar_ImportarImagenesSedes.sql   la foto de cada sede (datos\fuentes\sedes)
   36_Ejecutar_Entrega7_Reportes.sql       los reportes de la Entrega 7
   40_Ejecutar_Cifrado.sql                 cifrado de los datos personales (ejecuta 41 a 45)
   46_Ejecutar_Entrega9_ConsultasToBe.sql  lee las vistas descifradas que crea 40

 Los tests no siguen ese orden: los 53 a 80 van antes del cifrado (40), porque
 después los que buscan personas por nombre en las tablas no las encuentran y
 su limpieza deja datos de prueba; los 81 a 84 (permisos por rol) y 91 a 95
 (cifrado), después.
*/

-- CAMBIAR: ruta de la carpeta src\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
:setvar src "C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\src\"
:on error exit

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Base, esquemas, tablas, funciones y vistas.
:r $(src)01_CrearBaseDeDatos.sql
GO
:r $(src)02_CrearEsquemas.sql
GO
:r $(src)03_CrearTablas.sql
GO
:r $(src)04_CrearFuncionesYVistas.sql
GO

-- SP de ABM.
:r $(src)05_SP_ABM_DatosGenerales.sql
GO
:r $(src)06_SP_ABM_Torneo.sql
GO
:r $(src)07_SP_ABM_DesarrolloPartido.sql
GO
:r $(src)08_SP_ABM_Arbitraje.sql
GO
:r $(src)09_SP_ABM_Publicidad.sql
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
:r $(src)26_SP_Importar_Cotizaciones.sql
GO
:r $(src)27_SP_Importar_Feriados.sql
GO
:r $(src)28_SP_Reportes.sql
GO


-- Roles de aplicación.
:r $(src)29_Seguridad.sql
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






