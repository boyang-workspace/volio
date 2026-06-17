import { useState, useEffect } from 'react'
import { useVolio } from '../VolioContext'
import { createIosPairingSession } from '../api'

export default function IosPairingModal() {
  const { iosPairingOpen, setIosPairingOpen, setIosPairingSession, toast, t } = useVolio()
  const [pairing, setPairing] = useState(null)
  const [loading, setLoading] = useState(false)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!iosPairingOpen) return
    let cancelled = false
    Promise.resolve()
      .then(() => {
        if (cancelled) return null
        setPairing(null)
        setFailed(false)
        setLoading(true)
        return createIosPairingSession()
      })
      .then(data => {
        if (cancelled) return
        if (!data) return
        setPairing(data)
        setIosPairingSession({
          token: data.token,
          baseUrl: data.base_url,
          hostName: data.host_name,
          expiresAt: Date.now() + (data.expires_in || 28800) * 1000,
        })
        setLoading(false)
      })
      .catch(() => {
        if (cancelled) return
        setFailed(true)
        setLoading(false)
        toast(t('failedToGenerate'))
      })
    return () => { cancelled = true }
  }, [iosPairingOpen, setIosPairingSession, toast, t])

  if (!iosPairingOpen) return null

  const copyPayload = async () => {
    if (!pairing) return
    try {
      await navigator.clipboard.writeText(pairing.pairing_url)
      toast(t('copyPairingPayload'))
    } catch {
      toast(pairing.base_url)
    }
  }

  return (
    <div className="fixed inset-0 z-[72] flex items-center justify-center" onClick={() => setIosPairingOpen(false)}>
      <div className="fixed inset-0 bg-black/40 backdrop-blur-sm -z-10" />
      <div
        className="relative w-full max-w-sm overflow-hidden rounded-2xl border border-[#e5e5e5] bg-white shadow-2xl"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-start justify-between px-5 pb-2 pt-5">
          <div>
            <h2 className="font-sans text-lg font-bold text-[#1d1d1f]">{t('connectIphoneTitle')}</h2>
            <p className="mt-0.5 text-xs font-medium text-[#a1a1a6]">{t('connectIphoneHelp')}</p>
          </div>
          <button
            type="button"
            onClick={() => setIosPairingOpen(false)}
            className="grid size-7 shrink-0 cursor-pointer place-items-center rounded-full border-0 bg-[#f5f5f7] text-xs text-[#6e6e73] transition-colors hover:bg-[#e5e5e5]"
          >
            x
          </button>
        </div>

        <div className="flex flex-col items-center gap-3 px-5 pb-5">
          {loading && (
            <div className="py-5 text-xs text-[#a1a1a6] animate-pulse">{t('generatingQr')}</div>
          )}
          {failed && (
            <div className="py-5 text-xs text-[#a1a1a6]">{t('failedToGenerate')}</div>
          )}
          {pairing?.qr_data_url && (
            <div className="rounded-2xl border border-[#e5e5e5] bg-white p-3 shadow-sm">
              <img src={pairing.qr_data_url} alt="Volio iPhone pairing QR code" className="size-44 image-rendering-pixelated" />
            </div>
          )}
          {pairing && (
            <div className="w-full rounded-xl border border-[#ececf0] bg-[#fbfbfc] p-2.5">
              <div className="mb-1 text-[10px] font-semibold uppercase tracking-[0.06em] text-[#a1a1a6]">
                {t('desktopEndpoint')}
              </div>
              <p className="break-all text-[11px] leading-relaxed text-[#6e6e73]">{pairing.base_url}</p>
              <div className="mt-2 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={copyPayload}
                  className="rounded-lg border border-[#e5e5e5] bg-white px-2 py-1.5 text-xs font-semibold text-[#5f5f66] hover:bg-[#f5f5f7]"
                >
                  {t('copyPairingPayload')}
                </button>
                <a
                  href={pairing.pairing_url}
                  className="rounded-lg border border-[#007aff]/20 bg-[#f2f8ff] px-2 py-1.5 text-center text-xs font-semibold text-[#007aff] hover:bg-[#e8f2ff]"
                >
                  {t('openVolioLink')}
                </a>
              </div>
            </div>
          )}
          <p className="max-w-[270px] text-center text-[11px] leading-relaxed text-[#a1a1a6]">
            {t('connectIphoneSameWifi')}
          </p>
        </div>
      </div>
    </div>
  )
}
