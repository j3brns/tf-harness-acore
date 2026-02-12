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

        if (!res.ok) {
            const errText = await res.text();
            appendLog(`ERROR: ${errText}`, 'text-red-500');
            return;
        }

        if (!res.body || !res.body.getReader) {
            const data = await res.json();
            appendLog(data.response || JSON.stringify(data), 'text-white');
            return;
        }

        const responseDiv = appendLog('', 'text-white');
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        let responseText = '';

        const processLine = (line) => {
            const trimmed = line.trim();
            if (!trimmed) return;
            try {
                const obj = JSON.parse(trimmed);
                if (obj.type === 'delta' && obj.delta !== undefined) {
                    responseText += obj.delta;
                    responseDiv.innerText = responseText;
                    return;
                }
                if (obj.error) {
                    appendLog(`ERROR: ${obj.error}`, 'text-red-500');
                    return;
                }
            } catch (err) {
                responseText += line;
                responseDiv.innerText = responseText;
            }
        };

        while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop();
            lines.forEach(processLine);
        }

        if (buffer.trim()) {
            processLine(buffer);
        }

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
    return div;
}

// Init
checkAuth();
