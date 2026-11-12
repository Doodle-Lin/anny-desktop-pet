import AppKit
import Darwin

struct PetError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

final class Atlas {
    let config: [String: String]
    let columns: Int
    let rows: Int
    let width: Int
    let height: Int
    private let bitmap: NSBitmapImageRep
    private var images: [Int: NSImage] = [:]
    private var boundsCache: [Int: NSRect] = [:]
    let actions = ["idle", "walkRight", "walkLeft", "wave", "jump", "sad", "wait", "think", "review", "eat", "sleep"]

    init(root: URL) throws {
        let ini = try String(contentsOf: root.appendingPathComponent("pet.ini"), encoding: .utf8)
        var parsed: [String: String] = [:]
        for raw in ini.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { parsed[parts[0]] = parts[1] }
        }
        config = parsed
        columns = Int(parsed["columns"] ?? "8") ?? 8
        rows = Int(parsed["rows"] ?? "13") ?? 13
        guard columns == 8, rows >= 13, rows <= 64 else { throw PetError("素材需要 8 列、至少 13 行") }
        let file = root.appendingPathComponent(parsed["image"] ?? "pet.png")
        guard let rep = NSBitmapImageRep(data: try Data(contentsOf: file)), rep.hasAlpha,
              rep.pixelsWide % columns == 0, rep.pixelsHigh % rows == 0 else {
            throw PetError("素材必须是带透明通道且尺寸能整除网格的 PNG")
        }
        bitmap = rep
        width = rep.pixelsWide / columns
        height = rep.pixelsHigh / rows
        for action in actions {
            guard let row = Int(parsed[action] ?? ""), (0..<rows).contains(row) else { throw PetError("缺少动作: \(action)") }
        }
    }
    func number(_ key: String, _ fallback: Int) -> Int { Int(config[key] ?? "") ?? fallback }
    func count(_ action: String) -> Int { max(1, min(columns, number(action + "Frames", columns))) }
    func rate(_ action: String) -> Double { Double(max(1, min(24, number(action + "Fps", number("fps", 8))))) }
    func row(_ action: String, look: Int = 0) -> Int { action == "look" ? 9 + look / 8 : number(action, 0) }
    func alpha(x: Int, y: Int, column: Int, row: Int) -> CGFloat {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return bitmap.colorAt(x: column * width + x, y: row * height + y)?.alphaComponent ?? 0
    }
    func image(column: Int, row: Int) -> NSImage {
        let key = row * columns + column
        if let cached = images[key] { return cached }
        let rect = CGRect(x: column * width, y: row * height, width: width, height: height)
        let cg = bitmap.cgImage!.cropping(to: rect)!
        let image = NSImage(cgImage: cg, size: NSSize(width: width, height: height))
        images[key] = image
        return image
    }
    func opaqueBounds(column: Int, row: Int) -> NSRect {
        let key = row * columns + column
        if let cached = boundsCache[key] { return cached }
        var left = width, top = height, right = -1, bottom = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x: x, y: y, column: column, row: row) >= 128.0 / 255.0 {
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        }
        let rect = right < left ? NSRect(x: 0, y: 0, width: width, height: height) : NSRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        boundsCache[key] = rect
        return rect
    }
    func destination(action: String, frame: Int, look: Int = 0) -> NSRect {
        let scale = min(192.0 / CGFloat(width), 208.0 / CGFloat(height))
        var rect = NSRect(x: (300 - CGFloat(width) * scale) / 2, y: 160 + (208 - CGFloat(height) * scale) / 2,
                          width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        if action == "sleep" {
            let base = opaqueBounds(column: 0, row: row("idle"))
            let current = opaqueBounds(column: frame, row: row("sleep"))
            rect.origin.x += (base.midX - current.midX) * scale
            rect.origin.y += (base.maxY - current.maxY) * scale
        }
        return rect
    }
}

struct SavedState: Codable {
    var food: Double
    var mood: Double
    var energy: Double
    var timestamp: Double
    var sleeping: Bool?
    var roam: Bool?
    var trackMouse: Bool?
    var blend: Bool?
    var alwaysOnTop: Bool?
    var windowX: Double?
    var windowY: Double?
}

final class PetModel {
    let atlas: Atlas
    var food = 80.0, mood = 80.0, energy = 80.0
    var sleeping = false, roam = true, trackMouse = true, blend = false, moving = true
    var alwaysOnTop = true
    var savedPosition: NSPoint?
    var dragging = false, menuOpen = false, panelVisible = false
    var activity = "", activityLeft = 0.0, animationTime = 0.0, renderedAction = ""
    var hoverGrace = 0.0, wanderLeft = 5.0, pause = 0.0
    var direction = 1
    let dogZone = NSRect(x: 54, y: 160, width: 192, height: 208)
    let panelZone = NSRect(x: 8, y: 8, width: 284, height: 144)
    let corridor = NSRect(x: 8, y: 8, width: 284, height: 360)
    init(_ atlas: Atlas) { self.atlas = atlas }
    static func limit(_ value: Double) -> Double { max(0, min(100, value)) }
    static func lookDirection(_ p: NSPoint) -> Int {
        let angle = atan2(p.x, -p.y) * 180 / .pi
        return Int(((angle < 0 ? angle + 360 : angle) / 22.5).rounded()) % 16
    }
    func begin(_ action: String, loops: Int = 1) {
        sleeping = false; activity = action
        activityLeft = Double(atlas.count(action) * loops) / atlas.rate(action)
        animationTime = 0; renderedAction = action; pause = activityLeft
    }
    func feed() { food = Self.limit(food + 22); mood = Self.limit(mood + 5); begin("eat", loops: 4) }
    func play() { mood = Self.limit(mood + 12); energy = Self.limit(energy - 3); begin("wave") }
    func toggleSleep() { sleeping.toggle(); activityLeft = 0; animationTime = 0; pause = 3 }
    func quickAction(_ index: Int) { if index == 0 { feed() } else if index == 1 { play() } else { toggleSleep() } }
    func hover(_ point: NSPoint, dt: Double) {
        if dogZone.contains(point) || (panelVisible && corridor.contains(point)) || dragging || menuOpen {
            panelVisible = true; hoverGrace = 0.4
        } else {
            hoverGrace = max(0, hoverGrace - dt)
            if hoverGrace == 0 { panelVisible = false }
        }
    }
    func action(mouse: NSPoint) -> (String, Int) {
        if sleeping { return ("sleep", 0) }
        if activityLeft > 0 { return (activity, 0) }
        if dragging { return ("wave", 0) }
        if roam && moving && !menuOpen && !panelVisible && pause <= 0 { return (direction > 0 ? "walkRight" : "walkLeft", 0) }
        let delta = NSPoint(x: mouse.x - 150, y: mouse.y - 245)
        let distance = hypot(delta.x, delta.y)
        if trackMouse && !menuOpen && distance > 30 && distance < 500 { return ("look", Self.lookDirection(delta)) }
        return (food < 20 ? "wait" : "idle", 0)
    }
    @discardableResult func step(_ dt: Double) -> CGFloat {
        food = Self.limit(food - dt * 0.022); mood = Self.limit(mood - dt * 0.012)
        energy = Self.limit(energy + dt * (sleeping ? 0.35 : -0.012)); pause = max(0, pause - dt)
        if !dragging && !menuOpen { activityLeft = max(0, activityLeft - dt); animationTime += dt }
        if roam && !sleeping && !dragging && !menuOpen && !panelVisible && activityLeft <= 0 && pause <= 0 {
            wanderLeft -= dt
            if wanderLeft <= 0 {
                moving.toggle(); wanderLeft = Double.random(in: moving ? 3...7 : 3...6)
                if moving { direction = Bool.random() ? 1 : -1 }
            }
            if moving { return CGFloat(direction) * CGFloat(max(10, min(120, atlas.number("speed", 48)))) * dt }
        }
        return 0
    }
    func save(to url: URL) throws {
        let state = SavedState(food: food, mood: mood, energy: energy, timestamp: Date().timeIntervalSince1970,
                               sleeping: sleeping, roam: roam, trackMouse: trackMouse, blend: blend,
                               alwaysOnTop: alwaysOnTop, windowX: savedPosition.map { Double($0.x) },
                               windowY: savedPosition.map { Double($0.y) })
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(SavedState.self, from: data),
              state.food.isFinite, state.mood.isFinite, state.energy.isFinite, state.timestamp.isFinite else { return }
        let elapsed = max(0, min(28800, Date().timeIntervalSince1970 - state.timestamp))
        food = Self.limit(state.food - elapsed * 0.001); mood = Self.limit(state.mood - elapsed * 0.0005); energy = Self.limit(state.energy)
        sleeping = state.sleeping ?? false; roam = state.roam ?? true
        moving = roam; trackMouse = state.trackMouse ?? true; blend = state.blend ?? false
        alwaysOnTop = state.alwaysOnTop ?? true
        if let x = state.windowX, let y = state.windowY, x.isFinite, y.isFinite {
            savedPosition = NSPoint(x: x, y: y)
        } else { savedPosition = nil }
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    let model: PetModel
    var showMenu: ((NSEvent) -> Void)?
    var clampWindow: (() -> Void)?
    var mouse = NSPoint(x: -1000, y: -1000)
    var dragStart = NSPoint.zero, windowStart = NSPoint.zero
    var moved = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    static let ink = NSColor(srgbRed: 25/255, green: 23/255, blue: 49/255, alpha: 1)
    static let cyan = NSColor(srgbRed: 23/255, green: 232/255, blue: 243/255, alpha: 1)
    static let colors = [NSColor(srgbRed: 1, green: 218/255, blue: 51/255, alpha: 1), NSColor(srgbRed: 1, green: 79/255, blue: 139/255, alpha: 1), NSColor(srgbRed: 64/255, green: 239/255, blue: 173/255, alpha: 1)]
    init(model: PetModel) { self.model = model; super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 380)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func button(_ i: Int) -> NSRect { NSRect(x: 20 + i * 88, y: 111, width: 80, height: 28) }
    func pose() -> (action: String, look: Int, frame: Int, row: Int, rect: NSRect) {
        let (action, look) = model.action(mouse: mouse)
        if model.renderedAction != action { model.renderedAction = action; model.animationTime = 0 }
        let frame = action == "look" ? look % 8 : Int(model.animationTime * model.atlas.rate(action)) % model.atlas.count(action)
        return (action, look, frame, model.atlas.row(action, look: look), model.atlas.destination(action: action, frame: frame, look: look))
    }
    func interactive(at point: NSPoint) -> Bool {
        if model.dragging || model.menuOpen || (model.panelVisible && model.corridor.contains(point)) { return true }
        let p = pose()
        guard p.rect.contains(point) else { return false }
        let x = Int((point.x - p.rect.minX) * CGFloat(model.atlas.width) / p.rect.width)
        let y = Int((point.y - p.rect.minY) * CGFloat(model.atlas.height) / p.rect.height)
        return model.atlas.alpha(x: x, y: y, column: p.frame, row: p.row) > 0.05
    }
    func renderScene() {
        let p = pose()
        NSGraphicsContext.current?.imageInterpolation = .high
        model.atlas.image(column: p.frame, row: p.row).draw(in: p.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if model.blend && p.action != "look" {
            let position = model.animationTime * model.atlas.rate(p.action)
            let fraction = position - floor(position)
            if fraction > 0.65 {
                let next = (p.frame + 1) % model.atlas.count(p.action)
                let rect = model.atlas.destination(action: p.action, frame: next)
                model.atlas.image(column: next, row: p.row).draw(in: rect, from: .zero, operation: .sourceOver, fraction: (fraction - 0.65) / 0.35 * 0.65, respectFlipped: true, hints: nil)
            }
        }
        if model.panelVisible { drawPanel() }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        renderScene()
    }
    func box(_ rect: NSRect, _ color: NSColor) {
        color.setFill(); rect.fill(); Self.ink.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)); path.lineWidth = 2; path.stroke()
    }
    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 12, bold: Bool = false) {
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: Self.ink])
    }
    func drawPanel() {
        NSGraphicsContext.current?.shouldAntialias = false
        Self.ink.setFill(); NSRect(x: 14, y: 14, width: 280, height: 142).fill()
        box(NSRect(x: 8, y: 8, width: 280, height: 140), NSColor(srgbRed: 1, green: 253/255, blue: 238/255, alpha: 1))
        box(NSRect(x: 8, y: 8, width: 280, height: 42), Self.cyan)
        Self.ink.setFill()
        for rect in [NSRect(x: 22, y: 24, width: 7, height: 7), NSRect(x: 32, y: 19, width: 7, height: 7), NSRect(x: 42, y: 24, width: 7, height: 7), NSRect(x: 29, y: 33, width: 14, height: 8)] { rect.fill() }
        NSGraphicsContext.current?.shouldAntialias = true
        label(model.atlas.config["name"] ?? "Anny", x: 59, y: 13, size: 25, bold: true)
        label("右键 · 更多", x: 213, y: 26, size: 10)
        let values = [model.food, model.mood, model.energy]
        let labels = ["饱食", "心情", "精力"]
        let buttons = ["喂食", "摸摸", model.sleeping ? "唤醒" : "睡觉"]
        for i in 0..<3 {
            let x = CGFloat(20 + i * 88)
            label(labels[i], x: x, y: 61, bold: true); label(String(Int(values[i].rounded())), x: x + 54, y: 61, size: 11)
            box(NSRect(x: x, y: 83, width: 76, height: 14), .white)
            Self.colors[i].setFill()
            for j in 0..<Int((values[i] / 10).rounded()) { NSRect(x: x + 3 + CGFloat(j * 7), y: 86, width: 5, height: 8).fill() }
            box(button(i), button(i).contains(mouse) ? Self.cyan : Self.colors[i])
            label(buttons[i], x: x + 28, y: 117, bold: true)
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if model.panelVisible && model.panelZone.contains(p) {
            for i in 0..<3 where button(i).contains(p) { model.quickAction(i) }
            needsDisplay = true; return
        }
        guard interactive(at: p) else { return }
        model.dragging = true; moved = false; dragStart = NSEvent.mouseLocation; windowStart = window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard model.dragging else { return }
        let p = NSEvent.mouseLocation
        let delta = NSPoint(x: p.x - dragStart.x, y: p.y - dragStart.y)
        if abs(delta.x) + abs(delta.y) > 4 { moved = true }
        window?.setFrameOrigin(NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard model.dragging else { return }
        model.dragging = false; clampWindow?()
        if !moved { model.play() }
    }
    override func rightMouseDown(with event: NSEvent) { showMenu?(event) }
    func snapshot(to url: URL) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 380, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw PetError("无法创建预览") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.translateBy(x: 0, y: 380); context.cgContext.scaleBy(x: 1, y: -1)
        // Mark this context flipped so NSImage's respectFlipped path matches the live NSView.
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        draw(bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw PetError("无法保存预览") }
        try data.write(to: url)
        return rep
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: PetPanel!
    var pet: PetView!
    var model: PetModel!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var last = ProcessInfo.processInfo.systemUptime, saveElapsed = 0.0
    var stateURL: URL!
    var lockFD: Int32 = -1
    var ownsInstanceLock = false
    var lastSaveError = ""
    var motionRemainder: CGFloat = 0
    let testing = CommandLine.arguments.contains("--smoke-test")
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let resources = Bundle.main.resourceURL!.appendingPathComponent("assets")
            let atlas = try Atlas(root: resources)
            model = PetModel(atlas)
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnnyDesktop")
            stateURL = support.appendingPathComponent("state.json")
            if !testing {
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                lockFD = open(support.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
                guard lockFD >= 0 else { throw PetError("无法创建应用锁文件") }
                if flock(lockFD, LOCK_EX | LOCK_NB) != 0 { NSApp.terminate(nil); return }
                ownsInstanceLock = true
                model.load(from: stateURL)
            }
            panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 380), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = model.alwaysOnTop ? .floating : .normal; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
            pet = PetView(model: model); panel.contentView = pet
            pet.clampWindow = { [weak self] in self?.clamp() }
            let menu = makeMenu(); menu.delegate = self
            pet.showMenu = { [weak self] event in
                guard let self = self else { return }
                NSMenu.popUpContextMenu(menu, with: event, for: self.pet)
            }
            if let position = model.savedPosition {
                panel.setFrameOrigin(position); clamp()
            } else { resetPosition() }
            panel.orderFrontRegardless()
            if testing {
                try smoke()
                print("PASS: macOS native window/render, sprites, hover, click-through, feeding x4, sleep alignment, movement, gaze, save/load")
                NSApp.terminate(nil); return
            }
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "🐾"; statusItem.button?.toolTip = "Anny 桌宠"; statusItem.menu = menu
            last = ProcessInfo.processInfo.systemUptime
            let ticker = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            timer = ticker; RunLoop.main.add(ticker, forMode: .common)
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        } catch {
            fputs("Anny: \(error)\n", stderr)
            if testing { exit(1) }
            let alert = NSAlert(); alert.messageText = "Anny 启动失败"; alert.informativeText = String(describing: error); alert.runModal()
            NSApp.terminate(nil)
        }
    }
    func save() {
        model.savedPosition = panel?.frame.origin ?? model.savedPosition
        do { try model.save(to: stateURL); lastSaveError = "" }
        catch { lastSaveError = String(describing: error); NSLog("Anny save failed: %@", lastSaveError) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if !testing && lockFD >= 0 {
            // Only the instance holding the lock owns this save.
            if ownsInstanceLock && model != nil { save() }
            close(lockFD)
        }
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let commands = [("喂食（四口）", "feed"), ("摸摸 / 玩耍", "play"), ("挥爪打招呼", "wave"), ("跳一下", "jump"), ("受挫 / 安慰", "sad"), ("等你回来", "wait"), ("认真思考", "think"), ("好奇观察", "review"), ("睡觉 / 唤醒", "sleep"), ("自由走动", "roam"), ("休息时看鼠标", "gaze"), ("帧间柔化（可能有重影）", "blend"), ("保持置顶", "top"), ("找回 Anny", "reset"), ("关于 / 存档状态", "about"), ("退出", "quit")]
        for (title, command) in commands {
            let item = NSMenuItem(title: title, action: #selector(command(_:)), keyEquivalent: command == "quit" ? "q" : "")
            item.target = self; item.representedObject = command; menu.addItem(item)
        }
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.menuOpen = true
        for item in menu.items {
            let command = item.representedObject as? String ?? ""
            let checked = command == "roam" ? model.roam : command == "gaze" ? model.trackMouse : command == "blend" ? model.blend : command == "sleep" ? model.sleeping : command == "top" ? panel.level == .floating : false
            item.state = checked ? .on : .off
        }
    }
    func menuDidClose(_ menu: NSMenu) { model.menuOpen = false }
    @objc func command(_ sender: NSMenuItem) {
        switch sender.representedObject as? String ?? "" {
        case "feed": model.feed()
        case "play": model.play()
        case "sleep": model.toggleSleep()
        case "roam": model.roam.toggle(); model.moving = model.roam; model.wanderLeft = 4
        case "gaze": model.trackMouse.toggle()
        case "blend": model.blend.toggle()
        case "top": model.alwaysOnTop.toggle(); panel.level = model.alwaysOnTop ? .floating : .normal
        case "reset": resetPosition()
        case "quit": NSApp.terminate(nil)
        case "about":
            let alert = NSAlert(); alert.messageText = "Anny Desktop 4.1.0 · macOS"
            alert.informativeText = "离线桌宠 · 拖动狗狗移动，单击摸摸，悬停显示互动卡片。\n素材位于 Anny.app/Contents/Resources/assets。\n存档：\(stateURL.path)\n" + (lastSaveError.isEmpty ? "存档正常" : "上次存档失败：\(lastSaveError)")
            alert.runModal()
        default: model.begin(sender.representedObject as? String ?? "idle")
        }
        if !testing { save() }
        pet.needsDisplay = true
    }
    func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 340, y: screen.visibleFrame.minY + 20)); clamp()
    }
    @objc func screenChanged() { clamp() }
    static func constrainedOrigin(_ rect: NSRect, in area: NSRect) -> NSPoint {
        NSPoint(x: max(area.minX, min(rect.minX, area.maxX - rect.width)),
                y: max(area.minY, min(rect.minY, area.maxY - rect.height)))
    }
    @discardableResult func clamp(origin: NSPoint? = nil) -> Bool {
        var rect = panel.frame
        if let origin = origin { rect.origin = origin }
        let screen = NSScreen.screens.max { a, b in
            let aa = a.visibleFrame.intersection(rect), bb = b.visibleFrame.intersection(rect)
            return (aa.isNull ? 0 : aa.width * aa.height) < (bb.isNull ? 0 : bb.width * bb.height)
        } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return false }
        let constrained = Self.constrainedOrigin(rect, in: area)
        panel.setFrameOrigin(constrained)
        // AppKit may round window coordinates. Only actual bounds clipping is a collision.
        return abs(constrained.x - rect.minX) > 0.000001
    }
    func moveHorizontally(_ delta: CGFloat) {
        guard delta != 0 else { motionRemainder = 0; return }
        if motionRemainder * delta < 0 { motionRemainder = 0 }
        motionRemainder += delta
        let pixels = motionRemainder.rounded(.towardZero)
        guard pixels != 0 else { return }
        motionRemainder -= pixels
        let origin = panel.frame.origin
        if clamp(origin: NSPoint(x: origin.x + pixels, y: origin.y)) {
            model.direction *= -1
            motionRemainder = 0
        }
    }
    @objc func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.2, max(0, now - last)); last = now
        pet.mouse = pet.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        model.hover(pet.mouse, dt: dt)
        let delta = model.step(dt)
        moveHorizontally(delta)
        panel.ignoresMouseEvents = !pet.interactive(at: pet.mouse)
        pet.needsDisplay = true
        saveElapsed += dt
        if saveElapsed >= 30 { saveElapsed = 0; save() }
    }
    func smoke() throws {
        func check(_ passed: Bool, _ message: String) throws { if !passed { throw PetError("Smoke: " + message) } }
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ANNY_QA_DIR"] ?? FileManager.default.currentDirectoryPath + "/qa-macos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try check(!panel.isOpaque && panel.backgroundColor == .clear && !panel.hasShadow, "transparent window")
        try check(panel.level == .floating && panel.styleMask.contains(.nonactivatingPanel), "nonactivating floating panel")
        model.roam = false; model.trackMouse = false; model.food = 40; model.feed()
        let duration = Double(model.atlas.count("eat")) / model.atlas.rate("eat") * 4
        try check(abs(model.activityLeft - duration) < 0.001 && model.food == 62, "four bites")
        model.step(duration - 0.05); try check(model.action(mouse: .zero).0 == "eat", "feeding still running")
        model.step(0.06); try check(model.activityLeft == 0 && model.action(mouse: .zero).0 == "idle" && model.food <= 62, "feeding completion")
        for (p, d) in [(NSPoint(x: 0, y: -100), 0), (NSPoint(x: 100, y: 0), 4), (NSPoint(x: 0, y: 100), 8), (NSPoint(x: -100, y: 0), 12)] {
            try check(PetModel.lookDirection(p) == d, "gaze cardinal")
        }
        model.hover(NSPoint(x: 150, y: 250), dt: 0.016); try check(model.panelVisible, "hover show")
        model.hover(NSPoint(x: 50, y: 120), dt: 0.6); try check(model.panelVisible, "hover card reachable")
        model.hover(NSPoint(x: -100, y: -100), dt: 0.5); try check(!model.panelVisible, "hover hide")
        try check(!pet.interactive(at: NSPoint(x: 1, y: 1)), "blank click-through")
        model.begin("idle"); model.activityLeft = 0
        let idle = try pet.snapshot(to: dir.appendingPathComponent("rest.png"))
        for y in 0..<150 { for x in 0..<300 { try check((idle.colorAt(x: x, y: y)?.alphaComponent ?? 1) == 0, "rest UI must be transparent") } }
        var alphaMismatch = 0, visiblePixels = 0
        for y in 0..<208 {
            for x in 0..<192 {
                let expected = model.atlas.alpha(x: x, y: y, column: 0, row: model.atlas.row("idle"))
                let actual = idle.colorAt(x: 54 + x, y: 160 + y)?.alphaComponent ?? 0
                if actual > 0.5 { visiblePixels += 1 }
                if abs(expected - actual) > 0.1 { alphaMismatch += 1 }
            }
        }
        try check(visiblePixels > 5000 && alphaMismatch < 100, "sprite orientation and alpha pixels: \(alphaMismatch)")
        model.panelVisible = true
        let hover = try pet.snapshot(to: dir.appendingPathComponent("hover.png"))
        try check((hover.colorAt(x: 16, y: 16)?.alphaComponent ?? 0) > 0.9, "panel rendered")
        model.panelVisible = false
        for action in model.atlas.actions {
            for frame in 0..<model.atlas.count(action) {
                model.begin(action); model.animationTime = Double(frame) / model.atlas.rate(action)
                _ = try pet.snapshot(to: dir.appendingPathComponent("\(action)-\(frame).png"))
            }
        }
        let base = model.atlas.opaqueBounds(column: 0, row: model.atlas.row("idle"))
        let scale = min(192.0 / CGFloat(model.atlas.width), 208.0 / CGFloat(model.atlas.height))
        let idleDest = model.atlas.destination(action: "idle", frame: 0)
        for frame in 0..<model.atlas.count("sleep") {
            let bounds = model.atlas.opaqueBounds(column: frame, row: model.atlas.row("sleep"))
            let dst = model.atlas.destination(action: "sleep", frame: frame)
            try check(abs(dst.midX + (bounds.midX - CGFloat(model.atlas.width) / 2) * scale - (idleDest.minX + base.midX * scale)) < 0.01, "sleep center")
            try check(abs(dst.minY + bounds.maxY * scale - (idleDest.minY + base.maxY * scale)) < 0.01, "sleep ground")
        }
        model.activityLeft = 0; model.sleeping = false; model.trackMouse = true; model.roam = false
        for i in 0..<16 {
            let angle = Double(i) * .pi / 8
            pet.mouse = NSPoint(x: 150 + sin(angle) * 100, y: 245 - cos(angle) * 100)
            try check(pet.pose().look == i, "look direction \(i)")
            _ = try pet.snapshot(to: dir.appendingPathComponent("look-\(i).png"))
        }
        model.trackMouse = false; model.roam = true; model.moving = true; model.direction = 1; model.pause = 0; model.wanderLeft = 10
        var distance: CGFloat = 0
        for _ in 0..<60 { distance += model.step(1.0 / 60.0) }
        try check(abs(distance - CGFloat(max(10, min(120, model.atlas.number("speed", 48))))) < 0.01, "movement timing")
        // Exercise the real NSWindow, whose coordinate rounding is not modeled by PetModel.
        if let screen = NSScreen.main {
            let start = NSPoint(x: (screen.visibleFrame.midX - 150).rounded(), y: (screen.visibleFrame.midY - 190).rounded())
            for direction in [-1, 1] {
                panel.setFrameOrigin(start); motionRemainder = 0; model.direction = direction
                let initialX = panel.frame.minX
                for _ in 0..<60 { moveHorizontally(CGFloat(direction) * 0.8) }
                try check(abs(panel.frame.minX - initialX - CGFloat(direction) * 48) <= 1, "real window movement in direction \(direction)")
                try check(model.direction == direction, "no spurious turn while moving")
            }
            moveHorizontally(0)
            try check(motionRemainder == 0, "clear movement remainder when paused")
        }
        let area = NSRect(x: 0, y: 0, width: 1440, height: 900)
        for direction in [-1, 1] {
            model.direction = direction
            let delta = model.step(1.0 / 60.0)
            let requested = NSRect(x: 400 + delta, y: 100, width: 300, height: 380)
            try check(Self.constrainedOrigin(requested, in: area).x == requested.minX, "subpixel movement must not bounce")
            try check(model.action(mouse: .zero).0 == (direction > 0 ? "walkRight" : "walkLeft"), "movement sprite direction")
        }
        try check(Self.constrainedOrigin(NSRect(x: -0.8, y: 100, width: 300, height: 380), in: area).x == 0, "left edge collision")
        try check(Self.constrainedOrigin(NSRect(x: 1140.8, y: 100, width: 300, height: 380), in: area).x == 1140, "right edge collision")
        model.dragging = true; try check(model.step(0.1) == 0, "drag pause"); model.dragging = false
        model.toggleSleep(); let energy = model.energy
        try check(model.step(0.1) == 0 && model.energy > energy, "sleep stops movement")
        model.quickAction(2); try check(!model.sleeping, "wake")
        model.food = 40; model.quickAction(0); try check(model.food == 62 && abs(model.activityLeft - duration) < 0.001, "quick feed")
        model.mood = 40; model.quickAction(1); try check(model.mood == 52 && model.activity == "wave", "quick play")
        let temp = dir.appendingPathComponent("test-state.json")
        try model.save(to: temp); model.food = 0; model.load(from: temp); try check(model.food > 61.9, "state roundtrip")
        model.sleeping = true; model.roam = false; model.trackMouse = false
        model.blend = true; model.alwaysOnTop = false; model.savedPosition = NSPoint(x: -120, y: 240)
        try model.save(to: temp)
        let restored = PetModel(model.atlas); restored.load(from: temp)
        try check(restored.sleeping && !restored.roam && !restored.trackMouse && restored.blend && !restored.alwaysOnTop, "preferences roundtrip")
        try check(restored.savedPosition == NSPoint(x: -120, y: 240), "position roundtrip")
        try Data("{\"food\":70,\"mood\":80,\"energy\":90,\"timestamp\":0}".utf8).write(to: temp)
        let legacy = PetModel(model.atlas); legacy.load(from: temp)
        try check(legacy.roam && legacy.trackMouse && !legacy.sleeping && legacy.alwaysOnTop && legacy.savedPosition == nil, "legacy state defaults")
        try FileManager.default.removeItem(at: temp)
        try "PASS\n".write(to: dir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
