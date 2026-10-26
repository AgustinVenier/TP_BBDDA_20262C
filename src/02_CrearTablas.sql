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

  Fecha:        25/10/2026
  Objetivo:     Crear todas las tablas del sistema con sus claves primarias,
                claves foraneas, restricciones UNIQUE, CHECK y DEFAULT, y los
                indices sobre claves foraneas.
                Requiere haber ejecutado 00_CrearBaseDeDatos.sql y
                01_CrearEsquemas.sql.

================================================================================

    Nomenclatura: 
    Tablas                      ESQUEMA.NOMBRE_EN_MAYUSCULAS (en singular)
    Columnas                    snake_case en minusculas; PK = id_<tabla>
    Clave primaria              PK_<TABLA>
    Clave foranea               FK_<TABLA>_<TABLA_REFERENCIADA>[_<rol>]
    Unique                      UQ_<TABLA>_<columnas>
    Índices únicos con filtro   UX_<TABLA>_<columnas>
    Indice                      IX_<TABLA>_<columnas>
    Check                       CK_<TABLA>_<regla>
    Default                     DF_<TABLA>_<columna>
    SP de ABM                   ESQUEMA.usp_<TABLA>_<Alta|Baja|Modificacion>
                                (ej. Torneo.usp_SEDE_Alta)
    SP de negocio               ESQUEMA.usp_<Verbo><Objeto> en PascalCase
                                (ej. Torneo.usp_RegistrarSede,
                                Torneo.usp_ImportarFixture)
                                No se usa el prefijo sp_, que es el de los
                                SP del sistema.
    Funcion                     ESQUEMA.fn_<Nombre> (ej. fn_EquipoEnCancha)
    Vista                       ESQUEMA.vw_<Nombre> (ej. vw_Fixture)
    Parametro                   @<columna> en snake_case, con el mismo nombre
                                que la columna que carga (ej. @id_sede)
    Variable local              @<nombre> en snake_case descriptivo
                                (ej. @cantidad_titulares). La que junta los
                                mensajes de validacion se llama @errores.

    Tipos de datos:
    Texto                       VARCHAR por defecto: la intercalacion
                                Modern_Spanish_100_CI_AS_SC usa la pagina de
                                codigos 1252, que cubre tildes, ñ y dieresis.
                                NVARCHAR solo para nombres que pueden venir en
                                cualquier alfabeto (personas, clubes,
                                anunciantes, campanias y piezas).
    Cantidades                  El entero mas chico que cubra el dominio:
                                TINYINT en minutos, goles, dorsal, numero de
                                partido, duraciones y parametros; SMALLINT en
                                el anio; INT en capacidad y asistencia (pasan
                                de 32.767).
    Claves                      INT en las tablas que crecen con el uso:
                                IDENTITY no reutiliza los valores que consumen
                                los INSERT fallidos, los ROLLBACK y los
                                borrados, y achicarlas ahorraria pocos KB.
                                Los catalogos cerrados usan el tipo mas chico:
                                TIPO_GOL TINYINT, PAIS e IDIOMA SMALLINT. Cada
                                FK tiene el mismo tipo que la PK que referencia.
    Montos y coordenadas        DECIMAL, se evita FLOAT a menos que sea estrictamente necesario.

  El script es re-ejecutable: borra las tablas en orden inverso de dependencias
  y las vuelve a crear (CUIDADO: al hacer esto se pierden datos previamente cargados).

*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   BORRADO EN ORDEN INVERSO DE DEPENDENCIAS
   ============================================================================ */

DROP TABLE IF EXISTS Publicidad.EXHIBICION;
DROP TABLE IF EXISTS Publicidad.PIEZA_PAIS_INTERES;
DROP TABLE IF EXISTS Publicidad.PIEZA_PUBLICITARIA;
DROP TABLE IF EXISTS Publicidad.ESPACIO_PUBLICITARIO;
DROP TABLE IF EXISTS Publicidad.CAMPANIA;
DROP TABLE IF EXISTS Publicidad.ANUNCIANTE;

DROP TABLE IF EXISTS Arbitraje.DESIGNACION_ARBITRAL;
DROP TABLE IF EXISTS Arbitraje.ARBITRO_IDIOMA;
DROP TABLE IF EXISTS Arbitraje.ARBITRO;

DROP TABLE IF EXISTS DesarrolloPartido.AMONESTACION;
DROP TABLE IF EXISTS DesarrolloPartido.GOL;
DROP TABLE IF EXISTS DesarrolloPartido.TIPO_GOL;
DROP TABLE IF EXISTS DesarrolloPartido.CAMBIO;
DROP TABLE IF EXISTS DesarrolloPartido.ALINEACION;
DROP TABLE IF EXISTS DesarrolloPartido.FORMACION;

DROP TABLE IF EXISTS Torneo.PARTIDO;
DROP TABLE IF EXISTS Torneo.PERSONA_CUERPO_TECNICO;
DROP TABLE IF EXISTS Torneo.JUGADOR;
DROP TABLE IF EXISTS Torneo.LISTA_CONVOCADOS;
DROP TABLE IF EXISTS Torneo.SELECCION;
DROP TABLE IF EXISTS Torneo.SEDE;

DROP TABLE IF EXISTS DatosGenerales.PARAMETRO_REGLAMENTO;
DROP TABLE IF EXISTS DatosGenerales.INDICADOR_ECONOMICO;
DROP TABLE IF EXISTS DatosGenerales.IDIOMA;
DROP TABLE IF EXISTS DatosGenerales.PAIS;
GO

/* ============================================================================
   ESQUEMA DatosGenerales
   ============================================================================ */

/*
  PAIS
  - Inglaterra, Escocia y Gales juegan como selecciones separadas pero comparten
    codigo ISO (GB / GBR), por eso los codigos ISO no son UNIQUE ni obligatorios.
    El identificador natural para importar fixtures es codigo_fifa.
  - codigo_iso2: lo usa Nager.Date (feriados).
  - codigo_iso3: lo usa la API del Banco Mundial.
  - huso_horario: nombre de zona de Windows (ver sys.time_zone_info) para poder
    usar AT TIME ZONE en el calculo de prime time. Ej: 'Argentina Standard Time'.
    La validacion contra sys.time_zone_info se hace en los SP.
  - codigo_moneda: ISO 4217.
*/
CREATE TABLE DatosGenerales.PAIS (
    id_pais         SMALLINT IDENTITY(1,1) NOT NULL,
    nombre          VARCHAR(60)            NOT NULL,
    codigo_fifa     CHAR(3)                NULL,
    codigo_iso2     CHAR(2)                NULL,
    codigo_iso3     CHAR(3)                NULL,
    huso_horario    VARCHAR(50)            NOT NULL,
    codigo_moneda   CHAR(3)                NULL,

    CONSTRAINT PK_PAIS PRIMARY KEY (id_pais),
    CONSTRAINT UQ_PAIS_nombre UNIQUE (nombre),
    CONSTRAINT CK_PAIS_codigo_fifa   CHECK (codigo_fifa   LIKE '[A-Z][A-Z][A-Z]'),
    CONSTRAINT CK_PAIS_codigo_iso2   CHECK (codigo_iso2   LIKE '[A-Z][A-Z]'),
    CONSTRAINT CK_PAIS_codigo_iso3   CHECK (codigo_iso3   LIKE '[A-Z][A-Z][A-Z]'),
    CONSTRAINT CK_PAIS_codigo_moneda CHECK (codigo_moneda LIKE '[A-Z][A-Z][A-Z]')
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_PAIS_codigo_fifa
    ON DatosGenerales.PAIS (codigo_fifa)
    WHERE codigo_fifa IS NOT NULL;
GO


CREATE TABLE DatosGenerales.IDIOMA (
    id_idioma       SMALLINT IDENTITY(1,1) NOT NULL,
    nombre          VARCHAR(40)            NOT NULL,
    codigo_iso      CHAR(2)                NULL,     -- ISO 639-1 (ej. 'es', 'en')

    CONSTRAINT PK_IDIOMA PRIMARY KEY (id_idioma),
    CONSTRAINT UQ_IDIOMA_nombre UNIQUE (nombre),
    CONSTRAINT CK_IDIOMA_codigo_iso CHECK (codigo_iso LIKE '[a-z][a-z]')
);
GO


/*
  INDICADOR_ECONOMICO
  Un registro por pais, indicador y año. El UNIQUE es la clave natural que
  usa el upsert de la importacion desde el Banco Mundial (ej. NY.GDP.PCAP.CD).
*/
CREATE TABLE DatosGenerales.INDICADOR_ECONOMICO (
    id_indicador        INT IDENTITY(1,1) NOT NULL,
    id_pais             SMALLINT          NOT NULL,
    codigo_indicador    VARCHAR(30)       NOT NULL,
    anio                SMALLINT          NOT NULL,
    valor               DECIMAL(18,4)     NOT NULL,
    fecha_actualizacion DATETIME2(0)      NOT NULL
        CONSTRAINT DF_INDICADOR_ECONOMICO_fecha_actualizacion DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_INDICADOR_ECONOMICO PRIMARY KEY (id_indicador),
    CONSTRAINT FK_INDICADOR_ECONOMICO_PAIS
        FOREIGN KEY (id_pais) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT UQ_INDICADOR_ECONOMICO_pais_codigo_anio
        UNIQUE (id_pais, codigo_indicador, anio),
    CONSTRAINT CK_INDICADOR_ECONOMICO_anio CHECK (anio BETWEEN 1960 AND 2100)
);
GO


/*
  PARAMETRO_REGLAMENTO
  No figura en el DER: es una tabla de configuracion del sistema, no una
  entidad del dominio, y no se relaciona con ninguna otra tabla.
  Valores del reglamento que usan los SP para validar y calcular, para que
  cambiar una regla no requiera tocar codigo (criterios de suspension
  parametrizables, maximo de cambios y ventanas).
  Formato clave-valor: agregar un parametro nuevo es un INSERT, no un ALTER.
  Codigos previstos (los valores se cargan en el script de datos iniciales):
    AMARILLAS_PARA_SUSPENSION        amarillas acumuladas en partidos distintos
    FECHAS_SUSPENSION_ACUMULACION    partidos de suspension por acumulacion
    FECHAS_SUSPENSION_DOBLE_AMARILLA partidos de suspension por doble amarilla
    FECHAS_SUSPENSION_ROJA_DIRECTA   partidos de suspension por roja directa
    MAX_CAMBIOS                      cambios permitidos en tiempo reglamentario
    MAX_VENTANAS                     ventanas de cambio en tiempo reglamentario
    CAMBIOS_EXTRA_ALARGUE            cambios adicionales en tiempo suplementario
    VENTANAS_EXTRA_ALARGUE           ventanas adicionales en tiempo suplementario
    MIN_CONVOCADOS / MAX_CONVOCADOS  tamanio de la lista de convocados
  valor es TINYINT: los parametros son conteos chicos (0 a 255) y el tipo ya
  impide valores negativos.
*/
CREATE TABLE DatosGenerales.PARAMETRO_REGLAMENTO (
    codigo              VARCHAR(50)     NOT NULL,
    descripcion         VARCHAR(200)    NOT NULL,
    valor               TINYINT         NOT NULL,
    fecha_modificacion  DATETIME2(0)    NOT NULL
        CONSTRAINT DF_PARAMETRO_REGLAMENTO_fecha_modificacion DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_PARAMETRO_REGLAMENTO PRIMARY KEY (codigo),
    CONSTRAINT CK_PARAMETRO_REGLAMENTO_codigo CHECK (codigo NOT LIKE '%[^A-Z0-9_]%')
);
GO


/* ============================================================================
   ESQUEMA Torneo
   ============================================================================ */

/*
  SEDE
  Tiene su propio huso horario porque un mismo pais (EEUU, Mexico, Canada)
  puede tener sedes en zonas distintas. Latitud y longitud para el mapa de BI.
*/
CREATE TABLE Torneo.SEDE (
    id_sede         INT IDENTITY(1,1) NOT NULL,
    nombre_estadio  VARCHAR(100)      NOT NULL,
    ciudad          VARCHAR(80)       NOT NULL,
    id_pais         SMALLINT          NOT NULL,
    capacidad       INT               NOT NULL,
    huso_horario    VARCHAR(50)       NOT NULL,
    latitud         DECIMAL(9,6)      NULL,
    longitud        DECIMAL(9,6)      NULL,

    CONSTRAINT PK_SEDE PRIMARY KEY (id_sede),
    CONSTRAINT FK_SEDE_PAIS
        FOREIGN KEY (id_pais) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT UQ_SEDE_nombre_estadio UNIQUE (nombre_estadio),
    CONSTRAINT CK_SEDE_capacidad CHECK (capacidad > 0),
    CONSTRAINT CK_SEDE_latitud   CHECK (latitud  BETWEEN -90  AND 90),
    CONSTRAINT CK_SEDE_longitud  CHECK (longitud BETWEEN -180 AND 180)
);
GO


/*
  SELECCION
  Relacion 1:1 con PAIS (UNIQUE sobre id_pais).
  Grupos A a L (48 selecciones).
*/
CREATE TABLE Torneo.SELECCION (
    id_seleccion    INT IDENTITY(1,1) NOT NULL,
    id_pais         SMALLINT          NOT NULL,
    confederacion   VARCHAR(10)       NOT NULL,
    grupo           CHAR(1)           NULL,

    CONSTRAINT PK_SELECCION PRIMARY KEY (id_seleccion),
    CONSTRAINT FK_SELECCION_PAIS
        FOREIGN KEY (id_pais) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT UQ_SELECCION_id_pais UNIQUE (id_pais),
    CONSTRAINT CK_SELECCION_confederacion
        CHECK (confederacion IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')),
    CONSTRAINT CK_SELECCION_grupo CHECK (grupo LIKE '[A-L]')
);
GO


/*
  LISTA_CONVOCADOS
  Relacion 1:1 con SELECCION (UNIQUE sobre id_seleccion).
*/
CREATE TABLE Torneo.LISTA_CONVOCADOS (
    id_lista            INT IDENTITY(1,1) NOT NULL,
    id_seleccion        INT               NOT NULL,
    fecha_presentacion  DATE              NOT NULL,

    CONSTRAINT PK_LISTA_CONVOCADOS PRIMARY KEY (id_lista),
    CONSTRAINT FK_LISTA_CONVOCADOS_SELECCION
        FOREIGN KEY (id_seleccion) REFERENCES Torneo.SELECCION (id_seleccion),
    CONSTRAINT UQ_LISTA_CONVOCADOS_id_seleccion UNIQUE (id_seleccion)
);
GO


/*
  JUGADOR
  Relacion N:1 con LISTA_CONVOCADOS (convoca).
  Altas y bajas de ultima hora: el jugador dado de baja conserva el registro con
  fecha_baja y motivo_baja; el reemplazo se da de alta con motivo_alta.
  El dorsal es unico dentro de la lista solo entre jugadores activos, asi el
  reemplazante puede heredar el numero del lesionado.
  (id_lista, apellido, nombre) es la clave para el upsert de plantillas.
*/
CREATE TABLE Torneo.JUGADOR (
    id_jugador          INT IDENTITY(1,1) NOT NULL,
    id_lista            INT               NOT NULL,
    id_pais_nacimiento  SMALLINT          NULL,
    nombre              NVARCHAR(60)      NOT NULL,
    apellido            NVARCHAR(60)      NOT NULL,
    fecha_nacimiento    DATE              NULL,
    club_origen         NVARCHAR(100)     NULL,
    posicion_habitual   VARCHAR(15)       NOT NULL,
    dorsal              TINYINT           NOT NULL,
    fecha_alta          DATE              NOT NULL
        CONSTRAINT DF_JUGADOR_fecha_alta DEFAULT (CONVERT(DATE, GETDATE())),
    motivo_alta         VARCHAR(200)      NULL,
    fecha_baja          DATE              NULL,
    motivo_baja         VARCHAR(200)      NULL,

    CONSTRAINT PK_JUGADOR PRIMARY KEY (id_jugador),
    CONSTRAINT FK_JUGADOR_LISTA_CONVOCADOS
        FOREIGN KEY (id_lista) REFERENCES Torneo.LISTA_CONVOCADOS (id_lista),
    CONSTRAINT FK_JUGADOR_PAIS_nacimiento
        FOREIGN KEY (id_pais_nacimiento) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT UQ_JUGADOR_lista_apellido_nombre UNIQUE (id_lista, apellido, nombre),
    CONSTRAINT CK_JUGADOR_posicion_habitual
        CHECK (posicion_habitual IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')),
    CONSTRAINT CK_JUGADOR_dorsal CHECK (dorsal BETWEEN 1 AND 99),
    CONSTRAINT CK_JUGADOR_fechas CHECK (fecha_baja IS NULL OR fecha_baja >= fecha_alta),
    CONSTRAINT CK_JUGADOR_baja_con_motivo CHECK (
        (fecha_baja IS NULL     AND motivo_baja IS NULL) OR
        (fecha_baja IS NOT NULL AND motivo_baja IS NOT NULL)
    )
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_JUGADOR_lista_dorsal_activo
    ON Torneo.JUGADOR (id_lista, dorsal)
    WHERE fecha_baja IS NULL;
GO


/*
  PERSONA_CUERPO_TECNICO
  Relacion N:1 con SELECCION (se compone) y N:1 con PAIS (nacio en).
  Un solo director tecnico por seleccion.
*/
CREATE TABLE Torneo.PERSONA_CUERPO_TECNICO (
    id_persona_ct       INT IDENTITY(1,1) NOT NULL,
    id_seleccion        INT               NOT NULL,
    id_pais_nacimiento  SMALLINT          NULL,
    nombre              NVARCHAR(60)      NOT NULL,
    apellido            NVARCHAR(60)      NOT NULL,
    fecha_nacimiento    DATE              NULL,
    rol                 VARCHAR(20)       NOT NULL,

    CONSTRAINT PK_PERSONA_CUERPO_TECNICO PRIMARY KEY (id_persona_ct),
    CONSTRAINT FK_PERSONA_CUERPO_TECNICO_SELECCION
        FOREIGN KEY (id_seleccion) REFERENCES Torneo.SELECCION (id_seleccion),
    CONSTRAINT FK_PERSONA_CUERPO_TECNICO_PAIS_nacimiento
        FOREIGN KEY (id_pais_nacimiento) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT CK_PERSONA_CUERPO_TECNICO_rol CHECK (rol IN (
        'DIRECTOR_TECNICO', 'AYUDANTE_CAMPO', 'PREPARADOR_FISICO',
        'ENTRENADOR_ARQUEROS', 'MEDICO', 'OTRO'))
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_PERSONA_CUERPO_TECNICO_un_dt
    ON Torneo.PERSONA_CUERPO_TECNICO (id_seleccion)
    WHERE rol = 'DIRECTOR_TECNICO';
GO


/*
  PARTIDO
  - Relacion N:1 con SEDE (se disputa).
  - Las dos relaciones "juega" con SELECCION se resuelven como local y visitante.
    Son NULL para poder cargar el fixture de eliminatorias antes de conocer los
    cruces (ej. "1A vs 2B").
  - Se guarda la fecha y hora local de la sede y la UTC.
    La local se deriva de la UTC y del huso de la sede (excepcion a 3FN): se
    guarda para mostrar el fixture oficial tal como se publica, y el SP de alta
    debe calcular una a partir de la otra para que no queden inconsistentes.
  - Resultado NULL hasta que se juega. Penales solo en eliminacion directa y
    con empate en goles.
  - numero_partido es la clave natural para el upsert del fixture oficial.
*/
CREATE TABLE Torneo.PARTIDO (
    id_partido              INT IDENTITY(1,1) NOT NULL,
    numero_partido          TINYINT           NOT NULL,
    id_sede                 INT               NOT NULL,
    id_seleccion_local      INT               NULL,
    id_seleccion_visitante  INT               NULL,
    fase                    VARCHAR(15)       NOT NULL,
    fecha_hora_local        DATETIME2(0)      NOT NULL,
    fecha_hora_utc          DATETIME2(0)      NOT NULL,
    goles_local             TINYINT           NULL,
    goles_visitante         TINYINT           NULL,
    penales_local           TINYINT           NULL,
    penales_visitante       TINYINT           NULL,
    asistencia              INT               NULL,
    estado                  VARCHAR(12)       NOT NULL
    
    CONSTRAINT DF_PARTIDO_estado DEFAULT ('PROGRAMADO'),

    CONSTRAINT PK_PARTIDO PRIMARY KEY (id_partido),
    CONSTRAINT FK_PARTIDO_SEDE
        FOREIGN KEY (id_sede) REFERENCES Torneo.SEDE (id_sede),
    CONSTRAINT FK_PARTIDO_SELECCION_local
        FOREIGN KEY (id_seleccion_local) REFERENCES Torneo.SELECCION (id_seleccion),
    CONSTRAINT FK_PARTIDO_SELECCION_visitante
        FOREIGN KEY (id_seleccion_visitante) REFERENCES Torneo.SELECCION (id_seleccion),
    CONSTRAINT UQ_PARTIDO_numero_partido UNIQUE (numero_partido),
    CONSTRAINT CK_PARTIDO_fase CHECK (fase IN (
        'GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS',
        'SEMIFINAL', 'TERCER_PUESTO', 'FINAL')),
    CONSTRAINT CK_PARTIDO_estado CHECK (estado IN (
        'PROGRAMADO', 'EN_JUEGO', 'FINALIZADO', 'SUSPENDIDO')),
    CONSTRAINT CK_PARTIDO_selecciones_distintas
        CHECK (id_seleccion_local <> id_seleccion_visitante),
    CONSTRAINT CK_PARTIDO_goles_completos CHECK (
        (goles_local IS NULL     AND goles_visitante IS NULL) OR
        (goles_local IS NOT NULL AND goles_visitante IS NOT NULL)
    ),
    CONSTRAINT CK_PARTIDO_penales_completos CHECK (
        (penales_local IS NULL     AND penales_visitante IS NULL) OR
        (penales_local IS NOT NULL AND penales_visitante IS NOT NULL)
    ),
    CONSTRAINT CK_PARTIDO_penales_solo_eliminatoria
        CHECK (penales_local IS NULL OR fase <> 'GRUPOS'),
    CONSTRAINT CK_PARTIDO_penales_con_empate CHECK (
        penales_local IS NULL OR
        (goles_local IS NOT NULL AND goles_local = goles_visitante
                                 AND penales_local <> penales_visitante)
    ),
    CONSTRAINT CK_PARTIDO_finalizado_con_resultado CHECK (
        estado <> 'FINALIZADO' OR
        (goles_local IS NOT NULL AND id_seleccion_local IS NOT NULL
                                 AND id_seleccion_visitante IS NOT NULL)
    ),
    CONSTRAINT CK_PARTIDO_asistencia CHECK (asistencia >= 0)
);
GO


/* ============================================================================
   ESQUEMA DesarrolloPartido
   ============================================================================ */

/*
  TIPO_GOL
  es_en_contra marca los tipos que suman para el rival del autor: el marcador
  se lo computa a la otra seleccion y la tabla de goleadores no lo cuenta.
*/
CREATE TABLE DesarrolloPartido.TIPO_GOL (
    id_tipo_gol     TINYINT IDENTITY(1,1) NOT NULL,
    descripcion     VARCHAR(40)           NOT NULL,   -- jugada, penal, tiro libre, en contra, cabezazo...
    es_en_contra    BIT                   NOT NULL
        CONSTRAINT DF_TIPO_GOL_es_en_contra DEFAULT (0),

    CONSTRAINT PK_TIPO_GOL PRIMARY KEY (id_tipo_gol),
    CONSTRAINT UQ_TIPO_GOL_descripcion UNIQUE (descripcion)
);
GO


/*
  FORMACION
  Relacion N:1 con PARTIDO (tiene). Una formacion por seleccion por partido.
*/
CREATE TABLE DesarrolloPartido.FORMACION (
    id_formacion    INT IDENTITY(1,1) NOT NULL,
    id_partido      INT               NOT NULL,
    id_seleccion    INT               NOT NULL,
    esquema_tactico VARCHAR(10)       NOT NULL,   -- ej. '4-3-3', '4-2-3-1'

    CONSTRAINT PK_FORMACION PRIMARY KEY (id_formacion),
    CONSTRAINT FK_FORMACION_PARTIDO
        FOREIGN KEY (id_partido) REFERENCES Torneo.PARTIDO (id_partido),
    CONSTRAINT FK_FORMACION_SELECCION
        FOREIGN KEY (id_seleccion) REFERENCES Torneo.SELECCION (id_seleccion),
    CONSTRAINT UQ_FORMACION_partido_seleccion UNIQUE (id_partido, id_seleccion),
    CONSTRAINT CK_FORMACION_esquema_tactico
        CHECK (esquema_tactico LIKE '[0-9]-[0-9]%')
);
GO


/*
  ALINEACION
  Resuelve la relacion N:N entre FORMACION y JUGADOR.
  es_titular = 1 -> once inicial; es_titular = 0 -> banco de suplentes.
  El dorsal no se repite aca porque ya esta en JUGADOR (3FN).
*/
CREATE TABLE DesarrolloPartido.ALINEACION (
    id_formacion        INT          NOT NULL,
    id_jugador          INT          NOT NULL,
    es_titular          BIT          NOT NULL,
    posicion_en_cancha  VARCHAR(30)  NULL,

    CONSTRAINT PK_ALINEACION PRIMARY KEY (id_formacion, id_jugador),
    CONSTRAINT FK_ALINEACION_FORMACION
        FOREIGN KEY (id_formacion) REFERENCES DesarrolloPartido.FORMACION (id_formacion),
    CONSTRAINT FK_ALINEACION_JUGADOR
        FOREIGN KEY (id_jugador) REFERENCES Torneo.JUGADOR (id_jugador),
    CONSTRAINT CK_ALINEACION_titular_con_posicion
        CHECK (es_titular = 0 OR posicion_en_cancha IS NOT NULL)
);
GO


/*
  CAMBIO
  Relaciones N:1 con PARTIDO (se realiza), con JUGADOR (sale) y con JUGADOR (entra).
  Minuto: 1 a 120 (minuto > 90 implica tiempo suplementario); los adicionales
  van en minuto_adicional (ej. 90+3 -> minuto 90, adicional 3).
  Los cambios hechos en un entretiempo (antes del segundo tiempo, antes del
  alargue o en su descanso) no consumen ventana: se registran con
  en_entretiempo = 1 y minuto 46, 91 o 106.
*/
CREATE TABLE DesarrolloPartido.CAMBIO (
    id_cambio           INT IDENTITY(1,1) NOT NULL,
    id_partido          INT               NOT NULL,
    id_jugador_sale     INT               NOT NULL,
    id_jugador_entra    INT               NOT NULL,
    minuto              TINYINT           NOT NULL,
    minuto_adicional    TINYINT           NOT NULL
        CONSTRAINT DF_CAMBIO_minuto_adicional DEFAULT (0),
    en_entretiempo      BIT               NOT NULL
        CONSTRAINT DF_CAMBIO_en_entretiempo DEFAULT (0),
    motivo              VARCHAR(12)       NOT NULL,

    CONSTRAINT PK_CAMBIO PRIMARY KEY (id_cambio),
    CONSTRAINT FK_CAMBIO_PARTIDO
        FOREIGN KEY (id_partido) REFERENCES Torneo.PARTIDO (id_partido),
    CONSTRAINT FK_CAMBIO_JUGADOR_sale
        FOREIGN KEY (id_jugador_sale) REFERENCES Torneo.JUGADOR (id_jugador),
    CONSTRAINT FK_CAMBIO_JUGADOR_entra
        FOREIGN KEY (id_jugador_entra) REFERENCES Torneo.JUGADOR (id_jugador),
    CONSTRAINT UQ_CAMBIO_partido_sale  UNIQUE (id_partido, id_jugador_sale),
    CONSTRAINT UQ_CAMBIO_partido_entra UNIQUE (id_partido, id_jugador_entra),
    CONSTRAINT CK_CAMBIO_jugadores_distintos CHECK (id_jugador_sale <> id_jugador_entra),
    CONSTRAINT CK_CAMBIO_minuto CHECK (minuto BETWEEN 1 AND 120),
    CONSTRAINT CK_CAMBIO_minuto_adicional CHECK (minuto_adicional BETWEEN 0 AND 30),
    CONSTRAINT CK_CAMBIO_entretiempo CHECK (
        en_entretiempo = 0 OR (minuto IN (46, 91, 106) AND minuto_adicional = 0)
    ),
    CONSTRAINT CK_CAMBIO_motivo CHECK (motivo IN ('TACTICO', 'LESION', 'PRECAUCION'))
);
GO


/*
  GOL
  Relaciones N:1 con PARTIDO (se realiza), JUGADOR (autor), JUGADOR (asiste,
  opcional) y TIPO_GOL (es).
    PRIMER_TIEMPO   minuto 1 a 45
    SEGUNDO_TIEMPO  minuto 46 a 90
    ALARGUE         minuto 91 a 120
    ADICIONALES     tiempo agregado de cualquier tiempo: minuto 45, 90, 105 o
                    120 y minuto_adicional > 0 (ej. 90+3)
    PENALES         definicion por penales: sin minuto; no suma al marcador
                    ni a la tabla de goleadores
*/
CREATE TABLE DesarrolloPartido.GOL (
    id_gol                  INT IDENTITY(1,1) NOT NULL,
    id_partido              INT               NOT NULL,
    id_jugador_autor        INT               NOT NULL,
    id_jugador_asistencia   INT               NULL,
    id_tipo_gol             TINYINT           NOT NULL,
    periodo                 VARCHAR(15)       NOT NULL,
    minuto                  TINYINT           NULL,
    minuto_adicional        TINYINT           NOT NULL
        CONSTRAINT DF_GOL_minuto_adicional DEFAULT (0),

    CONSTRAINT PK_GOL PRIMARY KEY (id_gol),
    CONSTRAINT FK_GOL_PARTIDO
        FOREIGN KEY (id_partido) REFERENCES Torneo.PARTIDO (id_partido),
    CONSTRAINT FK_GOL_JUGADOR_autor
        FOREIGN KEY (id_jugador_autor) REFERENCES Torneo.JUGADOR (id_jugador),
    CONSTRAINT FK_GOL_JUGADOR_asistencia
        FOREIGN KEY (id_jugador_asistencia) REFERENCES Torneo.JUGADOR (id_jugador),
    CONSTRAINT FK_GOL_TIPO_GOL
        FOREIGN KEY (id_tipo_gol) REFERENCES DesarrolloPartido.TIPO_GOL (id_tipo_gol),
    CONSTRAINT CK_GOL_periodo CHECK (periodo IN (
        'PRIMER_TIEMPO', 'SEGUNDO_TIEMPO', 'ALARGUE', 'ADICIONALES', 'PENALES')),
    CONSTRAINT CK_GOL_minuto_segun_periodo CHECK (
        (periodo = 'PENALES' AND minuto IS NULL AND minuto_adicional = 0) OR
        (periodo <> 'PENALES' AND minuto IS NOT NULL AND (
            (periodo = 'PRIMER_TIEMPO'  AND minuto BETWEEN 1  AND 45  AND minuto_adicional = 0) OR
            (periodo = 'SEGUNDO_TIEMPO' AND minuto BETWEEN 46 AND 90  AND minuto_adicional = 0) OR
            (periodo = 'ALARGUE'        AND minuto BETWEEN 91 AND 120 AND minuto_adicional = 0) OR
            (periodo = 'ADICIONALES'    AND minuto IN (45, 90, 105, 120) AND minuto_adicional > 0)
        ))
    ),
    CONSTRAINT CK_GOL_minuto_adicional CHECK (minuto_adicional BETWEEN 0 AND 30),
    CONSTRAINT CK_GOL_asistencia_distinta_autor
        CHECK (id_jugador_asistencia <> id_jugador_autor)
);
GO


/*
  AMONESTACION
  Relaciones N:1 con PARTIDO (pertenece), JUGADOR (recibe) y
  PERSONA_CUERPO_TECNICO (recibe). Exactamente uno de los dos receptores.
  Doble amarilla: se registra la segunda AMARILLA y ademas una ROJA con
  es_doble_amarilla = 1. Roja directa: ROJA con es_doble_amarilla = 0.
*/
CREATE TABLE DesarrolloPartido.AMONESTACION (
    id_amonestacion     INT IDENTITY(1,1) NOT NULL,
    id_partido          INT               NOT NULL,
    id_jugador          INT               NULL,
    id_persona_ct       INT               NULL,
    tipo_tarjeta        VARCHAR(8)        NOT NULL,
    es_doble_amarilla   BIT               NOT NULL
        CONSTRAINT DF_AMONESTACION_es_doble_amarilla DEFAULT (0),
    minuto              TINYINT           NOT NULL,
    minuto_adicional    TINYINT           NOT NULL
        CONSTRAINT DF_AMONESTACION_minuto_adicional DEFAULT (0),
    motivo              VARCHAR(200)      NOT NULL,

    CONSTRAINT PK_AMONESTACION PRIMARY KEY (id_amonestacion),
    CONSTRAINT FK_AMONESTACION_PARTIDO
        FOREIGN KEY (id_partido) REFERENCES Torneo.PARTIDO (id_partido),
    CONSTRAINT FK_AMONESTACION_JUGADOR
        FOREIGN KEY (id_jugador) REFERENCES Torneo.JUGADOR (id_jugador),
    CONSTRAINT FK_AMONESTACION_PERSONA_CUERPO_TECNICO
        FOREIGN KEY (id_persona_ct) REFERENCES Torneo.PERSONA_CUERPO_TECNICO (id_persona_ct),
    CONSTRAINT CK_AMONESTACION_un_receptor CHECK (
        (id_jugador IS NOT NULL AND id_persona_ct IS NULL) OR
        (id_jugador IS NULL     AND id_persona_ct IS NOT NULL)
    ),
    CONSTRAINT CK_AMONESTACION_tipo_tarjeta CHECK (tipo_tarjeta IN ('AMARILLA', 'ROJA')),
    CONSTRAINT CK_AMONESTACION_doble_amarilla_es_roja
        CHECK (es_doble_amarilla = 0 OR tipo_tarjeta = 'ROJA'),
    CONSTRAINT CK_AMONESTACION_minuto CHECK (minuto BETWEEN 0 AND 120),
    CONSTRAINT CK_AMONESTACION_minuto_adicional CHECK (minuto_adicional BETWEEN 0 AND 30)
);
GO


/* ============================================================================
   ESQUEMA Arbitraje
   ============================================================================ */

/*
  ARBITRO
  Relacion N:1 con PAIS (nacio en). Es el pais que se usa para validar el
  conflicto de nacionalidad en la designacion.
  (id_pais, apellido, nombre) es la clave natural para el upsert de la nomina.
*/
CREATE TABLE Arbitraje.ARBITRO (
    id_arbitro          INT IDENTITY(1,1) NOT NULL,
    id_pais             SMALLINT          NOT NULL,
    nombre              NVARCHAR(60)      NOT NULL,
    apellido            NVARCHAR(60)      NOT NULL,
    fecha_nacimiento    DATE              NULL,
    categoria           VARCHAR(15)       NOT NULL,
    activo              BIT               NOT NULL
        CONSTRAINT DF_ARBITRO_activo DEFAULT (1),

    CONSTRAINT PK_ARBITRO PRIMARY KEY (id_arbitro),
    CONSTRAINT FK_ARBITRO_PAIS
        FOREIGN KEY (id_pais) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT UQ_ARBITRO_pais_apellido_nombre UNIQUE (id_pais, apellido, nombre),
    CONSTRAINT CK_ARBITRO_categoria CHECK (categoria IN ('FIFA', 'CONFEDERACION'))
);
GO


/*
  ARBITRO_IDIOMA
  Resuelve la relacion "habla" como N:N (un idioma lo hablan muchos arbitros).
*/
CREATE TABLE Arbitraje.ARBITRO_IDIOMA (
    id_arbitro  INT      NOT NULL,
    id_idioma   SMALLINT NOT NULL,

    CONSTRAINT PK_ARBITRO_IDIOMA PRIMARY KEY (id_arbitro, id_idioma),
    CONSTRAINT FK_ARBITRO_IDIOMA_ARBITRO
        FOREIGN KEY (id_arbitro) REFERENCES Arbitraje.ARBITRO (id_arbitro),
    CONSTRAINT FK_ARBITRO_IDIOMA_IDIOMA
        FOREIGN KEY (id_idioma) REFERENCES DatosGenerales.IDIOMA (id_idioma)
);
GO


/*
  DESIGNACION_ARBITRAL
  Resuelve la relacion N:N "dirige" entre PARTIDO y ARBITRO.
  Un arbitro cumple un solo rol por partido y cada rol lo cubre un solo arbitro.
  El conflicto de nacionalidad se valida en el SP de designacion.
*/
CREATE TABLE Arbitraje.DESIGNACION_ARBITRAL (
    id_partido          INT             NOT NULL,
    id_arbitro          INT             NOT NULL,
    rol                 VARCHAR(12)     NOT NULL,
    informe_postpartido VARCHAR(MAX)    NULL,
    sancion             VARCHAR(500)    NULL,
    fecha_designacion   DATETIME2(0)    NOT NULL
        CONSTRAINT DF_DESIGNACION_ARBITRAL_fecha_designacion DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_DESIGNACION_ARBITRAL PRIMARY KEY (id_partido, id_arbitro),
    CONSTRAINT FK_DESIGNACION_ARBITRAL_PARTIDO
        FOREIGN KEY (id_partido) REFERENCES Torneo.PARTIDO (id_partido),
    CONSTRAINT FK_DESIGNACION_ARBITRAL_ARBITRO
        FOREIGN KEY (id_arbitro) REFERENCES Arbitraje.ARBITRO (id_arbitro),
    CONSTRAINT UQ_DESIGNACION_ARBITRAL_partido_rol UNIQUE (id_partido, rol),
    CONSTRAINT CK_DESIGNACION_ARBITRAL_rol CHECK (rol IN (
        'PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR'))
);
GO


/* ============================================================================
   ESQUEMA Publicidad
   ============================================================================ */

CREATE TABLE Publicidad.ANUNCIANTE (
    id_anunciante   INT IDENTITY(1,1) NOT NULL,
    razon_social    NVARCHAR(150)     NOT NULL,
    id_pais         SMALLINT          NOT NULL,

    CONSTRAINT PK_ANUNCIANTE PRIMARY KEY (id_anunciante),
    CONSTRAINT FK_ANUNCIANTE_PAIS
        FOREIGN KEY (id_pais) REFERENCES DatosGenerales.PAIS (id_pais),
    CONSTRAINT UQ_ANUNCIANTE_razon_social UNIQUE (razon_social)
);
GO


/*
  CAMPAÑA
  Relacion N:1 con ANUNCIANTE (publica).
*/
CREATE TABLE Publicidad.CAMPANIA (
    id_campania     INT IDENTITY(1,1) NOT NULL,
    id_anunciante   INT               NOT NULL,
    nombre          NVARCHAR(150)     NOT NULL,
    fecha_inicio    DATE              NOT NULL,
    fecha_fin       DATE              NOT NULL,

    CONSTRAINT PK_CAMPANIA PRIMARY KEY (id_campania),
    CONSTRAINT FK_CAMPANIA_ANUNCIANTE
        FOREIGN KEY (id_anunciante) REFERENCES Publicidad.ANUNCIANTE (id_anunciante),
    CONSTRAINT UQ_CAMPANIA_anunciante_nombre UNIQUE (id_anunciante, nombre),
    CONSTRAINT CK_CAMPANIA_fechas CHECK (fecha_fin >= fecha_inicio)
);
GO


/*
  PIEZA_PUBLICITARIA
  Relacion N:1 con CAMPANIA (pertenece). id_idioma cubre "piezas por idioma".
*/
CREATE TABLE Publicidad.PIEZA_PUBLICITARIA (
    id_pieza            INT IDENTITY(1,1) NOT NULL,
    id_campania         INT               NOT NULL,
    id_idioma           SMALLINT          NULL,
    titulo              NVARCHAR(150)     NOT NULL,
    duracion_segundos   TINYINT           NULL,

    CONSTRAINT PK_PIEZA_PUBLICITARIA PRIMARY KEY (id_pieza),
    CONSTRAINT FK_PIEZA_PUBLICITARIA_CAMPANIA
        FOREIGN KEY (id_campania) REFERENCES Publicidad.CAMPANIA (id_campania),
    CONSTRAINT FK_PIEZA_PUBLICITARIA_IDIOMA
        FOREIGN KEY (id_idioma) REFERENCES DatosGenerales.IDIOMA (id_idioma),
    CONSTRAINT UQ_PIEZA_PUBLICITARIA_campania_titulo UNIQUE (id_campania, titulo),
    CONSTRAINT CK_PIEZA_PUBLICITARIA_duracion CHECK (duracion_segundos > 0)
);
GO


/*
  PIEZA_PAIS_INTERES
  Resuelve la relacion "interes" como N:N (una pieza apunta a varios mercados
  y un mercado recibe muchas piezas).
*/
CREATE TABLE Publicidad.PIEZA_PAIS_INTERES (
    id_pieza    INT      NOT NULL,
    id_pais     SMALLINT NOT NULL,

    CONSTRAINT PK_PIEZA_PAIS_INTERES PRIMARY KEY (id_pieza, id_pais),
    CONSTRAINT FK_PIEZA_PAIS_INTERES_PIEZA_PUBLICITARIA
        FOREIGN KEY (id_pieza) REFERENCES Publicidad.PIEZA_PUBLICITARIA (id_pieza),
    CONSTRAINT FK_PIEZA_PAIS_INTERES_PAIS
        FOREIGN KEY (id_pais) REFERENCES DatosGenerales.PAIS (id_pais)
);
GO


/*
  ESPACIO_PUBLICITARIO
  Relacion N:1 con SEDE (alberga). Exactamente 4 espacios por sede:
  numero_espacio entre 1 y 4 + UNIQUE (id_sede, numero_espacio) impiden que
  haya mas de cuatro; que sean exactamente cuatro lo garantiza el SP de alta
  de la sede.
*/
CREATE TABLE Publicidad.ESPACIO_PUBLICITARIO (
    id_espacio      INT IDENTITY(1,1) NOT NULL,
    id_sede         INT               NOT NULL,
    numero_espacio  TINYINT           NOT NULL,
    descripcion     VARCHAR(100)      NULL,
    tarifa_usd      DECIMAL(9,2)      NOT NULL,

    CONSTRAINT PK_ESPACIO_PUBLICITARIO PRIMARY KEY (id_espacio),
    CONSTRAINT FK_ESPACIO_PUBLICITARIO_SEDE
        FOREIGN KEY (id_sede) REFERENCES Torneo.SEDE (id_sede),
    CONSTRAINT UQ_ESPACIO_PUBLICITARIO_sede_numero UNIQUE (id_sede, numero_espacio),
    CONSTRAINT CK_ESPACIO_PUBLICITARIO_numero CHECK (numero_espacio BETWEEN 1 AND 4),
    CONSTRAINT CK_ESPACIO_PUBLICITARIO_tarifa CHECK (tarifa_usd >= 0)
);
GO


/*
  EXHIBICION
  Relacion ternaria entre PARTIDO (N), ESPACIO_PUBLICITARIO (1) y
  PIEZA_PUBLICITARIA (1): en cada partido, cada espacio muestra una pieza y
  cada pieza ocupa un solo espacio.
  Es el historico para facturar. El costo se guarda al momento de la exhibicion
  (no es redundante con tarifa_usd porque la tarifa puede cambiar despues).
  costo admite otras monedas (codigo_moneda), con montos nominales mucho
  mayores que en dolares: DECIMAL(19,4) ocupa los mismos 9 bytes que (12,2).
  Que el espacio pertenezca a la sede del partido se valida en el SP.
*/
CREATE TABLE Publicidad.EXHIBICION (
    id_partido      INT             NOT NULL,
    id_espacio      INT             NOT NULL,
    id_pieza        INT             NOT NULL,
    costo           DECIMAL(19,4)   NOT NULL,
    codigo_moneda   CHAR(3)         NOT NULL
        CONSTRAINT DF_EXHIBICION_codigo_moneda DEFAULT ('USD'),
    fecha_registro  DATETIME2(0)    NOT NULL
        CONSTRAINT DF_EXHIBICION_fecha_registro DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_EXHIBICION PRIMARY KEY (id_partido, id_espacio),
    CONSTRAINT FK_EXHIBICION_PARTIDO
        FOREIGN KEY (id_partido) REFERENCES Torneo.PARTIDO (id_partido),
    CONSTRAINT FK_EXHIBICION_ESPACIO_PUBLICITARIO
        FOREIGN KEY (id_espacio) REFERENCES Publicidad.ESPACIO_PUBLICITARIO (id_espacio),
    CONSTRAINT FK_EXHIBICION_PIEZA_PUBLICITARIA
        FOREIGN KEY (id_pieza) REFERENCES Publicidad.PIEZA_PUBLICITARIA (id_pieza),
    CONSTRAINT UQ_EXHIBICION_partido_pieza UNIQUE (id_partido, id_pieza),
    CONSTRAINT CK_EXHIBICION_costo CHECK (costo >= 0),
    CONSTRAINT CK_EXHIBICION_codigo_moneda CHECK (codigo_moneda LIKE '[A-Z][A-Z][A-Z]')
);
GO


/* ============================================================================
   INDICES
   Regla: un indice por cada clave foranea que no sea la primera columna de
   la PK o de un UNIQUE (esas ya tienen el suyo). SQL Server no los crea
   solo. Sirven a los JOIN de las vistas y los SP, y a las bajas: al borrar
   una fila, SQL Server busca en cada tabla hija para validar la FK, y los SP
   de baja cuentan las referencias antes de borrar. Sin el indice, cada una
   de esas busquedas recorre la tabla hija completa.
   Los indices unicos filtrados (UX_) estan junto a su tabla: son reglas de
   negocio, no indices de busqueda.
   ============================================================================ */
CREATE INDEX IX_SEDE_id_pais                        ON Torneo.SEDE (id_pais);
CREATE INDEX IX_JUGADOR_id_pais_nacimiento          ON Torneo.JUGADOR (id_pais_nacimiento);
CREATE INDEX IX_PERSONA_CUERPO_TECNICO_id_seleccion ON Torneo.PERSONA_CUERPO_TECNICO (id_seleccion);
CREATE INDEX IX_PERSONA_CUERPO_TECNICO_id_pais_nacimiento
    ON Torneo.PERSONA_CUERPO_TECNICO (id_pais_nacimiento);
CREATE INDEX IX_PARTIDO_id_sede                     ON Torneo.PARTIDO (id_sede);
CREATE INDEX IX_PARTIDO_id_seleccion_local          ON Torneo.PARTIDO (id_seleccion_local);
CREATE INDEX IX_PARTIDO_id_seleccion_visitante      ON Torneo.PARTIDO (id_seleccion_visitante);
GO

CREATE INDEX IX_FORMACION_id_seleccion              ON DesarrolloPartido.FORMACION (id_seleccion);
CREATE INDEX IX_ALINEACION_id_jugador               ON DesarrolloPartido.ALINEACION (id_jugador);
CREATE INDEX IX_CAMBIO_id_jugador_sale              ON DesarrolloPartido.CAMBIO (id_jugador_sale);
CREATE INDEX IX_CAMBIO_id_jugador_entra             ON DesarrolloPartido.CAMBIO (id_jugador_entra);
CREATE INDEX IX_GOL_id_partido                      ON DesarrolloPartido.GOL (id_partido);
CREATE INDEX IX_GOL_id_jugador_autor                ON DesarrolloPartido.GOL (id_jugador_autor);
CREATE INDEX IX_GOL_id_jugador_asistencia           ON DesarrolloPartido.GOL (id_jugador_asistencia);
CREATE INDEX IX_GOL_id_tipo_gol                     ON DesarrolloPartido.GOL (id_tipo_gol);
CREATE INDEX IX_AMONESTACION_id_partido             ON DesarrolloPartido.AMONESTACION (id_partido);
CREATE INDEX IX_AMONESTACION_id_jugador             ON DesarrolloPartido.AMONESTACION (id_jugador);
CREATE INDEX IX_AMONESTACION_id_persona_ct          ON DesarrolloPartido.AMONESTACION (id_persona_ct);
GO

CREATE INDEX IX_ARBITRO_IDIOMA_id_idioma            ON Arbitraje.ARBITRO_IDIOMA (id_idioma);
CREATE INDEX IX_DESIGNACION_ARBITRAL_id_arbitro     ON Arbitraje.DESIGNACION_ARBITRAL (id_arbitro);
GO

CREATE INDEX IX_ANUNCIANTE_id_pais                  ON Publicidad.ANUNCIANTE (id_pais);
CREATE INDEX IX_PIEZA_PUBLICITARIA_id_idioma        ON Publicidad.PIEZA_PUBLICITARIA (id_idioma);
CREATE INDEX IX_PIEZA_PAIS_INTERES_id_pais          ON Publicidad.PIEZA_PAIS_INTERES (id_pais);
CREATE INDEX IX_EXHIBICION_id_espacio               ON Publicidad.EXHIBICION (id_espacio);
CREATE INDEX IX_EXHIBICION_id_pieza                 ON Publicidad.EXHIBICION (id_pieza);
GO


-- Evidencia: tablas creadas por esquema.
SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;
GO
