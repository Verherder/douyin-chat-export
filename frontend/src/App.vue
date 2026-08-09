<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import ConversationList from './components/ConversationList.vue'
import MessageList from './components/MessageList.vue'
import SearchBar from './components/SearchBar.vue'

const activeConversation = ref(null)
const searchHighlight = ref('')
const jumpToSeq = ref(null)
const sidebarOpen = ref(false)

// Auth
const authChecking = ref(true)
const authenticated = ref(false)
const loginPassword = ref('')
const loginError = ref('')
const authToken = ref(localStorage.getItem('authToken') || localStorage.getItem('panel_token') || '')
const scrapeStatus = ref('idle')
const scrapeStatusText = ref('管理与导出')
let controlStatusTimer = null

function persistAuthToken(token) {
  authToken.value = token
  localStorage.setItem('authToken', token)
  // The viewer and /panel are two frontends served by the same FastAPI app.
  // Keep their token stores in sync so switching pages does not ask for the
  // same password again. The cookie also authenticates file downloads.
  localStorage.setItem('panel_token', token)
  document.cookie = `auth_token=${encodeURIComponent(token)};path=/;max-age=${7 * 24 * 3600};SameSite=Lax`
}

async function loadControlStatus() {
  if (!authenticated.value) return
  try {
    const res = await fetch('/panel/api/status')
    if (!res.ok) return
    const data = await res.json()
    scrapeStatus.value = data.scrape?.status || 'idle'
    scrapeStatusText.value = scrapeStatus.value === 'running'
      ? '正在采集…'
      : scrapeStatus.value === 'failed'
        ? '采集失败 · 查看'
        : '管理与导出'
  } catch {}
}

function startControlStatusPolling() {
  loadControlStatus()
  if (!controlStatusTimer) {
    controlStatusTimer = window.setInterval(loadControlStatus, 5000)
  }
}

async function checkAuth() {
  try {
    const headers = authToken.value ? { Authorization: `Bearer ${authToken.value}` } : {}
    const res = await fetch('/api/auth/check', { headers })
    const data = await res.json()
    if (!data.need_password || data.authenticated) {
      authenticated.value = true
      if (authToken.value) persistAuthToken(authToken.value)
      startControlStatusPolling()
    }
  } catch {}
  authChecking.value = false
}

async function doLogin() {
  loginError.value = ''
  try {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: loginPassword.value }),
    })
    if (!res.ok) {
      loginError.value = '密码错误'
      return
    }
    const data = await res.json()
    persistAuthToken(data.token)
    authenticated.value = true
    startControlStatusPolling()
  } catch {
    loginError.value = '登录失败'
  }
}

// Inject auth token into all fetch requests
const _origFetch = window.fetch
window.fetch = function(url, opts = {}) {
  if (authToken.value && typeof url === 'string' &&
      (url.startsWith('/api/') || url.startsWith('/panel/api/'))) {
    opts.headers = opts.headers || {}
    if (opts.headers instanceof Headers) {
      opts.headers.set('Authorization', `Bearer ${authToken.value}`)
    } else {
      opts.headers['Authorization'] = `Bearer ${authToken.value}`
    }
  }
  return _origFetch.call(this, url, opts)
}

onMounted(checkAuth)
onUnmounted(() => {
  if (controlStatusTimer) window.clearInterval(controlStatusTimer)
})

const themes = [
  { id: 'dark',   label: '深蓝', color: '#1a1a2e' },
  { id: 'wechat', label: '微信', color: '#95ec69' },
  { id: 'light',  label: '浅色', color: '#ffffff' },
  { id: 'warm',   label: '暖棕', color: '#8b5e3c' },
  { id: 'purple', label: '紫夜', color: '#6a2fad' },
]
const currentTheme = ref(localStorage.getItem('theme') || 'dark')
applyTheme(currentTheme.value)

function applyTheme(id) {
  currentTheme.value = id
  document.documentElement.setAttribute('data-theme', id === 'dark' ? '' : id)
  localStorage.setItem('theme', id)
}

function selectConversation(conv) {
  activeConversation.value = conv
  searchHighlight.value = ''
  sidebarOpen.value = false
}

function onConversationDeleted(convId) {
  if (activeConversation.value?.conv_id === convId) {
    activeConversation.value = null
  }
}

function navigateToMessage(item) {
  activeConversation.value = {
    conv_id: item.conv_id,
    name: item.conv_name || '未知',
  }
  searchHighlight.value = item.content?.substring(0, 20) || ''
  jumpToSeq.value = item.seq || null
}
</script>

<template>
  <!-- Loading -->
  <div v-if="authChecking" class="login-screen">
    <div class="login-box">
      <div class="login-loading">Loading...</div>
    </div>
  </div>
  <!-- Login -->
  <div v-else-if="!authenticated" class="login-screen">
    <div class="login-box">
      <div class="login-title">抖音聊天记录</div>
      <div class="login-subtitle">请输入密码</div>
      <form @submit.prevent="doLogin" class="login-form">
        <input
          v-model="loginPassword"
          type="password"
          placeholder="密码"
          class="login-input"
          autofocus
        />
        <button type="submit" class="login-btn">登录</button>
      </form>
      <div v-if="loginError" class="login-error">{{ loginError }}</div>
    </div>
  </div>
  <!-- Main app -->
  <div v-else class="app-layout">
    <div class="sidebar-overlay" :class="{ visible: sidebarOpen }" @click="sidebarOpen = false"></div>
    <div class="app-sidebar" :class="{ open: sidebarOpen }">
      <ConversationList
        :activeId="activeConversation?.conv_id"
        @select="selectConversation"
        @deleted="onConversationDeleted"
      />
    </div>
    <div class="app-main">
      <div class="app-toolbar">
        <button class="sidebar-toggle" @click="sidebarOpen = !sidebarOpen">☰</button>
        <div class="app-title">抖音聊天记录</div>
        <SearchBar @navigate="navigateToMessage" />
        <a
          class="control-center-btn"
          :class="`status-${scrapeStatus}`"
          href="/panel"
          aria-label="打开管理与导出控制面板"
          title="采集、定时任务、导出、媒体下载与登录设置"
        >
          <span class="control-status-dot"></span>
          <span class="control-center-label">{{ scrapeStatusText }}</span>
        </a>
        <div class="theme-switcher">
          <button
            v-for="t in themes"
            :key="t.id"
            class="theme-btn"
            :class="{ active: currentTheme === t.id }"
            :title="t.label"
            :style="{ background: t.color }"
            @click="applyTheme(t.id)"
          />
        </div>
      </div>
      <MessageList
        :conversation="activeConversation"
        :searchHighlight="searchHighlight"
        :jumpToSeq="jumpToSeq"
        @jumped="jumpToSeq = null"
      />
    </div>
  </div>
</template>

<style scoped>
.login-screen {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  background: var(--bg-primary);
}
.login-box {
  text-align: center;
  padding: 40px;
  background: var(--bg-secondary);
  border-radius: 16px;
  border: 1px solid var(--border-color);
  min-width: 300px;
}
.login-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--accent);
  margin-bottom: 6px;
}
.login-subtitle {
  font-size: 14px;
  color: var(--text-muted);
  margin-bottom: 24px;
}
.login-form {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.login-input {
  padding: 10px 14px;
  border: 1px solid var(--border-color);
  border-radius: 8px;
  background: var(--bg-primary);
  color: var(--text-primary);
  font-size: 15px;
  outline: none;
  text-align: center;
}
.login-input:focus {
  border-color: var(--accent);
}
.login-btn {
  padding: 10px;
  border: none;
  border-radius: 8px;
  background: var(--accent);
  color: #fff;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  transition: filter 0.15s;
}
.login-btn:hover {
  filter: brightness(1.15);
}
.login-error {
  margin-top: 12px;
  color: #ff4d4f;
  font-size: 13px;
}
.login-loading {
  color: var(--text-muted);
  font-size: 14px;
}

.app-layout {
  display: flex;
  height: 100vh;
}

.app-sidebar {
  width: 300px;
  flex-shrink: 0;
}

.app-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
  overflow: hidden;
}

.app-toolbar {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 11px 20px;
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border-color);
}

.app-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 15px;
  font-weight: 600;
  white-space: nowrap;
  color: var(--text-primary);
  letter-spacing: 0.01em;
}
.app-title::before {
  content: "";
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: var(--accent);
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--accent) 20%, transparent);
}

.app-toolbar .search-container {
  flex: 1;
  max-width: 400px;
}

.control-center-btn {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  min-height: 32px;
  padding: 0 12px;
  border: 1px solid var(--border-color);
  border-radius: 8px;
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
  transition: border-color 0.15s, color 0.15s, filter 0.15s;
}

.control-center-btn:hover {
  border-color: var(--accent);
  color: var(--accent);
  filter: brightness(1.08);
}

.control-status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--text-muted);
}

.control-center-btn.status-running .control-status-dot {
  background: #e2b23c;
  animation: controlPulse 1.5s infinite;
}

.control-center-btn.status-completed .control-status-dot {
  background: #4dd08a;
}

.control-center-btn.status-failed .control-status-dot {
  background: #ff5c6c;
}

@keyframes controlPulse {
  50% { opacity: 0.35; }
}

.theme-switcher {
  display: flex;
  gap: 6px;
  align-items: center;
  margin-left: auto;
}

.theme-btn {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  border: 1px solid rgba(255, 255, 255, 0.15);
  cursor: pointer;
  transition: transform 0.15s, box-shadow 0.15s;
  padding: 0;
}

.theme-btn:hover {
  transform: scale(1.15);
}

.theme-btn.active {
  transform: scale(1.1);
  box-shadow: 0 0 0 2px var(--bg-secondary), 0 0 0 4px var(--accent);
}

.sidebar-toggle {
  display: none;
  background: none;
  border: none;
  color: var(--text-primary);
  font-size: 22px;
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 4px;
  flex-shrink: 0;
}
.sidebar-toggle:hover {
  background: var(--bg-tertiary);
}

.sidebar-overlay {
  display: none;
}

@media (max-width: 768px) {
  .sidebar-toggle {
    display: block;
  }

  .app-sidebar {
    position: fixed;
    left: 0;
    top: 0;
    height: 100vh;
    z-index: 1000;
    transform: translateX(-100%);
    transition: transform 0.25s ease;
    width: 280px;
  }

  .app-sidebar.open {
    transform: translateX(0);
  }

  .sidebar-overlay {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    z-index: 999;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.25s ease;
  }

  .sidebar-overlay.visible {
    opacity: 1;
    pointer-events: auto;
  }

  .app-toolbar {
    flex-wrap: wrap;
    padding: 8px 12px;
    gap: 8px;
  }

  .app-title {
    flex: 1;
    font-size: 14px;
  }

  .theme-switcher {
    order: 0;
    margin-left: 0;
    gap: 5px;
  }

  .app-toolbar .search-container {
    order: 1;
    flex-basis: 100%;
    max-width: none;
  }

  .control-center-label {
    display: none;
  }

  .control-center-btn::after {
    content: '管理';
  }
}
</style>
