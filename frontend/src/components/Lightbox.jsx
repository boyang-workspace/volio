import { useEffect, useMemo, useState } from 'react'
import { useVolio } from '../VolioContext'

export default function Lightbox() {
  const { lightboxSrc, setLightboxSrc, selectedWork, t } = useVolio()
  const open = !!lightboxSrc
  const work = selectedWork
  const [mode, setMode] = useState('display')

  useEffect(() => {
    if (!open) return
    const timer = setTimeout(() => setMode('display'), 0)
    return () => clearTimeout(timer)
  }, [open, work?.id])

  useEffect(() => {
    if (!open) return
    const handler = event => {
      if (event.key === 'Escape') setLightboxSrc(null)
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [open, setLightboxSrc])

  const src = useMemo(() => {
    if (!work) return typeof lightboxSrc === 'string' ? lightboxSrc : lightboxSrc?.src
    if (mode === 'original') return work.original_url
    return work.display_url || work.processed_url || work.original_url
  }, [lightboxSrc, mode, work])

  if (!open) return null

  return (
    <div className="fixed inset-0 z-[60] flex flex-col bg-[#171717]/90 backdrop-blur-md">
      <div className="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-white/10 px-4 text-white">
        <div className="min-w-0 truncate text-sm font-semibold">{work?.title || ''}</div>
        <div className="flex items-center gap-2">
          {work?.processed_url && (
            <div className="flex overflow-hidden rounded-xl bg-white/10 p-0.5">
              <button
                type="button"
                onClick={() => setMode('display')}
                className={'rounded-[10px] px-3 py-1.5 text-xs font-semibold ' + (mode === 'display' ? 'bg-white text-[#1d1d1f]' : 'text-white/75 hover:text-white')}
              >
                {t('processed')}
              </button>
              <button
                type="button"
                onClick={() => setMode('original')}
                className={'rounded-[10px] px-3 py-1.5 text-xs font-semibold ' + (mode === 'original' ? 'bg-white text-[#1d1d1f]' : 'text-white/75 hover:text-white')}
              >
                {t('original')}
              </button>
            </div>
          )}
          <button
            type="button"
            onClick={() => setLightboxSrc(null)}
            className="grid size-8 cursor-pointer place-items-center rounded-full border border-white/15 bg-white/10 text-sm text-white transition-all hover:bg-white/20"
          >
            x
          </button>
        </div>
      </div>

      <div className="flex min-h-0 flex-1 items-center justify-center px-6 py-5">
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
