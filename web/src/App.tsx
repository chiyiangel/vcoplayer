import { useEffect, useState } from 'react'
import './App.css'

type PlaybackState = 'idle' | 'playing' | 'paused' | 'stopped' | 'unsupported'

type PlayerStatus = {
  playbackState: PlaybackState
  nowPlaying: string | null
  playbackList: string[]
  selectedOutputDevice: string | null
  failureReason: string | null
  runtimeInfo: {
    musicLibraryRoot: string
    serverHost: string
    serverPort: number
  }
}

const playbackStateText: Record<PlaybackState, string> = {
  idle: '空闲',
  playing: '播放中',
  paused: '已暂停',
  stopped: '已停止',
  unsupported: '不支持',
}

function App() {
  const [status, setStatus] = useState<PlayerStatus | null>(null)

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

  return (
    <main className="remote-shell">
      <header className="remote-header">
        <div>
          <p className="eyebrow">VCO Player</p>
          <h1>播放</h1>
        </div>
        <nav className="remote-tabs" aria-label="主视图">
          <button type="button" className="active">
            播放
          </button>
          <button type="button">资料库</button>
        </nav>
      </header>

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
            {status.playbackList.map((item, index) => (
              <li key={`${item}-${index}`}>{item}</li>
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
    </main>
  )
}

export default App
