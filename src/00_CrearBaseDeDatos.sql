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

 Fecha: 25/10/2026
 Archivo: 00_CrearBaseDeDatos.sql
 Objetivo: Crear la base de datos MundialFutbol desde cero. Si ya existe, se
           elimina y se vuelve a crear con intercalación
           Modern_Spanish_100_CI_AS_SC y modelo de recuperación FULL.
================================================================================
*/

USE master;
GO

/*
    Si la base ya existe se la elimina para poder recrearla completa desde cero
    SINGLE_USER WITH ROLLBACK IMMEDIATE cierra las
    conexiones abiertas que impedirían el borrado.
*/
IF DB_ID(N'MundialFutbol') IS NOT NULL
BEGIN
    ALTER DATABASE MundialFutbol SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MundialFutbol;
END;
GO

/*
    Se crea la base con la ubicación de archivos y el tamaño inicial por defecto
    de la instancia. La intercalación se fija explícitamente para no depender
    de la del servidor donde se ejecute: Modern_Spanish_100_CI_AS_SC, la misma
    que se definió para la instancia. Sus VARCHAR usan la página de códigos
    1252, que cubre el español completo, y sus NVARCHAR admiten caracteres
    suplementarios.
*/
CREATE DATABASE MundialFutbol
    COLLATE Modern_Spanish_100_CI_AS_SC;
GO

/*
    Modelo de recuperación FULL: permite respaldos de log y restauración a un
    punto en el tiempo.
*/
ALTER DATABASE MundialFutbol SET RECOVERY FULL;
GO

-- Evidencia: base creada, intercalación, modelo de recuperación y archivos.
SELECT d.name                AS base,
       d.collation_name      AS intercalacion,
       d.recovery_model_desc AS modelo_recuperacion,
       d.create_date         AS fecha_creacion,
       mf.type_desc          AS tipo_archivo,
       mf.physical_name      AS archivo
FROM sys.databases AS d
INNER JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.name = N'MundialFutbol';
GO
