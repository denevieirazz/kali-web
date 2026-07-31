// Serviço para Notificações Nativas do Navegador e Sistema
export const initNotifications = () => {
  if (!("Notification" in window)) {
    console.log("[CloudOS] Navegador não suporta notificações.");
    return;
  }

  if (Notification.permission === 'default') {
    Notification.requestPermission().then(permission => {
      if (permission === 'granted') {
        new Notification('CloudOS Tático', {
          body: 'Sistema de notificações ativado. Pronto para operar.',
          icon: '/favicon.ico'
        });
      }
    });
  }
};

export const showNotification = (title, body, onClickCallback) => {
  if (!("Notification" in window)) return;

  if (Notification.permission === 'granted') {
    const notification = new Notification(title, {
      body: body,
      icon: '/favicon.ico',
      silent: false
    });

    if (onClickCallback) {
      notification.onclick = () => {
        window.focus();
        onClickCallback();
        notification.close();
      };
    }
  } else if (Notification.permission !== 'denied') {
    initNotifications();
  }
};
