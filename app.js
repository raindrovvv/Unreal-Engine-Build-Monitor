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
const stallCard = document.getElementById('stallCard');
const stallStatus = document.getElementById('stallStatus');
const gitCard = document.getElementById('gitCard');
const gitInfo = document.getElementById('gitInfo');
const statusBadge = document.getElementById('statusBadge');
const statusText = document.getElementById('statusText');
const lastUpdate = document.getElementById('lastUpdate');
const errorPanel = document.getElementById('errorPanel');
const firstError = document.getElementById('firstError');
const errorList = document.getElementById('errorList');
const errorTypeBadge = document.getElementById('errorTypeBadge');
const errorContextDetails = document.getElementById('errorContextDetails');
const errorContextLog = document.getElementById('errorContextLog');
const historyList = document.getElementById('historyList');
const slowFilesList = document.getElementById('slowFilesList');
const discordWebhookUrl = document.getElementById('discordWebhookUrl');
const discordWebhookEnabled = document.getElementById('discordWebhookEnabled');
const slackWebhookUrl = document.getElementById('slackWebhookUrl');
const slackWebhookEnabled = document.getElementById('slackWebhookEnabled');
const saveWebhookSettings = document.getElementById('saveWebhookSettings');
const testDiscordWebhook = document.getElementById('testDiscordWebhook');
const testSlackWebhook = document.getElementById('testSlackWebhook');
const webhookSettingsStatus = document.getElementById('webhookSettingsStatus');
const historyModal = document.getElementById('historyModal');
const closeHistoryModal = document.getElementById('closeHistoryModal');
const historyModalTitle = document.getElementById('historyModalTitle');
const historyModalContent = document.getElementById('historyModalContent');

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
let webhookSettingsSaveTimer = null;
let latestHistory = [];

function clampPercent(percent) {
    return Math.max(0, Math.min(100, Number(percent) || 0));
}

function formatDuration(seconds) {
    const value = Number(seconds) || 0;
    if (value < 60) return `${value.toFixed(1)}s`;
    const minutes = Math.floor(value / 60);
    return `${minutes}m ${(value % 60).toFixed(0)}s`;
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
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

function getWebhookSettingsFromForm() {
    return {
        discord: {
            enabled: discordWebhookEnabled.checked,
            url: discordWebhookUrl.value.trim()
        },
        slack: {
            enabled: slackWebhookEnabled.checked,
            url: slackWebhookUrl.value.trim()
        }
    };
}

function applyWebhookSettings(settings) {
    const discord = settings.discord || {};
    const slack = settings.slack || {};
    discordWebhookEnabled.checked = Boolean(discord.enabled);
    discordWebhookUrl.value = discord.url || '';
    slackWebhookEnabled.checked = Boolean(slack.enabled);
    slackWebhookUrl.value = slack.url || '';
    validateWebhookForm();
}

function setWebhookStatus(message, tone = 'muted') {
    webhookSettingsStatus.textContent = message;
    webhookSettingsStatus.className = tone;
}

function validateWebhookUrl(provider, url) {
    if (!url) return true;
    if (provider === 'discord') {
        return /^https:\/\/(?:discord\.com|discordapp\.com)\/api\/webhooks\/\d+\/[\w-]+$/i.test(url);
    }
    if (provider === 'slack') {
        return /^https:\/\/hooks\.slack\.com\/services\/[A-Z0-9]+\/[A-Z0-9]+\/[A-Za-z0-9]+$/i.test(url);
    }
    return false;
}

function validateWebhookForm() {
    const discordValid = validateWebhookUrl('discord', discordWebhookUrl.value.trim());
    const slackValid = validateWebhookUrl('slack', slackWebhookUrl.value.trim());

    discordWebhookUrl.classList.toggle('invalid', !discordValid);
    slackWebhookUrl.classList.toggle('invalid', !slackValid);
    testDiscordWebhook.disabled = !discordWebhookEnabled.checked || !discordWebhookUrl.value.trim() || !discordValid;
    testSlackWebhook.disabled = !slackWebhookEnabled.checked || !slackWebhookUrl.value.trim() || !slackValid;
    saveWebhookSettings.disabled = !discordValid || !slackValid;

    if (!discordValid) {
        setWebhookStatus('Discord webhook URL looks invalid.', 'error');
    } else if (!slackValid) {
        setWebhookStatus('Slack webhook URL looks invalid.', 'error');
    }

    return discordValid && slackValid;
}

async function loadWebhookSettings() {
    try {
        const response = await fetch('api/webhooks', { cache: 'no-store' });
        if (!response.ok) throw new Error('API unavailable');
        const settings = await response.json();
        applyWebhookSettings(settings);
        setWebhookStatus('Settings loaded from webhook_settings.json.', 'success');
    } catch {
        const local = window.localStorage.getItem('buildMonitorWebhookSettings');
        if (local) {
            applyWebhookSettings(JSON.parse(local));
            setWebhookStatus('Loaded browser-only settings. Start with serve.ps1 to save for monitor.ps1.', 'warning');
        } else {
            setWebhookStatus('Use serve.ps1 to save webhook settings for monitor.ps1.', 'warning');
        }
    }
}

async function saveWebhookSettingsToServer() {
    if (!validateWebhookForm()) return;

    const settings = getWebhookSettingsFromForm();
    window.localStorage.setItem('buildMonitorWebhookSettings', JSON.stringify(settings));

    try {
        const response = await fetch('api/webhooks', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(settings)
        });
        if (!response.ok) throw new Error(await response.text());
        setWebhookStatus('Saved to webhook_settings.json. monitor.ps1 will use it on the next terminal build result.', 'success');
    } catch {
        setWebhookStatus('Saved only in this browser. Start with serve.ps1 to write webhook_settings.json.', 'warning');
    }
}

async function testWebhook(provider) {
    if (!validateWebhookForm()) return;

    const settings = getWebhookSettingsFromForm();
    const target = settings[provider];
    if (!target || !target.enabled || !target.url) {
        setWebhookStatus(`${provider} webhook is not enabled or URL is empty.`, 'error');
        return;
    }

    setWebhookStatus(`Sending ${provider} test...`, 'muted');

    try {
        const response = await fetch(`api/test-webhook?provider=${encodeURIComponent(provider)}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(settings)
        });
        if (!response.ok) throw new Error(await response.text());
        setWebhookStatus(`${provider} test sent successfully.`, 'success');
    } catch {
        setWebhookStatus(`${provider} test failed. Start with serve.ps1 and check the webhook URL.`, 'error');
    }
}

function setupWebhookSettings() {
    saveWebhookSettings.addEventListener('click', saveWebhookSettingsToServer);
    testDiscordWebhook.addEventListener('click', () => testWebhook('discord'));
    testSlackWebhook.addEventListener('click', () => testWebhook('slack'));

    [discordWebhookUrl, discordWebhookEnabled, slackWebhookUrl, slackWebhookEnabled].forEach((element) => {
        element.addEventListener('input', () => {
            validateWebhookForm();
            window.clearTimeout(webhookSettingsSaveTimer);
            webhookSettingsSaveTimer = window.setTimeout(() => {
                window.localStorage.setItem('buildMonitorWebhookSettings', JSON.stringify(getWebhookSettingsFromForm()));
            }, 250);
        });
        element.addEventListener('change', validateWebhookForm);
    });

    validateWebhookForm();
    loadWebhookSettings();
}

function setupHistoryModal() {
    historyList.addEventListener('click', (event) => {
        const button = event.target.closest('.history-row');
        if (!button) return;
        openHistoryModal(latestHistory[Number(button.dataset.historyIndex)]);
    });

    closeHistoryModal.addEventListener('click', closeModal);
    historyModal.addEventListener('click', (event) => {
        if (event.target === historyModal) {
            closeModal();
        }
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            closeModal();
        }
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
    const context = Array.isArray(data.error_context) ? data.error_context : [];
    const shouldShow = (data.status || '').toUpperCase() === 'FAILED' || errors.length > 0;

    errorPanel.classList.toggle('hidden', !shouldShow);
    errorTypeBadge.textContent = data.error_type || 'Unknown';
    errorTypeBadge.className = `error-type-badge ${String(data.error_type || 'unknown').toLowerCase()}`;
    firstError.textContent = mainError || 'No errors detected.';
    errorList.innerHTML = '';

    errors.slice(1, 5).forEach((error) => {
        const item = document.createElement('li');
        item.textContent = error;
        errorList.appendChild(item);
    });

    errorContextDetails.classList.toggle('hidden', !context.length);
    errorContextLog.innerHTML = context.map((entry) => {
        const line = String(entry.line || '').padStart(4, ' ');
        const marker = entry.is_error ? '>' : ' ';
        return `<span class="${entry.is_error ? 'context-error' : ''}">${marker} ${line} | ${escapeHtml(entry.text || '')}</span>`;
    }).join('\n');
}

function renderHistory(history) {
    historyList.innerHTML = '';
    const rows = Array.isArray(history) ? history.slice(0, 10) : [];
    latestHistory = rows;

    if (!rows.length) {
        historyList.classList.add('empty-list');
        historyList.innerHTML = '<li>No history yet.</li>';
        return;
    }

    historyList.classList.remove('empty-list');
    rows.forEach((build, index) => {
        const item = document.createElement('li');
        const status = (build.status || 'UNKNOWN').toUpperCase();
        item.innerHTML = `<button type="button" class="history-row" data-history-index="${index}"><span class="list-main">${status}</span><span>${build.elapsed_time || '00:00'} / ${build.total_actions || 0} actions</span></button>`;
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

function renderStall(stall) {
    const info = stall || {};
    const stalled = Boolean(info.stalled);
    const seconds = Number(info.seconds || 0);

    stallCard.classList.toggle('hidden', !stalled && seconds <= 0);
    stallCard.classList.toggle('stalled', stalled);
    stallStatus.textContent = stalled
        ? `No progress for ${formatDuration(seconds)}`
        : `${formatDuration(seconds)} since action change`;
}

function renderGitInfo(info) {
    const git = info || {};
    gitCard.classList.toggle('hidden', !git.available);
    if (!git.available) return;

    const dirty = git.dirty ? ' dirty' : '';
    gitInfo.textContent = `${git.branch || 'detached'} @ ${git.commit || 'unknown'}${dirty}`;
}

function openHistoryModal(build) {
    if (!build) return;

    const status = (build.status || 'UNKNOWN').toUpperCase();
    const context = Array.isArray(build.error_context) ? build.error_context : [];
    const slowFiles = Array.isArray(build.slow_files) ? build.slow_files : [];
    const git = build.git_info || {};

    historyModalTitle.textContent = `${status} build`;
    historyModalContent.innerHTML = `
        <div class="modal-metrics">
            <div><span>Status</span><strong>${escapeHtml(status)}</strong></div>
            <div><span>Elapsed</span><strong>${escapeHtml(build.elapsed_time || '00:00')}</strong></div>
            <div><span>Actions</span><strong>${escapeHtml(build.total_actions || 0)}</strong></div>
            <div><span>Error Type</span><strong>${escapeHtml(build.error_type || 'None')}</strong></div>
        </div>
        <section>
            <h3>First Error</h3>
            <p>${escapeHtml(build.first_error || 'No error recorded.')}</p>
        </section>
        <section>
            <h3>Git</h3>
            <p>${git.available ? `${escapeHtml(git.branch || 'detached')} @ ${escapeHtml(git.commit || 'unknown')}${git.dirty ? ' dirty' : ''}` : 'No git metadata recorded.'}</p>
        </section>
        <section>
            <h3>Slow Files</h3>
            <ul>${slowFiles.length ? slowFiles.map((file) => `<li>${escapeHtml(file.file || 'Unknown')} — ${formatDuration(file.seconds)}</li>`).join('') : '<li>No slow file data recorded.</li>'}</ul>
        </section>
        <section>
            <h3>Error Context</h3>
            <pre>${context.length ? context.map((entry) => `${entry.is_error ? '>' : ' '} ${String(entry.line || '').padStart(4, ' ')} | ${escapeHtml(entry.text || '')}`).join('\n') : 'No nearby log context recorded.'}</pre>
        </section>
    `;
    historyModal.classList.remove('hidden');
}

function closeModal() {
    historyModal.classList.add('hidden');
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
    renderStall(data.stall);
    renderGitInfo(data.git_info);
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
        stall: { stalled: false, seconds: 0 },
        git_info: { available: false },
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
setupWebhookSettings();
setupHistoryModal();
applyProject(activeProject);
fetchStatus();
