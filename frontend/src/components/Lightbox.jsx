import { useEffect } from 'react'
import { useVolio } from '../VolioContext'

export default function Lightbox() {
  const { lightboxSrc, setLightboxSrc, selectedWork, t } = useVolio()
  const open = !!lightboxSrc
  const work = selectedWork

  const src = !work
    ? (typeof lightboxSrc === 'string' ? lightboxSrc : lightboxSrc?.src)
    : (work.original_url || work.display_url || '')

  useEffect(() => {
    if (!open) return
    const handler = event => {
      if (event.key === 'Escape') setLightboxSrc(null)
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [open, setLightboxSrc])

  if (!open) return null

  return (
    <div className="fixed inset-0 z-[60] flex flex-col bg-[#171717]/90 backdrop-blur-md pt-[38px]">
      <div className="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-white/10 px-4 text-white [-webkit-app-region:no-drag]">
        <div className="min-w-0 truncate text-sm font-semibold">{work?.title || ''}</div>
        <button
          type="button"
          onClick={() => setLightboxSrc(null)}
          className="grid size-8 cursor-pointer place-items-center rounded-full border border-white/15 bg-white/10 text-sm text-white transition-all hover:bg-white/20"
        >
          x
        </button>
      </div>

      <div className="flex min-h-0 flex-1 items-center justify-center px-6 py-5 [-webkit-app-region:no-drag]">
        <img
          className="block max-h-[calc(100vh-112px)] max-w-[94vw] select-none rounded-2xl object-contain shadow-2xl"
          src={src}
          alt={work?.title || ''}
          draggable={false}
        />
      </div>

      <div className="flex h-10 shrink-0 items-center justify-center px-4 pb-4 text-xs font-semibold text-white/60">
        {t('lightboxHint')}
      </div>
    </div>
  )
}
