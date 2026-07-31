/**
 * AutoFix Script - CloudOS
 * Roda automaticamente na inicialização para corrigir problemas de cache, 
 * tokens inválidos e garantir que o sistema esteja pronto para qualquer usuário.
 */
export const runAutoFix = () => {
  try {
    // 1. Corrige o erro do Token 'default'
    const token = localStorage.getItem('cloudos_token');
    const invalidTokens = ['default', 'null', 'undefined', 'false', ''];
    
    if (invalidTokens.includes(token)) {
      console.warn('[AutoFix] Token inválido detectado. Limpando localStorage...');
      localStorage.removeItem('cloudos_token');
    }

    // 2. Limpa estado do terminal corrompido com wsToken='default'
    const terminalTabs = localStorage.getItem('terminal_tabs');
    if (terminalTabs && terminalTabs.includes('"default"')) {
      console.warn('[AutoFix] Abas do terminal com token default detectadas. Limpando...');
      localStorage.removeItem('terminal_tabs');
    }

    // 3. Limpa estado de janelas corrompidas (se tiver tamanho 0)
    const windowsState = localStorage.getItem('cloudos_window_state');
    if (windowsState) {
      const parsed = JSON.parse(windowsState);
      if (Array.isArray(parsed)) {
        const cleanState = parsed.filter(w => 
          (w.w === undefined || w.w > 100) && 
          (w.h === undefined || w.h > 100) && 
          !isNaN(w.x) && !isNaN(w.y)
        );
        localStorage.setItem('cloudos_window_state', JSON.stringify(cleanState));
      }
    }

    console.log('[AutoFix] Verificação de ambiente concluída com sucesso.');
  } catch (error) {
    console.error('[AutoFix] Erro ao limpar ambiente:', error);
  }
};
