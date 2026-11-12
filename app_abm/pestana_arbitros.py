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

 Fecha: 12/11/2026
 Archivo: pestana_arbitros.py
 Objetivo: Pestaña de la aplicación para importar árbitros desde un CSV con
           Arbitraje.usp_ImportarArbitrosCSV. La aplicación no lee el
           archivo: le pasa la ruta al SP, que lo lee, valida cada fila, carga
           las válidas y guarda las rechazadas en Arbitraje.ERRORES_ARBITRO.
           Acá solo se muestra el resumen y lo que pasó con cada fila.
================================================================================
"""

from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import customtkinter as ctk

CARPETA_CSV = Path(__file__).resolve().parent.parent / "datos" / "pruebas"

COLUMNAS = [
    # (clave, título, ancho, alineación)
    ("linea", "Línea", 60, "center"),
    ("pais", "País", 60, "center"),
    ("nombre", "Nombre", 130, "w"),
    ("apellido", "Apellido", 170, "w"),
    ("categoria", "Categoría", 130, "w"),
    ("fecha_nacimiento", "Nacimiento", 100, "center"),
    ("idiomas", "Idiomas", 80, "w"),
    ("accion", "Resultado", 110, "w"),
    ("motivos", "Motivos", 420, "w"),
]


class ImportarArbitros(ctk.CTkFrame):
    def __init__(self, padre, repo, estilo_tabla):
        super().__init__(padre, fg_color="transparent")
        self.repo = repo
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(3, weight=1)

        ctk.CTkLabel(self, text="Importar árbitros", font=ctk.CTkFont(size=20, weight="bold")).grid(
            row=0, column=0, sticky="w", padx=12, pady=(10, 0))

        barra = ctk.CTkFrame(self)
        barra.grid(row=1, column=0, sticky="ew", padx=12, pady=10)
        barra.grid_columnconfigure(1, weight=1)
        ctk.CTkLabel(barra, text="Archivo .csv").grid(row=0, column=0, padx=(12, 6), pady=10)
        self.txt_ruta = ctk.CTkEntry(
            barra, placeholder_text="pais,nombre,apellido,categoria,fecha_nacimiento,idiomas")
        self.txt_ruta.grid(row=0, column=1, sticky="ew", padx=(0, 8))
        ctk.CTkButton(barra, text="Elegir…", width=90, fg_color="transparent", border_width=1,
                      text_color=("gray20", "gray85"), command=self.elegir).grid(row=0, column=2, padx=(0, 8))
        ctk.CTkButton(barra, text="Importar", width=100, command=self.importar).grid(row=0, column=3, padx=(0, 12))

        self.lbl_resumen = ctk.CTkLabel(self, text="", anchor="w", text_color=("gray35", "gray65"))
        self.lbl_resumen.grid(row=2, column=0, sticky="ew", padx=12, pady=(0, 6))

        contenedor = ctk.CTkFrame(self, fg_color="transparent")
        contenedor.grid(row=3, column=0, sticky="nsew", padx=12, pady=(0, 10))
        contenedor.grid_columnconfigure(0, weight=1)
        contenedor.grid_rowconfigure(0, weight=1)
        self.tabla = ttk.Treeview(contenedor, columns=[c[0] for c in COLUMNAS], show="headings",
                                  style=estilo_tabla, selectmode="browse")
        for clave, titulo, ancho, alineacion in COLUMNAS:
            self.tabla.heading(clave, text=titulo)
            self.tabla.column(clave, width=ancho, anchor=alineacion, stretch=(clave == "motivos"))
        self.tabla.tag_configure("RECHAZADO", foreground="#e05a4f")
        self.tabla.grid(row=0, column=0, sticky="nsew")
        vertical = ctk.CTkScrollbar(contenedor, command=self.tabla.yview)
        vertical.grid(row=0, column=1, sticky="ns")
        horizontal = ctk.CTkScrollbar(contenedor, orientation="horizontal", command=self.tabla.xview)
        horizontal.grid(row=1, column=0, sticky="ew")
        self.tabla.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)

    def elegir(self):
        ruta = filedialog.askopenfilename(title="Elegir el CSV de árbitros", initialdir=CARPETA_CSV,
                                          filetypes=[("CSV", "*.csv")])
        if ruta:
            self.txt_ruta.delete(0, "end")
            self.txt_ruta.insert(0, str(Path(ruta)))  # con barras de Windows, como la espera SQL Server

    def importar(self):
        ruta = self.txt_ruta.get().strip()
        try:
            resumen, filas = self.repo.importar_arbitros(ruta)
        except Exception as e:  # ruta inválida, archivo ilegible o con otras columnas: no se importó nada
            messagebox.showerror("No se pudo importar el archivo", str(e))
            return
        self.tabla.delete(*self.tabla.get_children())
        for f in filas:
            # Si una fila tiene varios motivos, el SP los separa con saltos de línea.
            motivos = " ".join((f.motivos or "").split("\r\n"))
            valores = (f.linea, f.pais or "", f.nombre or "", f.apellido or "", f.categoria or "",
                       f.fecha_nacimiento or "", f.idiomas or "", f.accion or "", motivos)
            self.tabla.insert("", "end", values=valores, tags=(f.accion,))
        self.lbl_resumen.configure(
            text=f"Importación {resumen.id_importacion}: {resumen.leidos} leídos, {resumen.insertados} insertados, "
                 f"{resumen.actualizados} actualizados, {resumen.sin_cambios} sin cambios y "
                 f"{resumen.rechazados} rechazados (guardados en Arbitraje.ERRORES_ARBITRO).")
