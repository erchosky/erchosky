# Avisos de terceros y procedencia (Third-Party Notices)

## Disk Jockey (MIT License)

- **Repositorio de origen**: https://github.com/bmcreations/disk-jockey
- **Commit revisado**: `f28f7e1914dcc74d7c29b0cebda516fb9394ba20`
- **Versión declarada**: `0.3.0`
- **Alcance adaptado en Brisa**:
  - Escenarios de descubrimiento e inventario para macOS en `Sources/BrisaCore/Resources/brisa-catalog.json` (`diskJockeyRules` y metadatos `upstreamProvenance`), integrados exclusivamente en modo inventario (`listOnly: true`, sin ejecución de comandos `cmd:`).
  - Conceptos de inspección de solo lectura reimplementados de forma nativa y tipada en Swift para:
    - Detección de compilaciones potencialmente huérfanas (`Sources/BrisaCore/OrphanBuildDetector.swift`, basado en el modelo de `WorkspacePath` de `info.plist` y `workspaceRoot` de `XcodeBuildMCP`/`MobileBuildMCP`).
    - Descubrimiento e inspección en solo lectura de árboles de trabajo Git y artefactos anclados a proyecto (`Sources/BrisaCore/WorktreeAndProjectDetector.swift`).
    - Diagnóstico de memoria, swap, presión de memoria e instantáneas locales APFS en solo lectura (`Sources/BrisaCore/SystemDiagnostics.swift`).

```text
MIT License

Copyright (c) 2026 bmcreations

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
