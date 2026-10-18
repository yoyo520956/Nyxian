/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 拷贝right (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero 通用 Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero 通用 Public License for more details.

 You should have received a copy of the GNU Affero 通用 Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import Foundation
import UIKit
import Darwin
import Uniform类型Identifiers

class FileInfoViewController: NXUITableViewController {
    
    private struct Row {
        let title: String
        var value: String
        var monospaced: Bool = false
    }
    
    private struct Section {
        let title: String?
        var rows: [Row]
    }
    
    let fileEntry: FileListEntry
    let fileAttr: [FileAttributeKey: Any]
    
    private var sections: [Section] = []
    
    private var directory大小IndexPath: IndexPath?
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()
    
    init(fileEntry: FileListEntry) throws {
        self.fileEntry = fileEntry
        self.fileAttr = try FileManager.default.attributesOfItem(atPath: fileEntry.path)
        
        super.init(style: .inset群组ed)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "\(self.fileEntry.name) 信息"
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "filelist.info.vc")
        
        self.buildSections()
        
        if self.file类型 == .type目录 {
            self.load目录大小()
        }
    }
    
    private var file类型: FileAttribute类型? {
        guard let raw = self.fileAttr[.type] as? String else { return nil }
        return FileAttribute类型(rawValue: raw)
    }
    
    private var logical大小: Int64 {
        (self.fileAttr[.size] as? NSNumber)?.int64Value ?? 0
    }
    
    private func number(_ key: FileAttributeKey) -> NSNumber? {
        self.fileAttr[key] as? NSNumber
    }
    
    private func date(_ key: FileAttributeKey) -> String? {
        guard let date = self.fileAttr[key] as? Date else { return nil }
        return Self.dateFormatter.string(from: date)
    }
    
    private static func describe(_ type: FileAttribute类型?) -> String {
        switch type {
            case .some(.typeRegular):
                return "普通文件"
            case .some(.type目录):
                return "目录"
            case .some(.typeSymbolicLink):
                return "符号链接"
            case .some(.type套接字):
                return "套接字"
            case .some(.typeCharacterSpecial):
                return "字符设备"
            case .some(.typeBlockSpecial):
                return "块设备"
            default:
                return "未知"
        }
    }
    
    private static func describe权限(_ mode: UInt16) -> String {
        let bits = ["---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx"]
        let owner = bits[Int((mode >> 6) & 0o7)]
        let group = bits[Int((mode >> 3) & 0o7)]
        let other = bits[Int(mode & 0o7)]
        return "\(owner)\(group)\(other) (\(String(mode & 0o7777, radix: 8)))"
    }
    
    private static func describe保护(_ raw: String) -> String {
        switch File保护类型(rawValue: raw) {
            case .complete:
                return "Complete"
            case .completeUnlessOpen:
                return "打开前保持完整"
            case .completeUntilFirstUserAuthentication:
                return "首次解锁前"
            case .none:
                return "None"
            default:
                return raw
        }
    }
    
    private static func kind(for path: String, type: FileAttribute类型?) -> String {
        if type == .type目录 { return "文件夹" }
        if type == .typeSymbolicLink { return "别名" }
        
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty,
           let ut类型 = UT类型(filenameExtension: ext),
           let description = ut类型.localizedDescription {
            return description
        }
        return ext.isEmpty ? "文档" : "\(ext.uppercased()) 文件"
    }
    
    private static func allocated大小(for path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.totalFileAllocated大小Key])
        return (values?.totalFileAllocated大小).map(Int64.init)
    }
    
    private static func extendedAttribute名称s(atPath path: String) -> [String] {
        let length = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard length > 0 else {
            return []
        }
        
        var buffer = [CChar](repeating: 0, count: length)
        guard listxattr(path, &buffer, length, XATTR_NOFOLLOW) > 0 else { return [] }
        
        return buffer.split(separator: 0).compactMap { slice in
            String(cString: Array(slice) + [0])
        }
    }
    
    private func buildSections() {
        let path = self.fileEntry.path
        let type = self.file类型
        var result: [Section] = []
        
        var general: [Row] = [
            Row(title: "名称", value: self.fileEntry.name),
            Row(title: "种类", value: Self.kind(for: path, type: type))
        ]
        
        if type == .type目录 {
            general.append(Row(title: "大小", value: "计算中\u{2026}"))
            self.directory大小IndexPath = IndexPath(row: general.count - 1, section: 0)
        } else {
            general.append(Row(title: "大小", value: ByteCountFormatter.string(fromByteCount: self.logical大小, countStyle: .file)))
            if let allocated = Self.allocated大小(for: path), allocated != self.logical大小 {
                general.append(Row(title: "磁盘占用", value: ByteCountFormatter.string(fromByteCount: allocated, countStyle: .file)))
            }
        }
        
        if type == .typeSymbolicLink, let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            general.append(Row(title: "目标", value: target, monospaced: true))
        }
        
        general.append(Row(title: "位置", value: (path as NSString).deletingLastPathComponent, monospaced: true))
        result.append(Section(title: "通用", rows: general))
        
        var dates: [Row] = []
        if let created = self.date(.creationDate) {
            dates.append(Row(title: "创建时间", value: created))
        }
        if let modified = self.date(.modificationDate) {
            dates.append(Row(title: "修改时间", value: modified))
        }
        if !dates.isEmpty {
            result.append(Section(title: "日期", rows: dates))
        }
        
        var ownership: [Row] = []
        if let owner = self.fileAttr[.ownerAccount名称] as? String {
            ownership.append(Row(title: "所有者", value: owner))
        } else if let uid = self.number(.ownerAccountID) {
            ownership.append(Row(title: "所有者", value: "uid \(uid.intValue)"))
        }
        if let group = self.fileAttr[.group所有者Account名称] as? String {
            ownership.append(Row(title: "群组", value: group))
        } else if let gid = self.number(.group所有者AccountID) {
            ownership.append(Row(title: "群组", value: "gid \(gid.intValue)"))
        }
        if let mode = self.number(.posix权限)?.uint16Value {
            ownership.append(Row(title: "权限", value: Self.describe权限(mode), monospaced: true))
        }
        if let protection = self.fileAttr[.protectionKey] as? String {
            ownership.append(Row(title: "保护", value: Self.describe保护(protection)))
        }
        if !ownership.isEmpty {
            result.append(Section(title: "所有权", rows: ownership))
        }
        
        var advanced: [Row] = [Row(title: "类型", value: Self.describe(type))]
        if let inode = self.number(.systemFileNumber) {
            advanced.append(Row(title: "Inode", value: "\(inode.uint64Value)", monospaced: true))
        }
        if let links = self.number(.referenceCount), links.intValue > 1 {
            advanced.append(Row(title: "硬链接数", value: "\(links.intValue)"))
        }
        
        var flags: [String] = []
        if self.number(.不可变)?.boolValue == true { flags.append("不可变") }
        if self.number(.appendOnly)?.boolValue == true { flags.append("仅追加") }
        if self.number(.extensionHidden)?.boolValue == true { flags.append("隐藏扩展名") }
        if !flags.isEmpty {
            advanced.append(Row(title: "标志", value: flags.joined(separator: ", ")))
        }
        result.append(Section(title: "高级", rows: advanced))
        
        let xattrs = Self.extendedAttribute名称s(atPath: path)
        if !xattrs.isEmpty {
            result.append(Section(title: "扩展属性", rows: xattrs.map { Row(title: $0, value: "", monospaced: true) }))
        }
        
        self.sections = result
    }
    
    private func load目录大小() {
        let path = self.fileEntry.path
        
        Task.detached(priority: .utility) {
            var total: Int64 = 0
            var items = 0
            
            let url = URL(fileURLWithPath: path)
            let keys: Set<URLResourceKey> = [.totalFileAllocated大小Key, .file大小Key, .isRegularFileKey]
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) {
                for case let child as URL in enumerator {
                    guard let values = try? child.resourceValues(forKeys: keys) else { continue }
                    items += 1
                    if values.isRegularFile == true {
                        total += Int64(values.totalFileAllocated大小 ?? values.file大小 ?? 0)
                    }
                }
            }
            
            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let summary = "\(formatted), \(items) item\(items == 1 ? "" : "s")"
            
            await MainActor.run { [weak self] in
                guard let self, let indexPath = self.directory大小IndexPath else {
                    return
                }
                self.sections[indexPath.section].rows[indexPath.row].value = summary
                if self.isViewLoaded {
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }
            }
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].rows.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sections[section].title
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "filelist.info.vc", for: indexPath)
        let row = self.sections[indexPath.section].rows[indexPath.row]
        
        var config = UIListContentConfiguration.valueCell()
        config.text = row.title
        config.secondaryText = row.value.isEmpty ? nil : row.value
        config.prefersSideBySideTextAndSecondaryText = true
        config.secondaryTextProperties.numberOfLines = 0
        if row.monospaced {
            config.secondaryTextProperties.font = .monospacedSystemFont(of大小: 15, weight: .regular)
        }
        
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let row = self.sections[indexPath.section].rows[indexPath.row]
        let copied = row.value.isEmpty ? row.title : row.value
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(title: "拷贝", image: UIImage(system名称: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = copied
                }
            ])
        }
    }
}
