import { useState, useEffect, useRef } from 'react'
import { useVolio } from '../VolioContext'
import { getQueueStatus, pauseQueue, resumeQueue, processNow } from '../api'

function Icon({ name }) {
  const common = { width: 15, height: 15, viewBox: '0 0 16 16', fill: 'none', className: 'shrink-0' }
  if (name === 'all') return (
    <svg {...common}><rect x="2.5" y="2.5" width="4.2" height="4.2" rx="1" stroke="currentColor" strokeWidth="1.35"/><rect x="9.3" y="2.5" width="4.2" height="4.2" rx="1" stroke="currentColor" strokeWidth="1.35"/><rect x="2.5" y="9.3" width="4.2" height="4.2" rx="1" stroke="currentColor" strokeWidth="1.35"/><rect x="9.3" y="9.3" width="4.2" height="4.2" rx="1" stroke="currentColor" strokeWidth="1.35"/></svg>
  )
  if (name === 'unassigned') return (
    <svg {...common}><path d="M2.2 5.2h11.6M4.1 2.8h3.3l1.3 1.4h3.2c.8 0 1.4.6 1.4 1.4v6.2c0 .8-.6 1.4-1.4 1.4H4.1c-.8 0-1.4-.6-1.4-1.4V4.2c0-.8.6-1.4 1.4-1.4Z" stroke="currentColor" strokeWidth="1.35" strokeLinejoin="round"/></svg>
  )
  if (name === 'untagged') return (
    <svg {...common}><path d="M2.8 4.1v3.1c0 .4.2.8.5 1.1l4.4 4.4c.5.5 1.3.5 1.8 0l3.2-3.2c.5-.5.5-1.3 0-1.8L8.3 3.3c-.3-.3-.7-.5-1.1-.5H4.1c-.7 0-1.3.6-1.3 1.3Z" stroke="currentColor" strokeWidth="1.35" strokeLinejoin="round"/><circle cx="5.4" cy="5.4" r=".8" fill="currentColor"/><path d="M11.8 3.2 3.2 11.8" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round"/></svg>
  )
  if (name === 'trash') return (
    <svg {...common}><path d="M2.8 4.4h10.4M6.1 2.6h3.8M4.2 4.4l.5 8.2c.1.7.6 1.2 1.3 1.2h4c.7 0 1.3-.5 1.3-1.2l.5-8.2M6.6 6.8v4.5M9.4 6.8v4.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/></svg>
  )
  if (name === 'person') return (
    <svg {...common}><circle cx="8" cy="5" r="2.2" stroke="currentColor" strokeWidth="1.35"/><path d="M3.8 13.1c.7-2 2.2-3.2 4.2-3.2s3.5 1.2 4.2 3.2" stroke="currentColor" strokeWidth="1.35" strokeLinecap="round"/></svg>
  )
  return (
    <svg {...common}><path d="M3 8h10M8 3v10" stroke="currentColor" strokeWidth="1.35" strokeLinecap="round"/></svg>
  )
}

function NavItem({ label, count, active, onClick, icon, indent }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        'w-full flex items-center gap-2 py-2 text-sm rounded-lg transition-all duration-150 cursor-pointer ' +
        (indent ? 'pl-3 pr-3 ' : 'px-3 ') +
        (active
          ? 'bg-[#e8f2ff] text-[#007aff] font-semibold'
          : 'text-[#6e6e73] hover:bg-[#e5e5e5]/60')
      }
    >
      {icon && <Icon name={icon} />}
      <span className="truncate">{label}</span>
      {count != null && <span className="ml-auto text-xs text-[#a1a1a6]">{count}</span>}
    </button>
  )
}

function SectionLabel({ label }) {
  return (
    <div className="text-[11px] font-semibold text-[#9a9aa1] uppercase tracking-[0.06em] px-3 pt-4 pb-1.5">
      {label}
    </div>
  )
}

function RailGroup({ children }) {
  return (
    <div className="rail-group relative ml-3 space-y-0.5 pl-4">
      {children}
    </div>
  )
}

export default function Sidebar() {
  const {
    facets, children, currentChild, currentNav, currentTagFilter,
    selectNav, selectSmartPortfolio, setCurrentChild,
    setImportModalOpen, setPhoneImportOpen, setIosPairingOpen, setSettingsOpen,
    reloadAll,
    mobileSession, iosPairingSession,
    t,
  } = useVolio()

  const [queue, setQueue] = useState({ pending: 0, processing: 0, paused: false, can_process: true, worker_active: false })
  const [manualRun, setManualRun] = useState(false)
  const [progress, setProgress] = useState(0)
  const polling = useRef(null)
  const progressTimer = useRef(null)

  useEffect(() => {
    const fetchQueue = async () => {
      try {
        const data = await getQueueStatus()
        setQueue(data)
      } catch { /* ignore */ }
    }
    fetchQueue()
    polling.current = setInterval(fetchQueue, 1800)
    return () => clearInterval(polling.current)
  }, [])

  useEffect(() => {
    return () => clearInterval(progressTimer.current)
  }, [])

  const handlePauseResume = async () => {
    try {
      if (queue.paused) await resumeQueue()
      else await pauseQueue()
      const data = await getQueueStatus()
      setQueue(data)
    } catch { /* ignore */ }
  }

  const handleProcessNow = async () => {
    try {
      setManualRun(true)
      setProgress(8)
      clearInterval(progressTimer.current)
      progressTimer.current = setInterval(() => {
        setProgress(current => Math.min(current + 9, 86))
      }, 350)
      await processNow()
      const data = await getQueueStatus()
      setQueue(data)
      await reloadAll()
      if (!data.pending && !data.processing && !data.worker_active) {
        clearInterval(progressTimer.current)
        setProgress(100)
        setTimeout(() => {
          setManualRun(false)
          setProgress(0)
        }, 1200)
      }
    } catch {
      clearInterval(progressTimer.current)
      setManualRun(false)
      setProgress(0)
    }
  }

  useEffect(() => {
    const totalItems = Number(queue.pending || 0) + Number(queue.processing || 0)
    if (!manualRun && !queue.worker_active) return
    if (totalItems > 0 || queue.worker_active) return
    clearInterval(progressTimer.current)
    const progressDoneTimer = setTimeout(() => setProgress(100), 0)
    const timer = setTimeout(() => {
      setManualRun(false)
      setProgress(0)
    }, 1200)
    return () => {
      clearTimeout(progressDoneTimer)
      clearTimeout(timer)
    }
  }, [manualRun, queue.pending, queue.processing, queue.worker_active])

  const total = Number(queue.pending || 0) + Number(queue.processing || 0)
  const tagGroups = facets?.tags
  const smartItems = facets?.smart || []
  const countFor = id => smartItems.find(item => item.id === id)?.count
  const statusLabel = queue.paused ? t('paused') : total > 0 || queue.worker_active || manualRun ? t('working') : t('ready')
  const progressValue = manualRun ? progress : total > 0 || queue.worker_active ? 58 : 0
  const phoneConnected = Boolean(mobileSession?.token)
  const iosConnected = Boolean(iosPairingSession?.token)
  const topItems = [
    ['all', t('all'), 'all', true],
    ['unassigned', t('unassigned'), 'unassigned', Number(countFor('unassigned') || 0) > 0],
    ['untagged', t('untagged'), 'untagged', Number(countFor('untagged') || 0) > 0],
    ['trash', t('trash'), 'trash', true],
  ].filter(item => item[3])

  return (
    <aside className="bg-white border-r border-[#e5e5e5] flex flex-col overflow-hidden select-none text-sm">
      <div className="flex items-center gap-2.5 px-5 pt-5 pb-3 shrink-0">
        <div className="size-9 rounded-xl bg-[#007aff] text-white grid place-items-center font-bold shadow-sm">
          V
        </div>
        <span className="font-sans text-xl font-bold text-[#1d1d1f] tracking-tight">Volio Desktop</span>
      </div>

      <div className="px-3 pb-3 shrink-0 space-y-1.5 border-b border-[#e5e5e5]">
        <button
          type="button"
          onClick={() => setImportModalOpen(true)}
          className="w-full flex items-center gap-2.5 px-3 py-2.5 text-sm font-semibold text-white bg-[#007aff] rounded-xl hover:bg-[#0062cc] transition-colors cursor-pointer border-0"
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="shrink-0">
            <path d="M7 1v12M1 7h12" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
          </svg>
          {t('newPhotos')}
        </button>
        <button
          type="button"
          onClick={() => setPhoneImportOpen(true)}
          className={
            'w-full flex items-center gap-2.5 px-3 py-2.5 text-sm font-medium rounded-xl transition-colors cursor-pointer border-0 ' +
            (phoneConnected
              ? 'text-[#248a3d] bg-[#ecf8f0] hover:bg-[#dff3e7]'
              : 'text-[#5f5f66] bg-[#f5f5f7] hover:bg-[#e5e5e5]')
          }
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="shrink-0">
            <rect x="3" y="0.5" width="8" height="13" rx="1.5" stroke="currentColor" strokeWidth="1.2"/>
            <circle cx="7" cy="11" r="1" fill="currentColor"/>
          </svg>
          {phoneConnected ? t('phoneConnected') : t('phoneImport')}
        </button>
        <button
          type="button"
          onClick={() => setIosPairingOpen(true)}
          className={
            'w-full flex items-center gap-2.5 px-3 py-2.5 text-sm font-medium rounded-xl transition-colors cursor-pointer border-0 ' +
            (iosConnected
              ? 'text-[#248a3d] bg-[#ecf8f0] hover:bg-[#dff3e7]'
              : 'text-[#5f5f66] bg-[#f5f5f7] hover:bg-[#e5e5e5]')
          }
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="shrink-0">
            <path d="M2.5 2.5h3v3h-3v-3ZM8.5 2.5h3v3h-3v-3ZM2.5 8.5h3v3h-3v-3ZM8.5 8.5h1.6v1.6H8.5V8.5ZM10.7 10.7h.8v.8h-.8v-.8Z" stroke="currentColor" strokeWidth="1.1" strokeLinejoin="round"/>
          </svg>
          {iosConnected ? t('iphonePaired') : t('connectIphone')}
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 pb-2 pt-1.5 space-y-0.5">
        {topItems.map(([id, label, icon]) => (
          <NavItem
            key={id}
            label={label}
            icon={icon}
            count={countFor(id)}
            active={currentNav === id && !currentChild && !currentTagFilter}
            onClick={() => { selectNav(id); setCurrentChild(null) }}
          />
        ))}

        {children.length > 0 && (
          <div>
            <SectionLabel label={t('people')} />
            <RailGroup>
              {children.map(c => (
                <NavItem
                  key={c.id}
                  label={c.name}
                  icon="person"
                  count={c.count}
                  active={currentChild === c.id}
                  onClick={() => { selectNav('all'); setCurrentChild(c.id) }}
                  indent
                />
              ))}
            </RailGroup>
          </div>
        )}

        {tagGroups && Object.entries(tagGroups)
          .filter(([, tags]) => tags?.filter(Boolean).length)
          .map(([type, tags]) => (
          <div key={type}>
            <SectionLabel label={type} />
            <RailGroup>
              {tags.filter(Boolean).map((t, i) => {
                const name = t.name || t.tag || t
                const isActive = currentNav === 'smart'
                  && currentTagFilter?.type === type
                  && currentTagFilter?.name === name
                return (
                  <NavItem
                    key={name + i}
                    label={name}
                    count={t.count}
                    active={isActive}
                    onClick={() => selectSmartPortfolio(type, name)}
                    indent
                  />
                )
              })}
            </RailGroup>
          </div>
        ))}
      </nav>

      <div className="shrink-0 border-t border-[#e5e5e5] px-3 py-2.5 bg-[#fbfbfc]">
        <button
          type="button"
          onClick={() => setSettingsOpen(true)}
          className="mb-2 flex w-full cursor-pointer items-center gap-2.5 rounded-xl border border-[#e7e7eb] bg-white px-3 py-2 text-sm font-semibold text-[#5f5f66] shadow-[0_1px_2px_rgba(0,0,0,0.025)] transition-colors hover:bg-[#f5f5f7]"
        >
          <svg width="15" height="15" viewBox="0 0 16 16" fill="none" className="shrink-0">
            <path d="M6.9 1.5h2.2l.4 1.7c.4.1.8.3 1.2.5l1.5-.9 1.6 1.6-.9 1.5c.2.4.4.8.5 1.2l1.6.4v2.2l-1.6.4c-.1.4-.3.8-.5 1.2l.9 1.5-1.6 1.6-1.5-.9c-.4.2-.8.4-1.2.5l-.4 1.7H6.9l-.4-1.7c-.4-.1-.8-.3-1.2-.5l-1.5.9-1.6-1.6.9-1.5c-.2-.4-.4-.8-.5-1.2L1 9.7V7.5l1.6-.4c.1-.4.3-.8.5-1.2l-.9-1.5 1.6-1.6 1.5.9c.4-.2.8-.4 1.2-.5l.4-1.7Z" stroke="currentColor" strokeWidth="1.15" strokeLinejoin="round"/>
            <circle cx="8" cy="8.6" r="2.1" stroke="currentColor" strokeWidth="1.15"/>
          </svg>
          {t('settings')}
        </button>
        <div className="rounded-xl border border-[#e7e7eb] bg-white p-2.5 shadow-[0_1px_2px_rgba(0,0,0,0.035)]">
          <div className="flex items-center gap-2">
            <div className={
              'shrink-0 size-7 rounded-full grid place-items-center ' +
              (queue.paused
                ? 'bg-[#fff4de] text-[#b86b00]'
                : total > 0 || manualRun
                  ? 'bg-[#e8f2ff] text-[#007aff]'
                  : 'bg-[#ecf8f0] text-[#248a3d]')
            }>
              <span className={total > 0 || manualRun ? 'size-2 rounded-full bg-current animate-pulse' : 'size-2 rounded-full bg-current'} />
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <div className="text-[10px] font-semibold text-[#9a9aa1] uppercase tracking-[0.06em]">
                  {t('aiProcessing')}
                </div>
                <div className="text-[11px] text-[#8e8e93]">
                  {t('runningCount', { count: queue.processing })} · {t('waitingCount', { count: queue.pending })}
                </div>
              </div>
              <div className="mt-0.5 text-sm font-semibold text-[#1d1d1f]">{statusLabel}</div>
            </div>
          </div>

          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-[#ececf0]">
            <div
              className="h-full rounded-full bg-[#007aff] transition-all duration-300"
              style={{ width: `${progressValue}%` }}
            />
          </div>

          {!queue.can_process && !queue.paused && (
            <div className="mt-2 rounded-lg bg-[#fff4de] px-2.5 py-1.5 text-[11px] leading-relaxed text-[#8a5a00]">
              {t('waitingWindow')}
            </div>
          )}

          <div className="mt-2 flex gap-2">
            <button
              type="button"
              onClick={handlePauseResume}
              className="flex-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-[#e5e5e5] text-[#5f5f66] bg-white hover:bg-[#f5f5f7] transition-colors cursor-pointer"
            >
              {queue.paused ? t('resume') : t('pause')}
            </button>
            <button
              type="button"
              onClick={handleProcessNow}
              disabled={!queue.can_process || manualRun}
              className="flex-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-[#007aff]/20 text-[#007aff] bg-[#f2f8ff] hover:bg-[#e8f2ff] transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {t('runNow')}
            </button>
          </div>
        </div>
      </div>
    </aside>
  )
}
