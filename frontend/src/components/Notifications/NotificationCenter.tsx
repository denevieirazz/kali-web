import React from 'react';
import { useSystem } from '../../stores/systemStore';
import { NotificationItem } from './NotificationItem';
import './Notifications.css';

export const NotificationCenter: React.FC = () => {
  const { 
    showNotificationCenter, 
    notifications, 
    dismissNotification, 
    clearNotifications,
    toggleNotificationCenter
  } = useSystem();

  return (
    <>
      {/* Backdrop for outside click closing */}
      {showNotificationCenter && (
        <div 
          className="notification-center-backdrop"
          style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, zIndex: 9997 }}
          onClick={toggleNotificationCenter}
        />
      )}

      <div className={`notification-center ${showNotificationCenter ? 'open' : ''}`}>
        <div className="notification-center-header">
          <h2>Notificações</h2>
          {notifications.length > 0 && (
            <button className="clear-all-btn" onClick={clearNotifications}>
              Limpar tudo
            </button>
          )}
        </div>

        <div className="notification-list">
          {notifications.length > 0 ? (
            notifications.map(notification => (
              <NotificationItem 
                key={notification.id} 
                notification={notification} 
                onDismiss={dismissNotification}
              />
            ))
          ) : (
            <div className="notification-empty">
              <div className="notification-empty-icon">🔔</div>
              <p>Nenhuma notificação por enquanto.</p>
            </div>
          )}
        </div>
      </div>
    </>
  );
};
