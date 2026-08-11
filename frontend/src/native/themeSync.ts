import { useSystem } from '../stores/systemStore';
function apply() { const theme = useSystem.getState().theme; document.documentElement.dataset.theme = theme.mode; document.documentElement.dataset.cloudosTransparency = String(theme.transparency !== false); }
apply(); useSystem.subscribe(apply);
