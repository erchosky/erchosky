# Compilar, firmar y distribuir

## Construcción local

`bash scripts/package.sh` congela Sources, Tests y Package.swift en un directorio temporal controlado, compila en Release con el SDK instalado, copia los recursos al bundle, incluye el icono original y aplica firma ad hoc hardened runtime. El snapshot evita cambios de timestamps del workspace durante compilación y se elimina al terminar. El binario de la interfaz se empaqueta como `Contents/MacOS/Brisa`. Las CLI se entregan junto al bundle para que `brisa` pueda localizarlo.

No hay dependencias de red ni recursos descargados. Los scripts no instalan certificados, no solicitan Full Disk Access, no crean LaunchAgents ni modifican proveedores de IA.

El workspace observado adjunta `com.apple.fileprovider.fpfs#P` y `com.apple.FinderInfo` automáticamente a bundles, y cambia timestamps subsegundo sin alterar contenido. Se firma fuera del workspace y se guarda una copia ejecutable en `~/Library/Caches/dev.brisa.build/Brisa.app`. `dist/Brisa.app` es un enlace local a ella; `dist/Brisa.zip` contiene el bundle firmado sin esos metadatos y es el artefacto autocontenido. Puedes elegir otra carpeta **local no sincronizada** con `BRISA_LOCAL_DIR=/ruta/local`. Cierra la app antes de recompilar. No se presenta el enlace como una app portable.

Para regenerar el icono propio:

```sh
swift scripts/make-icon.swift
iconutil -c icns packaging/Brisa.iconset -o packaging/Brisa.icns
```

## Firma del propietario

Configura tu identidad instalada, nunca una identidad ajena:

```sh
BRISA_SIGN_IDENTITY='Developer ID Application: Propietario (TEAMID)' bash scripts/package.sh
codesign --verify --deep --strict --verbose=2 dist/Brisa.app
```

Antes de distribuir, firma también `brisa` y `brisa-mcp` con tu Developer ID y hardened runtime. El script solo garantiza la firma del bundle de la app; los binarios auxiliares conservan la firma que les dé el toolchain local hasta que tú los firmes para distribución.

```sh
codesign --force --options runtime --timestamp --sign 'Developer ID Application: Propietario (TEAMID)' dist/brisa
codesign --force --options runtime --timestamp --sign 'Developer ID Application: Propietario (TEAMID)' dist/brisa-mcp
```

## Notarización

Se requiere una cuenta de desarrollador del propietario y un perfil previamente guardado en su llavero. El proyecto no crea ni lee credenciales por su cuenta. El ejemplo asume que `BrisaNotary` ya existe:

```sh
xcrun notarytool submit dist/Brisa.zip --keychain-profile BrisaNotary --wait
xcrun stapler staple dist/Brisa.app
xcrun stapler validate dist/Brisa.app
spctl --assess --type execute --verbose=2 dist/Brisa.app
```

Los binarios auxiliares requieren su propio flujo de notarización en un archivo o instalador firmado que los incluya. **No se ha ejecutado firma Developer ID, envío a Apple ni notarización en este proyecto.** La firma ad hoc local no sustituye ese proceso ni garantiza aprobación de Gatekeeper en otro Mac.

## Reproducibilidad y compatibilidad

El código puede compilarse desde cero con un toolchain compatible. No se afirma identidad binaria bit a bit: SDK, versión de Swift, arquitectura, rutas de depuración, timestamps y firma influyen. Guarda las versiones de herramientas y el resultado de `shasum -a 256` de los artefactos de cada release.

La compilación real registrada corresponde al Mac de desarrollo descrito en VERIFICATION.md. El deployment target es macOS 14. Falta verificar macOS 14/15/26, Intel y binarios universales. No se declara soporte probado para sistemas que no se han ejecutado.

## Actualizaciones

No hay feed ni descargador de actualizaciones. El comando `update` devuelve `available:false`. No se acepta una actualización sin firma ni se pide al usuario desactivar Gatekeeper. Para incorporar actualizaciones automáticas harían falta un proveedor adecuado, claves del propietario, validación de firma, protección de rollback y pruebas del ciclo completo. Un documento de diseño no se presenta como ese sistema implementado.

## Desinstalar

1. Sal de Brisa con su menú o `brisa quit`, después de terminar tareas activas.
2. Elimina únicamente la copia de `Brisa.app` y los ejecutables `brisa` / `brisa-mcp` que hayas instalado. La copia local de desarrollo está en `~/Library/Caches/dev.brisa.build/Brisa.app`; `dist/Brisa.app` es solo un enlace. Puedes eliminar también ese directorio de caché propio cuando no lo necesites.
3. Opcionalmente, tras revisar o exportar el diario, elimina `~/Library/Application Support/Brisa` y el dominio propio de preferencias `dev.brisa.mac`. Esto elimina el historial y la capacidad de localizar restauraciones desde la app; no vacía la Papelera.
4. Si añadiste voluntariamente una configuración MCP a otro cliente, quita solo esa entrada `brisa`.

La app retira su socket al salir normalmente. Tras un cierre inesperado, la siguiente apertura recupera el socket obsoleto bajo su lock. El directorio temporal privado puede permanecer hasta la limpieza normal de macOS. No hay extensiones, demonios privilegiados, componentes de kernel ni inicio automático que desinstalar.
