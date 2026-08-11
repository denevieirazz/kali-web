import React from 'react';
import { useSystem } from '../../stores/systemStore';
import { NotificationItem } from './NotificationItem';
import './Notifications.css';

export const NotificationContainer: React.FC = () => {
  const { notifications, dismissNotification, bootPhase } = useSystem();

  // Handle case where we only want to show recent/unread toasts
  // For toast display, maybe only show notifications from last X seconds 
  // or that haven't been "seen" in toast form.
  // For now, we'll show all notifications that haven't been dismissed yet.
  
  if (bootPhase !== 'desktop') return null;

  return (
    <div className="notifications-container">
      {notifications.map(notification => (
        <NotificationItem 
          key={notification.id} 
          notification={notification} 
          onDismiss={dismissNotification}
          isToast={true}
        />
      ))}
    </div>
  );
};
