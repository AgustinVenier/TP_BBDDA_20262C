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
           Ejecuta, en orden, los scripts 01 a 28: estructura (01 a 04),
           objetos (05 a 27, el 27 crea los roles) y datos iniciales (28).
           Las importaciones y cargas (30 a 35), los reportes (36), el cifrado
           (40 a 47), las consultas de la Entrega 9 (48) y los tests (54 a 97)
           se ejecutan aparte.
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
   30_Importar_Indicadores.sql          PBI per cápita (API)
   31_Importar_APIs.sql                 campañas, cotizaciones y feriados (APIs)
   el scraping, en una terminal, desde la carpeta del repositorio:
        python scraping/Scraping_Jugadores.py
        python scraping/Scraping_Arbitros.py
   32_Importar_Mundial2026.sql          el torneo, con errores parciales
   33_Cargar_DatosComplementarios.sql   lo que las fuentes no traen
   34_Cargar_SedesAdicionales.sql       sedes propias del juego de datos
   35_Importar_ImagenesSedes.sql        la foto de cada sede (datos\fuentes\sedes)
   36_Mostrar_Reportes.sql              los reportes de la Entrega 7
   40_Ejecutar_Cifrado.sql              cifrado de los datos personales (ejecuta 41 a 47)
   48_Mostrar_ConsultasToBe.sql         lee las vistas descifradas que crea 40

 Los tests no siguen ese orden. Cada uno lleva el número de su script más 50
 (el de roles, 27, tiene uno por usuario: 77 a 80). Los 54 a 76 van antes del
 cifrado (40), porque después los que buscan personas por nombre en las
 tablas no las encuentran y su limpieza deja datos de prueba; los 77 a 80
 (permisos por rol) y 91 a 97 (cifrado), después.
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

-- SP de negocio y de carga masiva.
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
:r $(src)16_SP_CargaMasiva.sql
GO

-- SP que leen los archivos y consultan las APIs.
:r $(src)17_SP_Utilidades_Importacion.sql
GO
:r $(src)18_SP_Importar_Mundial2026.sql
GO
:r $(src)19_SP_Importar_Jugadores.sql
GO
:r $(src)20_SP_Importar_Publicidad.sql
GO
:r $(src)21_SP_Importar_Indicadores.sql
GO
:r $(src)22_SP_Importar_Cotizaciones.sql
GO
:r $(src)23_SP_Importar_Feriados.sql
GO
:r $(src)24_SP_Importar_ImagenesSedes.sql
GO

-- SP de consulta (aplicación ABM), reportes y roles de aplicación.
:r $(src)25_SP_Consultas.sql
GO
:r $(src)26_SP_Reportes.sql
GO
:r $(src)27_SP_Roles.sql
GO

-- Datos iniciales (países, idiomas, parámetros del reglamento).
:r $(src)28_Cargar_DatosIniciales.sql
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






