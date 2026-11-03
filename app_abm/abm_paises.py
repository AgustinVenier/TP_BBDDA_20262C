"""
Universidad Nacional de La Matanza - 3641 Bases de Datos Aplicada
Comision 01, Grupo 2

ABM de paises (DatosGenerales.PAIS) como aplicacion de escritorio.

Todas las operaciones pasan por los stored procedures del proyecto
(usp_PAIS_Alta, usp_PAIS_Modificacion, usp_PAIS_Baja): las validaciones viven
en la base y la aplicacion solo muestra lo que ellas informan.

Configuracion de la conexion (variables de entorno opcionales):
    MUNDIAL_SERVER    por defecto localhost\\SQLEXPRESS
    MUNDIAL_DATABASE  por defecto MundialFutbol
    MUNDIAL_DRIVER    por defecto ODBC Driver 18 for SQL Server
Usa autenticacion de Windows.
"""

import os
import re
import tkinter as tk
from tkinter import messagebox, ttk

import customtkinter as ctk
import pyodbc

SERVER = os.environ.get("MUNDIAL_SERVER", r"localhost\SQLEXPRESS")
DATABASE = os.environ.get("MUNDIAL_DATABASE", "MundialFutbol")
DRIVER = os.environ.get("MUNDIAL_DRIVER", "ODBC Driver 18 for SQL Server")

COLUMNAS = [
    ("id_pais", "ID", 60, "center"),
    ("nombre", "Nombre", 230, "w"),
    ("codigo_fifa", "FIFA", 65, "center"),
    ("codigo_iso2", "ISO-2", 65, "center"),
    ("codigo_iso3", "ISO-3", 65, "center"),
    ("codigo_moneda", "Moneda", 75, "center"),
    ("huso_horario", "Huso horario", 250, "w"),
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


class RepositorioPaises:
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

    def listar(self, filtro=""):
        like = f"%{filtro.strip()}%"
        cur = self._ejecutar(
            """SELECT id_pais, nombre, codigo_fifa, codigo_iso2, codigo_iso3,
                      codigo_moneda, huso_horario
               FROM DatosGenerales.PAIS
               WHERE nombre LIKE ? OR codigo_fifa LIKE ? OR codigo_iso2 LIKE ?
                  OR codigo_iso3 LIKE ? OR codigo_moneda LIKE ?
               ORDER BY nombre""",
            (like,) * 5,
        )
        return [tuple("" if v is None else v for v in f) for f in cur.fetchall()]

    def husos(self):
        cur = self._ejecutar("SELECT name FROM sys.time_zone_info ORDER BY name")
        return [f[0] for f in cur.fetchall()]

    def alta(self, d):
        cur = self._ejecutar(
            """SET NOCOUNT ON;
               DECLARE @id SMALLINT;
               EXEC DatosGenerales.usp_PAIS_Alta
                    @nombre=?, @huso_horario=?, @codigo_fifa=?, @codigo_iso2=?,
                    @codigo_iso3=?, @codigo_moneda=?, @id_pais=@id OUTPUT;
               SELECT @id;""",
            (d["nombre"], d["huso_horario"], d["codigo_fifa"], d["codigo_iso2"],
             d["codigo_iso3"], d["codigo_moneda"]),
        )
        return cur.fetchone()[0]

    def modificacion(self, id_pais, d):
        self._ejecutar(
            """EXEC DatosGenerales.usp_PAIS_Modificacion
                    @id_pais=?, @nombre=?, @huso_horario=?, @codigo_fifa=?,
                    @codigo_iso2=?, @codigo_iso3=?, @codigo_moneda=?""",
            (id_pais, d["nombre"], d["huso_horario"], d["codigo_fifa"],
             d["codigo_iso2"], d["codigo_iso3"], d["codigo_moneda"]),
        )

    def baja(self, id_pais):
        self._ejecutar("EXEC DatosGenerales.usp_PAIS_Baja @id_pais=?", (id_pais,))


# ---------------------------------------------------------------------------
# Interfaz
# ---------------------------------------------------------------------------
class App(ctk.CTk):
    def __init__(self, repo: RepositorioPaises):
        super().__init__()
        self.repo = repo
        self.id_seleccionado = None

        ctk.set_appearance_mode("system")
        ctk.set_default_color_theme("blue")
        self.title("Mundial 2026 - ABM de países")
        self.geometry("1280x700")
        self.minsize(1100, 600)

        self.columnconfigure(0, weight=1)
        self.columnconfigure(1, weight=0)
        self.rowconfigure(0, weight=1)

        self._panel_listado()
        self._panel_formulario()
        self._estado = ctk.CTkLabel(self, text="", anchor="w", text_color=("gray30", "gray70"))
        self._estado.grid(row=1, column=0, columnspan=2, sticky="ew", padx=20, pady=(0, 8))

        self.refrescar()

    # -- listado ------------------------------------------------------------
    def _panel_listado(self):
        marco = ctk.CTkFrame(self, corner_radius=12)
        marco.grid(row=0, column=0, sticky="nsew", padx=(20, 10), pady=20)
        marco.columnconfigure(0, weight=1)
        marco.rowconfigure(1, weight=1)

        cab = ctk.CTkFrame(marco, fg_color="transparent")
        cab.grid(row=0, column=0, columnspan=2, sticky="ew", padx=16, pady=(16, 8))
        cab.columnconfigure(1, weight=1)
        ctk.CTkLabel(cab, text="Países", font=ctk.CTkFont(size=22, weight="bold")).grid(row=0, column=0)
        self.busqueda = ctk.StringVar()
        self.busqueda.trace_add("write", lambda *_: self.refrescar())
        ctk.CTkEntry(cab, textvariable=self.busqueda, width=280, height=34,
                     placeholder_text="Buscar por nombre, código o moneda…"
                     ).grid(row=0, column=2, sticky="e")

        estilo = ttk.Style()
        estilo.theme_use("clam")
        self._aplicar_estilo_tabla(estilo)
        self.tabla = ttk.Treeview(marco, columns=[c[0] for c in COLUMNAS],
                                  show="headings", selectmode="browse", style="Paises.Treeview")
        for clave, titulo, ancho, ancla in COLUMNAS:
            self.tabla.heading(clave, text=titulo)
            self.tabla.column(clave, width=ancho, anchor=ancla, stretch=clave in ("nombre", "huso_horario"))
        self.tabla.grid(row=1, column=0, sticky="nsew", padx=(16, 0), pady=(0, 16))
        barra = ctk.CTkScrollbar(marco, command=self.tabla.yview)
        barra.grid(row=1, column=1, sticky="ns", padx=(0, 12), pady=(0, 16))
        self.tabla.configure(yscrollcommand=barra.set)
        self.tabla.bind("<<TreeviewSelect>>", self._al_seleccionar)
        self.tabla.bind("<Double-1>", lambda _e: self.nombre.focus())
        self.tabla.tag_configure("par", background=self._color_fila(True))
        self.tabla.tag_configure("impar", background=self._color_fila(False))

    @staticmethod
    def _oscuro():
        return ctk.get_appearance_mode() == "Dark"

    def _color_fila(self, par):
        if self._oscuro():
            return "#2b2b2b" if par else "#242424"
        return "#ffffff" if par else "#f1f4f9"

    def _aplicar_estilo_tabla(self, estilo):
        fondo = "#2b2b2b" if self._oscuro() else "#ffffff"
        texto = "#e6e6e6" if self._oscuro() else "#1a1a1a"
        cab = "#1f538d"
        estilo.configure("Paises.Treeview", background=fondo, fieldbackground=fondo,
                         foreground=texto, rowheight=30, borderwidth=0, font=("Segoe UI", 11))
        estilo.configure("Paises.Treeview.Heading", background=cab, foreground="white",
                         relief="flat", font=("Segoe UI", 11, "bold"), padding=(6, 6))
        estilo.map("Paises.Treeview.Heading", background=[("active", "#2a6bb5")])
        estilo.map("Paises.Treeview", background=[("selected", "#3b8ed0")],
                   foreground=[("selected", "white")])

    # -- formulario ---------------------------------------------------------
    def _panel_formulario(self):
        marco = ctk.CTkFrame(self, corner_radius=12, width=340)
        marco.grid(row=0, column=1, sticky="ns", padx=(10, 20), pady=20)
        marco.grid_propagate(False)
        marco.columnconfigure(0, weight=1)

        self.titulo_form = ctk.CTkLabel(marco, text="Nuevo país", anchor="w",
                                        font=ctk.CTkFont(size=20, weight="bold"))
        self.titulo_form.grid(row=0, column=0, sticky="ew", padx=20, pady=(18, 4))

        self.vars = {k: ctk.StringVar() for k in
                     ("nombre", "codigo_fifa", "codigo_iso2", "codigo_iso3", "codigo_moneda", "huso_horario")}

        fila = 1
        self.nombre = self._campo(marco, fila, "Nombre *", "nombre", "Argentina"); fila += 2
        self._campo(marco, fila, "Código FIFA (3 letras)", "codigo_fifa", "ARG"); fila += 2
        self._campo(marco, fila, "Código ISO alfa-2", "codigo_iso2", "AR"); fila += 2
        self._campo(marco, fila, "Código ISO alfa-3", "codigo_iso3", "ARG"); fila += 2
        self._campo(marco, fila, "Código de moneda (ISO 4217)", "codigo_moneda", "ARS"); fila += 2

        ctk.CTkLabel(marco, text="Huso horario *", anchor="w").grid(row=fila, column=0, sticky="ew", padx=20, pady=(8, 0))
        try:
            husos = self.repo.husos()
        except ErrorBD:
            husos = []
        self.cbo_huso = ctk.CTkComboBox(marco, values=husos, variable=self.vars["huso_horario"], height=34)
        self.cbo_huso.grid(row=fila + 1, column=0, sticky="ew", padx=20)
        fila += 2

        botones = ctk.CTkFrame(marco, fg_color="transparent")
        botones.grid(row=fila, column=0, sticky="ew", padx=20, pady=(22, 0))
        botones.columnconfigure((0, 1), weight=1)
        self.btn_guardar = ctk.CTkButton(botones, text="Guardar", height=38, command=self.guardar)
        self.btn_guardar.grid(row=0, column=0, columnspan=2, sticky="ew")
        ctk.CTkButton(botones, text="Nuevo", height=34, fg_color="transparent", border_width=1,
                      text_color=("gray20", "gray90"), command=self.nuevo).grid(row=1, column=0, sticky="ew", padx=(0, 4), pady=(8, 0))
        self.btn_eliminar = ctk.CTkButton(botones, text="Eliminar", height=34, fg_color="#c0392b",
                                          hover_color="#962d22", command=self.eliminar)
        self.btn_eliminar.grid(row=1, column=1, sticky="ew", padx=(4, 0), pady=(8, 0))
        self.nuevo()

    def _campo(self, padre, fila, etiqueta, clave, ejemplo):
        ctk.CTkLabel(padre, text=etiqueta, anchor="w").grid(row=fila, column=0, sticky="ew", padx=20, pady=(8, 0))
        e = ctk.CTkEntry(padre, textvariable=self.vars[clave], height=34, placeholder_text=f"ej. {ejemplo}")
        e.grid(row=fila + 1, column=0, sticky="ew", padx=20)
        return e

    # -- acciones -----------------------------------------------------------
    def refrescar(self, seleccionar=None):
        try:
            filas = self.repo.listar(self.busqueda.get())
        except ErrorBD as e:
            messagebox.showerror("Error", str(e))
            return
        self.tabla.delete(*self.tabla.get_children())
        for i, f in enumerate(filas):
            self.tabla.insert("", "end", iid=str(f[0]), values=f, tags=("par" if i % 2 == 0 else "impar",))
        if seleccionar is not None and self.tabla.exists(str(seleccionar)):
            self.tabla.selection_set(str(seleccionar))
            self.tabla.see(str(seleccionar))
        self._estado.configure(text=f"{len(filas)} país(es)  ·  {SERVER}  ·  {DATABASE}")

    def _al_seleccionar(self, _e):
        sel = self.tabla.selection()
        if not sel:
            return
        v = self.tabla.item(sel[0], "values")
        self.id_seleccionado = int(v[0])
        for (clave, *_), valor in zip(COLUMNAS[1:], v[1:]):
            self.vars[clave].set(valor)
        self.titulo_form.configure(text=f"Editar país #{v[0]}")
        self.btn_guardar.configure(text="Guardar cambios")
        self.btn_eliminar.configure(state="normal")

    def nuevo(self):
        self.id_seleccionado = None
        if hasattr(self, "tabla") and self.tabla.selection():
            self.tabla.selection_remove(self.tabla.selection())
        for var in self.vars.values():
            var.set("")
        self.titulo_form.configure(text="Nuevo país")
        self.btn_guardar.configure(text="Agregar país")
        self.btn_eliminar.configure(state="disabled")
        self.nombre.focus()

    def _datos(self):
        return {k: v.get().strip() or None for k, v in self.vars.items()}

    def guardar(self):
        try:
            if self.id_seleccionado is None:
                nuevo_id = self.repo.alta(self._datos())
                self._estado.configure(text=f"País #{nuevo_id} agregado.")
                self.nuevo()
                self.refrescar(nuevo_id)
            else:
                self.repo.modificacion(self.id_seleccionado, self._datos())
                id_ = self.id_seleccionado
                self.refrescar(id_)
                self._estado.configure(text=f"País #{id_} modificado.")
        except ErrorBD as e:
            messagebox.showwarning("No se pudo guardar", str(e))

    def eliminar(self):
        if self.id_seleccionado is None:
            return
        nombre = self.vars["nombre"].get()
        if not messagebox.askyesno("Eliminar país", f"¿Eliminar a {nombre}?\nEsta acción no se puede deshacer."):
            return
        try:
            self.repo.baja(self.id_seleccionado)
        except ErrorBD as e:
            messagebox.showwarning("No se pudo eliminar", str(e))
            return
        self.nuevo()
        self.refrescar()
        self._estado.configure(text=f"{nombre} eliminado.")


def main():
    raiz = tk.Tk()
    raiz.withdraw()
    try:
        repo = RepositorioPaises()
    except pyodbc.Error as e:
        messagebox.showerror(
            "Sin conexión",
            f"No se pudo conectar a {SERVER} / {DATABASE}.\n\n{_limpiar(e)}")
        return
    finally:
        raiz.destroy()
    App(repo).mainloop()


if __name__ == "__main__":
    main()
