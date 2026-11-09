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

 Fecha: 09/11/2026
 Archivo: abm_sedes.py
 Objetivo: Alta, baja y modificacion de sedes del Mundial como aplicacion
           de escritorio. Muestra las sedes cargadas, da de alta una nueva con
           Torneo.usp_RegistrarSede (la sede y sus 4 espacios publicitarios en
           una sola transaccion), modifica una existente con
           Torneo.usp_ModificarSede y elimina una que no se uso con
           Torneo.usp_EliminarSede (rechaza las que tienen partidos o
           exhibiciones). Las validaciones las hacen los SP; la aplicacion solo
           convierte los numeros y muestra lo que la base informa.
================================================================================

Configuracion de la conexion (variables de entorno opcionales):
    MUNDIAL_SERVER    por defecto localhost (instancia por defecto de SQL Server;
                      para una instancia con nombre, por ejemplo localhost\\SQLEXPRESS)
    MUNDIAL_DATABASE  por defecto MundialFutbol
    MUNDIAL_DRIVER    por defecto ODBC Driver 18 for SQL Server
Usa autenticacion de Windows.
"""

import ctypes
import io
import os
import re
import tkinter as tk
import unicodedata
from decimal import Decimal, InvalidOperation
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import customtkinter as ctk
import pyodbc
from PIL import Image, ImageDraw, ImageOps, UnidentifiedImageError

CARPETA_FOTOS = Path(__file__).resolve().parent.parent / "datos" / "fuentes" / "sedes"

SERVER = os.environ.get("MUNDIAL_SERVER", "localhost")
DATABASE = os.environ.get("MUNDIAL_DATABASE", "MundialFutbol")
DRIVER = os.environ.get("MUNDIAL_DRIVER", "ODBC Driver 18 for SQL Server")

COLUMNAS = [
    # (clave, titulo, ancho, alineacion)
    ("id_sede", "ID", 50, "center"),
    ("nombre_estadio", "Estadio", 250, "w"),
    ("ciudad", "Ciudad", 150, "w"),
    ("pais", "País", 130, "w"),
    ("capacidad", "Capacidad", 90, "e"),
    ("huso", "Huso horario", 210, "w"),
    ("espacios", "Espacios", 90, "center"),
]


# ---------------------------------------------------------------------------
# Acceso a datos
# ---------------------------------------------------------------------------
class ErrorBD(Exception):
    """Error de la base ya limpio, listo para mostrar al usuario."""


def _limpiar(error: pyodbc.Error) -> str:
    """Saca el prefijo [Microsoft][ODBC Driver...][SQL Server] del mensaje."""
    texto = str(error.args[1]) if len(error.args) > 1 else str(error)
    texto = re.sub(r"^\[[^\]]*\]\s*(\[[^\]]*\])*", "", texto)
    texto = re.sub(r"\s*\(\d+\)\s*\(SQLExec\w+\)\s*$", "", texto)
    return texto.strip()


class Repositorio:
    def __init__(self):
        self.cn = pyodbc.connect(
            f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};"
            "Trusted_Connection=yes;TrustServerCertificate=yes;",
            autocommit=True,
            timeout=5,
        )

    def _ejecutar(self, sql, params=()):
        try:
            cur = self.cn.cursor()
            cur.execute(sql, params)
            return cur
        except pyodbc.Error as e:
            raise ErrorBD(_limpiar(e)) from e

    # Todas las lecturas van por los SP de consulta (src/18_SP_Consultas.sql): la
    # aplicación no lee ninguna tabla, así funciona con un usuario de
    # rol_AdministradorOperativo, que tiene DENY SELECT sobre las tablas.

    def sedes(self, filtro=""):
        """(id_sede, estadio, ciudad, país, capacidad, huso, espacios) de cada sede."""
        cur = self._ejecutar("EXEC Torneo.usp_ConsultarSedes @buscar = ?;", (filtro.strip() or None,))
        return cur.fetchall()

    def paises(self):
        """(id_pais, nombre, huso_horario) de cada país."""
        cur = self._ejecutar("EXEC DatosGenerales.usp_ConsultarPaises;")
        return [(f.id_pais, f.nombre, f.huso_horario) for f in cur.fetchall()]

    def husos(self):
        """(huso, desfase actual) de cada huso que acepta SQL Server."""
        cur = self._ejecutar("EXEC DatosGenerales.usp_ConsultarHusosHorarios;")
        return cur.fetchall()

    def alta(self, d):
        cur = self._ejecutar(
            """SET NOCOUNT ON;
               DECLARE @id INT;
               EXEC Torneo.usp_RegistrarSede
                    @nombre_estadio = ?, @ciudad = ?, @id_pais = ?, @capacidad = ?,
                    @huso_horario = ?,
                    @tarifa_espacio_1 = ?, @tarifa_espacio_2 = ?,
                    @tarifa_espacio_3 = ?, @tarifa_espacio_4 = ?,
                    @latitud = ?, @longitud = ?,
                    @id_sede = @id OUTPUT, @mostrar = 0;
               SELECT @id;""",
            (d["nombre_estadio"], d["ciudad"], d["id_pais"], d["capacidad"], d["huso_horario"],
             *d["tarifas"], d["latitud"], d["longitud"]),
        )
        return cur.fetchone()[0]

    def sede(self, id_sede):
        """Los datos de una sede para precargar el formulario: (estadio, ciudad, país,
        capacidad, huso, latitud, longitud, tarifa 1, 2, 3 y 4), o None si no existe."""
        f = self._ejecutar("EXEC Torneo.usp_ConsultarSede @id_sede = ?;", (id_sede,)).fetchone()
        if f is None:
            return None
        return (f.nombre_estadio, f.ciudad, f.pais, f.capacidad, f.huso_horario, f.latitud, f.longitud,
                f.tarifa_espacio_1, f.tarifa_espacio_2, f.tarifa_espacio_3, f.tarifa_espacio_4)

    def modificar(self, id_sede, d):
        self._ejecutar(
            """EXEC Torneo.usp_ModificarSede
                    @id_sede = ?, @nombre_estadio = ?, @ciudad = ?, @id_pais = ?, @capacidad = ?,
                    @huso_horario = ?, @latitud = ?, @longitud = ?,
                    @tarifa_espacio_1 = ?, @tarifa_espacio_2 = ?,
                    @tarifa_espacio_3 = ?, @tarifa_espacio_4 = ?, @mostrar = 0;""",
            (id_sede, d["nombre_estadio"], d["ciudad"], d["id_pais"], d["capacidad"], d["huso_horario"],
             d["latitud"], d["longitud"], *d["tarifas"]))

    def baja(self, id_sede):
        self._ejecutar("EXEC Torneo.usp_EliminarSede @id_sede = ?, @mostrar = 0;", (id_sede,))

    def imagen(self, id_sede):
        """Devuelve (bytes, formato, fecha_carga) o None si la sede no tiene foto."""
        cur = self._ejecutar("EXEC Torneo.usp_ConsultarImagenSede @id_sede = ?;", (id_sede,))
        return cur.fetchone()

    def guardar_imagen(self, id_sede, datos, reemplazar):
        sp = "Torneo.usp_SEDE_IMAGEN_Modificacion" if reemplazar else "Torneo.usp_SEDE_IMAGEN_Alta"
        self._ejecutar(f"EXEC {sp} @id_sede = ?, @imagen = ?;", (id_sede, pyodbc.Binary(datos)))

    def quitar_imagen(self, id_sede):
        self._ejecutar("EXEC Torneo.usp_SEDE_IMAGEN_Baja @id_sede = ?;", (id_sede,))

    def importar_fotos(self, carpeta):
        """Carga las fotos prebajadas con usp_ImportarImagenesSedes. Devuelve las
        filas del resultado (estadio, archivo, estado, formato, kb, motivo)."""
        cur = self._ejecutar("EXEC Torneo.usp_ImportarImagenesSedes @carpeta = ?, @mostrar = 1;", (carpeta,))
        return cur.fetchall()


# ---------------------------------------------------------------------------
# Conversion de los campos (las reglas de negocio las valida la base)
# ---------------------------------------------------------------------------
def _decimal(texto, campo, obligatorio):
    texto = texto.strip().replace(" ", "")
    if not texto:
        if obligatorio:
            raise ValueError(f"{campo}: es obligatorio.")
        return None
    # Acepta 1.234,56 / 1234,56 / 1234.56
    if "," in texto:
        texto = texto.replace(".", "").replace(",", ".")
    try:
        return Decimal(texto)
    except InvalidOperation:
        raise ValueError(f"{campo}: \"{texto}\" no es un número.") from None


LADO_MAXIMO = 1280  # px: las fotos se achican antes de subirlas


def preparar_imagen(ruta):
    """Lee la foto elegida, la achica a LADO_MAXIMO px de lado si es más grande
    y la devuelve como bytes PNG (si tiene transparencia) o JPEG."""
    with Image.open(ruta) as img:
        img = ImageOps.exif_transpose(img)  # respeta la orientación de las fotos del celular
        img.thumbnail((LADO_MAXIMO, LADO_MAXIMO))
        salida = io.BytesIO()
        transparente = img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info)
        if transparente:
            img.save(salida, format="PNG", optimize=True)
        else:
            img.convert("RGB").save(salida, format="JPEG", quality=85, optimize=True)
        return salida.getvalue()


ICONO = Path(__file__).resolve().parent / "copa.ico"


def poner_icono(ventana, demora=0):
    """Pone la copa como icono de la ventana. Los CTkToplevel ponen el suyo a los
    200 ms de abrirse, asi que en esos se llama con demora."""
    if not ICONO.exists():
        return
    if demora:
        ventana.after(demora, lambda: ventana.iconbitmap(str(ICONO)))
    else:
        ventana.iconbitmap(str(ICONO))


def icono_en_barra_de_tareas(app_id):
    """Sin esto, Windows muestra en la barra de tareas el icono de Python y no el de la ventana."""
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(app_id)
    except (AttributeError, OSError):
        pass  # no es Windows


def clave_de_orden(valor):
    """Para ordenar la tabla: los números como números y el texto sin distinguir
    mayúsculas ni tildes ("Ámsterdam" junto a "Amsterdam")."""
    if valor is None:
        return (1, "")  # los vacíos, al final
    if isinstance(valor, (int, float, Decimal)):
        return (0, valor)
    sin_tildes = unicodedata.normalize("NFKD", str(valor))
    return (0, "".join(c for c in sin_tildes if not unicodedata.combining(c)).casefold())


def icono_lupa(lado=18):
    """Una lupa dibujada (se dibuja 4 veces más grande y se achica, para suavizar
    los bordes), gris oscuro para el tema claro y gris claro para el oscuro."""
    def dibujar(color):
        n = lado * 4
        img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        grosor = max(4, n // 10)
        d.ellipse((n * 0.08, n * 0.08, n * 0.66, n * 0.66), outline=color, width=grosor)
        d.line((n * 0.58, n * 0.58, n * 0.92, n * 0.92), fill=color, width=round(grosor * 1.3))
        return img.resize((lado, lado), Image.LANCZOS)
    return ctk.CTkImage(light_image=dibujar((90, 90, 90, 255)), dark_image=dibujar((185, 185, 185, 255)),
                        size=(lado, lado))


def centrar_ventana(ventana, ancho, alto, minimo=None):
    """Abre la ventana centrada en la pantalla, achicada si no entra.
    customtkinter escala el ancho y el alto según el DPI de Windows, pero no la
    posición, que va en píxeles reales; por eso se calcula con la escala."""
    escala = ventana._get_window_scaling()
    pantalla_ancho = ventana.winfo_screenwidth()
    pantalla_alto = ventana.winfo_screenheight() - round(48 * escala)  # sin la barra de tareas
    ancho = min(ancho, int(pantalla_ancho / escala) - 20)
    alto = min(alto, int(pantalla_alto / escala) - 40)
    x = max(0, (pantalla_ancho - round(ancho * escala)) // 2)
    y = max(0, (pantalla_alto - round((alto + 32) * escala)) // 2)  # 32: la barra de título
    ventana.geometry(f"{ancho}x{alto}+{x}+{y}")
    if minimo:
        ventana.minsize(min(minimo[0], ancho), min(minimo[1], alto))


def _entero(texto, campo):
    texto = texto.strip().replace(".", "").replace(" ", "")
    if not texto:
        return None  # la obligatoriedad la informa el SP
    if not texto.isdigit():
        raise ValueError(f"{campo}: \"{texto}\" no es un número entero.")
    return int(texto)


# ---------------------------------------------------------------------------
# Interfaz
# ---------------------------------------------------------------------------
class App(ctk.CTk):
    def __init__(self, repo: Repositorio):
        super().__init__()
        poner_icono(self)
        self.repo = repo
        ctk.set_appearance_mode("system")
        ctk.set_default_color_theme("blue")
        self.title("Mundial 2026 - Sedes")
        centrar_ventana(self, 1400, 900, minimo=(1150, 700))
        self.tiene_imagen = False
        self.id_edicion = None  # sede que se está editando en el formulario (None: alta)
        self._orden = (None, False)  # (columna, descendente); None: el orden de la consulta
        self._crudos = {}

        self.paises = {nombre: (id_pais, huso) for id_pais, nombre, huso in repo.paises()}
        # "(UTC-03:00) Argentina Standard Time" -> "Argentina Standard Time"
        self.husos = {f"(UTC{off}) {name}": name for name, off in repo.husos()}
        self.huso_a_etiqueta = {v: k for k, v in self.husos.items()}

        self.grid_columnconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=0)
        self.grid_rowconfigure(0, weight=1)

        self._panel_lista()
        self._panel_formulario()
        self.recargar()

    # --- Lista de sedes -----------------------------------------------------
    def _panel_lista(self):
        marco = ctk.CTkFrame(self)
        marco.grid(row=0, column=0, sticky="nsew", padx=(12, 6), pady=12)
        marco.grid_columnconfigure(0, weight=1)
        marco.grid_rowconfigure(2, weight=1)

        ctk.CTkLabel(marco, text="Sedes", font=ctk.CTkFont(size=20, weight="bold")).grid(
            row=0, column=0, sticky="w", padx=12, pady=(10, 4))

        self._barra_busqueda(marco).grid(row=1, column=0, sticky="ew", padx=12, pady=(0, 8))

        self._estilo_tabla()
        contenedor = ctk.CTkFrame(marco, fg_color="transparent")
        contenedor.grid(row=2, column=0, sticky="nsew", padx=12)
        contenedor.grid_columnconfigure(0, weight=1)
        contenedor.grid_rowconfigure(0, weight=1)

        self.tabla = ttk.Treeview(contenedor, columns=[c[0] for c in COLUMNAS],
                                  show="headings", style="Sedes.Treeview", selectmode="browse")
        for clave, titulo, ancho, alin in COLUMNAS:
            self.tabla.heading(clave, text=titulo, command=lambda c=clave: self.ordenar_por(c))
            self.tabla.column(clave, width=ancho, anchor=alin, stretch=clave == "nombre_estadio")
        self.tabla.grid(row=0, column=0, sticky="nsew")
        barra = ctk.CTkScrollbar(contenedor, command=self.tabla.yview)
        barra.grid(row=0, column=1, sticky="ns")
        self.tabla.configure(yscrollcommand=barra.set)

        pie = ctk.CTkFrame(marco, fg_color="transparent")
        pie.grid(row=3, column=0, sticky="ew", padx=12, pady=(6, 10))
        pie.grid_columnconfigure(0, weight=1)
        self.lbl_total = ctk.CTkLabel(pie, text="", text_color=("gray35", "gray65"))
        self.lbl_total.grid(row=0, column=0, sticky="w")
        self.btn_eliminar = ctk.CTkButton(pie, text="Eliminar sede seleccionada", state="disabled",
                                          fg_color="#c0392b", hover_color="#962d22", command=self.eliminar)
        self.btn_eliminar.grid(row=0, column=2, sticky="e")
        ctk.CTkButton(pie, text="Importar fotos del repositorio", fg_color="transparent", border_width=1,
                      text_color=("gray20", "gray85"), command=self.importar_fotos).grid(
            row=0, column=1, sticky="e", padx=(0, 8))
        self.tabla.bind("<<TreeviewSelect>>", lambda _: self._seleccion_cambiada())

        self._panel_imagen(marco)

    # --- Búsqueda -------------------------------------------------------------
    def _barra_busqueda(self, padre):
        """Un campo con la lupa a la izquierda y una ✕ para borrar la búsqueda.
        El campo no usa textvariable, así se ve el texto de ejemplo."""
        barra = ctk.CTkFrame(padre, height=36, corner_radius=6, border_width=2,
                             fg_color=("#f9f9fa", "#343638"), border_color=("#979da2", "#565b5e"))
        barra.grid_columnconfigure(1, weight=1)
        ctk.CTkLabel(barra, text="", image=icono_lupa(), width=24).grid(row=0, column=0, padx=(10, 0), pady=4)
        self.ent_buscar = ctk.CTkEntry(barra, border_width=0, fg_color="transparent",
                                       placeholder_text="Buscar por estadio, ciudad o país")
        self.ent_buscar.grid(row=0, column=1, sticky="ew", padx=(2, 4), pady=4)
        self.ent_buscar.bind("<KeyRelease>", lambda _: self._busqueda_cambiada())
        self.btn_borrar_busqueda = ctk.CTkButton(barra, text="✕", width=28, height=24, fg_color="transparent",
                                                 hover_color=("gray85", "gray30"),
                                                 text_color=("gray35", "gray70"), command=self.borrar_busqueda)
        self._ultima_busqueda = ""
        return barra

    def _busqueda_cambiada(self):
        texto = self.ent_buscar.get()
        if texto == self._ultima_busqueda:  # flechas, Shift, etc.: no cambia nada
            return
        self._ultima_busqueda = texto
        if texto:
            self.btn_borrar_busqueda.grid(row=0, column=2, padx=(0, 6))
        else:
            self.btn_borrar_busqueda.grid_remove()
        self.recargar()

    def borrar_busqueda(self, recargar=True):
        self.ent_buscar.delete(0, "end")
        if self.focus_get() is not self.ent_buscar._entry:
            self.ent_buscar._activate_placeholder()  # ver _poner
        self._ultima_busqueda = ""
        self.btn_borrar_busqueda.grid_remove()
        if recargar:
            self.recargar()

    # --- Imagen de la sede seleccionada ---------------------------------------
    def _panel_imagen(self, padre):
        panel = ctk.CTkFrame(padre, fg_color=("#ffffff", "#2b2b2b"), border_width=1,
                             border_color=("#d5dae3", "#3a3a3a"))
        panel.grid(row=4, column=0, sticky="ew", padx=12, pady=(0, 12))
        panel.grid_columnconfigure(1, weight=1)

        # Sin foto, el cuadro muestra una imagen transparente con el texto encima. No se
        # usa image=None: customtkinter no la quita de la etiqueta de tkinter, que queda
        # apuntando a la foto anterior y falla cuando esa foto se libera.
        transparente = Image.new("RGBA", (360, 200), (0, 0, 0, 0))
        self._sin_foto = ctk.CTkImage(light_image=transparente, dark_image=transparente, size=(360, 200))
        self.lbl_foto = ctk.CTkLabel(panel, text="Elegí una sede", image=self._sin_foto, compound="center",
                                     width=360, height=200,
                                     fg_color=("#eef1f5", "#232323"), corner_radius=6,
                                     text_color=("gray40", "gray60"))
        self.lbl_foto.grid(row=0, column=0, rowspan=4, padx=10, pady=10)

        self.lbl_foto_titulo = ctk.CTkLabel(panel, text="Imagen de la sede",
                                            font=ctk.CTkFont(size=16, weight="bold"), anchor="w")
        self.lbl_foto_titulo.grid(row=0, column=1, sticky="ew", padx=(4, 12), pady=(14, 0))
        self.lbl_foto_info = ctk.CTkLabel(panel, text="", anchor="w", justify="left",
                                          text_color=("gray35", "gray65"))
        self.lbl_foto_info.grid(row=1, column=1, sticky="new", padx=(4, 12))

        self.btn_cargar = ctk.CTkButton(panel, text="Cargar imagen…", state="disabled",
                                        command=self.cargar_imagen)
        self.btn_cargar.grid(row=2, column=1, sticky="w", padx=(4, 12), pady=(4, 4))
        self.btn_quitar = ctk.CTkButton(panel, text="Quitar imagen", state="disabled",
                                        fg_color="transparent", border_width=1,
                                        text_color=("gray20", "gray85"), command=self.quitar_imagen)
        self.btn_quitar.grid(row=3, column=1, sticky="nw", padx=(4, 12), pady=(0, 14))
        self._foto_actual = None  # referencia para que tkinter no libere la imagen

    def _sede_seleccionada(self):
        seleccion = self.tabla.selection()
        if not seleccion:
            return None
        valores = self.tabla.item(seleccion[0], "values")
        return int(valores[0]), valores[1]

    def _seleccion_cambiada(self):
        """Clic en una sede: muestra su foto y precarga sus datos en el formulario.
        Si la selección se pierde (por ejemplo, al filtrar), el formulario no se
        toca, para no perder lo que se estaba editando."""
        self._sede_elegida()
        sede = self._sede_seleccionada()
        if sede is not None:
            self._cargar_formulario(sede[0])

    def _sede_elegida(self):
        sede = self._sede_seleccionada()
        estado = "normal" if sede else "disabled"
        self.btn_eliminar.configure(state=estado)
        self.btn_cargar.configure(state=estado)
        self._mostrar_imagen(sede)

    def _poner_foto(self, foto=None, texto=""):
        """Muestra la foto (CTkImage) o, sin foto, el texto sobre la imagen transparente.
        La referencia a la foto anterior se suelta recién después de reemplazarla en la
        etiqueta: si Python la libera antes, tkinter queda apuntando a una imagen borrada."""
        self.lbl_foto.configure(image=foto or self._sin_foto, text=texto)
        self._foto_actual = foto

    def _mostrar_imagen(self, sede):
        self.tiene_imagen = False
        if sede is None:
            self._poner_foto(texto="Elegí una sede")
            self.lbl_foto_titulo.configure(text="Imagen de la sede")
            self.lbl_foto_info.configure(text="")
            self.btn_quitar.configure(state="disabled")
            return
        id_sede, estadio = sede
        self.lbl_foto_titulo.configure(text=estadio)
        try:
            fila = self.repo.imagen(id_sede)
        except ErrorBD as e:
            messagebox.showerror("Error", str(e))
            return
        if fila is None:
            self._poner_foto(texto="Sin imagen")
            self.lbl_foto_info.configure(text="Esta sede todavía no tiene foto.")
            self.btn_cargar.configure(text="Cargar imagen…")
            self.btn_quitar.configure(state="disabled")
            return
        datos, formato, fecha = fila
        try:
            with Image.open(io.BytesIO(datos)) as img:
                img.load()
                foto = img.copy()
        except (UnidentifiedImageError, OSError):
            self._poner_foto(texto="La imagen guardada\nno se puede mostrar")
        else:
            ancho, alto = foto.size
            foto.thumbnail((360, 200))
            self._poner_foto(ctk.CTkImage(light_image=foto, dark_image=foto, size=foto.size))
            formato = f"{formato}, {ancho} × {alto} px"
        self.tiene_imagen = True
        kb = f"{len(datos) / 1024:,.0f}".replace(",", ".")
        self.lbl_foto_info.configure(text=f"{formato}, {kb} KB\nCargada el {fecha:%d/%m/%Y %H:%M}")
        self.btn_cargar.configure(text="Reemplazar imagen…")
        self.btn_quitar.configure(state="normal")

    def cargar_imagen(self):
        sede = self._sede_seleccionada()
        if sede is None:
            return
        ruta = filedialog.askopenfilename(
            title=f"Imagen de {sede[1]}",
            filetypes=[("Imágenes", "*.png *.jpg *.jpeg *.webp *.bmp"), ("Todos los archivos", "*.*")])
        if not ruta:
            return
        try:
            datos = preparar_imagen(ruta)
        except (UnidentifiedImageError, OSError) as e:
            messagebox.showerror("Imagen inválida", f"No se pudo abrir el archivo como imagen.\n\n{e}")
            return
        try:
            self.repo.guardar_imagen(sede[0], datos, reemplazar=self.tiene_imagen)
        except ErrorBD as e:
            messagebox.showerror("No se guardó la imagen", str(e))
            return
        self._mostrar_imagen(sede)

    def importar_fotos(self):
        if not messagebox.askyesno(
                "Importar fotos",
                "Se cargan las fotos prebajadas de las 24 sedes de la lista fija desde\n"
                f"{CARPETA_FOTOS}\n\n"
                "Las que ya tengan otra foto (cargada a mano) se reemplazan. ¿Continuar?"):
            return
        try:
            filas = self.repo.importar_fotos(str(CARPETA_FOTOS))
        except ErrorBD as e:
            messagebox.showerror("No se importaron las fotos", str(e))
            return
        conteo = {}
        for f in filas:
            conteo[f[2]] = conteo.get(f[2], 0) + 1
        resumen = ", ".join(f"{n} {estado.lower()}" for estado, n in conteo.items())
        problemas = [f"- {f[0]}: {f[5]}" for f in filas if f[2] in ("RECHAZADA", "OMITIDA")]
        texto = f"Fotos: {resumen}."
        if problemas:
            texto += "\n\n" + "\n".join(problemas[:12]) + ("\n…" if len(problemas) > 12 else "")
        sede = self._sede_seleccionada()
        self.recargar(resaltar=sede[0] if sede else None)
        (messagebox.showwarning if problemas else messagebox.showinfo)("Importar fotos", texto)

    def quitar_imagen(self):
        sede = self._sede_seleccionada()
        if sede is None or not messagebox.askyesno("Quitar imagen", f"¿Quitar la foto de \"{sede[1]}\"?"):
            return
        try:
            self.repo.quitar_imagen(sede[0])
        except ErrorBD as e:
            messagebox.showerror("No se quitó la imagen", str(e))
            return
        self._mostrar_imagen(sede)

    def _estilo_tabla(self):
        oscuro = ctk.get_appearance_mode() == "Dark"
        fondo, texto, cabecera = ("#2b2b2b", "#e6e6e6", "#3a3a3a") if oscuro else ("#ffffff", "#1f1f1f", "#e9edf3")
        # Encabezado con el mouse encima y presionado: sin esto, el tema "clam" lo pinta de
        # gris claro y el título (claro en modo oscuro) no se ve.
        cabecera_hover, cabecera_presionada = ("#474b4f", "#1f6aa5") if oscuro else ("#d5dce6", "#c2ccda")
        estilo = ttk.Style(self)
        estilo.theme_use("clam")
        estilo.configure("Sedes.Treeview", background=fondo, fieldbackground=fondo,
                         foreground=texto, rowheight=28, borderwidth=0, font=("Segoe UI", 10))
        estilo.configure("Sedes.Treeview.Heading", background=cabecera, foreground=texto,
                         relief="flat", font=("Segoe UI", 10, "bold"))
        estilo.map("Sedes.Treeview", background=[("selected", "#1f6aa5")],
                   foreground=[("selected", "#ffffff")])
        estilo.map("Sedes.Treeview.Heading",
                   background=[("pressed", cabecera_presionada), ("active", cabecera_hover)],
                   foreground=[("pressed", "#ffffff" if oscuro else texto), ("active", texto)])

    # --- Orden por columna -----------------------------------------------------
    def ordenar_por(self, clave):
        """Clic en un encabezado: ordena por esa columna; otro clic invierte el orden."""
        actual, descendente = self._orden
        self._orden = (clave, not descendente if clave == actual else False)
        self._aplicar_orden()

    def _aplicar_orden(self):
        """Reordena las filas moviéndolas (no se borran ni se vuelven a cargar), así la
        sede seleccionada sigue seleccionada y el formulario no se recarga."""
        clave, descendente = self._orden
        for c, titulo, _, _ in COLUMNAS:
            flecha = (" ▼" if descendente else " ▲") if c == clave else ""
            self.tabla.heading(c, text=titulo + flecha)
        if clave is None:
            return
        indice = [c for c, *_ in COLUMNAS].index(clave)
        filas = sorted(self.tabla.get_children(),
                       key=lambda iid: clave_de_orden(self._crudos[iid][indice]), reverse=descendente)
        for posicion, iid in enumerate(filas):
            self.tabla.move(iid, "", posicion)
        if self.tabla.selection():
            self.tabla.see(self.tabla.selection()[0])

    def recargar(self, resaltar=None):
        try:
            filas = self.repo.sedes(self.ent_buscar.get())
        except ErrorBD as e:
            messagebox.showerror("Error", str(e))
            return
        self.tabla.delete(*self.tabla.get_children())
        self._crudos = {}  # valores sin formato de cada fila, para ordenar
        for f in filas:
            id_sede, estadio, ciudad, pais, capacidad, huso, espacios = f
            self._crudos[str(id_sede)] = tuple(f)
            self.tabla.insert("", "end", iid=str(id_sede),
                              values=(id_sede, estadio, ciudad, pais, f"{capacidad:,}".replace(",", "."),
                                      huso, espacios))
        self._aplicar_orden()
        self.lbl_total.configure(text=f"{len(filas)} sede(s)")
        if resaltar is not None and self.tabla.exists(str(resaltar)):
            self.tabla.selection_set(str(resaltar))
            self.tabla.see(str(resaltar))
        self._sede_elegida()

    def eliminar(self):
        seleccion = self.tabla.selection()
        if not seleccion:
            return
        id_sede, estadio, ciudad, pais = self.tabla.item(seleccion[0], "values")[:4]
        if not messagebox.askyesno(
                "Eliminar sede",
                f"¿Eliminar \"{estadio}\" ({ciudad}, {pais}) y sus espacios publicitarios?\n\n"
                "Solo se puede eliminar una sede que no tenga partidos ni exhibiciones.",
                icon="warning"):
            return
        try:
            self.repo.baja(int(id_sede))
        except ErrorBD as e:
            messagebox.showerror("No se eliminó la sede", str(e))
            return
        if self.id_edicion == int(id_sede):
            self.nueva_sede()
        self.recargar()
        messagebox.showinfo("Sede eliminada", f"Se eliminó \"{estadio}\" con sus espacios publicitarios.")

    # --- Formulario: alta de una sede nueva o edición de la seleccionada -------
    TARIFAS = ("t1", "t2", "t3", "t4")

    def _panel_formulario(self):
        marco = ctk.CTkFrame(self, width=420)
        marco.grid(row=0, column=1, sticky="nsew", padx=(6, 12), pady=12)
        marco.grid_columnconfigure((0, 1), weight=1)

        self.lbl_form_titulo = ctk.CTkLabel(marco, text="Nueva sede", font=ctk.CTkFont(size=20, weight="bold"))
        self.lbl_form_titulo.grid(row=0, column=0, columnspan=2, sticky="w", padx=14, pady=(10, 0))
        self.lbl_form_sub = ctk.CTkLabel(marco, text="Completá los datos y registrala.",
                                         text_color=("gray35", "gray65"))
        self.lbl_form_sub.grid(row=1, column=0, columnspan=2, sticky="w", padx=14, pady=(0, 6))

        # Los campos de texto no usan textvariable: así customtkinter muestra los textos de ejemplo.
        self.campos = {}
        self.var_pais = tk.StringVar(value="")
        self.var_huso = tk.StringVar(value="")

        def entrada(clave, ejemplo):
            self.campos[clave] = ctk.CTkEntry(marco, placeholder_text=ejemplo)
            return self.campos[clave]

        fila = 2
        fila = self._campo(marco, fila, "Estadio *", entrada("nombre_estadio", "Ej.: Estadio Mario Alberto Kempes"))
        fila = self._campo(marco, fila, "Ciudad *", entrada("ciudad", "Ej.: Córdoba"))
        self.cmb_pais = ctk.CTkComboBox(marco, values=list(self.paises), variable=self.var_pais,
                                        command=self._pais_elegido)
        fila = self._campo(marco, fila, "País *", self.cmb_pais)
        fila = self._campo(marco, fila, "Capacidad *", entrada("capacidad", "Ej.: 45000"))
        self.cmb_huso = ctk.CTkComboBox(marco, values=list(self.husos), variable=self.var_huso)
        fila = self._campo(marco, fila, "Huso horario *", self.cmb_huso)
        self.var_pais.set("")
        self.var_huso.set("")

        ctk.CTkLabel(marco, text="Ubicación (opcional, las dos juntas)",
                     font=ctk.CTkFont(weight="bold")).grid(
            row=fila, column=0, columnspan=2, sticky="w", padx=14, pady=(12, 2))
        fila += 1
        entrada("latitud", "Latitud (-34.6355)").grid(row=fila, column=0, sticky="ew", padx=(14, 4), pady=4)
        entrada("longitud", "Longitud (-58.3647)").grid(row=fila, column=1, sticky="ew", padx=(4, 14), pady=4)
        fila += 1

        ctk.CTkLabel(marco, text="Tarifas de los 4 espacios publicitarios (USD) *",
                     font=ctk.CTkFont(weight="bold")).grid(
            row=fila, column=0, columnspan=2, sticky="w", padx=14, pady=(12, 2))
        fila += 1
        for i, clave in enumerate(self.TARIFAS):
            entrada(clave, f"Panel perimetral {i + 1}").grid(
                row=fila + i // 2, column=i % 2, sticky="ew",
                padx=(14, 4) if i % 2 == 0 else (4, 14), pady=4)
        fila += 2
        ctk.CTkButton(marco, text="Misma tarifa en los 4", fg_color="transparent", border_width=1,
                      text_color=("gray20", "gray85"), command=self._copiar_tarifa).grid(
            row=fila, column=0, columnspan=2, sticky="ew", padx=14, pady=(2, 10))
        fila += 1

        self.btn_guardar = ctk.CTkButton(marco, text="Registrar sede", height=38,
                                         font=ctk.CTkFont(size=14, weight="bold"), command=self.guardar)
        self.btn_guardar.grid(row=fila, column=0, columnspan=2, sticky="ew", padx=14, pady=(10, 4))
        fila += 1
        self.btn_secundario = ctk.CTkButton(marco, text="Limpiar", fg_color="transparent", border_width=1,
                                            text_color=("gray20", "gray85"), command=self.nueva_sede)
        self.btn_secundario.grid(row=fila, column=0, columnspan=2, sticky="ew", padx=14, pady=(4, 10))
        fila += 1

        ctk.CTkLabel(marco, text=f"{SERVER}  ·  {DATABASE}", text_color=("gray45", "gray55")).grid(
            row=fila, column=0, columnspan=2, sticky="sw", padx=14, pady=(10, 10))
        marco.grid_rowconfigure(fila, weight=1)

    def _campo(self, padre, fila, etiqueta, widget):
        ctk.CTkLabel(padre, text=etiqueta).grid(row=fila, column=0, columnspan=2, sticky="w", padx=14, pady=(6, 0))
        widget.grid(row=fila + 1, column=0, columnspan=2, sticky="ew", padx=14, pady=(2, 2))
        return fila + 2

    def _poner(self, clave, valor):
        campo = self.campos[clave]
        campo.delete(0, "end")
        if valor not in (None, ""):
            campo.insert(0, str(valor))
        elif self.focus_get() is not campo._entry:
            # customtkinter da por enfocado el campo hasta que pierde el foco por primera vez,
            # y en ese caso no vuelve a mostrar el texto de ejemplo al vaciarlo.
            campo._activate_placeholder()

    def _modo(self, id_sede=None, estadio=None):
        """Pasa el formulario a edición de la sede id_sede, o a alta si es None."""
        self.id_edicion = id_sede
        if id_sede is None:
            self.lbl_form_titulo.configure(text="Nueva sede")
            self.lbl_form_sub.configure(text="Completá los datos y registrala.")
            self.btn_guardar.configure(text="Registrar sede")
            self.btn_secundario.configure(text="Limpiar")
        else:
            self.lbl_form_titulo.configure(text=f"Editar sede #{id_sede}")
            self.lbl_form_sub.configure(text=estadio if len(estadio) <= 44 else estadio[:43] + "…")
            self.btn_guardar.configure(text="Guardar cambios")
            self.btn_secundario.configure(text="Nueva sede (descartar cambios)")

    def _cargar_formulario(self, id_sede):
        try:
            fila = self.repo.sede(id_sede)
        except ErrorBD as e:
            messagebox.showerror("Error", str(e))
            return
        if fila is None:
            return
        estadio, ciudad, pais, capacidad, huso, latitud, longitud, *tarifas = fila
        self._poner("nombre_estadio", estadio)
        self._poner("ciudad", ciudad)
        self.var_pais.set(pais)
        self._poner("capacidad", capacidad)
        self.var_huso.set(self.huso_a_etiqueta.get(huso, huso))
        self._poner("latitud", latitud)
        self._poner("longitud", longitud)
        for clave, tarifa in zip(self.TARIFAS, tarifas):
            # 120000.00 se muestra como 120000; 1500.50 queda igual.
            self._poner(clave, None if tarifa is None else
                        (int(tarifa) if tarifa == tarifa.to_integral_value() else tarifa))
        self._modo(id_sede, estadio)

    def nueva_sede(self):
        """Vacía el formulario y lo deja para dar de alta una sede nueva."""
        if self.tabla.selection():
            self.tabla.selection_remove(*self.tabla.selection())
        self.limpiar()
        self._modo(None)

    def _pais_elegido(self, nombre):
        # Sugiere el huso del país si todavía no se eligió uno.
        datos = self.paises.get(nombre)
        if datos and datos[1] and not self.var_huso.get():
            self.var_huso.set(self.huso_a_etiqueta.get(datos[1], ""))

    def _copiar_tarifa(self):
        valor = next((self.campos[k].get() for k in self.TARIFAS if self.campos[k].get().strip()), "")
        if not valor:
            messagebox.showinfo("Tarifas", "Escribí la tarifa en alguno de los cuatro espacios.")
            return
        for k in self.TARIFAS:
            self._poner(k, valor)

    def limpiar(self):
        for clave in self.campos:
            self._poner(clave, None)
        self.var_pais.set("")
        self.var_huso.set("")

    def _datos(self):
        v = {k: campo.get() for k, campo in self.campos.items()}
        v["pais"], v["huso"] = self.var_pais.get(), self.var_huso.get()
        pais = v["pais"].strip()
        if pais and pais not in self.paises:
            raise ValueError(f"País: \"{pais}\" no está en la lista.")
        huso = v["huso"].strip()
        if huso and huso not in self.husos and huso not in self.huso_a_etiqueta:
            raise ValueError(f"Huso horario: \"{huso}\" no está en la lista.")
        return {
            "nombre_estadio": v["nombre_estadio"],
            "ciudad": v["ciudad"],
            "id_pais": self.paises[pais][0] if pais else None,
            "capacidad": _entero(v["capacidad"], "Capacidad"),
            "huso_horario": self.husos.get(huso, huso) or None,
            "tarifas": [_decimal(v[k], f"Tarifa del espacio {i}", obligatorio=False)
                        for i, k in enumerate(("t1", "t2", "t3", "t4"), start=1)],
            "latitud": _decimal(v["latitud"], "Latitud", obligatorio=False),
            "longitud": _decimal(v["longitud"], "Longitud", obligatorio=False),
        }

    def guardar(self):
        try:
            datos = self._datos()
        except ValueError as e:
            messagebox.showerror("Dato inválido", str(e))
            return
        estadio = datos["nombre_estadio"].strip()
        if self.id_edicion is not None:
            id_sede = self.id_edicion
            try:
                self.repo.modificar(id_sede, datos)
            except ErrorBD as e:
                messagebox.showerror("No se guardaron los cambios", str(e))
                return
            self.recargar(resaltar=id_sede)
            messagebox.showinfo("Sede modificada", f"Se guardaron los cambios de \"{estadio}\" (id {id_sede}).")
            return
        try:
            id_sede = self.repo.alta(datos)
        except ErrorBD as e:
            messagebox.showerror("No se registró la sede", str(e))
            return
        self.borrar_busqueda(recargar=False)
        self.recargar(resaltar=id_sede)
        messagebox.showinfo("Sede registrada",
                            f"Se registró \"{estadio}\" (id {id_sede}) con sus 4 espacios publicitarios.\n"
                            "Quedó seleccionada: podés cargarle la foto o seguir editándola.")


def main():
    icono_en_barra_de_tareas("UNLaM.MundialFutbol.Sedes")
    raiz = tk.Tk()
    raiz.withdraw()
    try:
        repo = Repositorio()
    except pyodbc.Error as e:
        messagebox.showerror("Sin conexión", f"No se pudo conectar a {SERVER} / {DATABASE}.\n\n{_limpiar(e)}")
        return
    finally:
        raiz.destroy()
    App(repo).mainloop()


if __name__ == "__main__":
    main()
