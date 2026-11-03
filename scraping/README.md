# Scraping de los jugadores y del equipo arbitral del Mundial 2026

Universidad Nacional de La Matanza · 3641 - Bases de Datos Aplicada · Comisión 01 · Grupo 2
Entrega 6 – Procesos de importación

Hay dos scripts, los dos sobre Wikipedia en inglés:

| Script | Genera | Se importa con |
|---|---|---|
| `Scraping_Jugadores.py` | `datos/jugadores.csv`: los convocados de cada selección | `Torneo.usp_ImportarJugadoresCSV` (`src/24_SP_Importar_Jugadores.sql`) |
| `Scraping_Arbitros.py` | `datos/designaciones_arbitrales.csv`: el equipo arbitral de cada partido | `Arbitraje.usp_ImportarDesignacionesCSV` (`src/23_SP_Importar_Mundial2026.sql`) |

Las secciones 1 a 6 describen el de jugadores. La 7 describe el del equipo arbitral, que usa la misma técnica, los mismos límites de uso y las mismas funciones de descarga.

---
## 1. Qué se obtiene

El script genera **`jugadores.csv`**: los 1248 convocados de las 48 selecciones del Mundial 2026, 26 por selección. Se carga en la tabla **`Torneo.JUGADOR`**.

### Destino de cada columna

| Columna del CSV | Columna de `JUGADOR` | Observación |
|---|---|---|
| `codigo_fifa` | `id_lista` | `usp_ImportarJugadores` busca la lista de convocados de la selección de ese país |
| `dorsal` | `dorsal` | |
| `posicion` | `posicion_habitual` | Viene como GK / DF / MF / FW; el SP la traduce a ARQUERO / DEFENSOR / MEDIOCAMPISTA / DELANTERO |
| `nombre`, `apellido` | `nombre`, `apellido` | Ver [separación de nombre y apellido](#44-separación-de-nombre-y-apellido) |
| `fecha_nacimiento` | `fecha_nacimiento` | Formato ISO `AAAA-MM-DD` |
| `club` | `club_origen` | |

Las demás columnas de `JUGADOR` no vienen en el archivo:

| Columna | Valor | Motivo |
|---|---|---|
| `fecha_alta`, `motivo_alta` | Fecha de presentación de la lista y "Importación" | Los pone `usp_ImportarJugadores` |
| `fecha_baja`, `motivo_baja` | NULL | No es un dato faltante: NULL significa que el jugador está activo en la lista |
| `id_pais_nacimiento` | NULL | La fuente no lo publica. La consigna no lo pide y ninguna vista, función ni reporte lo usa |

---

## 2. Páginas de origen

Las dos páginas son de Wikipedia en inglés.

| Página | URL | Qué se toma |
|---|---|---|
| 2026 FIFA World Cup squads | https://en.wikipedia.org/wiki/2026_FIFA_World_Cup_squads | **Fuente principal.** Una sección por selección con la tabla de sus 26 convocados |
| List of FIFA country codes | https://en.wikipedia.org/wiki/List_of_FIFA_country_codes | El código FIFA de cada selección, solo de la sección "FIFA member codes". Con ese código, cada jugador se asocia a su selección en la base |

Las dos páginas escriben cada selección con el mismo nombre (por ejemplo, "Ivory Coast" o "Cape Verde"). Por eso se cruzan por nombre sin tablas de traducción escritas a mano, y las 48 selecciones encontraron su código.

---

## 3. Límites de uso de la fuente

| Aspecto | Condición de Wikipedia | Qué hace el script |
|---|---|---|
| Clave / registro | No requiere clave ni cuenta para leer artículos | — |
| User-Agent | Exige un User-Agent que identifique al cliente y tenga un dato de contacto, con el formato `nombre/versión (contacto)`. Los agentes genéricos (`python-requests`, `curl`) pueden recibir un error 403 o quedar bloqueados | Envía `TP-BBDDA-UNLaM-Grupo2/1.0 (trabajo práctico; https://github.com/AgustinVenier/TP_BBDDA_20262C)` |
| Ritmo de pedidos | Para páginas `/wiki/`: concurrencia menor a 10 y un promedio menor a 20 pedidos por segundo. Ante un error 429 hay que esperar lo que indique `Retry-After` | Hace **2 pedidos por ejecución**, uno detrás de otro, sin paralelismo y por una misma conexión. Ante un 429 espera lo que indica `Retry-After` y reintenta hasta 3 veces; si no viene ese encabezado, espera 5, 10 y 20 s. Ante cualquier otro error HTTP se detiene |
| Formato de URL | Usar `/wiki/Título` sin parámetros, sin guardar cookies ni ejecutar JavaScript | Usa solo `/wiki/Título` y no guarda cookies |
| robots.txt | Los artículos están permitidos ("Friendly, low-speed bots are welcome viewing article pages"). Están prohibidas `/w/`, `/api/` y `Special:` | Solo lee artículos |
| Licencia | El texto está publicado bajo CC BY-SA 4.0, que permite reutilizarlo citando la fuente | La fuente se cita en este documento y en el encabezado del script |

Fuentes:
- [Wikimedia Foundation User-Agent Policy](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy)
- [Wikimedia Robot policy](https://wikitech.wikimedia.org/wiki/Robot_policy)
- [robots.txt de en.wikipedia.org](https://en.wikipedia.org/robots.txt)
- [Términos de uso de Wikimedia](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use)

---

## 4. Técnica de scraping

**Scraping de HTML estático mediante pedido HTTP y parseo del DOM con selectores CSS.** Además, aprovecha un microformato (hCard) y atributos de datos (`data-sort-value`) que la página incluye en el HTML.

Es la técnica adecuada porque Wikipedia entrega el HTML ya armado desde el servidor, con todos los datos. No hace falta un navegador automatizado (Selenium, Playwright), que se usa para páginas que arman su contenido con JavaScript y es mucho más lento.

### 4.1 Herramientas

| Herramienta | Versión usada | Para qué |
|---|---|---|
| Python | 3.11 | Lenguaje del script |
| `requests` | 2.34 | Descargar el HTML de cada página |
| `beautifulsoup4` | 4.15 | Recorrer el HTML y buscar elementos por etiqueta, clase y atributo |
| `lxml` | 6.1 | Parser de HTML que usa BeautifulSoup |
| `csv` (biblioteca estándar) | — | Escribir el archivo de salida |

### 4.2 Pasos

1. **Descargar** cada página con una `requests.Session`. La sesión reutiliza la misma conexión para los dos pedidos y envía siempre el User-Agent propio. Cada pedido tiene un timeout de 60 s y los reintentos ante un 429 que se describen en la sección 3.
2. **Quedarse con el cuerpo del artículo** (`#mw-content-text .mw-parser-output`), para dejar afuera menús y barras laterales.
3. **Armar un diccionario** nombre de la selección → código FIFA, desde "List of FIFA country codes".
4. **Recorrer la página de plantillas** sección por sección (ver 4.3) y armar una fila por jugador.
5. **Escribir el CSV** e informar por pantalla cuántas selecciones y jugadores se encontraron, junto con los avisos (por ejemplo, una selección sin código).

### 4.3 Dónde está cada dato en el HTML

En la página de plantillas cada grupo es un `<h2>` ("Group A") y cada selección un `<h3>` dentro de él. Debajo del `<h3>` está la tabla de convocados, con una fila por jugador:

```html
<h3>Mexico</h3>
...
<table class="sortable wikitable plainrowheaders">
  <tr class="nat-fs-player">
    <td>1</td>
    <td><span style="display:none">1</span><a ...>GK</a></td>
    <th data-sort-value="Rangel, Raul" scope="row"><a ...>Raúl Rangel</a></th>
    <td><span style="display:none"> (<span class="bday">2000-02-25</span>)</span>25 February 2000 (aged 26)</td>
    <td>14</td>   <!-- partidos jugados: no se usa -->
    <td>0</td>    <!-- goles: no se usa -->
    <td><span class="flagicon">...</span> <a ...>Guadalajara</a></td>
  </tr>
```

| Dato | Cómo se obtiene |
|---|---|
| Selección | El texto del `<h3>`, traducido a su código FIFA |
| Jugadores | Cada fila `<tr class="nat-fs-player">` de la primera tabla de la sección |
| Dorsal | Primera celda |
| Posición | Texto del enlace de la segunda celda. Se toma el enlace y no toda la celda, porque la celda tiene un número oculto que usa la página para ordenar |
| Nombre visible | Texto del enlace de la celda `<th>` |
| Orden "Apellido, Nombre" | Atributo `data-sort-value` de esa `<th>`, que Wikipedia usa para ordenar la tabla por apellido |
| Fecha de nacimiento | El `<span class="bday">` oculto (microformato hCard), que ya está en formato ISO. No hace falta interpretar "25 February 2000" |
| Club | Texto del último enlace de la última celda que no sea la bandera (`.flagicon`) |

El resto de la página no se toma: partidos jugados, goles, edad, DT, listas preliminares y notas. Solo se extrae lo que tiene columna en `JUGADOR`.

### 4.4 Separación de nombre y apellido

La base guarda nombre y apellido por separado, pero la página muestra el nombre completo ("Raúl Rangel"). Para separarlos se usa el atributo `data-sort-value`, que trae el apellido primero y sin tildes. El script busca dónde está ese apellido dentro del nombre visible y corta ahí, conservando las tildes del nombre visible.

| Nombre visible | `data-sort-value` | Nombre | Apellido | Caso |
|---|---|---|---|---|
| Edson Álvarez | `Alvarez, Edson` | Edson | Álvarez | Normal (las tildes se conservan) |
| Jan Paul van Hecke | `Hecke, Jan Paul van` | Jan Paul | van Hecke | Partícula: van, de, de la, da, dos, etc. |
| Micky van de Ven | `Ven, Micky van de` | Micky | van de Ven | Partícula de dos palabras |
| Son Heung-min | `Son, Heung-min` | Heung-min | Son | El apellido va primero (Corea) |
| Hassan Al-Haydos | `Haydos, Hassan` | Hassan | Al-Haydos | El orden omite el prefijo "Al-" |
| Neymar | `Neymar` | Neymar | Neymar | Nombre único (ver abajo) |

**Nombre único.** Hay 22 jugadores conocidos por un solo nombre, como Neymar, Alisson, Casemiro o Raphinha. Como `nombre` y `apellido` son obligatorios en `JUGADOR`, se guarda el mismo valor en los dos.

Estas transformaciones se hacen durante el scraping. La consigna prohíbe modificar los archivos con herramientas externas antes de importarlos, pero exceptúa lo que se obtiene por scraping.

---

## 5. Formato del archivo generado

- Codificación **UTF-8 sin BOM**: se conservan tildes y letras como č, ø o ł.
- Separador **coma**, con una primera fila de **encabezado** con los nombres de columna.
- Un valor que contenga una coma o comillas va entre comillas dobles (estándar CSV); en el dataset actual no hay ninguno.
- Fechas en formato ISO `AAAA-MM-DD`.
- Fin de línea `\r\n`.

```csv
codigo_fifa,dorsal,posicion,nombre,apellido,fecha_nacimiento,club
CZE,1,GK,Matěj,Kovář,2000-05-17,PSV Eindhoven
CZE,2,DF,David,Zima,2000-11-08,Slavia Prague
```

---

## 6. Cómo ejecutarlo

Requisitos: Python 3.9 o superior y conexión a internet.

```bash
pip install requests beautifulsoup4 lxml
python Scraping_Jugadores.py
```

Tarda unos 3 segundos y por defecto deja `jugadores.csv` en la carpeta `datos`, junto al script. Para elegir otra carpeta:

```bash
python Scraping_Jugadores.py --salida C:\MundialFutbol\Importacion
```

Salida esperada:

```
Selecciones: 48  Jugadores: 1248
Archivo: ...\datos\jugadores.csv
```
---

## 7. Equipo arbitral (`Scraping_Arbitros.py`)

### 7.1 Qué se obtiene

**`designaciones_arbitrales.csv`**: una fila por árbitro designado en cada uno de los 104 partidos, con los ocho roles que publica la FIFA. Son 832 designaciones de 169 árbitros de 49 países. Se cargan en **`Arbitraje.ARBITRO`** y **`Arbitraje.DESIGNACION_ARBITRAL`**.

| Columna del CSV | Destino | Observación |
|---|---|---|
| `fecha` | Partido | Fecha del partido en la hora local de la sede (`AAAA-MM-DD`). Con las dos selecciones identifica al partido: el archivo no numera los partidos |
| `local`, `visitante` | Partido | Código FIFA de cada selección |
| `rol` | `DESIGNACION_ARBITRAL.rol` | Como lo publica la página. `Arbitraje.usp_ImportarDesignaciones` lo traduce (ver la tabla de abajo) |
| `nombre`, `apellido` | `ARBITRO.nombre`, `ARBITRO.apellido` | Ver [nombre y apellido](#74-nombre-y-apellido) |
| `pais` | `ARBITRO.id_pais` | Código FIFA del país del árbitro |

| Rol en la página | Rol en la base |
|---|---|
| Referee | `PRINCIPAL` |
| Assistant referees (el primero y el segundo) | `ASISTENTE_1` y `ASISTENTE_2` |
| Fourth official | `CUARTO` |
| Reserve assistant referee | `ASISTENTE_RESERVA` |
| Video assistant referee | `VAR` |
| Assistant video assistant referee | `AVAR` |
| Support video assistant referee | `VAR_APOYO` |

La página no publica la fecha de nacimiento, la categoría ni los idiomas de los árbitros. La categoría se pasa como parámetro al importar (FIFA, porque la FIFA eligió a los árbitros del Mundial); los idiomas se registran después con `Arbitraje.usp_ARBITRO_IDIOMA_Alta`.

### 7.2 Páginas de origen

| Página | Qué se toma |
|---|---|
| 2026 FIFA World Cup Group A … Group L | Los 72 partidos de la fase de grupos |
| 2026 FIFA World Cup round of 32 | Los 16 partidos de dieciseisavos |
| 2026 FIFA World Cup knockout stage | Los 16 partidos de octavos a la final. También tiene los dieciseisavos, pero sin el equipo arbitral: de esos se toma la página anterior |
| List of FIFA country codes | El código FIFA de cada selección y del país de cada árbitro, igual que en el scraping de jugadores |

Son **15 pedidos por ejecución**, uno detrás de otro, por la misma conexión y con un segundo de pausa entre cada uno, muy por debajo de los límites de la sección 3. Ante un 429 se espera y se reintenta igual que en el scraping de jugadores.

### 7.3 Dónde está cada dato en el HTML

Cada partido es un `<div class="footballbox">`. Debajo, después de las formaciones, un párrafo trae el resto del equipo arbitral, con un `<b>` por rol y una línea "Nombre (País)" por árbitro:

```html
<div class="footballbox">
  <div class="fleft"><time><div class="fdate">June 11, 2026 <span class="dtstart">2026-06-11</span></div> ...</time></div>
  <table class="fevent"><tr>
    <th class="fhome"><a ...>Mexico</a></th> <th class="fscore">2–0</th> <th class="faway"><a ...>South Africa</a></th>
  </tr></table>
  <div class="fright"> ... <div>Referee: <a ...>Wilton Sampaio</a> (<a ...>Brazil</a>)</div></div>
</div>
...
<p><b>Assistant referees:</b><br/>Bruno Pires (Brazil)<br/>Bruno Boschilia (Brazil)
   <br/><b>Fourth official:</b><br/>Juan Gabriel Benítez (Paraguay)
   <br/><b>Video assistant referee:</b><br/>Nicolás Gallo (Colombia) ...</p>
```

| Dato | Cómo se obtiene |
|---|---|
| Fecha | El `<span class="dtstart">` oculto, que ya está en formato ISO |
| Selecciones | El texto de `.fhome` y `.faway`, traducido a su código FIFA |
| Árbitro principal | La línea "Referee: Nombre (País)" de `.fright` |
| Resto del equipo | El párrafo que tiene un `<b>` "Fourth official", el primero después del partido. Cada `<br>` separa una línea; las que terminan en ":" son el rol y las demás, sus árbitros |

Se quitan las notas ("[14]") y los enlaces a artículos en otros idiomas ("[de]") que la página pone junto a algunos nombres.

### 7.4 Nombre y apellido

La página muestra el nombre completo y, a diferencia de la de plantillas, no tiene un atributo que marque el apellido. Se toma **la primera palabra como nombre y el resto como apellido**: "Carlos del Cerro Grande" queda como Carlos / del Cerro Grande. Con los nombres compuestos el corte no es el real ("Juan Gabriel Benítez" queda como Juan / Gabriel Benítez), pero es siempre el mismo, así que el árbitro se reconoce igual al volver a importar.

**Un árbitro escrito de dos formas.** Algunas páginas escriben al mismo árbitro de otra forma. Se toman como la misma persona dos formas del mismo país que:

- son iguales sin tildes ni signos ("Hamza El-Fariq" y "Hamza El Fariq"), o
- tienen la misma primera y última palabra y una está dentro de la otra ("Katia García" y "Katia Itzel García"), o
- son casi iguales y terminan igual ("Masimiliano Del Yesso" y "Maximiliano Del Yesso").

Se usa la forma que más se repite, y el script avisa cada unificación. En el dataset actual son 6.

### 7.5 Formato y ejecución

El formato es el de la sección 5 (UTF-8 sin BOM, comas, encabezado y `\r\n`):

```csv
fecha,local,visitante,rol,nombre,apellido,pais
2026-06-11,MEX,RSA,Referee,Wilton,Sampaio,BRA
2026-06-11,MEX,RSA,Assistant referee 1,Bruno,Pires,BRA
```

```bash
python Scraping_Arbitros.py [--salida CARPETA]
```

Tarda unos 25 segundos. Salida esperada:

```
Partidos: 104  Designaciones: 832  Árbitros: 169
Archivo: ...\datos\designaciones_arbitrales.csv
Aviso: Facundo Rodriguez (Argentina) se toma como Facundo Rodríguez.
...
```
---


