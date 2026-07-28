import { useState } from 'react';

export const NotepadApp = () => {
  const [text, setText] = useState('Bem-vindo ao CloudOS Notepad!\n\nSalvamento automático local.');
  return <textarea className="notepad-area" value={text} onChange={(e) => setText(e.target.value)}></textarea>;
};
