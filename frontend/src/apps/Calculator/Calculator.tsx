// ============================================
// Calculator App
// ============================================
import { useState } from 'react';
import './Calculator.css';

export default function CalculatorApp({}: { windowId: string }) {
  const [display, setDisplay] = useState('0');
  const [prevValue, setPrevValue] = useState<number | null>(null);
  const [operation, setOperation] = useState<string | null>(null);
  const [resetNext, setResetNext] = useState(false);
  const [history, setHistory] = useState('');

  const handleNumber = (num: string) => {
    if (resetNext) {
      setDisplay(num);
      setResetNext(false);
    } else {
      setDisplay(display === '0' ? num : display + num);
    }
  };

  const handleDecimal = () => {
    if (!display.includes('.')) {
      setDisplay(display + '.');
    }
  };

  const handleOperation = (op: string) => {
    const current = parseFloat(display);
    if (prevValue !== null && operation && !resetNext) {
      const result = calculate(prevValue, current, operation);
      setDisplay(String(result));
      setPrevValue(result);
      setHistory(`${result} ${op}`);
    } else {
      setPrevValue(current);
      setHistory(`${current} ${op}`);
    }
    setOperation(op);
    setResetNext(true);
  };

  const calculate = (a: number, b: number, op: string): number => {
    switch (op) {
      case '+': return a + b;
      case '−': return a - b;
      case '×': return a * b;
      case '÷': return b !== 0 ? a / b : 0;
      default: return b;
    }
  };

  const handleEquals = () => {
    if (prevValue !== null && operation) {
      const current = parseFloat(display);
      const result = calculate(prevValue, current, operation);
      setHistory(`${prevValue} ${operation} ${current} =`);
      setDisplay(String(result));
      setPrevValue(null);
      setOperation(null);
      setResetNext(true);
    }
  };

  const handleClear = () => {
    setDisplay('0');
    setPrevValue(null);
    setOperation(null);
    setResetNext(false);
    setHistory('');
  };

  const handleClearEntry = () => {
    setDisplay('0');
  };

  const handleBackspace = () => {
    if (display.length > 1) {
      setDisplay(display.slice(0, -1));
    } else {
      setDisplay('0');
    }
  };

  const handlePercent = () => {
    const current = parseFloat(display);
    if (prevValue !== null) {
      setDisplay(String(prevValue * current / 100));
    } else {
      setDisplay(String(current / 100));
    }
  };

  const handleNegate = () => {
    setDisplay(String(-parseFloat(display)));
  };

  const handleInverse = () => {
    const current = parseFloat(display);
    if (current !== 0) {
      setDisplay(String(1 / current));
    }
  };

  const handleSquare = () => {
    const current = parseFloat(display);
    setDisplay(String(current * current));
    setHistory(`sqr(${current})`);
  };

  const handleSqrt = () => {
    const current = parseFloat(display);
    setDisplay(String(Math.sqrt(current)));
    setHistory(`√(${current})`);
  };

  const formatDisplay = (val: string) => {
    const num = parseFloat(val);
    if (isNaN(num)) return val;
    if (val.endsWith('.')) return val;
    if (val.includes('.') && val.endsWith('0')) return val;
    if (Math.abs(num) >= 1e12) return num.toExponential(6);
    return num.toLocaleString('pt-BR', { maximumFractionDigits: 10 });
  };

  const buttons = [
    { label: '%', action: handlePercent, type: 'func' },
    { label: 'CE', action: handleClearEntry, type: 'func' },
    { label: 'C', action: handleClear, type: 'func' },
    { label: '⌫', action: handleBackspace, type: 'func' },
    { label: '1/x', action: handleInverse, type: 'func' },
    { label: 'x²', action: handleSquare, type: 'func' },
    { label: '√x', action: handleSqrt, type: 'func' },
    { label: '÷', action: () => handleOperation('÷'), type: 'op' },
    { label: '7', action: () => handleNumber('7'), type: 'num' },
    { label: '8', action: () => handleNumber('8'), type: 'num' },
    { label: '9', action: () => handleNumber('9'), type: 'num' },
    { label: '×', action: () => handleOperation('×'), type: 'op' },
    { label: '4', action: () => handleNumber('4'), type: 'num' },
    { label: '5', action: () => handleNumber('5'), type: 'num' },
    { label: '6', action: () => handleNumber('6'), type: 'num' },
    { label: '−', action: () => handleOperation('−'), type: 'op' },
    { label: '1', action: () => handleNumber('1'), type: 'num' },
    { label: '2', action: () => handleNumber('2'), type: 'num' },
    { label: '3', action: () => handleNumber('3'), type: 'num' },
    { label: '+', action: () => handleOperation('+'), type: 'op' },
    { label: '±', action: handleNegate, type: 'func' },
    { label: '0', action: () => handleNumber('0'), type: 'num' },
    { label: ',', action: handleDecimal, type: 'num' },
    { label: '=', action: handleEquals, type: 'equals' },
  ];

  return (
    <div className="calculator">
      <div className="calc-header">
        <span className="calc-title">Padrão</span>
      </div>

      <div className="calc-display">
        <div className="calc-history">{history}</div>
        <div className="calc-value">{formatDisplay(display)}</div>
      </div>

      <div className="calc-buttons">
        {buttons.map(btn => (
          <button
            key={btn.label}
            className={`calc-btn ${btn.type}`}
            onClick={btn.action}
          >
            {btn.label}
          </button>
        ))}
      </div>
    </div>
  );
}
