const RESOURCE = (window.GetParentResourceName && window.GetParentResourceName()) || 'mz_bank';
const IS_BROWSER = typeof window.GetParentResourceName === 'undefined';
const REQUEST_TIMEOUT_MS = 10000;

const app = document.getElementById('app');
const views = document.querySelectorAll('.view');

function loadPendingOperations() {
    try {
        const stored = JSON.parse(window.sessionStorage.getItem('mz_bank_pending_operations') || '{}');
        return stored && typeof stored === 'object' ? stored : {};
    } catch (_) {
        return {};
    }
}

function savePendingOperations(pendingOperations) {
    try {
        window.sessionStorage.setItem('mz_bank_pending_operations', JSON.stringify(pendingOperations || {}));
    } catch (_) { /* persistence is best effort; server-side idempotency remains authoritative */ }
}

const state = {
    view: 'welcome',
    data: { balance: 0, cash: 0, name: '-', account: '-', statement: [] },
    amounts: { withdraw: '', deposit: '', transfer: '' },
    focus: 'amount',
    busy: false,
    currencySymbol: 'R$',
    channel: 'atm',
    cardInserted: false,
    pendingOperations: loadPendingOperations(),
};

let audioCtx = null;
function beep(freq = 660, duration = 60, type = 'square', vol = 0.05) {
    try {
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = type;
        osc.frequency.value = freq;
        gain.gain.value = vol;
        osc.connect(gain).connect(audioCtx.destination);
        osc.start();
        osc.stop(audioCtx.currentTime + duration / 1000);
    } catch (_) { /* audio is optional */ }
}

const SOFT = {
    welcome: {},
    menu: {
        0: { label: 'Ver saldo', act: () => show('balance') },
        1: { label: 'Saque', act: () => show('withdraw') },
        2: { label: 'Deposito', act: () => show('deposit') },
        4: { label: 'Transferencia', act: () => show('transfer') },
        5: { label: 'Extrato', act: () => show('statement') },
        7: { label: 'Sair', danger: true, act: () => exitBank() },
    },
    balance: { 7: { label: 'Voltar', act: () => show('menu') } },
    withdraw: {
        0: { label: '$50', act: () => quick('withdraw', 50) },
        1: { label: '$100', act: () => quick('withdraw', 100) },
        2: { label: '$500', act: () => quick('withdraw', 500) },
        3: { label: '$1000', act: () => quick('withdraw', 1000) },
        4: { label: 'Confirmar', act: () => confirmAction('withdraw') },
        7: { label: 'Voltar', danger: true, act: () => show('menu') },
    },
    deposit: {
        0: { label: '$50', act: () => quick('deposit', 50) },
        1: { label: '$100', act: () => quick('deposit', 100) },
        2: { label: '$500', act: () => quick('deposit', 500) },
        3: { label: '$1000', act: () => quick('deposit', 1000) },
        4: { label: 'Confirmar', act: () => confirmAction('deposit') },
        7: { label: 'Voltar', danger: true, act: () => show('menu') },
    },
    transfer: {
        0: { label: 'Editar ID', act: () => setFocus('target') },
        1: { label: 'Editar valor', act: () => setFocus('amount') },
        4: { label: 'Enviar', act: () => confirmAction('transfer') },
        7: { label: 'Voltar', danger: true, act: () => show('menu') },
    },
    statement: { 7: { label: 'Voltar', act: () => show('menu') } },
};

function renderSoftKeys(view) {
    const config = SOFT[view] || {};
    document.querySelectorAll('.sslot').forEach((slot) => {
        const index = Number(slot.dataset.soft);
        const button = slot.querySelector('.soft-key');
        const edgeSlot = document.querySelector(`.eslot[data-soft="${index}"]`);
        const label = edgeSlot && edgeSlot.querySelector('.elabel');
        const item = config[index];
        button.disabled = state.busy || !item;
        button.classList.toggle('active', !!item && !state.busy);
        if (label) label.textContent = item ? item.label.replace('$', state.currencySymbol) : '';
        if (edgeSlot) edgeSlot.classList.toggle('danger', !!(item && item.danger));
    });
}

function runSoft(index) {
    if (state.busy) return;
    const item = (SOFT[state.view] || {})[index];
    if (!item) return;
    beep(560, 35);
    item.act();
}

function setCardState(status) {
    const slot = document.getElementById('card-slot');
    const label = document.getElementById('card-slot-label');
    if (!slot || !label) return;

    slot.classList.remove('waiting', 'inserted', 'ejecting', 'error');
    slot.classList.add(status);

    const labels = {
        waiting: 'INSIRA O CARTAO',
        inserted: 'CARTAO INSERIDO',
        ejecting: 'RETIRE O CARTAO',
        error: 'CARTAO RECUSADO',
    };
    label.textContent = labels[status] || labels.waiting;
    slot.disabled = state.busy || status !== 'waiting' || state.channel !== 'atm';
}

async function nui(callback, body = {}) {
    if (IS_BROWSER) return mockNui(callback, body);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
        const response = await fetch(`https://${RESOURCE}/${callback}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body),
            signal: controller.signal,
        });
        return await response.json();
    } catch (_) {
        return { ok: false, error: 'bank_unavailable', message: 'O servico bancario nao respondeu.' };
    } finally {
        clearTimeout(timeout);
    }
}

function show(viewName) {
    state.view = viewName;
    views.forEach((view) => view.classList.toggle('hidden', view.dataset.view !== viewName));
    renderSoftKeys(viewName);
    if (viewName === 'balance') renderBalance();
    if (viewName === 'statement') renderStatement();
    if (viewName === 'transfer') setFocus('target');
    beep(520, 40);
}

function formatMoney(value, showPositive = false) {
    const amount = Number(value || 0);
    const sign = amount < 0 ? '-' : (showPositive && amount > 0 ? '+' : '');
    return `${sign}${state.currencySymbol}${Math.abs(amount).toLocaleString('pt-BR')}`;
}

function renderMenu() {
    document.getElementById('menu-name').textContent = state.data.name || '-';
    document.getElementById('menu-balance').textContent = formatMoney(state.data.balance);
}

function renderBalance() {
    document.getElementById('balance-value').textContent = Number(state.data.balance || 0).toLocaleString('pt-BR');
    document.getElementById('balance-cash').textContent = formatMoney(state.data.cash);
    document.getElementById('balance-account').textContent = state.data.account || '-';
}

function renderAmount(target) {
    const element = document.getElementById(`${target}-amount`);
    if (element) element.textContent = Number(state.amounts[target] || 0).toLocaleString('pt-BR');
}

function renderStatement() {
    const list = document.getElementById('statement-list');
    list.innerHTML = '';
    const items = state.data.statement || [];
    if (!items.length) {
        list.innerHTML = `<p class="statement-empty">${state.data.statementError ? 'Extrato temporariamente indisponivel.' : 'Nenhuma movimentacao ainda.'}</p>`;
        return;
    }
    const labels = {
        atm_withdraw: 'Saque', branch_withdraw: 'Saque',
        atm_deposit: 'Deposito', branch_deposit: 'Deposito',
        atm_transfer: 'Transferencia enviada', branch_transfer: 'Transferencia enviada',
        atm_transfer_received: 'Transferencia recebida', branch_transfer_received: 'Transferencia recebida',
    };
    items.forEach((transaction) => {
        const item = document.createElement('li');
        const positive = Number(transaction.amount) >= 0;
        const date = transaction.created_at ? new Date(transaction.created_at).toLocaleString('pt-BR') : '';
        const description = labels[transaction.type] || transaction.description || transaction.type || 'Movimentacao';
        const descriptionContainer = document.createElement('span');
        descriptionContainer.className = 'st-desc';
        const descriptionText = document.createElement('span');
        descriptionText.textContent = description;
        const dateText = document.createElement('small');
        dateText.textContent = date;
        descriptionContainer.append(descriptionText, dateText);
        const amountText = document.createElement('span');
        amountText.className = `st-amount ${positive ? 'pos' : 'neg'}`;
        amountText.textContent = formatMoney(transaction.amount, true);
        item.append(descriptionContainer, amountText);
        list.appendChild(item);
    });
}

function applyData(data) {
    state.data = { ...state.data, ...(data || {}) };
    if (data && data.currencySymbol) setCurrency(data.currencySymbol);
    renderMenu();
    if (state.view === 'balance') renderBalance();
    if (state.view === 'statement') renderStatement();
}

function applyResponse(result, successToMenu = false) {
    if (result && result.data) applyData(result.data);
    if (!result || result.ok !== true) {
        toast((result && result.message) || 'Nao foi possivel concluir a operacao.', 'error');
        return false;
    }
    if (result.message) toast(result.message, 'success');
    if (successToMenu) {
        state.amounts = { withdraw: '', deposit: '', transfer: '' };
        ['withdraw', 'deposit', 'transfer'].forEach(renderAmount);
        document.getElementById('transfer-target').value = '';
        show('menu');
    }
    return true;
}

function setFocus(which) {
    state.focus = which;
    const input = document.getElementById('transfer-target');
    if (input) input.classList.toggle('focus-field', which === 'target');
}

function currentAmountTarget() {
    return ['withdraw', 'deposit', 'transfer'].includes(state.view) ? state.view : null;
}

function typeDigit(digit) {
    if (state.busy) return;
    if (state.view === 'transfer' && state.focus === 'target') {
        const input = document.getElementById('transfer-target');
        input.value = (input.value + digit).slice(0, 6);
        return;
    }
    const target = currentAmountTarget();
    if (!target) return;
    const current = state.amounts[target] || '';
    if (current.length >= 9) return;
    state.amounts[target] = String(parseInt(current + digit, 10) || 0);
    renderAmount(target);
}

function backspace() {
    if (state.busy) return;
    if (state.view === 'transfer' && state.focus === 'target') {
        const input = document.getElementById('transfer-target');
        input.value = input.value.slice(0, -1);
        return;
    }
    const target = currentAmountTarget();
    if (!target) return;
    state.amounts[target] = String(state.amounts[target] || '').slice(0, -1);
    renderAmount(target);
}

function clearAmount() {
    if (state.busy) return;
    if (state.view === 'transfer' && state.focus === 'target') {
        document.getElementById('transfer-target').value = '';
        return;
    }
    const target = currentAmountTarget();
    if (!target) return;
    state.amounts[target] = '';
    renderAmount(target);
}

function quick(target, value) {
    if (state.busy) return;
    state.amounts[target] = String(value);
    renderAmount(target);
    beep(600, 40);
}

let processingTimer = null;
function processing(on) {
    state.busy = on;
    document.getElementById('processing').classList.toggle('hidden', !on);
    renderSoftKeys(state.view);
    clearTimeout(processingTimer);
    if (on) {
        processingTimer = setTimeout(() => {
            state.busy = false;
            document.getElementById('processing').classList.add('hidden');
            renderSoftKeys(state.view);
            toast('A operacao excedeu o tempo limite.', 'error');
        }, REQUEST_TIMEOUT_MS + 500);
    }
}

async function enterCard() {
    if (state.busy || state.cardInserted || state.channel !== 'atm') return;
    processing(true);
    beep(760, 90);
    try {
        const result = await nui('authenticate');
        if (applyResponse(result)) {
            state.cardInserted = true;
            setCardState('inserted');
            show('menu');
        } else {
            setCardState('error');
            setTimeout(() => {
                if (!state.cardInserted && !app.classList.contains('hidden')) setCardState('waiting');
            }, 900);
        }
    } finally {
        processing(false);
    }
}

function createIdempotencyKey() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
        return window.crypto.randomUUID();
    }
    const bytes = new Uint8Array(16);
    if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
        window.crypto.getRandomValues(bytes);
    } else {
        for (let index = 0; index < bytes.length; index += 1) {
            bytes[index] = Math.floor(Math.random() * 256);
        }
    }
    const random = Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
    return `mzbank_${Date.now().toString(36)}_${random}`;
}

function operationFingerprint(kind, payload) {
    return JSON.stringify([
        kind,
        payload.amount,
        kind === 'transfer' ? String(payload.recipientValue || '') : '',
    ]);
}

async function confirmAction(kind) {
    if (state.busy) return;
    const amount = parseInt(state.amounts[kind] || '0', 10);
    if (!amount || amount <= 0) return toast('Valor invalido', 'error');
    const payload = { amount };
    if (kind === 'transfer') {
        payload.recipientValue = document.getElementById('transfer-target').value;
        if (!payload.recipientValue) return toast('Informe o ID de destino', 'error');
    }
    const fingerprint = operationFingerprint(kind, payload);
    const pending = state.pendingOperations[kind];
    if (!pending || pending.fingerprint !== fingerprint) {
        state.pendingOperations[kind] = { fingerprint, key: createIdempotencyKey() };
        savePendingOperations(state.pendingOperations);
    }
    payload.idempotencyKey = state.pendingOperations[kind].key;

    processing(true);
    try {
        const result = await nui(kind, payload);
        if (result && (result.ok === true || result.error === 'idempotency_conflict' || result.error === 'invalid_idempotency_key')) {
            delete state.pendingOperations[kind];
            savePendingOperations(state.pendingOperations);
        }
        applyResponse(result, result && result.ok === true);
    } finally {
        processing(false);
    }
}

let toastTimer = null;
function toast(message, type = 'info') {
    const element = document.getElementById('toast');
    element.textContent = message;
    element.className = `toast ${type}`;
    beep(type === 'error' ? 220 : 880, 120, type === 'error' ? 'sawtooth' : 'square');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => element.classList.add('hidden'), 2600);
}

function setCurrency(symbol) {
    state.currencySymbol = String(symbol || 'R$');
    document.querySelectorAll('.currency-symbol').forEach((element) => { element.textContent = state.currencySymbol; });
    renderSoftKeys(state.view);
}

function openApp(message) {
    app.classList.remove('hidden');
    document.getElementById('brand-name').textContent = message.bankName || 'Banco Central';
    state.channel = message.channel || 'atm';
    state.cardInserted = message.authenticated === true;
    setCurrency(message.currencySymbol || 'R$');
    if (message.data) applyData(message.data);
    setCardState(state.cardInserted ? 'inserted' : 'waiting');
    show(message.authenticated === true && message.data ? 'menu' : 'welcome');
    if (message.issueMessage) toast(message.issueMessage, message.issueOk === false ? 'error' : 'success');
    beep(720, 80);
}

function closeApp() {
    processing(false);
    app.classList.add('hidden');
    state.amounts = { withdraw: '', deposit: '', transfer: '' };
    state.cardInserted = false;
    setCardState('waiting');
}

function exitBank() {
    if (state.busy) return;
    beep(400, 100, 'sawtooth');

    if (state.channel === 'atm' && state.cardInserted) {
        state.busy = true;
        state.cardInserted = false;
        setCardState('ejecting');
        setTimeout(() => {
            nui('close');
            state.busy = false;
            if (IS_BROWSER) closeApp();
        }, 550);
        return;
    }

    nui('close');
    if (IS_BROWSER) closeApp();
}

window.addEventListener('message', (event) => {
    const message = event.data || {};
    if (message.action === 'open') openApp(message);
    else if (message.action === 'close') closeApp();
    else if (message.action === 'update') applyData(message.data || {});
    else if (message.action === 'cardRejected') {
        state.cardInserted = false;
        setCardState('error');
    }
});

document.addEventListener('keydown', (event) => {
    if (app.classList.contains('hidden')) return;
    if (event.key === 'Escape') return exitBank();
    if (event.key >= '0' && event.key <= '9') typeDigit(event.key);
    else if (event.key === 'Backspace') { event.preventDefault(); backspace(); }
    else if (event.key === 'Enter' && !state.busy) {
        const target = currentAmountTarget();
        if (target) confirmAction(target);
        else if (state.view === 'welcome') enterCard();
    }
});

document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.sslot').forEach((slot) => {
        slot.querySelector('.soft-key').addEventListener('click', () => runSoft(Number(slot.dataset.soft)));
    });
    document.querySelectorAll('.key').forEach((key) => {
        key.addEventListener('click', () => {
            if (state.busy) return;
            const value = key.dataset.key;
            beep(680, 35);
            if (value === 'cancel') exitBank();
            else if (value === 'clear') clearAmount();
            else if (value === 'back') backspace();
            else if (value === 'enter') {
                const target = currentAmountTarget();
                if (target) confirmAction(target);
                else if (state.view === 'welcome') enterCard();
            } else typeDigit(value);
        });
    });
    document.getElementById('transfer-target').addEventListener('click', () => setFocus('target'));
    document.getElementById('card-slot').addEventListener('click', () => enterCard());
    if (IS_BROWSER) openApp({ bankName: 'Banco Central', currencySymbol: 'R$', channel: 'atm' });
});

async function mockNui(callback, body) {
    const data = mockNui.data || (mockNui.data = {
        balance: 12500,
        cash: 800,
        name: 'Joao Silva',
        account: 'Conta corrente',
        statement: [
            { type: 'atm_deposit', amount: 500, created_at: Date.now() - 3600000 },
            { type: 'atm_withdraw', amount: -200, created_at: Date.now() - 7200000 },
        ],
    });
    await new Promise((resolve) => setTimeout(resolve, 350));
    if (callback === 'close') return { ok: true };
    if (callback === 'authenticate' || callback === 'refresh') return { ok: true, data };
    if (callback === 'withdraw') {
        if (data.balance < body.amount) return { ok: false, error: 'not_enough_bank', message: 'Saldo bancario insuficiente.' };
        data.balance -= body.amount; data.cash += body.amount;
        data.statement.unshift({ type: 'atm_withdraw', amount: -body.amount, created_at: Date.now() });
    } else if (callback === 'deposit') {
        if (data.cash < body.amount) return { ok: false, error: 'not_enough_wallet', message: 'Dinheiro em especie insuficiente.' };
        data.balance += body.amount; data.cash -= body.amount;
        data.statement.unshift({ type: 'atm_deposit', amount: body.amount, created_at: Date.now() });
    } else if (callback === 'transfer') {
        if (data.balance < body.amount) return { ok: false, error: 'not_enough_bank', message: 'Saldo bancario insuficiente.' };
        data.balance -= body.amount;
        data.statement.unshift({ type: 'atm_transfer', amount: -body.amount, created_at: Date.now() });
    }
    return { ok: true, message: 'Operacao realizada com sucesso.', data };
}
