import React, { useEffect, useState } from 'react';
import type { NotificationData } from '../../types';

interface NotificationItemProps {
  notification: NotificationData;
  onDismiss: (id: string) => void;
  isToast?: boolean;
}

export const NotificationItem: React.FC<NotificationItemProps> = ({ 
  notification, 
  onDismiss, 
  isToast = false 
}) => {
  const [isClosing, setIsClosing] = useState(false);
  const [progress, setProgress] = useState(100);

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(() => onDismiss(notification.id), 300);
  };

  useEffect(() => {
    if (!isToast || !notification.duration) return;

    const interval = 50; // ms
    const totalDuration = notification.duration || 5000;
    const step = (interval / totalDuration) * 100;

    const timer = setInterval(() => {
      setProgress(prev => {
        const next = Math.max(0, prev - step);
        if (next === 0) {
          clearInterval(timer);
          handleClose();
        }
        return next;
      });
    }, interval);

    return () => clearInterval(timer);
  }, [isToast, notification.duration]);

  const getTimeAgo = (timestamp: number) => {
    const diff = Date.now() - timestamp;
    if (diff < 60000) return 'agora';
    const mins = Math.floor(diff / 60000);
    if (mins < 60) return `${mins}m`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h`;
    return new Date(timestamp).toLocaleDateString();
  };

  return (
    <div className={`notification-toast ${notification.type} ${isClosing ? 'closing' : ''}`}>
      <div className="notification-icon">
        {notification.icon || (
          notification.type === 'info' ? 'ℹ️' :
          notification.type === 'success' ? '✅' :
          notification.type === 'warning' ? '⚠️' :
          '❌'
        )}
      </div>
      
      <div className="notification-content">
        <div className="notification-header">
          <span className="notification-title">{notification.title}</span>
          {!isToast && <span className="notification-time">{getTimeAgo(notification.timestamp)}</span>}
        </div>
        
        <div className="notification-message">{notification.message}</div>
        
        {notification.actions && notification.actions.length > 0 && (
          <div className="notification-actions">
            {notification.actions.map((action, i) => (
              <button 
                key={i} 
                className="notification-action-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  action.onClick();
                  handleClose();
                }}
              >
                {action.label}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="notification-close" onClick={(e) => {
        e.stopPropagation();
        handleClose();
      }}>
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
      </div>

      {isToast && notification.duration && (
        <div className="notification-progress" style={{ width: `${progress}%` }} />
      )}
    </div>
  );
};
