# CloudOS RC1.2 — Registro de Correções, Diagnósticos e Regressões

Este documento registra as inconformidades e fragilidades diagnosticadas durante a bateria de testes de release do RC1.2, juntamente com suas correções implementadas e validações empíricas.

---

## BUG-RC12-01: Identidade Hardcoded de Desenvolvedor no Menu Iniciar e Configurações
- **Severidade:** Média (Distribuição & Privacidade)
- **Diagnóstico:** A varredura de caminhos de desenvolvimento identificou que o widget `StartFooter` exibia fixamente o nome "Douglas", a tela Sobre continha a linha "Desenvolvido para Douglas", e dados de preview apontavam para `\\wsl.localhost\Ubuntu\home\dougl`.
- **Causa Raiz:** Resquícios de desenvolvimento dos protótipos iniciais do shell.
- **Solução Implementada:**
  - `start_footer.dart`: Utilização dinâmica de `Platform.environment['USERNAME'] ?? 'Usuário'`.
  - `cloudos_preview_data.dart`: Rotação para caminho genérico `\\wsl.localhost\Ubuntu\home\user`.
  - `settings_window.dart`: Atualização para "CloudOS Provedor de Shell Autônomo para Windows."
- **Validação:** `flutter analyze` aprovado (0 warnings) e 156 testes unitários aprovados.

---

## BUG-RC12-02: Ausência de Limite Superior para Histórico e Pins de Aplicativos
- **Severidade:** Baixa (Consumo de Memória / Resiliência)
- **Diagnóstico:** Em `CloudOSPreferences.fromJson`, listas de aplicativos fixados (`pinnedAppIds`) e recentes (`recentAppIds`) aceitavam quantidade ilimitada de itens se um arquivo corrompido ou malicioso fosse carregado.
- **Causa Raiz:** Ausência de limites de corte (*bounding*) na desserialização do JSON.
- **Solução Implementada:**
  - Inclusão de corte superior em 50 para `pinnedAppIds` e 20 para `recentAppIds`.
- **Validação:** Adição de caso de teste específico em `desktop/CloudOS.FlutterShell/test/cloudos_preferences_test.dart` com 100 itens simulados; aprovado com 100% de sucesso.

---

## BUG-RC12-03: Mecanismo de Downgrade Baseado Apenas em Build Inteira
- **Severidade:** Média (Integridade de Atualização)
- **Diagnóstico:** `Invoke-Update` em `scripts/installer/CloudOS.Maintenance.ps1` verificava apenas `$newBuild < $curBuild`. Caso as tags de build fossem omitidas ou versões SemVer como `21.0.0-rc.1` fossem atualizadas para versões inferiores sem mudança de build numérica, a rejeição poderia falhar.
- **Causa Raiz:** Falta de um comparador nativo em conformidade com o padrão SemVer 2.0.0.
- **Solução Implementada:**
  - Criação da função `Compare-CloudOSSemVer` com suporte a Major, Minor, Patch, sufixos pré-release delimitados por pontos e precedência alfanumérica/numérica.
  - Integração no fluxo de `Invoke-Update` para rejeição preventiva de regressões SemVer antes de iniciar o staging.
- **Validação:** Casos de teste SemVer (`21.0.0-rc.1 < 21.0.0-rc.2`, `21.0.9 < 21.0.10`, `22.0.0 > 21.99.99`, `21.0.0-rc.1.1 < 21.0.0-rc.1.2`) executados com êxito. Todos os 5 contratos de instalador/updater continuam passando.

---

## BUG-RC12-04: Metadados PE e pubspec Desalinhados da Versão Canônica
- **Severidade:** Baixa (Release Engineering)
- **Diagnóstico:** O arquivo `pubspec.yaml` mantinha a versão padrão `0.1.0+19` e o arquivo `Runner.rc` continha informações de empresa genéricas (`com.example`), fazendo com que as propriedades de arquivo do executável do Flutter Shell exibissem dados padrão.
- **Causa Raiz:** O pipeline compilava o Flutter sem atualizar o arquivo raiz de pacote e os recursos do Windows Runner.
- **Solução Implementada:**
  - Atualização do `pubspec.yaml` para `version: 21.0.0+33`.
  - Atualização dos campos `CompanyName`, `FileDescription` e `ProductName` em `desktop/CloudOS.FlutterShell/windows/runner/Runner.rc`.
- **Validação:** Compilação do executável com metadados PE válidos e aprovada pelo Inno Setup.
