import os
import glob
import json
import re
import sys

SEARCH_DIRS = [
    '/usr/share/applications',
    '/usr/local/share/applications',
    '/root/.local/share/applications',
    '/var/lib/snapd/desktop/applications',
    '/var/lib/flatpak/exports/share/applications'
]

# Standard icon directories to search for icon assets
ICON_THEME_DIRS = [
    '/usr/share/icons/hicolor',
    '/usr/share/icons/Adwaita',
    '/usr/share/icons/Papirus',
    '/usr/share/icons/breeze',
    '/usr/share/icons/locolor',
    '/usr/share/pixmaps',
]

def clean_exec(raw):
    if not raw:
        return ''
    # Strip field codes: %f, %F, %u, %U, %d, %D, %n, %N, %i, %c, %k, %v, %m
    cleaned = re.sub(r'%[fFuUdDnNickvm]', '', raw).strip()
    return cleaned

def map_category(cats):
    cat_set = {c.lower() for c in cats}
    if cat_set & {'development', 'programming', 'ide', 'debugger', 'building'}:
        return 'development'
    if cat_set & {'network', 'webbrowser', 'email', 'chat', 'feed', 'filetransfer', 'remoteaccess'}:
        return 'internet'
    if cat_set & {'graphics', '2dgraphics', 'rastergraphics', 'vectorgraphics', 'photography', 'viewer', 'image'}:
        return 'graphics'
    if cat_set & {'audiovideo', 'audio', 'video', 'player', 'recorder', 'music', 'midi'}:
        return 'multimedia'
    if cat_set & {'office', 'wordprocessor', 'spreadsheet', 'presentation', 'publishing', 'finance', 'projectmanagement'}:
        return 'office'
    if cat_set & {'security', 'networksecurity', 'forensics', 'kali', 'penetrationtesting', 'vulnerability'}:
        return 'security'
    return 'utilities'

def get_emoji_fallback(category, name):
    name_lower = name.lower()
    if 'terminal' in name_lower or 'uxterm' in name_lower or 'xterm' in name_lower:
        return '🖥️'
    if 'calc' in name_lower:
        return '🧮'
    if 'edit' in name_lower or 'pad' in name_lower or 'vim' in name_lower:
        return '📝'
    if 'browser' in name_lower or 'web' in name_lower:
        return '🌐'
    if 'view' in name_lower or 'image' in name_lower or 'photo' in name_lower:
        return '🎨'
    if 'play' in name_lower or 'media' in name_lower or 'music' in name_lower or 'audio' in name_lower:
        return '🎬'
    if 'parted' in name_lower or 'disk' in name_lower:
        return '💾'
    if 'shark' in name_lower or 'sniff' in name_lower or 'scan' in name_lower:
        return '🦈'

    fallbacks = {
        'development': '💻',
        'internet': '🌐',
        'graphics': '🎨',
        'multimedia': '🎬',
        'office': '📄',
        'security': '🛡️',
        'utilities': '⚙️'
    }
    return fallbacks.get(category, '📦')

def scan_desktop_entries():
    apps = []
    seen_ids = set()

    for d in SEARCH_DIRS:
        if not os.path.exists(d):
            continue
        for path in glob.glob(os.path.join(d, '*.desktop')):
            try:
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
            except Exception:
                continue

            in_entry = False
            props = {}
            for line in content.splitlines():
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('['):
                    in_entry = (line == '[Desktop Entry]')
                    continue
                if in_entry and '=' in line:
                    k, v = line.split('=', 1)
                    k = k.strip()
                    v = v.strip()
                    if k not in props:
                        props[k] = v

            if props.get('Type', 'Application') != 'Application':
                continue
            if props.get('NoDisplay', '').lower() in ('true', '1') or props.get('Hidden', '').lower() in ('true', '1'):
                continue

            raw_exec = props.get('Exec', '')
            if not raw_exec:
                continue

            exec_cmd = clean_exec(raw_exec)
            name = props.get('Name[pt_BR]') or props.get('Name[pt]') or props.get('Name') or os.path.basename(path)[:-8]
            generic_name = props.get('GenericName[pt_BR]') or props.get('GenericName[pt]') or props.get('GenericName') or ''
            comment = props.get('Comment[pt_BR]') or props.get('Comment[pt]') or props.get('Comment') or generic_name or ''
            icon = props.get('Icon', '')
            terminal = props.get('Terminal', '').lower() in ('true', '1')
            cats_raw = props.get('Categories', '')
            cats = [c.strip() for c in cats_raw.split(';') if c.strip()]
            primary_cat = map_category(cats)
            emoji_icon = get_emoji_fallback(primary_cat, name)

            base_id = os.path.basename(path)[:-8].lower()
            if base_id in seen_ids:
                continue
            seen_ids.add(base_id)

            apps.append({
                'id': base_id,
                'name': name,
                'genericName': generic_name,
                'comment': comment,
                'command': exec_cmd,
                'rawExec': raw_exec,
                'icon': icon or emoji_icon,
                'iconName': icon,
                'emojiFallback': emoji_icon,
                'categories': cats,
                'category': primary_cat,
                'terminal': terminal,
                'desktopFile': path,
                'installed': True,
                'isDiscovered': True
            })

    # Sort alphabetically by name
    apps.sort(key=lambda a: a['name'].lower())
    return apps

if __name__ == '__main__':
    result = scan_desktop_entries()
    json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
