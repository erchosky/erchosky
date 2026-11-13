# Brisa 🌬️

**Una app para macOS que te ayuda a entender qué está ocupando espacio en tu Mac y a limpiar lo que ya no necesitas.** Sin borrar cosas a lo loco: primero revisas qué va a pasar y decides tú.

Brisa vive en la barra de menús, así que puedes echar un vistazo rápido sin tener que abrir una ventana enorme. Y si quieres investigar más a fondo, también tiene una ventana principal.

## ¿Qué puedes hacer con Brisa?

- **Ver cómo va tu Mac:** consulta el espacio libre, la CPU, la RAM, el swap y la presión de memoria.
- **Explorar qué ocupa espacio:** revisa cachés, descargas, máquinas virtuales, archivos temporales y otras categorías. También tienes un mapa visual para hacerte una idea de un vistazo.
- **Limpiar archivos de proyectos:** encuentra cosas que se pueden volver a generar, como `node_modules` o carpetas de compilación.
- **Buscar archivos duplicados:** compara su contenido para detectar copias exactas y elegir cuáles sobran.
- **Revisar aplicaciones:** busca archivos relacionados con una app antes de desinstalarla.
- **Ordenar herramientas de desarrollo:** revisa cachés de Homebrew, npm, pnpm y Yarn, además de recursos de Docker.

## ¿Y si borro algo que no quería?

La idea es que **sepas qué vas a hacer antes de hacerlo**. Brisa muestra un resumen con los elementos seleccionados, su tamaño y si se pueden recuperar. Muchas operaciones utilizan la Papelera, pero algunas acciones de herramientas externas, como Docker, pueden ser irreversibles y se indican antes de confirmar.

Brisa no analiza ni limpia automáticamente al abrirse. Algunas carpetas necesitan que les des permiso, y la app indica cuando no ha podido acceder o completar un análisis. Aun así, revisa siempre lo seleccionado antes de confirmar: ninguna herramienta puede decidir por ti qué necesitas conservar.

## Requisitos

- macOS 14 o posterior para el proyecto. La compilación incluida en la entrega se ha generado para **Apple Silicon**; no incluye versión Intel.
- Para compilar: Xcode o Command Line Tools con Swift 6 o posterior, y Python 3.

## Compilar y abrir

Desde la carpeta del proyecto:

```bash
bash scripts/package.sh
open dist/Brisa.app
```

Al abrirla, pulsa **Empezar** y después **Analizar** cuando quieras revisar el espacio. También puedes abrir la ventana principal desde la barra de menús.

La app generada usa una firma local ad hoc: **no está firmada con Developer ID ni notarizada por Apple**. macOS puede mostrar un aviso de seguridad al abrirla. Consulta [la documentación de distribución](docs/DISTRIBUTION.md) para conocer los detalles.

## Para quienes quieran trastear

Brisa está hecha con **Swift y SwiftUI**. Además de la app, incluye una herramienta de terminal y un servidor MCP de solo lectura para integraciones locales.

```bash
./dist/brisa help
./dist/brisa status --json
```

Para ejecutar las comprobaciones del proyecto:

```bash
bash scripts/check.sh
```

Si quieres meterte en los detalles, aquí tienes la [documentación técnica](README-TECNICO.md), la [arquitectura](docs/ARCHITECTURE.md), las [funciones](docs/FEATURES.md), la [verificación](docs/VERIFICATION.md) y los [avisos de terceros](THIRD_PARTY_NOTICES.md).

## Estado del proyecto

**Versión 0.1.0.** Es una primera versión, así que puede tener fallos o cosas que mejorar. Las funciones y sus límites están explicados con más detalle en la documentación del proyecto.
