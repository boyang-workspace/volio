import { useEffect, useState } from 'react'
import { useVolio } from '../VolioContext'
import { updateArtwork, deleteArtwork, restoreArtwork, removeTag, analyzeArtwork } from '../api'

function SectionTitle({ children }) {
  return (
    <div className="text-[10px] font-semibold text-[#9a9aa1] uppercase tracking-[0.06em] mb-2">
      {children}
    </div>
  )
}

function InfoRow({ label, value }) {
  const { t } = useVolio()
  return (
    <div className="grid grid-cols-[92px_1fr] gap-3 py-2 border-b border-[#f0f0f2] last:border-b-0">
      <div className="text-xs font-medium text-[#8e8e93]">{label}</div>
      <div className="min-w-0 text-xs text-[#1d1d1f] leading-relaxed break-words">
        {value || <span className="text-[#b8b8bd]">{t('notSet')}</span>}
      </div>
    </div>
  )
}

function AIStatusPill({ work }) {
  const state = work?.ai_status || 'pending'
  const hasContent = Boolean((work?.description || '').trim() || (work?.long_description || '').trim())
  const complete = state === 'completed' && hasContent
  const processing = state === 'processing' || state === 'pending'
  const failed = state === 'failed'

  if (complete) {
    return (
      <span className="inline-flex h-6 shrink-0 items-center gap-1.5 rounded-full border border-[#cdeed7] bg-[#effaf2] px-2 text-[11px] font-semibold text-[#248a3d]">
        <span className="grid size-3.5 place-items-center rounded-full bg-[#34c759] text-[9px] leading-none text-white">✓</span>
        AI
      </span>
    )
  }

  if (processing) {
    return (
      <span className="inline-flex h-6 shrink-0 items-center gap-1.5 rounded-full border border-[#e6e6ea] bg-[#f6f6f7] px-2 text-[11px] font-semibold text-[#8e8e93]">
        <span className="ai-ring size-3.5 rounded-full" />
        AI
      </span>
    )
  }

  return (
    <span className={'inline-flex h-6 shrink-0 items-center gap-1.5 rounded-full border px-2 text-[11px] font-semibold ' + (failed ? 'border-[#ffd8d6] bg-[#fff7f6] text-[#d1433c]' : 'border-[#e6e6ea] bg-[#f6f6f7] text-[#b0b0b6]')}>
      <span className={'size-2 rounded-full ' + (failed ? 'bg-[#ff4b43]' : 'bg-[#d1d1d6]')} />
      AI
    </span>
  )
}

export default function DetailPane() {
  const {
    selectedWork, selectWork, reloadArtwork, reloadAll,
    setLightboxSrc, setSelectedWork, replaceWork, toast,
    children, t,
  } = useVolio()
  const [descriptionDraft, setDescriptionDraft] = useState('')
  const [longDescriptionDraft, setLongDescriptionDraft] = useState('')
  const [saving, setSaving] = useState(false)
  const [runningAI, setRunningAI] = useState(false)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const w = selectedWork

  useEffect(() => {
    const timer = setTimeout(() => {
      setDescriptionDraft(w?.description || '')
      setLongDescriptionDraft(w?.long_description || '')
    }, 0)
    return () => clearTimeout(timer)
  }, [w?.id, w?.description, w?.long_description])

  if (!w) {
    return (
      <aside className="border-l border-[#e5e5e5] bg-white overflow-hidden flex flex-col">
        <div className="flex-1 flex items-center justify-center text-[#a1a1a6] text-xs font-sans italic">
          {t('selectArtwork')}
        </div>
      </aside>
    )
  }

  const path = w.display_url || w.processed_url || w.original_url || w.source || w.path || ''
  const title = w.title || 'Untitled'
  const date = w.artwork_date || ''
  const child = w.child_name || t('unassigned')
  const tags = w.tags || []

  const handleDelete = async () => {
    if (!confirm('Move this artwork to Trash?')) return
    try {
      await deleteArtwork(w.id)
      toast('Moved to Trash')
      selectWork(null)
      reloadAll()
    } catch { toast('Failed to delete') }
  }

  const handleRestore = async () => {
    try {
      await restoreArtwork(w.id)
      toast('Restored')
      selectWork(null)
      reloadAll()
    } catch { toast('Failed to restore') }
  }

  const handleRemoveTag = (name, type) => {
    removeTag(w.id, name, type)
      .then(async () => {
        toast('Tag removed')
        await reloadArtwork(w.id)
        await reloadAll()
      })
      .catch(() => toast('Failed to remove tag'))
  }

  const metaParts = [date, child].filter(Boolean)
  const dimensions = w.width && w.height ? `${w.width} x ${w.height}` : ''
  const createdAt = w.created_at ? new Date(w.created_at).toLocaleString() : ''
  const updatedAt = w.updated_at ? new Date(w.updated_at).toLocaleString() : ''
  const aiStatus = [w.ai_status, w.ai_model].filter(Boolean).join(' · ')
  const aiState = w.ai_status || 'pending'
  const aiStateLabel = aiState === 'completed'
    ? t('completed')
    : aiState === 'processing'
      ? t('processing')
      : aiState === 'failed'
        ? t('failed')
        : t('needsAI')
  const hasChanges = descriptionDraft !== (w.description || '')
    || longDescriptionDraft !== (w.long_description || '')

  const handleChildChange = async (childId) => {
    const nextChildId = childId || null
    if ((nextChildId || '') === (w.child_id || '')) return
    try {
      const res = await updateArtwork(w.id, { child_id: nextChildId })
      if (!res.ok) throw new Error((await res.json()).detail || 'Failed to update child')
      const updated = await res.json()
      const work = updated.work || updated
      setSelectedWork(work)
      replaceWork(work)
      reloadAll()
      toast('Saved')
    } catch (err) {
      toast(err.message || 'Failed to update child')
    }
  }

  const handleSave = async () => {
    try {
      setSaving(true)
      const res = await updateArtwork(w.id, {
        description: descriptionDraft,
        long_description: longDescriptionDraft,
      })
      if (!res.ok) throw new Error((await res.json()).detail || 'Failed to save')
      const updated = await res.json()
      setSelectedWork(updated.work || updated)
      toast('Saved')
      reloadAll()
    } catch (err) {
      toast(err.message || 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  const handleRunAI = async () => {
    try {
      setRunningAI(true)
      await analyzeArtwork(w.id)
      const processingWork = { ...w, ai_status: 'processing', ai_error: null }
      setSelectedWork(processingWork)
      replaceWork(processingWork)
      toast('AI started')
      setTimeout(() => reloadArtwork(w.id), 1200)
      setTimeout(() => {
        reloadArtwork(w.id)
        reloadAll()
        setRunningAI(false)
      }, 5000)
    } catch {
      setRunningAI(false)
      toast('Failed to start AI')
    }
  }

  return (
    <aside className="border-l border-[#e5e5e5] bg-white overflow-hidden flex flex-col">
      <div className="flex-1 overflow-y-auto">
        <div
          className="w-full grid place-items-center bg-[#f0f0f0] h-[280px] cursor-zoom-in border-b border-[#e5e5e5] relative overflow-hidden"
          onClick={() => setLightboxSrc({ id: w.id, src: path })}
        >
          <img
            className="max-w-full max-h-[280px] object-contain block transition-transform duration-300 hover:scale-[1.02]"
            src={path}
            alt={title}
          />
        </div>

        <div className="p-5 flex flex-col gap-5 pb-6">
          <div className="flex flex-col gap-2">
            <div className="flex items-start justify-between gap-3">
              <h2 className="min-w-0 font-sans text-lg font-bold text-[#1d1d1f] leading-tight">{title}</h2>
              <AIStatusPill work={w} />
            </div>
            {metaParts.length > 0 && (
              <div className="flex flex-wrap gap-1.5 text-xs text-[#a1a1a6]">
                {metaParts.map((p, i) => (
                  <span key={i} className="flex items-center gap-1">
                    {i > 0 && <span className="text-[#e5e5e5]">·</span>}
                    {p}
                  </span>
                ))}
              </div>
            )}
            <select
              value={w.child_id || ''}
              onChange={e => handleChildChange(e.target.value)}
              className="h-8 w-fit max-w-full rounded-lg border border-[#ededf0] bg-[#fbfbfc] px-2.5 text-xs font-semibold text-[#5f5f66] outline-none hover:bg-white focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
            >
              <option value="">{t('unassigned')}</option>
              {children.map(childItem => (
                <option key={childItem.id} value={childItem.id}>{childItem.name}</option>
              ))}
            </select>
            {(aiState !== 'completed' || w.ai_error) && (
              <div className="text-xs leading-relaxed text-[#a1a1a6]">
                {aiStateLabel}{w.ai_error ? ` · ${w.ai_error}` : ''}
              </div>
            )}
          </div>

          <div>
            <SectionTitle>{t('brief')}</SectionTitle>
            <textarea
              value={descriptionDraft}
              onChange={e => setDescriptionDraft(e.target.value)}
              placeholder={t('noBrief')}
              rows={3}
              className="w-full resize-y rounded-xl border border-[#eeeeef] bg-[#fbfbfc] px-3 py-2.5 text-sm leading-relaxed text-[#5f5f66] outline-none focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
            />
          </div>

          <div>
            <SectionTitle>{t('description')}</SectionTitle>
            <textarea
              value={longDescriptionDraft}
              onChange={e => setLongDescriptionDraft(e.target.value)}
              placeholder={t('noDescription')}
              rows={8}
              className="w-full resize-y rounded-xl border border-[#eeeeef] bg-white px-3 py-2.5 text-sm leading-relaxed text-[#5f5f66] outline-none focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
            />
          </div>

          <div>
            <SectionTitle>{t('tags')}</SectionTitle>
            <div className="flex flex-wrap gap-1.5">
              {tags.map((t, i) => (
                <span
                  key={i}
                  className="inline-flex items-center gap-1 text-[11px] px-2.5 py-1 rounded-full bg-[#f5f5f7] text-[#6e6e73] leading-tight border border-[#e5e5e5]"
                >
                  {t.name}
                  <button
                    onClick={() => handleRemoveTag(t.name, t.type)}
                    className="text-[#a1a1a6] hover:text-[#007aff] text-[11px] font-bold leading-none border-0 bg-transparent p-0 cursor-pointer"
                  >
                    ✕
                  </button>
                </span>
              ))}
              {!tags.length && (
                <span className="text-xs text-[#b8b8bd]">{t('noTags')}</span>
              )}
            </div>
          </div>

          <div className="border-t border-[#f0f0f2] pt-1">
            <button
              type="button"
              onClick={() => setShowAdvanced(value => !value)}
              className="flex w-full cursor-pointer items-center justify-between rounded-lg px-1 py-2 text-xs font-semibold text-[#8e8e93] hover:text-[#1d1d1f]"
            >
              <span>{showAdvanced ? t('hideAdvanced') : t('advanced')}</span>
              <span>{showAdvanced ? '−' : '+'}</span>
            </button>
            {showAdvanced && (
              <div className="mt-2 flex flex-col gap-4">
                <div>
                  <SectionTitle>{t('artworkInfo')}</SectionTitle>
                  <div className="rounded-xl border border-[#eeeeef] bg-white px-3">
                    <InfoRow label={t('child')} value={child} />
                    <InfoRow label={t('date')} value={date || w.date_note} />
                    <InfoRow label={t('batch')} value={w.batch_name} />
                    <InfoRow label={t('type')} value={w.work_type} />
                    <InfoRow label={t('stage')} value={w.stage} />
                    <InfoRow label={t('medium')} value={w.medium} />
                    <InfoRow label={t('size')} value={dimensions} />
                    <InfoRow label={t('status')} value={w.physical_status} />
                    <InfoRow label={t('ai')} value={aiStatus} />
                    <InfoRow label={t('locale')} value={w.ai_locale} />
                    <InfoRow label={t('file')} value={w.original_filename} />
                    <InfoRow label={t('created')} value={createdAt} />
                    <InfoRow label={t('updated')} value={updatedAt} />
                  </div>
                </div>
                <div>
                  <SectionTitle>{t('personalNotes')}</SectionTitle>
                  <div className="rounded-xl border border-[#eeeeef] bg-white px-3">
                    <InfoRow label={t('childQuote')} value={w.child_quote} />
                    <InfoRow label={t('parentNote')} value={w.parent_note} />
                    <InfoRow label={t('story')} value={w.story} />
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
      <div className="shrink-0 border-t border-[#e5e5e5] bg-white/95 backdrop-blur px-4 py-3">
        <div className="flex gap-2">
          <button
            type="button"
            className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold text-white bg-[#007aff] border border-[#007aff] hover:bg-[#0062cc] cursor-pointer disabled:opacity-45 disabled:cursor-not-allowed"
            onClick={handleSave}
            disabled={!hasChanges || saving}
          >
            {saving ? t('saving') : t('save')}
          </button>
          <button
            type="button"
            className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold text-[#007aff] bg-[#f2f8ff] border border-[#007aff]/20 hover:bg-[#e8f2ff] cursor-pointer disabled:opacity-45 disabled:cursor-not-allowed"
            onClick={handleRunAI}
            disabled={runningAI || w.ai_status === 'processing'}
          >
            {runningAI || w.ai_status === 'processing' ? t('running') : t('runAI')}
          </button>
          {w.deleted_at ? (
            <button
              type="button"
              className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold text-[#248a3d] bg-[#effaf2] border border-[#cdeed7] hover:bg-[#e5f7ea] cursor-pointer"
              onClick={handleRestore}
            >
              {t('restore')}
            </button>
          ) : (
            <button
              type="button"
              className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold text-[#ff4b43] bg-white border border-[#ffd8d6] hover:bg-[#ff4b43]/5 cursor-pointer"
              onClick={handleDelete}
            >
              {t('moveToTrash')}
            </button>
          )}
        </div>
      </div>
    </aside>
  )
}
