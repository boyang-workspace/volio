import { useState, useEffect } from 'react'
import { useVolio } from '../VolioContext'
import { checkIosPairingSession, createIosPairingSession } from '../api'

export default function IosPairingModal() {
  const { iosPairingOpen, setIosPairingOpen, setIosPairingSession, toast, t } = useVolio()
  const [pairing, setPairing] = useState(null)
  const [loading, setLoading] = useState(false)
  const [failed, setFailed] = useState(false)
  const [paired, setPaired] = useState(false)

  useEffect(() => {
    if (!iosPairingOpen) return
    let cancelled = false
    Promise.resolve()
      .then(() => {
        if (cancelled) return null
        setPairing(null)
        setFailed(false)
        setPaired(false)
        setLoading(true)
        return createIosPairingSession()
      })
      .then(data => {
        if (cancelled) return
        if (!data) return
        setPairing(data)
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

  useEffect(() => {
    if (!iosPairingOpen || !pairing?.token || paired) return
    let cancelled = false
    let closeTimer = null
    const poll = async () => {
      try {
        const result = await checkIosPairingSession(pairing.token)
        if (cancelled) return
        if (result?.valid && result?.last_seen_at) {
          setPaired(true)
          setIosPairingSession(current => ({
            ...(current || {}),
            token: pairing.token,
            baseUrl: pairing.base_url,
            hostName: pairing.host_name,
            expiresAt: Date.now() + (result.expires_in || pairing.expires_in || 28800) * 1000,
            lastSeenAt: result.last_seen_at,
          }))
          toast('iPhone connected')
          closeTimer = setTimeout(() => setIosPairingOpen(false), 1100)
        }
      } catch { /* keep waiting */ }
    }
    poll()
    const timer = setInterval(poll, 1200)
    return () => {
      cancelled = true
      clearInterval(timer)
      clearTimeout(closeTimer)
    }
  }, [iosPairingOpen, pairing, paired, setIosPairingOpen, setIosPairingSession, toast])

  if (!iosPairingOpen) return null

  const copyPayload = async () => {
    if (!pairing) return
    const payload = JSON.stringify({
      type: 'volio-ios-pairing',
      version: 1,
      base_url: pairing.base_url,
      token: pairing.token,
      host_name: pairing.host_name,
    })
    try {
      await navigator.clipboard.writeText(payload)
      toast(t('copyPairingPayload'))
    } catch {
      toast(pairing.pairing_url)
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
          {pairing?.qr_data_url && !paired && (
            <div className="rounded-2xl border border-[#e5e5e5] bg-white p-3 shadow-sm">
              <img src={pairing.qr_data_url} alt="Volio iPhone pairing QR code" className="size-44 image-rendering-pixelated" />
            </div>
          )}
          {paired && (
            <div className="grid size-44 place-items-center rounded-2xl border border-[#cdeed7] bg-[#ecf8f0] text-[#248a3d] shadow-sm">
              <div className="text-center">
                <div className="mx-auto mb-3 grid size-14 place-items-center rounded-full bg-white">
                  <svg width="30" height="30" viewBox="0 0 24 24" fill="none">
                    <path d="m5 12 4 4L19 6" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </div>
                <div className="text-sm font-bold">iPhone connected</div>
                <div className="mt-1 text-xs font-medium text-[#5f8f67]">Volio is ready</div>
              </div>
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
