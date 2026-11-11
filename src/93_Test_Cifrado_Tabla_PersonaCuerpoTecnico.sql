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
 Archivo: 93_Test_Cifrado_Tabla_PersonaCuerpoTecnico.sql
 Objetivo: Probar 43_Cifrado_Tabla_PersonaCuerpoTecnico.sql: que Torneo.PERSONA_CUERPO_TECNICO
           guarde cifrados el nombre, el apellido y la fecha de nacimiento, que
           la vista Seguridad.vw_PersonaCuerpoTecnico los devuelva descifrados, que no se
           pueda guardar un apellido sin abrir la clave y que
           Seguridad.usp_CifrarPersonaCuerpoTecnico no vuelva a cifrar lo que ya está cifrado.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql. Ejecutar como dueño de la
 base (dbo). No queda nada modificado.

 Cada caso es independiente y se puede ejecutar solo. Muestra lo que probó en
 la grilla e imprime una línea en la pestaña Mensajes:
   OK     dio lo esperado.
   ERROR  dio otra cosa.
 El test está bien si ninguna línea empieza con ERROR.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
GO


/* Caso 1: las columnas nombre, apellido y fecha_nacimiento son VARBINARY. */
SELECT name AS columna, TYPE_NAME(system_type_id) AS tipo
FROM sys.columns
WHERE object_id = OBJECT_ID(N'Torneo.PERSONA_CUERPO_TECNICO')
  AND name IN (N'nombre', N'apellido', N'fecha_nacimiento');

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID(N'Torneo.PERSONA_CUERPO_TECNICO')
             AND name IN (N'nombre', N'apellido', N'fecha_nacimiento')
             AND TYPE_NAME(system_type_id) <> N'varbinary')
    PRINT N'ERROR  1. Alguna columna de datos personales de Torneo.PERSONA_CUERPO_TECNICO no es VARBINARY.';
ELSE
    PRINT N'OK     1. Las columnas de datos personales de Torneo.PERSONA_CUERPO_TECNICO son VARBINARY.';
GO


/* Caso 2: la tabla guarda bytes y la vista devuelve el nombre y el apellido
   descifrados. Si alguno no se pudiera descifrar, saldría NULL. */
SELECT TOP (5) t.id_persona_ct, t.apellido AS apellido_guardado, v.apellido AS apellido_descifrado, v.nombre AS nombre_descifrado
FROM Torneo.PERSONA_CUERPO_TECNICO AS t
INNER JOIN Seguridad.vw_PersonaCuerpoTecnico AS v ON v.id_persona_ct = t.id_persona_ct
ORDER BY t.id_persona_ct;

IF EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico WHERE nombre IS NULL OR apellido IS NULL)
    PRINT N'ERROR  2. Seguridad.vw_PersonaCuerpoTecnico tiene filas con el nombre o el apellido en NULL: no los descifra.';
ELSE
    PRINT N'OK     2. Seguridad.vw_PersonaCuerpoTecnico devuelve el nombre y el apellido descifrados en todas las filas.';
GO


/* Caso 3: la fecha de nacimiento es opcional. La vista tiene que descifrar
   tantas fechas como las que hay guardadas en la tabla. */
DECLARE @guardadas INT, @descifradas INT;

SELECT @guardadas = COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO WHERE fecha_nacimiento IS NOT NULL;
SELECT @descifradas = COUNT(*) FROM Seguridad.vw_PersonaCuerpoTecnico WHERE fecha_nacimiento IS NOT NULL;

SELECT @guardadas AS fechas_guardadas, @descifradas AS fechas_descifradas;

IF @guardadas = @descifradas
    PRINT N'OK     3. Seguridad.vw_PersonaCuerpoTecnico descifra todas las fechas de nacimiento guardadas.';
ELSE
    PRINT N'ERROR  3. Seguridad.vw_PersonaCuerpoTecnico no descifra todas las fechas de nacimiento guardadas.';
GO


/* Caso 4: sin abrir la clave no se puede guardar un apellido. Con la clave
   cerrada, fn_CifrarTexto da NULL y la columna no admite NULL (error 515). */
BEGIN TRANSACTION;
BEGIN TRY
    UPDATE TOP (1) Torneo.PERSONA_CUERPO_TECNICO SET apellido = Seguridad.fn_CifrarTexto(N'Sin clave');
    PRINT N'ERROR  4. Se guardó un apellido sin abrir la clave.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 515
        PRINT N'OK     4. No se puede guardar un apellido sin abrir la clave: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  4. Falló por otro motivo: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 5: usp_CifrarPersonaCuerpoTecnico se puede ejecutar otra vez. Como la tabla ya está
   cifrada no hace nada (estado YA ESTABA CIFRADA) y los datos se siguen
   descifrando. */
EXEC Seguridad.usp_CifrarPersonaCuerpoTecnico;

IF EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico WHERE nombre IS NULL OR apellido IS NULL)
    PRINT N'ERROR  5. Después de ejecutar otra vez usp_CifrarPersonaCuerpoTecnico, hay filas que no se descifran.';
ELSE
    PRINT N'OK     5. usp_CifrarPersonaCuerpoTecnico se ejecutó otra vez y los datos se siguen descifrando.';
GO
