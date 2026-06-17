import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { loadArtworks, loadArtwork, loadFacets, loadChildren, loadSettings, loadState, checkMobileSession } from './api'
import { translate } from './i18n'
import { VolioContext } from './VolioContext'
import Sidebar from './components/Sidebar'
import MainPane from './components/MainPane'
import DetailPane from './components/DetailPane'
import ImportModal from './components/ImportModal'
import PhoneImportModal from './components/PhoneImportModal'
import IosPairingModal from './components/IosPairingModal'
import SettingsModal from './components/SettingsModal'
import Lightbox from './components/Lightbox'

export default function App() {
  const [allWorks, setAllWorks] = useState([])
  const [facets, setFacets] = useState({})
  const [children, setChildren] = useState([])
  const [currentNav, setCurrentNav] = useState('all')
  const [currentTagFilter, setCurrentTagFilter] = useState(null)
  const [currentChild, setCurrentChild] = useState(null)
  const [currentView, setCurrentView] = useState('masonry')
  const [selectedWorkId, setSelectedWorkId] = useState(null)
  const [selectedWork, setSelectedWork] = useState(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [importModalOpen, setImportModalOpen] = useState(false)
  const [phoneImportOpen, setPhoneImportOpen] = useState(false)
  const [iosPairingOpen, setIosPairingOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [lightboxSrc, setLightboxSrc] = useState(null)
  const [settings, setSettings] = useState(null)
  const [mobileSession, setMobileSession] = useState(() => {
    try {
      const data = JSON.parse(localStorage.getItem('volioMobileSession') || 'null')
      if (data?.token && data?.expiresAt > Date.now()) return data
    } catch { /* ignore */ }
    return null
  })
  const [iosPairingSession, setIosPairingSession] = useState(() => {
    try {
      const data = JSON.parse(localStorage.getItem('volioIosPairingSession') || 'null')
      if (data?.token && data?.expiresAt > Date.now()) return data
    } catch { /* ignore */ }
    return null
  })
  const toastTimer = useRef(null)
  const stateSignatureRef = useRef('')

  const toast = useCallback(msg => {
    const el = document.getElementById('app-toast')
    if (!el) return
    el.textContent = msg
    el.hidden = false
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => { el.hidden = true }, 2500)
  }, [])

  const t = useCallback((key, vars) => (
    translate(settings?.ui_language || 'en', key, vars)
  ), [settings?.ui_language])

  const loadData = useCallback(async () => {
    const [w, f, c, s] = await Promise.all([
      loadArtworks({ includeDeleted: true }),
      loadFacets(),
      loadChildren(),
      loadSettings(),
    ])
    setAllWorks(w || [])
    setFacets(f || {})
    setChildren(c || [])
    setSettings(s || null)
    return { works: w || [] }
  }, [])

  const selectWork = useCallback(async (id) => {
    setSelectedWorkId(id)
    if (!id) { setSelectedWork(null); return }
    try {
      const data = await loadArtwork(id)
      setSelectedWork(data.work || data)
    } catch { toast('Failed to load artwork details') }
  }, [toast])

  const reloadArtwork = useCallback(async (id) => {
    try {
      const data = await loadArtwork(id)
      const work = data.work || data
      setSelectedWork(work)
      setAllWorks(prev => prev.map(item => item.id === work.id ? { ...item, ...work } : item))
    } catch { /* ignore */ }
  }, [])

  const replaceWork = useCallback((work) => {
    if (!work?.id) return
    setAllWorks(prev => prev.map(item => item.id === work.id ? { ...item, ...work } : item))
    setSelectedWork(current => current?.id === work.id ? { ...current, ...work } : current)
  }, [])

  const reloadAll = useCallback(async () => {
    const data = await loadData()
    if (data.works.length && selectedWorkId) {
      selectWork(selectedWorkId)
    }
  }, [loadData, selectWork, selectedWorkId])

  const filteredWorks = useCallback(() => {
    let list = allWorks
    if (currentNav === 'trash') {
      list = list.filter(w => w.deleted_at)
    } else {
      list = list.filter(w => !w.deleted_at)
    }
    if (currentNav === 'unassigned' || currentNav === 'uncategorized') {
      list = list.filter(w => !w.child_id)
    }
    if (currentNav === 'untagged') {
      list = list.filter(w => !w.tags?.length)
    }
    if (currentNav === 'smart' && currentTagFilter) {
      list = list.filter(w =>
        w.tags?.some(t => t.type === currentTagFilter.type && t.name === currentTagFilter.name)
      )
    }
    if (currentChild) {
      list = list.filter(w => w.child_id === currentChild)
    }
    if (searchQuery) {
      const q = searchQuery.toLowerCase()
      list = list.filter(w =>
        (w.title && w.title.toLowerCase().includes(q)) ||
        (w.description && w.description.toLowerCase().includes(q)) ||
        (w.tags && w.tags.some(t => t.name.toLowerCase().includes(q)))
      )
    }
    return list
  }, [allWorks, currentNav, currentTagFilter, currentChild, searchQuery])

  const selectNav = useCallback((nav) => {
    setCurrentNav(nav)
    setCurrentTagFilter(null)
  }, [])

  const selectSmartPortfolio = useCallback((type, name) => {
    setCurrentNav('smart')
    setCurrentTagFilter({ type, name })
  }, [])

  useEffect(() => {
    let cancelled = false
    Promise.resolve()
      .then(loadData)
      .then(data => {
        const firstActive = data.works.find(work => !work.deleted_at) || data.works[0]
        if (!cancelled && firstActive) selectWork(firstActive.id)
      })
    return () => { cancelled = true }
  }, [loadData, selectWork])

  useEffect(() => {
    if (selectedWorkId) return
    const list = filteredWorks()
    if (!list.length) return
    let cancelled = false
    Promise.resolve().then(() => {
      if (!cancelled) selectWork(list[0].id)
    })
    return () => { cancelled = true }
  }, [filteredWorks, selectedWorkId, selectWork])

  useEffect(() => {
    if (!searchQuery) return
    const timer = setTimeout(() => {
      if (!selectedWorkId) {
        const list = filteredWorks()
        if (list.length) selectWork(list[0].id)
      }
    }, 200)
    return () => clearTimeout(timer)
  }, [searchQuery, filteredWorks, selectedWorkId, selectWork])

  useEffect(() => {
    if (!currentChild) return
    if (children.some(child => child.id === currentChild)) return
    const timer = setTimeout(() => {
      setCurrentChild(null)
      setCurrentNav('all')
    }, 0)
    return () => clearTimeout(timer)
  }, [children, currentChild])

  useEffect(() => {
    if (!mobileSession?.token) return
    localStorage.setItem('volioMobileSession', JSON.stringify(mobileSession))
    let cancelled = false
    const validate = async () => {
      if (mobileSession.expiresAt <= Date.now()) {
        if (!cancelled) setMobileSession(null)
        return
      }
      const result = await checkMobileSession(mobileSession.token)
      if (cancelled) return
      if (!result.valid) {
        setMobileSession(null)
        return
      }
      const previousUploads = Number(mobileSession.uploadedCount || 0)
      const nextUploads = Number(result.uploaded_count || 0)
      if (nextUploads > previousUploads) {
        setCurrentChild(null)
        setCurrentTagFilter(null)
        setCurrentNav('all')
        setSearchQuery('')
        const data = await loadData()
        if (!cancelled && data.works.length) selectWork(data.works[0].id)
      }
      setMobileSession(current => current?.token === mobileSession.token
        ? (
            Number(current.uploadedCount || 0) === nextUploads
              && (result.last_upload_at || current.lastUploadAt) === current.lastUploadAt
              && (result.child_name || current.childName) === current.childName
              ? current
              : {
                  ...current,
                  uploadedCount: nextUploads,
                  lastUploadAt: result.last_upload_at || current.lastUploadAt,
                  childName: result.child_name || current.childName,
                }
          )
        : current)
    }
    validate()
    const timer = setInterval(validate, 3000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [mobileSession, loadData, selectWork])

  useEffect(() => {
    if (mobileSession) return
    localStorage.removeItem('volioMobileSession')
  }, [mobileSession])

  useEffect(() => {
    if (iosPairingSession?.token) {
      localStorage.setItem('volioIosPairingSession', JSON.stringify(iosPairingSession))
      return
    }
    localStorage.removeItem('volioIosPairingSession')
  }, [iosPairingSession])

  const hasActiveAI = useMemo(() => (
    allWorks.some(work => work.ai_status === 'pending' || work.ai_status === 'processing')
    || selectedWork?.ai_status === 'pending'
    || selectedWork?.ai_status === 'processing'
  ), [allWorks, selectedWork])

  useEffect(() => {
    if (!hasActiveAI) return
    let cancelled = false
    const refreshAIState = async () => {
      try {
        const [works, facetsData] = await Promise.all([loadArtworks({ includeDeleted: true }), loadFacets()])
        if (cancelled) return
        setAllWorks(works || [])
        setFacets(facetsData || {})
        if (selectedWorkId) {
          const data = await loadArtwork(selectedWorkId)
          if (!cancelled) setSelectedWork(data.work || data)
        }
      } catch { /* keep existing UI state */ }
    }
    const timer = setInterval(refreshAIState, 2000)
    refreshAIState()
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [hasActiveAI, selectedWorkId])

  useEffect(() => {
    let cancelled = false
    const refreshIfChanged = async () => {
      try {
        const state = await loadState()
        if (cancelled) return
        const counts = state?.counts || {}
        const latest = state?.latest || []
        const signature = JSON.stringify({
          counts,
          revision: state?.revision || null,
          latest: latest.map(work => [work.id, work.updated_at, work.ai_status, work.deleted_at]),
        })
        if (!stateSignatureRef.current) {
          stateSignatureRef.current = signature
          return
        }
        if (signature !== stateSignatureRef.current) {
          stateSignatureRef.current = signature
          await reloadAll()
        }
      } catch {
        // Keep the current UI if the local service is temporarily busy.
      }
    }
    const timer = setInterval(refreshIfChanged, 2500)
    refreshIfChanged()
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [reloadAll])

  const ctx = useMemo(() => ({
    allWorks, facets, children,
    currentNav, currentTagFilter, currentChild,
    currentView, selectedWorkId, selectedWork, searchQuery,
    importModalOpen, phoneImportOpen, iosPairingOpen, settingsOpen, lightboxSrc,
    settings, mobileSession, iosPairingSession,
    setCurrentNav, setCurrentChild, setCurrentView,
    setSearchQuery, setImportModalOpen, setPhoneImportOpen,
    setIosPairingOpen,
    setSettingsOpen, setLightboxSrc, setSelectedWorkId,
    setSettings, setChildren, setMobileSession, setIosPairingSession, setSelectedWork,
    replaceWork,
    selectNav, selectSmartPortfolio,
    selectWork, reloadArtwork, reloadAll, filteredWorks,
    toast, t,
  }), [
    allWorks, facets, children,
    currentNav, currentTagFilter, currentChild,
    currentView, selectedWorkId, selectedWork, searchQuery,
    importModalOpen, phoneImportOpen, iosPairingOpen, settingsOpen, lightboxSrc,
    settings, mobileSession, iosPairingSession,
    setCurrentNav, setCurrentChild, setCurrentView,
    setSearchQuery, setImportModalOpen, setPhoneImportOpen,
    setIosPairingOpen,
    setSettingsOpen, setLightboxSrc, setSelectedWorkId,
    setSettings, setChildren, setMobileSession, setIosPairingSession, setSelectedWork,
    replaceWork,
    selectNav, selectSmartPortfolio,
    selectWork, reloadArtwork, reloadAll, filteredWorks,
    toast, t,
  ])

  return (
    <VolioContext.Provider value={ctx}>
      <div className="grid h-dvh min-w-[860px]" style={{ gridTemplateColumns: '240px 1fr 420px' }}>
        <Sidebar />
        <MainPane />
        <DetailPane />
      </div>

      <ImportModal />
      <PhoneImportModal />
      <IosPairingModal />
      <SettingsModal />
      <Lightbox />

      <div id="app-toast" hidden
        className="fixed right-5 bottom-5 z-50 max-w-[340px] rounded-xl bg-[#1d1d1f] text-white px-4 py-3 text-sm leading-tight shadow-xl"
      />
    </VolioContext.Provider>
  )
}
