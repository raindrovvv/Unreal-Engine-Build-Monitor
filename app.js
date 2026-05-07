// Real-time Build Monitor Engine (file:// friendly script payload version)

const appTitle = document.getElementById('appTitle');
const appSubtitle = document.getElementById('appSubtitle');
const progressRing = document.getElementById('progressRing');
const percentText = document.getElementById('percentText');
const linearProgressBar = document.getElementById('linearProgressBar');
const activeFileName = document.getElementById('activeFileName');
const elapsedTime = document.getElementById('elapsedTime');
const completedActions = document.getElementById('completedActions');
const statusBadge = document.getElementById('statusBadge');
const statusText = document.getElementById('statusText');
const lastUpdate = document.getElementById('lastUpdate');

const config = window.buildMonitorConfig || {};
const statusFile = config.statusFile || 'build_status.js';
const refreshMs = Number(config.refreshMs || 1000);

const CIRCUMFERENCE = 2 * Math.PI * 95;

function applyConfig() {
    const title = config.title || 'Unreal Build Monitor';
    const subtitle = config.subtitle || 'Real-time Unreal Engine Compilation Status';

    document.title = title;
    appTitle.textContent = title;
    appSubtitle.textContent = subtitle;
}

function setProgress(percent) {
    const safePercent = Math.max(0, Math.min(100, Number(percent) || 0));
    const offset = CIRCUMFERENCE - (safePercent / 100) * CIRCUMFERENCE;
    progressRing.style.strokeDashoffset = offset;
    percentText.textContent = `${safePercent}%`;
    linearProgressBar.style.width = `${safePercent}%`;
}

function renderStatus(data) {
    setProgress(data.progress);

    activeFileName.textContent = data.current_file || 'Waiting for build step...';
    elapsedTime.textContent = data.elapsed_time || '00:00';
    completedActions.textContent = `${data.current_action || 0} / ${data.total_actions || 0}`;
    lastUpdate.textContent = data.last_update || 'N/A';

    const status = (data.status || 'WAITING').toUpperCase();
    statusText.textContent = status;

    statusBadge.className = 'status-badge';
    if (status === 'RUNNING') {
        statusBadge.classList.add('running');
    } else if (status === 'SUCCEEDED') {
        statusBadge.classList.add('succeeded');
    } else if (status === 'FAILED') {
        statusBadge.classList.add('failed');
    } else {
        statusBadge.classList.add('waiting');
    }
}

function renderStatusLoadError() {
    renderStatus({
        status: 'WAITING',
        progress: 0,
        current_file: `Waiting for ${statusFile}...`,
        current_action: 0,
        total_actions: 0,
        elapsed_time: '00:00',
        last_update: 'N/A'
    });
}

function fetchStatus() {
    const oldScript = document.getElementById('dynamicStatusScript');
    if (oldScript) oldScript.remove();

    window.buildStatus = null;

    const script = document.createElement('script');
    script.id = 'dynamicStatusScript';
    script.src = `${statusFile}?t=${Date.now()}`;
    script.onload = () => {
        if (window.buildStatus) {
            renderStatus(window.buildStatus);
        } else {
            renderStatusLoadError();
        }
    };
    script.onerror = renderStatusLoadError;

    document.body.appendChild(script);
}

applyConfig();
fetchStatus();
setInterval(fetchStatus, refreshMs);
