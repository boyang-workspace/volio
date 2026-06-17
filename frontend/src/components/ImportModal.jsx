import { useMemo, useState, useRef } from 'react'
import { useVolio } from '../VolioContext'
import { importPhoto } from '../api'

const COLORS = ['#007aff', '#34c759', '#ff9500', '#ff3b30', '#af52de', '#5ac8fa']

function seededUnit(index, salt) {
  const value = Math.sin(index * 78.233 + salt * 37.719) * 43758.5453
  return value - Math.floor(value)
}

function Confetti() {
  const pieces = useMemo(() => (
    Array.from({ length: 40 }, (_, i) => ({
      id: i,
      color: COLORS[i % COLORS.length],
      left: seededUnit(i, 1) * 100,
      delay: seededUnit(i, 2) * 0.4,
      dur: 0.6 + seededUnit(i, 3) * 0.8,
      size: 5 + seededUnit(i, 4) * 7,
      rot: seededUnit(i, 5) * 360,
    }))
  ), [])

  return (
    <div className="fixed inset-0 pointer-events-none z-[100] overflow-hidden">
      {pieces.map(p => (<div
          key={p.id}
          className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
          style={{
            '--color': p.color,
            '--left': `${p.left}%`,
            '--dur': `${p.dur}s`,
            '--delay': `${p.delay}s`,
            '--size': `${p.size}px`,
            '--rot': `${p.rot}deg`,
          }}
        >
          <div
            className="w-[var(--size)] h-[var(--size)] rounded-sm animate-[confetti-fall_var(--dur)_var(--delay)_ease-out_both]"
            style={{ backgroundColor: p.color, transform: `rotate(${p.rot}deg)` }}
          />
        </div>
      ))}
    </div>
  )
}

export default function ImportModal() {
  const { importModalOpen, setImportModalOpen, reloadAll, toast, children, t } = useVolio()
  const [selectedChildId, setSelectedChildId] = useState('')
  const [childName, setChildName] = useState('')
  const [importing, setImporting] = useState(false)
  const [showConfetti, setShowConfetti] = useState(false)
  const fileRef = useRef(null)

  const handleSubmit = async e => {
    e.preventDefault()
    const effectiveChildId = selectedChildId || children[0]?.id || ''
    const selectedChild = children.find(c => c.id === effectiveChildId)
    const cleanChildName = (selectedChild?.name || childName).trim()
    if (!cleanChildName) return toast(t('enterChildName'))
    const files = fileRef.current?.files
    if (!files || !files.length) return toast(t('selectFiles'))
    setImporting(true)
    let imported = 0
    let failed = 0
    for (const f of files) {
      try {
        const res = await importPhoto(cleanChildName, f)
        if (!res.ok) throw new Error((await res.json()).detail || 'Import failed')
        imported++
      } catch (err) {
        failed++
        console.error('Import error', f.name, err)
      }
    }
    setImporting(false)
    if (imported > 0) {
      setShowConfetti(true)
      setTimeout(() => setShowConfetti(false), 1800)
      toast(failed ? `${imported} imported, ${failed} failed` : `${imported} photo(s) imported`)
      setTimeout(() => {
        setImportModalOpen(false)
        reloadAll()
      }, 800)
    } else {
      toast(t('importFailed'))
    }
  }

  if (!importModalOpen) return null
  const hasChildren = children.length > 0
  const addingNewChild = !hasChildren || selectedChildId === '__new__'

  return (
    <>
      <div className="fixed inset-0 z-[70] flex items-center justify-center" onClick={() => setImportModalOpen(false)}>
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm -z-10" />
        <div
          className="relative w-full max-w-md bg-white rounded-2xl shadow-2xl border border-[#e5e5e5] overflow-hidden"
          onClick={e => e.stopPropagation()}
        >
          <div className="px-5 pt-5 pb-2 flex items-center justify-between">
            <h2 className="font-sans text-lg font-bold text-[#1d1d1f]">{t('importPhotos')}</h2>
            <button
              type="button"
              onClick={() => setImportModalOpen(false)}
              className="size-7 rounded-full bg-[#f5f5f7] text-[#6e6e73] border-0 cursor-pointer grid place-items-center text-xs hover:bg-[#e5e5e5] transition-colors"
            >
              ✕
            </button>
          </div>
          <form onSubmit={handleSubmit} className="px-5 pb-5 space-y-4">
            {hasChildren && (
              <label className="grid gap-1.5 text-sm font-semibold text-[#4a4a4f]">
                {t('child')}
                <select
                  autoFocus
                  value={selectedChildId || children[0]?.id || ''}
                  onChange={e => setSelectedChildId(e.target.value)}
                  className="h-10 rounded-xl border border-[#d9d9de] bg-white px-3 text-sm font-normal text-[#1d1d1f] outline-none transition focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
                >
                  {children.map(child => (
                    <option key={child.id} value={child.id}>{child.name}</option>
                  ))}
                  <option value="__new__">{t('addNewChild')}</option>
                </select>
              </label>
            )}
            {addingNewChild && (
              <label className="grid gap-1.5 text-sm font-semibold text-[#4a4a4f]">
                {t('childName')}
                <input
                  autoFocus={!hasChildren}
                  value={childName}
                  onChange={e => setChildName(e.target.value)}
                  placeholder="Emma"
                  className="h-10 rounded-xl border border-[#d9d9de] bg-white px-3 text-sm font-normal text-[#1d1d1f] outline-none transition focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
                />
              </label>
            )}
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              multiple
              className="block w-full text-sm text-[#a1a1a6] file:mr-3 file:py-1.5 file:px-3 file:rounded-xl file:border file:border-[#e5e5e5] file:text-xs file:font-medium file:bg-white hover:file:bg-[#f5f5f7] file:cursor-pointer cursor-pointer file:transition-colors"
            />
            <div className="flex justify-end">
              <button
                type="submit"
                disabled={importing}
                className="px-4 py-2 text-sm font-semibold text-white bg-[#007aff] rounded-xl hover:bg-[#0062cc] disabled:opacity-50 transition-colors cursor-pointer border-0"
              >
                {importing ? t('importing') : t('import')}
              </button>
            </div>
          </form>
        </div>
      </div>
      {showConfetti && <Confetti />}
    </>
  )
}
