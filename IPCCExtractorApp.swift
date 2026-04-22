import SwiftUI
import Foundation
import AppKit

enum DownloadMode: String, CaseIterable, Identifiable {
    case latestRelease
    case latestBeta
    case version
    case build

    var id: String { rawValue }
}

enum DeviceFamily: String, CaseIterable, Identifiable {
    case iPhone
    case iPad

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iPhone: return "iPhone"
        case .iPad: return "Cellular iPad"
        }
    }
}

enum IPSWHealth {
    case missing
    case outdated
    case current
    case checking
    case unknown

    var color: Color {
        switch self {
        case .missing:
            return .red
        case .outdated:
            return .yellow
        case .current:
            return .green
        case .checking, .unknown:
            return .gray
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto
    case zhHans
    case zhHant
    case en
    case ja
    case ko
    case fr
    case es

    var id: String { rawValue }
}

struct L10n {
    let zhHans: String
    let zhHant: String
    let en: String
    let ja: String
    let ko: String
    let fr: String
    let es: String

    func text(for language: AppLanguage) -> String {
        switch language {
        case .auto:
            return text(for: Self.detectSystemLanguage())
        case .zhHans:
            return zhHans
        case .zhHant:
            return zhHant
        case .en:
            return en
        case .ja:
            return ja
        case .ko:
            return ko
        case .fr:
            return fr
        case .es:
            return es
        }
    }

    static func detectSystemLanguage() -> AppLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return .en
        }
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return .zhHant
        }
        if preferred.hasPrefix("zh") {
            return .zhHans
        }
        if preferred.hasPrefix("ja") {
            return .ja
        }
        if preferred.hasPrefix("ko") {
            return .ko
        }
        if preferred.hasPrefix("fr") {
            return .fr
        }
        if preferred.hasPrefix("es") {
            return .es
        }
        return .en
    }
}

final class AppViewModel: ObservableObject {
    @Published var language: AppLanguage = .auto
    @Published var deviceFamily: DeviceFamily = .iPhone
    @Published var deviceSuffix = ""
    @Published var selectedIPSWPath = ""
    @Published var mode: DownloadMode = .latestRelease
    @Published var versionInput = ""
    @Published var buildInput = ""
    @Published var cleanOnly = true
    @Published var deleteIPSW = false
    @Published var openOutput = true
    @Published var outputFolder: String
    @Published var logText = ""
    @Published var isRunning = false
    @Published var isRefreshing = false
    @Published var latestStable = ""
    @Published var latestBeta = ""
    @Published var statusText = "Ready"
    @Published var resolvedIpswPath = ""
    @Published var isManagingIpsw = false
    @Published var ipswHealth: IPSWHealth = .checking
    @Published var showIpswInstallAlert = false

    private let fileManager = FileManager.default
    private var runningProcess: Process?

    init() {
        let defaultFolder = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("IPCC_Extractor", isDirectory: true)
        outputFolder = defaultFolder.path
        resolvedIpswPath = Self.findIpswBinary() ?? ""
        statusText = tr(
            "就绪",
            "就緒",
            "Ready",
            "準備完了",
            "준비됨",
            "Prêt",
            "Listo"
        )
    }

    var effectiveLanguage: AppLanguage {
        language == .auto ? L10n.detectSystemLanguage() : language
    }

    var deviceCode: String {
        let trimmed = deviceSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "\(deviceFamily.rawValue)\(trimmed)"
    }

    var coreScriptURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("extract_all_ipcc.sh")
    }

    var appHomeURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("IPCCExtractor", isDirectory: true)
    }

    func tr(_ zhHans: String, _ zhHant: String, _ en: String, _ ja: String, _ ko: String, _ fr: String, _ es: String) -> String {
        L10n(
            zhHans: zhHans,
            zhHant: zhHant,
            en: en,
            ja: ja,
            ko: ko,
            fr: fr,
            es: es
        ).text(for: language)
    }

    func appendLog(_ line: String) {
        let suffix = line.hasSuffix("\n") ? line : line + "\n"
        logText += suffix
    }

    func ensureAppHome() {
        try? fileManager.createDirectory(at: appHomeURL, withIntermediateDirectories: true)
    }

    func defaultLogFileURL() -> URL {
        let base = URL(fileURLWithPath: outputFolder, isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return base.appendingPathComponent("ipcc_extractor_\(formatter.string(from: Date())).log")
    }

    func writeLogSnapshot() {
        guard !logText.isEmpty else { return }
        try? fileManager.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
        try? logText.write(to: defaultLogFileURL(), atomically: true, encoding: .utf8)
    }

    func updateDevice(from fullCode: String) {
        let trimmed = fullCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("ipad") {
            deviceFamily = .iPad
            deviceSuffix = String(trimmed.dropFirst("iPad".count))
        } else if trimmed.lowercased().hasPrefix("iphone") {
            deviceFamily = .iPhone
            deviceSuffix = String(trimmed.dropFirst("iPhone".count))
        } else {
            deviceSuffix = trimmed
        }
    }

    func refreshDeviceAndBuilds() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusText = tr(
            "正在获取机型和版本信息...",
            "正在取得機型與版本資訊...",
            "Loading device and build info...",
            "デバイスとビルド情報を取得しています...",
            "기기 및 빌드 정보를 불러오는 중...",
            "Chargement des infos de l'appareil et des builds...",
            "Cargando información del dispositivo y de las compilaciones..."
        )
        ensureAppHome()
        let currentDeviceCode = deviceCode
        let appHomeURL = self.appHomeURL

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let detected = Self.detectConnectedDevice(appHomeURL: appHomeURL) ?? ""
            let target = detected.isEmpty ? currentDeviceCode : detected
            let stable = target.isEmpty ? "" : (Self.queryLatest(for: target, beta: false, appHomeURL: appHomeURL) ?? "")
            let beta = target.isEmpty ? "" : (Self.queryLatest(for: target, beta: true, appHomeURL: appHomeURL) ?? "")
            let ipswPath = Self.findIpswBinary() ?? ""
            let health = Self.detectIpswHealth(ipswPath: ipswPath)

            await MainActor.run {
                self.resolvedIpswPath = ipswPath
                self.ipswHealth = health
                if !detected.isEmpty {
                    self.updateDevice(from: detected)
                }
                self.latestStable = stable
                self.latestBeta = beta
                self.isRefreshing = false
                self.statusText = self.tr("就绪", "就緒", "Ready", "準備完了", "준비됨", "Prêt", "Listo")
                if !detected.isEmpty {
                    self.appendLog(self.tr(
                        "已识别连接设备: \(detected)",
                        "已識別連接裝置: \(detected)",
                        "Detected connected device: \(detected)",
                        "接続中のデバイスを検出: \(detected)",
                        "연결된 기기 감지: \(detected)",
                        "Appareil connecté détecté: \(detected)",
                        "Dispositivo conectado detectado: \(detected)"
                    ))
                }
                if !stable.isEmpty {
                    self.appendLog(self.tr(
                        "最新正式版: \(stable)",
                        "最新正式版: \(stable)",
                        "Latest stable: \(stable)",
                        "最新安定版: \(stable)",
                        "최신 정식 버전: \(stable)",
                        "Dernière version stable : \(stable)",
                        "Última versión estable: \(stable)"
                    ))
                }
                if !beta.isEmpty {
                    self.appendLog(self.tr(
                        "最新 Beta: \(beta)",
                        "最新 Beta: \(beta)",
                        "Latest beta: \(beta)",
                        "最新ベータ: \(beta)",
                        "최신 베타: \(beta)",
                        "Dernière bêta : \(beta)",
                        "Última beta: \(beta)"
                    ))
                }
                if !ipswPath.isEmpty {
                    self.appendLog(self.tr(
                        "当前使用系统 ipsw: \(ipswPath)",
                        "目前使用系統 ipsw: \(ipswPath)",
                        "Using system ipsw: \(ipswPath)",
                        "システムの ipsw を使用: \(ipswPath)",
                        "시스템 ipsw 사용 중: \(ipswPath)",
                        "Utilise le binaire système ipsw : \(ipswPath)",
                        "Usando el binario del sistema ipsw: \(ipswPath)"
                    ))
                } else {
                    self.appendLog(self.tr(
                        "未检测到系统 ipsw。",
                        "未檢測到系統 ipsw。",
                        "System ipsw was not found.",
                        "システムの ipsw が見つかりません。",
                        "시스템 ipsw를 찾지 못했습니다.",
                        "Le binaire système ipsw est introuvable.",
                        "No se encontró ipsw en el sistema."
                    ))
                    self.showIpswInstallAlert = true
                }
                if stable.isEmpty || beta.isEmpty {
                    self.appendLog(self.tr(
                        "版本查询未返回有效结果，可能是网络、AppleDB 或 ipsw 本地缓存问题。",
                        "版本查詢未返回有效結果，可能是網路、AppleDB 或 ipsw 本機快取問題。",
                        "Version lookup did not return a valid result. This may be caused by network, AppleDB, or local ipsw cache issues.",
                        "バージョン取得に有効な結果が返りませんでした。ネットワーク、AppleDB、または ipsw のローカルキャッシュが原因の可能性があります。",
                        "버전 조회 결과가 유효하지 않습니다. 네트워크, AppleDB 또는 ipsw 로컬 캐시 문제일 수 있습니다.",
                        "La recherche de version n’a pas renvoyé de résultat valide. Cela peut venir du réseau, d’AppleDB ou du cache local de ipsw.",
                        "La consulta de versión no devolvió un resultado válido. Puede deberse a la red, AppleDB o la caché local de ipsw."
                    ))
                }
            }
        }
    }

    func installOrUpdateIpsw() {
        guard !isManagingIpsw, !isRunning else { return }
        isManagingIpsw = true
        statusText = tr(
            "正在安装或升级 ipsw...",
            "正在安裝或升級 ipsw...",
            "Installing or upgrading ipsw...",
            "ipsw をインストールまたはアップグレードしています...",
            "ipsw 설치 또는 업그레이드 중...",
            "Installation ou mise à niveau de ipsw...",
            "Instalando o actualizando ipsw..."
        )
        appendLog(tr(
            "开始处理系统里的 ipsw 工具...",
            "開始處理系統中的 ipsw 工具...",
            "Starting ipsw install/update on the system...",
            "システム上の ipsw の処理を開始...",
            "시스템의 ipsw 설치/업데이트 시작...",
            "Démarrage de l'installation/mise à jour de ipsw...",
            "Iniciando instalación/actualización de ipsw..."
        ))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-lc",
            "if command -v brew >/dev/null 2>&1; then if command -v ipsw >/dev/null 2>&1; then brew upgrade ipsw || brew install ipsw; else brew install ipsw; fi; else echo 'Homebrew not found'; exit 1; fi"
        ]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = appHomeURL.path
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.isManagingIpsw = false
                self?.resolvedIpswPath = Self.findIpswBinary() ?? ""
                self?.statusText = proc.terminationStatus == 0
                    ? (self?.tr("ipsw 已就绪", "ipsw 已就緒", "ipsw is ready", "ipsw の準備完了", "ipsw 준비 완료", "ipsw est prêt", "ipsw está listo") ?? "ipsw is ready")
                    : (self?.tr("ipsw 处理失败", "ipsw 處理失敗", "ipsw update failed", "ipsw の更新失敗", "ipsw 업데이트 실패", "Échec de la mise à jour de ipsw", "Falló la actualización de ipsw") ?? "ipsw update failed")
                self?.writeLogSnapshot()
                self?.refreshDeviceAndBuilds()
            }
        }

        do {
            try process.run()
        } catch {
            appendLog(tr(
                "无法启动 brew: \(error.localizedDescription)",
                "無法啟動 brew: \(error.localizedDescription)",
                "Failed to launch brew: \(error.localizedDescription)",
                "brew の起動に失敗: \(error.localizedDescription)",
                "brew 실행 실패: \(error.localizedDescription)",
                "Impossible de lancer brew : \(error.localizedDescription)",
                "No se pudo iniciar brew: \(error.localizedDescription)"
            ))
            isManagingIpsw = false
            statusText = tr("ipsw 处理失败", "ipsw 處理失敗", "ipsw update failed", "ipsw の更新失敗", "ipsw 업데이트 실패", "Échec de la mise à jour de ipsw", "Falló la actualización de ipsw")
        }
    }

    private static func findIpswBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ipsw",
            "/usr/local/bin/ipsw"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ipsw"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }
        return output
    }

    private static func detectIpswHealth(ipswPath: String) -> IPSWHealth {
        guard !ipswPath.isEmpty else { return .missing }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "if command -v brew >/dev/null 2>&1; then brew outdated ipsw >/dev/null 2>&1; code=$?; if [ $code -eq 0 ]; then echo outdated; elif [ $code -eq 1 ]; then echo current; else echo unknown; fi; else echo unknown; fi"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return .unknown
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch output {
        case "outdated":
            return .outdated
        case "current":
            return .current
        default:
            return .unknown
        }
    }

    private static func runTool(arguments: [String], appHomeURL: URL) -> String? {
        guard let ipsw = findIpswBinary() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["HOME=\(appHomeURL.path)", ipsw] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func detectConnectedDevice(appHomeURL: URL) -> String? {
        guard let output = runTool(arguments: ["idev", "list", "-i", "-j"], appHomeURL: appHomeURL) else { return nil }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first else {
            return nil
        }
        return (first["product_type"] as? String) ?? (first["ProductType"] as? String) ?? (first["device"] as? String)
    }

    private static func queryLatest(for device: String, beta: Bool, appHomeURL: URL) -> String? {
        let args = beta
            ? ["download", "appledb", "--show-latest", "--json", "--os", "iOS", "--device", device, "--beta"]
            : ["download", "appledb", "--show-latest", "--json", "--os", "iOS", "--device", device, "--release"]
        guard let output = runTool(arguments: args, appHomeURL: appHomeURL) else { return nil }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        func flatten(_ object: Any) -> [[String: Any]] {
            if let array = object as? [Any] {
                return array.flatMap { flatten($0) }
            }
            if let dict = object as? [String: Any] {
                return [dict] + dict.values.flatMap { flatten($0) }
            }
            return []
        }

        let candidates = flatten(json)
        for dict in candidates {
            let version = dict["version"] as? String
            let build = dict["build"] as? String ?? dict["buildid"] as? String ?? dict["buildId"] as? String
            if let version, let build {
                return "\(version) (\(build))"
            }
            if let version {
                return version
            }
            if let build {
                return build
            }
        }
        return nil
    }

    func chooseLocalIPSW() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.prompt = tr("选择 IPSW", "選擇 IPSW", "Choose IPSW", "IPSW を選択", "IPSW 선택", "Choisir l’IPSW", "Elegir IPSW")
        if panel.runModal() == .OK, let url = panel.url {
            selectedIPSWPath = url.path
            if deviceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fileName = url.deletingPathExtension().lastPathComponent
                if let prefix = fileName.split(separator: "_").first, prefix.lowercased().hasPrefix("iphone") {
                    updateDevice(from: String(prefix))
                } else if let prefix = fileName.split(separator: "_").first, prefix.lowercased().hasPrefix("ipad") {
                    updateDevice(from: String(prefix))
                }
            }
            appendLog(tr(
                "已选择本地 IPSW: \(url.path)",
                "已選擇本機 IPSW: \(url.path)",
                "Selected local IPSW: \(url.path)",
                "ローカル IPSW を選択: \(url.path)",
                "로컬 IPSW 선택됨: \(url.path)",
                "IPSW local sélectionné : \(url.path)",
                "IPSW local seleccionado: \(url.path)"
            ))
        }
    }

    func runExtraction() {
        guard !isRunning else { return }
        guard !deviceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog(tr(
                "请先输入机型代号。",
                "請先輸入機型代號。",
                "Please enter a device identifier first.",
                "先にデバイス識別子を入力してください。",
                "먼저 기기 식별자를 입력하세요.",
                "Veuillez d'abord saisir l'identifiant de l'appareil.",
                "Primero ingresa el identificador del dispositivo."
            ))
            return
        }
        if mode == .version && versionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(tr(
                "请选择“指定版本号”时填写版本号。",
                "選擇「指定版本號」時請填入版本號。",
                "Fill in the version when using Specific version.",
                "特定バージョンを選ぶ場合はバージョン番号を入力してください。",
                "특정 버전을 사용할 때는 버전 번호를 입력하세요.",
                "Renseigne la version pour l'option Specific version.",
                "Introduce la versión al usar Specific version."
            ))
            return
        }
        if mode == .build && buildInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(tr(
                "请选择“指定构建号”时填写构建号。",
                "選擇「指定構建號」時請填入構建號。",
                "Fill in the build number when using Specific build.",
                "特定ビルドを選ぶ場合はビルド番号を入力してください。",
                "특정 빌드를 사용할 때는 빌드 번호를 입력하세요.",
                "Renseigne le numéro de build pour l'option Specific build.",
                "Introduce el número de compilación al usar Specific build."
            ))
            return
        }

        ensureAppHome()
        isRunning = true
        statusText = tr("任务运行中...", "任務執行中...", "Running...", "実行中...", "실행 중...", "Exécution...", "Ejecutando...")
        logText = ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [coreScriptURL.path]
        var env = ProcessInfo.processInfo.environment
        let scriptLanguage: String = {
            switch effectiveLanguage {
            case .zhHans, .zhHant: return "zh"
            default: return "en"
            }
        }()
        env["LANG_MODE"] = scriptLanguage
        env["HOME"] = appHomeURL.path
        env["WORK_ROOT"] = outputFolder
        env["DEVICE_CODE_OVERRIDE"] = deviceCode
        env["DOWNLOAD_MODE_OVERRIDE"] = modeValue(mode)
        env["VERSION_INPUT_OVERRIDE"] = versionInput
        env["BUILD_INPUT_OVERRIDE"] = buildInput
        env["LOCAL_IPSW_FILE_OVERRIDE"] = selectedIPSWPath
        env["AUTO_CONFIRM_OVERRIDE"] = "y"
        env["CLEAN_CONFIRM_OVERRIDE"] = cleanOnly ? "y" : "n"
        env["DELETE_IPSW_OVERRIDE"] = deleteIPSW ? "y" : "n"
        env["OPEN_FINAL_DIR_OVERRIDE"] = openOutput ? "y" : "n"
        process.environment = env
        try? fileManager.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
        process.currentDirectoryURL = URL(fileURLWithPath: outputFolder)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.isRunning = false
                self?.statusText = proc.terminationStatus == 0
                    ? (self?.tr("完成", "完成", "Done", "完了", "완료", "Terminé", "Terminado") ?? "Done")
                    : (self?.tr("执行失败", "執行失敗", "Failed", "失敗", "실패", "Échec", "Falló") ?? "Failed")
                self?.writeLogSnapshot()
                self?.runningProcess = nil
            }
        }

        do {
            try process.run()
            runningProcess = process
        } catch {
            appendLog(tr(
                "启动失败: \(error.localizedDescription)",
                "啟動失敗: \(error.localizedDescription)",
                "Failed to start: \(error.localizedDescription)",
                "起動失敗: \(error.localizedDescription)",
                "시작 실패: \(error.localizedDescription)",
                "Échec du démarrage : \(error.localizedDescription)",
                "Error al iniciar: \(error.localizedDescription)"
            ))
            isRunning = false
            statusText = tr("执行失败", "執行失敗", "Failed", "失敗", "실패", "Échec", "Falló")
        }
    }

    func stopRunning() {
        runningProcess?.terminate()
        runningProcess = nil
        isRunning = false
        statusText = tr("已停止", "已停止", "Stopped", "停止済み", "중지됨", "Arrêté", "Detenido")
        writeLogSnapshot()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: outputFolder)
        panel.prompt = tr("选择输出目录", "選擇輸出資料夾", "Choose output folder", "出力フォルダを選択", "출력 폴더 선택", "Choisir le dossier de sortie", "Elegir carpeta de salida")
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url.path
        }
    }

    private func modeValue(_ mode: DownloadMode) -> String {
        switch mode {
        case .latestRelease: return "1"
        case .latestBeta: return "2"
        case .version: return "3"
        case .build: return "4"
        }
    }
}

struct AnimatedStatusDot: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.secondary.opacity(0.6))
            .frame(width: 10, height: 10)
            .scaleEffect(pulse ? 1.18 : 0.92)
            .opacity(pulse ? 1.0 : 0.65)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider()
            rightPanel
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(backgroundGradient)
        .onAppear {
            model.refreshDeviceAndBuilds()
        }
        .alert(
            model.tr(
                "未检测到 ipsw",
                "未檢測到 ipsw",
                "ipsw not found",
                "ipsw が見つかりません",
                "ipsw를 찾을 수 없습니다",
                "ipsw introuvable",
                "ipsw no encontrado"
            ),
            isPresented: $model.showIpswInstallAlert
        ) {
            Button(model.tr("安装 / 升级", "安裝 / 升級", "Install / Update", "インストール / 更新", "설치 / 업데이트", "Installer / Mettre à jour", "Instalar / Actualizar")) {
                model.installOrUpdateIpsw()
            }
            Button(model.tr("稍后", "稍後", "Later", "あとで", "나중에", "Plus tard", "Más tarde"), role: .cancel) { }
        } message: {
            Text(model.tr(
                "系统里没有检测到 ipsw，很多功能会不可用。建议先安装。",
                "系統中沒有偵測到 ipsw，很多功能會不可用。建議先安裝。",
                "No system ipsw was found. Several features will not work until it is installed.",
                "システムに ipsw が見つかりません。インストールするまで一部機能は使えません。",
                "시스템 ipsw를 찾지 못했습니다. 설치 전까지 일부 기능을 사용할 수 없습니다.",
                "Aucun ipsw système n’a été trouvé. Certaines fonctions resteront indisponibles tant qu’il n’est pas installé.",
                "No se encontró ipsw en el sistema. Varias funciones no estarán disponibles hasta instalarlo."
            ))
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(nsColor: .windowBackgroundColor), Color(red: 0.12, green: 0.15, blue: 0.20)]
                : [Color(nsColor: .windowBackgroundColor), Color(red: 0.92, green: 0.96, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IPCC Extractor")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(model.tr(
                            "自动提取、整理并准备安装 IPCC",
                            "自動提取、整理並準備安裝 IPCC",
                            "Extract, organize, and prepare IPCC installs",
                            "IPCC を抽出・整理してインストール準備",
                            "IPCC 추출, 정리, 설치 준비",
                            "Extraire, organiser et préparer les IPCC",
                            "Extrae, organiza y prepara IPCC"
                        ))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AnimatedStatusDot(active: model.isRunning || model.isRefreshing)
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(model.tr("语言", "語言", "Language", "言語", "언어", "Langue", "Idioma"), selection: $model.language) {
                            Text(model.tr("自动", "自動", "Auto", "自動", "자동", "Auto", "Auto")).tag(AppLanguage.auto)
                            Text("简中").tag(AppLanguage.zhHans)
                            Text("繁中").tag(AppLanguage.zhHant)
                            Text("English").tag(AppLanguage.en)
                            Text("日本語").tag(AppLanguage.ja)
                            Text("한국어").tag(AppLanguage.ko)
                            Text("Français").tag(AppLanguage.fr)
                            Text("Español").tag(AppLanguage.es)
                        }
                        .pickerStyle(.menu)

                        Text(model.tr(
                            "当前跟随系统语言：\(L10n.detectSystemLanguage().rawValue)",
                            "目前跟隨系統語言：\(L10n.detectSystemLanguage().rawValue)",
                            "Current system language: \(L10n.detectSystemLanguage().rawValue)",
                            "現在のシステム言語: \(L10n.detectSystemLanguage().rawValue)",
                            "현재 시스템 언어: \(L10n.detectSystemLanguage().rawValue)",
                            "Langue système actuelle : \(L10n.detectSystemLanguage().rawValue)",
                            "Idioma actual del sistema: \(L10n.detectSystemLanguage().rawValue)"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack {
                            Picker(model.tr("设备类型", "裝置類型", "Device type", "デバイスタイプ", "기기 유형", "Type d’appareil", "Tipo de dispositivo"), selection: $model.deviceFamily) {
                                Text(DeviceFamily.iPhone.displayName).tag(DeviceFamily.iPhone)
                                Text(DeviceFamily.iPad.displayName).tag(DeviceFamily.iPad)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)

                            TextField(
                                model.tr(
                                    "型号编号，例如 18,2",
                                    "型號編號，例如 18,2",
                                    "Model suffix, e.g. 18,2",
                                    "型番番号 例: 18,2",
                                    "모델 접미사 예: 18,2",
                                    "Suffixe du modèle, ex. 18,2",
                                    "Sufijo del modelo, ej. 18,2"
                                ),
                                text: $model.deviceSuffix
                            )
                            .textFieldStyle(.roundedBorder)

                            Button(model.tr("自动识别", "自動識別", "Detect", "自動検出", "자동 감지", "Détecter", "Detectar")) {
                                model.refreshDeviceAndBuilds()
                            }
                        }

                        Text(model.deviceCode.isEmpty ? " " : model.deviceCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                model.chooseLocalIPSW()
                            } label: {
                                Label(model.tr("手动选择 IPSW", "手動選擇 IPSW", "Choose IPSW", "IPSW を手動選択", "IPSW 수동 선택", "Choisir un IPSW", "Elegir IPSW"), systemImage: "doc.badge.plus")
                            }

                            Button {
                                model.selectedIPSWPath = ""
                            } label: {
                                Label(model.tr("清除", "清除", "Clear", "クリア", "지우기", "Effacer", "Limpiar"), systemImage: "xmark.circle")
                            }
                            .disabled(model.selectedIPSWPath.isEmpty)
                        }

                        if !model.selectedIPSWPath.isEmpty {
                            Text(model.selectedIPSWPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            infoBadge(title: model.tr("最新正式版", "最新正式版", "Latest stable", "最新安定版", "최신 정식", "Dernière stable", "Última estable"), value: model.latestStable)
                            infoBadge(title: model.tr("最新 Beta", "最新 Beta", "Latest beta", "最新ベータ", "최신 베타", "Dernière bêta", "Última beta"), value: model.latestBeta)
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(model.tr("下载方式", "下載方式", "Download mode", "ダウンロード方式", "다운로드 방식", "Mode de téléchargement", "Modo de descarga"), selection: $model.mode) {
                            Text(model.tr("最新正式版", "最新正式版", "Latest stable", "最新安定版", "최신 정식", "Dernière stable", "Última estable")).tag(DownloadMode.latestRelease)
                            Text(model.tr("最新 Beta", "最新 Beta", "Latest beta", "最新ベータ", "최신 베타", "Dernière bêta", "Última beta")).tag(DownloadMode.latestBeta)
                            Text(model.tr("指定版本号", "指定版本號", "Specific version", "特定バージョン", "특정 버전", "Version précise", "Versión específica")).tag(DownloadMode.version)
                            Text(model.tr("指定构建号", "指定構建號", "Specific build", "特定ビルド", "특정 빌드", "Build précis", "Compilación específica")).tag(DownloadMode.build)
                        }
                        .pickerStyle(.menu)

                        if model.mode == .version {
                            TextField(model.tr("输入版本号，例如 26.5", "輸入版本號，例如 26.5", "Enter version, e.g. 26.5", "バージョンを入力 例: 26.5", "버전 입력 예: 26.5", "Saisir la version, ex. 26.5", "Introduce la versión, ej. 26.5"), text: $model.versionInput)
                                .textFieldStyle(.roundedBorder)
                        }

                        if model.mode == .build {
                            TextField(model.tr("输入构建号，例如 23F5059e", "輸入構建號，例如 23F5059e", "Enter build, e.g. 23F5059e", "ビルドを入力 例: 23F5059e", "빌드 입력 예: 23F5059e", "Saisir le build, ex. 23F5059e", "Introduce la compilación, ej. 23F5059e"), text: $model.buildInput)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text(model.tr("输出目录", "輸出目錄", "Output folder", "出力フォルダ", "출력 폴더", "Dossier de sortie", "Carpeta de salida"))
                            Spacer()
                            Button(model.tr("选择", "選擇", "Choose", "選択", "선택", "Choisir", "Elegir")) {
                                model.chooseOutputFolder()
                            }
                        }
                        Text(model.outputFolder)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        Text(model.tr(
                            "日志会自动保存在输出目录下，文件名格式为 ipcc_extractor_时间.log",
                            "日誌會自動保存在輸出目錄下，檔名格式為 ipcc_extractor_時間.log",
                            "Logs are automatically saved into the output folder as ipcc_extractor_TIMESTAMP.log",
                            "ログは出力フォルダに ipcc_extractor_TIMESTAMP.log 形式で自動保存されます",
                            "로그는 출력 폴더에 ipcc_extractor_TIMESTAMP.log 형식으로 자동 저장됩니다",
                            "Les journaux sont enregistrés automatiquement dans le dossier de sortie au format ipcc_extractor_TIMESTAMP.log",
                            "Los registros se guardan automáticamente en la carpeta de salida como ipcc_extractor_TIMESTAMP.log"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(model.tr("完成后清理中间文件，只保留整理后的 IPCC", "完成後清理中間檔，只保留整理後的 IPCC", "Clean intermediate files and keep organized IPCC only", "完了後に中間ファイルを削除し、整理済み IPCC のみ残す", "완료 후 중간 파일 정리, 정리된 IPCC만 보관", "Nettoyer les fichiers intermédiaires et garder uniquement les IPCC organisés", "Limpiar archivos intermedios y conservar solo los IPCC organizados"), isOn: $model.cleanOnly)
                        Toggle(model.tr("同时删除下载的 IPSW", "同時刪除下載的 IPSW", "Also delete downloaded IPSW", "ダウンロードした IPSW も削除", "다운로드한 IPSW도 삭제", "Supprimer aussi l’IPSW téléchargé", "Eliminar también el IPSW descargado"), isOn: $model.deleteIPSW)
                            .disabled(!model.cleanOnly)
                        Toggle(model.tr("完成后自动打开结果目录", "完成後自動打開結果資料夾", "Open output folder when finished", "完了後に出力フォルダを開く", "완료 후 결과 폴더 열기", "Ouvrir le dossier de sortie à la fin", "Abrir la carpeta final al terminar"), isOn: $model.openOutput)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.tr("工具来源", "工具來源", "Tool source", "ツール元", "도구 출처", "Source de l’outil", "Origen de la herramienta"))
                            .font(.headline)
                        Text(model.tr(
                            "不会把 ipsw 二进制打包进 app。这里始终调用系统里已安装的 ipsw，后续更新只需要更新 Homebrew 里的 ipsw 即可。",
                            "不會把 ipsw 二進位打包進 app。這裡始終呼叫系統已安裝的 ipsw，後續更新只要更新 Homebrew 裡的 ipsw 即可。",
                            "The app does not bundle the ipsw binary. It always uses the system-installed ipsw, so future updates only require updating ipsw via Homebrew.",
                            "この app は ipsw バイナリを内包しません。常にシステムに入っている ipsw を使うので、更新は Homebrew 側だけで済みます。",
                            "이 앱은 ipsw 바이너리를 내장하지 않습니다. 항상 시스템에 설치된 ipsw를 사용하므로 업데이트는 Homebrew 쪽만 하면 됩니다.",
                            "L’app n’embarque pas le binaire ipsw. Elle utilise toujours la version système installée, donc la mise à jour se fait simplement via Homebrew.",
                            "La app no incluye el binario ipsw. Siempre usa el ipsw instalado en el sistema, así que actualizarlo solo requiere Homebrew."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(model.resolvedIpswPath.isEmpty ? "ipsw: not found" : "ipsw: \(model.resolvedIpswPath)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.ipswHealth.color)
                                .frame(width: 10, height: 10)
                            Text(model.tr(
                                model.ipswHealth == .missing ? "未安装" : model.ipswHealth == .outdated ? "需要升级" : model.ipswHealth == .current ? "已安装且较新" : model.ipswHealth == .checking ? "检测中" : "状态未知",
                                model.ipswHealth == .missing ? "未安裝" : model.ipswHealth == .outdated ? "需要升級" : model.ipswHealth == .current ? "已安裝且較新" : model.ipswHealth == .checking ? "檢測中" : "狀態未知",
                                model.ipswHealth == .missing ? "Not installed" : model.ipswHealth == .outdated ? "Needs update" : model.ipswHealth == .current ? "Installed and current" : model.ipswHealth == .checking ? "Checking" : "Unknown state",
                                model.ipswHealth == .missing ? "未インストール" : model.ipswHealth == .outdated ? "更新が必要" : model.ipswHealth == .current ? "導入済み・比較的新しい" : model.ipswHealth == .checking ? "確認中" : "状態不明",
                                model.ipswHealth == .missing ? "미설치" : model.ipswHealth == .outdated ? "업데이트 필요" : model.ipswHealth == .current ? "설치됨 / 최신" : model.ipswHealth == .checking ? "확인 중" : "상태 알 수 없음",
                                model.ipswHealth == .missing ? "Non installé" : model.ipswHealth == .outdated ? "Mise à jour nécessaire" : model.ipswHealth == .current ? "Installé et à jour" : model.ipswHealth == .checking ? "Vérification..." : "État inconnu",
                                model.ipswHealth == .missing ? "No instalado" : model.ipswHealth == .outdated ? "Necesita actualización" : model.ipswHealth == .current ? "Instalado y al día" : model.ipswHealth == .checking ? "Comprobando" : "Estado desconocido"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Button {
                            model.installOrUpdateIpsw()
                        } label: {
                            Label(
                                model.tr("安装 / 升级 ipsw", "安裝 / 升級 ipsw", "Install / Update ipsw", "ipsw を導入 / 更新", "ipsw 설치 / 업데이트", "Installer / Mettre à jour ipsw", "Instalar / Actualizar ipsw"),
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .disabled(model.isRunning || model.isManagingIpsw)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        model.runExtraction()
                    } label: {
                        Label(model.tr("开始提取", "開始提取", "Start", "開始", "시작", "Démarrer", "Iniciar"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)

                    Button {
                        model.refreshDeviceAndBuilds()
                    } label: {
                        Label(model.tr("刷新版本信息", "刷新版本資訊", "Refresh builds", "ビルド更新", "빌드 새로고침", "Rafraîchir", "Actualizar"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRunning || model.isRefreshing || model.isManagingIpsw)

                    Button {
                        model.stopRunning()
                    } label: {
                        Label(model.tr("停止", "停止", "Stop", "停止", "중지", "Arrêter", "Detener"), systemImage: "stop.fill")
                    }
                    .disabled(!model.isRunning)
                }

                HStack {
                    AnimatedStatusDot(active: model.isRunning || model.isRefreshing)
                    Text(model.statusText)
                        .font(.headline)
                }

                Text("creditor: github@hcy311")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 430)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.tr("实时日志", "即時日誌", "Live log", "リアルタイムログ", "실시간 로그", "Journal en direct", "Registro en vivo"))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            TextEditor(text: $model.logText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(24)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
            )
    }

    private func infoBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "..." : value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.thinMaterial)
        )
    }
}

@main
struct IPCCExtractorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(nil)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
