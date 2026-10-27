import AppKit
import ServiceManagement

// Locais do Android SDK e das AVDs. Apps abertos pelo Finder não herdam o ~/.zshrc,
// então as variáveis de ambiente são só um extra; o padrão é o caminho do Android Studio.
let home = FileManager.default.homeDirectoryForCurrentUser.path
let env = ProcessInfo.processInfo.environment
let sdkPath = env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"] ?? "\(home)/Library/Android/sdk"
let emulatorPath = "\(sdkPath)/emulator/emulator"
let avdHome = env["ANDROID_AVD_HOME"] ?? "\(home)/.android/avd"
let simDevicesPath = "\(home)/Library/Developer/CoreSimulator/Devices"

struct AVD {
    let name: String
    let displayName: String
}

struct Simulator {
    let udid: String
    let name: String
    let runtime: String
    let booted: Bool
}

// Lê as AVDs direto dos arquivos *.ini, sem abrir o binário do emulador.
func listAVDs() -> [AVD] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: avdHome)) ?? []
    return files.filter { $0.hasSuffix(".ini") }.sorted().map { file in
        let name = String(file.dropLast(4))
        let config = (try? String(contentsOfFile: "\(avdHome)/\(name).avd/config.ini", encoding: .utf8)) ?? ""
        let displayName = config.split(separator: "\n")
            .first { $0.hasPrefix("avd.ini.displayName") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return AVD(name: name, displayName: displayName ?? name.replacingOccurrences(of: "_", with: " "))
    }
}

// Mapeia nome da AVD -> PIDs dos processos do emulador em execução, lendo o `ps`.
func runningEmulators() -> [String: [pid_t]] {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-Ao", "pid=,command="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    guard (try? ps.run()) != nil else { return [:] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()

    var result: [String: [pid_t]] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count > 1, let pid = pid_t(parts[0]) else { continue }
        let command = parts[1]
        guard command.hasSuffix("/emulator") || command.contains("qemu-system") else { continue }
        var name: Substring?
        if let i = parts.firstIndex(of: "-avd"), i + 1 < parts.count {
            name = parts[i + 1]
        } else if let arg = parts.first(where: { $0.hasPrefix("@") }) {
            name = arg.dropFirst()
        }
        if let name { result[String(name), default: []].append(pid) }
    }
    return result
}

// Lê os simuladores iOS dos device.plist do CoreSimulator. O `simctl list` leva segundos,
// esses arquivos são lidos na hora e o campo `state` já diz se o simulador está ligado (3).
func listSimulators(availableRuntimes: Set<String>?) -> [Simulator] {
    let dirs = (try? FileManager.default.contentsOfDirectory(atPath: simDevicesPath)) ?? []
    return dirs.compactMap { dir in
        guard let data = FileManager.default.contents(atPath: "\(simDevicesPath)/\(dir)/device.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let udid = plist["UDID"] as? String, let name = plist["name"] as? String,
              let runtime = plist["runtime"] as? String, runtime.contains(".iOS-"),
              plist["isDeleted"] as? Bool != true,
              availableRuntimes?.contains(runtime) ?? true
        else { return nil }
        return Simulator(udid: udid, name: name, runtime: runtime, booted: plist["state"] as? Int == 3)
    }
}

// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> "iOS 26.5"
func runtimeName(_ id: String) -> String {
    let version = id.split(separator: ".").last ?? Substring(id)
    let parts = version.split(separator: "-")
    return "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
}

func runtimeVersion(_ id: String) -> [Int] {
    (id.split(separator: ".").last ?? "").split(separator: "-").compactMap { Int($0) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    // Runtimes instalados, carregados uma vez em segundo plano para esconder simuladores
    // de runtimes removidos. Até carregar, todos aparecem.
    var availableRuntimes: Set<String>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "DeviceBar")
        image?.isTemplate = true
        statusItem.button?.image = image
        menu.delegate = self
        statusItem.menu = menu
        loadRuntimes()
    }

    func loadRuntimes() {
        run("/usr/bin/xcrun", ["simctl", "list", "runtimes", "available", "-j"]) { status, output in
            guard status == 0,
                  let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
                  let runtimes = json["runtimes"] as? [[String: Any]] else { return }
            self.availableRuntimes = Set(runtimes.compactMap { $0["identifier"] as? String })
        }
    }

    // O menu é montado na hora em que abre, então não há timer nem trabalho em segundo plano.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addAndroidSection()
        addIOSSection()

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Abrir ao iniciar sessão", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        // Seletor próprio em vez de terminate(_:): no macOS 26 o sistema põe um ícone automático
        // no "Sair" padrão, o que desalinha os outros itens do menu.
        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc func quit() { NSApp.terminate(nil) }

    func addAndroidSection() {
        menu.addItem(disabled("Android"))
        guard FileManager.default.isExecutableFile(atPath: emulatorPath) else {
            menu.addItem(disabled("Emulador não encontrado em \(sdkPath)"))
            return
        }
        let avds = listAVDs()
        let running = runningEmulators()
        if avds.isEmpty { menu.addItem(disabled("Nenhuma AVD em \(avdHome)")) }

        for avd in avds {
            if let pids = running[avd.name] {
                menu.addItem(runningItem(avd.displayName, [
                    action("Parar", #selector(stop(_:)), pids),
                    action("Forçar parada", #selector(forceStop(_:)), pids),
                ]))
            } else {
                menu.addItem(action(avd.displayName, #selector(start(_:)), avd.name))
                // Segurando ⌥ o item vira "cold boot", ignorando o snapshot salvo.
                let cold = action("\(avd.displayName) (cold boot)", #selector(coldBoot(_:)), avd.name)
                cold.isAlternate = true
                cold.keyEquivalentModifierMask = .option
                menu.addItem(cold)
            }
        }
    }

    // Simuladores ligados ficam no menu principal; os desligados, num submenu por versão do iOS.
    func addIOSSection() {
        guard FileManager.default.fileExists(atPath: simDevicesPath) else { return }
        let sims = listSimulators(availableRuntimes: availableRuntimes)
        guard !sims.isEmpty else { return }

        menu.addItem(.separator())
        menu.addItem(disabled("iOS"))
        for sim in sims.filter(\.booted).sorted(by: { $0.name < $1.name }) {
            menu.addItem(runningItem("\(sim.name) (\(runtimeName(sim.runtime)))", [
                action("Mostrar", #selector(showSimulator(_:)), sim.udid),
                action("Parar", #selector(shutdownSimulator(_:)), sim.udid),
            ]))
        }

        let byRuntime = Dictionary(grouping: sims.filter { !$0.booted }, by: \.runtime)
        for runtime in byRuntime.keys.sorted(by: { runtimeVersion($0).lexicographicallyPrecedes(runtimeVersion($1)) }).reversed() {
            let item = NSMenuItem(title: runtimeName(runtime), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            // iPhones antes dos iPads, cada grupo em ordem alfabética.
            let sorted = byRuntime[runtime]!.sorted { ($0.name.hasPrefix("iPad") ? 1 : 0, $0.name) < ($1.name.hasPrefix("iPad") ? 1 : 0, $1.name) }
            for sim in sorted { sub.addItem(action(sim.name, #selector(bootSimulator(_:)), sim.udid)) }
            item.submenu = sub
            menu.addItem(item)
        }
    }

    func runningItem(_ title: String, _ actions: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.state = .on
        let sub = NSMenu()
        actions.forEach(sub.addItem)
        item.submenu = sub
        return item
    }

    func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func action(_ title: String, _ selector: Selector, _ object: Any) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = object
        return item
    }

    // Roda um comando sem bloquear o menu; `done` é chamado na thread principal.
    func run(_ path: String, _ args: [String], done: ((Int32, Data) -> Void)? = nil) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = done == nil ? FileHandle.nullDevice : pipe
        p.standardError = done == nil ? FileHandle.nullDevice : pipe
        do { try p.run() } catch {
            alert("Não foi possível executar \(path)", error.localizedDescription)
            return
        }
        guard let done else { return }
        DispatchQueue.global().async {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            DispatchQueue.main.async { done(p.terminationStatus, output) }
        }
    }

    func launch(_ name: String, extra: [String] = []) { run(emulatorPath, ["-avd", name] + extra) }

    @objc func start(_ sender: NSMenuItem) { launch(sender.representedObject as! String) }
    @objc func coldBoot(_ sender: NSMenuItem) { launch(sender.representedObject as! String, extra: ["-no-snapshot-load"]) }
    @objc func stop(_ sender: NSMenuItem) { (sender.representedObject as! [pid_t]).forEach { kill($0, SIGTERM) } }
    @objc func forceStop(_ sender: NSMenuItem) { (sender.representedObject as! [pid_t]).forEach { kill($0, SIGKILL) } }

    @objc func bootSimulator(_ sender: NSMenuItem) {
        let udid = sender.representedObject as! String
        run("/usr/bin/xcrun", ["simctl", "boot", udid]) { status, output in
            guard status == 0 else {
                self.alert("Não foi possível iniciar o simulador", String(decoding: output, as: UTF8.self))
                return
            }
            self.openSimulatorApp(udid)
        }
    }

    @objc func showSimulator(_ sender: NSMenuItem) { openSimulatorApp(sender.representedObject as! String) }
    @objc func shutdownSimulator(_ sender: NSMenuItem) { run("/usr/bin/xcrun", ["simctl", "shutdown", sender.representedObject as! String]) }

    func openSimulatorApp(_ udid: String) {
        run("/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            alert("Não foi possível alterar a abertura ao iniciar sessão", error.localizedDescription)
        }
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
