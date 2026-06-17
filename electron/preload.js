import { contextBridge } from 'electron'

contextBridge.exposeInMainWorld('volioDesktop', {
  platform: process.platform,
})
