"use strict";
const byId = id => document.getElementById(id);
let api;
let operationBusy = false;
let statusRequest;
let pollTimer;
let installation;
let runtime = { connected: false, ready: false };
let pendingSettings;
let pendingUpgrade;
let pendingSearch;
let searchTimer;
let searchGeneration = 0;
let candidateGeneration = -1;
let searchSend = Promise.resolve();
let chosenItem;

function message(id, text, error = false) {
    byId(id).textContent = text;
    byId(id).dataset.error = String(error);
}

function errorText(error) {
    return String(error).split('\n')[0].replace(/^.*\.lua:\d+:\s*/, '');
}

function selectedSettings() {
    return { randomWeapons: byId('random-weapons').checked,
        randomShadowWeapons: byId('random-shadow').checked };
}

function updateControls() {
    document.querySelectorAll('button,input,select').forEach(element => {
        element.disabled = operationBusy || !api;
    });
    const currentVersion = installation?.version === '0.6.3-ue4ss' && installation?.installed;
    byId('apply').disabled ||= !currentVersion;
    byId('upgrade').disabled ||= !currentVersion || !runtime.connected || !runtime.ready || Boolean(pendingUpgrade);
    byId('fragments-toggle').disabled ||= !currentVersion || !runtime.connected;
    byId('item-open').disabled ||= !currentVersion || !runtime.connected || !runtime.ready;
    byId('item-query').disabled ||= !currentVersion || !runtime.connected || !runtime.ready;
    byId('item-confirm').disabled ||= !currentVersion || !runtime.connected || !runtime.ready ||
        candidateGeneration !== searchGeneration || !chosenItem?.remainingCount;
    byId('item-clear').disabled ||= !currentVersion || !runtime.connected || !runtime.mapItemID;
    document.querySelectorAll('[data-item-id]').forEach(button => {
        button.disabled ||= !currentVersion || !runtime.connected || !runtime.ready || candidateGeneration !== searchGeneration;
    });
    byId('install').textContent = operationBusy ? '处理中…' : '安装 / 更新';
}

async function call(method, ...arguments_) {
    const result = await api[method](...arguments_);
    if (!result?.ok)
        throw new Error(result?.error || '操作失败');
    return result.data;
}

function showInstallation(result) {
    installation = result;
    byId('directory').value = result.directory;
    byId('random-weapons').checked = result.settings.randomWeapons;
    byId('random-shadow').checked = result.settings.randomShadowWeapons;
    message('status', result.message || describeInstallation(result));
}

function describeInstallation(result) {
    if (!result.installed)
        return '未安装';
    if (result.version !== '0.6.3-ue4ss')
        return '需要更新';
    return '已安装';
}

function resetConnection() {
    runtime = { connected: false, ready: false };
    pendingSettings = undefined;
    if (pendingUpgrade)
        message('upgrade-result', '升级结果未确认', true);
    pendingUpgrade = undefined;
    closeItemPicker();
    byId('item-results').replaceChildren();
    message('item-state', '');
    message('connection', '等待连接');
    byId('connection').dataset.state = 'waiting';
    message('equipment-state', '');
    message('map-state', '');
    updateControls();
}

function showRuntime(state) {
    runtime = state;
    message('connection', state.error ? errorText(state.error) : state.message, Boolean(state.error));
    byId('connection').dataset.state = state.connected && state.ready ? 'connected' : 'waiting';
    if (state.connected) {
        const equipment = state.equipment;
        message('equipment-state', equipment?.error ? errorText(equipment.error) : '', Boolean(equipment?.error));
        showFragments(state.fragments, state.map);
        showItems(state.items);
    } else {
        message('equipment-state', '');
        message('map-state', '');
    }
    resolveSettings(state);
    resolveUpgrade(state);
    updateControls();
}

function showFragments(fragments, map) {
    const enabled = fragments?.enabled === true;
    byId('fragments-toggle').setAttribute('aria-checked', String(enabled));
    const error = map?.error || runtime.tracking?.error;
    const description = error ? errorText(error) : (enabled ? `${fragments.count} 个未取得` : '');
    message('map-state', description, Boolean(error));
}

function showItems(search) {
    if (!byId('item-picker').open || !pendingSearch)
        return;
    if (search?.requestId !== pendingSearch.requestId) {
        if (Date.now() > pendingSearch.deadline) {
            message('item-picker-state', '搜索无响应，请重试', true);
            pendingSearch = undefined;
        }
        return;
    }
    if (pendingSearch.generation !== searchGeneration)
        return;
    candidateGeneration = searchGeneration;
    message('item-picker-state', search.error ? errorText(search.error) : `${search.total} 项${search.total > 80 ? '，显示前 80 项' : ''}`, Boolean(search.error));
    pendingSearch = undefined;
    const list = byId('item-results');
    list.replaceChildren();
    chosenItem = undefined;
    for (const item of search.results || [])
        list.append(createItemCandidate(item));
}

function createItemCandidate(item) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'item-candidate';
    row.dataset.itemId = item.id;
    row.setAttribute('role', 'option');
    row.setAttribute('aria-selected', 'false');
    const name = document.createElement('strong');
    name.textContent = item.name;
    const source = document.createElement('span');
    source.className = 'candidate-source';
    source.textContent = item.source;
    row.append(name, source);
    row.addEventListener('click', () => {
        chosenItem = item;
        byId('item-results').querySelectorAll('[data-item-id]').forEach(candidate => {
            candidate.setAttribute('aria-selected', String(candidate.dataset.itemId === item.id));
        });
        updateControls();
    });
    return row;
}

function closeItemPicker() {
    clearTimeout(searchTimer);
    searchGeneration += 1;
    candidateGeneration = -1;
    pendingSearch = undefined;
    chosenItem = undefined;
    if (byId('item-picker').open)
        byId('item-picker').close();
    schedulePoll();
}

function scheduleCandidateSearch() {
    clearTimeout(searchTimer);
    const generation = ++searchGeneration;
    const query = byId('item-query').value.trim();
    pendingSearch = undefined;
    chosenItem = undefined;
    message('item-picker-state', query ? '搜索中…' : '');
    if (!query) {
        byId('item-results').replaceChildren();
        updateControls();
        return;
    }
    updateControls();
    searchTimer = setTimeout(() => queueCandidateSearch(query, generation), 200);
}

function queueCandidateSearch(query, generation) {
    // 查询串行发送；尚未发送的旧输入直接跳过，输入框始终可编辑。
    searchSend = searchSend.then(async () => {
        if (generation !== searchGeneration || !byId('item-picker').open)
            return;
        try {
            const result = await call('search_items', byId('directory').value, query);
            if (generation === searchGeneration && byId('item-picker').open) {
                pendingSearch = { ...result, generation, deadline: Date.now() + 20000 };
                schedulePoll();
            }
        } catch (error) {
            if (generation === searchGeneration)
                message('item-picker-state', error.message, true);
        }
    });
}

function resolveSettings(state) {
    if (!pendingSettings)
        return;
    if (state.connected && state.ready && state.revision === pendingSettings.revision) {
        message('settings-result', '已应用');
        pendingSettings = undefined;
    }
}

function resolveUpgrade(state) {
    if (!pendingUpgrade)
        return;
    const result = state.connected ? state.result : undefined;
    if (result?.id === pendingUpgrade.requestId) {
        if (!result.ok) {
            message('upgrade-result', '升级失败：' + errorText(result.error), true);
        } else {
            const report = result.report;
            let text = `30 级：主武器 ${report.main.succeeded}/${report.main.total}，影之武装 ${report.shadow.succeeded}/${report.shadow.total}`;
            if (report.failed.length)
                text += ' 未达目标：' + report.failed.map(item => `${item.category} ${item.weaponID}（${item.actualLevel} 级，上限 ${item.maxLevel}）`).join('、') + '。';
            message('upgrade-result', text, !report.complete);
        }
        pendingUpgrade = undefined;
    } else if (Date.now() > pendingUpgrade.deadline) {
        message('upgrade-result', '未收到升级结果，请检查游戏内等级', true);
        pendingUpgrade = undefined;
    }
}

function schedulePoll() {
    clearTimeout(pollTimer);
    if (api && !operationBusy)
        pollTimer = setTimeout(refreshRuntime, byId('item-picker').open ? 160 : 1000);
}

async function refreshRuntime() {
    if (!api || operationBusy || statusRequest)
        return;
    const directory = byId('directory').value;
    statusRequest = call('runtime_status', directory);
    try {
        const state = await statusRequest;
        if (directory === byId('directory').value)
            showRuntime(state);
    } catch (error) {
        if (directory === byId('directory').value)
            showRuntime({ connected: false, ready: false, message: error.message });
    } finally {
        statusRequest = undefined;
        schedulePoll();
    }
}

async function operate(action, resultId = 'status') {
    if (operationBusy || !api)
        return;
    operationBusy = true;
    clearTimeout(pollTimer);
    updateControls();
    try {
        // 接受点击后等待只读检查结束，避免轮询与操作争用界面状态。
        if (statusRequest)
            await statusRequest.catch(() => {});
        await action();
    } catch (error) {
        message(resultId, error.message, true);
    } finally {
        operationBusy = false;
        updateControls();
        schedulePoll();
    }
}

byId('directory').addEventListener('change', () => operate(async () => {
    installation = undefined;
    resetConnection();
    showInstallation(await call('inspect', byId('directory').value));
}));
byId('choose').addEventListener('click', () => operate(async () => {
    const selection = await call('choose_directory', byId('directory').value);
    if (selection.directory) {
        byId('directory').value = selection.directory;
        installation = undefined;
        resetConnection();
        showInstallation(await call('inspect', selection.directory));
    }
}));
byId('refresh').addEventListener('click', () => operate(async () => {
    showInstallation(await call('inspect', byId('directory').value));
}));
byId('install').addEventListener('click', () => operate(async () => {
    message('status', '安装中…');
    showInstallation(await call('install', byId('directory').value, selectedSettings()));
    resetConnection();
}));
byId('uninstall').addEventListener('click', () => operate(async () => {
    showInstallation(await call('uninstall', byId('directory').value));
    resetConnection();
}));
byId('apply').addEventListener('click', () => operate(async () => {
    const result = await call('apply_settings', byId('directory').value, selectedSettings());
    pendingSettings = result;
    message('settings-result', result.message);
}, 'settings-result'));
byId('upgrade').addEventListener('click', () => operate(async () => {
    const result = await call('upgrade_weapons', byId('directory').value);
    pendingUpgrade = { ...result, deadline: Date.now() + 15000 };
    message('upgrade-result', result.message);
}, 'upgrade-result'));
byId('fragments-toggle').addEventListener('click', () => operate(async () => {
    const enabled = runtime.fragments?.enabled !== true;
    const result = await call('fragment_settings', byId('directory').value, enabled);
    message('map-state', result.message);
}, 'map-state'));
byId('item-open').addEventListener('click', () => {
    byId('item-picker').showModal();
    byId('item-query').focus();
    scheduleCandidateSearch();
    schedulePoll();
});
byId('item-query').addEventListener('input', event => {
    if (!event.isComposing)
        scheduleCandidateSearch();
});
byId('item-query').addEventListener('compositionend', scheduleCandidateSearch);
byId('item-query').addEventListener('compositionstart', () => {
    clearTimeout(searchTimer);
    searchGeneration += 1;
    pendingSearch = undefined;
    chosenItem = undefined;
    updateControls();
});
byId('item-query').addEventListener('keydown', event => {
    if (event.key === 'Enter' && !event.isComposing && !byId('item-confirm').disabled) {
        event.preventDefault();
        byId('item-confirm').click();
    }
});
byId('item-cancel').addEventListener('click', closeItemPicker);
byId('item-picker').addEventListener('cancel', event => {
    event.preventDefault();
    closeItemPicker();
});
byId('item-confirm').addEventListener('click', () => operate(async () => {
    const result = await call('show_item', byId('directory').value, chosenItem.id);
    message('item-state', result.message);
    closeItemPicker();
}, 'item-picker-state'));
byId('item-clear').addEventListener('click', () => operate(async () => {
    const result = await call('show_item', byId('directory').value, '');
    message('item-state', result.message);
}, 'item-state'));

async function start() {
    if (api || !window.pywebview?.api)
        return;
    api = window.pywebview.api;
    await operate(async () => {
        const config = await call('initialize');
        byId('directory').value = config.directory;
        showInstallation(await call('inspect', config.directory));
    });
}
window.addEventListener('pywebviewready', start);
start();
