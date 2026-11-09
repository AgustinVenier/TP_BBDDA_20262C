# Campañas publicitarias del Dossier Mundial

El [Dossier Mundial](https://dossiermundial.netlify.app/) es el catálogo de las campañas publicitarias del Mundial 2026 que publica Dossier ([dossiernet.com](https://dossiernet.com)), un medio del mercado publicitario argentino. De ahí salen los anunciantes, las campañas y las piezas reales que se cargan en `Publicidad.ANUNCIANTE`, `Publicidad.CAMPANIA`, `Publicidad.PIEZA_PUBLICITARIA` y `Publicidad.PIEZA_PAIS_INTERES`. Con esos datos la asignación de publicidad y los reportes de ocupación e ingresos muestran campañas reales, como pide la sección H de la consigna.

El 02/11/2026 tenía 75 campañas de 62 anunciantes.

## De dónde salen los datos

La página no trae las campañas en el HTML: muestra "Cargando campañas..." y las lee con JavaScript desde una base [Firebase Firestore](https://firebase.google.com/docs/firestore). En su código está la configuración pública de Firebase:

| Dato | Valor |
|---|---|
| Proyecto (`projectId`) | `repositorio2026-61a28` |
| Clave (`apiKey`) | `AIzaSyAvVQTFWTCHwSCMIS2le22ZQ6aQBv8oUgo` |
| Colección | `campanas` (`getDocs(collection(db, 'campanas'))`) |

La clave de una app web de Firebase no es secreta: va en el código que descarga cada visitante, y lo que se puede leer lo deciden las reglas de seguridad del proyecto. La colección `campanas` es de lectura pública, porque la lee la página sin pedir usuario. El sistema hace la misma lectura que cualquier visitante, por la [API REST de Firestore](https://firebase.google.com/docs/firestore/use-rest-api), sin credenciales ni datos de quien la ejecuta.

## Consumo desde SQL Server

`Publicidad.usp_ImportarCampaniasAPI` (`src/21_SP_Importar_Publicidad.sql`) hace un pedido GET con `DatosGenerales.usp_ConsumirAPI` (`src/22_SP_ConsumirAPI.sql`) y procesa la respuesta con `Publicidad.usp_ProcesarCampaniasJSON`. `src/31_Ejecutar_ImportarAPIs.sql` la ejecuta antes de los datos complementarios (`src/33_Ejecutar_DatosComplementarios.sql`), que asignan la publicidad de cada partido: así las piezas del Dossier compiten en esa asignación. El 33 agrega anunciantes de otros países, porque el Dossier cubre solo el mercado argentino.

Pedido:

```text
https://firestore.googleapis.com/v1/projects/repositorio2026-61a28/databases/(default)/documents/campanas?pageSize=300&key=AIzaSyAvVQTFWTCHwSCMIS2le22ZQ6aQBv8oUgo
```

- `pageSize=300`: entran todas las campañas en una respuesta. Si algún día hay más, la respuesta trae `nextPageToken` y el SP avisa que importó las primeras 300.

Para verlo desde una consola:

```bat
curl "https://firestore.googleapis.com/v1/projects/repositorio2026-61a28/databases/(default)/documents/campanas?pageSize=300&key=AIzaSyAvVQTFWTCHwSCMIS2le22ZQ6aQBv8oUgo"
```

Las campañas se cargan con el SP de la Entrega 5 `Publicidad.usp_ImportarCampanias` (`src/16_SP_Importacion.sql`). Lee las tablas de staging que arma el proceso, valida cada campaña con las reglas de anunciantes, campañas y piezas y hace el upsert de las válidas de una vez. Las rechazadas quedan en `Publicidad.ERRORES_CAMPANIA`, con el número de la importación (`DatosGenerales.IMPORTACION`).

## Formato

Firestore responde un objeto con la lista `documents`. Cada campo viene con su tipo:

```json
{
  "documents": [
    {
      "name": "projects/repositorio2026-61a28/databases/(default)/documents/campanas/<id>",
      "fields": {
        "anunciante": {"stringValue": "Fernet Branca"},
        "titulo":     {"stringValue": "Manual para festejar como un argentino"},
        "categorias": {"arrayValue": {"values": [{"stringValue": "Digital"}]}},
        "youtube":    {"stringValue": "L7fF_t9gL7A"},
        "videos":     {"arrayValue": {"values": [{"stringValue": "L7fF_t9gL7A"}, {"stringValue": "Jz_DPhD6VCo"}]}},
        "periodo":    {"stringValue": ""},
        "marca":      {"stringValue": ""}
      },
      "createTime": "...",
      "updateTime": "..."
    }
  ]
}
```

| Campo | Campañas que lo traen | Qué es |
|---|---|---|
| `anunciante`, `titulo`, `youtube` | 75 | El anunciante, el nombre de la campaña y el id del video de portada en YouTube |
| `videos` | 48 | Los ids de todos los videos de la campaña (el de portada incluido) |
| `categorias` | 75 | El formato: Film, Promo, Integral, Digital, RRSS, Exterior, Diseño, Activación |
| `periodo`, `marca` | 75 | Vienen vacíos |
| `agencia`, `productora`, `creditos`, `premios`, `descripcion`, `url_dossier`, `orden` | 51 a 75 | Datos de la producción y de la nota del Dossier |

Si Firestore rechaza el pedido, responde con un código HTTP 4xx y un objeto con el motivo:

```json
{"error": {"code": 403, "message": "Missing or insufficient permissions.", "status": "PERMISSION_DENIED"}}
```

Si la colección está vacía, responde `{}`.

## Transformaciones

Se hacen todas en T-SQL, al importar:

| Destino | Origen | Regla |
|---|---|---|
| `ANUNCIANTE.razon_social` | `anunciante` | Tal como viene, con el apóstrofo tipográfico (’) cambiado por el simple: la página escribe "McDonald’s" y "McDonald's", y es el mismo anunciante. "Visa y Banco Macro" es un solo anunciante: el de esa campaña |
| `ANUNCIANTE.id_pais` | — | Argentina: el Dossier cubre el mercado argentino, aunque el anunciante sea una empresa extranjera |
| `CAMPANIA.nombre` | `titulo` | Con el mismo cambio de apóstrofo |
| `CAMPANIA.fecha_inicio` y `fecha_fin` | — | `periodo` viene vacío: se usa el período del torneo, del 11/06 al 19/07/2026 |
| `PIEZA_PUBLICITARIA` | `videos`, o `youtube` si no hay `videos` | Una pieza por video distinto. La primera lleva el nombre de la campaña y las demás, el nombre con su número ("... (2)"), así un video nuevo agrega una pieza sin cambiar el título de las otras. Una campaña sin videos tiene una sola pieza |
| `PIEZA_PUBLICITARIA.id_idioma` | — | Español |
| `PIEZA_PAIS_INTERES` | — | Argentina |

El país, el idioma y el período son parámetros de `usp_ProcesarCampaniasJSON` (`@codigo_fifa`, `@codigo_idioma`, `@fecha_inicio` y `@fecha_fin`).

No se importan `creditos` (son nombres de personas: directores, creativos, productores), `agencia`, `productora`, `premios`, `descripcion`, `categorias`, `url_dossier` ni `orden`: no tienen lugar en el modelo y ningún reporte los usa.

Se rechazan las campañas sin anunciante o sin nombre, las de más de 150 caracteres, las que vienen dos veces y las que no son un objeto. También se rechaza una campaña ya cargada si las fechas nuevas dejan afuera un partido en el que se exhibe una de sus piezas.

## Límites de uso

- No hace falta registrarse: la única clave es la pública de la página.
- Cada documento leído descuenta de la cuota del proyecto del Dossier. En el plan gratuito de Firebase (Spark) son 50.000 lecturas por día ([cuotas de Firestore](https://firebase.google.com/docs/firestore/quotas)). Una importación es un solo pedido y lee 75 documentos.
- Firestore aplica además sus límites de tráfico por proyecto (ver el mismo enlace). Las importaciones son esporádicas: un pedido por ejecución del 31 o del test, sin reintentos automáticos.
- Si el dueño del sitio cambia las reglas de seguridad, la clave o el nombre de la colección, la consulta deja de funcionar y el SP lo informa con el error de la API.
- El contenido es del Dossier. Solo se guardan los nombres de los anunciantes y los títulos de las campañas, sin los créditos ni los textos de las notas.

Fuentes:
- [API REST de Cloud Firestore](https://firebase.google.com/docs/firestore/use-rest-api)
- [Claves de API de Firebase](https://firebase.google.com/docs/projects/api-keys)
- [Cuotas y límites de Cloud Firestore](https://firebase.google.com/docs/firestore/quotas)
