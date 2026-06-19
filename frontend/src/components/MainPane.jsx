import WorkCard from './WorkCard'
import { useVolio } from '../VolioContext'

function Toolbar() {
  const { searchQuery, setSearchQuery, currentView, setCurrentView, t } = useVolio()

  return (
    <div className="flex items-center gap-3 px-6 h-16 border-b border-[#e5e5e5] shrink-0 bg-[#f5f5f7]/80 backdrop-blur-sm [-webkit-app-region:drag]">
      <div className="flex-1 min-w-0">
        <input
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          placeholder={t('search')}
          className="h-8 w-full max-w-xs rounded-lg border border-[#d9d9de] bg-white px-3 text-sm text-[#1d1d1f] outline-none transition placeholder:text-[#a1a1a6] focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10 [-webkit-app-region:no-drag]"
        />
      </div>
      <div className="flex gap-0.5 shrink-0 rounded-lg overflow-hidden bg-[#e5e5e5]/50 p-0.5 [-webkit-app-region:no-drag]">
        {(['masonry', 'timeline']).map(v => (
          <button
            key={v}
            onClick={() => setCurrentView(v)}
            className={
              'h-7 px-2.5 text-[11px] font-medium rounded-[8px] border-0 transition-all duration-150 capitalize cursor-pointer ' +
              (currentView === v
                ? 'bg-white text-[#1d1d1f] shadow-sm font-semibold'
                : 'bg-transparent text-[#a1a1a6] hover:text-[#6e6e73]')
            }
          >
            {v === 'masonry' ? t('masonry') : t('timeline')}
          </button>
        ))}
      </div>
    </div>
  )
}

function EmptyState() {
  const { t } = useVolio()
  return (
    <div className="flex-1 flex items-center justify-center text-[#a1a1a6]">
      <div className="text-center">
        <div className="text-5xl mb-3 opacity-40">&#x1F3A8;</div>
        <p className="font-sans text-lg text-[#6e6e73]">{t('noArtworks')}</p>
        <p className="text-xs mt-1">{t('tryDifferentFilter')}</p>
      </div>
    </div>
  )
}

function toColumnMajor(arr, cols) {
  const n = arr.length
  const fullRows = Math.floor(n / cols)
  const remainder = n % cols
  const result = []
  for (let col = 0; col < cols; col++) {
    const rows = col < remainder ? fullRows + 1 : fullRows
    for (let row = 0; row < rows; row++) {
      result.push(arr[row * cols + col])
    }
  }
  return result
}

function WorksMasonry({ list, selectedWorkId, onSelect }) {
  const sorted = [...list].sort((a, b) => {
    const da = a.artwork_date || a.captured_at || a.created_at || ''
    const db = b.artwork_date || b.captured_at || b.created_at || ''
    return da > db ? -1 : da < db ? 1 : 0
  })

  const cols = 4

  return (
    <div className="columns-4 gap-4">
      {toColumnMajor(sorted, cols).map((w) => (
        <div key={w.id} className="break-inside-avoid mb-4">
          <WorkCard
            work={w}
            isSelected={w.id === selectedWorkId}
            onSelect={onSelect}
          />
        </div>
      ))}
    </div>
  )
}

function WorksTimeline({ list, selectedWorkId, onSelect }) {
  const groups = {}
  for (const w of list) {
    const key = (w.artwork_date || w.created_at || '').slice(0, 10) || 'No date'
    if (!groups[key]) groups[key] = []
    groups[key].push(w)
  }
  const sorted = Object.entries(groups).sort((a, b) => b[0].localeCompare(a[0]))

  return (
    <div className="relative">
      {sorted.map(([date, works]) => (
        <div key={date} className="grid grid-cols-[112px_28px_1fr] gap-3">
          <div className="pt-1 text-right text-sm font-semibold text-[#9a9aa1] leading-5">{date}</div>
          <div className="tl-track flex justify-center pt-[7px]">
            <div className="relative z-10 size-3 rounded-full bg-[#007aff] tl-line-dot" />
          </div>
          <div className="min-w-0 pb-7">
            <div className="text-sm text-[#a1a1a6] mb-3 font-semibold leading-5">
              {works.length} work{works.length > 1 ? 's' : ''}
            </div>
            <div className="grid gap-4" style={{ gridTemplateColumns: 'repeat(4, 1fr)' }}>
              {works.map((w) => (
                <WorkCard
                  key={w.id}
                  work={w}
                  isSelected={w.id === selectedWorkId}
                  onSelect={onSelect}
                  square
                />
              ))}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}

export default function MainPane() {
  const { filteredWorks, selectedWorkId, selectWork, currentView } = useVolio()
  const list = filteredWorks()

  const handlePointerDown = (e) => {
    if (e.target === e.currentTarget || e.target.closest('section')) {
      document.activeElement?.blur()
    }
  }

  return (
    <section className="min-w-0 overflow-hidden flex flex-col bg-white" onPointerDown={handlePointerDown}>
      <Toolbar />
      <div className="flex-1 overflow-y-auto px-6 py-5">
        {list.length === 0 ? <EmptyState /> : (
          currentView === 'timeline'
            ? <WorksTimeline list={list} selectedWorkId={selectedWorkId} onSelect={selectWork} />
            : <WorksMasonry list={list} selectedWorkId={selectedWorkId} onSelect={selectWork} />
        )}
      </div>
    </section>
  )
}
