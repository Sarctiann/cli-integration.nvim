# Sidebar Refactor: Eliminar Proxy Split

## Overview

Eliminar la ventana proxy split (vsplit de background) del modo sidebar. El float window se posiciona directamente en el lado derecho del editor sin necesidad de un split de navegación artificial.

## Cambios Principales

### 1. Estructura de Window

**Antes:**
```
+----------------+------------------+
|                |  Proxy Split     |  <- Empty buffer, winfixwidth=true
|   Normal       |  (navigation)   |  <- WinEnter -> redirects to float
|   Windows      +------------------+
|                |  Float Window    |  <- Terminal buffer (locked)
+----------------+------------------+
```

**Después:**
```
+----------------+------------------------+
|                |                        |
|   Normal       |  Float Window          |  <- Terminal buffer (locked)
|   Windows      |  (directo a la derecha)|
|                |                        |
+----------------+------------------------+
```

El float usa `col = vim.o.columns - float_width` para posicionarse en el borde derecho.

### 2. Navegación

- **C-h desde float**: `wincmd h` va al vecino izquierdo (window a la izquierda del float)
- **C-l desde float**: `wincmd l` va al vecino derecho (o se queda si no hay más windows)
- **C-j/k**: igual que antes (arriba/abajo)
- El float tiene zindex=45 para estar sobre otras ventanas flotantes

### 3. Fullwidth Toggle

Mantiene el mismo comportamiento:
- Sidebar -> fullwidth: float se expande a ancho completo (col=0, width=editor_width)
- Fullwidth -> sidebar: float restaura a ancho configurado en el lado derecho

Ya no hay split que cerrar/abrir - solo cambia la geometría del float.

### 4. M.sidebars Simplificado

**Antes:**
```lua
M.sidebars[float_win] = {
  split_win = number,
  split_buf = number,
  terminal_buf = number,
  width_config = number,
  padding = number,
  win_opts = table,
  is_expanded = boolean,
  list_buffer = boolean,
}
```

**Después:**
```lua
M.sidebars[float_win] = {
  terminal_buf = number,
  width_config = number,
  padding = number,
  win_opts = table,
  is_expanded = boolean,
  list_buffer = boolean,
}
```

### 5. Funciones Eliminadas

- `create_proxy_split()` - eliminada completamente
- `ensure_split_inert()` - eliminada completamente
- `is_sidebar_split_win()` - eliminada
- `is_integration_proxy_split()` - eliminada
- `apply_split_width()` - eliminada (no hay split que resize)

### 6. Funciones Modificadas

- `create_sidebar_layout()` - elimina creación de proxy split, usa float directo
- `update_sidebar_geometry()` - elimina lógica de split, solofloat geometry
- `resize_sidebars()` - elimina sync con split, solofloat resize
- `compute_sidebar_target_geometry()` - elimina split como referencia

### 7. Autocmds Eliminados

- WinEnter en split_buf para redirigir a float - eliminado
- QuitPre en split_buf para cerrar float - eliminado
- WinClosed para cleanup de split - simplificado (solo limpia M.sidebars)

## Archivos a Modificar

1. `lua/cli-integration/window.lua` - lógica principal
2. `docs/superpowers/specs/window-system-architecture.md` - actualizar diagrama
3. `docs/superpowers/specs/module-window.md` - actualizar si es necesario
4. `README.md` - eliminar referencias a proxy split
5. `AGENTS.md` - actualizar restricciones si es necesario

## Comportamiento Preservado

- Buffer lock (BufWinEnter protection)
- C-h/j/k/l navegación desde terminal
- start_insert_on_click
- list_buffer
- auto_close
- Padding (foldcolumn)
- Resize handling (editor resize recalcula desde width_config)