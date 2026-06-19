import { memo } from 'react'
import { useVolio } from '../VolioContext'

function WorkCard({ work, isSelected, onSelect, square }) {
  const { t } = useVolio()
  const path = work.original_url || work.path || work.thumbnail_url || work.thumbnail || work.display_url || ''
  const title = work.title || 'Untitled'
  const needsAI = work.ai_status !== 'completed' || (!work.description && !work.long_description)
  const failed = work.ai_status === 'failed'
  const processing = work.ai_status === 'processing'
  const pending = work.ai_status === 'pending'
  const badgeLabel = failed ? t('failed') : processing ? t('processing') : pending ? t('queued') : t('needsAI')

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => onSelect(work.id)}
      onKeyDown={e => e.key === 'Enter' && onSelect(work.id)}
      className={
        'group relative rounded-2xl overflow-hidden cursor-pointer border-2 transition-all duration-200 ' +
        (square ? 'aspect-square ' : '') +
        (isSelected
          ? 'border-[#007aff] shadow-[0_0_0_3px_rgba(0,122,255,0.15),0_4px_16px_rgba(0,122,255,0.1)]'
          : 'border-[#e5e5e5] hover:border-[#d4d4d4] hover:shadow-md')
      }
    >
      <div className={'overflow-hidden bg-[#f0f0f0] ' + (square ? 'size-full' : '')}>
        <img
          className={'block w-full transition-transform duration-500 ease-out group-hover:scale-105 ' + (square ? 'h-full object-cover' : '')}
          src={path}
          alt={title}
          loading="lazy"
        />
      </div>
      {needsAI && (
        <div
          className={
            'absolute right-2 top-2 rounded-full px-2 py-1 text-[10px] font-bold leading-none shadow-sm backdrop-blur ' +
            (failed
              ? 'bg-[#ff4b43] text-white'
              : processing
                ? 'bg-[#007aff] text-white'
              : 'bg-[#fff4de]/95 text-[#9a6300] border border-[#f1cf85]')
          }
        >
          {badgeLabel}
        </div>
      )}
    </div>
  )
}

export default memo(WorkCard)
