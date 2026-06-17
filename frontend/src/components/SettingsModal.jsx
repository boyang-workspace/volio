import { useEffect, useState } from 'react'
import { useVolio } from '../VolioContext'
import { addChild, updateChild, deleteChild, saveSettings } from '../api'

const languageOptions = [
  { value: 'en', label: 'English' },
  { value: 'zh', label: '中文' },
]

function FieldLabel({ children }) {
  return <div className="text-xs font-semibold text-[#6e6e73]">{children}</div>
}

export default function SettingsModal() {
  const {
    settingsOpen, setSettingsOpen, children, settings,
    setSettings, reloadAll, toast, t,
  } = useVolio()
  const [uiLanguage, setUiLanguage] = useState('en')
  const [aiLanguage, setAiLanguage] = useState('zh')
  const [ttlMinutes, setTtlMinutes] = useState(60)
  const [newChildName, setNewChildName] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!settings) return
    const timer = setTimeout(() => {
      setUiLanguage(settings.ui_language || 'en')
      setAiLanguage(settings.ai_language || 'zh')
      setTtlMinutes(settings.mobile_session_ttl_minutes || 60)
    }, 0)
    return () => clearTimeout(timer)
  }, [settings])

  if (!settingsOpen) return null

  const handleSaveSettings = async () => {
    try {
      setSaving(true)
      const saved = await saveSettings({
        ui_language: uiLanguage,
        ai_language: aiLanguage,
        mobile_session_ttl_minutes: ttlMinutes,
      })
      setSettings(saved)
      toast(t('saveSettings'))
    } catch (err) {
      toast(err.message || 'Failed to save settings')
    } finally {
      setSaving(false)
    }
  }

  const handleAddChild = async () => {
    const name = newChildName.trim()
    if (!name) return toast(t('enterChildName'))
    try {
      await addChild(name)
      setNewChildName('')
      await reloadAll()
      toast(t('add'))
    } catch (err) {
      toast(err.message || 'Failed to add child')
    }
  }

  const handleRenameChild = async (child) => {
    const name = prompt('Child name:', child.name)
    if (!name || name.trim() === child.name) return
    try {
      await updateChild(child.id, name.trim())
      await reloadAll()
      toast(t('rename'))
    } catch (err) {
      toast(err.message || 'Failed to rename child')
    }
  }

  const handleDeleteChild = async (child) => {
    if (!confirm(`Delete ${child.name}? Their artworks will stay in Volio and move to Unassigned.`)) return
    try {
      await deleteChild(child.id)
      await reloadAll()
      toast('Child deleted')
    } catch (err) {
      toast(err.message || 'Failed to delete child')
    }
  }

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center" onClick={() => setSettingsOpen(false)}>
      <div className="fixed inset-0 bg-black/40 backdrop-blur-sm -z-10" />
      <div
        className="relative flex max-h-[86vh] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-[#e5e5e5] bg-white shadow-2xl"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4 border-b border-[#eeeeef] px-5 py-4">
          <div>
            <h2 className="text-lg font-bold text-[#1d1d1f]">{t('settingsTitle')}</h2>
            <p className="mt-0.5 text-xs font-medium text-[#8e8e93]">
              {t('settingsIntro')}
            </p>
          </div>
          <button
            type="button"
            onClick={() => setSettingsOpen(false)}
            className="grid size-7 shrink-0 cursor-pointer place-items-center rounded-full border-0 bg-[#f5f5f7] text-xs text-[#6e6e73] transition-colors hover:bg-[#e5e5e5]"
          >
            ✕
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-5">
          <section className="space-y-3">
            <div>
              <h3 className="text-sm font-bold text-[#1d1d1f]">{t('children')}</h3>
              <p className="mt-0.5 text-xs text-[#8e8e93]">
                {t('childrenIntro')}
              </p>
            </div>
            <div className="rounded-xl border border-[#eeeeef]">
              {children.length === 0 && (
                <div className="px-3 py-3 text-sm text-[#8e8e93]">{t('noChildren')}</div>
              )}
              {children.map(child => (
                <div key={child.id} className="flex items-center gap-3 border-b border-[#f0f0f2] px-3 py-2.5 last:border-b-0">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-semibold text-[#1d1d1f]">{child.name}</div>
                    <div className="text-xs text-[#8e8e93]">{child.created_at ? t('profileReady') : t('add')}</div>
                  </div>
                  <button
                    type="button"
                    onClick={() => handleRenameChild(child)}
                    className="rounded-lg border border-[#e5e5e5] bg-white px-3 py-1.5 text-xs font-semibold text-[#5f5f66] hover:bg-[#f5f5f7]"
                  >
                    {t('rename')}
                  </button>
                  <button
                    type="button"
                    onClick={() => handleDeleteChild(child)}
                    className="rounded-lg border border-[#ffd8d6] bg-white px-3 py-1.5 text-xs font-semibold text-[#ff4b43] hover:bg-[#ff4b43]/5"
                  >
                    {t('delete')}
                  </button>
                </div>
              ))}
            </div>
            <div className="flex gap-2">
              <input
                value={newChildName}
                onChange={e => setNewChildName(e.target.value)}
                placeholder={t('newChildName')}
                className="h-9 flex-1 rounded-xl border border-[#d9d9de] bg-white px-3 text-sm outline-none focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
              />
              <button
                type="button"
                onClick={handleAddChild}
                className="rounded-xl border border-[#007aff]/20 bg-[#f2f8ff] px-4 text-sm font-semibold text-[#007aff] hover:bg-[#e8f2ff]"
              >
                {t('add')}
              </button>
            </div>
          </section>

          <section className="mt-7 grid gap-4 border-t border-[#eeeeef] pt-5">
            <div>
              <h3 className="text-sm font-bold text-[#1d1d1f]">{t('languages')}</h3>
              <p className="mt-0.5 text-xs text-[#8e8e93]">
                {t('languagesIntro')}
              </p>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <label className="grid gap-1.5">
                <FieldLabel>{t('systemLanguage')}</FieldLabel>
                <select
                  value={uiLanguage}
                  onChange={e => setUiLanguage(e.target.value)}
                  className="h-10 rounded-xl border border-[#d9d9de] bg-white px-3 text-sm text-[#1d1d1f] outline-none focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
                >
                  {languageOptions.map(option => (
                    <option key={option.value} value={option.value}>{option.label}</option>
                  ))}
                </select>
              </label>
              <label className="grid gap-1.5">
                <FieldLabel>{t('aiDescriptionLanguage')}</FieldLabel>
                <select
                  value={aiLanguage}
                  onChange={e => setAiLanguage(e.target.value)}
                  className="h-10 rounded-xl border border-[#d9d9de] bg-white px-3 text-sm text-[#1d1d1f] outline-none focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
                >
                  {languageOptions.map(option => (
                    <option key={option.value} value={option.value}>{option.label}</option>
                  ))}
                </select>
              </label>
            </div>
          </section>

          <section className="mt-7 grid gap-4 border-t border-[#eeeeef] pt-5">
            <div>
              <h3 className="text-sm font-bold text-[#1d1d1f]">{t('phoneImportSettings')}</h3>
              <p className="mt-0.5 text-xs text-[#8e8e93]">
                {t('phoneImportSettingsIntro')}
              </p>
            </div>
            <label className="grid max-w-[220px] gap-1.5">
              <FieldLabel>{t('connectionDuration')}</FieldLabel>
              <select
                value={ttlMinutes}
                onChange={e => setTtlMinutes(Number(e.target.value))}
                className="h-10 rounded-xl border border-[#d9d9de] bg-white px-3 text-sm text-[#1d1d1f] outline-none focus:border-[#007aff] focus:ring-3 focus:ring-[#007aff]/10"
              >
                <option value={30}>{t('minutes30')}</option>
                <option value={60}>{t('hour1')}</option>
                <option value={120}>{t('hours2')}</option>
                <option value={240}>{t('hours4')}</option>
              </select>
            </label>
          </section>
        </div>

        <div className="flex justify-end gap-2 border-t border-[#eeeeef] px-5 py-4">
          <button
            type="button"
            onClick={() => setSettingsOpen(false)}
            className="rounded-xl border border-[#e5e5e5] bg-white px-4 py-2 text-sm font-semibold text-[#5f5f66] hover:bg-[#f5f5f7]"
          >
            {t('close')}
          </button>
          <button
            type="button"
            onClick={handleSaveSettings}
            disabled={saving}
            className="rounded-xl border border-[#007aff]/20 bg-[#007aff] px-4 py-2 text-sm font-semibold text-white hover:bg-[#0062cc] disabled:opacity-50"
          >
            {saving ? t('saving') : t('saveSettings')}
          </button>
        </div>
      </div>
    </div>
  )
}
