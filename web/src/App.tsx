import { useEffect, useState } from 'react'
import './App.css'

type PlaybackState = 'idle' | 'playing' | 'paused' | 'stopped' | 'unsupported'

type PlayerStatus = {
  playbackState: PlaybackState
  nowPlaying: string | null
  playbackList: PlaybackListItem[]
  selectedOutputDevice: string | null
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

function App() {
  const [status, setStatus] = useState<PlayerStatus | null>(null)
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

    void loadStatus()

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

  async function addLibraryFolder(path: string) {
    const response = await fetch('/api/playback-list/folders', {
      method: 'POST',
      body: JSON.stringify({ path }),
    })
    const nextStatus = (await response.json()) as PlayerStatus
    setStatus(nextStatus)
  }

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
              <strong>{status?.nowPlaying ?? '无'}</strong>
            </div>
          </section>

          <section className="panel" aria-label="输出设备">
            <div className="status-row">
              <span>输出设备</span>
              <strong>{status?.selectedOutputDevice ?? '未选择输出设备'}</strong>
            </div>
          </section>

          <section className="panel" aria-label="播放列表">
            <div className="panel-heading">
              <h2>播放列表</h2>
              <span>{status?.playbackList.length ?? 0}</span>
            </div>
            {status?.playbackList.length ? (
              <ol className="playback-list">
                {status.playbackList.map((item) => (
                  <li key={item.itemId}>{item.path}</li>
                ))}
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
