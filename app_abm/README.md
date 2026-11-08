# Aplicaciones de escritorio (Python)

- `abm_paises.py`: ABM de `DatosGenerales.PAIS`.
- `abm_jugadores.py`: plantillas del Mundial. Alta de jugadores (`usp_JUGADOR_Alta`) y reemplazos de último momento (`usp_ReemplazarJugador`: clic en un jugador de la plantilla). El botón "Elegir de no convocados" carga los datos desde `scraping/datos/jugadores.csv`.

# ABM de países

Aplicación en Python (customtkinter + pyodbc) para dar de alta, modificar, dar de baja y buscar registros de `DatosGenerales.PAIS`. Usa solo los SP `usp_PAIS_Alta`, `usp_PAIS_Modificacion` y `usp_PAIS_Baja`; las validaciones son las de la base.

## Uso

```
pip install -r requirements.txt
python abm_paises.py
```

Requiere la base `MundialFutbol` creada (scripts 00 a 04) y un ODBC Driver for SQL Server. Por defecto se conecta a `localhost\SQLEXPRESS` con autenticación de Windows. Se puede cambiar con las variables de entorno `MUNDIAL_SERVER`, `MUNDIAL_DATABASE` y `MUNDIAL_DRIVER`.
