import AppKit
import Foundation

// ── 設定 ────────────────────────────────────────────────────────────────
// ~/.config/cryptobar/config.json，不存在時自動建立預設檔
struct Config: Codable {
    var symbols: [String]        // Binance 交易對，如 BTCUSDT
    var pinned: [String]         // 直接顯示在選單列上的（其餘只在下拉選單裡）
    var refreshSeconds: Double
    var lang: String?            // "hant" 繁體 / "hans" 简体；舊設定檔沒有這欄位時預設繁體
    var exchange: String?        // "binance" / "okx"；各交易所價格會有差異
    var theme: String?           // "system" / "light" / "dark"

    static let fallback = Config(
        symbols: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT"],
        pinned: ["BTCUSDT", "ETHUSDT"],
        refreshSeconds: 15,
        lang: "hant",
        exchange: "binance",
        theme: "system"
    )

    static var path: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cryptobar/config.json")
    }

    func save() {
        let url = Config.path
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: url) }
    }

    static func load() -> Config {
        let url = path
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        // 首次啟動：寫出預設設定，方便使用者自己改
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(fallback) {
            try? data.write(to: url)
        }
        return fallback
    }
}

/// 介面文案：繁體 / 简体
enum L10n {
    static var lang = "hant"

    private static let table: [String: (String, String)] = [
        "loading":    ("載入中…", "载入中…"),
        "nodata":     ("無資料", "无数据"),
        "offline":    ("離線", "离线"),
        "updated":    ("更新於 %@", "更新于 %@"),
        "refresh":    ("立即重新整理", "立即刷新"),
        "coins":      ("幣種", "币种"),
        "pin":        ("在選單列顯示", "在菜单栏显示"),
        "quotes":     ("即時行情", "实时行情"),
        "tracking":   ("追蹤中", "追踪中"),
        "popular":    ("常用", "常用"),
        "custom":     ("自訂…", "自定义…"),
        "quit":       ("結束", "退出"),
        "empty":      ("（尚未加入幣種）", "（尚未添加币种）"),
        "addTitle":   ("加入幣種", "添加币种"),
        "addInfo":    ("輸入幣種代號，例如 WLD 或 WLDUSDT。\n會向 Binance 驗證是否存在。",
                       "输入币种代号，例如 WLD 或 WLDUSDT。\n会向 Binance 验证是否存在。"),
        "add":        ("加入", "添加"),
        "cancel":     ("取消", "取消"),
        "notFound":   ("找不到 %@", "找不到 %@"),
        "notFoundIn": ("Binance 上沒有這個交易對，請確認代號。", "Binance 上没有这个交易对，请确认代号。"),
        "exchange":   ("交易所", "交易所"),
        "autostart":  ("開機時啟動", "开机时启动"),
        "theme":      ("外觀", "外观"),
        "system":     ("跟隨系統", "跟随系统"),
        "light":      ("淺色", "浅色"),
        "dark":       ("深色", "深色"),
        "language":   ("語言", "语言"),
        "hant":       ("繁體中文", "繁体中文"),
        "hans":       ("簡體中文", "简体中文"),
    ]

    static func t(_ key: String) -> String {
        guard let pair = table[key] else { return key }
        return lang == "hans" ? pair.1 : pair.0
    }
}

/// 選單裡直接可勾的常用幣種；不在清單裡的用「自訂…」輸入
let popularSymbols: [String] = [
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT",
    "ADAUSDT", "TRXUSDT", "AVAXUSDT", "LINKUSDT", "TONUSDT", "SUIUSDT",
]

func baseName(_ symbol: String) -> String {
    for quote in ["USDT", "USDC", "FDUSD", "BUSD", "TUSD"] where symbol.hasSuffix(quote) {
        return String(symbol.dropLast(quote.count))
    }
    return symbol
}

// ── 行情 ────────────────────────────────────────────────────────────────
struct Ticker {
    let symbol: String
    let price: Double
    let changePercent: Double

    /// BTCUSDT -> BTC
    var base: String {
        for quote in ["USDT", "USDC", "FDUSD", "BUSD", "TUSD"] where symbol.hasSuffix(quote) {
            return String(symbol.dropLast(quote.count))
        }
        return symbol
    }
}

private struct BinanceTicker: Decodable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
}

private struct OKXResponse: Decodable {
    struct Row: Decodable {
        let instId: String
        let last: String
        let open24h: String
    }
    let data: [Row]
}

enum Exchange: String, CaseIterable {
    case binance, okx

    var display: String { self == .binance ? "Binance" : "OKX" }

    /// 內部一律用 Binance 式代號（BTCUSDT）存設定，送出前才轉成各家格式
    func symbol(_ canonical: String) -> String {
        switch self {
        case .binance: return canonical
        case .okx:     return "\(baseName(canonical))-\(quoteName(canonical))"
        }
    }
}

func quoteName(_ symbol: String) -> String {
    for quote in ["USDT", "USDC", "FDUSD", "BUSD", "TUSD"] where symbol.hasSuffix(quote) {
        return quote
    }
    return "USDT"
}

enum Feed {
    static func fetch(_ symbols: [String], on exchange: Exchange,
                      completion: @escaping ([Ticker]?) -> Void) {
        guard !symbols.isEmpty else { completion([]); return }
        switch exchange {
        case .binance: fetchBinance(symbols, completion)
        case .okx:     fetchOKX(symbols, completion)
        }
    }

    /// Binance 支援一次帶多個交易對，一個請求就夠
    private static func fetchBinance(_ symbols: [String], _ completion: @escaping ([Ticker]?) -> Void) {
        guard let list = try? JSONSerialization.data(withJSONObject: symbols),
              let json = String(data: list, encoding: .utf8),
              let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbols=\(encoded)")
        else { completion(nil); return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let raw = try? JSONDecoder().decode([BinanceTicker].self, from: data)
            else { completion(nil); return }

            let bySymbol = Dictionary(uniqueKeysWithValues: raw.map { ($0.symbol, $0) })
            completion(symbols.compactMap { sym in
                guard let t = bySymbol[sym],
                      let p = Double(t.lastPrice),
                      let c = Double(t.priceChangePercent) else { return nil }
                return Ticker(symbol: sym, price: p, changePercent: c)
            })
        }.resume()
    }

    /// OKX 的批次端點會回傳全市場（上千筆、數 MB），15 秒刷一次太浪費，
    /// 改成逐個查詢並行送出；幣種數量通常個位數，實測比拉全市場快。
    private static func fetchOKX(_ symbols: [String], _ completion: @escaping ([Ticker]?) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var result: [String: Ticker] = [:]
        var anyFailure = false

        for sym in symbols {
            let inst = Exchange.okx.symbol(sym)
            guard let url = URL(string: "https://www.okx.com/api/v5/market/ticker?instId=\(inst)")
            else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10

            group.enter()
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let resp = try? JSONDecoder().decode(OKXResponse.self, from: data),
                      let row = resp.data.first,
                      let last = Double(row.last),
                      let open = Double(row.open24h), open > 0
                else { lock.lock(); anyFailure = true; lock.unlock(); return }

                // OKX 只給 24h 開盤價，漲跌幅自己算
                let change = (last - open) / open * 100
                lock.lock()
                result[sym] = Ticker(symbol: sym, price: last, changePercent: change)
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .global()) {
            let ordered = symbols.compactMap { result[$0] }
            completion(ordered.isEmpty && anyFailure ? nil : ordered)
        }
    }
}

// ── 格式化 ──────────────────────────────────────────────────────────────
enum Fmt {
    /// 價格跨度很大（BTC 六位數、PEPE 小數點後六位），依量級決定小數位。
    /// - compact: 選單列用，壓寬度；下拉選單用 false，給足精度。
    static func price(_ v: Double, compact: Bool = false) -> String {
        let digits: Int
        if compact {
            switch abs(v) {
            case 10000...:    digits = 0
            case 100..<10000: digits = 1
            case 1..<100:     digits = 2
            case 0.01..<1:    digits = 4
            default:          digits = 6
            }
        } else {
            // 交易所回傳幾位就顯示幾位（上限 8），不足兩位補到兩位。
            // 直接寫死更多位數只會補出一串沒有意義的零 ——
            // Binance BTC/USDT 的最小報價單位就是 0.01。
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 8
            f.roundingMode = .halfUp
            return f.string(from: NSNumber(value: v)) ?? "\(v)"
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func change(_ v: Double) -> String {
        String(format: "%@%.2f%%", v >= 0 ? "+" : "", v)
    }
}

extension NSColor {
    /// 選單背景在淺色模式偏白、深色模式偏黑，用同一組顏色會有一邊看不清
    static let up = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.18, green: 0.90, blue: 0.44, alpha: 1)   // 深色底：高明度
            : NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.16, alpha: 1)   // 淺色底：壓深
    }
    static let down = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 1.00, green: 0.33, blue: 0.36, alpha: 1)
            : NSColor(calibratedRed: 0.80, green: 0.05, blue: 0.10, alpha: 1)
    }
}

// ── 自訂選單列（毛玻璃 hover）────────────────────────────────────────
/// 有 view 的 NSMenuItem 不會被系統畫成藍色反白，highlight 完全由我們控制。
final class MenuRowView: NSView {
    private let highlight = NSView()
    private let label = NSTextField(labelWithString: "")
    private let check = NSTextField(labelWithString: "")
    private let accessory = NSTextField(labelWithString: "")
    private var padH: CGFloat = 10
    private let interactive: Bool
    private var inset: CGFloat = 6
    private var rowHeight: CGFloat = 24

    /// - checkmark: nil 表示這列沒有勾選欄（例如行情列）
    init(text: NSAttributedString, checkmark: Bool?, interactive: Bool, trailing: String? = nil) {
        self.interactive = interactive
        super.init(frame: .zero)

        let checkWidth: CGFloat = checkmark == nil ? 0 : 18
        let inset: CGFloat = 6          // 反白色塊左右內縮，貼合 macOS 選單觀感
        let padH: CGFloat = 10
        let height: CGFloat = 24
        self.inset = inset
        self.rowHeight = height
        self.padH = padH

        // 系統的 unemphasizedSelectedContentBackgroundColor 疊在半透明選單上太淡，
        // 改用固定濃度的中性灰，看得出是「選中這一列」但不會變成實心色塊。
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 5
        highlight.alphaValue = 0
        addSubview(highlight)

        label.attributedStringValue = text
        label.backgroundColor = .clear
        label.isBordered = false
        label.sizeToFit()
        addSubview(label)

        if let checkmark {
            check.stringValue = checkmark ? "✓" : ""
            // 跟文字同字級，否則兩者的行高不同、視覺基準就對不齊
            check.font = .systemFont(ofSize: 13, weight: .semibold)
            check.textColor = .labelColor
            check.backgroundColor = .clear
            check.isBordered = false
            check.alignment = .center
            check.sizeToFit()
            addSubview(check)
        }

        var accessoryWidth: CGFloat = 0
        if let trailing {
            accessory.stringValue = trailing
            accessory.font = .systemFont(ofSize: 11)
            accessory.textColor = .secondaryLabelColor
            accessory.backgroundColor = .clear
            accessory.isBordered = false
            accessory.sizeToFit()
            accessoryWidth = accessory.frame.width + 12   // 與文字保持間距
            addSubview(accessory)
        }

        let width = inset * 2 + padH * 2 + checkWidth + label.frame.width + accessoryWidth
        wantsLayer = true
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        highlight.frame = NSRect(x: inset, y: 1, width: width - inset * 2, height: height - 2)
        // 兩個欄位各自用自身高度置中，基準才會一致
        let checkH = check.frame.height
        check.frame = NSRect(x: inset + padH - 2, y: (height - checkH) / 2,
                             width: checkWidth, height: checkH)
        label.frame = NSRect(x: inset + padH + checkWidth,
                             y: (height - label.frame.height) / 2,
                             width: label.frame.width, height: label.frame.height)
        layoutAccessory()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layoutAccessory() {
        guard accessory.superview != nil else { return }
        accessory.frame = NSRect(x: frame.width - inset - padH - accessory.frame.width,
                                 y: (rowHeight - accessory.frame.height) / 2,
                                 width: accessory.frame.width, height: accessory.frame.height)
    }

    /// NSMenu 以最寬的一列決定選單寬度，但不會把較窄的 item view 撐開，
    /// 導致短文字那幾列的反白色塊只有文字那麼寬。建完選單後統一拉齊。
    func setRowWidth(_ w: CGFloat) {
        guard w > frame.width else { return }
        frame.size.width = w
        highlight.frame = NSRect(x: inset, y: 1, width: w - inset * 2, height: rowHeight - 2)
        layoutAccessory()
    }

    /// 濃度想調就改這裡：數字越大反白越明顯
    static func highlightColor(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.22)
            : NSColor.black.withAlphaComponent(0.14)
    }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.06      // 反白要跟手，太慢會覺得延遲
            highlight.animator().alphaValue = alpha
        }
    }

    /// 由 NSMenuDelegate 的 willHighlight 驅動。
    /// 不用 NSTrackingArea 的原因：有子選單的項目，滑鼠事件會被 AppKit
    /// 攔去處理子選單展開，mouseEntered 根本收不到。
    /// 改用選單自己的高亮通知，鍵盤上下鍵移動時也會正確反白。
    func setHighlighted(_ on: Bool) {
        guard interactive else { return }
        // cgColor 不會跟著外觀變，且 init 時 view 還沒進視窗、拿不到正確的
        // effectiveAppearance，所以每次要亮之前重新取一次
        if on {
            highlight.layer?.backgroundColor =
                MenuRowView.highlightColor(for: effectiveAppearance).cgColor
        }
        fade(to: on ? 1 : 0)
    }

    override func mouseUp(with event: NSEvent) {
        guard interactive, let item = enclosingMenuItem, let menu = item.menu else { return }
        if item.submenu != nil { return }      // 子選單由系統負責展開，別攔截
        if item.action == nil { return }       // 只亮不做事的列，點了不關選單
        let idx = menu.index(of: item)
        menu.cancelTracking()
        // 等選單關閉再執行，否則跳對話框的動作會卡住
        DispatchQueue.main.async { menu.performActionForItem(at: idx) }
    }
}

/// 把既有 NSMenuItem 換成毛玻璃列
func styled(_ item: NSMenuItem, text: NSAttributedString,
            checkmark: Bool? = nil, trailing: String? = nil,
            highlightOnly: Bool = false) -> NSMenuItem {
    // 子選單的父項本身沒有 action，但仍需要 hover 效果；
    // highlightOnly 用於行情列：要反白，但點了不做任何事
    let interactive = item.action != nil || item.submenu != nil || highlightOnly
    item.view = MenuRowView(text: text, checkmark: checkmark,
                            interactive: interactive, trailing: trailing)
    return item
}

/// 把一個選單裡所有自訂列拉成同寬（取最寬那列）
func equalizeRowWidths(_ menu: NSMenu) {
    let rows = menu.items.compactMap { $0.view as? MenuRowView }
    guard let maxW = rows.map({ $0.frame.width }).max() else { return }
    rows.forEach { $0.setRowWidth(maxW) }
}

func monoText(_ s: String, color: NSColor = .labelColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: color,
    ])
}

func plainText(_ s: String, color: NSColor = .labelColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: color,
    ])
}

// ── 開機自啟 ──────────────────────────────────────────────────────────
enum LaunchAgent {
    static let label = "com.kingwong.cryptobar"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private static var executablePath: String {
        // 裸執行檔沒有 app bundle，Bundle.main.executablePath 仍會給出完整路徑；
        // 保險起見用 argv[0] 補位並轉成絕對路徑
        if let p = Bundle.main.executablePath, p.hasPrefix("/") { return p }
        let arg0 = CommandLine.arguments.first ?? "cryptobar"
        return arg0.hasPrefix("/")
            ? arg0
            : FileManager.default.currentDirectoryPath + "/" + arg0
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        let url = plistURL
        if !on {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        // 刻意不設 KeepAlive：設了的話從選單「結束」會被 launchd 立刻拉回來
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

// ── App ─────────────────────────────────────────────────────────────────
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var config = Config.load()
    private var latest: [Ticker] = []
    private var exchange: Exchange = .binance
    private var theme: String = "system"

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        L10n.lang = config.lang ?? "hant"
        exchange = Exchange(rawValue: config.exchange ?? "binance") ?? .binance
        theme = config.theme ?? "system"
        item.button?.title = L10n.t("loading")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self          // 打開前才填內容，避免刷新時抽換選單吃掉點擊
        item.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: config.refreshSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func refresh() {
        Feed.fetch(config.symbols, on: exchange) { [weak self] tickers in
            DispatchQueue.main.async {
                guard let self else { return }
                if let tickers { self.latest = tickers }
                self.render(ok: tickers != nil)
            }
        }
    }

    private func render(ok: Bool) {
        guard let button = item.button else { return }

        if latest.isEmpty {
            button.title = ok ? L10n.t("nodata") : L10n.t("offline")
            return
        }

        // 選單列標題：只放 pinned 的幾個，價格用等寬字避免每秒跳動
        let shown = latest.filter { config.pinned.contains($0.symbol) }
        let parts = (shown.isEmpty ? Array(latest.prefix(2)) : shown)
        let title = NSMutableAttributedString()
        for (i, t) in parts.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            let arrow = t.changePercent >= 0 ? "▲" : "▼"
            let text = "\(t.base) \(Fmt.price(t.price, compact: true)) \(arrow)"
            title.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: t.changePercent >= 0 ? NSColor.up : NSColor.down,
            ]))
        }
        if !ok {
            title.append(NSAttributedString(string: " ⚠︎", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        button.attributedTitle = title
    }

    /// 選單即將顯示：這時才重建內容。刷新計時器不會碰選單，
    /// 所以使用者瀏覽子選單時不會被抽換掉（先前 toggle 點不動就是這個原因）。
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 子選單共用同一個 delegate，這裡只重建主選單，否則會把子選單內容清空
        guard menu === item.menu else { return }
        menu.appearance = themeAppearance()   // 顯示前套用，切換後立刻生效
        menu.removeAllItems()
        rebuildMenu(into: menu)
    }

    func menu(_ menu: NSMenu, willHighlight highlighted: NSMenuItem?) {
        for mi in menu.items {
            (mi.view as? MenuRowView)?.setHighlighted(mi === highlighted)
        }
    }

    private func rebuildMenu(into menu: NSMenu) {
        menu.addItem(header(L10n.t("quotes")))

        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        for t in latest {
            let name = t.base.padding(toLength: max(6, t.base.count + 1), withPad: " ", startingAt: 0)
            let priceText = Fmt.price(t.price)
            let pad = String(repeating: " ", count: max(1, 14 - priceText.count))
            let arrow = t.changePercent >= 0 ? "▲" : "▼"

            // 反白已改成灰底，彩色文字不會被藍底吃掉，所以整列都能跟著漲跌上色
            let tone = t.changePercent >= 0 ? NSColor.up : NSColor.down
            let line = NSMutableAttributedString(string: "\(name)\(pad)\(priceText)   ", attributes: [
                .font: mono,
                .foregroundColor: tone,
            ])
            line.append(NSAttributedString(string: "\(arrow) \(Fmt.change(t.changePercent))", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: tone,
            ]))

            let mi = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menu.addItem(styled(mi, text: line, highlightOnly: true))
        }
        menu.addItem(.separator())

        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        let updated = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        updated.isEnabled = false
        let line = String(format: L10n.t("updated"), stamp.string(from: Date()))
                 + "  ·  " + exchange.display
        menu.addItem(styled(updated, text: NSAttributedString(string: line, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])))

        let coins = NSMenuItem(title: L10n.t("coins"), action: nil, keyEquivalent: "")
        coins.submenu = buildCoinMenu()
        menu.addItem(styled(coins, text: plainText(L10n.t("coins")), trailing: "▸"))

        let pin = NSMenuItem(title: L10n.t("pin"), action: nil, keyEquivalent: "")
        pin.submenu = buildPinMenu()
        menu.addItem(styled(pin, text: plainText(L10n.t("pin")), trailing: "▸"))

        let refreshItem = NSMenuItem(title: L10n.t("refresh"), action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(styled(refreshItem, text: plainText(L10n.t("refresh"))))
        let exItem = NSMenuItem(title: L10n.t("exchange"), action: nil, keyEquivalent: "")
        exItem.submenu = buildExchangeMenu()
        menu.addItem(styled(exItem, text: plainText(L10n.t("exchange")), trailing: "▸"))

        let auto = NSMenuItem(title: L10n.t("autostart"), action: #selector(toggleAutostart), keyEquivalent: "")
        auto.target = self
        menu.addItem(styled(auto, text: plainText(L10n.t("autostart")),
                            checkmark: LaunchAgent.isEnabled))

        let themeItem = NSMenuItem(title: L10n.t("theme"), action: nil, keyEquivalent: "")
        themeItem.submenu = buildThemeMenu()
        menu.addItem(styled(themeItem, text: plainText(L10n.t("theme")), trailing: "▸"))

        let langItem = NSMenuItem(title: L10n.t("language"), action: nil, keyEquivalent: "")
        langItem.submenu = buildLangMenu()
        menu.addItem(styled(langItem, text: plainText(L10n.t("language")), trailing: "▸"))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.t("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(styled(quitItem, text: plainText(L10n.t("quit"))))

        for mi in menu.items where mi.action != nil && mi.target == nil {
            if mi.action != #selector(NSApplication.terminate(_:)) { mi.target = self }
        }
        equalizeRowWidths(menu)
    }

    /// 分組標題：小字級 + 次要色，沒有 action 所以不會有 hover 效果
    private func header(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        mi.isEnabled = false
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.5,
        ])
        return styled(mi, text: text)
    }

    private func buildCoinMenu() -> NSMenu {
        let m = NSMenu()
        m.appearance = themeAppearance()
        m.delegate = self
        if !config.symbols.isEmpty { m.addItem(header(L10n.t("tracking"))) }
        // 已追蹤的排在最上面，勾選狀態代表「正在追蹤」，點一下移除
        for sym in config.symbols {
            let mi = NSMenuItem(title: baseName(sym), action: #selector(toggleCoin(_:)), keyEquivalent: "")
            mi.representedObject = sym
            mi.target = self
            m.addItem(styled(mi, text: plainText(baseName(sym)), checkmark: true))
        }
        let rest = popularSymbols.filter { !config.symbols.contains($0) }
        if !rest.isEmpty {
            m.addItem(.separator())
            m.addItem(header(L10n.t("popular")))
            for sym in rest {
                let mi = NSMenuItem(title: baseName(sym), action: #selector(toggleCoin(_:)), keyEquivalent: "")
                mi.representedObject = sym
                mi.target = self
                m.addItem(styled(mi, text: plainText(baseName(sym)), checkmark: false))
            }
        }
        m.addItem(.separator())
        let custom = NSMenuItem(title: L10n.t("custom"), action: #selector(addCustomCoin), keyEquivalent: "")
        custom.target = self
        m.addItem(custom)
        equalizeRowWidths(m)
        return m
    }

    private func buildPinMenu() -> NSMenu {
        let m = NSMenu()
        m.appearance = themeAppearance()
        m.delegate = self
        for sym in config.symbols {
            let mi = NSMenuItem(title: baseName(sym), action: #selector(togglePin(_:)), keyEquivalent: "")
            mi.representedObject = sym
            mi.target = self
            m.addItem(styled(mi, text: plainText(baseName(sym)),
                             checkmark: config.pinned.contains(sym)))
        }
        if config.symbols.isEmpty {
            let mi = NSMenuItem(title: L10n.t("empty"), action: nil, keyEquivalent: "")
            mi.isEnabled = false
            m.addItem(mi)
        }
        equalizeRowWidths(m)
        return m
    }

    @objc private func toggleCoin(_ sender: NSMenuItem) {
        guard let sym = sender.representedObject as? String else { return }
        if let idx = config.symbols.firstIndex(of: sym) {
            config.symbols.remove(at: idx)
            config.pinned.removeAll { $0 == sym }      // 移除追蹤時一併取消釘選
            latest.removeAll { $0.symbol == sym }
        } else {
            config.symbols.append(sym)
        }
        config.save()
        render(ok: true)     // 立刻反映移除，不等網路
        refresh()
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let sym = sender.representedObject as? String else { return }
        if let idx = config.pinned.firstIndex(of: sym) {
            config.pinned.remove(at: idx)
        } else {
            config.pinned.append(sym)
        }
        config.save()
        render(ok: true)
    }

    @objc private func addCustomCoin() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.t("addTitle")
        alert.informativeText = L10n.t("addInfo")
        alert.addButton(withTitle: L10n.t("add"))
        alert.addButton(withTitle: L10n.t("cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "WLD"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var sym = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !sym.isEmpty else { return }
        if !["USDT", "USDC", "FDUSD", "BUSD", "TUSD"].contains(where: { sym.hasSuffix($0) }) {
            sym += "USDT"
        }
        if config.symbols.contains(sym) { return }

        // 先驗證再寫入，避免打錯字讓整批查詢都失敗
        Feed.fetch([sym], on: exchange) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result, !result.isEmpty {
                    self.config.symbols.append(sym)
                    self.config.save()
                    self.refresh()
                } else {
                    let a = NSAlert()
                    a.alertStyle = .warning
                    a.messageText = String(format: L10n.t("notFound"), sym)
                    a.informativeText = L10n.t("notFoundIn")
                    a.runModal()
                }
            }
        }
    }

    private func buildExchangeMenu() -> NSMenu {
        let m = NSMenu()
        m.appearance = themeAppearance()
        m.delegate = self
        for ex in Exchange.allCases {
            let mi = NSMenuItem(title: ex.display, action: #selector(setExchange(_:)), keyEquivalent: "")
            mi.representedObject = ex.rawValue
            mi.target = self
            m.addItem(styled(mi, text: plainText(ex.display), checkmark: exchange == ex))
        }
        equalizeRowWidths(m)
        return m
    }

    @objc private func setExchange(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let ex = Exchange(rawValue: raw), ex != exchange else { return }
        exchange = ex
        config.exchange = raw
        config.save()
        latest.removeAll()          // 換家之後價格會變，先清掉避免顯示舊值
        item.button?.title = L10n.t("loading")
        refresh()
    }

    /// nil = 跟隨系統
    private func themeAppearance() -> NSAppearance? {
        switch theme {
        case "light": return NSAppearance(named: .aqua)
        case "dark":  return NSAppearance(named: .darkAqua)
        default:      return nil
        }
    }

    private func buildThemeMenu() -> NSMenu {
        let m = NSMenu()
        m.appearance = themeAppearance()
        m.delegate = self
        for key in ["system", "light", "dark"] {
            let mi = NSMenuItem(title: L10n.t(key), action: #selector(setTheme(_:)), keyEquivalent: "")
            mi.representedObject = key
            mi.target = self
            m.addItem(styled(mi, text: plainText(L10n.t(key)), checkmark: theme == key))
        }
        equalizeRowWidths(m)
        return m
    }

    @objc private func toggleAutostart() {
        LaunchAgent.setEnabled(!LaunchAgent.isEnabled)
    }

    @objc private func setTheme(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        theme = key
        config.theme = key
        config.save()
    }

    private func buildLangMenu() -> NSMenu {
        let m = NSMenu()
        m.appearance = themeAppearance()
        m.delegate = self
        for code in ["hant", "hans"] {
            let mi = NSMenuItem(title: L10n.t(code), action: #selector(setLang(_:)), keyEquivalent: "")
            mi.representedObject = code
            mi.target = self
            m.addItem(styled(mi, text: plainText(L10n.t(code)), checkmark: L10n.lang == code))
        }
        equalizeRowWidths(m)
        return m
    }

    @objc private func setLang(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        L10n.lang = code
        config.lang = code
        config.save()
        render(ok: true)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不進 Dock、不搶焦點
app.run()
