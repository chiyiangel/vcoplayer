import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import App from './App'

const idleStatus = {
  playbackState: 'idle',
  nowPlaying: null,
  playbackList: [],
  selectedOutputDevice: null,
  failureReason: null,
  runtimeInfo: {
    musicLibraryRoot: '/Users/me/Music',
    serverHost: '127.0.0.1',
    serverPort: 8080,
  },
}

const rootDirectory = {
  path: '',
  folders: [{ name: 'Album', path: 'Album' }],
  files: [{ name: 'Intro.flac', path: 'Intro.flac' }],
}

const albumDirectory = {
  path: 'Album',
  folders: [],
  files: [{ name: 'Track 01.wav', path: 'Album/Track 01.wav' }],
}

let currentRootDirectory: typeof rootDirectory

describe('Operator Remote initial status', () => {
  beforeEach(() => {
    currentRootDirectory = rootDirectory
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input)
        let body: typeof idleStatus | typeof rootDirectory | typeof albumDirectory = idleStatus
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
    expect(screen.getByRole('button', { name: '播放' })).toBeTruthy()
    expect(screen.getByRole('button', { name: '资料库' })).toBeTruthy()
    expect(screen.getByText('空闲')).toBeTruthy()
    expect(screen.getByText('播放列表为空')).toBeTruthy()
    expect(screen.getByText('未选择输出设备')).toBeTruthy()
    expect(screen.getByText('/Users/me/Music')).toBeTruthy()
    expect(fetch).toHaveBeenCalledWith('/api/status')
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
