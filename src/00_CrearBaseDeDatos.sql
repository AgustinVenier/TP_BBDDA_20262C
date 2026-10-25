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

 Fecha: 25/10/2026
 Archivo: 00_CrearBaseDeDatos.sql
 Objetivo: Crear la base de datos MundialFutbol desde cero. Si ya existe, se
           elimina y se vuelve a crear con modelo de recuperación FULL.
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
    de la instancia.
*/
CREATE DATABASE MundialFutbol;
GO

/*
    Modelo de recuperación FULL: permite respaldos de log y restauración a un
    punto en el tiempo.
*/
ALTER DATABASE MundialFutbol SET RECOVERY FULL;
GO
