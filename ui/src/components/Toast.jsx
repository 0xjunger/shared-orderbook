import { useState, useCallback, useRef } from 'react';

let _addToast = () => {};

/** Global imperative API — call from anywhere */
export function toast(message, type = 'error') {
  _addToast({ message, type, id: Date.now() + Math.random() });
}

export function ToastContainer() {
  const [toasts, setToasts] = useState([]);
  const timers = useRef({});

  _addToast = useCallback((t) => {
    setToasts((prev) => [...prev, t]);
    timers.current[t.id] = setTimeout(() => {
      setToasts((prev) => prev.filter((x) => x.id !== t.id));
      delete timers.current[t.id];
    }, 5000);
  }, []);

  const dismiss = (id) => {
    clearTimeout(timers.current[id]);
    delete timers.current[id];
    setToasts((prev) => prev.filter((x) => x.id !== id));
  };

  return (
    <div className="toast-container">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`toast toast-${t.type}`}
          onClick={() => dismiss(t.id)}
        >
          {t.message}
        </div>
      ))}
    </div>
  );
}
