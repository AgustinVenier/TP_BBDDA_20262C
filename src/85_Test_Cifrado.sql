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
 Archivo: 85_Test_Cifrado.sql
 Objetivo: Comprobar el cifrado de los datos personales (nombre, apellido y
           fecha de nacimiento de jugadores, cuerpos técnicos y árbitros): las
           claves, las columnas cifradas, que los datos se descifran bien y
           que los SP cifran lo que guardan y controlan los duplicados.
================================================================================

 Requiere haber ejecutado 38_Ejecutar_Cifrado.sql. Ejecutar como dueño de la
 base (dbo). Las altas de prueba se hacen dentro de una transacción que se
 deshace, así no queda nada. Si algún control no da lo esperado, el script
 termina con error.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 38_Ejecutar_Cifrado.sql.', 1;
GO

DECLARE @controles TABLE (n INT IDENTITY, control NVARCHAR(200), esperado NVARCHAR(200), obtenido NVARCHAR(400));

/* 1. Claves: clave maestra de la base, certificado y clave simétrica AES_256 protegida por el certificado. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Clave maestra de la base', N'existe',
       IIF(EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##'), N'existe', N'no existe');
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Certificado CertDatosPersonales con clave privada', N'ENCRYPTED_BY_MASTER_KEY',
       ISNULL((SELECT pvt_key_encryption_type_desc FROM sys.certificates WHERE name = N'CertDatosPersonales'), N'no existe');
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Clave ClaveDatosPersonales: algoritmo y protección', N'AES_256 por CertDatosPersonales',
       ISNULL((SELECT k.algorithm_desc + N' por ' + c.name
               FROM sys.symmetric_keys AS k
               INNER JOIN sys.key_encryptions AS ke ON ke.key_id = k.symmetric_key_id
               INNER JOIN sys.certificates AS c ON c.thumbprint = ke.thumbprint
               WHERE k.name = N'ClaveDatosPersonales'), N'no existe');

/* 2. Columnas: las 9 son VARBINARY; nombre y apellido no admiten NULL. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Columnas ' + OBJECT_SCHEMA_NAME(c.object_id) + N'.' + OBJECT_NAME(c.object_id) + N'.' + c.name,
       IIF(c.name = N'fecha_nacimiento', N'varbinary NULL', N'varbinary NOT NULL'),
       TYPE_NAME(c.system_type_id) + IIF(c.is_nullable = 1, N' NULL', N' NOT NULL')
FROM sys.columns AS c
WHERE c.object_id IN (OBJECT_ID(N'Torneo.JUGADOR'), OBJECT_ID(N'Torneo.PERSONA_CUERPO_TECNICO'), OBJECT_ID(N'Arbitraje.ARBITRO'))
  AND c.name IN (N'nombre', N'apellido', N'fecha_nacimiento');

INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Restricciones de unicidad sobre nombre y apellido', N'ninguna',
       ISNULL((SELECT STRING_AGG(name, N', ') FROM sys.objects
               WHERE name IN (N'UQ_JUGADOR_lista_apellido_nombre', N'UQ_ARBITRO_pais_apellido_nombre')), N'ninguna');

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
          + (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN Seguridad.vw_Arbitro AS v ON v.id_arbitro = a.id_arbitro
             WHERE a.fecha_nacimiento IS NOT NULL AND v.fecha_nacimiento IS NULL) AS NVARCHAR(10));
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Jugadores cuyo dato guardado, leído como texto, es su apellido', N'0',
       CAST(COUNT(*) AS NVARCHAR(10))
FROM Torneo.JUGADOR AS j INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = j.id_jugador
WHERE CONVERT(NVARCHAR(60), j.apellido) = v.apellido;

/* 4. El mismo texto cifrado dos veces da bytes distintos (por eso no sirve una restricción UNIQUE). */
DECLARE @abierta_aca BIT, @a VARBINARY(256), @b VARBINARY(256);
EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;
SELECT @a = Seguridad.fn_CifrarTexto(N'Messi'), @b = Seguridad.fn_CifrarTexto(N'Messi');
EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
INSERT INTO @controles (control, esperado, obtenido)
VALUES (N'"Messi" cifrado dos veces', N'bytes distintos, mismo texto al descifrar',
        CONCAT(IIF(@a = @b, N'bytes iguales', N'bytes distintos'),
               IIF(CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @a))
                 = CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @b)),
                   N', mismo texto al descifrar', N', otro texto al descifrar')));

/* 5. Con la clave cerrada, cifrar da NULL, y el NOT NULL de nombre y apellido impide guardarlo. */
INSERT INTO @controles (control, esperado, obtenido)
VALUES (N'Cifrar con la clave cerrada', N'NULL',
        ISNULL(CONVERT(NVARCHAR(400), Seguridad.fn_CifrarTexto(N'Messi'), 1), N'NULL'));
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

/* 6. Los SP cifran lo que guardan, se lee descifrado y controlan los duplicados. */
DECLARE @id_lista INT, @libre INT, @id INT, @guardado VARBINARY(256);
SELECT TOP (1) @id_lista = id_lista FROM Torneo.LISTA_CONVOCADOS ORDER BY id_lista;
SELECT TOP (1) @libre = id_jugador FROM Torneo.JUGADOR
WHERE id_lista = @id_lista AND fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY dorsal;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @libre, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @fecha_nacimiento = '2001-02-03', @id_jugador = @id OUTPUT;
    SELECT @guardado = apellido FROM Torneo.JUGADOR WHERE id_jugador = @id;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'Alta con usp_JUGADOR_Alta: dato guardado', N'varbinary', IIF(@guardado IS NULL, N'NULL', N'varbinary');
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'Alta con usp_JUGADOR_Alta: leído en Seguridad.vw_Jugador', N'Ñandú Pérez Cifrado 2001-02-03',
           CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento)
    FROM Seguridad.vw_Jugador WHERE id_jugador = @id;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'Alta con usp_JUGADOR_Alta: leído en Reportes.vw_Plantillas', N'Ñandú Pérez Cifrado',
           CONCAT(nombre, N' ', apellido)
    FROM Reportes.vw_Plantillas WHERE id_jugador = @id;
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 98;
    INSERT INTO @controles (control, esperado, obtenido) VALUES (N'Segunda alta del mismo jugador', N'rechazada', N'aceptada');
END TRY
BEGIN CATCH
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'Segunda alta del mismo jugador', N'rechazada',
            IIF(ERROR_MESSAGE() LIKE N'%ya figura en la lista%', N'rechazada', LEFT(ERROR_MESSAGE(), 400)));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* 7. Al terminar, ninguna clave queda abierta en la sesión. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Claves abiertas en la sesión', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;

SELECT n, control, esperado, obtenido, IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado
FROM @controles
ORDER BY n;

/* Cómo se ve un jugador guardado y cómo lo devuelve la vista. */
SELECT TOP (3) j.id_jugador, j.apellido AS apellido_guardado, v.apellido AS apellido_descifrado
FROM Torneo.JUGADOR AS j
INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = j.id_jugador
ORDER BY j.id_jugador;

IF EXISTS (SELECT 1 FROM @controles WHERE esperado <> obtenido)
    THROW 51014, N'El cifrado de los datos personales no da lo esperado.', 1;
GO
