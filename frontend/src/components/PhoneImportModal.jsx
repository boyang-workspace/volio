import { useState, useEffect } from 'react'
import { useVolio } from '../VolioContext'
import { createMobileSession } from '../api'

export default function PhoneImportModal() {
  const { phoneImportOpen, setPhoneImportOpen, toast, setMobileSession, t } = useVolio()
  const [qr, setQr] = useState(null)
  const [url, setUrl] = useState('')
  const [loading, setLoading] = useState(false)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!phoneImportOpen) return
    let cancelled = false
    Promise.resolve()
      .then(() => {
        if (cancelled) return null
        setQr(null); setUrl(''); setFailed(false); setLoading(true)
        return createMobileSession()
      })
      .then(data => {
        if (!data || cancelled) return
        setUrl(data.url)
        setQr(data.qr_data_url)
        setMobileSession({
          token: data.token,
          url: data.url,
          childName: data.child_name,
          uploadedCount: data.uploaded_count || 0,
          lastUploadAt: data.last_upload_at || null,
          expiresAt: Date.now() + (data.expires_in || 3600) * 1000,
        })
        setLoading(false)
      })
      .catch(() => {
        if (cancelled) return
        setFailed(true); setLoading(false); toast(t('failedToGenerate'))
      })
    return () => { cancelled = true }
  }, [phoneImportOpen, setMobileSession, toast, t])

  if (!phoneImportOpen) return null

  const copyLink = async () => {
    if (!url) return
    try {
      await navigator.clipboard.writeText(url)
      toast(t('copyPhoneLink'))
    } catch {
      toast(url)
    }
  }

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center" onClick={() => setPhoneImportOpen(false)}>
      <div className="fixed inset-0 bg-black/40 backdrop-blur-sm -z-10" />
      <div
        className="relative w-full max-w-sm bg-white rounded-2xl shadow-2xl border border-[#e5e5e5] overflow-hidden"
        onClick={e => e.stopPropagation()}
      >
        <div className="px-5 pt-5 pb-2 flex items-center justify-between">
          <div>
            <h2 className="font-sans text-lg font-bold text-[#1d1d1f]">{t('phoneImportTitle')}</h2>
            <p className="text-xs text-[#a1a1a6] mt-0.5 font-medium">
              {t('phoneImportHelp')}
            </p>
          </div>
          <button
            type="button"
            onClick={() => setPhoneImportOpen(false)}
            className="size-7 rounded-full bg-[#f5f5f7] text-[#6e6e73] border-0 cursor-pointer grid place-items-center text-xs hover:bg-[#e5e5e5] transition-colors shrink-0"
          >
            ✕
          </button>
        </div>
        <div className="px-5 pb-5 flex flex-col items-center gap-3">
          {loading && (
            <div className="text-[#a1a1a6] text-xs py-5 animate-pulse">{t('generatingQr')}</div>
          )}
          {failed && (
            <div className="text-[#a1a1a6] text-xs py-5">{t('failedToGenerate')}</div>
          )}
          {qr && (
            <div className="bg-white p-3 rounded-2xl shadow-sm border border-[#e5e5e5]">
              <img src={qr} alt="QR code" className="size-44 image-rendering-pixelated" />
            </div>
          )}
          {url && (
            <div className="w-full rounded-xl border border-[#ececf0] bg-[#fbfbfc] p-2.5">
              <div className="mb-1 text-[10px] font-semibold uppercase tracking-[0.06em] text-[#a1a1a6]">
                {t('phoneImportUrl')}
              </div>
              <p className="text-[11px] text-[#6e6e73] break-all leading-relaxed">{url}</p>
              <div className="mt-2 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={copyLink}
                  className="rounded-lg border border-[#e5e5e5] bg-white px-2 py-1.5 text-xs font-semibold text-[#5f5f66] hover:bg-[#f5f5f7]"
                >
                  {t('copyPhoneLink')}
                </button>
                <a
                  href={url}
                  target="_blank"
                  rel="noreferrer"
                  className="rounded-lg border border-[#007aff]/20 bg-[#f2f8ff] px-2 py-1.5 text-center text-xs font-semibold text-[#007aff] hover:bg-[#e8f2ff]"
                >
                  {t('openPhoneLink')}
                </a>
              </div>
            </div>
          )}
          <p className="text-[11px] text-[#a1a1a6] text-center max-w-[260px] leading-relaxed">
            {t('sameWifi')}
          </p>
        </div>
      </div>
    </div>
  )
}
