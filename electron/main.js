import { app, BrowserWindow, dialog, nativeImage, shell } from 'electron'
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const electronDir = path.dirname(fileURLToPath(import.meta.url))
const rootDir = path.resolve(electronDir, '..')
const frontendIndex = path.join(rootDir, 'frontend', 'dist', 'index.html')
const requirementsPath = path.join(rootDir, 'requirements.txt')
const logDir = path.join(rootDir, '.volio', 'logs')
const backendLogPath = path.join(logDir, 'electron-backend.log')

let mainWindow = null
let backendProcess = null
let backendPort = null
let isQuitting = false

function appendLaunchLog(message) {
  fs.mkdirSync(logDir, { recursive: true })
  fs.appendFileSync(backendLogPath, `[${new Date().toISOString()}] ${message}\n`)
}

function resetLaunchLog() {
  fs.mkdirSync(logDir, { recursive: true })
  fs.writeFileSync(backendLogPath, `[${new Date().toISOString()}] Volio Desktop launch started\n`)
}

async function preferredPython() {
  const candidates = [
    process.env.VOLIO_PYTHON,
    '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3',
    '/opt/homebrew/bin/python3',
    '/usr/local/bin/python3',
    '/usr/bin/python3',
    'python3',
  ].filter(Boolean)
  for (const candidate of candidates) {
    for (const invocation of pythonInvocations(candidate)) {
      try {
        await runCommand(invocation.command, [...invocation.args, '--version'])
        return invocation
      } catch {
        // Try the next common Python location or architecture wrapper.
      }
    }
  }
  throw new Error('Python 3 was not found. Install Python 3, then open Volio Desktop again.')
}

function pythonInvocations(candidate) {
  const invocations = []
  if (process.platform === 'darwin' && fs.existsSync('/usr/bin/arch')) {
    invocations.push({
      command: '/usr/bin/arch',
      args: ['-arm64', candidate],
      label: `arch -arm64 ${candidate}`,
    })
  }
  invocations.push({ command: candidate, args: [], label: candidate })
  return invocations
}

function runCommand(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: rootDir,
      env: { ...process.env, PYTHONUNBUFFERED: '1' },
      stdio: ['ignore', 'pipe', 'pipe'],
      ...options,
    })
    let stdout = ''
    let stderr = ''
    child.stdout?.on('data', data => { stdout += data.toString() })
    child.stderr?.on('data', data => { stderr += data.toString() })
    child.on('error', reject)
    child.on('close', code => {
      if (code === 0) {
        resolve({ stdout, stderr })
      } else {
        const error = new Error(stderr || stdout || `${command} exited with code ${code}`)
        error.stdout = stdout
        error.stderr = stderr
        error.code = code
        reject(error)
      }
    })
  })
}

async function ensurePythonDependencies(python) {
  const probeScript = [
    'import platform, fastapi, uvicorn, PIL, requests, multipart, qrcode, cv2, numpy',
    'print(f"python_arch={platform.machine()} numpy={numpy.__version__} cv2={cv2.__version__}")',
    'assert platform.machine() == "arm64"',
  ].join('; ')
  try {
    await runCommand(python.command, [
      ...python.args,
      '-c',
      probeScript,
    ])
  } catch (error) {
    appendLaunchLog(`Python dependency check failed for ${python.label}: ${formatCommandError(error)}`)
    appendLaunchLog('Python dependencies missing. Installing requirements.txt...')
    await runCommand(python.command, [
      ...python.args,
      '-m',
      'pip',
      'install',
      '--trusted-host',
      'pypi.org',
      '--trusted-host',
      'files.pythonhosted.org',
      '-r',
      requirementsPath,
    ])
    await runCommand(python.command, [...python.args, '-c', probeScript])
  }
}

function formatCommandError(error) {
  const message = `${error.stderr || error.stdout || error.message || error}`
    .replace(/\s+/g, ' ')
    .trim()
  return message.slice(0, 1200)
}

function canListen(port, host) {
  return new Promise(resolve => {
    const server = net.createServer()
    server.once('error', () => resolve(false))
    server.once('listening', () => {
      server.close(() => resolve(true))
    })
    server.listen(port, host)
  })
}

async function findPort(startPort) {
  for (let port = startPort; port < startPort + 80; port += 1) {
    const localAvailable = await canListen(port, '127.0.0.1')
    const lanAvailable = await canListen(port, '0.0.0.0')
    if (localAvailable && lanAvailable) return port
  }
  throw new Error(`No free local port found from ${startPort} to ${startPort + 79}.`)
}

function waitForServer(port, timeoutMs = 20000) {
  const startedAt = Date.now()
  const url = `http://127.0.0.1:${port}/api/state`
  return new Promise((resolve, reject) => {
    const probe = () => {
      const request = http.get(url, response => {
        response.resume()
        if (response.statusCode && response.statusCode < 500) {
          resolve()
        } else if (Date.now() - startedAt > timeoutMs) {
          reject(new Error(`Volio server did not become ready on port ${port}.`))
        } else {
          setTimeout(probe, 250)
        }
      })
      request.on('error', () => {
        if (Date.now() - startedAt > timeoutMs) {
          reject(new Error(`Volio server did not become ready on port ${port}.`))
        } else {
          setTimeout(probe, 250)
        }
      })
      request.setTimeout(1000, () => request.destroy())
    }
    probe()
  })
}

async function startBackend() {
  if (!fs.existsSync(frontendIndex)) {
    throw new Error('Frontend build is missing. Run `npm run build:frontend` first.')
  }

  const python = await preferredPython()
  await ensurePythonDependencies(python)

  const preferredPort = Number.parseInt(process.env.VOLIO_PORT || '8001', 10)
  backendPort = await findPort(Number.isFinite(preferredPort) ? preferredPort : 8001)
  appendLaunchLog(`Starting backend on ${backendPort} with ${python.label}`)

  fs.mkdirSync(logDir, { recursive: true })
  const logStream = fs.createWriteStream(backendLogPath, { flags: 'a' })
  backendProcess = spawn(python.command, [
    ...python.args,
    '-m',
    'uvicorn',
    'server.main:app',
    '--host',
    '0.0.0.0',
    '--port',
    String(backendPort),
  ], {
    cwd: rootDir,
    env: {
      ...process.env,
      VOLIO_PORT: String(backendPort),
      PYTHONUNBUFFERED: '1',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  backendProcess.stdout.pipe(logStream, { end: false })
  backendProcess.stderr.pipe(logStream, { end: false })
  backendProcess.on('exit', code => {
    appendLaunchLog(`Backend exited with code ${code}`)
    backendProcess = null
    if (!isQuitting) {
      dialog.showErrorBox('Volio Desktop', `Volio local service stopped. Details are in ${backendLogPath}`)
    }
  })

  await waitForServer(backendPort)
  return `http://127.0.0.1:${backendPort}`
}

function createWindow(baseUrl) {
  const iconPath = path.join(electronDir, '..', 'Volio.icns')
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1080,
    minHeight: 680,
    title: 'Volio Desktop',
    backgroundColor: '#f6f6f7',
    trafficLightPosition: { x: 14, y: 14 },
    icon: iconPath,
    webPreferences: {
      preload: path.join(electronDir, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  })

  mainWindow.loadURL(baseUrl)
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(baseUrl)) return { action: 'allow' }
    shell.openExternal(url)
    return { action: 'deny' }
  })
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith(baseUrl)) {
      event.preventDefault()
      shell.openExternal(url)
    }
  })
  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

function stopBackend() {
  if (!backendProcess) return
  appendLaunchLog(`Stopping backend on ${backendPort}`)
  backendProcess.kill('SIGTERM')
  backendProcess = null
}

app.setName('Volio Desktop')

// Set dock icon for macOS (development mode uses Electron.app's default icon otherwise)
if (process.platform === 'darwin') {
  const iconPath = path.join(electronDir, '..', 'Volio.icns')
  const appIcon = nativeImage.createFromPath(iconPath)
  if (!appIcon.isEmpty()) {
    app.dock.setIcon(appIcon)
  }
}

app.whenReady().then(async () => {
  resetLaunchLog()
  try {
    const baseUrl = await startBackend()
    if (process.env.VOLIO_ELECTRON_SMOKE === '1') {
      appendLaunchLog(`Smoke test passed at ${baseUrl}`)
      app.quit()
      return
    }
    createWindow(baseUrl)
  } catch (error) {
    appendLaunchLog(error.stack || error.message)
    dialog.showErrorBox('Volio Desktop could not start', `${error.message}\n\nDetails are in ${backendLogPath}`)
    app.quit()
  }
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0 && backendPort) {
    createWindow(`http://127.0.0.1:${backendPort}`)
  }
})

app.on('before-quit', () => {
  isQuitting = true
  stopBackend()
})
