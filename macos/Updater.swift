import AppKit
import CryptoKit

struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
        let size: Int
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    static func version(_ value: String) -> [Int]? {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }
    func updateAsset(current: String) throws -> Asset? {
        guard !draft, !prerelease, let newest = Self.version(tag_name), let installed = Self.version(current) else {
            throw PetError("更新版本信息无效")
        }
        guard installed.lexicographicallyPrecedes(newest) else { return nil }
        let expected = "AnnyDesktop-v\(newest.map(String.init).joined(separator: "."))-macos-universal.zip"
        guard let asset = assets.first(where: { $0.name == expected }),
              asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
              asset.browser_download_url.path == "/Doodle-Lin/anny-desktop-pet/releases/download/\(tag_name)/\(expected)",
              asset.size > 0, asset.size < 100_000_000,
              let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              digest.dropFirst(7).allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw PetError("此版本缺少可验证的 macOS 安装包，请到发布页下载")
        }
        return asset
    }
}

final class AppUpdater {
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    private var busy = false
    private let defaults = UserDefaults.standard
    var automaticChecks: Bool {
        get { defaults.object(forKey: "automaticUpdateChecks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "automaticUpdateChecks") }
    }
    private static var errorFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnnyDesktop/update-error.txt")
    }
    func checkAutomatically() {
        if let message = try? String(contentsOf: Self.errorFile, encoding: .utf8) {
            try? FileManager.default.removeItem(at: Self.errorFile)
            show("上次更新未完成", message)
        }
        guard automaticChecks else { return }
        check(manual: false)
    }
    private func show(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.runModal()
    }
    func check(manual: Bool) {
        guard !busy else { if manual { show("正在检查或下载更新", "完成后会提示你。") }; return }
        busy = true
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Doodle-Lin/anny-desktop-pet/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AnnyDesktop/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<(ReleaseInfo, ReleaseInfo.Asset?), Error> = Result {
                if let error = error { throw error }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data = data else { throw PetError("无法读取更新信息，请稍后重试") }
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                return (release, try release.updateAsset(current: Self.currentVersion))
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .failure(let error): if manual { self.show("检查更新失败", error.localizedDescription) }
                case .success(let (release, asset)):
                    guard let asset = asset else { if manual { self.show("已是最新版本", "当前版本：\(Self.currentVersion)") }; return }
                    if !manual && self.defaults.string(forKey: "lastOfferedVersion") == release.tag_name { return }
                    self.defaults.set(release.tag_name, forKey: "lastOfferedVersion")
                    let alert = NSAlert(); alert.messageText = "发现 Anny \(release.tag_name)"
                    alert.informativeText = "当前版本 \(Self.currentVersion)。下载并校验后，将替换当前应用并重启，存档会保留。"
                    alert.addButton(withTitle: "下载并安装"); alert.addButton(withTitle: "稍后")
                    if alert.runModal() == .alertFirstButtonReturn { self.download(asset, version: release.tag_name) }
                }
            }
        }.resume()
    }
    private func download(_ asset: ReleaseInfo.Asset, version: String) {
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard !target.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            show("请先移动应用", "将 Anny.app 放到有写入权限的文件夹（例如个人“应用程序”目录），重新打开后再更新。")
            return
        }
        busy = true
        var request = URLRequest(url: asset.browser_download_url); request.timeoutInterval = 120
        URLSession.shared.downloadTask(with: request) { file, response, error in
            do {
                if let error = error { throw error }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let file = file else { throw PetError("安装包下载失败") }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                try Self.verify(data, asset: asset)
                let staged = try Self.stage(archive: file, target: target, version: version)
                DispatchQueue.main.async {
                    do {
                        try self.install(staged: staged, target: target)
                        NSApp.terminate(nil)
                    } catch {
                        try? FileManager.default.removeItem(at: staged)
                        self.busy = false; self.show("安装更新失败", error.localizedDescription)
                    }
                }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.show("下载更新失败", error.localizedDescription) }
            }
        }.resume()
    }
    static func verify(_ data: Data, asset: ReleaseInfo.Asset) throws {
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == asset.size, digest == asset.digest?.lowercased() else { throw PetError("安装包校验失败，已停止更新") }
    }
    @discardableResult private static func run(_ executable: String, _ args: [String]) throws -> Int32 {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PetError("更新操作失败：\(URL(fileURLWithPath: executable).lastPathComponent)") }
        return process.terminationStatus
    }
    static func stage(archive: URL, target: URL, version: String) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("AnnyUpdate-" + UUID().uuidString)
        let staged = target.deletingLastPathComponent().appendingPathComponent(".Anny-update-" + UUID().uuidString + ".app")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        do {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
            let app = work.appendingPathComponent("Anny.app")
            let metadata = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            let plist = try PropertyListSerialization.propertyList(from: metadata, format: nil) as? [String: Any]
            guard plist?["CFBundleIdentifier"] as? String == "org.doodlelin.anny-desktop-pet",
                  ReleaseInfo.version(plist?["CFBundleShortVersionString"] as? String ?? "") == ReleaseInfo.version(version) else { throw PetError("安装包应用或版本不匹配") }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            try run("/usr/bin/ditto", [app.path, staged.path])
            return staged
        } catch { try? fm.removeItem(at: staged); throw error }
    }
    // Arguments are passed separately; app paths never become shell source.
    static let installScript = """
    parent="$1"; staged="$2"; target="$3"; backup="$4"; errorfile="$5"; opener="$6"
    attempts=0
    while kill -0 "$parent" 2>/dev/null; do
      attempts=$((attempts + 1))
      if [ "$attempts" -ge 60 ]; then
        printf '%s' '旧版未退出，更新已取消。请退出后重试。' > "$errorfile"
        exit 1
      fi
      sleep 1
    done
    if ! /bin/mv "$target" "$backup"; then
      printf '%s' '无法替换应用，旧版仍保留，请检查文件夹权限。' > "$errorfile"
      "$opener" "$target"
      exit 1
    fi
    if ! /bin/mv "$staged" "$target"; then
      /bin/mv "$backup" "$target"
      printf '%s' '安装失败，已尝试恢复旧版。' > "$errorfile"
      "$opener" "$target"
      exit 1
    fi
    if ! "$opener" "$target"; then
      /bin/mv "$target" "$staged"
      /bin/mv "$backup" "$target"
      printf '%s' '新版启动失败，已尝试恢复旧版。' > "$errorfile"
      "$opener" "$target"
      exit 1
    fi
    """
    private func install(staged: URL, target: URL) throws {
        let backup = target.deletingLastPathComponent().appendingPathComponent("Anny-backup-" + UUID().uuidString + ".app")
        try FileManager.default.createDirectory(at: Self.errorFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.installScript, "anny-update", String(ProcessInfo.processInfo.processIdentifier), staged.path, target.path, backup.path, Self.errorFile.path, "/usr/bin/open"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
    static func smoke() throws {
        func check(_ value: Bool, _ message: String) throws { if !value { throw PetError("Updater: " + message) } }
        try check(ReleaseInfo.version("v4.10.0") == [4,10,0] && ReleaseInfo.version("4.2.0-beta") == nil, "version parsing")
        let bytes = Data("test archive".utf8)
        let asset = ReleaseInfo.Asset(name: "AnnyDesktop-v4.10.0-macos-universal.zip", browser_download_url: URL(string: "https://github.com/Doodle-Lin/anny-desktop-pet/releases/download/v4.10.0/AnnyDesktop-v4.10.0-macos-universal.zip")!, digest: "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), size: bytes.count)
        let release = ReleaseInfo(tag_name: "v4.10.0", draft: false, prerelease: false, assets: [asset])
        try check(try release.updateAsset(current: "4.9.0") != nil, "numeric version comparison")
        try check(try release.updateAsset(current: "4.10.0") == nil, "same version")
        try check(try release.updateAsset(current: "5.0.0") == nil, "no downgrade")
        let foreign = ReleaseInfo.Asset(name: asset.name, browser_download_url: URL(string: "https://example.com/" + asset.name)!, digest: asset.digest, size: asset.size)
        var foreignRejected = false
        do { _ = try ReleaseInfo(tag_name: "v4.10.0", draft: false, prerelease: false, assets: [foreign]).updateAsset(current: "4.9.0") } catch { foreignRejected = true }
        try check(foreignRejected, "foreign download URL rejected")
        try verify(bytes, asset: asset)
        var rejected = false
        do { try verify(Data("bad".utf8), asset: asset) } catch { rejected = true }
        try check(rejected, "corrupt download rejected")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Anny-updater-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        if let archive = ProcessInfo.processInfo.environment["ANNY_QA_UPDATE_ARCHIVE"] {
            let prepared = try stage(archive: URL(fileURLWithPath: archive), target: dir.appendingPathComponent("Anny.app"), version: currentVersion)
            try check(FileManager.default.fileExists(atPath: prepared.appendingPathComponent("Contents/MacOS/Anny").path), "real archive staged and verified")
        }
        let target = dir.appendingPathComponent("Anny with spaces.app"), staged = dir.appendingPathComponent("new.app"), backup = dir.appendingPathComponent("backup.app"), error = dir.appendingPathComponent("error.txt")
        try Data("old".utf8).write(to: target); try Data("new".utf8).write(to: staged)
        try run("/bin/sh", ["-c", installScript, "test", "99999999", staged.path, target.path, backup.path, error.path, "/usr/bin/true"])
        try check(try String(contentsOf: target) == "new" && String(contentsOf: backup) == "old", "install retains backup")
        try FileManager.default.removeItem(at: backup)
        rejected = false
        do { try run("/bin/sh", ["-c", installScript, "test", "99999999", staged.path, target.path, backup.path, error.path, "/usr/bin/true"]) } catch { rejected = true }
        try check(try rejected && String(contentsOf: target) == "new", "failed replacement rolls back")
    }
}
