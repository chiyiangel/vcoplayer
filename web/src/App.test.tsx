import { render, screen } from '@testing-library/react'
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

describe('Operator Remote initial status', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify(idleStatus), {
        headers: { 'Content-Type': 'application/json' },
      })),
    )
  })

  afterEach(() => {
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
})
