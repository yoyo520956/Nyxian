/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import UIKit
import UniformTypeIdentifiers

final class ROMImporter: NSObject, UIDocumentPickerDelegate {
    private var completion: ((URL?) -> Void)?
    
    func present(from viewController: UIViewController, completion: @escaping (URL?) -> Void) {
        self.completion = completion
        
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        
        picker.delegate = self
        picker.allowsMultipleSelection = false
        
        viewController.present(picker, animated: true)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls.first
        
        completion?(url)
        completion = nil
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(nil)
        completion = nil
    }
}

final class ROMPath {
    let path: String
    let permission: Int
    
    struct ROMPathCodeSigningInfo {
        let needed: Bool
        let neededNXT2: Bool
        let nxt2: [String:Any]
    }
    let codesigning: ROMPath.ROMPathCodeSigningInfo
    
    init(path: String,
         permission: Int,
         codesigning: ROMPath.ROMPathCodeSigningInfo) {
        self.path = path
        self.permission = permission
        self.codesigning = codesigning
    }
}

func adaptiveImage(light: UIImage, dark: UIImage) -> UIImage {
    let asset = UIImageAsset()
    let lightTraits = UITraitCollection(traitsFrom: [
        .current,
        UITraitCollection(userInterfaceStyle: .light)
    ])
    asset.register(light, with: lightTraits)
    let darkTraits = UITraitCollection(traitsFrom: [
        .current,
        UITraitCollection(userInterfaceStyle: .dark)
    ])
    asset.register(dark, with: darkTraits)
    return asset.image(with: .current)
}

final class ROMManifest {
    // ABI
    let manifestVersion: Int
    
    // identity
    let identifier: String
    let name: String
    let version: String
    let minimumNyxianVersion: String
    
    // file permissions
    let defaultFilePermission: Int
    let defaultDirectoryPermission: Int
    let paths: [ROMPath]
    
    // runtime
    let installer: String?
    let uninstaller: String?
    let executable: String
    
    // bootlogo
    let bootlogo: UIImage?
    
    // helpers
    var isNyxianMinimumVersionMet: Bool {
        get {
            // TODO: make this actually work
            return true
        }
    }
    
    init(manifestPlistURL: URL) throws {
        // first we'll read the plist
        guard let manifestContent = NSDictionary(contentsOf: manifestPlistURL) as? [String: Any] else {
            throw NSError(domain: "org.emexlabs.nyxian.bootloader.rom-flash", code: 1, userInfo: [NSLocalizedDescriptionKey:"failed to read menifest plist"])
        }
        
        // next we need to parse version
        guard let manifestVersion = manifestContent["NXRomManifestVersion"] as? Int,
              let identifier = manifestContent["NXRomIdentifier"] as? String,
              let name = manifestContent["NXRomName"] as? String,
              let version = manifestContent["NXRomVersion"] as? String,
        let minimumNyxianVersion = manifestContent["NXRomMinimumNyxianVersion"] as? String,
        let executable = manifestContent["NXRomExecutable"] as? String else {
            throw NSError(domain: "org.emexlabs.nyxian.bootloader.rom-flash", code: 1, userInfo: [NSLocalizedDescriptionKey:"malformed manifest plist"])
        }
        
        // ABI
        self.manifestVersion = manifestVersion
        
        // identity
        self.identifier = identifier
        self.name = name
        self.version = version
        self.minimumNyxianVersion = minimumNyxianVersion
        
        // file permissions
        self.defaultFilePermission = manifestContent["NXRomDefaultFilePermission"] as? Int ?? 420
        self.defaultDirectoryPermission = manifestContent["NXRomDefaultDirectoryPermission"] as? Int ?? 493
        
        // parsing explicit paths
        var actualPathObjects: [ROMPath] = []
        let paths: [[String:Any]] = manifestContent["NXRomPaths"] as? [[String:Any]] ?? []
        for pathDict in paths {
            let permission: Int = pathDict["NXPermission"] as? Int ?? self.defaultFilePermission
            let requiresCodeSigning: Bool = pathDict["NXRequiresCodeSigning"] as? Bool ?? false
            var requiresNXT2Signing: Bool = requiresCodeSigning
            let nxt2Entitlements: [String:Any]
            if requiresNXT2Signing {
                if let nxt2: [String:Any] = pathDict["NXT2Entitlements"] as? [String:Any] {
                    nxt2Entitlements = nxt2
                } else {
                    nxt2Entitlements = [:]
                    requiresNXT2Signing = false
                }
            } else {
                nxt2Entitlements = [:]
            }
            
            if let path: [String] = pathDict["NXPath"] as? [String] {
                for additionalPath in path {
                    actualPathObjects.append(ROMPath(path: additionalPath, permission: permission, codesigning: ROMPath.ROMPathCodeSigningInfo(needed: requiresCodeSigning, neededNXT2: requiresNXT2Signing, nxt2: nxt2Entitlements)))
                }
            } else if let path: String = pathDict["NXPath"] as? String {
                actualPathObjects.append(ROMPath(path: path, permission: permission, codesigning: ROMPath.ROMPathCodeSigningInfo(needed: requiresCodeSigning, neededNXT2: requiresNXT2Signing, nxt2: nxt2Entitlements)))
            } else {
                throw NSError(domain: "org.emexlabs.nyxian.bootloader.rom-flash", code: 1, userInfo: [NSLocalizedDescriptionKey:"malformed manifest path's in manifest plist"])
            }
        }
        self.paths = actualPathObjects
        
        self.installer = manifestContent["NXRomInstaller"] as? String
        self.uninstaller = manifestContent["NXRomUninstaller"] as? String
        self.executable = executable
        
        // bootlogo
        if let bootLogoConfig = manifestContent["NXRomBootLogo"] as? [String:String],
           let lightPath = bootLogoConfig["Light"],
           let darkPath = bootLogoConfig["Dark"],
           let light = UIImage(contentsOfFile: manifestPlistURL.deletingLastPathComponent().appendingPathComponent(lightPath).path) {
            let dark = UIImage(contentsOfFile: manifestPlistURL.deletingLastPathComponent().appendingPathComponent(darkPath).path) ?? light
            self.bootlogo = adaptiveImage(light: light, dark: dark)
        } else {
            self.bootlogo = nil
        }
    }
}

enum BootFlag: String, CaseIterable {
    case kextLoading = "nyxian.boot.kextLoading"
    case logObfucation = "nyxian.boot.log.obfuscated"
    case sandboxFilesystem = "nyxian.boot.sandbox.filesystems"
    
    var title: String {
        switch self {
            case .kextLoading: return "开机时加载 KEXT"
            case .logObfucation: return "混淆日志"
            case .sandboxFilesystem: return "文件系统沙盒"
        }
    }
    
    var defaultValue: Bool {
        switch self {
            case .kextLoading: return true
            case .logObfucation: return true
            case .sandboxFilesystem: return true
        }
    }
}

enum BootConfig {
    fileprivate static let entitlementModeKey = "nyxian.boot.entitlements.mode"
    
    static func registerDefaults() {
        var defaults: [String: Any] = Dictionary(uniqueKeysWithValues: BootFlag.allCases.map { ($0.rawValue, $0.defaultValue) })
        defaults[entitlementModeKey] = EnforcementMode.enforcing.rawValue
        
        UserDefaults.standard.register(defaults: defaults)
    }
    
    static var entitlementMode: EnforcementMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: entitlementModeKey),
                  let mode = EnforcementMode(rawValue: raw) else {
                return .enforcing
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: entitlementModeKey)
        }
    }
    
    static func isEnabled(_ flag: BootFlag) -> Bool {
        UserDefaults.standard.bool(forKey: flag.rawValue)
    }
    
    static func toggle(_ flag: BootFlag) {
        UserDefaults.standard.set(!isEnabled(flag), forKey: flag.rawValue)
    }
}

enum EnforcementMode: String, CaseIterable {
    case enforcing
    case permissive
    case disabled
    
    var badge: String {
        switch self {
            case .enforcing: return "E"
            case .permissive: return "P"
            case .disabled: return "-"
        }
    }
    
    var next: EnforcementMode {
        let all = EnforcementMode.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

private typealias NXSlotMainFn = @convention(c) () -> UnsafeMutableRawPointer?
private typealias NXSlotDidAppearFn = @convention(c) () -> Void
private typealias NXSlotCreateWindowFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
private typealias NXRomGenericFn = @convention(c) (UnsafePointer<CChar>) -> Int32

private func romError(_ message: String) -> NSError {
    NSError(domain: "org.emexlabs.nyxian.bootloader.rom-flash", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
}

private func slotFile(_ relative: String,
                      in slot: URL) throws -> URL {
    let root = slot.resolvingSymlinksInPath().standardizedFileURL.path
    let url = slot.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
    guard url.path.hasPrefix(root + "/") else {
        throw romError("路径越出 ROM 槽位：\(relative)")
    }
    return url
}

private let nxRomLogFD: Int32 = 27
private let romQueue = DispatchQueue(label: "org.emexlabs.nyxian.bootloader.rom", qos: .userInitiated)
private var romOperationInProgress = false

private struct RomLog {
    let controller: NXRecoveryViewController
    
    func info(_ message: String) {
        DispatchQueue.main.async { controller.recoveryLog(message) }
    }
    
    func error(_ message: String) {
        DispatchQueue.main.async { controller.recoveryLogError(message) }
    }
    
    func rom(_ line: String) {
        if line.hasPrefix("错误：") {
            error(line)
        } else {
            info(line)
        }
    }
}

private func romIsBusy(_ c: NXRecoveryViewController) -> Bool {
    if romOperationInProgress {
        c.recoveryLogError("错误：仍有 ROM 操作正在进行")
    }
    return romOperationInProgress
}

private func runRomOperation(_ c: NXRecoveryViewController, _ work: @escaping (RomLog) -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard !romIsBusy(c) else { return }
    romOperationInProgress = true
    let log = RomLog(controller: c)
    romQueue.async {
        work(log)
        DispatchQueue.main.async {
            romOperationInProgress = false
        }
    }
}

private func runRomGeneric(_ relative: String, symbol: String, slot: URL, onLine: @escaping (String) -> Void) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    
    let url = try slotFile(relative, in: slot)
    
    guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
        throw romError("无法加载 \(relative)：\(lastDlError())")
    }
    defer { dlclose(handle) }
    
    guard let sym = dlsym(handle, symbol) else {
        throw romError("\(relative) 缺少 \(symbol) 入口点")
    }
    
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else {
        throw romError("创建管道失败：\(String(cString: strerror(errno)))")
    }
    
    let readFD = fds[0]
    let writeFD = fds[1]
    
    let oldFD = dup(nxRomLogFD)
    guard dup2(writeFD, nxRomLogFD) >= 0 else {
        close(readFD)
        close(writeFD)
        if oldFD >= 0 { close(oldFD) }
        throw romError("dup2 失败：\(String(cString: strerror(errno)))")
    }
    close(writeFD)
    
    // don't touch this, it works
    let drained = DispatchGroup()
    drained.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        var buf = [UInt8](repeating: 0, count: 4096)
        var pending: [UInt8] = []
        while true {
            let n = read(readFD, &buf, buf.count)
            if n > 0 {
                pending.append(contentsOf: buf[0..<n])
                var start = pending.startIndex
                while let nl = pending[start...].firstIndex(of: 0x0A) {
                    emitRomLine(pending[start..<nl], onLine)
                    start = nl + 1
                }
                pending.removeFirst(start)
                continue
            }
            if n < 0 && errno == EINTR {
                continue
            }
            break
        }
        emitRomLine(pending[...], onLine)
        close(readFD)
        drained.leave()
    }
    let generic = unsafeBitCast(sym, to: NXRomGenericFn.self)
    let rc = slot.path.withCString {
        generic($0)
    }
    close(nxRomLogFD)
    if oldFD >= 0 {
        dup2(oldFD, nxRomLogFD)
        close(oldFD)
    }
    drained.wait()
    guard rc == 0 else {
        throw romError("\(symbol) 返回了 \(rc)")
    }
}

private func emitRomLine(_ bytes: ArraySlice<UInt8>, _ onLine: (String) -> Void) {
    var bytes = bytes
    if bytes.last == 0x0D {
        bytes = bytes.dropLast()
    }
    guard !bytes.isEmpty else { return }
    onLine(String(decoding: bytes, as: UTF8.self))
}

private enum SlotLoadResult {
    case loaded(name: String, main: NXSlotMainFn, didAppear: NXSlotDidAppearFn?, createWindow: NXSlotCreateWindowFn?)
    case failed(String)
}

private typealias RestartSelfFn = @convention(c) () -> Void

private func restartSelf() {
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let sym = dlsym(RTLD_DEFAULT, "PERestartSelf") else {
        exit(0)
    }
    unsafeBitCast(sym, to: RestartSelfFn.self)()
}

private func refreshVnode(atPath path: String) -> Bool {
    let fd = open(path, O_RDWR)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    guard unlink(path) == 0 else { return false }
    if fclonefileat(fd, AT_FDCWD, path, 0) == 0 {
        return true
    }
    let copyfd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0o777)
    guard copyfd >= 0 else { return false }
    defer { close(copyfd) }
    lseek(fd, 0, SEEK_SET)
    return fcopyfile(fd, copyfd, nil, copyfile_flags_t(COPYFILE_DATA)) == 0
}

private func flashedSlotURL() -> URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Boot/Slot/A")
}

private func lastDlError() -> String {
    if let err = dlerror() { return String(cString: err) }
    return "未知的 dyld 错误"
}

private func loadSlot(loadSuperslotForcefully: Bool) -> SlotLoadResult {
    let fm = FileManager.default
    let slot = flashedSlotURL()
    let manifestURL = slot.appendingPathComponent("manifest.plist")
    
    let image: URL
    let name: String
    
    if fm.fileExists(atPath: manifestURL.path),
       !loadSuperslotForcefully {
        do {
            let manifest = try ROMManifest(manifestPlistURL: manifestURL)
            image = try slotFile(manifest.executable, in: slot)
            name = manifest.name
        } catch {
            return .failed("已刷入的 ROM 无效：\(error.localizedDescription)")
        }
        guard fm.fileExists(atPath: image.path) else {
            return .failed("\(name): executable missing")
        }
    } else if let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("SuperSlot.dylib"),
              fm.fileExists(atPath: bundled.path) {
        image = bundled
        name = "SuperSlot.dylib"
    } else {
        return .failed("未找到槽位（既无已刷入的 ROM，也无内置的 SuperSlot.dylib）")
    }
    
    guard let handle = dlopen(image.path, RTLD_NOW | RTLD_NODELETE | RTLD_GLOBAL) else {
        return .failed("无法加载 \(name)：\(lastDlError())")
    }
    
    guard let mainSym = dlsym(handle, "NXSlotMain") else {
        return .failed("\(name) 缺少 NXSlotMain 入口点")
    }
    
    let main = unsafeBitCast(mainSym, to: NXSlotMainFn.self)
    let didAppear = dlsym(handle, "NXSlotDidAppear").map { unsafeBitCast($0, to: NXSlotDidAppearFn.self) }
    let createWindow = dlsym(handle, "NXSlotCreateWindow").map { unsafeBitCast($0, to: NXSlotCreateWindowFn.self) }
    return .loaded(name: name, main: main, didAppear: didAppear, createWindow: createWindow)
}

private func bootConfigItems(returningTo parent: @escaping (NXRecoveryViewController) -> Void) -> [NXRecoveryItem] {
    func label(_ flag: BootFlag) -> String {
        "[\(BootConfig.isEnabled(flag) ? "X" : " ")] \(flag.title)"
    }
    
    func reload(_ c: NXRecoveryViewController) {
        let keep = c.recoveryIndex
        c.recoveryItems = bootConfigItems(returningTo: parent)
        c.recoveryIndex = keep
    }
    
    var items: [NXRecoveryItem] = [
        NXRecoveryItem(title: "../") { c in
            if let c = c {
                parent(c)
            }
        }
    ]
    
    for flag in BootFlag.allCases {
        items.append(NXRecoveryItem(title: label(flag)) { c in
            guard let c = c else { return }
            
            BootConfig.toggle(flag)
            reload(c)
            
            let state = BootConfig.isEnabled(flag) ? "已启用" : "已禁用"
            c.recoveryLog("\(flag.title)：\(state)")
        })
    }
    
    let mode = BootConfig.entitlementMode
    items.append(NXRecoveryItem(title: "[\(mode.badge)] 权限：\(mode.rawValue)") { c in
        guard let c = c else { return }
        
        BootConfig.entitlementMode = BootConfig.entitlementMode.next
        reload(c)
        
        switch BootConfig.entitlementMode {
            case .enforcing: c.recoveryLog("权限：强制模式")
            case .permissive: c.recoveryLogError("权限：宽容模式（仅记录拒绝，不阻止）")
            case .disabled: c.recoveryLogError("权限：已禁用（不执行任何检查）")
        }
    })
    
    return items
}

func recoveryShowBootConfig(recoveryController c: NXRecoveryViewController) {
    c.enterRecovery(
        withHeader: "启动配置",
        instructions: nil,
        footer: nil,
        items: bootConfigItems(returningTo: { parent in
            recoveryShowMenu(recoveryController: parent)
        }),
        onSelect: nil,
        onMove: nil
    )
}

private struct WipeFailure {
    let path: String
    let reason: String
}

private struct WipeStats {
    var removedFiles = 0
    var removedDirectories = 0
    var bytes: Int64 = 0
    var failures: [WipeFailure] = []
}

private let maxFailuresShown = 3

private let wipeResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .totalFileAllocatedSizeKey,
]

private func errnoDescription(_ error: Error) -> String {
    let ns = error as NSError
    if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain {
        return String(cString: strerror(Int32(u.code)))
    }
    return ns.localizedDescription
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func relativePath(_ url: URL, home: String) -> String {
    let path = url.standardizedFileURL.path
    return path.hasPrefix(home) ? String(path.dropFirst(home.count)) : path
}

private func recordFailure(_ url: URL, _ error: Error, home: String, stats: inout WipeStats) {
    stats.failures.append(WipeFailure(path: relativePath(url, home: home), reason: errnoDescription(error)))
}

private func removeTree(_ url: URL,
                        keeping keep: Set<String>,
                        isRoot: Bool,
                        home: String,
                        stats: inout WipeStats) -> Bool {
    let fm = FileManager.default
    let values = try? url.resourceValues(forKeys: Set(wipeResourceKeys))
    let isSymlink = values?.isSymbolicLink ?? false
    let isRealDirectory = (values?.isDirectory ?? false) && !isSymlink
    
    var ok = true
    if isRealDirectory {
        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: wipeResourceKeys, options: [])
        } catch {
            recordFailure(url, error, home: home, stats: &stats)
            return false
        }
        
        for child in children {
            let childOK = removeTree(child, keeping: keep, isRoot: false, home: home, stats: &stats)
            ok = ok && childOK
        }
    }
    
    if isRoot || keep.contains(url.standardizedFileURL.path) || !ok {
        return ok
    }
    
    let size = Int64(values?.totalFileAllocatedSize ?? 0)
    do {
        try fm.removeItem(at: url)
    } catch {
        recordFailure(url, error, home: home, stats: &stats)
        return false
    }
    
    if isRealDirectory {
        stats.removedDirectories += 1
    } else {
        stats.removedFiles += 1
        stats.bytes += size
    }
    
    return true
}

func recoveryWipeData(_ c: NXRecoveryViewController) {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    let homePath = home.path
    
    let targets = ["Documents", "Library", "tmp"].map {
        home.appendingPathComponent($0, isDirectory: true)
    }
    
    let keep: Set<String> = [
        home.appendingPathComponent("Library/Caches").standardizedFileURL.path,
        home.appendingPathComponent("Library/Preferences").standardizedFileURL.path,
    ]
    
    c.recoveryLogMax = max(c.recoveryLogMax, 16)
    
    let started = CFAbsoluteTimeGetCurrent()
    c.recoveryLog("\n-- 正在清除数据…")
    
    var prefsOK = true
    if let id = Bundle.main.bundleIdentifier {
        let savedData = UserDefaults.standard.object(forKey: "LCCertificateData")
        let savedPassword = UserDefaults.standard.object(forKey: "LCCertificatePassword")
        
        let before = UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
        c.recoveryLog("正在清理偏好设置（\(before) 项）…")
        
        UserDefaults.standard.removePersistentDomain(forName: id)
        
        if let savedData = savedData {
            UserDefaults.standard.set(savedData, forKey: "LCCertificateData")
        }
        if let savedPassword = savedPassword {
            UserDefaults.standard.set(savedPassword, forKey: "LCCertificatePassword")
        }
        
        let after = UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
        if after != 2 {
            c.recoveryLogError("  失败：仍剩余 \(after) 项")
            prefsOK = false
        }
    } else {
        c.recoveryLogError("  失败：缺少包标识符")
        prefsOK = false
    }
    
    DispatchQueue.global(qos: .userInitiated).async {
        var success = prefsOK
        var totalBytes: Int64 = 0
        
        for dir in targets {
            let name = dir.lastPathComponent
            DispatchQueue.main.async { c.recoveryLog("正在格式化 /\(name)…") }
            
            var stats = WipeStats()
            let ok = removeTree(dir, keeping: keep, isRoot: true, home: homePath, stats: &stats)
            success = success && ok
            totalBytes += stats.bytes
            
            let summary = "  \(stats.removedFiles) 个文件，\(stats.removedDirectories) 个目录，\(formatBytes(stats.bytes))"
            let shown = Array(stats.failures.prefix(maxFailuresShown))
            let hidden = stats.failures.count - shown.count
            
            DispatchQueue.main.async {
                c.recoveryLog(summary)
                for f in shown {
                    c.recoveryLogError("  失败：\(f.path)：\(f.reason)")
                }
                if hidden > 0 {
                    c.recoveryLogError("  …另有 \(hidden) 条（详见系统日志）")
                }
            }
        }
        
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started)
        let tail = "（共 \(formatBytes(totalBytes))，用时 \(elapsed) 秒）"
        
        DispatchQueue.main.async {
            if success {
                c.recoveryLog("数据清除完成。\(tail)")
            } else {
                c.recoveryLogError("数据清除失败。\(tail)")
            }
        }
    }
}

func recoveryWipeCache(_ c: NXRecoveryViewController) {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    let homePath = home.path
    
    let targets = ["Library/Caches", "tmp"].map {
        home.appendingPathComponent($0, isDirectory: true)
    }
    
    let keep: Set<String> = [
        home.appendingPathComponent("Library/Caches").standardizedFileURL.path,
        home.appendingPathComponent("Library/Preferences").standardizedFileURL.path,
    ]
    
    c.recoveryLogMax = max(c.recoveryLogMax, 16)
    
    let started = CFAbsoluteTimeGetCurrent()
    c.recoveryLog("\n-- 正在清除缓存…")
    
    DispatchQueue.global(qos: .userInitiated).async {
        var success = true
        var totalBytes: Int64 = 0
        
        for dir in targets {
            let name = dir.lastPathComponent
            DispatchQueue.main.async { c.recoveryLog("正在格式化 /\(name)…") }
            
            var stats = WipeStats()
            let ok = removeTree(dir, keeping: keep, isRoot: true, home: homePath, stats: &stats)
            success = success && ok
            totalBytes += stats.bytes
            
            let summary = "  \(stats.removedFiles) 个文件，\(stats.removedDirectories) 个目录，\(formatBytes(stats.bytes))"
            let shown = Array(stats.failures.prefix(maxFailuresShown))
            let hidden = stats.failures.count - shown.count
            
            DispatchQueue.main.async {
                c.recoveryLog(summary)
                for f in shown {
                    c.recoveryLogError("  失败：\(f.path)：\(f.reason)")
                }
                if hidden > 0 {
                    c.recoveryLogError("  …另有 \(hidden) 条（详见系统日志）")
                }
            }
        }
        
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started)
        let tail = "（共 \(formatBytes(totalBytes))，用时 \(elapsed) 秒）"
        
        DispatchQueue.main.async {
            if success {
                c.recoveryLog("缓存清除完成。\(tail)")
            } else {
                c.recoveryLogError("缓存清除失败。\(tail)")
            }
        }
    }
}

func recoveryConfirmWipe(recoveryController c: NXRecoveryViewController) {
    c.enterRecovery(
        withHeader: "要清除所有用户数据吗？\n此操作无法撤销！",
        instructions: nil,
        footer: nil,
        items: [
            NXRecoveryItem(title: "取消") { c in
                if let c = c { recoveryShowMenu(recoveryController: c) }
            },
            NXRecoveryItem(title: "恢复出厂设置") { c in
                guard let c = c else { return }
                recoveryShowMenu(recoveryController: c)
                recoveryWipeData(c)
            },
        ],
        onSelect: nil,
        onMove: nil
    )
}

@discardableResult private func runUninstaller(_ log: RomLog) -> Bool {
    let slot = flashedSlotURL()
    let manifestURL = slot.appendingPathComponent("manifest.plist")
    guard FileManager.default.fileExists(atPath: manifestURL.path) else { return true }
    
    do {
        let manifest = try ROMManifest(manifestPlistURL: manifestURL)
        guard let uninstaller = manifest.uninstaller else { return true }
        log.info("正在运行 \(manifest.name) 的卸载器")
        try runRomGeneric(uninstaller, symbol: "NXRomUninstall", slot: slot, onLine: log.rom)
        log.info("卸载器执行完毕")
        return true
    } catch {
        log.error("卸载器运行失败：\(error.localizedDescription)")
        return false
    }
}

private func removeFlashedSlot(_ log: RomLog) {
    do {
        try FileManager.default.removeItem(at: flashedSlotURL())
        log.info("已移除刷入的 ROM，下次启动将使用 SuperSlot.dylib")
    } catch {
        log.error("错误：\(errnoDescription(error))")
    }
}

func recoveryShowUnflash(recoveryController c: NXRecoveryViewController) {
    guard !romIsBusy(c) else { return }
    
    let slot = flashedSlotURL()
    guard FileManager.default.fileExists(atPath: slot.path) else {
        c.recoveryLogError("未刷入任何 ROM")
        return
    }
    
    let manifest = try? ROMManifest(manifestPlistURL: slot.appendingPathComponent("manifest.plist"))
    
    let header: String
    if let manifest {
        header = "取消刷入 \(manifest.name) \(manifest.version)？\n\(manifest.identifier)"
    } else {
        header = "取消刷入 ROM？\n清单不可读，只能强制移除"
    }
    
    var items: [NXRecoveryItem] = [
        NXRecoveryItem(title: "../") { c in
            if let c = c { recoveryShowMenu(recoveryController: c) }
        }
    ]
    
    if let manifest {
        let title = manifest.uninstaller != nil ? "卸载 ROM" : "移除 ROM（无卸载器）"
        items.append(NXRecoveryItem(title: title) { c in
            guard let c = c else { return }
            recoveryShowMenu(recoveryController: c)
            runRomOperation(c) { log in
                log.info("\n-- 正在取消刷入 \(manifest.name)…")
                
                guard runUninstaller(log) else {
                    log.error("ROM 已保留，如仍需删除请使用强制移除")
                    return
                }
                removeFlashedSlot(log)
            }
        })
    }
    
    items.append(NXRecoveryItem(title: "强制移除（跳过卸载器）") { c in
        guard let c = c else { return }
        recoveryShowMenu(recoveryController: c)
        runRomOperation(c) { log in
            log.info("\n-- 正在强制移除 ROM…")
            log.error("已跳过卸载器，槽位外的残留文件可能仍会保留")
            removeFlashedSlot(log)
        }
    })
    
    c.enterRecovery(
        withHeader: header,
        instructions: nil,
        footer: nil,
        items: items,
        onSelect: nil,
        onMove: nil
    )
}

private func flashROM(archive: URL, log: RomLog) throws -> ROMManifest {
    let fm = FileManager.default
    let slot = flashedSlotURL()
    
    log.info("\n-- 正在刷入 ROM…")
    log.info("已选择的 ROM：\(archive.lastPathComponent)")
    
    try? fm.removeItem(at: slot)
    try fm.createDirectory(at: slot, withIntermediateDirectories: true, attributes: [:])
    
    guard unzipArchiveAtPathWithoutParentDirectory(archive.path, slot.path) else {
        throw romError("解压 ROM 失败")
    }
    
    log.info("ROM 解压完成")
    
    let manifest: ROMManifest = try ROMManifest(manifestPlistURL: slot.appendingPathComponent("manifest.plist"))
    
    log.info("正在设置默认文件与目录权限")
    guard let enumerator = fm.enumerator(at: slot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
        throw NSError(domain: "org.emexlabs.nyxian.bootloader.rom-flash", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法枚举 \(slot)"])
    }
    var dirs: [URL] = [slot]
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: Set([.isDirectoryKey, .isSymbolicLinkKey]))
        if values.isSymbolicLink == true { continue }
        if values.isDirectory == true {
            dirs.append(url)
        } else {
            try fm.setAttributes([.posixPermissions: manifest.defaultFilePermission], ofItemAtPath: url.path)
        }
    }
    for dir in dirs.reversed() {
        try fm.setAttributes([.posixPermissions: manifest.defaultDirectoryPermission], ofItemAtPath: dir.path)
    }
    
    log.info("正在设置显式路径权限与配置")
    var signFiles: [ROMPath] = []
    for path in manifest.paths {
        log.info("正在配置 \(path.path)")
        
        if path.codesigning.needed {
            signFiles.append(path)
        } else {
            try fm.setAttributes([.posixPermissions: path.permission], ofItemAtPath: slot.appendingPathComponent(path.path).path)
        }
    }
    
    if !signFiles.isEmpty {
        log.info("正在为文件签名")
        for file in signFiles {
            guard NXSignMachOAuto(slot.appendingPathComponent(file.path)) else {
                throw romError("签名 \(file.path) 失败")
            }
            log.info("已签名 \(file.path)")
        }
        
        log.info("正在刷新已签名的文件")
        for file in signFiles {
            guard refreshVnode(atPath: slot.appendingPathComponent(file.path).path) else {
                throw romError("刷新 \(file.path) 失败")
            }
            log.info("已刷新 \(file.path)")
        }
        
        log.info("按需添加 NXT2 权限")
        for file in signFiles {
            if file.codesigning.neededNXT2 {
                let kr: kern_return_t = trust_nxt2_sign(slot.appendingPathComponent(file.path).path, file.codesigning.nxt2 as CFDictionary, true, nil)
                if kr != 0 {
                    throw romError("为 \(file.path) 添加 NXT2 权限失败：\(String(cString: mach_error_string(kr)))")
                }
                log.info("已为 \(file.path) 添加 NXT2 权限")
            }
        }
        
        log.info("正在修正签名文件的权限")
        for file in signFiles {
            try fm.setAttributes([.posixPermissions: file.permission], ofItemAtPath: slot.appendingPathComponent(file.path).path)
        }
    }
    
    if let installer = manifest.installer {
        log.info("正在运行安装器")
        do {
            try runRomGeneric(installer, symbol: "NXRomInstall", slot: slot, onLine: log.rom)
        } catch {
            throw romError("安装器运行失败：\(error.localizedDescription)")
        }
        log.info("安装器执行完毕")
    }
    
    return manifest
}

private func recoveryFlashROM(_ c: NXRecoveryViewController, archive: URL) {
    guard !romIsBusy(c) else { return }
    c.enterConsole()
    
    runRomOperation(c) { log in
        do {
            let manifest = try flashROM(archive: archive, log: log)
            log.info("已刷入 \(manifest.name) \(manifest.version)")
            DispatchQueue.main.async {
                c.recoveryLog("\n刷入完成。\n准备好后请同时按住两个音量键重启。")
                c.finishConsole(selectAction: { _ in
                    restartSelf()
                })
            }
        } catch {
            log.error("错误：\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: flashedSlotURL())
            DispatchQueue.main.async {
                c.recoveryLogError("\n刷入失败。\n请同时按住两个音量键返回菜单。")
                c.finishConsole(selectAction: { c in
                    guard let c = c else { return }
                    c.exitConsole()
                    recoveryShowMenu(recoveryController: c)
                })
            }
        }
    }
}

// Cuz it is weak
let romImporter: ROMImporter = ROMImporter()

func recoveryShowMenu(recoveryController: NXRecoveryViewController) {
    recoveryController.enterRecovery(
        withHeader: "Nyxian 恢复模式\n\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") ?? "UNKNOWN") \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0.0.0") \"Scriptura\" Beta (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "UNKNOWN"))",
        instructions: nil,
        footer: nil,
        items: [
            NXRecoveryItem(title: "立即重启系统") { c in
                restartSelf()
            },
            NXRecoveryItem(title: "启动配置") { c in
                if let c = c {
                    recoveryShowBootConfig(recoveryController: c)
                }
            },
            NXRecoveryItem(title: "清除数据 / 恢复出厂") { c in
                if let c = c {
                    recoveryConfirmWipe(recoveryController: c)
                }
            },
            NXRecoveryItem(title: "清除缓存") { c in
                if let c = c {
                    recoveryWipeCache(c)
                }
            },
            NXRecoveryItem(title: "刷入 ROM") { c in
                guard let c = c, !romIsBusy(c) else { return }
                romImporter.present(from: c) { url in
                    if let url = url {
                        recoveryFlashROM(c, archive: url)
                    }
                }
            },
            NXRecoveryItem(title: "取消刷入 ROM") { c in
                if let c = c {
                    recoveryShowUnflash(recoveryController: c)
                }
            },
            NXRecoveryItem(title: "Nyxian 文件") { c in
                c?.enterFileBrowser(atPath: NSHomeDirectory(), root: NSHomeDirectory(), header: "Nyxian 文件", onBack: { recovery in
                    if let recovery = recovery {
                        recoveryShowMenu(recoveryController: recovery)
                    }
                }, onFile: { path,name,controller in
                })
            },
            NXRecoveryItem(title: "系统文件") { c in
                c?.enterFileBrowser(atPath: "/", root: "/", header: "系统文件", onBack: { recovery in
                    if let recovery = recovery {
                        recoveryShowMenu(recoveryController: recovery)
                    }
                }, onFile: { path,name,controller in
                })
            },
            NXRecoveryItem(title: "关机") { c in
                UIApplication.shared.perform(Selector("suspend"))
                exit(0)
            },
        ],
        onSelect: nil,
        onMove: nil
    )
}

class BootViewController: UIViewController {
    private let splashView = UIView()
    private let logoView = UIImageView()
    
    private enum BootTransition {
        case zoomThrough
        case crossfade
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        BootConfig.registerDefaults()
        
        self.view.backgroundColor = .systemBackground
        
        splashView.backgroundColor = self.view.backgroundColor
        splashView.frame = self.view.bounds
        splashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(splashView)
        
        let slot: URL = flashedSlotURL()
        if let manifest: ROMManifest = try? ROMManifest(manifestPlistURL: slot.appendingPathComponent("manifest.plist")),
           let logo: UIImage = manifest.bootlogo {
            logoView.image = logo
        } else {
            logoView.image = UIImage(named: "EmexLogo")
        }
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        
        splashView.addSubview(logoView)
        
        NSLayoutConstraint.activate([
            logoView.centerYAnchor.constraint(equalTo: splashView.centerYAnchor),
            logoView.centerXAnchor.constraint(equalTo: splashView.centerXAnchor),
            logoView.heightAnchor.constraint(equalToConstant: 125),
            logoView.widthAnchor.constraint(equalToConstant: 125),
        ])
        
        DispatchQueue.global(qos: .utility).async {
            let mode = NXVolumeButtonMonitor.scan(for: 1.0)
            NXVolumeButtonMonitor.disarm()
            
            if mode == 2 {
                DispatchQueue.main.async {
                    self.enterRecovery(error: nil)
                }
                return
            }
            
            let slot = loadSlot(loadSuperslotForcefully: mode == 1)
            
            DispatchQueue.main.async {
                guard case let .loaded(name, slotMain, slotDidAppear, slotCreateWindow) = slot else {
                    if case let .failed(message) = slot {
                        self.enterRecovery(error: "错误：\(message)")
                    }
                    return
                }
                
                guard let raw = slotMain() else {
                    self.enterRecovery(error: "错误：\(name) 的 NXSlotMain 未返回视图控制器")
                    return
                }
                let slotRoot = Unmanaged<UIViewController>.fromOpaque(raw).takeRetainedValue()
                
                self.changableStatusBarHidden = false
                UIView.animate(withDuration: 0.3) {
                    self.setNeedsStatusBarAppearanceUpdate()
                }
                
                if let slotCreateWindow, let slotWindow = self.makeSlotWindow(slotCreateWindow) {
                    self.transition(into: slotWindow, root: slotRoot) {
                        slotDidAppear?()
                    }
                } else {
                    self.transition(to: slotRoot) {
                        slotDidAppear?()
                    }
                }
            }
        }
    }
    
    private func makeSlotWindow(_ create: NXSlotCreateWindowFn) -> UIWindow? {
        guard let scene = view.window?.windowScene else { return nil }
        guard let raw = create(Unmanaged.passUnretained(scene).toOpaque()) else { return nil }
        return Unmanaged<UIWindow>.fromOpaque(raw).takeRetainedValue()
    }
    
    private func transition(into slotWindow: UIWindow,
                            root: UIViewController,
                            completion: (() -> Void)? = nil) {
        let hostWindow = view.window
        
        slotWindow.rootViewController = root
        slotWindow.alpha = 0
        slotWindow.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        
        if let presentation = logoView.layer.presentation() {
            logoView.layer.transform = presentation.transform
        }
        logoView.layer.removeAnimation(forKey: "breathe")
        
        let finish = {
            hostWindow?.isHidden = true
            hostWindow?.rootViewController = nil
            if let scene = slotWindow.windowScene {
                (scene.delegate as? SceneDelegate)?.window = slotWindow
            }
            completion?()
        }
        
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, animations: {
                slotWindow.alpha = 1
            }, completion: { _ in
                finish()
            })
            return
        }
        
        root.view.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        
        let splashOut = UIViewPropertyAnimator(duration: 0.4, curve: .easeOut) {
            self.logoView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            self.splashView.alpha = 0
            slotWindow.alpha = 1
        }
        
        let appIn = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 1.0) {
            root.view.transform = .identity
        }
        
        appIn.addCompletion { _ in
            finish()
        }
        
        splashOut.startAnimation()
        appIn.startAnimation()
    }
    
    private func enterRecovery(error: String?) {
        let recoveryController = NXRecoveryViewController()
        if let error {
            recoveryController.recoveryLogError(error)
        }
        recoveryShowMenu(recoveryController: recoveryController)
        self.transition(to: recoveryController, style: .crossfade)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startBreathing()
    }
    
    private func startBreathing() {
        guard !UIAccessibility.isReduceMotionEnabled,
              splashView.superview != nil,
              logoView.layer.animation(forKey: "breathe") == nil else { return }
        
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 0.94
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        logoView.layer.add(pulse, forKey: "breathe")
    }
    
    private func transition(to child: UIViewController,
                            style: BootTransition = .zoomThrough,
                            completion: (() -> Void)? = nil) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(child.view, belowSubview: splashView)
        child.view.layoutIfNeeded()
        
        if let presentation = logoView.layer.presentation() {
            logoView.layer.transform = presentation.transform
        }
        logoView.layer.removeAnimation(forKey: "breathe")
        
        let finish = {
            self.splashView.removeFromSuperview()
            child.didMove(toParent: self)
            completion?()
        }
        
        if style == .crossfade || UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, animations: {
                self.splashView.alpha = 0
            }, completion: { _ in
                finish()
            })
            return
        }
        
        child.view.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        
        let splashOut = UIViewPropertyAnimator(duration: 0.4, curve: .easeOut) {
            self.logoView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            self.splashView.alpha = 0
        }
        
        let appIn = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 1.0) {
            child.view.transform = .identity
        }
        
        appIn.addCompletion { _ in
            finish()
        }
        
        splashOut.startAnimation()
        appIn.startAnimation()
    }
    
    var changableStatusBarHidden = true
    override var prefersStatusBarHidden: Bool {
        return self.changableStatusBarHidden
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    override var childForStatusBarStyle: UIViewController? {
        splashView.superview == nil ? children.last : nil
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
