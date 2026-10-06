/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: COMPLETAR    Grupo: COMPLETAR
 Integrantes:
   COMPLETAR Apellido, Nombre - usuario GitHub COMPLETAR
   COMPLETAR Apellido, Nombre - usuario GitHub COMPLETAR
 Fecha: 04/10/2026
 Archivo: 00_CrearBaseDeDatos.sql
================================================================================
*/

USE master;
GO

/*
    Si la base ya existe se la elimina para poder recrearla completa desde cero
    (requisito del coloquio). SINGLE_USER WITH ROLLBACK IMMEDIATE cierra las
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
    de la instancia, definidos en la Entrega 4 (Instalación y Configuración).
*/
CREATE DATABASE MundialFutbol;
GO

/*
    Modelo de recuperación FULL: permite respaldos de log y restauración a un
    punto en el tiempo, base de la política de respaldo de la Entrega 8.
*/
ALTER DATABASE MundialFutbol SET RECOVERY FULL;
GO
