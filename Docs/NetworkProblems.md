# Network Problems — JustTwo iOS

Документ описывает диагностику проблем с загрузкой приложения, связанных с сетью до `api.jtwo.online`, и принятые меры на клиенте.

## Симптомы

- Splash зависает на «Загрузка пользователя» или «Загружаем чаты…»
- Помогает включение VPN
- На сервере **нет** записей в nginx/access log во время fail
- После VPN запросы появляются в логах (`GET /me HTTP/1.1 200`)

## Что выявлено

### 1. Запрос не доходит до сервера

При неуспешной загрузке nginx не видит `GET /me`. При успешной — видит.

**Вывод:** проблема на пути **клиент → DNS → маршрут → TLS → nginx**, а не в Vapor/PostgreSQL.

### 2. VPN меняет маршрут, не «стратегию приложения»

В логах iOS при включении VPN появляется интерфейс `utun6` и IP `77.239.107.143:443`. После этого тот же код, тот же `primary` URLSession, тот же хост — ответ за ~1–4 секунды.

**Вывод:** VPN меняет DNS и/или маршрут (часто IPv4 через туннель), а не логику приложения.

### 3. Ошибка — timeout (-1001), не DNS lookup failed

Типичные логи без VPN:

```
URLError code=-1001 (timedOut) url=https://api.jtwo.online/me
_kCFStreamErrorCodeKey=-2102
tcp_output ... state=CLOSED
```

Это **black hole**: TCP/TLS начинается, ответа нет, соединение закрывается. Часто оператор/DPI/битый IPv6-путь.

### 4. Стратегии URLSession не меняют маршрут

`primary` → `ephemeral` → `forcedFresh` → `lastResort` — это разные `URLSession` к **одному** `https://api.jtwo.online`. При полностью битом маршруте все стратегии падают одинаково.

Полный цикл 4 стратегий × ~20s ≈ **74 секунды** ожидания без пользы.

### 5. Ложный след: `withTimeout(15s)` на splash (исправлено)

Ранее splash оборачивал `/me` в `withTimeout(15s)`, что **отменяло** URLSession и мешало `NetworkExecutor` переключать стратегии. В логах это выглядело как `NSURLErrorCancelled` («отменено»), хотя причина — наш таймер.

**Статус:** убрано. Splash auth использует отдельный fast-fail flow.

## Принятые меры на клиенте

### Splash critical path

1. **`/me` и `/profile/me`** — `NetworkStrategy.splashFlow` (2 попытки, timeout **10s** каждая, ~21s max вместо ~74s).
2. **Чаты и аватары** — снова **блокируют** splash (`await warmupAuthenticatedHome`): список диалогов, фото профиля, critical avatar preload.
3. **Префетч сообщений** — в фоне после входа (как раньше).

### Сеть

- `waitsForConnectivity = false` на API-сессиях — fail-fast вместо бесконечного ожидания.
- `URLErrorDiagnostics` — логирует код ошибки (`-1001`, `-1003`, …) и URL.
- `ImageDownloadClient` — отдельная сессия и логи для `storage.yandexcloud.net`.

### UX при ошибке

- Тексты: «Не удаётся подключиться к серверу», совет про другую сеть / VPN.
- **`NetworkPathMonitor`** — при смене сети (в т.ч. включение VPN) splash **автоматически** retry, если показана ошибка.

### Realtime

- Дедупликация `connectIfPossible` / `syncConversationListSubscriptions` в `MessengerRealtimeCoordinator`.

## Файлы

| Файл | Роль |
|------|------|
| `SplashViewModel.swift` | Flow splash, fast auth, auto-retry |
| `SplashStartupPolicy.swift` | `authStrategies` = splashFlow |
| `NetworkStrategy.swift` | `splashFlow`, splash sessions |
| `URLSessionProvider.swift` | splashPrimary / splashEphemeral (10s) |
| `NetworkPathMonitor.swift` | auto-retry при смене пути |
| `AppStartupCoordinator.swift` | warmup: чаты + critical avatars на splash |
| `URLErrorDiagnostics.swift` | разбор NSError в логах |
| `ImageDownloadClient.swift` | загрузка аватаров с логами |

## Как диагностировать

### На устройстве (DEBUG)

1. Смотреть фазу: `Splash phase → loadingUser` / `loadingChats`.
2. Код ошибки: `URLError code=-1001 (timedOut)` vs `-1003 (cannotFindHost)`.
3. Переключение стратегий: `switching strategy → splashEphemeral`.
4. Auto-retry: `Splash auto-retry: network path changed`.

### На сервере

```bash
sudo tail -f /var/log/nginx/access.log | grep "GET /me"
sudo journalctl -u justtwo-api.service -f --no-pager
```

| Наблюдение | Интерпретация |
|------------|---------------|
| Нет записей при fail | Пакеты не доходят до nginx |
| Есть 200, быстро | Сервер OK, проблема была на клиентском маршруте |
| Есть запись, долго/5xx | Проблема на сервере |

### Вне приложения

- Safari: `https://api.jtwo.online/health` без VPN
- `nslookup api.jtwo.online` — сравнить IP с VPN и без

## Пути решения

### Клиент (сделано / возможно дальше)

- [x] Fast-fail на splash auth (~21s)
- [x] Auto-retry при смене сети
- [x] Чаты + critical avatars на splash
- [x] Логирование URLError codes
- [ ] Опционально: `NWPathMonitor` «нет сети» до первого запроса
- [ ] Опционально: кнопка «Скопировать диагностику» в UI ошибки

### Инфраструктура (если проблема массовая в РФ)

1. Проверить **A/AAAA** для `api.jtwo.online` — отключить AAAA при битом IPv6.
2. CDN или **запасной домен** (другой IP/SNI).
3. Проверить IP сервера (`77.239.107.143`) на блокировки у мобильных операторов.
4. Мониторинг доступности с разных ASN.

## Хронология инцидента (2026-06-30)

1. Splash зависал, помогал VPN.
2. Логи: все 4 стратегии `-1001 timedOut`, сервер молчит.
3. `withTimeout(15s)` маскировал проблему как «отменено» — исправлено.
4. После VPN: `GET /me` 200 за 3.65s, nginx видит запрос.
5. Корневая причина: **маршрут до API без VPN**, не код приложения.

## Связанные документы

- Backend API: `JustTwoBackend/Docs/API.md`
- Operations: `JustTwoBackend/Docs/OPERATIONS.md`
