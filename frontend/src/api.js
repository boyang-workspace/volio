const API = '/api'

export async function getJSON(url) {
  const r = await fetch(url)
  return r.json()
}

export async function postJSON(url, data) {
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  return r.json()
}

export async function delJSON(url, data) {
  const r = await fetch(url, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  return r.json()
}

export function loadArtworks(options = {}) {
  const params = new URLSearchParams()
  if (options.includeDeleted) params.set('include_deleted', 'true')
  const query = params.toString()
  return getJSON(`${API}/artworks${query ? `?${query}` : ''}`)
}

export function loadArtwork(id) {
  return getJSON(`${API}/artworks/${id}`)
}

export function loadFacets() {
  return getJSON(`${API}/facets`)
}

export function loadChildren() {
  return getJSON(`${API}/children`)
}

export function loadSettings() {
  return getJSON(`${API}/settings`)
}

export function loadState() {
  return getJSON(`${API}/state`)
}

export async function saveSettings(data) {
  const r = await fetch(`${API}/settings`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to save settings')
  return r.json()
}

export async function addChild(name) {
  const fd = new FormData()
  fd.set('name', name)
  const r = await fetch(`${API}/children`, { method: 'POST', body: fd })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to add child')
  return r.json()
}

export async function updateChild(id, name) {
  const r = await fetch(`${API}/children/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
  })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to update child')
  return r.json()
}

export async function deleteChild(id) {
  const r = await fetch(`${API}/children/${id}`, { method: 'DELETE' })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to delete child')
  return r.json()
}

export function deleteArtwork(id) {
  return fetch(`${API}/artworks/${id}`, { method: 'DELETE' })
}

export function restoreArtwork(id) {
  return postJSON(`${API}/artworks/${id}/restore`, {})
}

export function updateArtwork(id, data) {
  return fetch(`${API}/artworks/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
}

export function addTag(id, name) {
  return postJSON(`${API}/artworks/${id}/tags`, {
    name: name.trim(),
    type: 'custom',
    source: 'manual',
  })
}

export function removeTag(id, name, type) {
  return delJSON(`${API}/artworks/${id}/tags`, { name, type })
}

export function importPhoto(childName, file) {
  const fd = new FormData()
  fd.set('child_name', childName)
  fd.set('batch_name', '')
  fd.set('artwork_date', '')
  fd.set('date_note', '')
  fd.set('auto_analyze', 'true')
  fd.append('files', file, file.name)
  return fetch(`${API}/import`, { method: 'POST', body: fd })
}

export async function createMobileSession(childName) {
  const r = await fetch(`${API}/mobile/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ child_name: childName || '' }),
  })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to create phone import session')
  return r.json()
}

export async function createIosPairingSession() {
  const r = await fetch(`${API}/ios/pairing/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to create iPhone pairing session')
  return r.json()
}

export async function checkIosPairingSession(token) {
  const r = await fetch(`${API}/ios/pairing/session/${token}`, {
    headers: { 'X-Volio-Token': token },
  })
  if (!r.ok) return { valid: false }
  return r.json()
}

export async function checkMobileSession(token) {
  const r = await fetch(`${API}/mobile/session/${token}`)
  if (!r.ok) return { valid: false }
  return r.json()
}

export function getQueueStatus() {
  return getJSON(`${API}/ai/queue`)
}

export function pauseQueue() {
  return postJSON(`${API}/ai/queue/pause`, {})
}

export function resumeQueue() {
  return postJSON(`${API}/ai/queue/resume`, {})
}

export function processNow() {
  return postJSON(`${API}/ai/queue/process-now`, {})
}

export function analyzeArtwork(id) {
  return postJSON(`${API}/artworks/${id}/analyze`, {})
}

export async function processArtworkImage(id, data = {}) {
  const r = await fetch(`${API}/artworks/${id}/process`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!r.ok) throw new Error((await r.json()).detail || 'Failed to process image')
  return r.json()
}
