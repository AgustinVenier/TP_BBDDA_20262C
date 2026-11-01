"""
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - CarolinaCaruso
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier

 Fecha: 29/10/2026
 Archivo: Scraping_Jugadores.py
 Objetivo: Obtener por scraping los jugadores convocados al Mundial 2026
           publicados en Wikipedia y guardarlos en jugadores.csv, una fila por
           convocado: selección (código FIFA), dorsal, posición, nombre,
           apellido, fecha de nacimiento y club. El archivo lo importa
           21_Importacion_Jugadores.sql, después de que 20_DatosIniciales.sql
           creó las selecciones y sus listas de convocados.
================================================================================

 Páginas de origen (Wikipedia en inglés, licencia CC BY-SA 4.0):
   - 2026 FIFA World Cup squads: una sección por selección con la tabla de sus
     26 convocados. Es la fuente principal.
   - List of FIFA country codes: el código FIFA de cada selección, con el que
     el jugador se asocia a su selección en la base.
   Las dos usan el mismo nombre para cada selección (ej. "Ivory Coast"), así
   que se cruzan por nombre sin tablas de traducción escritas a mano.

 Técnica: scraping de HTML estático. Se descarga el HTML de cada página con
 requests y se recorre con BeautifulSoup (parser lxml), buscando los
 elementos por su estructura:
   - Selección: cada <h3> de la página de plantillas que esté dentro de un
     <h2> de grupo ("Group A").
   - Jugadores: las filas <tr class="nat-fs-player"> de la tabla de la
     sección. La fecha de nacimiento sale del <span class="bday"> (microformato
     hCard, formato ISO) y el orden "Apellido, Nombre" del atributo
     data-sort-value, que se usa para separar el nombre del apellido.
 La posición se guarda como la publica la página (GK, DF, MF, FW): la
 traduce Torneo.usp_ImportarJugador.

 Límites de uso: Wikipedia no pide clave, pero exige un User-Agent que
 identifique al cliente y pide no hacer muchos pedidos seguidos. El script
 hace dos pedidos por ejecución, por una misma conexión (requests.Session).
 Si Wikipedia responde 429 (demasiados pedidos), espera lo que indique el
 encabezado Retry-After y reintenta, hasta tres veces.

 Uso:
   pip install requests beautifulsoup4 lxml
   python Scraping_Jugadores.py [--salida CARPETA]
 Si no se indica, el CSV se guarda en la carpeta "datos", junto al script.
 Se escribe en UTF-8, separado por comas y con encabezado.
 La documentación completa (fuente, técnica, límites y formato) está en
 README.md, en esta misma carpeta.
"""

import argparse
import csv
import re
import sys
import time
import unicodedata
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

import requests
from bs4 import BeautifulSoup

URL_PLANTILLAS = 'https://en.wikipedia.org/wiki/2026_FIFA_World_Cup_squads'
URL_CODIGOS = 'https://en.wikipedia.org/wiki/List_of_FIFA_country_codes'
USER_AGENT = ('TP-BBDDA-UNLaM-Grupo2/1.0 '
              '(trabajo práctico; https://github.com/AgustinVenier/TP_BBDDA_20262C)')
REINTENTOS_429 = 3       # reintentos si Wikipedia responde 429 (demasiados pedidos)
ESPERA_POR_DEFECTO = 5   # segundos, si la respuesta 429 no trae Retry-After

# Letras que NFKD no descompone, para comparar con el orden de Wikipedia (sin tildes).
LETRAS_SIMPLES = str.maketrans({'ø': 'o', 'Ø': 'O', 'ł': 'l', 'Ł': 'L', 'đ': 'd',
                                'Đ': 'D', 'ı': 'i', 'æ': 'ae', 'Æ': 'Ae', 'ß': 'ss'})
# Partículas con las que empieza un apellido compuesto ("Virgil van Dijk").
PARTICULAS = {'de', 'del', 'da', 'das', 'do', 'dos', 'di', 'du', 'la', 'le',
              'van', 'von', 'der', 'den', 'ten', 'ter'}


def segundos_de_espera(respuesta, intento):
    """Lo que pide Retry-After (en segundos o como fecha); si no viene, 5, 10 y 20 s."""
    valor = respuesta.headers.get('Retry-After', '').strip()
    if valor.isdigit():
        return int(valor)
    try:
        return max(0, (parsedate_to_datetime(valor) - datetime.now(timezone.utc)).total_seconds())
    except (TypeError, ValueError):
        return ESPERA_POR_DEFECTO * 2 ** intento


def descargar(sesion, url):
    for intento in range(REINTENTOS_429 + 1):
        respuesta = sesion.get(url, timeout=60)
        if respuesta.status_code != 429 or intento == REINTENTOS_429:
            break
        espera = segundos_de_espera(respuesta, intento)
        print(f'Wikipedia pidió esperar (429): reintento en {espera:.0f} s.')
        time.sleep(espera)
    respuesta.raise_for_status()
    return BeautifulSoup(respuesta.text, 'lxml').select_one('#mw-content-text .mw-parser-output')


def plegar(texto):
    """Minúsculas, sin tildes ni signos: "O'Neill" -> "oneill", "Džeko" -> "dzeko"."""
    texto = unicodedata.normalize('NFKD', texto.translate(LETRAS_SIMPLES))
    texto = ''.join(c for c in texto if not unicodedata.combining(c))
    return re.sub(r'[^a-z0-9]', '', texto.lower())


def texto_enlace(celda):
    """Texto del primer enlace de la celda que no sea una bandera."""
    for enlace in celda.find_all('a'):
        if not enlace.find_parent(class_='flagicon') and enlace.get_text(strip=True):
            return enlace.get_text(' ', strip=True)
    return celda.get_text(' ', strip=True).split('(')[0].strip()


def separar_jugador(visible, orden):
    """
    Separa el nombre visible ("Edson Álvarez") en (nombre, apellido) usando el
    orden de Wikipedia ("Alvarez, Edson"), que está sin tildes. Contempla los
    nombres con el apellido primero (coreanos: "Son Heung-min").
    """
    palabras = visible.split()
    if ',' not in orden:
        # Nombre conocido sin apellido (Alisson, Vinícius Júnior).
        if len(palabras) == 1:
            return palabras[0], palabras[0]
        return palabras[0], ' '.join(palabras[1:])

    plegadas = [plegar(p) for p in palabras]
    apellido = [plegar(p) for p in orden.split(',')[0].split()]
    k = len(apellido)

    # Se busca dónde empieza el apellido, desde el final; primero exacto y
    # después por terminación ("Al-Haydos" figura como "Haydos").
    for coincide in (lambda a, b: a == b, lambda a, b: a.endswith(b)):
        for i in range(len(palabras) - k, -1, -1):
            if all(coincide(plegadas[i + j], apellido[j]) for j in range(k)):
                # Las partículas van con el apellido ("Hecke, Jan Paul van" -> "van Hecke").
                while i > 1 and palabras[i - 1] in PARTICULAS:
                    i -= 1
                if i > 0:
                    return ' '.join(palabras[:i]), ' '.join(palabras[i:])
                if k < len(palabras):
                    return ' '.join(palabras[k:]), ' '.join(palabras[:k])

    # Sin coincidencia: tantas palabras de nombre como tenga el orden.
    n = max(1, min(len(orden.split(',')[1].split()), len(palabras) - 1))
    return ' '.join(palabras[:n]), ' '.join(palabras[n:])


def leer_codigos_fifa(contenido):
    """Nombre -> código, solo de la sección "FIFA member codes" (después hay códigos viejos)."""
    codigos = {}
    fin = contenido.find(lambda t: t.name == 'h2' and t.get_text(strip=True) == 'Non-FIFA member codes')
    for tabla in contenido.select('table.wikitable'):
        if fin is not None and tabla.find_previous('h2') is fin:
            break
        for fila in tabla.find_all('tr')[1:]:
            celdas = [re.sub(r'\[.*?\]', '', c.get_text(' ', strip=True)).strip()
                      for c in fila.find_all(['th', 'td'])]
            for i in range(0, len(celdas) - 1, 2):
                if re.fullmatch(r'[A-Z]{3}', celdas[i + 1]):
                    codigos[celdas[i]] = celdas[i + 1]
    return codigos


def leer_jugadores(contenido, codigos):
    jugadores, avisos = [], []
    selecciones = 0

    for titulo in contenido.find_all('h3'):
        if not titulo.find_previous('h2').get_text(strip=True).startswith('Group '):
            continue
        nombre = titulo.get_text(strip=True)
        codigo = codigos.get(nombre)
        if not codigo:
            avisos.append(f'{nombre}: no se encontró su código FIFA; se omiten sus jugadores.')
            continue

        # La tabla de convocados es la primera de la sección.
        elemento = titulo.parent if titulo.parent.name == 'div' else titulo
        tabla = None
        for hermano in elemento.find_next_siblings():
            if hermano.name == 'table':
                tabla = hermano
                break
            if hermano.name == 'div' and 'mw-heading' in (hermano.get('class') or []):
                break
        if tabla is None:
            avisos.append(f'{nombre}: no se encontró la tabla de convocados.')
            continue

        selecciones += 1
        for fila in tabla.select('tr.nat-fs-player'):
            celdas = fila.find_all(['td', 'th'], recursive=False)
            jugador = fila.find('th')
            nombre_j, apellido_j = separar_jugador(texto_enlace(jugador),
                                                   jugador.get('data-sort-value', ''))
            nacimiento = fila.select_one('span.bday')
            jugadores.append({
                'codigo_fifa': codigo,
                'dorsal': celdas[0].get_text(strip=True),
                'posicion': texto_enlace(celdas[1]),
                'nombre': nombre_j,
                'apellido': apellido_j,
                'fecha_nacimiento': nacimiento.get_text(strip=True) if nacimiento else '',
                'club': texto_enlace(celdas[-1]),
            })

    return selecciones, jugadores, avisos


def guardar(ruta, filas):
    with open(ruta, 'w', encoding='utf-8', newline='') as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=list(filas[0]), quoting=csv.QUOTE_MINIMAL)
        escritor.writeheader()
        escritor.writerows(filas)


def main():
    parser = argparse.ArgumentParser(description='Scraping de los jugadores del Mundial 2026 (Wikipedia).')
    parser.add_argument('--salida', default=str(Path(__file__).resolve().parent / 'datos'),
                        help='carpeta donde se guarda jugadores.csv')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')

    # Una sola sesión: los dos pedidos reusan la conexión y el User-Agent.
    with requests.Session() as sesion:
        sesion.headers['User-Agent'] = USER_AGENT
        codigos = leer_codigos_fifa(descargar(sesion, URL_CODIGOS))
        selecciones, jugadores, avisos = leer_jugadores(descargar(sesion, URL_PLANTILLAS), codigos)
    if not jugadores:
        sys.exit('No se encontró ningún jugador: puede haber cambiado la estructura de la página.')

    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)
    guardar(salida / 'jugadores.csv', jugadores)

    print(f'Selecciones: {selecciones}  Jugadores: {len(jugadores)}')
    print(f'Archivo: {salida / "jugadores.csv"}')
    for aviso in avisos:
        print('Aviso:', aviso)


if __name__ == '__main__':
    main()
