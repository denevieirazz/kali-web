export const browserLauncherOpening = () => ({
  status: 'opening',
  code: null,
  message: 'Abrindo o Navegador CloudOS…',
  shouldClose: false,
});

export function browserLauncherSuccess(result) {
  if (result?.opened === true && result?.windowVisible === true) {
    return {
      status: 'success',
      code: null,
      message: '',
      shouldClose: true,
    };
  }

  return {
    status: 'error',
    code: result?.code || 'BROWSER_WINDOW_NOT_VISIBLE',
    message: result?.message || 'O Host respondeu, mas a janela nativa do Navegador não ficou visível.',
    shouldClose: false,
  };
}

export function browserLauncherFailure(error) {
  const code = typeof error?.code === 'string' && error.code.length > 0
    ? error.code
    : 'BROWSER_OPEN_FAILED';
  const message = error instanceof Error && error.message.length > 0
    ? error.message
    : 'O navegador nativo não pôde ser aberto.';
  return {
    status: 'error',
    code,
    message,
    shouldClose: false,
  };
}
