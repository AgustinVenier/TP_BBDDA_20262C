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
 Archivo: 16_SP_Importacion.sql
 Objetivo: Crear los SP de lógica de negocio para la importación de datos
           externos: un upsert por registro (inserta si es nuevo, actualiza
           si existe) para cada dataset, identificado por su clave natural:
             DatosGenerales.usp_ImportarIndicadorEconomico  país (ISO alfa-3) + indicador + año
             Torneo.usp_ImportarSede                        nombre del estadio
             Torneo.usp_ImportarPartido                     número de partido
             Torneo.usp_ImportarJugador                     selección + apellido + nombre
             Arbitraje.usp_ImportarArbitro                  país + apellido + nombre
           Los procesos de importación de la Entrega 6 (25, 27 y 28) leen el
           archivo o la API a una tabla de staging, marcan con UPDATE por
           conjuntos los registros que no pasan las reglas y cargan los
           válidos en una sola llamada a un SP en bloque, con un parámetro de
           tipo tabla. Así se importan los registros válidos y se informan los
           errores de los demás, sin recorrerlos de a uno:
             DatosGenerales.usp_ImportarIndicadoresEconomicos  país (ISO alfa-3) + indicador + año
             DatosGenerales.usp_ImportarCotizaciones           moneda + fecha
             DatosGenerales.usp_ImportarFeriados               país + fecha
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 00 a 15. Su script de testing es
           66_Test_SP_Importacion.sql.
================================================================================

 Criterios comunes:
   - Las altas y modificaciones se hacen con los SP de ABM y de negocio, que
     validan cada dato, salvo los indicadores económicos y los idiomas nuevos
     de un árbitro, que se cargan con un solo INSERT (y UPDATE) porque el SP
     de importación ya los validó. Los errores se informan con THROW.
   - Importar dos veces el mismo dato no duplica nada: si el registro existe
     y no cambió, no se modifica y @accion devuelve SIN CAMBIOS. Si cambió,
     se actualizan solo los datos distintos (ACTUALIZADO); si no existía,
     se da de alta (INSERTADO).
   - Un dato que no viene (NULL) no borra el valor guardado, así se conserva
     la información histórica ya registrada.
   - Las traducciones de valores de las fuentes (fases y posiciones en
     inglés, por ejemplo) se hacen acá, en T-SQL.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ImportarIndicadorEconomico
  Upsert de un indicador (ej. PBI per cápita del Banco Mundial, NY.GDP.PCAP.CD).
  El país se identifica por su código ISO alfa-3, que es el que usa la API.
  Como Inglaterra y Escocia comparten el código GBR, el valor se registra
  para todos los países que tengan ese código. Valida: código ISO de 3
  letras y existente; indicador obligatorio, de hasta 30 caracteres y solo
  con letras sin acentos, números, puntos y guiones bajos; año obligatorio
  entre 1960 y el actual; valor obligatorio. Con eso cubre las reglas de
  usp_INDICADOR_ECONOMICO_Alta y _Modificacion, y hace el upsert para todos
  los países con un UPDATE y un INSERT.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarIndicadorEconomico
    @codigo_iso3       VARCHAR(10),
    @codigo_indicador  VARCHAR(60),
    @anio              SMALLINT,
    @valor             DECIMAL(18,4),
    @accion            VARCHAR(15) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @anio_actual  SMALLINT       = YEAR(GETDATE());
    DECLARE @insertados   INT = 0;
    DECLARE @actualizados INT = 0;

    SET @codigo_iso3      = UPPER(NULLIF(TRIM(@codigo_iso3), ''));
    SET @codigo_indicador = UPPER(NULLIF(TRIM(@codigo_indicador), ''));

    DECLARE @paises TABLE (id_pais SMALLINT PRIMARY KEY);
    INSERT INTO @paises (id_pais)
    SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_iso3 = @codigo_iso3;

    IF @codigo_iso3 IS NULL
        SET @errores += @nl + N'- El código ISO alfa-3 del país es obligatorio.';
    ELSE IF @codigo_iso3 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += @nl + N'- El código ISO alfa-3 debe tener 3 letras.';
    ELSE IF NOT EXISTS (SELECT 1 FROM @paises)
        SET @errores += @nl + N'- No hay ningún país con código ISO alfa-3 "' + @codigo_iso3 + N'".';

    IF @codigo_indicador IS NULL
        SET @errores += @nl + N'- El código del indicador es obligatorio.';
    ELSE IF LEN(@codigo_indicador) > 30
        SET @errores += @nl + N'- El código del indicador no puede superar los 30 caracteres.';
    ELSE IF @codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
        SET @errores += @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.';
    IF @anio IS NULL
        SET @errores += @nl + N'- El año es obligatorio.';
    ELSE IF @anio NOT BETWEEN 1960 AND @anio_actual
        SET @errores += @nl + N'- El año debe estar entre 1960 y ' + CAST(@anio_actual AS NVARCHAR(4)) + N'.';
    IF @valor IS NULL
        SET @errores += @nl + N'- El valor es obligatorio.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarIndicadorEconomico: no se pudo importar el indicador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Países que ya tienen el indicador para ese año, con otro valor.
        UPDATE ie
        SET valor = @valor, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
        INNER JOIN @paises AS p ON p.id_pais = ie.id_pais
        WHERE ie.codigo_indicador = @codigo_indicador AND ie.anio = @anio AND ie.valor <> @valor;
        SET @actualizados = @@ROWCOUNT;

        -- Países que todavía no lo tienen.
        INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
        SELECT p.id_pais, @codigo_indicador, @anio, @valor
        FROM @paises AS p
        WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                          WHERE ie.id_pais = p.id_pais AND ie.codigo_indicador = @codigo_indicador
                            AND ie.anio = @anio);
        SET @insertados = @@ROWCOUNT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SET @accion = CASE WHEN @insertados > 0 THEN 'INSERTADO'
                       WHEN @actualizados > 0 THEN 'ACTUALIZADO'
                       ELSE 'SIN CAMBIOS' END;
END;
GO


/*
  usp_ImportarSede
  Upsert de una sede por el nombre del estadio. El país se identifica por su
  código FIFA. Una sede nueva se registra con Torneo.usp_RegistrarSede, con
  sus 4 espacios publicitarios a la tarifa @tarifa_espacio_usd (se pueden
  ajustar después); en una sede existente se actualizan los datos que
  cambiaron. Valida: nombre del estadio obligatorio y país existente.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSede
    @nombre_estadio      VARCHAR(200),
    @ciudad              VARCHAR(200),
    @codigo_fifa_pais    VARCHAR(10),
    @capacidad           INT,
    @huso_horario        VARCHAR(100),
    @latitud             DECIMAL(9,6) = NULL,
    @longitud            DECIMAL(9,6) = NULL,
    @tarifa_espacio_usd  DECIMAL(9,2) = 0,
    @accion              VARCHAR(15)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_pais      SMALLINT;
    DECLARE @id_sede      INT;
    DECLARE @ciudad_act   VARCHAR(80);
    DECLARE @pais_act     SMALLINT;
    DECLARE @capac_act    INT;
    DECLARE @huso_act     VARCHAR(50);
    DECLARE @lat_act      DECIMAL(9,6);
    DECLARE @lon_act      DECIMAL(9,6);

    SET @nombre_estadio   = NULLIF(TRIM(@nombre_estadio), '');
    SET @codigo_fifa_pais = UPPER(NULLIF(TRIM(@codigo_fifa_pais), ''));
    SET @ciudad           = NULLIF(TRIM(@ciudad), '');
    SET @huso_horario     = NULLIF(TRIM(@huso_horario), '');

    SELECT @id_pais = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = @codigo_fifa_pais;

    IF @nombre_estadio IS NULL
        SET @errores += @nl + N'- El nombre del estadio es obligatorio.';

    IF @codigo_fifa_pais IS NULL
        SET @errores += @nl + N'- El código FIFA del país es obligatorio.';
    ELSE IF @id_pais IS NULL
        SET @errores += @nl + N'- No existe un país con código FIFA "' + @codigo_fifa_pais + N'".';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSede: no se pudo importar la sede.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @id_sede = id_sede, @ciudad_act = ciudad, @pais_act = id_pais, @capac_act = capacidad,
           @huso_act = huso_horario, @lat_act = latitud, @lon_act = longitud
    FROM Torneo.SEDE
    WHERE nombre_estadio = @nombre_estadio;

    IF @id_sede IS NULL
    BEGIN
        EXEC Torneo.usp_RegistrarSede
            @nombre_estadio = @nombre_estadio, @ciudad = @ciudad, @id_pais = @id_pais,
            @capacidad = @capacidad, @huso_horario = @huso_horario,
            @tarifa_espacio_1 = @tarifa_espacio_usd, @tarifa_espacio_2 = @tarifa_espacio_usd,
            @tarifa_espacio_3 = @tarifa_espacio_usd, @tarifa_espacio_4 = @tarifa_espacio_usd,
            @latitud = @latitud, @longitud = @longitud, @mostrar = 0;
        SET @accion = 'INSERTADO';
    END
    ELSE
    BEGIN
        -- Solo se pasan los datos que cambiaron (NULL = no se modifica).
        SET @ciudad       = IIF(@ciudad = @ciudad_act, NULL, @ciudad);
        SET @id_pais      = IIF(@id_pais = @pais_act, NULL, @id_pais);
        SET @capacidad    = IIF(@capacidad = @capac_act, NULL, @capacidad);
        SET @huso_horario = IIF(@huso_horario = @huso_act, NULL, @huso_horario);
        IF @latitud = @lat_act AND @longitud = @lon_act
            SELECT @latitud = NULL, @longitud = NULL;

        IF COALESCE(CAST(@capacidad AS VARCHAR(80)), CAST(@id_pais AS VARCHAR(80)), @ciudad,
                    @huso_horario, CAST(@latitud AS VARCHAR(80)), CAST(@longitud AS VARCHAR(80))) IS NULL
            SET @accion = 'SIN CAMBIOS';
        ELSE
        BEGIN
            EXEC Torneo.usp_SEDE_Modificacion
                @id_sede = @id_sede, @ciudad = @ciudad, @id_pais = @id_pais, @capacidad = @capacidad,
                @huso_horario = @huso_horario, @latitud = @latitud, @longitud = @longitud;
            SET @accion = 'ACTUALIZADO';
        END;
    END;
END;
GO


/*
  usp_ImportarPartido
  Upsert de un partido del fixture oficial por su número. La sede se
  identifica por el nombre del estadio y las selecciones por el código FIFA
  de su país. Acepta las fases en español (GRUPOS, OCTAVOS...) o como las
  publican FIFA y Wikipedia en inglés (Group A, Round of 32, Round of 16,
  Quarter-finals, Semi-finals, Third place, Final). Si trae el resultado, el
  partido queda FINALIZADO. Un partido ya finalizado conserva su
  programación: solo se actualizan el resultado y la asistencia.
  Valida: número, estadio y fase obligatorios, y que existan la sede y las
  selecciones. El resto lo validan Torneo.usp_PARTIDO_Alta y
  Torneo.usp_PARTIDO_Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarPartido
    @numero_partido          TINYINT,
    @nombre_estadio          VARCHAR(200),
    @fase                    VARCHAR(50),
    @fecha_hora_utc          DATETIME2(0) = NULL,
    @fecha_hora_local        DATETIME2(0) = NULL,
    @codigo_fifa_local       VARCHAR(10)  = NULL,
    @codigo_fifa_visitante   VARCHAR(10)  = NULL,
    @goles_local             TINYINT      = NULL,
    @goles_visitante         TINYINT      = NULL,
    @penales_local           TINYINT      = NULL,
    @penales_visitante       TINYINT      = NULL,
    @asistencia              INT          = NULL,
    @accion                  VARCHAR(15)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia    BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_sede        INT;
    DECLARE @huso           VARCHAR(50);
    DECLARE @id_local       INT;
    DECLARE @id_visitante   INT;
    DECLARE @id_partido     INT;
    DECLARE @estado_act     VARCHAR(12);
    DECLARE @sede_act       INT;
    DECLARE @fase_act       VARCHAR(15);
    DECLARE @utc_act        DATETIME2(0);
    DECLARE @local_act      INT;
    DECLARE @visit_act      INT;
    DECLARE @gl_act         TINYINT;
    DECLARE @gv_act         TINYINT;
    DECLARE @pl_act         TINYINT;
    DECLARE @pv_act         TINYINT;
    DECLARE @asist_act      INT;
    DECLARE @trae_resultado BIT;
    DECLARE @estado         VARCHAR(12);

    SET @nombre_estadio        = NULLIF(TRIM(@nombre_estadio), '');
    SET @codigo_fifa_local     = UPPER(NULLIF(TRIM(@codigo_fifa_local), ''));
    SET @codigo_fifa_visitante = UPPER(NULLIF(TRIM(@codigo_fifa_visitante), ''));
    SET @fase                  = UPPER(NULLIF(TRIM(@fase), ''));
    SET @trae_resultado        = IIF(@goles_local IS NOT NULL OR @goles_visitante IS NOT NULL, 1, 0);

    -- Traducción de la fase.
    SET @fase = CASE
                    WHEN @fase LIKE 'GROUP%' OR @fase LIKE 'GRUPO%'               THEN 'GRUPOS'
                    WHEN @fase IN ('ROUND OF 32', 'DIECISEISAVOS DE FINAL')        THEN 'DIECISEISAVOS'
                    WHEN @fase IN ('ROUND OF 16', 'OCTAVOS DE FINAL')              THEN 'OCTAVOS'
                    WHEN @fase LIKE 'QUARTER%' OR @fase = 'CUARTOS DE FINAL'        THEN 'CUARTOS'
                    WHEN @fase LIKE 'SEMI%'                                         THEN 'SEMIFINAL'
                    WHEN @fase LIKE '%THIRD%' OR @fase LIKE 'TERCER%'               THEN 'TERCER_PUESTO'
                    ELSE @fase
                END;

    SELECT @id_sede = id_sede, @huso = huso_horario FROM Torneo.SEDE WHERE nombre_estadio = @nombre_estadio;

    SELECT @id_local = s.id_seleccion
    FROM Torneo.SELECCION AS s
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa = @codigo_fifa_local;

    SELECT @id_visitante = s.id_seleccion
    FROM Torneo.SELECCION AS s
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa = @codigo_fifa_visitante;

    IF @numero_partido IS NULL
        SET @errores += @nl + N'- El número de partido es obligatorio.';

    IF @nombre_estadio IS NULL
        SET @errores += @nl + N'- El estadio es obligatorio.';
    ELSE IF @id_sede IS NULL
        SET @errores += @nl + N'- No existe la sede "' + @nombre_estadio + N'" (se importa antes que los partidos).';

    IF @fase IS NULL
        SET @errores += @nl + N'- La fase es obligatoria.';

    IF @codigo_fifa_local IS NOT NULL AND @id_local IS NULL
        SET @errores += @nl + N'- No hay una selección con código FIFA "' + @codigo_fifa_local + N'".';
    IF @codigo_fifa_visitante IS NOT NULL AND @id_visitante IS NULL
        SET @errores += @nl + N'- No hay una selección con código FIFA "' + @codigo_fifa_visitante + N'".';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarPartido: no se pudo importar el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Hora UTC del dato, para compararla con la guardada.
    IF @fecha_hora_utc IS NULL AND @fecha_hora_local IS NOT NULL
        SET @fecha_hora_utc = CONVERT(DATETIME2(0), (@fecha_hora_local AT TIME ZONE @huso) AT TIME ZONE 'UTC');

    SELECT @id_partido = id_partido, @estado_act = estado, @sede_act = id_sede, @fase_act = fase,
           @utc_act = fecha_hora_utc, @local_act = id_seleccion_local, @visit_act = id_seleccion_visitante,
           @gl_act = goles_local, @gv_act = goles_visitante, @pl_act = penales_local,
           @pv_act = penales_visitante, @asist_act = asistencia
    FROM Torneo.PARTIDO
    WHERE numero_partido = @numero_partido;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        IF @id_partido IS NULL
        BEGIN
            EXEC Torneo.usp_PARTIDO_Alta
                @numero_partido = @numero_partido, @id_sede = @id_sede, @fase = @fase,
                @fecha_hora_utc = @fecha_hora_utc,
                @id_seleccion_local = @id_local, @id_seleccion_visitante = @id_visitante,
                @id_partido = @id_partido OUTPUT;

            IF @trae_resultado = 1
                EXEC Torneo.usp_PARTIDO_Modificacion
                    @id_partido = @id_partido, @goles_local = @goles_local, @goles_visitante = @goles_visitante,
                    @penales_local = @penales_local, @penales_visitante = @penales_visitante,
                    @asistencia = @asistencia, @estado = 'FINALIZADO';

            SET @accion = 'INSERTADO';
        END
        ELSE
        BEGIN
            -- Programación: solo los datos que cambiaron, y nunca en un partido ya jugado.
            IF @estado_act IN ('PROGRAMADO', 'SUSPENDIDO')
                SELECT @id_sede        = IIF(@id_sede = @sede_act, NULL, @id_sede),
                       @fase           = IIF(@fase = @fase_act, NULL, @fase),
                       @fecha_hora_utc = IIF(@fecha_hora_utc = @utc_act, NULL, @fecha_hora_utc),
                       @id_local       = IIF(@id_local = @local_act, NULL, @id_local),
                       @id_visitante   = IIF(@id_visitante = @visit_act, NULL, @id_visitante);
            ELSE
                SELECT @id_sede = NULL, @fase = NULL, @fecha_hora_utc = NULL, @id_local = NULL, @id_visitante = NULL;

            -- Resultado y asistencia: solo los que cambiaron.
            SELECT @goles_local       = IIF(@goles_local = @gl_act, NULL, @goles_local),
                   @goles_visitante   = IIF(@goles_visitante = @gv_act, NULL, @goles_visitante),
                   @penales_local     = IIF(@penales_local = @pl_act, NULL, @penales_local),
                   @penales_visitante = IIF(@penales_visitante = @pv_act, NULL, @penales_visitante),
                   @asistencia        = IIF(@asistencia = @asist_act, NULL, @asistencia);

            SET @estado = IIF(@trae_resultado = 1 AND @estado_act <> 'FINALIZADO', 'FINALIZADO', NULL);

            IF @id_sede IS NULL AND @fase IS NULL AND @fecha_hora_utc IS NULL AND @id_local IS NULL
               AND @id_visitante IS NULL AND @goles_local IS NULL AND @goles_visitante IS NULL
               AND @penales_local IS NULL AND @penales_visitante IS NULL AND @asistencia IS NULL
               AND @estado IS NULL
                SET @accion = 'SIN CAMBIOS';
            ELSE
            BEGIN
                EXEC Torneo.usp_PARTIDO_Modificacion
                    @id_partido = @id_partido, @id_sede = @id_sede, @fase = @fase,
                    @fecha_hora_utc = @fecha_hora_utc,
                    @id_seleccion_local = @id_local, @id_seleccion_visitante = @id_visitante,
                    @goles_local = @goles_local, @goles_visitante = @goles_visitante,
                    @penales_local = @penales_local, @penales_visitante = @penales_visitante,
                    @asistencia = @asistencia, @estado = @estado;
                SET @accion = 'ACTUALIZADO';
            END;
        END;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarJugador
  Upsert de un jugador de la lista de convocados de una selección (código
  FIFA de su país) por apellido y nombre. Acepta las posiciones en español o
  abreviadas como en las planillas de FIFA y Wikipedia (GK, DF, MF, FW). Un
  jugador nuevo se da de alta en la fecha de presentación de la lista.
  Valida: que la selección exista y tenga su lista, y nombre y apellido
  obligatorios. El resto lo validan Torneo.usp_JUGADOR_Alta y
  Torneo.usp_JUGADOR_Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarJugador
    @codigo_fifa_seleccion  VARCHAR(10),
    @nombre                 NVARCHAR(120),
    @apellido               NVARCHAR(120),
    @posicion               VARCHAR(30),
    @dorsal                 TINYINT,
    @fecha_nacimiento       DATE          = NULL,
    @club_origen            NVARCHAR(200) = NULL,
    @accion                 VARCHAR(15)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores            NVARCHAR(2048) = N'';
    DECLARE @nl                 NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @id_lista           INT;
    DECLARE @fecha_presentacion DATE;
    DECLARE @id_jugador         INT;
    DECLARE @posicion_act       VARCHAR(15);
    DECLARE @dorsal_act         TINYINT;
    DECLARE @nacimiento_act     DATE;
    DECLARE @club_act           NVARCHAR(100);

    SET @codigo_fifa_seleccion = UPPER(NULLIF(TRIM(@codigo_fifa_seleccion), ''));
    SET @nombre                = NULLIF(TRIM(@nombre), N'');
    SET @apellido              = NULLIF(TRIM(@apellido), N'');
    SET @club_origen           = NULLIF(TRIM(@club_origen), N'');
    SET @posicion              = UPPER(NULLIF(TRIM(@posicion), ''));

    -- Traducción de la posición.
    SET @posicion = CASE
                        WHEN @posicion IN ('GK', 'POR', 'ARQ', 'GOALKEEPER') THEN 'ARQUERO'
                        WHEN @posicion IN ('DF', 'DEF', 'DEFENDER')          THEN 'DEFENSOR'
                        WHEN @posicion IN ('MF', 'MED', 'MIDFIELDER')        THEN 'MEDIOCAMPISTA'
                        WHEN @posicion IN ('FW', 'DEL', 'FORWARD')           THEN 'DELANTERO'
                        ELSE @posicion
                    END;

    SELECT @id_lista = l.id_lista, @fecha_presentacion = l.fecha_presentacion
    FROM Torneo.LISTA_CONVOCADOS AS l
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa = @codigo_fifa_seleccion;

    IF @codigo_fifa_seleccion IS NULL
        SET @errores += @nl + N'- El código FIFA de la selección es obligatorio.';
    ELSE IF @id_lista IS NULL
        SET @errores += @nl + N'- No hay una selección con lista de convocados para el código FIFA "'
                      + @codigo_fifa_seleccion + N'".';

    IF @nombre IS NULL OR @apellido IS NULL
        SET @errores += @nl + N'- El nombre y el apellido son obligatorios.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarJugador: no se pudo importar el jugador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @id_jugador = id_jugador, @posicion_act = posicion_habitual, @dorsal_act = dorsal,
           @nacimiento_act = fecha_nacimiento, @club_act = club_origen
    FROM Torneo.JUGADOR
    WHERE id_lista = @id_lista AND apellido = @apellido AND nombre = @nombre;

    IF @id_jugador IS NULL
    BEGIN
        EXEC Torneo.usp_JUGADOR_Alta
            @id_lista = @id_lista, @nombre = @nombre, @apellido = @apellido,
            @posicion_habitual = @posicion, @dorsal = @dorsal, @fecha_nacimiento = @fecha_nacimiento,
            @club_origen = @club_origen, @fecha_alta = @fecha_presentacion, @motivo_alta = 'Importación';
        SET @accion = 'INSERTADO';
    END
    ELSE
    BEGIN
        SELECT @posicion         = IIF(@posicion = @posicion_act, NULL, @posicion),
               @dorsal           = IIF(@dorsal = @dorsal_act, NULL, @dorsal),
               @fecha_nacimiento = IIF(@fecha_nacimiento = @nacimiento_act, NULL, @fecha_nacimiento),
               @club_origen      = IIF(@club_origen = @club_act, NULL, @club_origen);

        IF @posicion IS NULL AND @dorsal IS NULL AND @fecha_nacimiento IS NULL AND @club_origen IS NULL
            SET @accion = 'SIN CAMBIOS';
        ELSE
        BEGIN
            EXEC Torneo.usp_JUGADOR_Modificacion
                @id_jugador = @id_jugador, @posicion_habitual = @posicion, @dorsal = @dorsal,
                @fecha_nacimiento = @fecha_nacimiento, @club_origen = @club_origen;
            SET @accion = 'ACTUALIZADO';
        END;
    END;
END;
GO


/*
  usp_ImportarArbitro
  Upsert de un árbitro por país (código FIFA), apellido y nombre. @idiomas es
  una lista de códigos ISO 639-1 separados por comas: a un árbitro existente
  se le agregan los idiomas que no tenía (no se le quita ninguno). La
  categoría admite CONFEDERATION como sinónimo de CONFEDERACION.
  Valida: país existente y nombre y apellido obligatorios. El resto lo
  validan Arbitraje.usp_RegistrarArbitro y los SP de ABM.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarArbitro
    @codigo_fifa_pais  VARCHAR(10),
    @nombre            NVARCHAR(120),
    @apellido          NVARCHAR(120),
    @categoria         VARCHAR(30),
    @idiomas           VARCHAR(200),
    @fecha_nacimiento  DATE        = NULL,
    @accion            VARCHAR(15) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia    BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_pais        SMALLINT;
    DECLARE @id_arbitro     INT;
    DECLARE @categoria_act  VARCHAR(15);
    DECLARE @nacimiento_act DATE;
    DECLARE @cambios        INT = 0;

    SET @codigo_fifa_pais = UPPER(NULLIF(TRIM(@codigo_fifa_pais), ''));
    SET @nombre           = NULLIF(TRIM(@nombre), N'');
    SET @apellido         = NULLIF(TRIM(@apellido), N'');
    SET @categoria        = UPPER(NULLIF(TRIM(@categoria), ''));
    SET @categoria        = IIF(@categoria = 'CONFEDERATION', 'CONFEDERACION', @categoria);

    SELECT @id_pais = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = @codigo_fifa_pais;

    IF @codigo_fifa_pais IS NULL
        SET @errores += @nl + N'- El código FIFA del país es obligatorio.';
    ELSE IF @id_pais IS NULL
        SET @errores += @nl + N'- No existe un país con código FIFA "' + @codigo_fifa_pais + N'".';

    IF @nombre IS NULL OR @apellido IS NULL
        SET @errores += @nl + N'- El nombre y el apellido son obligatorios.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ImportarArbitro: no se pudo importar el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @id_arbitro = id_arbitro, @categoria_act = categoria, @nacimiento_act = fecha_nacimiento
    FROM Arbitraje.ARBITRO
    WHERE id_pais = @id_pais AND apellido = @apellido AND nombre = @nombre;

    IF @id_arbitro IS NULL
    BEGIN
        EXEC Arbitraje.usp_RegistrarArbitro
            @id_pais = @id_pais, @nombre = @nombre, @apellido = @apellido, @categoria = @categoria,
            @idiomas = @idiomas, @fecha_nacimiento = @fecha_nacimiento, @mostrar = 0;
        SET @accion = 'INSERTADO';
        RETURN;
    END;

    -- Idiomas que el árbitro todavía no tiene.
    DECLARE @nuevos TABLE (id_idioma SMALLINT PRIMARY KEY);
    INSERT INTO @nuevos (id_idioma)
    SELECT DISTINCT i.id_idioma
    FROM STRING_SPLIT(@idiomas, ',') AS c
    INNER JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = LOWER(TRIM(c.value))
    WHERE NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai
                      WHERE ai.id_arbitro = @id_arbitro AND ai.id_idioma = i.id_idioma);

    SELECT @categoria        = IIF(@categoria = @categoria_act, NULL, @categoria),
           @fecha_nacimiento = IIF(@fecha_nacimiento = @nacimiento_act, NULL, @fecha_nacimiento);

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        IF @categoria IS NOT NULL OR @fecha_nacimiento IS NOT NULL
        BEGIN
            EXEC Arbitraje.usp_ARBITRO_Modificacion
                @id_arbitro = @id_arbitro, @categoria = @categoria, @fecha_nacimiento = @fecha_nacimiento;
            SET @cambios += 1;
        END;

        -- El árbitro existe y @nuevos solo tiene idiomas existentes que todavía no
        -- tiene: no queda nada que controle Arbitraje.usp_ARBITRO_IDIOMA_Alta.
        INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma)
        SELECT @id_arbitro, id_idioma FROM @nuevos;
        SET @cambios += @@ROWCOUNT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SET @accion = IIF(@cambios > 0, 'ACTUALIZADO', 'SIN CAMBIOS');
END;
GO


/* ============================================================================
   IMPORTACIÓN EN BLOQUE
   Indicadores, cotizaciones y feriados llegan de a cientos por archivo o
   consulta a la API. Estos SP reciben todos los registros en un parámetro de
   tipo tabla y hacen el upsert con un UPDATE y un INSERT, sin recorrerlos de
   a uno. Si un registro no pasa las reglas no se carga ninguno: el proceso
   que lee el archivo o la API los valida antes con las mismas reglas y pasa
   solo los válidos.
   Un tipo no se puede modificar mientras un SP lo use: se borran los SP y
   los tipos, y se vuelven a crear.
   ============================================================================ */
DROP PROCEDURE IF EXISTS DatosGenerales.usp_ImportarIndicadoresEconomicos;
DROP PROCEDURE IF EXISTS DatosGenerales.usp_ImportarCotizaciones;
DROP PROCEDURE IF EXISTS DatosGenerales.usp_ImportarFeriados;
DROP TYPE IF EXISTS DatosGenerales.TT_INDICADOR_ECONOMICO;
DROP TYPE IF EXISTS DatosGenerales.TT_COTIZACION;
DROP TYPE IF EXISTS DatosGenerales.TT_FERIADO;
GO

/*
  TT_INDICADOR_ECONOMICO / TT_COTIZACION / TT_FERIADO
  Una fila por registro. Las columnas admiten NULL para que el SP pueda
  informar qué filas vienen incompletas.
*/
CREATE TYPE DatosGenerales.TT_INDICADOR_ECONOMICO AS TABLE (
    codigo_iso3       VARCHAR(10)   NULL,
    codigo_indicador  VARCHAR(60)   NULL,
    anio              SMALLINT      NULL,
    valor             DECIMAL(18,4) NULL
);
GO

CREATE TYPE DatosGenerales.TT_COTIZACION AS TABLE (
    codigo_moneda     VARCHAR(10)   NULL,
    fecha             DATE          NULL,
    unidades_por_usd  DECIMAL(19,6) NULL
);
GO

CREATE TYPE DatosGenerales.TT_FERIADO AS TABLE (
    id_pais  SMALLINT      NULL,
    fecha    DATE          NULL,
    nombre   NVARCHAR(400) NULL
);
GO


/*
  usp_ImportarIndicadoresEconomicos
  Upsert de indicadores por país, indicador y año (ej. el PBI per cápita de
  la API del Banco Mundial, NY.GDP.PCAP.CD), con las reglas de
  usp_ImportarIndicadorEconomico. El país se identifica por su código ISO
  alfa-3: como Inglaterra y Escocia comparten GBR, un registro con ese código
  se carga para las dos.
  Valida, para todo el conjunto: filas completas; códigos ISO alfa-3 de 3
  letras y existentes; códigos de indicador de hasta 30 caracteres, solo con
  letras sin acentos, números, puntos y guiones bajos; años entre 1960 y el
  actual; que no venga dos veces el mismo país, indicador y año. Con eso
  cubre las reglas de usp_INDICADOR_ECONOMICO_Alta y _Modificacion. Los
  valores que cambiaron se actualizan con su fecha_actualizacion; los que no
  existían se insertan. Devuelve cuántos registros se insertaron, se
  actualizaron y quedaron sin cambios. Un registro de GBR cuenta una vez,
  como en usp_ImportarIndicadorEconomico: INSERTADO si le falta a alguno de
  los dos países, ACTUALIZADO si cambió en alguno y si no, SIN CAMBIOS.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarIndicadoresEconomicos
    @indicadores   DatosGenerales.TT_INDICADOR_ECONOMICO READONLY,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @anio_actual  SMALLINT       = YEAR(GETDATE());
    DECLARE @incompletas  INT;

    -- Copia normalizada, la que se valida y se carga, con lo que le pasa a cada registro.
    DECLARE @lista TABLE (
        codigo_iso3       VARCHAR(10),
        codigo_indicador  VARCHAR(60),
        anio              SMALLINT,
        valor             DECIMAL(18,4),
        accion            VARCHAR(15)
    );

    INSERT INTO @lista (codigo_iso3, codigo_indicador, anio, valor)
    SELECT UPPER(NULLIF(TRIM(codigo_iso3), '')), UPPER(NULLIF(TRIM(codigo_indicador), '')), anio, valor
    FROM @indicadores;

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE codigo_iso3 IS NULL OR codigo_indicador IS NULL OR anio IS NULL OR valor IS NULL;
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10))
                      + N' fila(s) sin país, indicador, año o valor.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Códigos ISO alfa-3 que no tiene ningún país: ' + STRING_AGG(codigo_iso3, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) l.codigo_iso3 FROM @lista AS l
              WHERE l.codigo_iso3 IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.codigo_iso3 = l.codigo_iso3)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Códigos de indicador de más de 30 caracteres o con caracteres que no son letras sin '
               + N'acentos, números, puntos ni guiones bajos: ' + STRING_AGG(codigo_indicador, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) codigo_indicador FROM @lista
              WHERE LEN(codigo_indicador) > 30
                 OR codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%') AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Años que no están entre 1960 y ' + CAST(@anio_actual AS NVARCHAR(4)) + N': '
               + STRING_AGG(CAST(anio AS NVARCHAR(10)), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) anio FROM @lista WHERE anio NOT BETWEEN 1960 AND @anio_actual) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Indicadores repetidos (país, indicador y año): '
               + STRING_AGG(codigo_iso3 + N' ' + codigo_indicador + N' ' + CAST(anio AS NVARCHAR(4)), ', ') + N'.'
        FROM (SELECT TOP (10) codigo_iso3, codigo_indicador, anio FROM @lista
              WHERE codigo_iso3 IS NOT NULL AND codigo_indicador IS NOT NULL AND anio IS NOT NULL
              GROUP BY codigo_iso3, codigo_indicador, anio HAVING COUNT(*) > 1) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarIndicadoresEconomicos: no se importó ningún indicador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Lo que le pasa a cada registro se calcula antes de cargar: después estarían todos sin cambios.
    UPDATE l
    SET accion = CASE WHEN EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p
                                   WHERE p.codigo_iso3 = l.codigo_iso3
                                     AND NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                                                     WHERE ie.id_pais = p.id_pais
                                                       AND ie.codigo_indicador = l.codigo_indicador
                                                       AND ie.anio = l.anio))
                           THEN 'INSERTADO'
                      WHEN EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p
                                   INNER JOIN DatosGenerales.INDICADOR_ECONOMICO AS ie ON ie.id_pais = p.id_pais
                                   WHERE p.codigo_iso3 = l.codigo_iso3
                                     AND ie.codigo_indicador = l.codigo_indicador
                                     AND ie.anio = l.anio
                                     AND ie.valor <> l.valor)
                           THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM @lista AS l;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Los que ya están cargados con otro valor.
        UPDATE ie
        SET valor = l.valor, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
        INNER JOIN @lista AS l ON l.codigo_iso3 = p.codigo_iso3
                              AND l.codigo_indicador = ie.codigo_indicador
                              AND l.anio = ie.anio
        WHERE ie.valor <> l.valor;

        -- Los que todavía no están, en cada país con ese código ISO.
        INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
        SELECT p.id_pais, l.codigo_indicador, l.anio, l.valor
        FROM @lista AS l
        INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_iso3 = l.codigo_iso3
        WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                          WHERE ie.id_pais = p.id_pais
                            AND ie.codigo_indicador = l.codigo_indicador
                            AND ie.anio = l.anio);

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0)
    FROM @lista;
END;
GO


/*
  usp_ImportarCotizaciones
  Upsert de cotizaciones por moneda y fecha (ej. las de la API Frankfurter).
  Valida, para todo el conjunto: filas completas; moneda de 3 letras y
  distinta del dólar; fechas no futuras; unidades por dólar mayores que
  cero; que no venga dos veces la misma moneda y fecha. Con eso cubre las
  reglas de usp_COTIZACION_Alta y _Modificacion. Las cotizaciones que
  cambiaron se actualizan con su fecha_actualizacion; las que no existían se
  insertan. Devuelve cuántas se insertaron, se actualizaron y quedaron sin
  cambios.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarCotizaciones
    @cotizaciones  DatosGenerales.TT_COTIZACION READONLY,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @hoy          DATE           = CONVERT(DATE, GETDATE());
    DECLARE @incompletas  INT;

    -- Copia normalizada, la que se valida y se carga.
    DECLARE @lista TABLE (
        codigo_moneda     VARCHAR(10),
        fecha             DATE,
        unidades_por_usd  DECIMAL(19,6)
    );

    INSERT INTO @lista (codigo_moneda, fecha, unidades_por_usd)
    SELECT UPPER(NULLIF(TRIM(codigo_moneda), '')), fecha, unidades_por_usd
    FROM @cotizaciones;

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE codigo_moneda IS NULL OR fecha IS NULL OR unidades_por_usd IS NULL;
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10))
                      + N' fila(s) sin moneda, fecha o unidades por dólar.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Monedas que no son un código de 3 letras (ISO 4217): ' + STRING_AGG(codigo_moneda, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) codigo_moneda FROM @lista
              WHERE codigo_moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]') AS x), N'');

    IF EXISTS (SELECT 1 FROM @lista WHERE codigo_moneda = 'USD')
        SET @errores += @nl + N'- El dólar no lleva cotización: es la base y vale siempre 1.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Fechas futuras: ' + STRING_AGG(CONVERT(NVARCHAR(10), fecha, 103), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) fecha FROM @lista WHERE fecha > @hoy) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Unidades por dólar que no son mayores que cero: ' + STRING_AGG(codigo_moneda, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) ISNULL(codigo_moneda, '(sin moneda)') AS codigo_moneda
              FROM @lista WHERE unidades_por_usd <= 0) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Cotizaciones repetidas: ' + STRING_AGG(codigo_moneda + N' ' + CONVERT(NVARCHAR(10), fecha, 103), ', ') + N'.'
        FROM (SELECT TOP (10) codigo_moneda, fecha FROM @lista
              WHERE codigo_moneda IS NOT NULL AND fecha IS NOT NULL
              GROUP BY codigo_moneda, fecha HAVING COUNT(*) > 1) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarCotizaciones: no se importó ninguna cotización.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Las que ya están cargadas con otro valor.
        UPDATE c
        SET unidades_por_usd = l.unidades_por_usd, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.COTIZACION AS c
        INNER JOIN @lista AS l ON l.codigo_moneda = c.codigo_moneda AND l.fecha = c.fecha
        WHERE c.unidades_por_usd <> l.unidades_por_usd;
        SET @actualizados = @@ROWCOUNT;

        -- Las que todavía no están.
        INSERT INTO DatosGenerales.COTIZACION (codigo_moneda, fecha, unidades_por_usd)
        SELECT l.codigo_moneda, l.fecha, l.unidades_por_usd
        FROM @lista AS l
        WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.COTIZACION AS c
                          WHERE c.codigo_moneda = l.codigo_moneda AND c.fecha = l.fecha);
        SET @insertados = @@ROWCOUNT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SET @sin_cambios = (SELECT COUNT(*) FROM @lista) - @insertados - @actualizados;
END;
GO


/*
  usp_ImportarFeriados
  Upsert de feriados por país y fecha (ej. los de la API Nager.Date).
  Valida, para todo el conjunto: filas completas; países existentes;
  nombres de hasta 200 caracteres; que no venga dos veces el mismo país y
  fecha (dos feriados del mismo día van juntos en el nombre). Con eso cubre
  las reglas de usp_FERIADO_Alta y _Modificacion. Los feriados que cambiaron
  de nombre se actualizan con su fecha_actualizacion; los que no existían se
  insertan. Devuelve cuántos se insertaron, se actualizaron y quedaron sin
  cambios.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarFeriados
    @feriados      DatosGenerales.TT_FERIADO READONLY,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @incompletas  INT;

    -- Copia normalizada, la que se valida y se carga.
    DECLARE @lista TABLE (
        id_pais  SMALLINT,
        fecha    DATE,
        nombre   NVARCHAR(400)
    );

    INSERT INTO @lista (id_pais, fecha, nombre)
    SELECT id_pais, fecha, NULLIF(TRIM(nombre), N'')
    FROM @feriados;

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE id_pais IS NULL OR fecha IS NULL OR nombre IS NULL;
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10)) + N' fila(s) sin país, fecha o nombre.';

    SET @errores += ISNULL((
        SELECT @nl + N'- No existen los países con id: ' + STRING_AGG(CAST(id_pais AS NVARCHAR(10)), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) l.id_pais FROM @lista AS l
              WHERE l.id_pais IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.id_pais = l.id_pais)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Nombres de más de 200 caracteres (fechas): ' + STRING_AGG(CONVERT(NVARCHAR(10), fecha, 103), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) fecha FROM @lista WHERE LEN(nombre) > 200) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Feriados repetidos (id de país y fecha): '
               + STRING_AGG(CAST(id_pais AS NVARCHAR(10)) + N' ' + CONVERT(NVARCHAR(10), fecha, 103), ', ') + N'.'
        FROM (SELECT TOP (10) id_pais, fecha FROM @lista
              WHERE id_pais IS NOT NULL AND fecha IS NOT NULL
              GROUP BY id_pais, fecha HAVING COUNT(*) > 1) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarFeriados: no se importó ningún feriado.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Los que ya están cargados con otro nombre.
        UPDATE f
        SET nombre = l.nombre, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.FERIADO AS f
        INNER JOIN @lista AS l ON l.id_pais = f.id_pais AND l.fecha = f.fecha
        WHERE f.nombre <> l.nombre;
        SET @actualizados = @@ROWCOUNT;

        -- Los que todavía no están.
        INSERT INTO DatosGenerales.FERIADO (id_pais, fecha, nombre)
        SELECT l.id_pais, l.fecha, l.nombre
        FROM @lista AS l
        WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.FERIADO AS f
                          WHERE f.id_pais = l.id_pais AND f.fecha = l.fecha);
        SET @insertados = @@ROWCOUNT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SET @sin_cambios = (SELECT COUNT(*) FROM @lista) - @insertados - @actualizados;
END;
GO


/* ============================================================================
   IMPORTACIÓN EN BLOQUE DEL TORNEO
   Sedes, selecciones, jugadores, partidos y lo que pasó en cada partido
   (formaciones, cambios, goles y tarjetas), para cargar un torneo real desde
   archivos (23_SP_Importar_Mundial2026.sql y 24_SP_Importar_Jugadores.sql).
   Mismo criterio que la sección anterior: cada SP recibe todos los registros
   en un parámetro de tipo tabla, valida el conjunto y, si algún registro no
   pasa las reglas, no carga ninguno. El proceso que lee el archivo los valida
   antes con las mismas reglas y pasa solo los válidos.
   Los jugadores de los eventos llegan con su id: identificarlos por el nombre
   que trae el archivo es tarea del proceso de importación.
   ============================================================================ */
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarSedes;
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarSelecciones;
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarJugadores;
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarPartidos;
DROP PROCEDURE IF EXISTS DesarrolloPartido.usp_ImportarDesarrolloPartidos;
DROP TYPE IF EXISTS Torneo.TT_SEDE;
DROP TYPE IF EXISTS Torneo.TT_SELECCION;
DROP TYPE IF EXISTS Torneo.TT_JUGADOR;
DROP TYPE IF EXISTS Torneo.TT_PARTIDO;
DROP TYPE IF EXISTS DesarrolloPartido.TT_ALINEACION_PARTIDO;
DROP TYPE IF EXISTS DesarrolloPartido.TT_CAMBIO;
DROP TYPE IF EXISTS DesarrolloPartido.TT_GOL;
DROP TYPE IF EXISTS DesarrolloPartido.TT_AMONESTACION;
GO

CREATE TYPE Torneo.TT_SEDE AS TABLE (
    nombre_estadio    VARCHAR(200)  NULL,
    ciudad            VARCHAR(200)  NULL,
    codigo_fifa_pais  VARCHAR(10)   NULL,
    capacidad         INT           NULL,
    huso_horario      VARCHAR(100)  NULL,
    latitud           DECIMAL(9,6)  NULL,
    longitud          DECIMAL(9,6)  NULL,
    tarifa_espacio_1  DECIMAL(9,2)  NULL,
    tarifa_espacio_2  DECIMAL(9,2)  NULL,
    tarifa_espacio_3  DECIMAL(9,2)  NULL,
    tarifa_espacio_4  DECIMAL(9,2)  NULL
);
GO

CREATE TYPE Torneo.TT_SELECCION AS TABLE (
    codigo_fifa         VARCHAR(10)   NULL,
    confederacion       VARCHAR(20)   NULL,
    grupo               VARCHAR(5)    NULL,
    nombre_alternativo  NVARCHAR(200) NULL
);
GO

CREATE TYPE Torneo.TT_JUGADOR AS TABLE (
    codigo_fifa_seleccion  VARCHAR(10)   NULL,
    nombre                 NVARCHAR(120) NULL,
    apellido               NVARCHAR(120) NULL,
    posicion               VARCHAR(30)   NULL,
    dorsal                 TINYINT       NULL,
    fecha_nacimiento       DATE          NULL,
    club_origen            NVARCHAR(200) NULL
);
GO

CREATE TYPE Torneo.TT_PARTIDO AS TABLE (
    numero_partido         TINYINT       NULL,
    nombre_estadio         VARCHAR(200)  NULL,
    fase                   VARCHAR(30)   NULL,
    fecha_hora_utc         DATETIME2(0)  NULL,
    codigo_fifa_local      VARCHAR(10)   NULL,
    codigo_fifa_visitante  VARCHAR(10)   NULL,
    goles_local            TINYINT       NULL,
    goles_visitante        TINYINT       NULL,
    penales_local          TINYINT       NULL,
    penales_visitante      TINYINT       NULL,
    asistencia             INT           NULL
);
GO

CREATE TYPE DesarrolloPartido.TT_ALINEACION_PARTIDO AS TABLE (
    numero_partido      TINYINT      NULL,
    id_jugador          INT          NULL,
    es_titular          BIT          NULL,
    posicion_en_cancha  VARCHAR(30)  NULL
);
GO

CREATE TYPE DesarrolloPartido.TT_CAMBIO AS TABLE (
    numero_partido    TINYINT      NULL,
    id_jugador_sale   INT          NULL,
    id_jugador_entra  INT          NULL,
    minuto            TINYINT      NULL,
    minuto_adicional  TINYINT      NULL,
    en_entretiempo    BIT          NULL,
    motivo            VARCHAR(12)  NULL
);
GO

CREATE TYPE DesarrolloPartido.TT_GOL AS TABLE (
    numero_partido    TINYINT      NULL,
    id_jugador_autor  INT          NULL,
    tipo_gol          VARCHAR(40)  NULL,
    periodo           VARCHAR(15)  NULL,
    minuto            TINYINT      NULL,
    minuto_adicional  TINYINT      NULL
);
GO

CREATE TYPE DesarrolloPartido.TT_AMONESTACION AS TABLE (
    numero_partido     TINYINT       NULL,
    id_jugador         INT           NULL,
    tipo_tarjeta       VARCHAR(8)    NULL,
    es_doble_amarilla  BIT           NULL,
    minuto             TINYINT       NULL,
    minuto_adicional   TINYINT       NULL,
    motivo             VARCHAR(200)  NULL
);
GO


/*
  usp_ImportarSedes
  Upsert de sedes por nombre del estadio. El país se identifica por su código
  FIFA. Una sede nueva se registra con sus 4 espacios publicitarios, como en
  usp_RegistrarSede; en una existente, un dato que no viene no se modifica.
  Valida, para todo el conjunto: nombre del estadio obligatorio, de hasta 100
  caracteres y sin repetir; ciudad de hasta 80; países existentes; capacidad
  mayor que cero y no menor que la asistencia de un partido ya jugado en la
  sede; huso horario existente en sys.time_zone_info; latitud y longitud
  juntas y dentro de rango; para las sedes nuevas, ciudad, país, capacidad,
  huso y las 4 tarifas obligatorios, y tarifas no negativas. Con eso cubre las
  reglas de usp_SEDE_Alta, usp_SEDE_Modificacion y usp_RegistrarSede. Si
  cambia el huso de una sede, recalcula la hora local de sus partidos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSedes
    @sedes         Torneo.TT_SEDE READONLY,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @incompletas  INT;

    -- Copia normalizada, la que se valida y se carga, con lo que le pasa a cada sede.
    DECLARE @lista TABLE (
        nombre_estadio  VARCHAR(200),
        ciudad          VARCHAR(200),
        codigo_fifa     VARCHAR(10),
        id_pais         SMALLINT,
        capacidad       INT,
        huso_horario    VARCHAR(100),
        latitud         DECIMAL(9,6),
        longitud        DECIMAL(9,6),
        tarifa_1        DECIMAL(9,2),
        tarifa_2        DECIMAL(9,2),
        tarifa_3        DECIMAL(9,2),
        tarifa_4        DECIMAL(9,2),
        id_sede         INT,
        cambia_huso     BIT,
        accion          VARCHAR(15)
    );

    INSERT INTO @lista (nombre_estadio, ciudad, codigo_fifa, capacidad, huso_horario, latitud, longitud,
                        tarifa_1, tarifa_2, tarifa_3, tarifa_4)
    SELECT NULLIF(TRIM(nombre_estadio), ''), NULLIF(TRIM(ciudad), ''), UPPER(NULLIF(TRIM(codigo_fifa_pais), '')),
           capacidad, NULLIF(TRIM(huso_horario), ''), latitud, longitud,
           tarifa_espacio_1, tarifa_espacio_2, tarifa_espacio_3, tarifa_espacio_4
    FROM @sedes;

    UPDATE l SET id_pais = p.id_pais
    FROM @lista AS l INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = l.codigo_fifa;

    UPDATE l SET id_sede = s.id_sede
    FROM @lista AS l INNER JOIN Torneo.SEDE AS s ON s.nombre_estadio = l.nombre_estadio;

    -- El huso se guarda con el nombre exacto de sys.time_zone_info.
    UPDATE l SET huso_horario = z.name COLLATE DATABASE_DEFAULT
    FROM @lista AS l INNER JOIN sys.time_zone_info AS z ON z.name COLLATE DATABASE_DEFAULT = l.huso_horario;

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE nombre_estadio IS NULL
       OR (id_sede IS NULL AND (ciudad IS NULL OR codigo_fifa IS NULL OR capacidad IS NULL OR huso_horario IS NULL
                                OR tarifa_1 IS NULL OR tarifa_2 IS NULL OR tarifa_3 IS NULL OR tarifa_4 IS NULL));
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10))
                      + N' fila(s) sin estadio o, si la sede es nueva, sin ciudad, país, capacidad, huso o las 4 tarifas.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Estadios de más de 100 caracteres o con ciudad de más de 80: '
               + STRING_AGG(CAST(LEFT(nombre_estadio, 40) AS NVARCHAR(40)), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) nombre_estadio FROM @lista
              WHERE LEN(nombre_estadio) > 100 OR LEN(ciudad) > 80) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Códigos FIFA que no tiene ningún país: ' + STRING_AGG(codigo_fifa, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) codigo_fifa FROM @lista
              WHERE codigo_fifa IS NOT NULL AND id_pais IS NULL) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Husos horarios que no existen en sys.time_zone_info: ' + STRING_AGG(huso_horario, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) l.huso_horario FROM @lista AS l
              WHERE l.huso_horario IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info AS z
                                WHERE z.name COLLATE DATABASE_DEFAULT = l.huso_horario)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Sedes con capacidad que no es mayor que cero: ' + STRING_AGG(nombre_estadio, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) nombre_estadio FROM @lista WHERE capacidad <= 0) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Sedes con capacidad menor que la asistencia de un partido ya jugado: '
               + STRING_AGG(nombre_estadio, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) l.nombre_estadio FROM @lista AS l
              WHERE l.capacidad > 0
                AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
                            WHERE p.id_sede = l.id_sede AND p.asistencia > l.capacidad)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Sedes con latitud sin longitud (o al revés) o fuera de rango: ' + STRING_AGG(nombre_estadio, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) nombre_estadio FROM @lista
              WHERE (latitud IS NULL AND longitud IS NOT NULL) OR (latitud IS NOT NULL AND longitud IS NULL)
                 OR latitud NOT BETWEEN -90 AND 90 OR longitud NOT BETWEEN -180 AND 180) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Sedes con tarifas negativas: ' + STRING_AGG(nombre_estadio, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) nombre_estadio FROM @lista
              WHERE tarifa_1 < 0 OR tarifa_2 < 0 OR tarifa_3 < 0 OR tarifa_4 < 0) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Sedes repetidas: ' + STRING_AGG(nombre_estadio, ', ') + N'.'
        FROM (SELECT TOP (10) nombre_estadio FROM @lista
              WHERE nombre_estadio IS NOT NULL
              GROUP BY nombre_estadio HAVING COUNT(*) > 1) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSedes: no se importó ninguna sede.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Lo que le pasa a cada sede se calcula antes de cargar.
    UPDATE l
    SET accion = CASE WHEN l.id_sede IS NULL THEN 'INSERTADO'
                      WHEN l.ciudad <> s.ciudad OR l.id_pais <> s.id_pais OR l.capacidad <> s.capacidad
                        OR l.huso_horario <> s.huso_horario
                        OR l.latitud <> ISNULL(s.latitud, 999) OR l.longitud <> ISNULL(s.longitud, 999)
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END,
        cambia_huso = IIF(l.huso_horario <> s.huso_horario, 1, 0)
    FROM @lista AS l
    LEFT JOIN Torneo.SEDE AS s ON s.id_sede = l.id_sede;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE s
        SET ciudad       = ISNULL(l.ciudad, s.ciudad),
            id_pais      = ISNULL(l.id_pais, s.id_pais),
            capacidad    = ISNULL(l.capacidad, s.capacidad),
            huso_horario = ISNULL(l.huso_horario, s.huso_horario),
            latitud      = ISNULL(l.latitud, s.latitud),
            longitud     = ISNULL(l.longitud, s.longitud)
        FROM Torneo.SEDE AS s
        INNER JOIN @lista AS l ON l.id_sede = s.id_sede
        WHERE l.accion = 'ACTUALIZADO';

        -- La hora local de los partidos sale de la UTC y el huso de la sede.
        UPDATE p
        SET fecha_hora_local = CONVERT(DATETIME2(0), (p.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE s.huso_horario)
        FROM Torneo.PARTIDO AS p
        INNER JOIN Torneo.SEDE AS s ON s.id_sede = p.id_sede
        INNER JOIN @lista AS l ON l.id_sede = s.id_sede
        WHERE l.cambia_huso = 1;

        INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario, latitud, longitud)
        SELECT nombre_estadio, ciudad, id_pais, capacidad, huso_horario, latitud, longitud
        FROM @lista
        WHERE accion = 'INSERTADO';

        INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, descripcion, tarifa_usd)
        SELECT s.id_sede, e.numero, CONCAT('Panel perimetral ', e.numero), e.tarifa
        FROM @lista AS l
        INNER JOIN Torneo.SEDE AS s ON s.nombre_estadio = l.nombre_estadio
        CROSS APPLY (VALUES (1, l.tarifa_1), (2, l.tarifa_2), (3, l.tarifa_3), (4, l.tarifa_4)) AS e (numero, tarifa)
        WHERE l.accion = 'INSERTADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0)
    FROM @lista;
END;
GO


/*
  usp_ImportarSelecciones
  Upsert de selecciones por el código FIFA de su país. Una selección nueva se
  registra con su lista de convocados (todavía vacía), presentada en
  @fecha_presentacion; el director técnico no viene en los archivos y se
  carga aparte. nombre_alternativo es el nombre con el que la fuente escribe
  la selección (en inglés, por ejemplo): si es distinto del nombre del país,
  se guarda en NOMBRE_ALTERNATIVO para reconocerla en otros archivos.
  Valida, para todo el conjunto: código FIFA obligatorio, existente y sin
  repetir; confederación válida (obligatoria si la selección es nueva); grupo
  de la A a la L; que ningún grupo quede con más de SELECCIONES_POR_GRUPO
  selecciones; que no cambie el grupo de una selección con partidos de la
  fase de grupos; nombres alternativos de hasta 120 caracteres y que no sean
  de otra selección; fecha de presentación obligatoria si hay que crear
  alguna lista, y no futura. Con eso cubre las reglas de usp_SELECCION_Alta,
  usp_SELECCION_Modificacion, usp_LISTA_CONVOCADOS_Alta y
  usp_NOMBRE_ALTERNATIVO_Alta.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSelecciones
    @selecciones         Torneo.TT_SELECCION READONLY,
    @fecha_presentacion  DATE = NULL,
    @insertados          INT  = NULL OUTPUT,
    @actualizados        INT  = NULL OUTPUT,
    @sin_cambios         INT  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @cupo_grupo   TINYINT        = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                            WHERE codigo = 'SELECCIONES_POR_GRUPO');
    DECLARE @incompletas  INT;

    DECLARE @lista TABLE (
        codigo_fifa         VARCHAR(10),
        id_pais             SMALLINT,
        nombre_pais         VARCHAR(60),
        confederacion       VARCHAR(20),
        grupo               VARCHAR(5),
        nombre_alternativo  NVARCHAR(200),
        id_seleccion        INT,
        tiene_lista         BIT,
        accion              VARCHAR(15)
    );

    INSERT INTO @lista (codigo_fifa, confederacion, grupo, nombre_alternativo)
    SELECT UPPER(NULLIF(TRIM(codigo_fifa), '')), UPPER(NULLIF(TRIM(confederacion), '')),
           UPPER(NULLIF(TRIM(grupo), '')), NULLIF(TRIM(nombre_alternativo), N'')
    FROM @selecciones;

    UPDATE l
    SET id_pais = p.id_pais, nombre_pais = p.nombre, id_seleccion = s.id_seleccion,
        tiene_lista = IIF(EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS AS lc
                                  WHERE lc.id_seleccion = s.id_seleccion), 1, 0)
    FROM @lista AS l
    INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = l.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = p.id_pais;

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE codigo_fifa IS NULL OR (id_seleccion IS NULL AND confederacion IS NULL);
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10))
                      + N' fila(s) sin código FIFA o, si la selección es nueva, sin confederación.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Códigos FIFA que no tiene ningún país: ' + STRING_AGG(codigo_fifa, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) codigo_fifa FROM @lista
              WHERE codigo_fifa IS NOT NULL AND id_pais IS NULL) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Confederaciones no válidas (AFC, CAF, CONCACAF, CONMEBOL, OFC o UEFA): '
               + STRING_AGG(confederacion, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) confederacion FROM @lista
              WHERE confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Grupos que no son una letra de la A a la L: ' + STRING_AGG(grupo, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) grupo FROM @lista
              WHERE grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]') AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Selecciones repetidas: ' + STRING_AGG(codigo_fifa, ', ') + N'.'
        FROM (SELECT TOP (10) codigo_fifa FROM @lista
              WHERE codigo_fifa IS NOT NULL GROUP BY codigo_fifa HAVING COUNT(*) > 1) AS x), N'');

    -- Grupos como quedarían: las selecciones del conjunto con su grupo nuevo y las demás con el suyo.
    SET @errores += ISNULL((
        SELECT @nl + N'- Grupos que quedarían con más de ' + CAST(@cupo_grupo AS NVARCHAR(3))
               + N' selecciones (SELECCIONES_POR_GRUPO): ' + STRING_AGG(grupo, ', ') + N'.'
        FROM (SELECT TOP (10) g.grupo
              FROM (SELECT ISNULL(l.grupo, s.grupo) AS grupo
                    FROM @lista AS l
                    LEFT JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                    WHERE l.id_pais IS NOT NULL
                    UNION ALL
                    SELECT s.grupo
                    FROM Torneo.SELECCION AS s
                    WHERE NOT EXISTS (SELECT 1 FROM @lista AS l WHERE l.id_seleccion = s.id_seleccion)) AS g
              WHERE g.grupo IS NOT NULL
              GROUP BY g.grupo HAVING COUNT(*) > @cupo_grupo) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Selecciones con partidos de la fase de grupos a las que no se les puede cambiar el grupo: '
               + STRING_AGG(codigo_fifa, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) l.codigo_fifa
              FROM @lista AS l
              INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
              WHERE l.grupo <> ISNULL(s.grupo, '')
                AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
                            WHERE p.fase = 'GRUPOS'
                              AND s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante))) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Nombres alternativos de más de 120 caracteres, de otra selección o repetidos para '
               + N'selecciones distintas: ' + STRING_AGG(CAST(LEFT(nombre_alternativo, 40) AS NVARCHAR(40)), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) l.nombre_alternativo
              FROM @lista AS l
              WHERE LEN(l.nombre_alternativo) > 120
                 OR EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                            WHERE na.id_jugador IS NULL AND na.nombre = l.nombre_alternativo
                              AND na.id_seleccion <> ISNULL(l.id_seleccion, 0))
                 OR EXISTS (SELECT 1 FROM @lista AS o
                            WHERE o.nombre_alternativo = l.nombre_alternativo
                              AND o.codigo_fifa <> l.codigo_fifa)) AS x), N'');

    IF EXISTS (SELECT 1 FROM @lista WHERE id_pais IS NOT NULL AND ISNULL(tiene_lista, 0) = 0)
    BEGIN
        IF @fecha_presentacion IS NULL
            SET @errores += @nl + N'- Hay selecciones sin lista de convocados: la fecha de presentación es obligatoria.';
        ELSE IF @fecha_presentacion > CONVERT(DATE, GETDATE())
            SET @errores += @nl + N'- La fecha de presentación no puede ser futura.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSelecciones: no se importó ninguna selección.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE l
    SET accion = CASE WHEN l.id_seleccion IS NULL THEN 'INSERTADO'
                      WHEN l.confederacion <> s.confederacion OR l.grupo <> ISNULL(s.grupo, '') OR l.tiene_lista = 0
                        OR (l.nombre_alternativo <> l.nombre_pais
                            AND NOT EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                                            WHERE na.id_jugador IS NULL AND na.nombre = l.nombre_alternativo))
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM @lista AS l
    LEFT JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE s
        SET confederacion = ISNULL(l.confederacion, s.confederacion),
            grupo         = ISNULL(l.grupo, s.grupo)
        FROM Torneo.SELECCION AS s
        INNER JOIN @lista AS l ON l.id_seleccion = s.id_seleccion
        WHERE l.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo)
        SELECT id_pais, confederacion, grupo
        FROM @lista
        WHERE accion = 'INSERTADO';

        UPDATE l SET id_seleccion = s.id_seleccion
        FROM @lista AS l INNER JOIN Torneo.SELECCION AS s ON s.id_pais = l.id_pais
        WHERE l.accion = 'INSERTADO';

        INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion)
        SELECT id_seleccion, @fecha_presentacion
        FROM @lista
        WHERE ISNULL(tiene_lista, 0) = 0;

        INSERT INTO Torneo.NOMBRE_ALTERNATIVO (id_seleccion, nombre)
        SELECT l.id_seleccion, l.nombre_alternativo
        FROM @lista AS l
        WHERE l.nombre_alternativo <> l.nombre_pais
          AND NOT EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                          WHERE na.id_jugador IS NULL AND na.nombre = l.nombre_alternativo);

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0)
    FROM @lista;
END;
GO


/*
  usp_ImportarJugadores
  Upsert de jugadores de las listas de convocados, por selección (código FIFA
  de su país), apellido y nombre, como usp_ImportarJugador. Acepta las
  posiciones en español o abreviadas (GK, DF, MF, FW). Un jugador nuevo se da
  de alta en la fecha de presentación de la lista, con motivo "Importación";
  en uno existente, la fecha de nacimiento y el club que no vienen no se
  borran. Los jugadores de la lista que no vienen en el conjunto quedan como
  están.
  Valida, para todo el conjunto: filas completas (selección, nombre,
  apellido, posición y dorsal); selecciones con lista de convocados; nombre y
  apellido de hasta 60 caracteres y club de hasta 100; posiciones válidas;
  dorsales entre 1 y 99; fechas de nacimiento no futuras; jugadores sin
  repetir. Y sobre cada lista como quedaría: dorsales sin repetir entre los
  activos y no más de MAX_CONVOCADOS activos; si la lista está vacía (es la
  lista inicial), entre MIN_CONVOCADOS y MAX_CONVOCADOS jugadores con al
  menos MIN_ARQUEROS_CONVOCADOS arqueros. Con eso cubre las reglas de
  usp_JUGADOR_Alta, usp_JUGADOR_Modificacion y usp_RegistrarConvocatoria.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarJugadores
    @jugadores     Torneo.TT_JUGADOR READONLY,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @nl              NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia     BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @min_convocados  TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados  TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros    TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');
    DECLARE @incompletas     INT;

    DECLARE @lista TABLE (
        codigo_fifa       VARCHAR(10),
        id_lista          INT,
        nombre            NVARCHAR(120),
        apellido          NVARCHAR(120),
        posicion          VARCHAR(30),
        dorsal            TINYINT,
        fecha_nacimiento  DATE,
        club_origen       NVARCHAR(200),
        id_jugador        INT,
        activo            BIT,
        accion            VARCHAR(15)
    );

    -- Listas que toca el conjunto, con su estado antes de la importación.
    DECLARE @listas TABLE (
        id_lista            INT PRIMARY KEY,
        codigo_fifa         VARCHAR(10),
        fecha_presentacion  DATE,
        vacia               BIT
    );

    INSERT INTO @lista (codigo_fifa, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen)
    SELECT UPPER(NULLIF(TRIM(codigo_fifa_seleccion), '')), NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''),
           CASE UPPER(NULLIF(TRIM(posicion), ''))
                WHEN 'GK' THEN 'ARQUERO'       WHEN 'GOALKEEPER' THEN 'ARQUERO'
                WHEN 'DF' THEN 'DEFENSOR'      WHEN 'DEFENDER'   THEN 'DEFENSOR'
                WHEN 'MF' THEN 'MEDIOCAMPISTA' WHEN 'MIDFIELDER' THEN 'MEDIOCAMPISTA'
                WHEN 'FW' THEN 'DELANTERO'     WHEN 'FORWARD'    THEN 'DELANTERO'
                ELSE UPPER(NULLIF(TRIM(posicion), ''))
           END,
           dorsal, fecha_nacimiento, NULLIF(TRIM(club_origen), N'')
    FROM @jugadores;

    INSERT INTO @listas (id_lista, codigo_fifa, fecha_presentacion, vacia)
    SELECT lc.id_lista, pa.codigo_fifa, lc.fecha_presentacion,
           IIF(EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j WHERE j.id_lista = lc.id_lista), 0, 1)
    FROM Torneo.LISTA_CONVOCADOS AS lc
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa IN (SELECT codigo_fifa FROM @lista);

    UPDATE l SET id_lista = ls.id_lista
    FROM @lista AS l INNER JOIN @listas AS ls ON ls.codigo_fifa = l.codigo_fifa;

    UPDATE l SET id_jugador = j.id_jugador, activo = IIF(j.fecha_baja IS NULL, 1, 0)
    FROM @lista AS l
    INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista AND j.apellido = l.apellido AND j.nombre = l.nombre;

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE codigo_fifa IS NULL OR nombre IS NULL OR apellido IS NULL OR posicion IS NULL OR dorsal IS NULL;
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10))
                      + N' fila(s) sin selección, nombre, apellido, posición o dorsal.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Selecciones sin lista de convocados (o códigos FIFA que no existen): '
               + STRING_AGG(codigo_fifa, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) codigo_fifa FROM @lista
              WHERE codigo_fifa IS NOT NULL AND id_lista IS NULL) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Nombres o apellidos de más de 60 caracteres, o clubes de más de 100: '
               + STRING_AGG(CAST(LEFT(CONCAT(nombre, N' ', apellido), 40) AS NVARCHAR(40)), ', ') + N'.'
        FROM (SELECT TOP (10) nombre, apellido FROM @lista
              WHERE LEN(nombre) > 60 OR LEN(apellido) > 60 OR LEN(club_origen) > 100) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Posiciones no válidas (ARQUERO, DEFENSOR, MEDIOCAMPISTA o DELANTERO): '
               + STRING_AGG(posicion, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) posicion FROM @lista
              WHERE posicion NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Dorsales fuera de rango (1 a 99): '
               + STRING_AGG(CONCAT(codigo_fifa, N' ', dorsal), ', ') + N'.'
        FROM (SELECT TOP (10) codigo_fifa, dorsal FROM @lista WHERE dorsal NOT BETWEEN 1 AND 99) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Fechas de nacimiento futuras: '
               + STRING_AGG(CAST(LEFT(CONCAT(nombre, N' ', apellido), 40) AS NVARCHAR(40)), ', ') + N'.'
        FROM (SELECT TOP (10) nombre, apellido FROM @lista WHERE fecha_nacimiento > CONVERT(DATE, GETDATE())) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Jugadores repetidos: '
               + STRING_AGG(CAST(LEFT(CONCAT(codigo_fifa, N' ', nombre, N' ', apellido), 50) AS NVARCHAR(50)), ', ') + N'.'
        FROM (SELECT TOP (10) codigo_fifa, nombre, apellido FROM @lista
              WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
              GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS x), N'');

    -- Cada lista como quedaría: los activos que no vienen en el conjunto más los que vienen.
    WITH plantel AS (
        SELECT ls.id_lista, ls.codigo_fifa, j.dorsal, j.posicion_habitual AS posicion
        FROM Torneo.JUGADOR AS j
        INNER JOIN @listas AS ls ON ls.id_lista = j.id_lista
        WHERE j.fecha_baja IS NULL
          AND NOT EXISTS (SELECT 1 FROM @lista AS l WHERE l.id_jugador = j.id_jugador)
        UNION ALL
        SELECT id_lista, codigo_fifa, dorsal, posicion
        FROM @lista
        WHERE id_lista IS NOT NULL AND ISNULL(activo, 1) = 1
    ),
    dorsales AS (
        SELECT TOP (10) codigo_fifa, dorsal
        FROM plantel WHERE dorsal IS NOT NULL
        GROUP BY codigo_fifa, dorsal HAVING COUNT(*) > 1
    )
    SELECT @errores += ISNULL(@nl + N'- Dorsales repetidos entre los convocados activos: '
                              + STRING_AGG(CONCAT(codigo_fifa, N' ', dorsal), ', ') + N'.', N'')
    FROM dorsales;

    WITH plantel AS (
        SELECT ls.id_lista, ls.codigo_fifa, j.posicion_habitual AS posicion
        FROM Torneo.JUGADOR AS j
        INNER JOIN @listas AS ls ON ls.id_lista = j.id_lista
        WHERE j.fecha_baja IS NULL
          AND NOT EXISTS (SELECT 1 FROM @lista AS l WHERE l.id_jugador = j.id_jugador)
        UNION ALL
        SELECT id_lista, codigo_fifa, posicion
        FROM @lista
        WHERE id_lista IS NOT NULL AND ISNULL(activo, 1) = 1
    ),
    listas AS (
        SELECT p.codigo_fifa, ls.vacia, COUNT(*) AS jugadores, SUM(IIF(p.posicion = 'ARQUERO', 1, 0)) AS arqueros
        FROM plantel AS p
        INNER JOIN @listas AS ls ON ls.id_lista = p.id_lista
        GROUP BY p.codigo_fifa, ls.vacia
    )
    SELECT @errores += ISNULL((
               SELECT @nl + N'- Listas que quedarían con más de ' + CAST(@max_convocados AS NVARCHAR(3))
                      + N' convocados activos (MAX_CONVOCADOS): ' + STRING_AGG(CONCAT(codigo_fifa, N' (', jugadores, N')'), ', ') + N'.'
               FROM listas WHERE jugadores > @max_convocados), N'')
                     + ISNULL((
               SELECT @nl + N'- Listas iniciales que no tienen entre ' + CAST(@min_convocados AS NVARCHAR(3)) + N' y '
                      + CAST(@max_convocados AS NVARCHAR(3)) + N' jugadores con al menos '
                      + CAST(@min_arqueros AS NVARCHAR(3)) + N' arqueros: '
                      + STRING_AGG(CONCAT(codigo_fifa, N' (', jugadores, N' jugadores, ', arqueros, N' arqueros)'), ', ') + N'.'
               FROM listas
               WHERE vacia = 1 AND (jugadores NOT BETWEEN @min_convocados AND @max_convocados OR arqueros < @min_arqueros)), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarJugadores: no se importó ningún jugador.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE l
    SET accion = CASE WHEN l.id_jugador IS NULL THEN 'INSERTADO'
                      WHEN l.posicion <> j.posicion_habitual OR l.dorsal <> j.dorsal
                        OR l.fecha_nacimiento <> ISNULL(j.fecha_nacimiento, '19000101')
                        OR l.club_origen <> ISNULL(j.club_origen, N'')
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM @lista AS l
    LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = l.id_jugador;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE j
        SET posicion_habitual = l.posicion,
            dorsal            = l.dorsal,
            fecha_nacimiento  = ISNULL(l.fecha_nacimiento, j.fecha_nacimiento),
            club_origen       = ISNULL(l.club_origen, j.club_origen)
        FROM Torneo.JUGADOR AS j
        INNER JOIN @lista AS l ON l.id_jugador = j.id_jugador
        WHERE l.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.JUGADOR
            (id_lista, nombre, apellido, fecha_nacimiento, club_origen, posicion_habitual, dorsal,
             fecha_alta, motivo_alta)
        SELECT l.id_lista, l.nombre, l.apellido, l.fecha_nacimiento, l.club_origen, l.posicion, l.dorsal,
               ls.fecha_presentacion, 'Importación'
        FROM @lista AS l
        INNER JOIN @listas AS ls ON ls.id_lista = l.id_lista
        WHERE l.accion = 'INSERTADO'
        ORDER BY l.id_lista, l.dorsal;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0)
    FROM @lista;
END;
GO


/*
  usp_ImportarPartidos
  Upsert de partidos del fixture por número, como usp_ImportarPartido: la
  sede se identifica por el nombre del estadio, las selecciones por el código
  FIFA de su país y la fase admite los nombres en inglés (Group A o First
  Stage, Group A, Round of 32, Round of 16, Quarter-final, Semi-final, Third
  place o Bronze final, Final). La hora local se calcula con la UTC y el huso
  de la sede. Si trae el resultado, el partido queda FINALIZADO (carga
  histórica). En un partido ya empezado o terminado solo se actualizan el
  resultado y la asistencia.
  Valida, para todo el conjunto: número mayor que cero y sin repetir; para
  los partidos nuevos, estadio, fase y fecha obligatorios; sedes existentes;
  fases válidas; selecciones existentes y distintas; en la fase de grupos, las
  dos selecciones y del mismo grupo; resultado completo, con las dos
  selecciones, penales solo en eliminación directa con empate y sin empate en
  los penales, y un empate de eliminación directa con penales; si cambia el
  resultado, que sea igual al de los goles ya cargados en GOL (uno que no
  cambia no se valida: los goles pueden estar cargados a medias);
  asistencia no negativa ni mayor
  que la capacidad. Y sobre el fixture como quedaría: que ninguna selección
  juegue dos partidos a menos de 24 horas y que ninguna sede tenga dos
  partidos el mismo día. Con eso cubre las reglas de usp_PARTIDO_Alta y
  usp_PARTIDO_Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarPartidos
    @partidos      Torneo.TT_PARTIDO READONLY,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @incompletas  INT;

    DECLARE @lista TABLE (
        numero_partido     TINYINT,
        nombre_estadio     VARCHAR(200),
        fase               VARCHAR(30),
        fecha_hora_utc     DATETIME2(0),
        fecha_hora_local   DATETIME2(0),
        codigo_local       VARCHAR(10),
        codigo_visitante   VARCHAR(10),
        goles_local        TINYINT,
        goles_visitante    TINYINT,
        penales_local      TINYINT,
        penales_visitante  TINYINT,
        asistencia         INT,
        id_sede            INT,
        capacidad          INT,
        id_local           INT,
        id_visitante       INT,
        id_partido         INT,
        estado_actual      VARCHAR(12),
        programable        BIT,
        sede_inexistente   BIT,
        accion             VARCHAR(15)
    );

    INSERT INTO @lista (numero_partido, nombre_estadio, fase, fecha_hora_utc, codigo_local, codigo_visitante,
                        goles_local, goles_visitante, penales_local, penales_visitante, asistencia)
    SELECT numero_partido, NULLIF(TRIM(nombre_estadio), ''),
           CASE WHEN f.fase LIKE '%GROUP%' OR f.fase LIKE 'GRUPO%'                           THEN 'GRUPOS'
                WHEN f.fase IN ('ROUND OF 32', 'DIECISEISAVOS DE FINAL')                      THEN 'DIECISEISAVOS'
                WHEN f.fase IN ('ROUND OF 16', 'OCTAVOS DE FINAL')                            THEN 'OCTAVOS'
                WHEN f.fase LIKE 'QUARTER%' OR f.fase = 'CUARTOS DE FINAL'                    THEN 'CUARTOS'
                WHEN f.fase LIKE 'SEMI%'                                                      THEN 'SEMIFINAL'
                WHEN f.fase LIKE '%THIRD%' OR f.fase LIKE 'BRONZE%' OR f.fase LIKE 'TERCER%'  THEN 'TERCER_PUESTO'
                ELSE f.fase
           END,
           fecha_hora_utc, UPPER(NULLIF(TRIM(codigo_fifa_local), '')), UPPER(NULLIF(TRIM(codigo_fifa_visitante), '')),
           goles_local, goles_visitante, penales_local, penales_visitante, asistencia
    FROM @partidos
    CROSS APPLY (SELECT UPPER(NULLIF(TRIM(fase), '')) AS fase) AS f;

    UPDATE l SET id_sede = s.id_sede, capacidad = s.capacidad,
                 fecha_hora_local = CONVERT(DATETIME2(0), (l.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE s.huso_horario)
    FROM @lista AS l INNER JOIN Torneo.SEDE AS s ON s.nombre_estadio = l.nombre_estadio;

    UPDATE @lista SET sede_inexistente = IIF(nombre_estadio IS NOT NULL AND id_sede IS NULL, 1, 0);

    UPDATE l SET id_local = s.id_seleccion
    FROM @lista AS l
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = l.codigo_local
    INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais;

    UPDATE l SET id_visitante = s.id_seleccion
    FROM @lista AS l
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = l.codigo_visitante
    INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais;

    -- Partidos existentes: la programación solo se cambia antes de que empiecen.
    UPDATE l
    SET id_partido = p.id_partido, estado_actual = p.estado,
        programable = IIF(p.estado IN ('PROGRAMADO', 'SUSPENDIDO'), 1, 0)
    FROM @lista AS l INNER JOIN Torneo.PARTIDO AS p ON p.numero_partido = l.numero_partido;

    UPDATE @lista SET programable = 1 WHERE id_partido IS NULL;

    -- Lo que no se puede cambiar queda como está, para validar el partido completo.
    UPDATE l
    SET id_sede          = IIF(l.programable = 1, ISNULL(l.id_sede, p.id_sede), p.id_sede),
        capacidad        = s.capacidad,
        fase             = IIF(l.programable = 1, ISNULL(l.fase, p.fase), p.fase),
        fecha_hora_utc   = IIF(l.programable = 1, ISNULL(l.fecha_hora_utc, p.fecha_hora_utc), p.fecha_hora_utc),
        fecha_hora_local = IIF(l.programable = 1 AND l.fecha_hora_utc IS NOT NULL, l.fecha_hora_local, p.fecha_hora_local),
        id_local         = IIF(l.programable = 1, ISNULL(l.id_local, p.id_seleccion_local), p.id_seleccion_local),
        id_visitante     = IIF(l.programable = 1, ISNULL(l.id_visitante, p.id_seleccion_visitante), p.id_seleccion_visitante)
    FROM @lista AS l
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = l.id_partido
    INNER JOIN Torneo.SEDE AS s ON s.id_sede = IIF(l.programable = 1, ISNULL(l.id_sede, p.id_sede), p.id_sede);

    SELECT @incompletas = COUNT(*)
    FROM @lista
    WHERE numero_partido IS NULL
       OR (id_partido IS NULL AND (nombre_estadio IS NULL OR fase IS NULL OR fecha_hora_utc IS NULL));
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10))
                      + N' fila(s) sin número o, si el partido es nuevo, sin estadio, fase o fecha.';

    IF EXISTS (SELECT 1 FROM @lista WHERE numero_partido = 0)
        SET @errores += @nl + N'- El número de partido debe ser mayor que cero.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Partidos repetidos: ' + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT TOP (10) numero_partido FROM @lista
              WHERE numero_partido IS NOT NULL GROUP BY numero_partido HAVING COUNT(*) > 1) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Estadios que no son una sede registrada: ' + STRING_AGG(nombre_estadio, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) nombre_estadio FROM @lista WHERE sede_inexistente = 1) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Fases no válidas: ' + STRING_AGG(fase, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) fase FROM @lista
              WHERE fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS',
                                 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Códigos FIFA sin selección registrada: ' + STRING_AGG(codigo, ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) c.codigo
              FROM @lista AS l
              CROSS APPLY (VALUES (l.codigo_local, l.id_local), (l.codigo_visitante, l.id_visitante)) AS c (codigo, id)
              WHERE c.codigo IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS pa
                                INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
                                WHERE pa.codigo_fifa = c.codigo)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Partidos con la misma selección como local y visitante, o de la fase de grupos sin las '
               + N'dos selecciones o con selecciones de grupos distintos: '
               + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT TOP (10) l.numero_partido
              FROM @lista AS l
              LEFT JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = l.id_local
              LEFT JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = l.id_visitante
              WHERE l.id_local = l.id_visitante
                 OR (l.fase = 'GRUPOS' AND (l.id_local IS NULL OR l.id_visitante IS NULL
                                            OR ISNULL(sl.grupo, '') <> ISNULL(sv.grupo, '-')))) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Partidos con un resultado incompleto o que no es posible (goles de las dos selecciones, '
               + N'con las dos selecciones; penales solo en eliminación directa empatada y sin empate en los '
               + N'penales; un empate de eliminación directa se define por penales): '
               + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT TOP (10) numero_partido FROM @lista
              WHERE (goles_local IS NULL AND goles_visitante IS NOT NULL)
                 OR (goles_local IS NOT NULL AND goles_visitante IS NULL)
                 OR (penales_local IS NULL AND penales_visitante IS NOT NULL)
                 OR (penales_local IS NOT NULL AND penales_visitante IS NULL)
                 OR (goles_local IS NOT NULL AND (id_local IS NULL OR id_visitante IS NULL))
                 OR (penales_local IS NOT NULL AND (fase = 'GRUPOS' OR goles_local IS NULL
                                                    OR goles_local <> goles_visitante
                                                    OR penales_local = penales_visitante))
                 OR (fase <> 'GRUPOS' AND goles_local = goles_visitante AND penales_local IS NULL)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Partidos cuyo resultado no coincide con los goles ya cargados: '
               + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT TOP (10) l.numero_partido
              FROM @lista AS l
              INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = l.id_partido
              CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(l.id_partido) AS m
              WHERE l.goles_local IS NOT NULL AND m.goles_registrados > m.penales_registrados
                AND (l.goles_local <> ISNULL(p.goles_local, 255) OR l.goles_visitante <> ISNULL(p.goles_visitante, 255))
                AND (l.goles_local <> m.goles_local OR l.goles_visitante <> m.goles_visitante)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Partidos con asistencia negativa o mayor que la capacidad de la sede: '
               + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT TOP (10) numero_partido FROM @lista
              WHERE asistencia < 0 OR asistencia > capacidad) AS x), N'');

    -- El fixture como quedaría: los partidos del conjunto y los demás ya cargados.
    WITH fixture AS (
        SELECT numero_partido, id_sede, fecha_hora_utc, fecha_hora_local, id_local, id_visitante
        FROM @lista
        WHERE numero_partido IS NOT NULL
        UNION ALL
        SELECT p.numero_partido, p.id_sede, p.fecha_hora_utc, p.fecha_hora_local,
               p.id_seleccion_local, p.id_seleccion_visitante
        FROM Torneo.PARTIDO AS p
        WHERE NOT EXISTS (SELECT 1 FROM @lista AS l WHERE l.numero_partido = p.numero_partido)
    ),
    jugados AS (
        SELECT f.numero_partido, f.fecha_hora_utc, s.id_seleccion
        FROM fixture AS f
        CROSS APPLY (VALUES (f.id_local), (f.id_visitante)) AS s (id_seleccion)
        WHERE s.id_seleccion IS NOT NULL
    )
    SELECT @errores += ISNULL((
               SELECT @nl + N'- Selecciones con dos partidos a menos de 24 horas (partidos): '
                      + STRING_AGG(CONCAT(x.numero_partido, N' y ', x.otro), ', ') + N'.'
               FROM (SELECT TOP (10) a.numero_partido, b.numero_partido AS otro
                     FROM jugados AS a
                     INNER JOIN jugados AS b ON b.id_seleccion = a.id_seleccion AND b.numero_partido > a.numero_partido
                     WHERE ABS(DATEDIFF(MINUTE, a.fecha_hora_utc, b.fecha_hora_utc)) < 1440) AS x), N'')
                     + ISNULL((
               SELECT @nl + N'- Sedes con dos partidos el mismo día (partidos): '
                      + STRING_AGG(CONCAT(x.numero_partido, N' y ', x.otro), ', ') + N'.'
               FROM (SELECT TOP (10) a.numero_partido, b.numero_partido AS otro
                     FROM fixture AS a
                     INNER JOIN fixture AS b ON b.id_sede = a.id_sede AND b.numero_partido > a.numero_partido
                     WHERE CAST(a.fecha_hora_local AS DATE) = CAST(b.fecha_hora_local AS DATE)) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarPartidos: no se importó ningún partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE l
    SET accion = CASE WHEN l.id_partido IS NULL THEN 'INSERTADO'
                      WHEN l.id_sede <> p.id_sede OR l.fase <> p.fase OR l.fecha_hora_utc <> p.fecha_hora_utc
                        OR ISNULL(l.id_local, 0) <> ISNULL(p.id_seleccion_local, 0)
                        OR ISNULL(l.id_visitante, 0) <> ISNULL(p.id_seleccion_visitante, 0)
                        OR l.goles_local <> ISNULL(p.goles_local, 255) OR l.goles_visitante <> ISNULL(p.goles_visitante, 255)
                        OR l.penales_local <> ISNULL(p.penales_local, 255)
                        OR l.penales_visitante <> ISNULL(p.penales_visitante, 255)
                        OR l.asistencia <> ISNULL(p.asistencia, -1)
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM @lista AS l
    LEFT JOIN Torneo.PARTIDO AS p ON p.id_partido = l.id_partido;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE p
        SET id_sede                = l.id_sede,
            fase                   = l.fase,
            fecha_hora_utc         = l.fecha_hora_utc,
            fecha_hora_local       = l.fecha_hora_local,
            id_seleccion_local     = l.id_local,
            id_seleccion_visitante = l.id_visitante,
            goles_local            = ISNULL(l.goles_local, p.goles_local),
            goles_visitante        = ISNULL(l.goles_visitante, p.goles_visitante),
            penales_local          = IIF(l.goles_local IS NULL, p.penales_local, l.penales_local),
            penales_visitante      = IIF(l.goles_local IS NULL, p.penales_visitante, l.penales_visitante),
            asistencia             = ISNULL(l.asistencia, p.asistencia),
            estado                 = IIF(l.goles_local IS NOT NULL, 'FINALIZADO', p.estado)
        FROM Torneo.PARTIDO AS p
        INNER JOIN @lista AS l ON l.id_partido = p.id_partido
        WHERE l.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.PARTIDO
            (numero_partido, id_sede, id_seleccion_local, id_seleccion_visitante, fase, fecha_hora_local,
             fecha_hora_utc, goles_local, goles_visitante, penales_local, penales_visitante, asistencia, estado)
        SELECT numero_partido, id_sede, id_local, id_visitante, fase, fecha_hora_local,
               fecha_hora_utc, goles_local, goles_visitante, penales_local, penales_visitante, asistencia,
               IIF(goles_local IS NOT NULL, 'FINALIZADO', 'PROGRAMADO')
        FROM @lista
        WHERE accion = 'INSERTADO'
        ORDER BY numero_partido;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0)
    FROM @lista;
END;
GO


/*
  usp_ImportarDesarrolloPartidos
  Carga lo que pasó en partidos ya cargados (por número de partido): las
  formaciones (titulares y suplentes), los cambios, los goles (los del
  período PENALES son los penales convertidos en la definición) y las
  tarjetas. Es una carga histórica: no repite las reglas de los SP que
  registran el partido en vivo (equipo en cancha en ese minuto, ventanas de
  cambio, suspensiones), sino las de las tablas.
  - La formación de cada selección se arma con sus jugadores del conjunto. El
    esquema táctico sale de las posiciones habituales de los titulares
    (defensores, mediocampistas y delanteros, ej. 4-3-3). Una formación ya
    cargada se completa con los jugadores que le falten: no se le quita ni
    se le cambia ninguno.
  - Los cambios, goles y tarjetas que ya están cargados no se repiten (mismo
    partido, jugador, tipo, período y minuto) y los cargados que no vienen no
    se borran.
  Valida, para todo el conjunto: filas completas; partidos y jugadores
  existentes; que cada jugador sea de una de las dos selecciones del partido
  y no se repita en la formación; que cada formación quede con 11
  titulares, todos con posición; en cambios, goles y tarjetas, que los jugadores estén en
  la formación del partido (la cargada o la del conjunto); en los cambios,
  jugadores distintos de la misma selección, que cada uno salga y entre una
  sola vez, minuto entre 1 y 120 y los del entretiempo en el 46, 91 o 106;
  tipos de gol existentes y minuto de acuerdo con el período; tarjetas
  AMARILLA o ROJA (la doble amarilla, solo roja), minuto entre 0 y 120 y
  motivo de hasta 200 caracteres. Devuelve cuántos registros de cada tabla
  se insertaron y cuántos ya estaban.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_ImportarDesarrolloPartidos
    @alineaciones    DesarrolloPartido.TT_ALINEACION_PARTIDO READONLY,
    @cambios         DesarrolloPartido.TT_CAMBIO             READONLY,
    @goles           DesarrolloPartido.TT_GOL                READONLY,
    @amonestaciones  DesarrolloPartido.TT_AMONESTACION       READONLY,
    @insertados      INT = NULL OUTPUT,
    @sin_cambios     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @incompletas  INT;

    -- Jugador de cada fila con el partido y su selección; tipo: A, C (sale), E (entra), G, T.
    DECLARE @participantes TABLE (
        tipo            CHAR(1),
        numero_partido  TINYINT,
        id_partido      INT,
        id_jugador      INT,
        id_seleccion    INT,
        de_un_equipo    BIT
    );

    DECLARE @alin TABLE (
        numero_partido      TINYINT,
        id_partido          INT,
        id_jugador          INT,
        id_seleccion        INT,
        es_titular          BIT,
        posicion_en_cancha  VARCHAR(30),
        posicion_habitual   VARCHAR(15),
        formacion_existe    BIT,
        ya_alineado         BIT
    );

    INSERT INTO @alin (numero_partido, id_jugador, es_titular, posicion_en_cancha)
    SELECT numero_partido, id_jugador, es_titular, UPPER(NULLIF(TRIM(posicion_en_cancha), ''))
    FROM @alineaciones;

    UPDATE a
    SET id_partido = p.id_partido, id_seleccion = lc.id_seleccion, posicion_habitual = j.posicion_habitual,
        formacion_existe = IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION AS f
                                       WHERE f.id_partido = p.id_partido AND f.id_seleccion = lc.id_seleccion), 1, 0),
        ya_alineado      = IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS al
                                       INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                                       WHERE f.id_partido = p.id_partido AND al.id_jugador = a.id_jugador), 1, 0)
    FROM @alin AS a
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = a.numero_partido
    LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista;

    INSERT INTO @participantes (tipo, numero_partido, id_jugador)
    SELECT 'A', numero_partido, id_jugador FROM @alin
    UNION ALL SELECT 'C', numero_partido, id_jugador_sale  FROM @cambios
    UNION ALL SELECT 'E', numero_partido, id_jugador_entra FROM @cambios
    UNION ALL SELECT 'G', numero_partido, id_jugador_autor FROM @goles
    UNION ALL SELECT 'T', numero_partido, id_jugador       FROM @amonestaciones;

    UPDATE x
    SET id_partido = p.id_partido, id_seleccion = lc.id_seleccion,
        de_un_equipo = IIF(lc.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante), 1, 0)
    FROM @participantes AS x
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = x.numero_partido
    LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = x.id_jugador
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista;

    SELECT @incompletas = COUNT(*) FROM @participantes WHERE numero_partido IS NULL OR id_jugador IS NULL;
    SELECT @incompletas += COUNT(*) FROM @alin WHERE es_titular IS NULL;
    SELECT @incompletas += COUNT(*) FROM @cambios WHERE minuto IS NULL OR motivo IS NULL;
    SELECT @incompletas += COUNT(*) FROM @goles WHERE tipo_gol IS NULL OR periodo IS NULL;
    SELECT @incompletas += COUNT(*) FROM @amonestaciones WHERE tipo_tarjeta IS NULL OR minuto IS NULL OR motivo IS NULL;
    IF @incompletas > 0
        SET @errores += @nl + N'- Hay ' + CAST(@incompletas AS NVARCHAR(10)) + N' fila(s) incompletas '
                      + N'(partido, jugadores, titular, minuto, motivo, tipo de gol, período o tipo de tarjeta).';

    SET @errores += ISNULL((
        SELECT @nl + N'- Partidos que no existen: ' + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) numero_partido FROM @participantes
              WHERE numero_partido IS NOT NULL AND id_partido IS NULL) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Jugadores que no existen o que no son de las selecciones del partido (partido-id): '
               + STRING_AGG(CONCAT(numero_partido, N'-', id_jugador), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) numero_partido, id_jugador FROM @participantes
              WHERE id_partido IS NOT NULL AND id_jugador IS NOT NULL AND ISNULL(de_un_equipo, 0) = 0) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Jugadores repetidos en una formación (partido-id): '
               + STRING_AGG(CONCAT(numero_partido, N'-', id_jugador), ', ') + N'.'
        FROM (SELECT TOP (10) numero_partido, id_jugador FROM @alin
              WHERE numero_partido IS NOT NULL AND id_jugador IS NOT NULL
              GROUP BY numero_partido, id_jugador HAVING COUNT(*) > 1) AS x), N'');

    -- Cada formación como quedaría: los titulares ya cargados más los nuevos.
    SET @errores += ISNULL((
        SELECT @nl + N'- Formaciones que no quedarían con 11 titulares con su posición (partido-selección): '
               + STRING_AGG(CONCAT(numero_partido, N'-', id_seleccion), ', ') + N'.'
        FROM (SELECT TOP (10) a.numero_partido, a.id_seleccion
              FROM @alin AS a
              WHERE a.id_partido IS NOT NULL AND a.id_seleccion IS NOT NULL
              GROUP BY a.numero_partido, a.id_partido, a.id_seleccion
              HAVING SUM(IIF(a.es_titular = 1 AND a.ya_alineado = 0, 1, 0))
                     + (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION AS al
                        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                        WHERE f.id_partido = a.id_partido AND f.id_seleccion = a.id_seleccion AND al.es_titular = 1) <> 11
                  OR SUM(IIF(a.es_titular = 1 AND a.ya_alineado = 0 AND a.posicion_en_cancha IS NULL, 1, 0)) > 0) AS x), N'');

    -- Cambios, goles y tarjetas: el jugador tiene que estar en la formación del partido.
    SET @errores += ISNULL((
        SELECT @nl + N'- Jugadores de cambios, goles o tarjetas que no están en la formación del partido (partido-id): '
               + STRING_AGG(CONCAT(numero_partido, N'-', id_jugador), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) x.numero_partido, x.id_jugador
              FROM @participantes AS x
              WHERE x.tipo <> 'A' AND x.de_un_equipo = 1
                AND NOT EXISTS (SELECT 1 FROM @alin AS a
                                WHERE a.id_partido = x.id_partido AND a.id_jugador = x.id_jugador)
                AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS al
                                INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                                WHERE f.id_partido = x.id_partido AND al.id_jugador = x.id_jugador)) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Cambios que no son posibles (partido): ' + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ')
               + N'. Tienen que ser jugadores distintos de la misma selección, minuto entre 1 y 120, adicional '
               + N'entre 0 y 30, motivo TACTICO, LESION o PRECAUCION, y los del entretiempo en el minuto 46, 91 o 106.'
        FROM (SELECT DISTINCT TOP (10) c.numero_partido
              FROM @cambios AS c
              LEFT JOIN @participantes AS s ON s.tipo = 'C' AND s.numero_partido = c.numero_partido
                                           AND s.id_jugador = c.id_jugador_sale
              LEFT JOIN @participantes AS e ON e.tipo = 'E' AND e.numero_partido = c.numero_partido
                                           AND e.id_jugador = c.id_jugador_entra
              WHERE c.id_jugador_sale = c.id_jugador_entra
                 OR s.id_seleccion <> e.id_seleccion
                 OR c.minuto NOT BETWEEN 1 AND 120
                 OR ISNULL(c.minuto_adicional, 0) NOT BETWEEN 0 AND 30
                 OR c.motivo NOT IN ('TACTICO', 'LESION', 'PRECAUCION')
                 OR (c.en_entretiempo = 1 AND (c.minuto NOT IN (46, 91, 106) OR ISNULL(c.minuto_adicional, 0) <> 0))) AS x), N'');

    -- Cada jugador sale y entra una sola vez por partido: los cambios del conjunto
    -- más los ya cargados que no vienen en él.
    WITH cambios AS (
        SELECT numero_partido, id_jugador_sale, id_jugador_entra
        FROM @cambios
        UNION ALL
        SELECT p.numero_partido, ca.id_jugador_sale, ca.id_jugador_entra
        FROM DesarrolloPartido.CAMBIO AS ca
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = ca.id_partido
        WHERE p.numero_partido IN (SELECT numero_partido FROM @cambios)
          AND NOT EXISTS (SELECT 1 FROM @cambios AS c
                          WHERE c.numero_partido = p.numero_partido
                            AND c.id_jugador_sale = ca.id_jugador_sale AND c.id_jugador_entra = ca.id_jugador_entra)
    ),
    repetidos AS (
        SELECT TOP (10) c.numero_partido, v.id_jugador
        FROM cambios AS c
        CROSS APPLY (VALUES ('S', c.id_jugador_sale), ('E', c.id_jugador_entra)) AS v (tipo, id_jugador)
        WHERE v.id_jugador IS NOT NULL
        GROUP BY c.numero_partido, v.id_jugador, v.tipo
        HAVING COUNT(*) > 1
    )
    SELECT @errores += ISNULL(@nl + N'- Jugadores que salen o entran más de una vez en un partido (partido-id): '
                              + STRING_AGG(CONCAT(numero_partido, N'-', id_jugador), ', ') + N'.', N'')
    FROM repetidos;

    SET @errores += ISNULL((
        SELECT @nl + N'- Goles con tipo inexistente o minuto que no corresponde al período (partido): '
               + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ') + N'.'
        FROM (SELECT DISTINCT TOP (10) g.numero_partido
              FROM @goles AS g
              WHERE NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL AS tg WHERE tg.descripcion = g.tipo_gol)
                 OR NOT ((g.periodo = 'PENALES' AND g.minuto IS NULL AND ISNULL(g.minuto_adicional, 0) = 0)
                         OR (g.periodo = 'PRIMER_TIEMPO'  AND g.minuto BETWEEN 1  AND 45  AND ISNULL(g.minuto_adicional, 0) = 0)
                         OR (g.periodo = 'SEGUNDO_TIEMPO' AND g.minuto BETWEEN 46 AND 90  AND ISNULL(g.minuto_adicional, 0) = 0)
                         OR (g.periodo = 'ALARGUE'        AND g.minuto BETWEEN 91 AND 120 AND ISNULL(g.minuto_adicional, 0) = 0)
                         OR (g.periodo = 'ADICIONALES'    AND g.minuto IN (45, 90, 105, 120)
                                                          AND g.minuto_adicional BETWEEN 1 AND 30))) AS x), N'');

    SET @errores += ISNULL((
        SELECT @nl + N'- Tarjetas que no son posibles (partido): ' + STRING_AGG(CAST(numero_partido AS NVARCHAR(3)), ', ')
               + N'. Tienen que ser AMARILLA o ROJA (la doble amarilla, solo ROJA), minuto entre 0 y 120, '
               + N'adicional entre 0 y 30 y motivo de hasta 200 caracteres.'
        FROM (SELECT DISTINCT TOP (10) numero_partido FROM @amonestaciones
              WHERE tipo_tarjeta NOT IN ('AMARILLA', 'ROJA')
                 OR (es_doble_amarilla = 1 AND tipo_tarjeta <> 'ROJA')
                 OR minuto NOT BETWEEN 0 AND 120
                 OR ISNULL(minuto_adicional, 0) NOT BETWEEN 0 AND 30
                 OR NULLIF(TRIM(motivo), '') IS NULL OR LEN(motivo) > 200) AS x), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_ImportarDesarrolloPartidos: no se importó nada.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DECLARE @a_insertar  INT = 0;
    DECLARE @total       INT = (SELECT COUNT(*) FROM @alin) + (SELECT COUNT(*) FROM @cambios)
                             + (SELECT COUNT(*) FROM @goles) + (SELECT COUNT(*) FROM @amonestaciones);

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Formaciones nuevas, con el esquema que sale de las posiciones habituales de los titulares.
        INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
        SELECT id_partido, id_seleccion,
               CONCAT(SUM(IIF(es_titular = 1 AND posicion_habitual = 'DEFENSOR', 1, 0)), '-',
                      SUM(IIF(es_titular = 1 AND posicion_habitual = 'MEDIOCAMPISTA', 1, 0)), '-',
                      SUM(IIF(es_titular = 1 AND posicion_habitual = 'DELANTERO', 1, 0)))
        FROM @alin
        WHERE formacion_existe = 0
        GROUP BY id_partido, id_seleccion;

        INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
        SELECT f.id_formacion, a.id_jugador, a.es_titular, a.posicion_en_cancha
        FROM @alin AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_partido = a.id_partido AND f.id_seleccion = a.id_seleccion
        WHERE a.ya_alineado = 0;
        SET @a_insertar += @@ROWCOUNT;

        INSERT INTO DesarrolloPartido.CAMBIO
            (id_partido, id_jugador_sale, id_jugador_entra, minuto, minuto_adicional, en_entretiempo, motivo)
        SELECT p.id_partido, c.id_jugador_sale, c.id_jugador_entra, c.minuto, ISNULL(c.minuto_adicional, 0),
               ISNULL(c.en_entretiempo, 0), c.motivo
        FROM @cambios AS c
        INNER JOIN Torneo.PARTIDO AS p ON p.numero_partido = c.numero_partido
        WHERE NOT EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO AS ca
                          WHERE ca.id_partido = p.id_partido
                            AND ca.id_jugador_sale = c.id_jugador_sale AND ca.id_jugador_entra = c.id_jugador_entra);
        SET @a_insertar += @@ROWCOUNT;

        INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto, minuto_adicional)
        SELECT p.id_partido, g.id_jugador_autor, tg.id_tipo_gol, g.periodo, g.minuto, ISNULL(g.minuto_adicional, 0)
        FROM @goles AS g
        INNER JOIN Torneo.PARTIDO AS p ON p.numero_partido = g.numero_partido
        INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.descripcion = g.tipo_gol
        WHERE NOT EXISTS (SELECT 1 FROM DesarrolloPartido.GOL AS go
                          WHERE go.id_partido = p.id_partido AND go.id_jugador_autor = g.id_jugador_autor
                            AND go.id_tipo_gol = tg.id_tipo_gol AND go.periodo = g.periodo
                            AND ISNULL(go.minuto, 0) = ISNULL(g.minuto, 0)
                            AND go.minuto_adicional = ISNULL(g.minuto_adicional, 0));
        SET @a_insertar += @@ROWCOUNT;

        INSERT INTO DesarrolloPartido.AMONESTACION
            (id_partido, id_jugador, tipo_tarjeta, es_doble_amarilla, minuto, minuto_adicional, motivo)
        SELECT p.id_partido, t.id_jugador, t.tipo_tarjeta, ISNULL(t.es_doble_amarilla, 0), t.minuto,
               ISNULL(t.minuto_adicional, 0), TRIM(t.motivo)
        FROM @amonestaciones AS t
        INNER JOIN Torneo.PARTIDO AS p ON p.numero_partido = t.numero_partido
        WHERE NOT EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS am
                          WHERE am.id_partido = p.id_partido AND am.id_jugador = t.id_jugador
                            AND am.tipo_tarjeta = t.tipo_tarjeta
                            AND am.es_doble_amarilla = ISNULL(t.es_doble_amarilla, 0)
                            AND am.minuto = t.minuto AND am.minuto_adicional = ISNULL(t.minuto_adicional, 0));
        SET @a_insertar += @@ROWCOUNT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SET @insertados  = @a_insertar;
    SET @sin_cambios = @total - @a_insertar;
END;
GO


-- Evidencia: SP de importación creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE p.name LIKE N'usp[_]Importar%'
ORDER BY s.name, p.name;
GO
