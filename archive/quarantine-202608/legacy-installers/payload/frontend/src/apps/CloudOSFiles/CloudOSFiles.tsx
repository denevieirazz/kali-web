import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import './CloudOSFiles.css';

type Entry = { name:string; kind:'file'|'directory'; size:number; modified:number };
type Sort = 'name'|'size'|'modified';
const ROOT = 'cloudos_files';

async function rootHandle() { return (await navigator.storage.getDirectory()).getDirectoryHandle(ROOT, { create:true }); }
async function handleAt(parts:string[]) { let dir = await rootHandle(); for (const part of parts) dir = await dir.getDirectoryHandle(part); return dir; }
const safeName = (name:string) => name.trim().replace(/[\\/:*?"<>|]/g,'-').slice(0,120);
const formatSize = (bytes:number) => bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${(bytes/1024).toFixed(1)} KB` : `${(bytes/1048576).toFixed(1)} MB`;

export default function CloudOSFiles({}: { windowId?:string }) {
  const [path,setPath] = useState<string[]>([]);
  const [entries,setEntries] = useState<Entry[]>([]);
  const [selected,setSelected] = useState<string|null>(null);
  const [query,setQuery] = useState('');
  const [sort,setSort] = useState<Sort>('name');
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState('');
  const [editor,setEditor] = useState<{name:string;content:string}|null>(null);
  const uploadRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setBusy(true); setError('');
    try {
      const dir = await handleAt(path); const list:Entry[] = [];
      for await (const [name,handle] of (dir as any).entries()) {
        if (handle.kind === 'file') { const file = await handle.getFile(); list.push({name,kind:'file',size:file.size,modified:file.lastModified}); }
        else list.push({name,kind:'directory',size:0,modified:0});
      }
      setEntries(list); setSelected(null);
    } catch { setError('Não foi possível abrir esta pasta.'); }
    finally { setBusy(false); }
  },[path]);
  useEffect(() => { void load(); },[load]);

  const visible = useMemo(() => entries.filter(e => e.name.toLowerCase().includes(query.toLowerCase())).sort((a,b) => {
    if (a.kind !== b.kind) return a.kind === 'directory' ? -1 : 1;
    if (sort === 'size') return a.size-b.size;
    if (sort === 'modified') return b.modified-a.modified;
    return a.name.localeCompare(b.name,'pt-BR',{numeric:true});
  }),[entries,query,sort]);

  async function create(kind:'file'|'directory') {
    const raw = prompt(kind==='file'?'Nome do arquivo':'Nome da pasta'); const name=safeName(raw||''); if(!name)return;
    try { const dir=await handleAt(path); if(kind==='file'){const h=await dir.getFileHandle(name,{create:true});const w=await h.createWritable();await w.close();}else await dir.getDirectoryHandle(name,{create:true}); await load(); } catch { setError('Não foi possível criar o item.'); }
  }
  async function open(entry:Entry) {
    if(entry.kind==='directory'){setPath(p=>[...p,entry.name]);return;}
    try { const dir=await handleAt(path); const file=await (await dir.getFileHandle(entry.name)).getFile(); if(file.type.startsWith('text/')||/\.(txt|md|json|js|ts|tsx|css|html|log)$/i.test(entry.name)) setEditor({name:entry.name,content:await file.text()}); else download(entry.name); } catch { setError('Não foi possível abrir o arquivo.'); }
  }
  async function saveEditor() { if(!editor)return; try{const dir=await handleAt(path);const h=await dir.getFileHandle(editor.name);const w=await h.createWritable();await w.write(editor.content);await w.close();setEditor(null);await load();}catch{setError('Não foi possível salvar.');} }
  async function download(name:string) { try{const dir=await handleAt(path);const file=await(await dir.getFileHandle(name)).getFile();const url=URL.createObjectURL(file);const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}catch{setError('Não foi possível baixar.');} }
  async function remove(entry:Entry) { if(!confirm(`Excluir “${entry.name}”?`))return; try{const dir=await handleAt(path);await dir.removeEntry(entry.name,{recursive:entry.kind==='directory'});await load();}catch{setError('Não foi possível excluir.');} }
  async function rename(entry:Entry) { const next=safeName(prompt('Novo nome',entry.name)||'');if(!next||next===entry.name)return; try{const dir=await handleAt(path);if(entry.kind==='file'){const old=await(await dir.getFileHandle(entry.name)).getFile();const nh=await dir.getFileHandle(next,{create:true});const w=await nh.createWritable();await w.write(old);await w.close();await dir.removeEntry(entry.name);}else{setError('Renomear pastas será incluído após suporte transacional.');return;}await load();}catch{setError('Não foi possível renomear.');} }
  async function upload(files:FileList|null) { if(!files?.length)return; setBusy(true);try{const dir=await handleAt(path);for(const file of Array.from(files)){const name=safeName(file.name);const h=await dir.getFileHandle(name,{create:true});const w=await h.createWritable();await w.write(file);await w.close();}await load();}catch{setError('Falha no envio de arquivo.');}finally{setBusy(false);} }

  return <div className="cf-root">
    <header className="cf-toolbar"><button onClick={()=>setPath(p=>p.slice(0,-1))} disabled={!path.length}>←</button><button onClick={()=>void load()}>↻</button><button onClick={()=>void create('file')}>＋ Arquivo</button><button onClick={()=>void create('directory')}>＋ Pasta</button><button onClick={()=>uploadRef.current?.click()}>↑ Enviar</button><input ref={uploadRef} hidden multiple type="file" onChange={e=>void upload(e.target.files)}/><div className="cf-address"><button onClick={()=>setPath([])}>local:</button>{path.map((part,i)=><button key={`${part}-${i}`} onClick={()=>setPath(path.slice(0,i+1))}>/ {part}</button>)}</div><input className="cf-search" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Pesquisar"/><select value={sort} onChange={e=>setSort(e.target.value as Sort)}><option value="name">Nome</option><option value="modified">Data</option><option value="size">Tamanho</option></select></header>
    {error&&<div className="cf-error">{error}<button onClick={()=>setError('')}>×</button></div>}
    <main className="cf-content">{busy?<div className="cf-empty">Carregando…</div>:visible.length?<div className="cf-grid">{visible.map(entry=><article key={entry.name} className={`cf-item ${selected===entry.name?'selected':''}`} onClick={()=>setSelected(entry.name)} onDoubleClick={()=>void open(entry)}><div className="cf-icon">{entry.kind==='directory'?'📁':'📄'}</div><strong title={entry.name}>{entry.name}</strong><small>{entry.kind==='directory'?'Pasta':formatSize(entry.size)}</small><div className="cf-actions"><button onClick={e=>{e.stopPropagation();void open(entry)}}>{entry.kind==='directory'?'Abrir':'Editar'}</button>{entry.kind==='file'&&<button onClick={e=>{e.stopPropagation();void download(entry.name)}}>Baixar</button>}<button onClick={e=>{e.stopPropagation();void rename(entry)}}>Renomear</button><button className="danger" onClick={e=>{e.stopPropagation();void remove(entry)}}>Excluir</button></div></article>)}</div>:<div className="cf-empty"><span>☁️</span><strong>Pasta vazia</strong><small>Crie uma pasta ou envie arquivos.</small></div>}</main>
    <footer className="cf-status"><span>{visible.length} item(ns)</span><span>OPFS local persistente</span></footer>
    {editor&&<div className="cf-modal"><section><header><strong>{editor.name}</strong><button onClick={()=>setEditor(null)}>×</button></header><textarea value={editor.content} onChange={e=>setEditor({...editor,content:e.target.value})}/><footer><button onClick={()=>setEditor(null)}>Cancelar</button><button className="primary" onClick={()=>void saveEditor()}>Salvar</button></footer></section></div>}
  </div>;
}
