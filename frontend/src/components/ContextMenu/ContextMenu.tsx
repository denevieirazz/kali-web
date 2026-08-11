import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { CSSProperties, KeyboardEvent } from 'react';
import type { ContextMenuItem } from '../../types';
import './ContextMenu.css';

interface Props { x:number; y:number; items:ContextMenuItem[]; onClose:()=>void }
const GAP=8;

function Submenu({anchor,items,onClose}:{anchor:HTMLElement;items:ContextMenuItem[];onClose:()=>void}){
  const ref=useRef<HTMLDivElement>(null);const [style,setStyle]=useState<CSSProperties>({visibility:'hidden'});
  useLayoutEffect(()=>{const menu=ref.current;if(!menu)return;const a=anchor.getBoundingClientRect();const m=menu.getBoundingClientRect();let left=a.right-2;if(left+m.width>innerWidth-GAP)left=a.left-m.width+2;left=Math.max(GAP,Math.min(left,innerWidth-m.width-GAP));let top=a.top;top=Math.max(GAP,Math.min(top,innerHeight-m.height-GAP));setStyle({left,top,visibility:'visible'});},[anchor,items]);
  return createPortal(<div ref={ref} className="context-submenu acrylic context-submenu-portal" style={style} role="menu">{items.map((item,index)=><Entry key={item.id||index} item={item} onClose={onClose}/>)}</div>,document.body);
}

function Entry({item,onClose}:{item:ContextMenuItem;onClose:()=>void}){
  const ref=useRef<HTMLButtonElement>(null);const [open,setOpen]=useState(false);
  if(item.separator)return <div className="context-menu-separator" role="separator"/>;
  const run=()=>{if(item.children){setOpen(value=>!value);return}if(!item.disabled&&item.onClick){item.onClick();onClose()}};
  return <div className="context-menu-item-wrapper" onPointerEnter={()=>item.children&&setOpen(true)} onPointerLeave={()=>item.children&&setOpen(false)}><button ref={ref} type="button" role="menuitem" aria-haspopup={item.children?'menu':undefined} aria-expanded={item.children?open:undefined} disabled={item.disabled} className={`context-menu-item ${item.disabled?'disabled':''}`} onClick={run}><span className="context-menu-icon">{item.icon||''}</span><span className="context-menu-label">{item.label}</span>{item.shortcut&&<span className="context-menu-shortcut">{item.shortcut}</span>}{item.children&&<span className="context-menu-arrow">›</span>}</button>{open&&item.children&&ref.current&&<Submenu anchor={ref.current} items={item.children} onClose={onClose}/>}</div>;
}

export default function ContextMenu({x,y,items,onClose}:Props){
  const ref=useRef<HTMLDivElement>(null);const [style,setStyle]=useState<CSSProperties>({left:x,top:y,visibility:'hidden'});
  useLayoutEffect(()=>{const menu=ref.current;if(!menu)return;const r=menu.getBoundingClientRect();setStyle({left:Math.max(GAP,Math.min(x,innerWidth-r.width-GAP)),top:Math.max(GAP,Math.min(y,innerHeight-r.height-GAP)),visibility:'visible'});},[x,y,items]);
  useEffect(()=>{const outside=(e:PointerEvent)=>{const target=e.target as Node;if(!ref.current?.contains(target)&&!(target as Element).closest?.('.context-submenu-portal'))onClose()};const close=()=>onClose();document.addEventListener('pointerdown',outside);window.addEventListener('resize',close);window.addEventListener('blur',close);requestAnimationFrame(()=>ref.current?.querySelector<HTMLButtonElement>('.context-menu-item:not(:disabled)')?.focus());return()=>{document.removeEventListener('pointerdown',outside);window.removeEventListener('resize',close);window.removeEventListener('blur',close)}},[onClose]);
  const keys=(e:KeyboardEvent<HTMLDivElement>)=>{const buttons=[...ref.current!.querySelectorAll<HTMLButtonElement>(':scope > .context-menu-item-wrapper > button:not(:disabled)')];const at=buttons.indexOf(document.activeElement as HTMLButtonElement);if(e.key==='Escape'){e.preventDefault();onClose()}else if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();const step=e.key==='ArrowDown'?1:-1;buttons[(at+step+buttons.length)%buttons.length]?.focus()}else if(e.key==='Home'){e.preventDefault();buttons[0]?.focus()}else if(e.key==='End'){e.preventDefault();buttons.at(-1)?.focus()}};
  return createPortal(<div ref={ref} className="context-menu acrylic context-menu-portal" style={style} role="menu" onKeyDown={keys}>{items.map((item,index)=><Entry key={item.id||index} item={item} onClose={onClose}/>)}</div>,document.body);
}
