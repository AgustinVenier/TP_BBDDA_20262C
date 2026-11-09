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

 Fecha: 09/11/2026
 Archivo: 92_Test_Cifrado_Tablas.sql
 Objetivo: Probar 42_Cifrado_Tablas.sql: que Torneo.JUGADOR,
           Torneo.PERSONA_CUERPO_TECNICO y Arbitraje.ARBITRO guarden cifrados
           el nombre, el apellido y la fecha de nacimiento, que todas las filas
           se descifren en las vistas Seguridad.vw_Jugador,
           vw_PersonaCuerpoTecnico y vw_Arbitro, que esas vistas tengan las
           columnas de su tabla, que no se pueda guardar una persona sin abrir
           la clave y que Seguridad.usp_CifrarDatosPersonales no vuelva a
           cifrar lo que ya está cifrado.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql. Ejecutar como dueño de la
 base (dbo). El alta de prueba se hace dentro de una transacción que se
 deshace, así no queda nada. Si algún control no da lo esperado, el script
 termina con error.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los índices filtrados y los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
GO

-- Por si una corrida anterior quedó a medias con la clave abierta.
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales')
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
GO

DECLARE @controles TABLE (n INT IDENTITY, control NVARCHAR(200), esperado NVARCHAR(200), obtenido NVARCHAR(400));
DECLARE @reproceso TABLE (tabla NVARCHAR(300), estado NVARCHAR(30), filas_cifradas INT);

/* 1. Columnas: las 9 son VARBINARY; nombre y apellido no admiten NULL. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Columna ' + OBJECT_SCHEMA_NAME(c.object_id) + N'.' + OBJECT_NAME(c.object_id) + N'.' + c.name,
       IIF(c.name = N'fecha_nacimiento', N'varbinary NULL', N'varbinary NOT NULL'),
       TYPE_NAME(c.system_type_id) + IIF(c.is_nullable = 1, N' NULL', N' NOT NULL')
FROM sys.columns AS c
WHERE c.object_id IN (OBJECT_ID(N'Torneo.JUGADOR'), OBJECT_ID(N'Torneo.PERSONA_CUERPO_TECNICO'), OBJECT_ID(N'Arbitraje.ARBITRO'))
  AND c.name IN (N'nombre', N'apellido', N'fecha_nacimiento');

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Columnas cifradas encontradas', N'9', CAST(COUNT(*) AS NVARCHAR(10))
FROM sys.columns AS c
WHERE c.object_id IN (OBJECT_ID(N'Torneo.JUGADOR'), OBJECT_ID(N'Torneo.PERSONA_CUERPO_TECNICO'), OBJECT_ID(N'Arbitraje.ARBITRO'))
  AND c.name IN (N'nombre', N'apellido', N'fecha_nacimiento')
  AND TYPE_NAME(c.system_type_id) = N'varbinary';

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Restricciones de unicidad sobre nombre y apellido', N'ninguna',
       ISNULL((SELECT STRING_AGG(name, N', ') FROM sys.objects
               WHERE name IN (N'UQ_JUGADOR_lista_apellido_nombre', N'UQ_ARBITRO_pais_apellido_nombre')), N'ninguna');

/* 2. Vistas descifradas: las mismas columnas que su tabla, con el tipo
      original en los datos personales, y una fila por fila de la tabla. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Columnas de ' + t.tabla + N' que faltan en ' + t.vista, N'ninguna',
       ISNULL((SELECT STRING_AGG(ct.name, N', ') FROM sys.columns AS ct
               WHERE ct.object_id = OBJECT_ID(t.tabla)
                 AND NOT EXISTS (SELECT 1 FROM sys.columns AS cv
                                 WHERE cv.object_id = OBJECT_ID(t.vista) AND cv.name = ct.name)), N'ninguna')
FROM (VALUES (N'Torneo.JUGADOR', N'Seguridad.vw_Jugador'),
             (N'Torneo.PERSONA_CUERPO_TECNICO', N'Seguridad.vw_PersonaCuerpoTecnico'),
             (N'Arbitraje.ARBITRO', N'Seguridad.vw_Arbitro')) AS t (tabla, vista);

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Tipo de ' + OBJECT_SCHEMA_NAME(c.object_id) + N'.' + OBJECT_NAME(c.object_id) + N'.' + c.name,
       IIF(c.name = N'fecha_nacimiento', N'date', N'nvarchar(60)'),
       TYPE_NAME(c.system_type_id) + IIF(TYPE_NAME(c.system_type_id) = N'nvarchar', CONCAT(N'(', c.max_length / 2, N')'), N'')
FROM sys.columns AS c
WHERE c.object_id IN (OBJECT_ID(N'Seguridad.vw_Jugador'), OBJECT_ID(N'Seguridad.vw_PersonaCuerpoTecnico'),
                      OBJECT_ID(N'Seguridad.vw_Arbitro'))
  AND c.name IN (N'nombre', N'apellido', N'fecha_nacimiento');

INSERT INTO @controles (control, esperado, obtenido)
VALUES (N'Filas de Seguridad.vw_Jugador = filas de Torneo.JUGADOR', N'iguales',
        IIF((SELECT COUNT(*) FROM Seguridad.vw_Jugador) = (SELECT COUNT(*) FROM Torneo.JUGADOR), N'iguales', N'distintas')),
       (N'Filas de Seguridad.vw_PersonaCuerpoTecnico = filas de Torneo.PERSONA_CUERPO_TECNICO', N'iguales',
        IIF((SELECT COUNT(*) FROM Seguridad.vw_PersonaCuerpoTecnico) = (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO),
            N'iguales', N'distintas')),
       (N'Filas de Seguridad.vw_Arbitro = filas de Arbitraje.ARBITRO', N'iguales',
        IIF((SELECT COUNT(*) FROM Seguridad.vw_Arbitro) = (SELECT COUNT(*) FROM Arbitraje.ARBITRO), N'iguales', N'distintas'));

/* 3. Datos: ninguna fila queda sin descifrar, y el dato guardado no es el texto. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Personas con nombre o apellido que no se descifra', N'0',
       CAST((SELECT COUNT(*) FROM Seguridad.vw_Jugador WHERE nombre IS NULL OR apellido IS NULL)
          + (SELECT COUNT(*) FROM Seguridad.vw_PersonaCuerpoTecnico WHERE nombre IS NULL OR apellido IS NULL)
          + (SELECT COUNT(*) FROM Seguridad.vw_Arbitro WHERE nombre IS NULL OR apellido IS NULL) AS NVARCHAR(10));
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Fechas de nacimiento guardadas que no se descifran', N'0',
       CAST((SELECT COUNT(*) FROM Torneo.JUGADOR AS j INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = j.id_jugador
             WHERE j.fecha_nacimiento IS NOT NULL AND v.fecha_nacimiento IS NULL)
          + (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
             INNER JOIN Seguridad.vw_PersonaCuerpoTecnico AS v ON v.id_persona_ct = ct.id_persona_ct
             WHERE ct.fecha_nacimiento IS NOT NULL AND v.fecha_nacimiento IS NULL)
          + (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN Seguridad.vw_Arbitro AS v ON v.id_arbitro = a.id_arbitro
             WHERE a.fecha_nacimiento IS NOT NULL AND v.fecha_nacimiento IS NULL) AS NVARCHAR(10));
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Personas cuyo dato guardado, leído como texto, es su apellido', N'0',
       CAST((SELECT COUNT(*) FROM Torneo.JUGADOR AS j INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = j.id_jugador
             WHERE CONVERT(NVARCHAR(60), j.apellido) = v.apellido)
          + (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
             INNER JOIN Seguridad.vw_PersonaCuerpoTecnico AS v ON v.id_persona_ct = ct.id_persona_ct
             WHERE CONVERT(NVARCHAR(60), ct.apellido) = v.apellido)
          + (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN Seguridad.vw_Arbitro AS v ON v.id_arbitro = a.id_arbitro
             WHERE CONVERT(NVARCHAR(60), a.apellido) = v.apellido) AS NVARCHAR(10));

/* 4. Sin abrir la clave, cifrar da NULL y el NOT NULL de nombre y apellido
      impide guardar la persona. */
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria)
    SELECT TOP (1) id_pais, Seguridad.fn_CifrarTexto(N'Sin'), Seguridad.fn_CifrarTexto(N'Clave'), 'FIFA' FROM DatosGenerales.PAIS;
    INSERT INTO @controles (control, esperado, obtenido) VALUES (N'Guardar un árbitro sin abrir la clave', N'error 515', N'se guardó');
END TRY
BEGIN CATCH
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'Guardar un árbitro sin abrir la clave', N'error 515', CONCAT(N'error ', ERROR_NUMBER()));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* 5. usp_CifrarDatosPersonales se puede ejecutar otra vez: las tres tablas ya
      están cifradas y no se cifra nada de nuevo. */
INSERT INTO @reproceso (tabla, estado, filas_cifradas)
EXEC Seguridad.usp_CifrarDatosPersonales;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Segunda ejecución de usp_CifrarDatosPersonales: ' + tabla, N'YA ESTABA CIFRADA', estado
FROM @reproceso;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Segunda ejecución de usp_CifrarDatosPersonales: tablas informadas', N'3', CAST(COUNT(*) AS NVARCHAR(10))
FROM @reproceso;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Personas que no se descifran después de la segunda ejecución', N'0',
       CAST((SELECT COUNT(*) FROM Seguridad.vw_Jugador WHERE nombre IS NULL OR apellido IS NULL)
          + (SELECT COUNT(*) FROM Seguridad.vw_PersonaCuerpoTecnico WHERE nombre IS NULL OR apellido IS NULL)
          + (SELECT COUNT(*) FROM Seguridad.vw_Arbitro WHERE nombre IS NULL OR apellido IS NULL) AS NVARCHAR(10));

/* 6. Al terminar, ninguna clave queda abierta en la sesión. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Claves abiertas en la sesión', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;

SELECT n, control, esperado, obtenido, IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado
FROM @controles
ORDER BY n;

/* Cómo se ve una persona guardada y cómo la devuelve la vista. */
SELECT TOP (3) j.id_jugador, j.apellido AS apellido_guardado, v.apellido AS apellido_descifrado
FROM Torneo.JUGADOR AS j
INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = j.id_jugador
ORDER BY j.id_jugador;

IF EXISTS (SELECT 1 FROM @controles WHERE esperado <> obtenido)
    THROW 51014, N'Las tablas cifradas (42) no dan lo esperado.', 1;
GO
