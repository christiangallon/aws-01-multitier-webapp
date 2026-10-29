(() => {
  'use strict';

  const $ = (sel) => document.querySelector(sel);
  const itemsEl = $('#items');
  const errorEl = $('#error');

  function showError(message) {
    errorEl.textContent = message || '';
  }

  async function api(path, options = {}) {
    const res = await fetch(path, {
      headers: { 'Content-Type': 'application/json' },
      ...options,
    });
    if (res.status === 204) return null;
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`);
    return body;
  }

  function renderItem(item) {
    const li = document.createElement('li');

    const text = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = item.name;
    const desc = document.createElement('p');
    desc.textContent = item.description || '';
    const meta = document.createElement('small');
    meta.textContent = `Created ${new Date(item.created_at).toLocaleString()}`;
    text.append(title, desc, meta);

    const del = document.createElement('button');
    del.textContent = 'Delete';
    del.className = 'danger';
    del.addEventListener('click', async () => {
      try {
        await api(`/api/items/${encodeURIComponent(item.id)}`, { method: 'DELETE' });
        await loadItems();
      } catch (err) {
        showError(err.message);
      }
    });

    li.append(text, del);
    return li;
  }

  async function loadItems() {
    try {
      const { data } = await api('/api/items');
      itemsEl.replaceChildren(...data.map(renderItem));
      if (data.length === 0) {
        const empty = document.createElement('li');
        empty.textContent = 'No items yet.';
        itemsEl.append(empty);
      }
      showError('');
    } catch (err) {
      showError(err.message);
    }
  }

  async function loadHealth() {
    const el = $('#health');
    try {
      const h = await api('/health');
      el.textContent = `App: ${h.status} · DB: ${h.db} · host: ${h.hostname} · version: ${String(h.version).slice(0, 8)}`;
      el.className = h.db === 'up' ? 'health ok' : 'health warn';
    } catch (err) {
      el.textContent = `Health check failed: ${err.message}`;
      el.className = 'health bad';
    }
  }

  $('#item-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const name = $('#name').value.trim();
    const description = $('#description').value.trim();
    try {
      await api('/api/items', {
        method: 'POST',
        body: JSON.stringify({ name, description: description || undefined }),
      });
      event.target.reset();
      await loadItems();
    } catch (err) {
      showError(err.message);
    }
  });

  $('#refresh').addEventListener('click', () => {
    loadHealth();
    loadItems();
  });

  loadHealth();
  loadItems();
})();
