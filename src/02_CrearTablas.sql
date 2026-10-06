/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: COMPLETAR    Grupo: COMPLETAR
 Integrantes:
   COMPLETAR Apellido, Nombre - usuario GitHub COMPLETAR
   COMPLETAR Apellido, Nombre - usuario GitHub COMPLETAR
 Fecha: 06/10/2026
 Archivo: 02_CrearTablas.sql
 Objetivo: Crear tablas y restricciones, incluyendo las relaciones de publicidad
 del DER y los atributos requeridos por las secciones H, I y J del enunciado.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. Eliminación de tablas existentes (orden inverso a las dependencias)
   ============================================================================= */
DROP TRIGGER IF EXISTS torneo.TR_Seleccion_CrearListaConvocados;
-- Estos triggers pertenecen a tablas deportivas, pero dependen de publicidad.
DROP TRIGGER IF EXISTS torneo.TR_Partido_SedePublicidad;
DROP TABLE IF EXISTS publicidad.EXHIBICION;
DROP TABLE IF EXISTS publicidad.INTERES;
DROP TABLE IF EXISTS publicidad.PIEZA_PUBLICITARIA;
DROP TABLE IF EXISTS publicidad.FRANJA;
DROP TABLE IF EXISTS publicidad.CAMPAÑA;
DROP TABLE IF EXISTS publicidad.ANUNCIANTE;
DROP TABLE IF EXISTS publicidad.ESPACIO_PUBLICITARIO;
DROP TABLE IF EXISTS importacion.ERROR_IMPORTACION;
DROP TABLE IF EXISTS importacion.LOTE;
DROP TABLE IF EXISTS arbitraje.INFORME_ARBITRAL;
DROP TABLE IF EXISTS arbitraje.DESIGNACION_DESCARTADA;
DROP TABLE IF EXISTS arbitraje.DIRIGE;
DROP TABLE IF EXISTS arbitraje.HABLA;
DROP TABLE IF EXISTS arbitraje.IDIOMA;
DROP TABLE IF EXISTS arbitraje.ARBITRO;
DROP TABLE IF EXISTS partido.SUSPENSION;
DROP TABLE IF EXISTS partido.AMONESTACION;
DROP TABLE IF EXISTS partido.GOL;
DROP TABLE IF EXISTS partido.TIPO_GOL;
DROP TABLE IF EXISTS partido.CAMBIO;
DROP TABLE IF EXISTS partido.ALINEACION;
DROP TABLE IF EXISTS partido.FORMACION;
DROP TABLE IF EXISTS plantel.CONVOCA;
DROP TABLE IF EXISTS plantel.LISTA_CONVOCADOS;
DROP TABLE IF EXISTS plantel.PERSONA_CUERPO_TECNICO;
DROP TABLE IF EXISTS plantel.JUGADOR;
DROP TABLE IF EXISTS torneo.PARTIDO;
DROP TABLE IF EXISTS torneo.SELECCION;
DROP TABLE IF EXISTS torneo.FASE;
DROP TABLE IF EXISTS torneo.SEDE;
DROP TABLE IF EXISTS torneo.INDICADOR_ECONOMICO;
DROP TABLE IF EXISTS torneo.PAIS;
DROP TABLE IF EXISTS config.PARAMETRO;
GO

/* =============================================================================
   2. Esquema config
   ============================================================================= */

-- Parámetros del reglamento vigente (cupos de convocatoria, cambios, suspensiones).
CREATE TABLE config.PARAMETRO
(
    Clave       VARCHAR(60)   NOT NULL,
    Valor       INT           NOT NULL,
    Descripcion NVARCHAR(200) NOT NULL,
    CONSTRAINT PK_Parametro PRIMARY KEY (Clave),
    CONSTRAINT CK_Parametro_Valor CHECK (Valor >= 0)
);
GO

/* =============================================================================
   3. Esquema torneo
   ============================================================================= */

-- País o mercado. CodigoFIFA es la clave natural (Inglaterra y Escocia comparten
-- el código ISO GBR pero son miembros FIFA distintos). Los códigos ISO se usan
-- para cruzar datos con APIs externas y ZonaHoraria para el cálculo de prime time.
CREATE TABLE torneo.PAIS
(
    IdPais      INT IDENTITY(1,1) NOT NULL,
    Nombre      NVARCHAR(60)      NOT NULL,
    CodigoFIFA  CHAR(3)           NOT NULL,
    CodigoISO2  CHAR(2)           NULL,
    CodigoISO3  CHAR(3)           NULL,
    ZonaHoraria VARCHAR(50)       NULL,
    CONSTRAINT PK_Pais PRIMARY KEY (IdPais),
    CONSTRAINT UQ_Pais_Nombre UNIQUE (Nombre),
    CONSTRAINT UQ_Pais_CodigoFIFA UNIQUE (CodigoFIFA),
    CONSTRAINT CK_Pais_CodigoFIFA CHECK (CodigoFIFA LIKE '[A-Z][A-Z][A-Z]'),
    CONSTRAINT CK_Pais_CodigoISO2 CHECK (CodigoISO2 IS NULL OR CodigoISO2 LIKE '[A-Z][A-Z]'),
    CONSTRAINT CK_Pais_CodigoISO3 CHECK (CodigoISO3 IS NULL OR CodigoISO3 LIKE '[A-Z][A-Z][A-Z]')
);
GO

-- PBI per cápita anual de cada país (proxy del poder adquisitivo del mercado).
CREATE TABLE torneo.INDICADOR_ECONOMICO
(
    IdIndicadorEconomico INT IDENTITY(1,1) NOT NULL,
    IdPais               INT               NOT NULL,
    Anio                 SMALLINT          NOT NULL,
    PbiPerCapitaUSD      DECIMAL(12,2)     NOT NULL,
    CONSTRAINT PK_IndicadorEconomico PRIMARY KEY (IdIndicadorEconomico),
    CONSTRAINT FK_IndicadorEconomico_Pais FOREIGN KEY (IdPais) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT UQ_IndicadorEconomico_PaisAnio UNIQUE (IdPais, Anio),
    CONSTRAINT CK_IndicadorEconomico_Anio CHECK (Anio BETWEEN 1960 AND 2100),
    CONSTRAINT CK_IndicadorEconomico_Pbi CHECK (PbiPerCapitaUSD > 0)
);
GO

-- Estadio sede. ZonaHoraria usa los nombres de sys.time_zone_info
-- (por ejemplo 'Eastern Standard Time') para convertir UTC a hora local.
CREATE TABLE torneo.SEDE
(
    IdSede        INT IDENTITY(1,1) NOT NULL,
    NombreEstadio NVARCHAR(80)      NOT NULL,
    Ciudad        NVARCHAR(60)      NOT NULL,
    IdPais        INT               NOT NULL,
    Capacidad     INT               NOT NULL,
    ZonaHoraria   VARCHAR(50)       NOT NULL,
    CONSTRAINT PK_Sede PRIMARY KEY (IdSede),
    CONSTRAINT FK_Sede_Pais FOREIGN KEY (IdPais) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT UQ_Sede_NombreEstadio UNIQUE (NombreEstadio),
    CONSTRAINT CK_Sede_Capacidad CHECK (Capacidad BETWEEN 1000 AND 200000)
);
GO

-- Fases del torneo. Orden permite comparar fases ("a partir de dieciseisavos")
-- y AnulaAmarillas parametriza en qué fases se limpian las amarillas simples.
CREATE TABLE torneo.FASE
(
    IdFase         TINYINT IDENTITY(1,1) NOT NULL,
    Nombre         NVARCHAR(30)          NOT NULL,
    Orden          TINYINT               NOT NULL,
    EsEliminatoria BIT                   NOT NULL,
    AnulaAmarillas BIT                   NOT NULL CONSTRAINT DF_Fase_AnulaAmarillas DEFAULT (0),
    CONSTRAINT PK_Fase PRIMARY KEY (IdFase),
    CONSTRAINT UQ_Fase_Nombre UNIQUE (Nombre),
    CONSTRAINT UQ_Fase_Orden UNIQUE (Orden),
    CONSTRAINT CK_Fase_Orden CHECK (Orden BETWEEN 1 AND 20)
);
GO

-- Selección participante (relación 1:1 con PAIS). FechaConfirmacionLista indica
-- que la lista de convocados fue validada contra el reglamento.
CREATE TABLE torneo.SELECCION
(
    IdSeleccion            INT IDENTITY(1,1) NOT NULL,
    IdPais                 INT               NOT NULL,
    Confederacion          VARCHAR(10)       NOT NULL,
    GrupoAsignado          CHAR(1)           NOT NULL,
    FechaConfirmacionLista DATETIME2(0)      NULL,
    CONSTRAINT PK_Seleccion PRIMARY KEY (IdSeleccion),
    CONSTRAINT FK_Seleccion_Pais FOREIGN KEY (IdPais) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT UQ_Seleccion_Pais UNIQUE (IdPais),
    CONSTRAINT CK_Seleccion_Confederacion CHECK (Confederacion IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')),
    CONSTRAINT CK_Seleccion_Grupo CHECK (GrupoAsignado LIKE '[A-L]')
);
GO

-- Partido. Se guarda la fecha y hora en UTC; la hora local de la sede se
-- calcula con torneo.fnUtcAHoraLocal. El resultado se descompone en goles,
-- alargue y penales para poder validarlo y explotarlo en reportes.
CREATE TABLE torneo.PARTIDO
(
    IdPartido            INT IDENTITY(1,1) NOT NULL,
    NumeroPartido        SMALLINT          NULL,
    IdFase               TINYINT           NOT NULL,
    IdSede               INT               NOT NULL,
    FechaHoraUTC         DATETIME2(0)      NOT NULL,
    IdSeleccionLocal     INT               NOT NULL,
    IdSeleccionVisitante INT               NOT NULL,
    Estado               VARCHAR(12)       NOT NULL CONSTRAINT DF_Partido_Estado DEFAULT ('Programado'),
    GolesLocal           TINYINT           NULL,
    GolesVisitante       TINYINT           NULL,
    HuboAlargue          BIT               NOT NULL CONSTRAINT DF_Partido_HuboAlargue DEFAULT (0),
    PenalesLocal         TINYINT           NULL,
    PenalesVisitante     TINYINT           NULL,
    Asistencia           INT               NULL,
    CONSTRAINT PK_Partido PRIMARY KEY (IdPartido),
    CONSTRAINT FK_Partido_Fase FOREIGN KEY (IdFase) REFERENCES torneo.FASE (IdFase),
    CONSTRAINT FK_Partido_Sede FOREIGN KEY (IdSede) REFERENCES torneo.SEDE (IdSede),
    CONSTRAINT FK_Partido_SeleccionLocal FOREIGN KEY (IdSeleccionLocal) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT FK_Partido_SeleccionVisitante FOREIGN KEY (IdSeleccionVisitante) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT CK_Partido_NumeroPartido CHECK (NumeroPartido IS NULL OR NumeroPartido BETWEEN 1 AND 200),
    CONSTRAINT CK_Partido_Selecciones CHECK (IdSeleccionLocal <> IdSeleccionVisitante),
    CONSTRAINT CK_Partido_Estado CHECK (Estado IN ('Programado', 'En juego', 'Finalizado')),
    CONSTRAINT CK_Partido_Resultado CHECK (
           (Estado = 'Finalizado' AND GolesLocal IS NOT NULL AND GolesVisitante IS NOT NULL)
        OR (Estado <> 'Finalizado' AND GolesLocal IS NULL AND GolesVisitante IS NULL
            AND HuboAlargue = 0 AND PenalesLocal IS NULL AND PenalesVisitante IS NULL)),
    CONSTRAINT CK_Partido_Penales CHECK (
           (PenalesLocal IS NULL AND PenalesVisitante IS NULL)
        OR (PenalesLocal IS NOT NULL AND PenalesVisitante IS NOT NULL AND PenalesLocal <> PenalesVisitante
            AND HuboAlargue = 1 AND GolesLocal IS NOT NULL AND GolesLocal = GolesVisitante)),
    CONSTRAINT CK_Partido_Asistencia CHECK (Asistencia IS NULL OR Asistencia >= 0)
);
GO

CREATE UNIQUE INDEX UX_Partido_NumeroPartido ON torneo.PARTIDO (NumeroPartido) WHERE NumeroPartido IS NOT NULL;
CREATE INDEX IX_Partido_FechaHoraUTC ON torneo.PARTIDO (FechaHoraUTC);
CREATE INDEX IX_Partido_SeleccionLocal ON torneo.PARTIDO (IdSeleccionLocal);
CREATE INDEX IX_Partido_SeleccionVisitante ON torneo.PARTIDO (IdSeleccionVisitante);
CREATE INDEX IX_Partido_SedeFechaHoraUTC ON torneo.PARTIDO (IdSede, FechaHoraUTC);
CREATE INDEX IX_Partido_Fase ON torneo.PARTIDO (IdFase);
GO

/* =============================================================================
   4. Esquema plantel
   ============================================================================= */

-- JUGADOR. IdPaisNacionalidad implementa la relación "nació en" con PAIS y
-- reemplaza al atributo redundante "nacionalidad" del DER.
CREATE TABLE plantel.JUGADOR
(
    IdJugador          INT IDENTITY(1,1) NOT NULL,
    Nombre             NVARCHAR(60)      NOT NULL,
    Apellido           NVARCHAR(60)      NOT NULL,
    FechaNacimiento    DATE              NULL,
    IdPaisNacionalidad INT               NOT NULL,
    Club               NVARCHAR(80)      NOT NULL,
    PosicionHabitual   NVARCHAR(15)      NOT NULL,
    CONSTRAINT PK_Jugador PRIMARY KEY (IdJugador),
    CONSTRAINT FK_Jugador_Pais FOREIGN KEY (IdPaisNacionalidad) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT CK_Jugador_FechaNacimiento CHECK (FechaNacimiento IS NULL OR FechaNacimiento >= '19000101'),
    CONSTRAINT CK_Jugador_Posicion CHECK (PosicionHabitual IN (N'Arquero', N'Defensor', N'Mediocampista', N'Delantero'))
);
GO

-- Búsqueda por país y nombre (control de jugadores duplicados).
CREATE INDEX IX_Jugador_PaisApellidoNombre ON plantel.JUGADOR (IdPaisNacionalidad, Apellido, Nombre);
GO

-- PERSONA_CUERPO_TECNICO. Cada selección tiene un único director técnico.
CREATE TABLE plantel.PERSONA_CUERPO_TECNICO
(
    IdCuerpoTecnico    INT IDENTITY(1,1) NOT NULL,
    Nombre             NVARCHAR(60)      NOT NULL,
    Apellido           NVARCHAR(60)      NOT NULL,
    FechaNacimiento    DATE              NULL,
    IdPaisNacionalidad INT               NOT NULL,
    IdSeleccion        INT               NOT NULL,
    Rol                NVARCHAR(30)      NOT NULL,
    CONSTRAINT PK_CuerpoTecnico PRIMARY KEY (IdCuerpoTecnico),
    CONSTRAINT FK_CuerpoTecnico_Pais FOREIGN KEY (IdPaisNacionalidad) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT FK_CuerpoTecnico_Seleccion FOREIGN KEY (IdSeleccion) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT CK_CuerpoTecnico_FechaNacimiento CHECK (FechaNacimiento IS NULL OR FechaNacimiento >= '19000101'),
    CONSTRAINT CK_CuerpoTecnico_Rol CHECK (Rol IN (N'Director técnico', N'Ayudante técnico', N'Preparador físico', N'Entrenador de arqueros'))
);
GO

CREATE UNIQUE INDEX UX_CuerpoTecnico_DirectorTecnico ON plantel.PERSONA_CUERPO_TECNICO (IdSeleccion) WHERE Rol = N'Director técnico';
CREATE INDEX IX_CuerpoTecnico_Seleccion ON plantel.PERSONA_CUERPO_TECNICO (IdSeleccion);
CREATE INDEX IX_CuerpoTecnico_Pais ON plantel.PERSONA_CUERPO_TECNICO (IdPaisNacionalidad);
GO

-- LISTA_CONVOCADOS: entidad del DER con relación 1:1 con SELECCION.
-- Se usa una clave primaria compartida: IdSeleccion identifica también su lista.
CREATE TABLE plantel.LISTA_CONVOCADOS
(
    IdSeleccion INT NOT NULL,
    CONSTRAINT PK_LISTA_CONVOCADOS PRIMARY KEY (IdSeleccion),
    CONSTRAINT FK_LISTA_CONVOCADOS_SELECCION FOREIGN KEY (IdSeleccion) REFERENCES torneo.SELECCION (IdSeleccion) ON DELETE CASCADE
);
GO

-- Cada selección tiene una lista, inicialmente vacía. El trigger crea su
-- identidad al registrar la selección mediante los SP existentes; funciona
-- también para inserciones de varias selecciones en una misma sentencia.
-- Si se elimina una selección sin historial, se elimina su lista vacía en
-- cascada; la FK de CONVOCA impide borrar listas con convocados históricos.
CREATE OR ALTER TRIGGER torneo.TR_Seleccion_CrearListaConvocados
ON torneo.SELECCION
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO plantel.LISTA_CONVOCADOS (IdSeleccion)
    SELECT IdSeleccion FROM inserted;
END;
GO

-- CONVOCA: relación 1:N entre LISTA_CONVOCADOS y JUGADOR del DER.
-- Pertenencia de un jugador a la lista de convocados de una selección.
-- Cada fila registra el alta (fecha y motivo) y, si corresponde, la baja,
-- lo que conserva el historial de altas y bajas de último momento.
-- Un jugador solo puede estar activo (sin baja) en una lista y el dorsal
-- no puede repetirse entre los convocados activos de una misma selección.
CREATE TABLE plantel.CONVOCA
(
    IdConvocatoria INT IDENTITY(1,1) NOT NULL,
    IdSeleccion    INT               NOT NULL,
    IdJugador      INT               NOT NULL,
    Dorsal         TINYINT           NOT NULL,
    FechaAlta      DATE              NOT NULL,
    MotivoAlta     NVARCHAR(150)     NOT NULL CONSTRAINT DF_Convocatoria_MotivoAlta DEFAULT (N'Lista inicial'),
    FechaBaja      DATE              NULL,
    MotivoBaja     NVARCHAR(150)     NULL,
    CONSTRAINT PK_Convocatoria PRIMARY KEY (IdConvocatoria),
    CONSTRAINT FK_Convocatoria_ListaConvocados FOREIGN KEY (IdSeleccion) REFERENCES plantel.LISTA_CONVOCADOS (IdSeleccion),
    CONSTRAINT FK_Convocatoria_Jugador FOREIGN KEY (IdJugador) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT CK_Convocatoria_Dorsal CHECK (Dorsal BETWEEN 1 AND 99),
    CONSTRAINT CK_Convocatoria_Baja CHECK (
           (FechaBaja IS NULL AND MotivoBaja IS NULL)
        OR (FechaBaja IS NOT NULL AND MotivoBaja IS NOT NULL AND FechaBaja >= FechaAlta))
);
GO

CREATE UNIQUE INDEX UX_Convocatoria_JugadorActivo ON plantel.CONVOCA (IdJugador) WHERE FechaBaja IS NULL;
CREATE UNIQUE INDEX UX_Convocatoria_DorsalActivo ON plantel.CONVOCA (IdSeleccion, Dorsal) WHERE FechaBaja IS NULL;
CREATE INDEX IX_Convocatoria_Jugador ON plantel.CONVOCA (IdJugador);
GO

/* =============================================================================
   5. Esquema partido
   ============================================================================= */

-- Formación de una selección en un partido (una por selección y partido).
CREATE TABLE partido.FORMACION
(
    IdFormacion    INT IDENTITY(1,1) NOT NULL,
    IdPartido      INT               NOT NULL,
    IdSeleccion    INT               NOT NULL,
    EsquemaTactico VARCHAR(12)       NOT NULL,
    CONSTRAINT PK_Formacion PRIMARY KEY (IdFormacion),
    CONSTRAINT FK_Formacion_Partido FOREIGN KEY (IdPartido) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT FK_Formacion_Seleccion FOREIGN KEY (IdSeleccion) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT UQ_Formacion_PartidoSeleccion UNIQUE (IdPartido, IdSeleccion),
    CONSTRAINT CK_Formacion_Esquema CHECK (EsquemaTactico LIKE '[1-9]-[1-9]%')
);
GO

-- Relación N:M "alineación" entre FORMACION y JUGADOR: titulares (con posición
-- en cancha) y suplentes disponibles en el banco.
CREATE TABLE partido.ALINEACION
(
    IdFormacion INT          NOT NULL,
    IdJugador   INT          NOT NULL,
    EsTitular   BIT          NOT NULL,
    Posicion    NVARCHAR(15) NULL,
    CONSTRAINT PK_Alineacion PRIMARY KEY (IdFormacion, IdJugador),
    CONSTRAINT FK_Alineacion_Formacion FOREIGN KEY (IdFormacion) REFERENCES partido.FORMACION (IdFormacion),
    CONSTRAINT FK_Alineacion_Jugador FOREIGN KEY (IdJugador) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT CK_Alineacion_Posicion CHECK (Posicion IS NULL OR Posicion IN (N'Arquero', N'Defensor', N'Mediocampista', N'Delantero')),
    CONSTRAINT CK_Alineacion_TitularConPosicion CHECK (EsTitular = 0 OR Posicion IS NOT NULL)
);
GO

CREATE INDEX IX_Alineacion_Jugador ON partido.ALINEACION (IdJugador);
GO

-- Sustitución. La clave foránea compuesta contra Formacion garantiza que la
-- selección tenga formación registrada en ese partido. Los cambios hechos en
-- un entretiempo (minutos 46, 91 o 106) no consumen ventana de cambios.
CREATE TABLE partido.CAMBIO
(
    IdCambio        INT IDENTITY(1,1) NOT NULL,
    IdPartido       INT               NOT NULL,
    IdSeleccion     INT               NOT NULL,
    IdJugadorSale   INT               NOT NULL,
    IdJugadorEntra  INT               NOT NULL,
    Minuto          TINYINT           NOT NULL,
    MinutoAdicional TINYINT           NOT NULL CONSTRAINT DF_Cambio_MinutoAdicional DEFAULT (0),
    EnEntretiempo   BIT               NOT NULL CONSTRAINT DF_Cambio_EnEntretiempo DEFAULT (0),
    Motivo          NVARCHAR(12)      NOT NULL,
    CONSTRAINT PK_Cambio PRIMARY KEY (IdCambio),
    CONSTRAINT FK_Cambio_Formacion FOREIGN KEY (IdPartido, IdSeleccion) REFERENCES partido.FORMACION (IdPartido, IdSeleccion),
    CONSTRAINT FK_Cambio_JugadorSale FOREIGN KEY (IdJugadorSale) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT FK_Cambio_JugadorEntra FOREIGN KEY (IdJugadorEntra) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT UQ_Cambio_JugadorSale UNIQUE (IdPartido, IdJugadorSale),
    CONSTRAINT UQ_Cambio_JugadorEntra UNIQUE (IdPartido, IdJugadorEntra),
    CONSTRAINT CK_Cambio_Jugadores CHECK (IdJugadorSale <> IdJugadorEntra),
    CONSTRAINT CK_Cambio_Minuto CHECK (Minuto BETWEEN 1 AND 120 AND MinutoAdicional <= 30),
    CONSTRAINT CK_Cambio_Entretiempo CHECK (EnEntretiempo = 0 OR (Minuto IN (46, 91, 106) AND MinutoAdicional = 0)),
    CONSTRAINT CK_Cambio_Motivo CHECK (Motivo IN (N'Táctico', N'Lesión', N'Precaución'))
);
GO

-- Tipo de gol (jugada, penal, tiro libre, cabezazo, en contra, etc.).
CREATE TABLE partido.TIPO_GOL
(
    IdTipoGol         TINYINT IDENTITY(1,1) NOT NULL,
    Descripcion       NVARCHAR(30)          NOT NULL,
    EsEnContra        BIT                   NOT NULL CONSTRAINT DF_TipoGol_EsEnContra DEFAULT (0),
    PermiteAsistencia BIT                   NOT NULL CONSTRAINT DF_TipoGol_PermiteAsistencia DEFAULT (1),
    CONSTRAINT PK_TipoGol PRIMARY KEY (IdTipoGol),
    CONSTRAINT UQ_TipoGol_Descripcion UNIQUE (Descripcion),
    CONSTRAINT CK_TipoGol_EnContraSinAsistencia CHECK (EsEnContra = 0 OR PermiteAsistencia = 0)
);
GO

-- Gol. IdSeleccion es la selección a la que se le computa el gol (en un gol en
-- contra es la rival del autor). Los goles de la definición por penales se
-- registran con su período y no cuentan para el marcador ni para goleadores.
CREATE TABLE partido.GOL
(
    IdGol               INT IDENTITY(1,1) NOT NULL,
    IdPartido           INT               NOT NULL,
    IdSeleccion         INT               NOT NULL,
    IdJugadorAutor      INT               NOT NULL,
    IdJugadorAsistencia INT               NULL,
    IdTipoGol           TINYINT           NOT NULL,
    Periodo             NVARCHAR(25)      NOT NULL,
    Minuto              TINYINT           NULL,
    MinutoAdicional     TINYINT           NOT NULL CONSTRAINT DF_Gol_MinutoAdicional DEFAULT (0),
    CONSTRAINT PK_Gol PRIMARY KEY (IdGol),
    CONSTRAINT FK_Gol_Partido FOREIGN KEY (IdPartido) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT FK_Gol_Seleccion FOREIGN KEY (IdSeleccion) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT FK_Gol_JugadorAutor FOREIGN KEY (IdJugadorAutor) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT FK_Gol_JugadorAsistencia FOREIGN KEY (IdJugadorAsistencia) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT FK_Gol_TipoGol FOREIGN KEY (IdTipoGol) REFERENCES partido.TIPO_GOL (IdTipoGol),
    CONSTRAINT CK_Gol_Asistencia CHECK (IdJugadorAsistencia IS NULL OR IdJugadorAsistencia <> IdJugadorAutor),
    CONSTRAINT CK_Gol_Periodo CHECK (
           (Periodo = N'Primer tiempo' AND Minuto IS NOT NULL AND Minuto BETWEEN 1 AND 45 AND MinutoAdicional = 0)
        OR (Periodo = N'Segundo tiempo' AND Minuto IS NOT NULL AND Minuto BETWEEN 46 AND 90 AND MinutoAdicional = 0)
        OR (Periodo = N'Adicionales' AND Minuto IS NOT NULL AND Minuto IN (45, 90) AND MinutoAdicional BETWEEN 1 AND 30)
        OR (Periodo = N'Alargue' AND Minuto IS NOT NULL AND Minuto BETWEEN 91 AND 120
            AND (MinutoAdicional = 0 OR (Minuto IN (105, 120) AND MinutoAdicional <= 30)))
        OR (Periodo = N'Definición por penales' AND Minuto IS NULL AND MinutoAdicional = 0))
);
GO

CREATE INDEX IX_Gol_Partido ON partido.GOL (IdPartido);
CREATE INDEX IX_Gol_JugadorAutor ON partido.GOL (IdJugadorAutor);
GO

-- AMONESTACION: tarjeta amarilla o roja que recibe un jugador o un integrante
-- del cuerpo técnico (exactamente uno de los dos, como en el DER). Toda roja
-- indica si la expulsión fue por doble amarilla o roja directa.
CREATE TABLE partido.AMONESTACION
(
    IdTarjeta       INT IDENTITY(1,1) NOT NULL,
    IdPartido       INT               NOT NULL,
    IdSeleccion     INT               NOT NULL,
    IdJugador       INT               NULL,
    IdCuerpoTecnico INT               NULL,
    Color           NVARCHAR(8)       NOT NULL,
    TipoExpulsion   NVARCHAR(15)      NULL,
    Minuto          TINYINT           NOT NULL,
    MinutoAdicional TINYINT           NOT NULL CONSTRAINT DF_Tarjeta_MinutoAdicional DEFAULT (0),
    Motivo          NVARCHAR(150)     NOT NULL,
    CONSTRAINT PK_Tarjeta PRIMARY KEY (IdTarjeta),
    CONSTRAINT FK_Tarjeta_Partido FOREIGN KEY (IdPartido) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT FK_Tarjeta_Seleccion FOREIGN KEY (IdSeleccion) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT FK_Tarjeta_Jugador FOREIGN KEY (IdJugador) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT FK_Tarjeta_CuerpoTecnico FOREIGN KEY (IdCuerpoTecnico) REFERENCES plantel.PERSONA_CUERPO_TECNICO (IdCuerpoTecnico),
    CONSTRAINT CK_Tarjeta_Destinatario CHECK (
           (IdJugador IS NOT NULL AND IdCuerpoTecnico IS NULL)
        OR (IdJugador IS NULL AND IdCuerpoTecnico IS NOT NULL)),
    CONSTRAINT CK_Tarjeta_Color CHECK (Color IN (N'Amarilla', N'Roja')),
    CONSTRAINT CK_Tarjeta_TipoExpulsion CHECK (
           (Color = N'Amarilla' AND TipoExpulsion IS NULL)
        OR (Color = N'Roja' AND TipoExpulsion IS NOT NULL AND TipoExpulsion IN (N'Doble amarilla', N'Roja directa'))),
    CONSTRAINT CK_Tarjeta_Minuto CHECK (Minuto BETWEEN 1 AND 120 AND MinutoAdicional <= 30)
);
GO

CREATE INDEX IX_Tarjeta_JugadorPartido ON partido.AMONESTACION (IdJugador, IdPartido);
CREATE INDEX IX_Tarjeta_CuerpoTecnicoPartido ON partido.AMONESTACION (IdCuerpoTecnico, IdPartido);
CREATE INDEX IX_Tarjeta_Partido ON partido.AMONESTACION (IdPartido);
GO

-- Suspensión de un jugador o de un integrante del cuerpo técnico a partir de un
-- partido de origen. Se cumple en los siguientes CantidadPartidos partidos de su
-- selección; los partidos cumplidos se derivan del fixture, por lo que no se almacenan.
CREATE TABLE partido.SUSPENSION
(
    IdSuspension     INT IDENTITY(1,1) NOT NULL,
    IdJugador        INT               NULL,
    IdCuerpoTecnico  INT               NULL,
    IdSeleccion      INT               NOT NULL,
    IdPartidoOrigen  INT               NOT NULL,
    Causa            NVARCHAR(30)      NOT NULL,
    CantidadPartidos TINYINT           NOT NULL,
    FechaRegistro    DATETIME2(0)      NOT NULL CONSTRAINT DF_Suspension_FechaRegistro DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Suspension PRIMARY KEY (IdSuspension),
    CONSTRAINT FK_Suspension_Jugador FOREIGN KEY (IdJugador) REFERENCES plantel.JUGADOR (IdJugador),
    CONSTRAINT FK_Suspension_CuerpoTecnico FOREIGN KEY (IdCuerpoTecnico) REFERENCES plantel.PERSONA_CUERPO_TECNICO (IdCuerpoTecnico),
    CONSTRAINT FK_Suspension_Seleccion FOREIGN KEY (IdSeleccion) REFERENCES torneo.SELECCION (IdSeleccion),
    CONSTRAINT FK_Suspension_PartidoOrigen FOREIGN KEY (IdPartidoOrigen) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT CK_Suspension_Destinatario CHECK (
           (IdJugador IS NOT NULL AND IdCuerpoTecnico IS NULL)
        OR (IdJugador IS NULL AND IdCuerpoTecnico IS NOT NULL)),
    CONSTRAINT CK_Suspension_Causa CHECK (Causa IN (N'Acumulación de amarillas', N'Doble amarilla', N'Roja directa', N'Sanción disciplinaria')),
    CONSTRAINT CK_Suspension_Cantidad CHECK (CantidadPartidos BETWEEN 1 AND 20)
);
GO

-- Una sola suspensión por sancionado, partido de origen y causa.
CREATE UNIQUE INDEX UX_Suspension_JugadorPartidoCausa ON partido.SUSPENSION (IdJugador, IdPartidoOrigen, Causa) WHERE IdJugador IS NOT NULL;
CREATE UNIQUE INDEX UX_Suspension_CuerpoTecnicoPartidoCausa ON partido.SUSPENSION (IdCuerpoTecnico, IdPartidoOrigen, Causa) WHERE IdCuerpoTecnico IS NOT NULL;
GO

/* =============================================================================
   6. Esquema arbitraje
   ============================================================================= */

-- ARBITRO. El país que se controla en las designaciones es IdPaisNacionalidad
-- (relación "nació en" con PAIS).
CREATE TABLE arbitraje.ARBITRO
(
    IdArbitro          INT IDENTITY(1,1) NOT NULL,
    Nombre             NVARCHAR(60)      NOT NULL,
    Apellido           NVARCHAR(60)      NOT NULL,
    FechaNacimiento    DATE              NULL,
    IdPaisNacionalidad INT               NOT NULL,
    Categoria          NVARCHAR(15)      NOT NULL,
    Habilitado         BIT               NOT NULL CONSTRAINT DF_Arbitro_Habilitado DEFAULT (1),
    CONSTRAINT PK_Arbitro PRIMARY KEY (IdArbitro),
    CONSTRAINT FK_Arbitro_Pais FOREIGN KEY (IdPaisNacionalidad) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT CK_Arbitro_FechaNacimiento CHECK (FechaNacimiento IS NULL OR FechaNacimiento >= '19000101'),
    CONSTRAINT CK_Arbitro_Categoria CHECK (Categoria IN (N'FIFA', N'Confederación'))
);
GO

-- Búsqueda por país y nombre (control de duplicados e importación de árbitros).
CREATE INDEX IX_Arbitro_PaisApellidoNombre ON arbitraje.ARBITRO (IdPaisNacionalidad, Apellido, Nombre);
GO

CREATE TABLE arbitraje.IDIOMA
(
    IdIdioma SMALLINT IDENTITY(1,1) NOT NULL,
    Nombre   NVARCHAR(40)           NOT NULL,
    CONSTRAINT PK_Idioma PRIMARY KEY (IdIdioma),
    CONSTRAINT UQ_Idioma_Nombre UNIQUE (Nombre)
);
GO

-- HABLA materializa la relación "habla" del DER. El modelo existente permite
-- que un mismo idioma sea hablado por varios árbitros (N:M); la imagen indica
-- 1:N. Se documenta la diferencia sin alterar aquí los datos y SP existentes.
CREATE TABLE arbitraje.HABLA
(
    IdArbitro INT      NOT NULL,
    IdIdioma  SMALLINT NOT NULL,
    CONSTRAINT PK_ArbitroIdioma PRIMARY KEY (IdArbitro, IdIdioma),
    CONSTRAINT FK_ArbitroIdioma_Arbitro FOREIGN KEY (IdArbitro) REFERENCES arbitraje.ARBITRO (IdArbitro),
    CONSTRAINT FK_ArbitroIdioma_Idioma FOREIGN KEY (IdIdioma) REFERENCES arbitraje.IDIOMA (IdIdioma)
);
GO

-- Relación N:M "dirige" entre ARBITRO y PARTIDO con el rol de la designación.
CREATE TABLE arbitraje.DIRIGE
(
    IdDesignacion    INT IDENTITY(1,1) NOT NULL,
    IdPartido        INT               NOT NULL,
    IdArbitro        INT               NOT NULL,
    Rol              NVARCHAR(15)      NOT NULL,
    FechaDesignacion DATETIME2(0)      NOT NULL CONSTRAINT DF_Designacion_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Designacion PRIMARY KEY (IdDesignacion),
    CONSTRAINT FK_Designacion_Partido FOREIGN KEY (IdPartido) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT FK_Designacion_Arbitro FOREIGN KEY (IdArbitro) REFERENCES arbitraje.ARBITRO (IdArbitro),
    CONSTRAINT UQ_Designacion_PartidoRol UNIQUE (IdPartido, Rol),
    CONSTRAINT UQ_Designacion_PartidoArbitro UNIQUE (IdPartido, IdArbitro),
    CONSTRAINT CK_Designacion_Rol CHECK (Rol IN (N'Principal', N'Asistente 1', N'Asistente 2', N'Cuarto árbitro', N'VAR'))
);
GO

CREATE INDEX IX_Designacion_Arbitro ON arbitraje.DIRIGE (IdArbitro);
GO

-- Registro histórico de designaciones rechazadas por el sistema (por ejemplo,
-- por conflicto de nacionalidad), para trazabilidad.
CREATE TABLE arbitraje.DESIGNACION_DESCARTADA
(
    IdDesignacionDescartada INT IDENTITY(1,1) NOT NULL,
    IdPartido               INT               NOT NULL,
    IdArbitro               INT               NOT NULL,
    Rol                     NVARCHAR(15)      NOT NULL,
    FechaIntento            DATETIME2(0)      NOT NULL CONSTRAINT DF_DesignacionDescartada_Fecha DEFAULT (SYSDATETIME()),
    Motivo                  NVARCHAR(1000)    NOT NULL,
    CONSTRAINT PK_DesignacionDescartada PRIMARY KEY (IdDesignacionDescartada),
    CONSTRAINT FK_DesignacionDescartada_Partido FOREIGN KEY (IdPartido) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT FK_DesignacionDescartada_Arbitro FOREIGN KEY (IdArbitro) REFERENCES arbitraje.ARBITRO (IdArbitro),
    CONSTRAINT CK_DesignacionDescartada_Rol CHECK (Rol IN (N'Principal', N'Asistente 1', N'Asistente 2', N'Cuarto árbitro', N'VAR'))
);
GO

-- Informes y sanciones post-partido que recibe un árbitro por una designación.
-- Una sanción inhabilita al árbitro para ser designado hasta FechaHastaSancion.
CREATE TABLE arbitraje.INFORME_ARBITRAL
(
    IdInformeArbitral INT IDENTITY(1,1) NOT NULL,
    IdDesignacion     INT               NOT NULL,
    Tipo              NVARCHAR(10)      NOT NULL,
    Fecha             DATE              NOT NULL,
    Detalle           NVARCHAR(1000)    NOT NULL,
    FechaHastaSancion DATE              NULL,
    CONSTRAINT PK_InformeArbitral PRIMARY KEY (IdInformeArbitral),
    CONSTRAINT FK_InformeArbitral_Designacion FOREIGN KEY (IdDesignacion) REFERENCES arbitraje.DIRIGE (IdDesignacion),
    CONSTRAINT CK_InformeArbitral_Tipo CHECK (Tipo IN (N'Informe', N'Sanción')),
    CONSTRAINT CK_InformeArbitral_Sancion CHECK (
           (Tipo = N'Informe' AND FechaHastaSancion IS NULL)
        OR (Tipo = N'Sanción' AND FechaHastaSancion IS NOT NULL AND FechaHastaSancion >= Fecha))
);
GO

CREATE INDEX IX_InformeArbitral_Designacion ON arbitraje.INFORME_ARBITRAL (IdDesignacion);
GO

/* =============================================================================
   7. Esquema importacion
   ============================================================================= */

-- Cabecera de cada ejecución de importación (archivo, página o API de origen).
CREATE TABLE importacion.LOTE
(
    IdLote            INT IDENTITY(1,1) NOT NULL,
    Origen            NVARCHAR(260)     NOT NULL,
    Entidad           NVARCHAR(50)      NOT NULL,
    FechaInicio       DATETIME2(0)      NOT NULL CONSTRAINT DF_Lote_FechaInicio DEFAULT (SYSDATETIME()),
    FechaFin          DATETIME2(0)      NULL,
    FilasLeidas       INT               NOT NULL CONSTRAINT DF_Lote_FilasLeidas DEFAULT (0),
    FilasInsertadas   INT               NOT NULL CONSTRAINT DF_Lote_FilasInsertadas DEFAULT (0),
    FilasActualizadas INT               NOT NULL CONSTRAINT DF_Lote_FilasActualizadas DEFAULT (0),
    FilasSinCambios   INT               NOT NULL CONSTRAINT DF_Lote_FilasSinCambios DEFAULT (0),
    FilasRechazadas   INT               NOT NULL CONSTRAINT DF_Lote_FilasRechazadas DEFAULT (0),
    CONSTRAINT PK_Lote PRIMARY KEY (IdLote),
    CONSTRAINT CK_Lote_Filas CHECK (FilasLeidas >= 0 AND FilasInsertadas >= 0 AND FilasActualizadas >= 0
                                    AND FilasSinCambios >= 0 AND FilasRechazadas >= 0),
    CONSTRAINT CK_Lote_Fechas CHECK (FechaFin IS NULL OR FechaFin >= FechaInicio)
);
GO

-- Detalle de las filas rechazadas en cada lote, con el motivo.
CREATE TABLE importacion.ERROR_IMPORTACION
(
    IdErrorImportacion INT IDENTITY(1,1) NOT NULL,
    IdLote             INT               NOT NULL,
    NumeroFila         INT               NOT NULL,
    Detalle            NVARCHAR(2048)    NOT NULL,
    CONSTRAINT PK_ErrorImportacion PRIMARY KEY (IdErrorImportacion),
    CONSTRAINT FK_ErrorImportacion_Lote FOREIGN KEY (IdLote) REFERENCES importacion.LOTE (IdLote) ON DELETE CASCADE,
    CONSTRAINT CK_ErrorImportacion_Fila CHECK (NumeroFila >= 0)
);
GO

CREATE INDEX IX_ErrorImportacion_Lote ON importacion.ERROR_IMPORTACION (IdLote);
GO

/*
    Tablas auxiliares que no son entidades del DER reducido:
      PARAMETRO: reglas parametrizables de convocatoria, cambios y suspensión.
      FASE: fases de partido exigidas en la sección A del enunciado.
      SUSPENSION: sanciones calculadas según la sección F.
      DESIGNACION_DESCARTADA: evidencia del rechazo por nacionalidad exigido
        en los casos obligatorios de la sección IV.
      INFORME_ARBITRAL: informes y sanciones post-partido de la sección G.
      LOTE / ERROR_IMPORTACION: trazabilidad de importaciones parciales (I).
      FRANJA: horario y tarifa de emisión requeridos en la sección H.
    Son ampliaciones del modelo lógico para cumplir el enunciado. Deben
    incorporarse al DER completo si se desea equivalencia con todas las tablas.
    AMONESTACION es la entidad del DER; DIRIGE, HABLA, ALINEACION, CONVOCA e
    INTERES son relaciones materializadas, no nuevas entidades del negocio.
*/

/* =============================================================================
   8. Esquema publicidad
   ============================================================================= */

/*
    Modelo acordado a partir del DER y de la sección H del enunciado:
      SEDE 1:N ESPACIO_PUBLICITARIO (lugares físicos de la sede).
      SEDE 1:N PARTIDO (ya implementada en torneo.PARTIDO).
      ANUNCIANTE 1:N CAMPAÑA; CAMPAÑA 1:N PIEZA_PUBLICITARIA.
      PIEZA_PUBLICITARIA N:M PAIS (mercados de interés).
      EXHIBICION representa la ternaria PARTIDO-ESPACIO-PIEZA (N:N:1):
        para cada partido y espacio se registra una única pieza.

    Atributos de negocio: país del anunciante (criterios de aceptación),
    contenido e idioma de la pieza, países de interés, franja de emisión y
    tarifa con su moneda (secciones H e I). Los nombres identifican al
    anunciante y la campaña; las claves y NumeroCupo son datos técnicos.
    No se agregan CUIT, contactos, presupuestos, vigencias ni tipos de panel.

    Se representa una pieza por espacio durante el partido, como se acordó.
    La franja es el horario local del mercado destino; si HoraInicio supera
    HoraFin, cruza medianoche. No se impone 19-23: el texto solo lo da como ejemplo.
    Los idiomas reutilizan el catálogo existente arbitraje.IDIOMA del DER.

    NumeroCupo 1-4 y su unicidad por partido garantizan COMO MAXIMO cuatro
    espacios ocupados. El SP de asignación debe registrar los cuatro dentro
    de una transacción y validar EXACTAMENTE cuatro al confirmar la pauta.
    No se limita a cuatro la cantidad de espacios físicos de una sede.
*/

CREATE TABLE publicidad.ESPACIO_PUBLICITARIO
(
    IdEspacioPublicitario INT IDENTITY(1,1) NOT NULL,
    IdSede                INT               NOT NULL,
    CONSTRAINT PK_EspacioPublicitario PRIMARY KEY (IdEspacioPublicitario),
    CONSTRAINT FK_EspacioPublicitario_Sede FOREIGN KEY (IdSede) REFERENCES torneo.SEDE (IdSede)
);
GO

CREATE INDEX IX_EspacioPublicitario_Sede ON publicidad.ESPACIO_PUBLICITARIO (IdSede);
GO

CREATE TABLE publicidad.ANUNCIANTE
(
    IdAnunciante INT IDENTITY(1,1) NOT NULL,
    Nombre       NVARCHAR(150)     NOT NULL,
    IdPais       INT               NOT NULL,
    CONSTRAINT PK_Anunciante PRIMARY KEY (IdAnunciante),
    CONSTRAINT FK_Anunciante_Pais FOREIGN KEY (IdPais) REFERENCES torneo.PAIS (IdPais),
    CONSTRAINT CK_Anunciante_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
);
GO

CREATE INDEX IX_Anunciante_Pais ON publicidad.ANUNCIANTE (IdPais);
GO

CREATE TABLE publicidad.CAMPAÑA
(
    IdCampania   INT IDENTITY(1,1) NOT NULL,
    IdAnunciante INT               NOT NULL,
    Nombre       NVARCHAR(150)     NOT NULL,
    CONSTRAINT PK_Campania PRIMARY KEY (IdCampania),
    CONSTRAINT FK_Campania_Anunciante FOREIGN KEY (IdAnunciante) REFERENCES publicidad.ANUNCIANTE (IdAnunciante),
    CONSTRAINT CK_Campania_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
);
GO

CREATE INDEX IX_Campania_Anunciante ON publicidad.CAMPAÑA (IdAnunciante);
GO

-- Horario de emisión y tarifa asociada a cada franja, requeridos en H.
-- La moneda permite interpretar el importe y convertirlo según I y J.
CREATE TABLE publicidad.FRANJA
(
    IdFranja   INT IDENTITY(1,1) NOT NULL,
    HoraInicio TIME(0)          NOT NULL,
    HoraFin    TIME(0)          NOT NULL,
    Tarifa     DECIMAL(18,2)    NOT NULL,
    Moneda     NVARCHAR(30)     NOT NULL,
    CONSTRAINT PK_Franja PRIMARY KEY (IdFranja),
    CONSTRAINT CK_Franja_Horario CHECK (HoraInicio <> HoraFin),
    CONSTRAINT CK_Franja_Tarifa CHECK (Tarifa >= 0),
    CONSTRAINT CK_Franja_Moneda CHECK (LEN(LTRIM(RTRIM(Moneda))) > 0)
);
GO

CREATE TABLE publicidad.PIEZA_PUBLICITARIA
(
    IdPiezaPublicitaria INT IDENTITY(1,1) NOT NULL,
    IdCampania          INT               NOT NULL,
    IdIdioma            SMALLINT          NOT NULL,
    IdFranja            INT               NOT NULL,
    Contenido           NVARCHAR(MAX)     NOT NULL,
    CONSTRAINT PK_PiezaPublicitaria PRIMARY KEY (IdPiezaPublicitaria),
    CONSTRAINT FK_PiezaPublicitaria_Campania FOREIGN KEY (IdCampania) REFERENCES publicidad.CAMPAÑA (IdCampania),
    CONSTRAINT FK_PiezaPublicitaria_Idioma FOREIGN KEY (IdIdioma) REFERENCES arbitraje.IDIOMA (IdIdioma),
    CONSTRAINT FK_PiezaPublicitaria_Franja FOREIGN KEY (IdFranja) REFERENCES publicidad.FRANJA (IdFranja),
    CONSTRAINT CK_PiezaPublicitaria_Contenido CHECK (LEN(LTRIM(RTRIM(Contenido))) > 0)
);
GO

CREATE INDEX IX_PiezaPublicitaria_Campania ON publicidad.PIEZA_PUBLICITARIA (IdCampania);
CREATE INDEX IX_PiezaPublicitaria_Idioma ON publicidad.PIEZA_PUBLICITARIA (IdIdioma);
CREATE INDEX IX_PiezaPublicitaria_Franja ON publicidad.PIEZA_PUBLICITARIA (IdFranja);
GO

-- Relación "interés" del DER: una pieza puede dirigirse a varios países.
CREATE TABLE publicidad.INTERES
(
    IdPiezaPublicitaria INT NOT NULL,
    IdPais              INT NOT NULL,
    CONSTRAINT PK_PiezaPaisInteres PRIMARY KEY (IdPiezaPublicitaria, IdPais),
    CONSTRAINT FK_PiezaPaisInteres_Pieza FOREIGN KEY (IdPiezaPublicitaria) REFERENCES publicidad.PIEZA_PUBLICITARIA (IdPiezaPublicitaria),
    CONSTRAINT FK_PiezaPaisInteres_Pais FOREIGN KEY (IdPais) REFERENCES torneo.PAIS (IdPais)
);
GO

CREATE INDEX IX_PiezaPaisInteres_Pais ON publicidad.INTERES (IdPais);
GO

-- Historial de piezas exhibidas. La sede se obtiene del partido y del espacio;
-- no se guarda nuevamente en la ternaria. TarifaAplicada y MonedaAplicada
-- conservan el importe histórico para facturar aunque cambie la tarifa vigente.
-- El SP de asignación debe copiar esos valores desde la franja de la pieza.
CREATE TABLE publicidad.EXHIBICION
(
    IdPartido             INT            NOT NULL,
    IdEspacioPublicitario INT            NOT NULL,
    IdPiezaPublicitaria   INT            NOT NULL,
    NumeroCupo            TINYINT        NOT NULL,
    TarifaAplicada        DECIMAL(18,2) NOT NULL,
    MonedaAplicada        NVARCHAR(30)   NOT NULL,
    CONSTRAINT PK_Exhibicion PRIMARY KEY (IdPartido, IdEspacioPublicitario),
    CONSTRAINT FK_Exhibicion_Partido FOREIGN KEY (IdPartido) REFERENCES torneo.PARTIDO (IdPartido),
    CONSTRAINT FK_Exhibicion_Espacio FOREIGN KEY (IdEspacioPublicitario) REFERENCES publicidad.ESPACIO_PUBLICITARIO (IdEspacioPublicitario),
    CONSTRAINT FK_Exhibicion_Pieza FOREIGN KEY (IdPiezaPublicitaria) REFERENCES publicidad.PIEZA_PUBLICITARIA (IdPiezaPublicitaria),
    CONSTRAINT UQ_Exhibicion_PartidoCupo UNIQUE (IdPartido, NumeroCupo),
    CONSTRAINT CK_Exhibicion_Cupo CHECK (NumeroCupo BETWEEN 1 AND 4),
    CONSTRAINT CK_Exhibicion_Tarifa CHECK (TarifaAplicada >= 0),
    CONSTRAINT CK_Exhibicion_Moneda CHECK (LEN(LTRIM(RTRIM(MonedaAplicada))) > 0)
);
GO

CREATE INDEX IX_Exhibicion_Espacio ON publicidad.EXHIBICION (IdEspacioPublicitario);
CREATE INDEX IX_Exhibicion_Pieza ON publicidad.EXHIBICION (IdPiezaPublicitaria);
GO

-- Un CHECK no puede consultar otras tablas. Estos triggers preservan que el
-- espacio y el partido pertenezcan a la misma sede, también al modificarla.
CREATE OR ALTER TRIGGER publicidad.TR_Exhibicion_MismaSede
ON publicidad.EXHIBICION
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN torneo.PARTIDO AS p WITH (UPDLOCK, HOLDLOCK) ON p.IdPartido = i.IdPartido
        INNER JOIN publicidad.ESPACIO_PUBLICITARIO AS ep WITH (UPDLOCK, HOLDLOCK)
            ON ep.IdEspacioPublicitario = i.IdEspacioPublicitario
        WHERE p.IdSede <> ep.IdSede
    )
        THROW 50001, N'[publicidad.EXHIBICION] El espacio publicitario debe pertenecer a la sede del partido.', 1;
END;
GO

CREATE OR ALTER TRIGGER publicidad.TR_EspacioPublicitario_Sede
ON publicidad.ESPACIO_PUBLICITARIO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(IdSede) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN publicidad.EXHIBICION AS e WITH (UPDLOCK, HOLDLOCK)
            ON e.IdEspacioPublicitario = i.IdEspacioPublicitario
        INNER JOIN torneo.PARTIDO AS p WITH (UPDLOCK, HOLDLOCK) ON p.IdPartido = e.IdPartido
        WHERE i.IdSede <> p.IdSede
    )
        THROW 50001, N'[publicidad.ESPACIO_PUBLICITARIO] La nueva sede es incompatible con las exhibiciones registradas.', 1;
END;
GO

CREATE OR ALTER TRIGGER torneo.TR_Partido_SedePublicidad
ON torneo.PARTIDO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(IdSede) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN publicidad.EXHIBICION AS e WITH (UPDLOCK, HOLDLOCK) ON e.IdPartido = i.IdPartido
        INNER JOIN publicidad.ESPACIO_PUBLICITARIO AS ep WITH (UPDLOCK, HOLDLOCK)
            ON ep.IdEspacioPublicitario = e.IdEspacioPublicitario
        WHERE i.IdSede <> ep.IdSede
    )
        THROW 50001, N'[torneo.PARTIDO] La nueva sede es incompatible con los espacios publicitarios de sus exhibiciones.', 1;
END;
GO

/* =============================================================================
   9. Tipos de tabla (parámetros con valores de tabla para operaciones masivas)
      Se crean solo si no existen: si un SP ya los referencia no se pueden borrar.
   ============================================================================= */

-- Alineación completa (titulares y suplentes) para partido.RegistrarFormacion.
IF TYPE_ID(N'partido.TipoAlineacion') IS NULL
    CREATE TYPE partido.TipoAlineacion AS TABLE
    (
        IdJugador INT          NOT NULL PRIMARY KEY,
        EsTitular BIT          NOT NULL,
        Posicion  NVARCHAR(15) NULL
    );
GO

-- Filas crudas de indicadores económicos (por ejemplo, API del Banco Mundial).
-- Las columnas son texto para poder detectar y reportar errores de formato.
IF TYPE_ID(N'importacion.TipoIndicadorEconomicoImportado') IS NULL
    CREATE TYPE importacion.TipoIndicadorEconomicoImportado AS TABLE
    (
        NumeroFila      INT          NOT NULL PRIMARY KEY,
        CodigoISO3      NVARCHAR(20) NULL,
        Anio            NVARCHAR(20) NULL,
        PbiPerCapitaUSD NVARCHAR(40) NULL
    );
GO

-- Filas crudas de árbitros (por ejemplo, scraping de la nómina de árbitros).
IF TYPE_ID(N'importacion.TipoArbitroImportado') IS NULL
    CREATE TYPE importacion.TipoArbitroImportado AS TABLE
    (
        NumeroFila      INT           NOT NULL PRIMARY KEY,
        Nombre          NVARCHAR(120) NULL,
        Apellido        NVARCHAR(120) NULL,
        CodigoFIFAPais  NVARCHAR(20)  NULL,
        Categoria       NVARCHAR(40)  NULL,
        FechaNacimiento NVARCHAR(30)  NULL
    );
GO

-- Evidencia: tablas creadas por esquema.
SELECT s.name AS Esquema, t.name AS Tabla
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;
GO
