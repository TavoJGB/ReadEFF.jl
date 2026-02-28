# ReadEFF

[![Build Status](https://github.com/TavoJGB/ReadEFF.jl/actions/workflows/CI.yml/badge.svg?branch=)](https://github.com/TavoJGB/ReadEFF.jl/actions/workflows/CI.yml?query=branch%3A)

**ReadEFF.jl** es un paquete de Julia diseñado para leer y procesar datos de la Encuesta Financiera de las Familias (EFF) del Banco de España. El paquete utiliza [DataReader.jl](https://github.com/TavoJGB/DataReader.jl) para manejar la lectura de datos multinivel (hogares e individuos) y la gestión de variables que cambian de nombre a través de diferentes oleadas de la encuesta.

## Instalación

```julia
using Pkg
Pkg.add(url="https://github.com/TavoJGB/DataReader.jl")
Pkg.add(url="https://github.com/TavoJGB/ReadEFF.jl")
```

## Uso Básico

```julia
using ReadEFF

# Especificar años e imputaciones a leer
identifier_ranges = (:year => [2002:3:2020;2022], :imputation => 1:5)

# Ruta al directorio con los archivos de la EFF
datadir = "path/to/eff/data"

# Leer datos de la EFF
eff_ii, eff_hh = read_eff(
    datadir, identifier_ranges;
    varlists_dir="var_lists", 
    varlist_filename="eff_vars.csv"
)
```

### Parámetros

- **`datadir`**: Directorio que contiene los archivos CSV de la EFF (formato: `section6_YYYY_impN.csv` y `other_sections_YYYY_impN.csv`)
- **`identifier_ranges`**: Named tuple que especifica:
  - `year`: Vector de años a leer (ej. `[2002, 2005, 2008, ..., 2022]`)
  - `imputation`: Rango de imputaciones (típicamente `1:5` para las 5 imputaciones de la EFF)
- **`varlists_dir`**: Directorio que contiene los archivos CSV con las listas de variables (por defecto: `"var_lists"`)
- **`varlist_filename`**: Nombre del archivo CSV con las variables a leer (por defecto: `"eff_vars.csv"`)
- **`preprocess`**: Función aplicada a la lista de variables antes de la lectura. Por defecto, añade las variables de cálculo de riqueza de `eff_vars_wealth.csv` y las marca como `"Internal"`. Se puede pasar una función propia para personalizar este paso.
- **`postprocess`**: Función aplicada a los DataFrames crudos después de la lectura. Por defecto, pivota, renombra, calcula variables derivadas y limpia. Se puede pasar una función propia para personalizar este paso.
- **`filefinder`**: Función que localiza los archivos CSV para un año e imputación dados. Por defecto busca `section6_YYYY_impN.csv` y `other_sections_YYYY_impN.csv`.

### Valores Devueltos

La función `read_eff` devuelve dos DataFrames:

- **`eff_ii`**: DataFrame con datos a nivel **individual** (un registro por persona)
  - Incluye identificadores: `year`, `hid` (household ID), `imputation`, `individual`
  - Variables calculadas: `head` (indicador de cabeza de familia), `age` (calculada a partir del año de nacimiento si falta)
  - Variables individuales por defecto en la varlist: `rel2hh`, `birthyear`, `age`, `gender`, `educ`, `lab_income_direct`, `lab_income_inkind`
  - Cualquier variable individual adicional incluida en la varlist.

- **`eff_hh`**: DataFrame con datos a nivel **hogar** (un registro por hogar)
  - Incluye identificadores: `year`, `hid`, `imputation`
  - Variables calculadas: `wealth` (riqueza neta), `h_tenure` (régimen de tenencia de vivienda), `weight` (peso muestral)
  - Variables del hogar por defecto en la varlist: `h_size`, `income`
  - Cualquier variable del hogar adicional incluida en la varlist.

## ¿Cómo Funciona el Sistema de Lectura?

### El Rol de DataReader.jl

**DataReader.jl** es la librería subyacente que proporciona la funcionalidad genérica para leer bases de datos con:
- **Estructura multinivel** (individuos dentro de hogares)
- **Variables que cambian de nombre** entre oleadas de la encuesta
- **Múltiples archivos** por período (la EFF divide sus datos en varios archivos CSV)

ReadEFF.jl configura DataReader.jl con las especificaciones concretas de la EFF mediante:
1. Funciones personalizadas para encontrar los archivos correctos
2. Preprocesamiento y postprocesamiento de los datos
3. Listas de variables en archivos CSV

### Los Archivos CSV de Variables

#### 1. `eff_vars.csv` - Variables Solicitadas por el Usuario

Este archivo define **qué variables quieres leer** de la EFF. Contiene columnas:

- **`varname`**: Nombre que tendrá la variable en el DataFrame final (ej. `age`, `income`, `educ`)
- **`varkey`**: Código original de la variable en la EFF (ej. `p1_2d`, `renthog`, `p1_5`)
- **`firsttime`**: Primer año en que aparece esta variable
- **`lasttime`**: Último año en que aparece esta variable
- **`level`**: Nivel de la variable (`individual` o `household`)

**Ejemplo:**
```csv
varname,varkey,firsttime,lasttime,level
age,p1_2d,2008,2099,individual
income,renthog,2002,2099,household
educ,p1_5,2002,2099,individual
```

**¿Por qué es necesario?**: Las variables de la EFF cambian de código entre oleadas. Por ejemplo:
- La edad puede estar codificada como `p1_2d` en unos años y de otra forma en otros
- Este archivo permite mapear consistentemente los códigos originales a nombres intuitivos
- DataReader.jl usa esta información para buscar automáticamente el código correcto según el año

#### 2. `eff_vars_wealth.csv` - Variables Auxiliares para Cálculo de Riqueza

Este archivo contiene **variables adicionales necesarias para calcular la riqueza neta**, pero que no necesariamente quieres en tu DataFrame final. Incluye:

- Variables de activos: valor de la vivienda principal, otras propiedades, negocios, activos financieros
- Variables de deudas: hipotecas, préstamos, deudas pendientes
- Más de 400 variables usadas en los cálculos de riqueza

**Formato:**
```csv
varname,varkey,firsttime,lasttime
pr_val,p2_5,2002,2099
pr_buyyear,p2_3,2002,2099
asset_firms_number,p4_102,2008,2099
```

**¿Por qué un archivo separado?**: 
- Estas variables son instrumentales para calcular `wealth` (riqueza neta)
- Se cargan automáticamente cuando pides variables a nivel hogar
- Se marcan como tipo `"Internal"` y se eliminan antes de devolver el resultado final
- Mantiene `eff_vars.csv` limpio y enfocado en las variables que realmente quieres analizar

### Flujo de Procesamiento

1. **Preprocesamiento** (`preprocess`):
   - Lee las variables solicitadas desde `eff_vars.csv`
   - Si hay variables de nivel hogar, añade automáticamente las variables de `eff_vars_wealth.csv`
   - Marca las variables del usuario como `"User"` y las de riqueza como `"Internal"`

2. **Lectura de Datos** (DataReader.jl):
   - Para cada año e imputación especificados:
     - Encuentra los archivos CSV correspondientes (`section6_*` y `other_sections_*`)
     - Lee las variables necesarias usando los códigos correctos para ese año
     - Combina datos de múltiples archivos por el ID del hogar

3. **Postprocesamiento** (`postprocess`):
   - Transforma datos de individuos de formato ancho a largo
   - Renombra variables a sus nombres intuitivos
   - Calcula variables adicionales:
     - `age`: edad (si falta, se calcula desde año de nacimiento)
     - `head`: indicador de cabeza de familia
     - `id`: identificador único de individuo
     - `wealth`: riqueza neta del hogar
     - `h_tenure`: régimen de tenencia de vivienda (`:owner`, `:renter`, `:notenure`)
   - Elimina individuos "fantasma": los datos originales almacenan las variables individuales como columnas a nivel de hogar (e.g., `age_1`, `age_2`, ..., hasta un máximo fijo), por lo que al pivotar a formato largo se crean filas para miembros inexistentes. Se eliminan cuando `individual > h_size`.
   - Elimina variables `"Internal"` (las de `eff_vars_wealth.csv`)
   - Ajusta el año (la encuesta pregunta sobre el año anterior)

## Estructura de Directorios Esperada

```
datadir/
├── section6_2002_imp1.csv
├── other_sections_2002_imp1.csv
├── section6_2002_imp2.csv
├── other_sections_2002_imp2.csv
├── ...
├── section6_2022_imp5.csv
└── other_sections_2022_imp5.csv
```

## Ejemplo Completo

```julia
using ReadEFF
using DataFrames

# Configuración
identifier_ranges = (:year => [2002, 2005, 2008, 2011, 2014, 2017, 2020, 2022], 
                     :imputation => 1:5)
datadir = "data/eff"

# Leer datos
eff_ii, eff_hh = read_eff(datadir, identifier_ranges)

# Explorar datos individuales
println("Dimensiones datos individuales: ", size(eff_ii))
println("Variables individuales: ", names(eff_ii))

# Explorar datos de hogares
println("Dimensiones datos hogares: ", size(eff_hh))
println("Variables de hogares: ", names(eff_hh))

# Análisis básico
using Statistics
println("Riqueza media por año:")
combine(groupby(eff_hh, :year), :wealth => mean)
```

## Personalización

### Lista de variables personalizada

Puedes crear tu propia lista de variables modificando `eff_vars.csv`:

1. Abre `var_lists/eff_vars.csv`
2. Añade las variables que necesites con el formato:
   ```csv
   varname,varkey,firsttime,lasttime,level
   mi_variable,p_codigo,2002,2099,individual
   ```
3. Consulta el cuestionario de la EFF para encontrar los códigos de variables

### `preprocess` y `postprocess` personalizados

Puedes reemplazar las funciones `preprocess` y `postprocess` por defecto pasando las tuyas como argumentos de palabra clave a `read_eff`. Esto es útil si quieres omitir o modificar pasos específicos del procesamiento (ej., cálculo de riqueza, ajuste del año, o computación de otras variables).

```julia
# Ejemplo: postprocess personalizado que conserva todas las variables
my_postprocess(df_ii_wide, df_hh, ivars, hvars) = (df_ii_wide, df_hh)

eff_ii, eff_hh = read_eff(
    datadir, identifier_ranges;
    postprocess=my_postprocess
)
```

Las firmas por defecto son:
- `preprocess(vars::DataFrame) -> DataFrame`
- `postprocess(df_ii_wide::DataFrame, df_hh::DataFrame, ivars::DataFrame, hvars::DataFrame) -> (DataFrame, DataFrame)`

## Soporte

Para problemas o preguntas:
- **ReadEFF.jl**: https://github.com/TavoJGB/ReadEFF.jl/issues
- **DataReader.jl**: https://github.com/TavoJGB/DataReader.jl/issues
