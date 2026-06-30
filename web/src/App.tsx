import { useEffect, useState } from 'react'
import './App.css'

type PlaybackState = 'idle' | 'playing' | 'paused' | 'stopped' | 'unsupported'

type PlayerStatus = {
  playbackState: PlaybackState
  nowPlaying: string | null
  nowPlayingItemId: string | null
  playbackList: PlaybackListItem[]
  selectedOutputDevice: OutputDevice | null
  progress: PlaybackProgress | null
  failureReason: string | null
  runtimeInfo: {
    musicLibraryRoot: string
    serverHost: string
    serverPort: number
  }
}

type PlaybackListItem = {
  itemId: string
  path: string
}

type OutputDevice = {
  id: string
  name: string
}

type PlaybackProgress = {
  elapsedSeconds: number
  durationSeconds: number | null
}

type LibraryEntry = {
  name: string
  path: string
}

type LibraryDirectory = {
  path: string
  folders: LibraryEntry[]
  files: LibraryEntry[]
}

type MainView = 'playback' | 'library'

const playbackStateText: Record<PlaybackState, string> = {
  idle: '空闲',
  playing: '播放中',
  paused: '已暂停',
  stopped: '已停止',
  unsupported: '不支持',
}

function formatPlaybackTime(seconds: number) {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '00:00'
  }
  const wholeSeconds = Math.floor(seconds)
  const minutes = Math.floor(wholeSeconds / 60)
  const remainingSeconds = wholeSeconds % 60
  return `${String(minutes).padStart(2, '0')}:${String(remainingSeconds).padStart(2, '0')}`
}

function App() {
  const [status, setStatus] = useState<PlayerStatus | null>(null)
  const [outputDevices, setOutputDevices] = useState<OutputDevice[] | null>(null)
  const [activeView, setActiveView] = useState<MainView>('playback')
  const [libraryDirectory, setLibraryDirectory] = useState<LibraryDirectory | null>(null)

  useEffect(() => {
    let cancelled = false

    async function loadStatus() {
      const response = await fetch('/api/status')
      const nextStatus = (await response.json()) as PlayerStatus
      if (!cancelled) {
        setStatus(nextStatus)
      }
    }

    async function loadOutputDevices() {
      const response = await fetch('/api/devices')
      const nextDevices = (await response.json()) as OutputDevice[]
      if (!cancelled) {
        setOutputDevices(nextDevices)
      }
    }

    void loadStatus()
    void loadOutputDevices()

    return () => {
      cancelled = true
    }
  }, [])

  async function loadLibrary(path = '') {
    const url = path ? `/api/library?path=${encodeURIComponent(path)}` : '/api/library'
    const response = await fetch(url)
    const nextDirectory = (await response.json()) as LibraryDirectory
    setLibraryDirectory(nextDirectory)
  }

  async function showLibrary() {
    setActiveView('library')
    if (!libraryDirectory) {
      await loadLibrary()
    }
  }

  function parentLibraryPath(path: string) {
    const lastSeparator = path.lastIndexOf('/')
    return lastSeparator === -1 ? '' : path.slice(0, lastSeparator)
  }

  async function addLibraryFile(path: string) {
    const response = await fetch('/api/playback-list/files', {
      method: 'POST',
      body: JSON.stringify({ path }),
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function play() {
    const response = await fetch('/api/play', {
      method: 'POST',
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function pause() {
    const response = await fetch('/api/pause', {
      method: 'POST',
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function next() {
    const response = await fetch('/api/next', {
      method: 'POST',
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function previous() {
    const response = await fetch('/api/previous', {
      method: 'POST',
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function selectPlaybackListItem(itemId: string) {
    const response = await fetch('/api/playback-list/select', {
      method: 'POST',
      body: JSON.stringify({ itemId }),
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function deletePlaybackListItem(itemId: string) {
    const response = await fetch('/api/playback-list/delete', {
      method: 'POST',
      body: JSON.stringify({ itemId }),
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function clearPlaybackList() {
    const response = await fetch('/api/playback-list/clear', {
      method: 'POST',
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function selectOutputDevice(deviceId: string) {
    const response = await fetch('/api/devices/select', {
      method: 'POST',
      body: JSON.stringify({ deviceId }),
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  async function addLibraryFolder(path: string) {
    const response = await fetch('/api/playback-list/folders', {
      method: 'POST',
      body: JSON.stringify({ path }),
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

  const selectableOutputDevices = outputDevices ?? []
  const selectedOutputDevice = status?.selectedOutputDevice ?? null
  const outputDevicesLoaded = outputDevices !== null
  const selectedOutputDeviceMissing = Boolean(
    outputDevicesLoaded &&
      selectedOutputDevice &&
      !selectableOutputDevices.some((device) => device.id === selectedOutputDevice.id),
  )
  const outputDeviceMissingText = !outputDevicesLoaded
    ? null
    : selectableOutputDevices.length === 0
      ? '未发现输出设备'
      : selectedOutputDeviceMissing
        ? '已选择的输出设备不在当前设备列表中'
        : null
  const isPlaying = status?.playbackState === 'playing'
  const isPaused = status?.playbackState === 'paused'
  const playButtonClassName = isPlaying ? 'primary-action' : 'secondary-action'
  const pauseButtonClassName = isPaused ? 'primary-action' : 'secondary-action'

  return (
    <main className="remote-shell">
      <header className="remote-header">
        <div>
          <p className="eyebrow">VCO Player</p>
          <h1>{activeView === 'playback' ? '播放' : '资料库'}</h1>
        </div>
        <nav className="remote-tabs" aria-label="主视图">
          <button
            type="button"
            className={activeView === 'playback' ? 'active' : undefined}
            onClick={() => setActiveView('playback')}
          >
            播放
          </button>
          <button
            type="button"
            className={activeView === 'library' ? 'active' : undefined}
            onClick={() => {
              void showLibrary()
            }}
          >
            资料库
          </button>
        </nav>
      </header>

      {activeView === 'playback' ? (
        <>
          <section className="panel" aria-label="当前播放">
            <div className="status-row">
              <span>状态</span>
              <strong>{status ? playbackStateText[status.playbackState] : '加载中'}</strong>
            </div>
            <div className="now-playing">
              <span>当前曲目</span>
              <strong aria-label="当前曲目">{status?.nowPlaying ?? '无'}</strong>
            </div>
            {status?.failureReason ? (
              <p className="failure-reason">{status.failureReason}</p>
            ) : null}
          </section>

          <section className="panel" aria-label="播放控制">
            <div className="transport-actions">
              <button
                type="button"
                className="secondary-action"
                onClick={() => {
                  void previous()
                }}
              >
                上一首
              </button>
              <button
                type="button"
                className={playButtonClassName}
                aria-pressed={isPlaying}
                onClick={() => {
                  void play()
                }}
              >
                播放
              </button>
              <button
                type="button"
                className={pauseButtonClassName}
                aria-pressed={isPaused}
                onClick={() => {
                  void pause()
                }}
              >
                暂停
              </button>
              <button
                type="button"
                className="secondary-action"
                onClick={() => {
                  void next()
                }}
              >
                下一首
              </button>
            </div>
            <div className="progress-grid">
              <span>已播放</span>
              <strong aria-label="已播放时间">
                {formatPlaybackTime(status?.progress?.elapsedSeconds ?? 0)}
              </strong>
              <span>总时长</span>
              <strong aria-label="总时长">
                {status?.progress?.durationSeconds == null
                  ? '未知'
                  : formatPlaybackTime(status.progress.durationSeconds)}
              </strong>
            </div>
          </section>

          <section className="panel" aria-label="输出设备">
            <div className="status-row">
              <span>输出设备</span>
              <strong aria-label="当前输出设备">
                {selectedOutputDevice?.name ?? '未选择输出设备'}
              </strong>
            </div>
            <label className="field-row">
              <span>输出设备</span>
              <select
                value={selectedOutputDevice?.id ?? ''}
                disabled={!outputDevicesLoaded || selectableOutputDevices.length === 0}
                onChange={(event) => {
                  if (event.target.value) {
                    void selectOutputDevice(event.target.value)
                  }
                }}
              >
                <option value="">
                  {!outputDevicesLoaded
                    ? '加载输出设备'
                    : selectableOutputDevices.length
                      ? '选择输出设备'
                      : '无可选输出设备'}
                </option>
                {selectedOutputDeviceMissing && selectedOutputDevice ? (
                  <option value={selectedOutputDevice.id} disabled>
                    {selectedOutputDevice.name} (不可用)
                  </option>
                ) : null}
                {selectableOutputDevices.map((device) => (
                  <option key={device.id} value={device.id}>
                    {device.name}
                  </option>
                ))}
              </select>
            </label>
            {outputDeviceMissingText ? (
              <p className="empty-state device-alert" aria-label="输出设备缺失状态">
                {outputDeviceMissingText}
              </p>
            ) : null}
          </section>

          <section className="panel" aria-label="播放列表">
            <div className="panel-heading">
              <h2>播放列表</h2>
              <div className="panel-actions">
                <span>{status?.playbackList.length ?? 0}</span>
                <button
                  type="button"
                  className="secondary-action"
                  disabled={!status?.playbackList.length}
                  onClick={() => {
                    void clearPlaybackList()
                  }}
                >
                  清空播放列表
                </button>
              </div>
            </div>
            {status?.playbackList.length ? (
              <ol className="playback-list">
                {status.playbackList.map((item) => {
                  const isNowPlayingItem = item.itemId === status.nowPlayingItemId

                  return (
                    <li
                      key={item.itemId}
                      className={isNowPlayingItem ? 'active' : undefined}
                    >
                      <span>{item.path}</span>
                      <div className="playback-list-actions">
                        <button
                          type="button"
                          className="secondary-action"
                          aria-label={`播放 ${item.path}`}
                          onClick={() => {
                            void selectPlaybackListItem(item.itemId)
                          }}
                        >
                          播放
                        </button>
                        <button
                          type="button"
                          className="secondary-action"
                          aria-label={`删除 ${item.path}`}
                          disabled={isNowPlayingItem}
                          onClick={() => {
                            void deletePlaybackListItem(item.itemId)
                          }}
                        >
                          删除
                        </button>
                      </div>
                    </li>
                  )
                })}
              </ol>
            ) : (
              <p className="empty-state">播放列表为空</p>
            )}
          </section>

          <section className="panel" aria-label="运行信息">
            <div className="runtime-grid">
              <span>资料库</span>
              <strong>{status?.runtimeInfo.musicLibraryRoot ?? '加载中'}</strong>
              <span>服务地址</span>
              <strong>
                {status
                  ? `${status.runtimeInfo.serverHost}:${status.runtimeInfo.serverPort}`
                  : '加载中'}
              </strong>
            </div>
          </section>
        </>
      ) : (
        <section className="panel" aria-label="资料库浏览">
          <div className="panel-heading">
            <h2>{libraryDirectory?.path || '根目录'}</h2>
            <div className="panel-actions">
              {libraryDirectory?.path ? (
                <button
                  type="button"
                  className="secondary-action"
                  onClick={() => {
                    void loadLibrary(parentLibraryPath(libraryDirectory.path))
                  }}
                >
                  上级
                </button>
              ) : null}
              <button
                type="button"
                className="secondary-action"
                onClick={() => {
                  void loadLibrary(libraryDirectory?.path ?? '')
                }}
              >
                刷新
              </button>
            </div>
          </div>
          {libraryDirectory ? (
            <div className="library-list">
              {libraryDirectory.folders.map((folder) => (
                <div key={folder.path} className="library-row folder-row">
                  <button
                    type="button"
                    className="library-name-action"
                    onClick={() => {
                      void loadLibrary(folder.path)
                    }}
                  >
                    {folder.name}
                  </button>
                  <button
                    type="button"
                    className="secondary-action"
                    onClick={() => {
                      void addLibraryFolder(folder.path)
                    }}
                  >
                    添加 {folder.name}
                  </button>
                </div>
              ))}
              {libraryDirectory.files.map((file) => (
                <div key={file.path} className="library-row file-row">
                  <span>{file.name}</span>
                  <button
                    type="button"
                    className="secondary-action"
                    onClick={() => {
                      void addLibraryFile(file.path)
                    }}
                  >
                    添加 {file.name}
                  </button>
                </div>
              ))}
              {!libraryDirectory.folders.length && !libraryDirectory.files.length ? (
                <p className="empty-state">资料库为空</p>
              ) : null}
            </div>
          ) : (
            <p className="empty-state">加载中</p>
          )}
        </section>
      )}
    </main>
  )
}

export default App
