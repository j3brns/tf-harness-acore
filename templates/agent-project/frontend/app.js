const API_URL = '/api/chat';
const AUTH_URL = '/auth/login';

// Check for session cookie (simple check)
function checkAuth() {
    if (document.cookie.includes('session_id')) {
        document.getElementById('status').innerHTML = '<span class="text-green-500">CONNECTED</span>';
        document.getElementById('chat-form').classList.remove('hidden');
        document.getElementById('auth-panel').classList.add('hidden');
    } else {
        document.getElementById('status').innerHTML = '<span class="text-red-500 blink">UNAUTHORIZED</span>';
        document.getElementById('chat-form').classList.add('hidden');
        document.getElementById('auth-panel').classList.remove('hidden');
    }
}

function login() {
    window.location.href = AUTH_URL;
}

async function sendMessage(e) {
    e.preventDefault();
    const input = document.getElementById('prompt');
    const text = input.value;
    if (!text) return;

    appendLog(`> ${text}`, 'text-green-300');
    input.value = '';

    try {
        const res = await fetch(API_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt: text })
        });

        if (res.status === 401 || res.status === 403) {
            appendLog('ERROR: SESSION_EXPIRED', 'text-red-500');
            checkAuth();
            return;
        }

        const data = await res.json();
        appendLog(data.response, 'text-white');

    } catch (err) {
        appendLog(`SYSTEM FAILURE: ${err.message}`, 'text-red-500');
    }
}

function appendLog(text, className) {
    const div = document.createElement('div');
    div.className = className;
    div.innerText = text;
    document.getElementById('chat-window').appendChild(div);
    document.getElementById('chat-window').scrollTop = document.getElementById('chat-window').scrollHeight;
}

// Init
checkAuth();
