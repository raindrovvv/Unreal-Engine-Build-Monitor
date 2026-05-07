// Real-time Build Monitor Engine (file:// friendly script payload version)

const appTitle = document.getElementById('appTitle');
const appSubtitle = document.getElementById('appSubtitle');
const projectSelect = document.getElementById('projectSelect');
const progressRing = document.getElementById('progressRing');
const percentText = document.getElementById('percentText');
const linearProgressBar = document.getElementById('linearProgressBar');
const activeFileName = document.getElementById('activeFileName');
const buildStage = document.getElementById('buildStage');
const elapsedTime = document.getElementById('elapsedTime');
const completedActions = document.getElementById('completedActions');
const statusBadge = document.getElementById('statusBadge');
const statusText = document.getElementById('statusText');
const lastUpdate = document.getElementById('lastUpdate');
const errorPanel = document.getElementById('errorPanel');
const firstError = document.getElementById('firstError');
const errorList = document.getElementById('errorList');
const historyList = document.getElementById('historyList');
const slowFilesList = document.getElementById('slowFilesList');

const config = window.buildMonitorConfig || {};
const projects = Array.isArray(config.projects) && config.projects.length
    ? config.projects
    : [{ id: 'default', name: 'Default Project' }];
const CIRCUMFERENCE = 2 * Math.PI * 95;

let activeProject = projects[0];
let statusFile = config.statusFile || activeProject.statusFile || 'build_status.js';
let refreshMs = Number(config.refreshMs || activeProject.refreshMs || 1000);
let lastTerminalNotification = null;
let pollTimer = null;

function clampPercent(percent) {
    return Math.max(0, Math.min(100, Number(percent) || 0));
}

function formatDuration(seconds) {
    const value = Number(seconds) || 0;
    if (value < 60) return `${value.toFixed(1)}s`;
    const minutes = Math.floor(value / 60);
    return `${minutes}m ${(value % 60).toFixed(0)}s`;
}

function applyProject(project) {
    activeProject = project || projects[0];
    statusFile = activeProject.statusFile || config.statusFile || 'build_status.js';
    refreshMs = Number(activeProject.refreshMs || config.refreshMs || 1000);

    const title = activeProject.title || config.title || 'Unreal Build Monitor';
    const subtitle = activeProject.subtitle || config.subtitle || 'Real-time Unreal Engine Compilation Status';

    document.title = title;
    appTitle.textContent = title;
    appSubtitle.textContent = subtitle;
    lastTerminalNotification = null;
}

function setupProjectSelect() {
    projectSelect.innerHTML = '';
    projects.forEach((project, index) => {
        const option = document.createElement('option');
        option.value = project.id || String(index);
        option.textContent = project.name || project.title || `Project ${index + 1}`;
        projectSelect.appendChild(option);
    });

    projectSelect.classList.toggle('hidden', projects.length < 2);
    projectSelect.addEventListener('change', () => {
        const selected = projects.find((project, index) => (project.id || String(index)) === projectSelect.value);
        applyProject(selected);
        fetchStatus();
    });
}

function setProgress(percent) {
    const safePercent = clampPercent(percent);
    const offset = CIRCUMFERENCE - (safePercent / 100) * CIRCUMFERENCE;
    progressRing.style.strokeDashoffset = offset;
    percentText.textContent = `${safePercent}%`;
    linearProgressBar.style.width = `${safePercent}%`;
}

function setStatusClass(status) {
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

function renderErrorPanel(data) {
    const errors = Array.isArray(data.errors) ? data.errors.filter(Boolean) : [];
    const mainError = data.first_error || errors[0] || '';
    const shouldShow = (data.status || '').toUpperCase() === 'FAILED' || errors.length > 0;

    errorPanel.classList.toggle('hidden', !shouldShow);
    firstError.textContent = mainError || 'No errors detected.';
    errorList.innerHTML = '';

    errors.slice(1, 5).forEach((error) => {
        const item = document.createElement('li');
        item.textContent = error;
        errorList.appendChild(item);
    });
}

function renderHistory(history) {
    historyList.innerHTML = '';
    const rows = Array.isArray(history) ? history.slice(0, 10) : [];

    if (!rows.length) {
        historyList.classList.add('empty-list');
        historyList.innerHTML = '<li>No history yet.</li>';
        return;
    }

    historyList.classList.remove('empty-list');
    rows.forEach((build) => {
        const item = document.createElement('li');
        const status = (build.status || 'UNKNOWN').toUpperCase();
        item.innerHTML = `<span class="list-main">${status}</span><span>${build.elapsed_time || '00:00'} / ${build.total_actions || 0} actions</span>`;
        item.classList.add(status.toLowerCase());
        historyList.appendChild(item);
    });
}

function renderSlowFiles(files) {
    slowFilesList.innerHTML = '';
    const rows = Array.isArray(files) ? files.slice(0, 5) : [];

    if (!rows.length) {
        slowFilesList.classList.add('empty-list');
        slowFilesList.innerHTML = '<li>No timing data yet.</li>';
        return;
    }

    slowFilesList.classList.remove('empty-list');
    rows.forEach((file) => {
        const item = document.createElement('li');
        item.innerHTML = `<span class="list-main">${file.file || 'Unknown'}</span><span>${formatDuration(file.seconds)}</span>`;
        slowFilesList.appendChild(item);
    });
}

function maybeNotify(data) {
    const status = (data.status || '').toUpperCase();
    if (!['SUCCEEDED', 'FAILED'].includes(status)) {
        if (status === 'RUNNING') {
            lastTerminalNotification = null;
        }
        return;
    }

    const notificationKey = `${activeProject.id || activeProject.name || 'default'}:${status}`;
    if (notificationKey === lastTerminalNotification) return;
    lastTerminalNotification = notificationKey;

    if (!config.notifications || !config.notifications.browser || !('Notification' in window)) return;

    const title = `${appTitle.textContent}: ${status}`;
    const body = data.first_error || data.current_file || `Build ${status.toLowerCase()}.`;

    if (Notification.permission === 'granted') {
        new Notification(title, { body });
    } else if (Notification.permission === 'default') {
        Notification.requestPermission().then((permission) => {
            if (permission === 'granted') {
                new Notification(title, { body });
            }
        });
    }
}

function renderStatus(data) {
    setProgress(data.progress);

    activeFileName.textContent = data.current_file || 'Waiting for build step...';
    buildStage.textContent = data.stage || data.status || 'Waiting';
    elapsedTime.textContent = data.elapsed_time || '00:00';
    completedActions.textContent = `${data.current_action || 0} / ${data.total_actions || 0}`;
    lastUpdate.textContent = data.last_update || 'N/A';

    const status = (data.status || 'WAITING').toUpperCase();
    statusText.textContent = status;
    setStatusClass(status);
    renderErrorPanel(data);
    renderHistory(data.history);
    renderSlowFiles(data.slow_files);
    maybeNotify(data);
}

function renderStatusLoadError() {
    renderStatus({
        status: 'WAITING',
        stage: 'Waiting',
        progress: 0,
        current_file: `Waiting for ${statusFile}...`,
        current_action: 0,
        total_actions: 0,
        elapsed_time: '00:00',
        last_update: 'N/A',
        history: [],
        slow_files: []
    });
}

function fetchStatus() {
    if (pollTimer) {
        window.clearTimeout(pollTimer);
        pollTimer = null;
    }

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
        scheduleNextFetch();
    };
    script.onerror = () => {
        renderStatusLoadError();
        scheduleNextFetch();
    };

    document.body.appendChild(script);
}

function scheduleNextFetch() {
    pollTimer = window.setTimeout(fetchStatus, refreshMs);
}

setupProjectSelect();
applyProject(activeProject);
fetchStatus();
