// Premium Real-time Build Monitor Engine (CORS Bypass Version)

const progressRing = document.getElementById('progressRing');
const percentText = document.getElementById('percentText');
const linearProgressBar = document.getElementById('linearProgressBar');
const activeFileName = document.getElementById('activeFileName');
const elapsedTime = document.getElementById('elapsedTime');
const completedActions = document.getElementById('completedActions');
const statusBadge = document.getElementById('statusBadge');
const statusText = document.getElementById('statusText');
const lastUpdate = document.getElementById('lastUpdate');

// Total circumference of circle: 2 * PI * r (r = 95)
const CIRCUMFERENCE = 2 * Math.PI * 95;

function setProgress(percent) {
    const offset = CIRCUMFERENCE - (percent / 100) * CIRCUMFERENCE;
    progressRing.style.strokeDashoffset = offset;
    percentText.textContent = `${percent}%`;
    linearProgressBar.style.width = `${percent}%`;
}

function fetchStatus() {
    // CORS Bypass: Load status as script tag to avoid local file:// security block
    const oldScript = document.getElementById('dynamicStatusScript');
    if (oldScript) oldScript.remove();
    
    const script = document.createElement('script');
    script.id = 'dynamicStatusScript';
    // Append timestamp to prevent cache
    script.src = 'build_status.js?t=' + new Date().getTime();
    
    script.onload = () => {
        if (window.buildStatus) {
            const data = window.buildStatus;
            
            // Progress Update
            setProgress(data.progress);
            
            // Stats Update
            activeFileName.textContent = data.current_file || "Waiting for build step...";
            elapsedTime.textContent = data.elapsed_time || "00:00";
            completedActions.textContent = `${data.current_action || 0} / ${data.total_actions || 0}`;
            lastUpdate.textContent = data.last_update || "N/A";
            
            // Update Status Badge
            const status = (data.status || 'RUNNING').toUpperCase();
            statusText.textContent = status;
            
            statusBadge.className = 'status-badge'; // reset
            if (status === 'RUNNING') {
                statusBadge.classList.add('running');
            } else if (status === 'SUCCEEDED') {
                statusBadge.classList.add('succeeded');
            } else if (status === 'FAILED') {
                statusBadge.classList.add('failed');
            }
        }
    };
    
    document.body.appendChild(script);
}

// Initial fetch & loop every 1 second
fetchStatus();
setInterval(fetchStatus, 1000);
