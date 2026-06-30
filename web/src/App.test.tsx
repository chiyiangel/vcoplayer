import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import App from './App'

type MockPlayerStatus = {
  playbackState: 'idle' | 'playing' | 'paused' | 'stopped' | 'unsupported'
  nowPlaying: string | null
  nowPlayingItemId: string | null
  playbackList: { itemId: string; path: string }[]
  selectedOutputDevice: { id: string; name: string } | null
  progress: { elapsedSeconds: number; durationSeconds: number | null } | null
  failureReason: string | null
  runtimeInfo: {
    musicLibraryRoot: string
    serverHost: string
    serverPort: number
  }
}

type MockLibraryDirectory = {
  path: string
  folders: { name: string; path: string }[]
  files: { name: string; path: string }[]
}

type MockOutputDevice = {
  id: string
  name: string
}

const idleStatus: MockPlayerStatus = {
  playbackState: 'idle',
  nowPlaying: null,
  nowPlayingItemId: null,
  playbackList: [],
  selectedOutputDevice: null,
  progress: null,
  failureReason: null,
  runtimeInfo: {
    musicLibraryRoot: '/Users/me/Music',
    serverHost: '127.0.0.1',
    serverPort: 8080,
  },
}

const outputDevices: MockOutputDevice[] = [
  { id: 'coreaudio:41', name: 'USB DAC' },
  { id: 'coreaudio:55', name: 'Built-in Output' },
]

const statusWithOutputDevice: MockPlayerStatus = {
  ...idleStatus,
  selectedOutputDevice: outputDevices[0],
}

const playingStatus: MockPlayerStatus = {
  ...statusWithOutputDevice,
  playbackState: 'playing',
  nowPlaying: 'Intro.flac',
  nowPlayingItemId: 'item-1',
  playbackList: [{ itemId: 'item-1', path: 'Intro.flac' }],
  progress: { elapsedSeconds: 37, durationSeconds: 182.5 },
}

const pausedStatus: MockPlayerStatus = {
  ...playingStatus,
  playbackState: 'paused',
  progress: { elapsedSeconds: 42, durationSeconds: 182.5 },
}

const navigationStatus: MockPlayerStatus = {
  ...statusWithOutputDevice,
  playbackState: 'playing',
  nowPlaying: 'Intro.flac',
  nowPlayingItemId: 'item-1',
  playbackList: [
    { itemId: 'item-1', path: 'Intro.flac' },
    { itemId: 'item-2', path: 'Second.wav' },
  ],
  progress: { elapsedSeconds: 2, durationSeconds: 182.5 },
}

const nextStatus: MockPlayerStatus = {
  ...navigationStatus,
  nowPlaying: 'Second.wav',
  nowPlayingItemId: 'item-2',
  progress: { elapsedSeconds: 0, durationSeconds: 205 },
}

const previousStatus: MockPlayerStatus = {
  ...navigationStatus,
  nowPlaying: 'Intro.flac',
  nowPlayingItemId: 'item-1',
  progress: { elapsedSeconds: 0, durationSeconds: 182.5 },
}

const unsupportedStatus: MockPlayerStatus = {
  ...statusWithOutputDevice,
  playbackState: 'unsupported',
  nowPlaying: 'Lossy.m4a',
  nowPlayingItemId: 'item-2',
  playbackList: [{ itemId: 'item-2', path: 'Lossy.m4a' }],
  progress: { elapsedSeconds: 5, durationSeconds: null },
  failureReason: 'Unsupported Playback: lossy m4a content cannot preserve Bit Perfect Playback.',
}

const statusWithIntro: MockPlayerStatus = {
  ...idleStatus,
  playbackList: [{ itemId: 'item-1', path: 'Intro.flac' }],
}

const statusWithAlbum: MockPlayerStatus = {
  ...idleStatus,
  playbackList: [{ itemId: 'item-2', path: 'Album/Track 01.wav' }],
}

const deletedSecondStatus: MockPlayerStatus = {
  ...navigationStatus,
  playbackList: [{ itemId: 'item-1', path: 'Intro.flac' }],
}

const clearedActiveStatus: MockPlayerStatus = {
  ...navigationStatus,
  playbackList: [{ itemId: 'item-1', path: 'Intro.flac' }],
}

const rootDirectory: MockLibraryDirectory = {
  path: '',
  folders: [{ name: 'Album', path: 'Album' }],
  files: [{ name: 'Intro.flac', path: 'Intro.flac' }],
}

const albumDirectory: MockLibraryDirectory = {
  path: 'Album',
  folders: [],
  files: [{ name: 'Track 01.wav', path: 'Album/Track 01.wav' }],
}

let currentRootDirectory: typeof rootDirectory
let currentStatus: MockPlayerStatus
let currentOutputDevices: MockOutputDevice[]

describe('Operator Remote initial status', () => {
  beforeEach(() => {
    currentRootDirectory = rootDirectory
    currentStatus = idleStatus
    currentOutputDevices = outputDevices
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input)
        let body: MockPlayerStatus | MockLibraryDirectory | MockOutputDevice[] = currentStatus
        if (url === '/api/devices') {
          body = currentOutputDevices
        }
        if (url === '/api/devices/select' && init?.method === 'POST') {
          body = statusWithOutputDevice
        }
        if (url === '/api/play' && init?.method === 'POST') {
          body = playingStatus
        }
        if (url === '/api/pause' && init?.method === 'POST') {
          body = pausedStatus
        }
        if (url === '/api/next' && init?.method === 'POST') {
          body = nextStatus
        }
        if (url === '/api/previous' && init?.method === 'POST') {
          body = previousStatus
        }
        if (url === '/api/playback-list/select' && init?.method === 'POST') {
          body = nextStatus
        }
        if (url === '/api/playback-list/delete' && init?.method === 'POST') {
          body = deletedSecondStatus
        }
        if (url === '/api/playback-list/clear' && init?.method === 'POST') {
          body = clearedActiveStatus
        }
        if (url === '/api/playback-list/files' && init?.method === 'POST') {
          body = statusWithIntro
        }
        if (url === '/api/playback-list/folders' && init?.method === 'POST') {
          body = statusWithAlbum
        }
        if (url === '/api/library') {
          body = currentRootDirectory
        }
        if (url === '/api/library?path=Album') {
          body = albumDirectory
        }
        return new Response(JSON.stringify(body), {
          headers: { 'Content-Type': 'application/json' },
        })
      }),
    )
  })

  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
  })

  test('renders the idle PlayerStatus from the Remote API', async () => {
    render(<App />)

    expect(await screen.findByRole('heading', { name: '播放' })).toBeTruthy()
    const mainViews = screen.getByRole('navigation', { name: '主视图' })
    expect(within(mainViews).getByRole('button', { name: '播放' })).toBeTruthy()
    expect(within(mainViews).getByRole('button', { name: '资料库' })).toBeTruthy()
    expect(screen.getByText('空闲')).toBeTruthy()
    expect(screen.getByText('播放列表为空')).toBeTruthy()
    expect(screen.getByLabelText('当前输出设备').textContent).toBe('未选择输出设备')
    expect(screen.getByText('/Users/me/Music')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/status')
  })

  test('lists and selects Playback Output Devices from the Remote API', async () => {
    const user = userEvent.setup()

    render(<App />)

    expect((await screen.findByLabelText('当前输出设备')).textContent).toBe('未选择输出设备')
    await user.selectOptions(await screen.findByRole('combobox', { name: '输出设备' }), 'coreaudio:41')

    expect(screen.getByLabelText('当前输出设备').textContent).toBe('USB DAC')
    expect(fetch).toHaveBeenCalledWith('/api/devices')
    expect(fetch).toHaveBeenCalledWith('/api/devices/select', {
      method: 'POST',
      body: JSON.stringify({ deviceId: 'coreaudio:41' }),
    })
  })

  test('shows a missing Playback Output Device state for unavailable selected devices', async () => {
    currentStatus = {
      ...idleStatus,
      selectedOutputDevice: { id: 'coreaudio:missing', name: 'Studio DAC' },
    }

    render(<App />)

    expect((await screen.findByLabelText('当前输出设备')).textContent).toBe('Studio DAC')
    expect(screen.getByLabelText('输出设备缺失状态').textContent).toBe('已选择的输出设备不在当前设备列表中')
    expect(screen.getByRole('combobox', { name: '输出设备' })).toBeTruthy()
  })

  test('shows a missing Playback Output Device state when no output devices are selectable', async () => {
    currentOutputDevices = []

    render(<App />)

    expect((await screen.findByLabelText('当前输出设备')).textContent).toBe('未选择输出设备')
    expect(screen.getByLabelText('输出设备缺失状态').textContent).toBe('未发现输出设备')
    expect((screen.getByRole('combobox', { name: '输出设备' }) as HTMLSelectElement).disabled).toBe(true)
  })

  test('shows Playback Controls and read-only progress from Play and Pause commands', async () => {
    const user = userEvent.setup()

    render(<App />)

    const controls = await screen.findByRole('region', { name: '播放控制' })
    const playButton = within(controls).getByRole('button', { name: '播放' })
    const pauseButton = within(controls).getByRole('button', { name: '暂停' })
    await user.click(playButton)

    expect(screen.getByText('播放中')).toBeTruthy()
    expect(screen.getByLabelText('当前曲目').textContent).toBe('Intro.flac')
    expect(screen.getByLabelText('已播放时间').textContent).toBe('00:37')
    expect(screen.getByLabelText('总时长').textContent).toBe('03:02')
    expect(playButton.getAttribute('aria-pressed')).toBe('true')
    expect(pauseButton.getAttribute('aria-pressed')).toBe('false')
    expect(playButton.className).toBe('primary-action')
    expect(pauseButton.className).toBe('secondary-action')
    expect(fetch).toHaveBeenCalledWith('/api/play', { method: 'POST' })

    await user.click(pauseButton)

    expect(screen.getByText('已暂停')).toBeTruthy()
    expect(screen.getByLabelText('已播放时间').textContent).toBe('00:42')
    expect(playButton.getAttribute('aria-pressed')).toBe('false')
    expect(pauseButton.getAttribute('aria-pressed')).toBe('true')
    expect(playButton.className).toBe('secondary-action')
    expect(pauseButton.className).toBe('primary-action')
    expect(fetch).toHaveBeenCalledWith('/api/pause', { method: 'POST' })
  })

  test('exposes next previous and Playback List Selection actions', async () => {
    const user = userEvent.setup()
    currentStatus = navigationStatus

    render(<App />)

    const controls = await screen.findByRole('region', { name: '播放控制' })
    await user.click(within(controls).getByRole('button', { name: '下一首' }))

    expect(screen.getByLabelText('当前曲目').textContent).toBe('Second.wav')
    expect(screen.getByLabelText('已播放时间').textContent).toBe('00:00')
    expect(fetch).toHaveBeenCalledWith('/api/next', { method: 'POST' })

    await user.click(within(controls).getByRole('button', { name: '上一首' }))

    expect(screen.getByLabelText('当前曲目').textContent).toBe('Intro.flac')
    expect(fetch).toHaveBeenCalledWith('/api/previous', { method: 'POST' })

    const playbackList = screen.getByRole('region', { name: '播放列表' })
    await user.click(within(playbackList).getByRole('button', { name: '播放 Second.wav' }))

    expect(screen.getByLabelText('当前曲目').textContent).toBe('Second.wav')
    expect(fetch).toHaveBeenCalledWith('/api/playback-list/select', {
      method: 'POST',
      body: JSON.stringify({ itemId: 'item-2' }),
    })
  })

  test('supports Playback List delete and clear actions while protecting Now Playing', async () => {
    const user = userEvent.setup()
    currentStatus = navigationStatus

    render(<App />)

    const playbackList = await screen.findByRole('region', { name: '播放列表' })
    expect(
      (within(playbackList).getByRole('button', { name: '删除 Intro.flac' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true)

    await user.click(within(playbackList).getByRole('button', { name: '删除 Second.wav' }))

    expect(screen.queryByText('Second.wav')).toBeNull()
    expect(screen.getByLabelText('当前曲目').textContent).toBe('Intro.flac')
    expect(fetch).toHaveBeenCalledWith('/api/playback-list/delete', {
      method: 'POST',
      body: JSON.stringify({ itemId: 'item-2' }),
    })

    await user.click(within(playbackList).getByRole('button', { name: '清空播放列表' }))

    expect(screen.getByLabelText('当前曲目').textContent).toBe('Intro.flac')
    expect(within(playbackList).getByText('Intro.flac')).toBeTruthy()
    expect(within(playbackList).queryByText('Second.wav')).toBeNull()
    expect(fetch).toHaveBeenCalledWith('/api/playback-list/clear', { method: 'POST' })
  })

  test('shows unknown duration and Playback Failure Reason from PlayerStatus', async () => {
    currentStatus = unsupportedStatus

    render(<App />)

    expect(await screen.findByText('不支持')).toBeTruthy()
    expect(screen.getByLabelText('当前曲目').textContent).toBe('Lossy.m4a')
    expect(screen.getByLabelText('已播放时间').textContent).toBe('00:05')
    expect(screen.getByLabelText('总时长').textContent).toBe('未知')
    expect(screen.getByText('Unsupported Playback: lossy m4a content cannot preserve Bit Perfect Playback.')).toBeTruthy()
  })

  test('renders the Library Browser root from the Remote API', async () => {
    const user = userEvent.setup()

    render(<App />)
    await user.click(screen.getByRole('button', { name: '资料库' }))

    expect(await screen.findByRole('heading', { name: '资料库' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Album' })).toBeTruthy()
    expect(screen.getByText('Intro.flac')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/library')
  })

  test('adds a Library Browser file and shows the updated Playback List', async () => {
    const user = userEvent.setup()

    render(<App />)
    await user.click(screen.getByRole('button', { name: '资料库' }))
    await user.click(await screen.findByRole('button', { name: '添加 Intro.flac' }))
    await user.click(screen.getByRole('button', { name: '播放' }))

    expect(screen.getByText('Intro.flac')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/playback-list/files', {
      method: 'POST',
      body: JSON.stringify({ path: 'Intro.flac' }),
    })
  })

  test('adds a Library Browser folder and shows the updated Playback List', async () => {
    const user = userEvent.setup()

    render(<App />)
    await user.click(screen.getByRole('button', { name: '资料库' }))
    await user.click(await screen.findByRole('button', { name: '添加 Album' }))
    await user.click(screen.getByRole('button', { name: '播放' }))

    expect(screen.getByText('Album/Track 01.wav')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/playback-list/folders', {
      method: 'POST',
      body: JSON.stringify({ path: 'Album' }),
    })
  })

  test('refreshes the visible Library Browser directory on demand', async () => {
    const user = userEvent.setup()

    render(<App />)
    await user.click(screen.getByRole('button', { name: '资料库' }))
    expect(await screen.findByText('Intro.flac')).toBeTruthy()

    currentRootDirectory = {
      path: '',
      folders: [{ name: 'New Album', path: 'New Album' }],
      files: [],
    }
    await user.click(screen.getByRole('button', { name: '刷新' }))

    expect(await screen.findByRole('button', { name: 'New Album' })).toBeTruthy()
    expect(screen.queryByText('Intro.flac')).toBeNull()
  })

  test('enters a Library Browser subfolder and returns upward within the root', async () => {
    const user = userEvent.setup()

    render(<App />)
    await user.click(screen.getByRole('button', { name: '资料库' }))
    await user.click(await screen.findByRole('button', { name: 'Album' }))

    expect(await screen.findByRole('heading', { name: 'Album' })).toBeTruthy()
    expect(screen.getByText('Track 01.wav')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/library?path=Album')

    await user.click(screen.getByRole('button', { name: '上级' }))

    expect(await screen.findByRole('button', { name: 'Album' })).toBeTruthy()
    expect(screen.getByText('Intro.flac')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/library')
  })
})
