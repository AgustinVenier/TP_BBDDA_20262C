/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - COMPLETAR
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier
   
 Archivo: 01_CrearEsquemas.sql
 Objetivo: Crear los esquemas lógicos en los que se agrupan las tablas.
================================================================================
*/

USE MundialFutbol;
GO

/*
    Esquemas lógicos del sistema (no se usa dbo para objetos propios):
      DatosGenerales    Países, idiomas, indicadores económicos y parámetros del reglamento.
      Torneo            Sedes, selecciones, listas de convocados, jugadores, cuerpo técnico y partidos.
      DesarrolloPartido Formaciones, alineaciones, cambios, goles y amonestaciones.
      Arbitraje         Árbitros, idiomas que hablan y designaciones por partido.
      Publicidad        Anunciantes, campañas, piezas, espacios publicitarios y exhibiciones.

    CREATE SCHEMA debe ser la única sentencia de su lote, por lo que no puede
    ir dentro de un IF. Para validar la existencia sin recurrir a SQL dinámico
    se usa SET NOEXEC: si el esquema ya existe, el lote siguiente se compila
    pero no se ejecuta, y luego se restablece la ejecución normal.
*/

IF SCHEMA_ID(N'DatosGenerales') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA DatosGenerales AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'Torneo') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA Torneo AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'DesarrolloPartido') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA DesarrolloPartido AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'Arbitraje') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA Arbitraje AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'Publicidad') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA Publicidad AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

-- Evidencia: esquemas creados.
SELECT name AS Esquema
FROM sys.schemas
WHERE name IN (N'DatosGenerales', N'Torneo', N'DesarrolloPartido', N'Arbitraje', N'Publicidad')
ORDER BY name;
GO
