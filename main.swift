import AppKit
import AVFoundation
import CoreMotion
import MediaPlayer
import ServiceManagement
import Speech

// Calibration: degrees of head turn from center to screen edge, and cursor smoothing (0-1, higher = snappier).
let yawRange = 30.0, pitchRange = 18.0, smoothing = 0.12
// Tilt scrolling: degrees of ear-to-shoulder tilt before scrolling starts, pixels per update per extra degree,
// and direction (flip to -1 if tilting right scrolls up).
let tiltDeadzone = 10.0, tiltSpeed = 2.0, tiltSign = 1.0

func cursorPoint(yaw: Double, pitch: Double, in f: CGRect) -> CGPoint {
    let nx = max(-1, min(1, -yaw * 180 / .pi / yawRange))   // turn left = cursor left
    let ny = max(-1, min(1, -pitch * 180 / .pi / pitchRange)) // look up = cursor up (CG origin is top-left)
    return CGPoint(x: min(f.maxX - 1, f.midX + nx * f.width / 2), y: min(f.maxY - 1, f.midY + ny * f.height / 2))
}

// A command only counts when said on its own, so "go back to the..." in conversation doesn't fire "back".
let commands: Set<String> = ["rightclick", "click", "unhold", "hold", "recenter", "recentre", "scrolldown", "scrollup",
                             "next", "back", "zoom", "stop", "handsoff"]
func command(in text: String) -> String? {
    let t = text.lowercased().filter(\.isLetter)
    return commands.contains(t) ? t : nil
}

if CommandLine.arguments.contains("--selftest") {
    let f = CGRect(x: 0, y: 0, width: 1000, height: 500)
    precondition(cursorPoint(yaw: 0, pitch: 0, in: f) == CGPoint(x: 500, y: 250))
    precondition(cursorPoint(yaw: 1, pitch: -1, in: f) == CGPoint(x: 0, y: 499))
    precondition(command(in: "Right click") == "rightclick" && command(in: "click") == "click")
    precondition(command(in: "un-hold") == "unhold" && command(in: "Re center.") == "recenter" && command(in: "scroll Down") == "scrolldown")
    precondition(command(in: "clicking") == nil && command(in: "go back") == nil && command(in: "Hands-off") == "handsoff")
    print("ok"); exit(0)
}

// Magnet: snap to the nearest clickable element within this many points of where your head is pointing.
let magnetRadius = 40.0
let pressable: Set<String> = ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuItem", "AXMenuBarItem", "AXMenuButton", "AXDisclosureTriangle"]
let systemWide = AXUIElementCreateSystemWide()
AXUIElementSetMessagingTimeout(systemWide, 0.05) // a hung app must not freeze the cursor

func buttonFrame(at p: CGPoint) -> CGRect? {
    var el: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success, var e = el else { return nil }
    for _ in 0..<3 { // the hit is often a label inside the button
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v) == .success, let role = v as? String, pressable.contains(role) {
            var pv: CFTypeRef?, sv: CFTypeRef?, o = CGPoint.zero, s = CGSize.zero
            guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
                  AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success,
                  AXValueGetValue(pv as! AXValue, .cgPoint, &o), AXValueGetValue(sv as! AXValue, .cgSize, &s),
                  s.width <= 300, s.height <= 120 else { return nil } // big rows/cells would yank the cursor far away
            return CGRect(origin: o, size: s)
        }
        guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &v) == .success, let v else { return nil }
        e = v as! AXUIElement
    }
    return nil
}

func magnet(_ t: CGPoint) -> CGPoint {
    let probes = [CGPoint.zero] + (0..<8).map { i in CGPoint(x: cos(Double(i) * .pi / 4) * magnetRadius, y: sin(Double(i) * .pi / 4) * magnetRadius) }
    let centers = probes.compactMap { buttonFrame(at: CGPoint(x: t.x + $0.x, y: t.y + $0.y)) }.map { CGPoint(x: $0.midX, y: $0.midY) }
    return centers.min { hypot($0.x - t.x, $0.y - t.y) < hypot($1.x - t.x, $1.y - t.y) } ?? t
}

let screen = { CGDisplayBounds(CGMainDisplayID()) }
var pos = CGPoint(x: screen().midX, y: screen().midY)
var reference: CMAttitude?
var holding = false
var active = false // off until "hands off"; stem presses and media keys go back to other apps meanwhile

func post(_ type: CGEventType, _ button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: button)?.post(tap: .cghidEventTap)
}
func leftClick() { post(.leftMouseDown); post(.leftMouseUp) }
func rightClick() { post(.rightMouseDown, .right); post(.rightMouseUp, .right) }

let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

let motion = CMHeadphoneMotionManager()
FileHandle.standardError.write("accessibility=\(trusted) motionAvailable=\(motion.isDeviceMotionAvailable) motionAuth=\(CMHeadphoneMotionManager.authorizationStatus().rawValue)\n".data(using: .utf8)!)
var logged = false
motion.startDeviceMotionUpdates(to: .main) { m, e in
    if let e { FileHandle.standardError.write("motion error: \(e)\n".data(using: .utf8)!) }
    guard active, let a = m?.attitude else { return }
    if !logged { logged = true; FileHandle.standardError.write("motion ok\n".data(using: .utf8)!) }
    if reference == nil { reference = a.copy() as? CMAttitude }
    a.multiply(byInverseOf: reference!)
    let tilt = a.roll * 180 / .pi * tiltSign
    if abs(tilt) > tiltDeadzone { // tilt right = scroll down; the cursor holds still meanwhile
        scroll(Int32((abs(tilt) - tiltDeadzone) * tiltSpeed) * (tilt > 0 ? -1 : 1), .pixel)
        return
    }
    let t = magnet(cursorPoint(yaw: a.yaw, pitch: a.pitch, in: screen()))
    pos.x += (t.x - pos.x) * smoothing
    pos.y += (t.y - pos.y) * smoothing
    post(holding ? .leftMouseDragged : .mouseMoved)
}

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
func recenter() { reference = nil; pos = CGPoint(x: screen().midX, y: screen().midY) }
func scroll(_ n: Int32, _ units: CGScrollEventUnit = .line) {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1, wheel1: n, wheel2: 0, wheel3: 0) else { return }
    e.location = pos // scroll goes to the window under this point
    e.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }
}

func run(_ c: String) {
    log("heard \(c)")
    guard active else { if c == "handsoff" { setActive(true) }; return }
    switch c {
    case "rightclick": rightClick()
    case "click": leftClick()
    case "hold": if !holding { holding = true; post(.leftMouseDown) }
    case "unhold": if holding { holding = false; post(.leftMouseUp) }
    case "recenter", "recentre": recenter()
    case "scrolldown": scroll(-5)
    case "scrollup": scroll(5)
    case "next": key(124) // right arrow: next image in Photos, Preview, Quick Look and most galleries
    case "back": key(123) // left arrow
    case "zoom": key(28, [.maskAlternate, .maskCommand]) // ⌥⌘8 toggles macOS Zoom, which zooms around the pointer
    case "stop": setActive(false)
    default: break
    }
}

let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
var request: SFSpeechAudioBufferRecognitionRequest?
var task: SFSpeechRecognitionTask?

var idle: DispatchWorkItem?

// Recognition restarts after each command and after a pause, so the transcript only holds the current utterance.
func listen() {
    idle?.cancel()
    task?.cancel()
    let r = SFSpeechAudioBufferRecognitionRequest()
    r.shouldReportPartialResults = true
    r.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    r.contextualStrings = ["click", "right click", "hold", "unhold", "recenter", "scroll down", "scroll up", "next", "back", "zoom", "stop", "hands off"]
    request = r
    task = recognizer.recognitionTask(with: r) { result, error in
        DispatchQueue.main.async {
            guard request === r else { return } // callback from a task we already replaced
            idle?.cancel()
            idle = DispatchWorkItem(block: listen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: idle!)
            if let text = result?.bestTranscription.formattedString, let c = command(in: text) { run(c); listen() }
            else if let error { log("speech error: \(error.localizedDescription)"); request = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: listen) }
            else if result?.isFinal == true { listen() }
        }
    }
}

// Stem presses arrive as media commands; macOS only routes them to the "now playing" app, hence the audio engine.
let engine = AVAudioEngine()
_ = engine.mainMixerNode
let mic = engine.inputNode
mic.installTap(onBus: 0, bufferSize: 1024, format: mic.outputFormat(forBus: 0)) { buf, _ in request?.append(buf) }
do { try engine.start() } catch { log("audio error: \(error)") }
SFSpeechRecognizer.requestAuthorization { s in
    log("speechAuth=\(s.rawValue) onDevice=\(recognizer.supportsOnDeviceRecognition)")
    if s == .authorized { DispatchQueue.main.async(execute: listen) }
}
MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "HandsOff"]
MPNowPlayingInfoCenter.default().playbackState = .playing

let rc = MPRemoteCommandCenter.shared()
func on(_ c: MPRemoteCommand, _ f: @escaping () -> Void) { c.isEnabled = true; c.addTarget { _ in f(); return .success } }
on(rc.togglePlayPauseCommand, leftClick)
on(rc.playCommand, leftClick)
on(rc.pauseCommand, leftClick)
on(rc.nextTrackCommand, rightClick)
on(rc.previousTrackCommand, recenter)

// Menu bar: the icon is dimmed while off.
class MenuActions: NSObject {
    @objc func toggle() { setActive(!active) }
    @objc func recenterNow() { recenter() }
    @objc func toggleLogin(_ i: NSMenuItem) {
        let svc = SMAppService.mainApp
        do { try svc.status == .enabled ? svc.unregister() : svc.register() } catch { log("login item error: \(error)") }
        i.state = svc.status == .enabled ? .on : .off
    }
}
let actions = MenuActions()
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "airpods", accessibilityDescription: "HandsOff")
let menu = NSMenu()
let toggleItem = menu.addItem(withTitle: "", action: #selector(MenuActions.toggle), keyEquivalent: "")
menu.addItem(withTitle: "Recenter", action: #selector(MenuActions.recenterNow), keyEquivalent: "")
menu.addItem(.separator())
let loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(MenuActions.toggleLogin(_:)), keyEquivalent: "")
loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
for i in menu.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = actions }
statusItem.menu = menu

func setActive(_ on: Bool) {
    active = on
    log("active=\(on)")
    if on { recenter() } else if holding { holding = false; post(.leftMouseUp) }
    for c in [rc.togglePlayPauseCommand, rc.playCommand, rc.pauseCommand, rc.nextTrackCommand, rc.previousTrackCommand] { c.isEnabled = on }
    MPNowPlayingInfoCenter.default().playbackState = on ? .playing : .stopped
    statusItem.button?.appearsDisabled = !on
    toggleItem.title = on ? "Turn Off (say “stop”)" : "Turn On (say “hands off”)"
}
setActive(false)

NSApplication.shared.setActivationPolicy(.accessory)
NSApp.run()
