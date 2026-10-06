/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: COMPLETAR    Grupo: COMPLETAR
 Integrantes:
   COMPLETAR Apellido, Nombre - usuario GitHub COMPLETAR
   COMPLETAR Apellido, Nombre - usuario GitHub COMPLETAR
 Fecha: 06/10/2026
 Archivo: 01_CrearEsquemas.sql
================================================================================
*/

USE MundialFutbol;
GO

/*
    Esquemas lógicos del sistema (no se usa dbo para objetos propios):
      config       Parámetros del reglamento (cupos, cambios, suspensiones).
      torneo       Países, indicadores económicos, sedes, fases, selecciones y partidos.
      plantel      Jugadores, cuerpo técnico y convocatorias.
      partido      Formaciones, alineaciones, cambios, goles, tarjetas y suspensiones.
      arbitraje    Árbitros, idiomas, designaciones e informes post-partido.
      publicidad   Anunciantes, campañas, piezas, espacios físicos y exhibiciones.
      importacion  Lotes de importación, errores y lógica de upsert.

    CREATE SCHEMA debe ser la única sentencia de su lote, por lo que no puede
    ir dentro de un IF. Para validar la existencia sin recurrir a SQL dinámico
    se usa SET NOEXEC: si el esquema ya existe, el lote siguiente se compila
    pero no se ejecuta, y luego se restablece la ejecución normal.
*/

IF SCHEMA_ID(N'config') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA config AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'torneo') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA torneo AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'plantel') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA plantel AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'partido') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA partido AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'arbitraje') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA arbitraje AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'importacion') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA importacion AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

IF SCHEMA_ID(N'publicidad') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA publicidad AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO

-- Evidencia: esquemas creados.
SELECT name AS Esquema
FROM sys.schemas
WHERE name IN (N'config', N'torneo', N'plantel', N'partido', N'arbitraje', N'importacion', N'publicidad')
ORDER BY name;
GO
