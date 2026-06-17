(() => {
  'use strict';

  let allWorks = [];
  let facets = {};
  let children = [];
  let currentNav = 'all';
  let currentTagFilter = null;
  let currentChild = null;
  let currentView = 'grid';
  let selectedWorkId = null;
  let searchQuery = '';
  let loadPromise = null;

  const $ = id => document.getElementById(id);
  const contentArea = $('contentArea');
  const detailScroll = $('detailScroll');

  /* ─── Fetch helpers ─── */
  async function getJSON(url) {
    const r = await fetch(url);
    return r.json();
  }
  async function delJSON(url, data) {
    const r = await fetch(url, { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    return r.json();
  }
  async function postJSON(url, data) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    return r.json();
  }

  /* ─── Toast ─── */
  let toastTimer;
  function toast(msg) {
    const el = $('toast');
    el.textContent = msg; el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.hidden = true, 2500);
  }

  /* ─── Load data ─── */
  async function loadAll() {
    const [w, f, c] = await Promise.all([
      getJSON('/api/artworks'),
      getJSON('/api/facets'),
      getJSON('/api/children'),
    ]);
    allWorks = w || [];
    facets = f;
    children = c;
    renderSidebarNav();
    renderChildren();
    renderWorks();
    if (allWorks.length && !selectedWorkId) {
      selectWork(allWorks[0].id);
    }
  }

  /* ─── Sidebar nav ─── */
  function renderSidebarNav() {
    const body = $('smartBody');
    body.innerHTML = '';
    const tagGroups = facets.tags;
    if (tagGroups) {
      for (const [type, tags] of Object.entries(tagGroups)) {
        if (!tags || !tags.length) continue;
        const header = document.createElement('div');
        header.className = 'nav-group-header';
        header.textContent = type;
        body.appendChild(header);
        for (const t of tags) {
          const btn = document.createElement('button');
          btn.className = 'nav-tag-item';
          btn.dataset.tagType = type;
          btn.dataset.tagName = t.name || t.tag || t;
          btn.innerHTML = `<span>${btn.dataset.tagName}</span><span class="count">${t.count || ''}</span>`;
          btn.addEventListener('click', () => selectSmartPortfolio(type, btn.dataset.tagName));
          body.appendChild(btn);
        }
      }
    }
    $('smartGroup').hidden = !body.children.length;
  }

  function selectNav(nav) {
    currentNav = nav;
    currentTagFilter = null;
    document.querySelectorAll('.nav-item').forEach(el => el.classList.toggle('active', el.dataset.nav === nav));
    document.querySelectorAll('.nav-tag-item').forEach(el => el.classList.remove('active'));
    renderWorks();
    autoSelectFirst();
  }

  function selectSmartPortfolio(type, name) {
    currentNav = 'smart';
    currentTagFilter = { type, name };
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.nav-tag-item').forEach(el => el.classList.remove('active'));
    document.querySelectorAll(`.nav-tag-item[data-tag-type="${type}"][data-tag-name="${name}"]`).forEach(el => el.classList.add('active'));
    renderWorks();
    autoSelectFirst();
  }

  function autoSelectFirst() {
    const list = filteredWorks();
    if (list.length) {
      selectWork(list[0].id);
    }
  }

  function renderChildren() {
    const strip = $('childStrip');
    if (!children.length) { strip.hidden = true; return; }
    strip.hidden = false;
    strip.innerHTML = '';
    const allBtn = document.createElement('button');
    allBtn.className = 'child-chip' + (currentChild === null ? ' active' : '');
    allBtn.textContent = 'All';
    allBtn.addEventListener('click', () => { currentChild = null; renderChildren(); renderWorks(); autoSelectFirst(); });
    strip.appendChild(allBtn);
    for (const c of children) {
      const btn = document.createElement('button');
      btn.className = 'child-chip' + (currentChild === c.id ? ' active' : '');
      btn.textContent = c.name;
      btn.addEventListener('click', () => { currentChild = c.id; renderChildren(); renderWorks(); autoSelectFirst(); });
      strip.appendChild(btn);
    }
  }

  /* ─── Filtering ─── */
  function filteredWorks() {
    let list = allWorks;
    if (currentNav === 'smart' && currentTagFilter) {
      list = list.filter(w => {
        if (!w.tags) return false;
        for (const t of w.tags) {
          if (t.type === currentTagFilter.type && t.name === currentTagFilter.name) return true;
        }
        return false;
      });
    }
    if (currentChild) {
      list = list.filter(w => w.child_id === currentChild);
    }
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      list = list.filter(w =>
        (w.title && w.title.toLowerCase().includes(q)) ||
        (w.description && w.description.toLowerCase().includes(q)) ||
        (w.tags && w.tags.some(t => t.name.toLowerCase().includes(q)))
      );
    }
    return list;
  }

  /* ─── Render works ─── */
  function renderWorks() {
    const list = filteredWorks();
    if (!list.length) {
      contentArea.innerHTML = '<div class="empty-state"><strong>No artworks found</strong><span>Try a different filter or search query.</span></div>';
      return;
    }
    if (currentView === 'timeline') renderTimeline(list);
    else renderGrid(list);
  }

  function renderGrid(list) {
    const grid = document.createElement('div');
    grid.className = currentView === 'masonry' ? 'works-masonry' : 'works-grid';
    for (const w of list) {
      const card = createWorkCard(w);
      grid.appendChild(card);
    }
    contentArea.innerHTML = '';
    contentArea.appendChild(grid);
  }

  function renderTimeline(list) {
    const groups = {};
    for (const w of list) {
      const key = w.artwork_date || 'Unknown';
      if (!groups[key]) groups[key] = [];
      groups[key].push(w);
    }
    const container = document.createElement('div');
    container.className = 'works-timeline';
    const sorted = Object.entries(groups).sort((a, b) => b[0].localeCompare(a[0]));
    for (const [date, works] of sorted) {
      const section = document.createElement('div');
      section.className = 'tl-entry';
      section.innerHTML = `
        <div class="tl-axis"><span class="tl-date">${date}</span><span class="tl-dot"></span><span class="tl-line"></span></div>
        <div class="tl-content"><div class="tl-count">${works.length} work${works.length > 1 ? 's' : ''}</div></div>
      `;
      const contentDiv = section.querySelector('.tl-content');
      const innerGrid = document.createElement('div');
      innerGrid.className = currentView === 'masonry' ? 'works-masonry' : 'works-grid';
      for (const w of works) innerGrid.appendChild(createWorkCard(w));
      contentDiv.appendChild(innerGrid);
      container.appendChild(section);
    }
    contentArea.innerHTML = '';
    contentArea.appendChild(container);
  }

  function createWorkCard(w) {
    const card = document.createElement('div');
    const path = w.thumbnail_url || w.thumbnail || w.original_url || w.path || '';
    const title = w.title || 'Untitled';
    const date = w.artwork_date || '';
    card.className = 'work-card' + (w.id === selectedWorkId ? ' active' : '');
    card.innerHTML = `<img class="work-thumb" src="${path}" alt="${title}" loading="lazy" />`
      + `<div class="work-body"><div class="title">${title}</div>${date ? '<div class="meta">' + date + '</div>' : ''}</div>`;
    if (w.id === selectedWorkId) card.classList.add('active');
    card.addEventListener('click', () => selectWork(w.id));
    return card;
  }

  /* ─── Select work → detail pane ─── */
  async function selectWork(id) {
    selectedWorkId = id;
    renderWorks();
    detailScroll.innerHTML = '<div class="empty-state"><strong>Loading…</strong></div>';

    try {
      const data = await getJSON('/api/artworks/' + id);
      const w = data.work || data;
      renderDetail(w);
    } catch (e) {
      detailScroll.innerHTML = '<div class="detail-body"><div style="color:var(--muted);padding:20px;text-align:center">Error loading details</div></div>';
      toast('Failed to load artwork details');
    }
  }

  function renderDetail(w) {
    const path = w.original_url || w.source || w.path || '';
    const title = w.title || 'Untitled';
    const date = w.artwork_date || '';
    const child = w.child_name || '';
    const desc = w.description || '';
    const tags = w.tags || [];

    let tagsHtml = '<div class="chip-list">';
    for (const t of tags) {
      tagsHtml += `<span class="chip">${t.name}<span class="chip-del" data-tag-name="${t.name}" data-tag-type="${t.type}">✕</span></span>`;
    }
    tagsHtml += `<button class="chip-add" id="addTagBtn">+ Add tag</button></div>`;

    const metaParts = [];
    if (date) metaParts.push(date);
    if (child) metaParts.push(child);

    detailScroll.innerHTML = `
      <div class="detail-image-wrap" id="detailImageWrap">
        <img src="${path}" alt="${title}" />
      </div>
      <div class="detail-body">
        <div class="detail-header">
          <h2>${title}</h2>
          ${metaParts.length ? '<div class="detail-meta">' + metaParts.map(p => '<span>' + p + '</span>').join('') + '</div>' : ''}
        </div>
        ${desc ? '<div><div class="detail-section-head">Description</div><div class="detail-desc">' + desc + '</div></div>' : ''}
        <div>
          <div class="detail-section-head">Tags</div>
          ${tagsHtml}
        </div>
        <div class="detail-actions">
          <button id="editDetailBtn">Edit</button>
          <button id="deleteDetailBtn" style="color:var(--red)">Delete</button>
        </div>
      </div>
    `;

    $('detailImageWrap').addEventListener('click', () => openLightbox(path));

    detailScroll.querySelectorAll('.chip-del').forEach(el => {
      el.addEventListener('click', async e => {
        e.stopPropagation();
        const name = el.dataset.tagName;
        const type = el.dataset.tagType;
        try {
          await delJSON('/api/artworks/' + w.id + '/tags', { name, type });
          toast('Tag removed');
          selectWork(w.id);
        } catch (e2) { toast('Failed to remove tag'); }
      });
    });

    $('addTagBtn').addEventListener('click', () => {
      const name = prompt('Enter tag name:');
      if (name && name.trim()) {
        postJSON('/api/artworks/' + w.id + '/tags', { name: name.trim(), type: 'custom', source: 'manual' })
          .then(() => { toast('Tag added'); selectWork(w.id); })
          .catch(() => toast('Failed to add tag'));
      }
    });

    $('editDetailBtn').addEventListener('click', () => openEdit(w));

    $('deleteDetailBtn').addEventListener('click', async () => {
      if (!confirm('Delete this artwork?')) return;
      try {
        await fetch('/api/artworks/' + w.id, { method: 'DELETE' });
        toast('Deleted');
        allWorks = allWorks.filter(x => x.id !== w.id);
        selectedWorkId = null;
        renderWorks();
        autoSelectFirst();
      } catch (e3) { toast('Failed to delete'); }
    });
  }

  /* ─── Edit detail ─── */
  function openEdit(w) {
    const form = document.createElement('div');
    form.className = 'detail-edit-area';
    form.innerHTML = `
      <label>Title <input id="editTitle" value="${(w.title || '').replace(/"/g, '&quot;')}" /></label>
      <label>Description <textarea id="editDesc">${(w.description || '').replace(/"/g, '&quot;')}</textarea></label>
      <label>Date <input id="editDate" value="${(w.artwork_date || '').replace(/"/g, '&quot;')}" /></label>
      <div style="display:flex;gap:5px">
        <button class="primary" id="saveEdit">Save</button>
        <button id="cancelEdit">Cancel</button>
      </div>
    `;
    const body = detailScroll.querySelector('.detail-body');
    body.replaceChildren(form);
    $('saveEdit').addEventListener('click', async () => {
      const updates = {};
      const title = $('editTitle').value.trim();
      const desc = $('editDesc').value.trim();
      const date = $('editDate').value.trim();
      if (title && title !== w.title) updates.title = title;
      if (desc !== (w.description || '')) updates.description = desc;
      if (date !== (w.artwork_date || '')) updates.artwork_date = date;
      if (!Object.keys(updates).length) { selectWork(w.id); return; }
      try {
        await fetch('/api/artworks/' + w.id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(updates) });
        toast('Saved');
        allWorks = await getJSON('/api/artworks');
        selectWork(w.id);
      } catch (e) { toast('Failed to save'); }
    });
    $('cancelEdit').addEventListener('click', () => selectWork(w.id));
  }

  /* ─── Lightbox ─── */
  function openLightbox(src) {
    $('lightboxImage').src = src;
    $('lightbox').hidden = false;
  }
  $('lightboxBackdrop').addEventListener('click', () => $('lightbox').hidden = true);
  $('lightboxClose').addEventListener('click', () => $('lightbox').hidden = true);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') $('lightbox').hidden = true; });

  /* ─── View switch — keep current selection ─── */
  document.querySelector('.view-switch').addEventListener('click', e => {
    const btn = e.target.closest('.view-btn');
    if (!btn) return;
    document.querySelectorAll('.view-btn').forEach(el => el.classList.remove('active'));
    btn.classList.add('active');
    currentView = btn.dataset.view;
    renderWorks();
    if (!selectedWorkId) autoSelectFirst();
  });

  /* ─── Navigation ─── */
  document.querySelector('.sidebar-nav').addEventListener('click', e => {
    const btn = e.target.closest('.nav-item');
    if (btn && btn.dataset.nav) selectNav(btn.dataset.nav);
  });

  /* ─── Search ─── */
  const searchInput = $('searchInput');
  let searchTimer;
  searchInput.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      searchQuery = searchInput.value.trim();
      renderWorks();
      autoSelectFirst();
    }, 200);
  });

  /* ─── Import modal ─── */
  $('openImport').addEventListener('click', () => $('importModal').hidden = false);
  $('closeImport').addEventListener('click', () => $('importModal').hidden = true);
  $('importModal').addEventListener('click', e => { if (e.target === $('importModal')) $('importModal').hidden = true; });

  $('importForm').addEventListener('submit', async e => {
    e.preventDefault();
    const fd = new FormData($('importForm'));
    const files = $('fileInput').files;
    if (!files.length) return toast('Select files');
    const status = $('importStatus');
    status.textContent = 'Importing…';
    let imported = 0;
    for (const f of files) {
      const single = new FormData();
      single.set('child_name', fd.get('child_name'));
      single.set('file', f, f.name);
      try {
        await fetch('/api/import', { method: 'POST', body: single });
        imported++;
      } catch (e) { console.error('Import error', f.name, e); }
    }
    status.textContent = '';
    toast(imported + ' photo(s) imported');
    $('importModal').hidden = true;
    loadAll();
  });

  /* ─── QR / Phone import ─── */
  $('openPhoneImport').addEventListener('click', async () => {
    $('qrModal').hidden = false;
    const wrap = $('qrImageWrap');
    wrap.innerHTML = '<div class="loading-state compact">Generating QR code…</div>';
    try {
      const data = await getJSON('/api/phone-import-url');
      $('qrUrl').textContent = data.url;
      const qr = await getJSON('/api/qr?url=' + encodeURIComponent(data.url));
      wrap.innerHTML = `<img src="${qr.qr}" alt="QR code" />`;
    } catch (e) {
      wrap.innerHTML = '<div class="empty-state" style="border:0;padding:10px">Failed to generate</div>';
      toast('Failed to generate QR code');
    }
  });
  $('closeQr').addEventListener('click', () => $('qrModal').hidden = true);
  $('qrModal').addEventListener('click', e => { if (e.target === $('qrModal')) $('qrModal').hidden = true; });

  /* ─── Init ─── */
  loadAll();
})();
