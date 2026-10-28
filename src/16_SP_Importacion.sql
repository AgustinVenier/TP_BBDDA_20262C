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
           Los procesos de la Entrega 6 leen el archivo (CSV, XML, scraping o
           API) a una tabla de staging y llaman a estos SP fila por fila, cada
           una en su TRY/CATCH: así se importan los registros válidos y se
           informan los errores de los demás.
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


-- Evidencia: SP de importación creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE p.name LIKE N'usp[_]Importar%'
ORDER BY s.name, p.name;
GO
