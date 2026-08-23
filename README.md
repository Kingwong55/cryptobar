# Cryptobar

macOS 選單列的虛擬幣即時報價，原生 Swift，零外部依賴。

![icon](docs/icon.png)

## 功能

- **即時報價**：預設 15 秒刷新，選單列顯示釘選的幣種
- **交易所可切換**：Binance / OKX（兩家的價格與 24h 漲跌會有差異）
- **幣種自選**：12 個常用幣一鍵勾選，其餘用「自訂…」輸入代號，送出前會向交易所驗證
- **釘選**：控制哪幾個顯示在選單列上，其餘留在下拉選單
- **外觀**：跟隨系統 / 淺色 / 深色
- **語言**：繁體中文 / 简体中文
- **開機自啟**：寫入使用者層級的 LaunchAgent，可隨時取消

漲跌用顏色 + ▲▼ 雙重標示，不依賴顏色也讀得懂。

## 建置

```bash
./build.sh
```

會編譯、產生圖示、打包成 `~/Applications/Cryptobar.app` 並重新啟動。
需要 Xcode Command Line Tools（`swiftc`、`iconutil`），不需要 Xcode 本體。

## 設定檔

`~/.config/cryptobar/config.json`，選單裡的操作會即時寫回：

```json
{
  "symbols": ["BTCUSDT", "ETHUSDT", "SOLUSDT"],
  "pinned": ["BTCUSDT", "ETHUSDT"],
  "refreshSeconds": 15,
  "exchange": "binance",
  "theme": "system",
  "lang": "hant"
}
```

幣種一律用 Binance 式代號（`BTCUSDT`）儲存，送往 OKX 前才轉成 `BTC-USDT`。

## 實作備忘

- 選單每一列都是自訂 `NSView`，因此反白是灰底而非系統藍底；子選單箭頭與勾選符號都要自己畫
- 反白由 `NSMenuDelegate.menu(_:willHighlight:)` 驅動，不用 `NSTrackingArea` ——
  有子選單的項目，滑鼠事件會被 AppKit 攔去處理展開，收不到 `mouseEntered`
- `NSMenu` 以最寬的列決定選單寬度，但不會撐開較窄的 item view，
  所以建完選單要呼叫 `equalizeRowWidths` 拉齊，否則反白色塊長短不一
- Binance 支援一次查詢多個交易對；OKX 的批次端點會回傳全市場（數 MB），
  改為逐一並行查詢反而更快
- LaunchAgent 刻意不設 `KeepAlive`，否則從選單「結束」會被 launchd 立刻拉回

## 授權

MIT
