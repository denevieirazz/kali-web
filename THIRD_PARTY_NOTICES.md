# Third-Party Software Notices and Licenses

This project, **CloudOS-Unified**, incorporates selected open-source components and architecture patterns from other projects under their respective licenses.

---

## 1. daedalOS
- **Project**: daedalOS (by Dustin Brett)
- **Repository**: https://github.com/DustinBrett/daedalOS
- **License**: MIT License

### MIT License Text (daedalOS):
```
MIT License

Copyright (c) Dustin Brett

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

### Components & Concepts Adapted:
1. **Window Management & Interactions**:
   - Resizing, snapping, and dragging concepts adapted to React 19 + TypeScript.
   - Window state persistence algorithms.
2. **File Explorer & Navigation**:
   - Breadcrumb navigation and view mode switching (Grid / List).
   - Context menu trigger architecture.
3. **Taskbar & Start Menu**:
   - Process grouping and search filtering.

---

## 2. ObsidianOS
- **Project**: ObsidianOS
- **Repository**: https://github.com/antojunimaia-ui/ObsidianOS
- **License**: Unspecified / Proprietary
- **Source Used**: Visual styles, OSL (Obsidian Scripting Language) parser/lexer concepts, OPFS low-level interaction driver, and Kernel lifecycle patterns.

---

## 3. CloudOS
- **Project**: CloudOS
- **Source Used**: Authentication models, real terminal WebSocket/PTY architecture, process monitoring, and system metrics integrations.
