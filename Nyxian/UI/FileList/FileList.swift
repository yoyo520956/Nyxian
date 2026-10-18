/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 拷贝right (C) 2025 - 2026 emexlab

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

class 文件ListViewController: NXUITableViewController, UIDocumentPickerDelegate {
    let project: NX工程?
    let path: String
    var entries: [文件ListEntry]
    let isSublink: Bool
    let isReadOnly: Bool
    var is选择ing: Bool = false
    var selectedPaths: Set<String> = []
    
    var observation: NSKeyValueObservation?

    init(isSublink: Bool = false,
         project: NX工程?,
         path: String? = nil,
         isReadOnly: Bool = false) {
        self.isReadOnly = isReadOnly
        self.project = project
        
        if let project = project {
            NXUser.shared().project名称 = project.projectConfig.display名称
            self.path = path ?? project.url.path
        } else {
            self.path = path ?? ""
        }
        
        self.entries = 文件ListEntry.getEntries(ofPath: self.path)
        self.isSublink = isSublink
        super.init(style: .insetGrouped)
        
        self.refreshControl = UIRefreshControl()
        self.refreshControl?.addTarget(self, action: #selector(performRefresh), for: .valueChanged)
    }
    
    init(isSublink: Bool = false,
         path: String,
         isReadOnly: Bool = false)
    {
        self.project = nil
        self.path = path
        self.entries = 文件ListEntry.getEntries(ofPath: self.path)
        self.isSublink = isSublink
        self.isReadOnly = isReadOnly
        super.init(style: .insetGrouped)
        
        self.refreshControl = UIRefreshControl()
        self.refreshControl?.addTarget(self, action: #selector(performRefresh), for: .valueChanged)
    }
    
    @objc func performRefresh() {
        if !self.isSublink, let project = self.project {
            if project.reload() {
                self.title = project.projectConfig.display名称
            }
        }
        
        self.entries = 文件ListEntry.getEntries(ofPath: self.path)
        self.refreshControl?.endRefreshing()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.tableView.visibleCells.forEach { cell in
                cell.alpha = 0
            }
            
            self.tableView.reloadData()
            
            self.tableView.layoutIfNeeded()
            
            guard let visibleCells = self.tableView.visibleCells as? [文件ListCell] else { return }
            
            visibleCells.forEach { cell in
                cell.transform = CGAffineTransform(translationX: -30, y: 0)
                cell.alpha = 0
            }
            
            for (index, cell) in visibleCells.enumerated() {
                let delay = Double(index) * 0.02
                UIView.animate(withDuration: 0.6, delay: delay, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.curveEaseOut], animations: {
                    cell.transform = .identity
                    cell.alpha = 1
                })
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatal错误("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.register(文件ListCell.self, forCellReuseIdentifier: 文件ListCell.reuseIdentifier)
        
        if let project = self.project {
            if !self.isSublink {
                observation = project.observe(\.projectConfig.dictionary, options: [.new, .old]) { [weak self] project, change in
                    DispatchQueue.main.async {
                        self?.title = project.projectConfig.display名称
                    }
                }
                self.title = project.projectConfig.display名称
            } else {
                self.title = URL(fileURLWithPath: self.path).lastPathComponent
            }
        } else {
            self.title = URL(fileURLWithPath: self.path).lastPathComponent
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad, !self.isSublink {
            self.navigationItem.setLeftBarButton(UIBarButtonItem(primaryAction: UIAction(title: "关闭") { [weak self] _ in
                guard let self = self else { return }
                UserDefaults.standard.set(nil, forKey: "LDELast工程选择ed")
                self.dismiss(animated: true)
            }), animated: false)
        }
        
        if !self.isReadOnly {
            if #available(iOS 26.0, *) {
                self.navigationItem.setRightBarButton(UIBarButtonItem(image: UIImage(system名称: "ellipsis.circle.fill"), primaryAction: nil, menu: generateMenu()), animated: false)
            } else {
                self.navigationItem.setRightBarButton(UIBarButtonItem(image: UIImage(system名称: "ellipsis.circle"), primaryAction: nil, menu: generateMenu()), animated: false)
            }
        }
    }

    @objc func toggle选择ionMode() {
        is选择ing.toggle()
        selectedPaths.removeAll()

        tableView.allowsMultiple选择ion = is选择ing

        navigationItem.rightBarButtonItem?.isEnabled = !is选择ing

        if is选择ing {
            let deleteButton = UIBarButtonItem(title: "删除", style: .plain, target: self, action: #selector(delete选择ed))
            deleteButton.tintColor = .systemRed
            let copyButton = UIBarButtonItem(title: "拷贝", style: .plain, target: self, action: #selector(copy选择ed))
            let shareButton = UIBarButtonItem(title: "分享", style: .plain, target: self, action: #selector(share选择ed))
            let spacer = UIBarButtonItem(barButton系统Item: .flexibleSpace, target: nil, action: nil)
            
            setToolbarItems([deleteButton, spacer, copyButton, spacer, shareButton], animated: true)
            navigationController?.setToolbarHidden(false, animated: true)
            tabBarController?.tabBar.isHidden = true
            
            let doneButton = UIBarButtonItem(title: "完成", style: .plain, target: self, action: #selector(toggle选择ionMode))
            navigationItem.setLeftBarButton(doneButton, animated: true)
            self.refreshControl = nil
        } else {
            setToolbarItems(nil, animated: true)
            navigationController?.setToolbarHidden(true, animated: true)
            tabBarController?.tabBar.isHidden = false
            
            if UIDevice.current.userInterfaceIdiom == .pad,
               !self.isSublink {
                self.navigationItem.setLeftBarButton(UIBarButtonItem(primaryAction: UIAction(title: "关闭") { [weak self] _ in
                    guard let self = self else { return }
                    UserDefaults.standard.set(nil, forKey: "LDELast工程选择ed")
                    self.dismiss(animated: true)
                }), animated: true)
            } else {
                navigationItem.setLeftBarButton(nil, animated: true)
            }
            
            self.refreshControl = UIRefreshControl()
            self.refreshControl?.addTarget(self, action: #selector(performRefresh), for: .valueChanged)
            tableView.reloadData()
        }
    }

    @objc func delete选择ed() {
        guard !selectedPaths.isEmpty else { return }

        let alert = UIAlertController(
            title: "删除 \(selectedPaths.count) 项？",
            message: "此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }

            for path in self.selectedPaths {
                let fileUrl = URL(fileURLWithPath: path)
                if ((try? 文件Manager.default.removeItem(at: fileUrl)) != nil), let project = self.project {
                    let database: DebugDatabase = DebugDatabase.getDatabase(ofPath: project.cacheURL.appendingPathComponent("debug.json").path)
                    NotificationCenter.default.post(name: Notification.名称("文件ListAct"), object: ["close", fileUrl.path])
                    database.remove文件Debug(ofPath: fileUrl.path)
                    database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)
                } else {
                    try? 文件Manager.default.removeItem(atPath: path)
                }
            }

            self.entries.removeAll { self.selectedPaths.contains($0.path) }
            self.selectedPaths.removeAll()
            self.tableView.reloadData()
            self.toggle选择ionMode()
        })

        present(alert, animated: true)
    }

    @objc func share选择ed() {
        guard !selectedPaths.isEmpty else { return }
        let urls = selectedPaths.map { URL(fileURLWithPath: $0) }
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        activityVC.modalPresentationStyle = .popover
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = .down
        }
        present(activityVC, animated: true)
    }

    @objc func copy选择ed() {
        粘贴BoardServices.copy(mode: .copy, paths:selectedPaths)
        toggle选择ionMode()
    }

    func createEntry(mode: 文件ListEntry.文件ListEntryType) {
        let alert: UIAlertController = UIAlertController(
            title: "新建\((mode == .file) ? "文件" : "文件夹")",
            message: nil,
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "名称"
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "提交", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let destination: URL = URL(fileURLWithPath: self.path).appendingPathComponent(alert.textFields![0].text ?? "")
            
            var isDirectory: ObjCBool = ObjCBool(false)
            if 文件Manager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
                self.presentConfirmationAlert(
                    title: mode == .dir ? "错误" : "警告",
                    message: "\(isDirectory.boolValue ? "文件夹" : "文件") ，名为“\(destination.lastPathComponent)”已存在。 \(!isDirectory.boolValue ? "" : "文件夹s cannot be removed!")",
                    confirmTitle: "覆盖",
                    confirmStyle: .destructive,
                    confirmHandler: {
                        try? String(NXUser.shared().generate文件CreationContent(for名称: destination.lastPathComponent)).write(to: destination, atomically: true, encoding: .utf8)
                        self.replace文件(destination: destination)
                    },
                    addHandler: mode == .file && !isDirectory.boolValue
                )
            } else {
                if mode == .file {
                    try? String(NXUser.shared().generate文件CreationContent(for名称: destination.lastPathComponent)).write(to: destination, atomically: true, encoding: .utf8)
                } else {
                    try? 文件Manager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                }
                self.add文件(destination: destination)
            }
        })
        
        self.present(alert, animated: true)
    }
    
    func generateMenu() -> UIMenu {
        var rootMenuChildren: [UIMenu] = []
        
        // 工程 Roots Menu in case its the root of the project obviously
        if !self.isSublink, UIDevice.current.userInterfaceIdiom != .pad, let project = self.project {
            var projectMenuElements: [UIMenuElement] = []
            if !NXApplicationState.extensionLessMode {
                projectMenuElements.append(UIAction(title: "运行", image: UIImage(system名称: "play.fill"), handler: { [weak self] _ in
                    guard let self = self else { return }
                    build工程WithArgumentUI(targetViewController: self, project: project, buildType: .run) { result, execPath in
                        if result {
                            if project.projectConfig.schemeKind == .app {
                                PEProcessManager.shared().spawnProcess(withBundleIdentifier: project.projectConfig.bundleid, withItems: [:], withKernelSurfaceProcess: nil, doRestartIf运行ning: true)
                            } else if project.projectConfig.schemeKind == .utility, let execPath = execPath {
                                let terminalSession: NXWindowSessionTerminal = NXWindowSessionTerminal(utilityPath: execPath)
                                NXWindowServer.shared().openWindow(with: terminalSession, withCompletion: nil)
                            }
                        }
                    }
                }))
            }
            projectMenuElements.append(UIAction(title: "导出", image: UIImage(system名称: "archivebox.fill"), handler: { [weak self] _ in
                guard let self = self else { return }
                build工程WithArgumentUI(targetViewController: self, project: project, buildType: .export)
            }))
            projectMenuElements.append(UIAction(title: "问题导航器", image: UIImage(system名称: "exclamationmark.triangle.fill"), handler: { [weak self] _ in
                guard let self = self else { return }
                let loggerView = UINavigationController(rootViewController: UIDebugViewController(project: project))
                loggerView.modalPresentationStyle = .formSheet
                self.present(loggerView, animated: true)
            }))
            
            rootMenuChildren.append({
                return UIMenu(title: "工程", options: [.displayAsPalette, .displayInline], children: projectMenuElements.reversed())
            }())
        }
        
        if !self.isSublink {
            rootMenuChildren.append(UIMenu(title: "系统", options: [.displayInline], children: [
                UIAction(
                    title: "浏览 SDK",
                    image: UIImage(system名称: "books.vertical.fill")
                ) { [weak self] _ in
                    guard let self = self else { return }
                    let fileVC = 文件ListViewController(
                        isSublink: true,
                        project: project,
                        path: NXBootstrap.shared().sdkURL.path,
                        isReadOnly: true
                    )
                    self.navigationController?.pushViewController(fileVC, animated: true)
                },
                UIAction(
                    title: "浏览缓存",
                    image: UIImage(system名称: "folder.fill.badge.person.crop")
                ) { [weak self] _ in
                    guard let self = self else { return }
                    let fileVC = 文件ListViewController(
                        isSublink: true,
                        project: project,
                        path: project?.cacheURL.path ?? "",
                        isReadOnly: true
                    )
                    self.navigationController?.pushViewController(fileVC, animated: true)
                },
                UIAction(
                    title: "配置",
                    image: UIImage(system名称: "folder.fill.badge.gearshape")
                ) { [weak self] _ in
                    guard let self = self else { return }
                    guard let project = self.project else { return }
                    let vc: 工程ConfigViewController = 工程ConfigViewController(project: project)
                    let nvc: UINavigationController = UINavigationController(rootViewController: vc)
                    nvc.modalPresentationStyle = .formSheet
                    nvc.isModalInPresentation = true
                    self.present(nvc, animated: true)
                }
            ]))
        }
        
        if !isReadOnly {
            // The generic file system menu
            var fileMenuElements: [UIMenuElement] = []
            var createMenuElements: [UIMenuElement] = []
            createMenuElements.append(UIAction(title: "文件", image: UIImage(system名称: "doc.fill"), handler: { [weak self] _ in
                guard let self = self else { return }
                self.createEntry(mode: .file)
            }))
            createMenuElements.append(UIAction(title: "文件夹", image: UIImage(system名称: "folder.fill"), handler: { [weak self] _ in
                guard let self = self else { return }
                self.createEntry(mode: .dir)
            }))
            fileMenuElements.append(UIMenu(title: "新建", image: UIImage(system名称: "plus.circle.fill"), children: createMenuElements))
            fileMenuElements.append(UIAction(title: "粘贴", image: UIImage(system名称: "list.bullet.clipboard.fill"), handler: { [weak self] _ in
                guard let self = self else { return }
                粘贴BoardServices.paste(path: self.path) { file in
                    self.add文件(destination: file)
                }
            }))
            fileMenuElements.append(UIAction(title: "导入", image: UIImage(system名称: "square.and.arrow.down.fill")) { [weak self] _ in
                guard let self = self else { return }
                let documentPicker: UIDocumentPickerViewController = UIDocumentPickerViewController(forOpeningContentTypes: [.item], as拷贝: true)
                documentPicker.allowsMultiple选择ion = true
                documentPicker.modalPresentationStyle = .formSheet
                documentPicker.delegate = self
                self.present(documentPicker, animated: true)
            })
            fileMenuElements.append(UIAction(title: "选择", image: UIImage(system名称: "checkmark.circle.fill")) { [weak self] _ in
                guard let self = self else { return }
                self.toggle选择ionMode()
            })

            rootMenuChildren.append(UIMenu(title: "文件", options: [.displayInline], children: fileMenuElements))
        }
        
        return UIMenu(children: rootMenuChildren)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // TODO: Add handling for overwrite and stuff... like keep,rename,overwrite. We also should merge these functions as thats the 3rd time copying those.
        for url in urls {
            let file名称: String = url.lastPathComponent
            let destination: URL = URL(fileURLWithPath: self.path).appendingPathComponent(file名称)
            
            do {
                try 文件Manager.default.moveItem(at: url, to: destination)
                replaceOrAdd文件(destination: destination)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if is选择ing { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggestedActions in
            guard let self = self else { return UIMenu() }
            
            let getInfoAction = UIAction(title: "显示简介", image: UIImage(system名称: "info")) { [weak self] action in
                guard let self = self else { return }
                do {
                    let nav: UINavigationController = UINavigationController(rootViewController: try 文件InfoViewController(fileEntry: self.entries[indexPath.row]))
                    nav.modalPresentationStyle = .formSheet
                    self.present(nav, animated: true)
                } catch {
                    NXAlertDiagnosticPresenter.notifyUser(with: .error, withMessage: "打开文件信息页出错：\(error.localizedDescription)", withDelay: 0.0)
                }
            }
            
            let copyAction = UIAction(title: "拷贝", image: UIImage(system名称: "document.on.clipboard")) { [weak self] action in
                guard let self = self else { return }
                粘贴BoardServices.copy(mode: .copy, paths: [self.entries[indexPath.row].path])
            }
            let moveAction = UIAction(title: "移动", image: UIImage(system名称: "arrow.right")) { [weak self] action in
                guard let self = self else { return }
                let entry = self.entries[indexPath.row]
                粘贴BoardServices.on移动 = { [weak self] in
                    guard let self = self else { return }
                    self.entries.removeAll(where: { $0.path == entry.path })
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                }
                粘贴BoardServices.copy(mode: .move, paths: [entry.path])
            }
            let renameAction = UIAction(title: "重命名", image: UIImage(system名称: "rectangle.and.pencil.and.ellipsis")) { [weak self] action in
                guard let self = self else { return }
                let entry: 文件ListEntry = self.entries[indexPath.row]
                
                let alert: UIAlertController = UIAlertController(
                    title: "重命名\(entry.type == .dir ? "文件夹" : "文件")",
                    message: nil,
                    preferredStyle: .alert
                )
                
                alert.addTextField { textField in
                    textField.placeholder = "文件名"
                    textField.text = entry.name
                }
                
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.addAction(UIAlertAction(title: "重命名", style: .default, handler: { [weak self] _ in
                    guard let self = self else { return }
                    let new名称 = alert.textFields![0].text ?? "0"
                    try? 文件Manager.default.moveItem(atPath: "\(self.path)/\(entry.name)", toPath: "\(self.path)/\(new名称)")
                    
                    if let masterIndex = self.entries.firstIndex(where: { $0.path == entry.path }) {
                        self.entries.remove(at: masterIndex)
                        self.entries.append(文件ListEntry.getEntry(ofPath: "\(self.path)/\(new名称)"))
                    }
                    self.tableView.reloadData()
                }))
                
                self.present(alert, animated: true)
            }
            let shareAction = UIAction(title: "分享", image: UIImage(system名称: "square.and.arrow.up.fill")) { [weak self] action in
                guard let self = self else { return }
                let entry: 文件ListEntry = self.entries[indexPath.row]
                share(url: URL(fileURLWithPath: "\(self.path)/\(entry.name)"), remove: false)
            }
            let deleteAction = UIAction(title: "移除", image: UIImage(system名称: "trash.fill"), attributes: .destructive) { [weak self] action in
                guard let self = self else { return }
                let entry = self.entries[indexPath.row]
                let fileUrl: URL = URL(fileURLWithPath: "\(self.path)/\(entry.name)")
                if ((try? 文件Manager.default.removeItem(at: fileUrl)) != nil) {
                    if let project = self.project {
                        let database: DebugDatabase = DebugDatabase.getDatabase(ofPath: project.cacheURL.appendingPathComponent("debug.json").path)
                        NotificationCenter.default.post(name: Notification.名称("文件ListAct"), object: ["close",fileUrl.path])
                        database.remove文件Debug(ofPath: fileUrl.path)
                        database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)
                    }
                    if let masterIndex = self.entries.firstIndex(where: { $0.path == entry.path }) {
                        self.entries.remove(at: masterIndex)
                    }
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                }
            }
            
            var children: [UIMenu] = []
            children.append(UIMenu(options: .displayInline, children: [getInfoAction]))
            children.append(UIMenu(options: .displayInline, children: self.isReadOnly ? [copyAction] : [copyAction, moveAction, renameAction]))
            children.append(UIMenu(options: .displayInline, children: [shareAction]))
            if !self.isReadOnly {
                children.append(UIMenu(options: .displayInline, children: [deleteAction]))
            }
            return UIMenu(children: children)
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }
    
    override func tableView(_ tableView: UITableView, did选择RowAt indexPath: IndexPath) {
        if is选择ing {
            selectedPaths.insert(entries[indexPath.row].path)
            tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
            return
        }
        
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        guard !self.navigationItem.hidesBackButton,
              self.navigationItem.leftBarButtonItem?.isEnabled ?? true else {
            return
        }
        
        let fileListEntry: 文件ListEntry = entries[indexPath.row]
        
        switch(fileListEntry.type) {
        case .dir:
            let fileVC = 文件ListViewController(isSublink: true, project: project, path: fileListEntry.path, isReadOnly: self.isReadOnly)
            self.navigationController?.pushViewController(fileVC, animated: true)
            break
        case .file:
            if ["zip","ipa"].contains(URL(fileURLWithPath: fileListEntry.path).pathExtension)  {
                let folder: URL = 粘贴BoardServices.resolvedDestinationURL(for: (fileListEntry.path as NSString).lastPathComponent, inDirectory: self.path)
                if ((try? 文件Manager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil) {
                    if(unzipArchiveAtPath(fileListEntry.path, folder.path)) {
                        self.entries.append(文件ListEntry.getEntry(ofPath: folder.path))
                        self.tableView.reloadData()
                    } else {
                        NXAlertDiagnosticPresenter.notifyUser(with: .error, withMessage: "解压 \(fileListEntry.path) 失败", withDelay: 0.0)
                    }
                }
            } else {
                if NXApplicationState.fileListRequiresToSendRequests {
                    NotificationCenter.default.post(name: Notification.名称("文件ListAct"), object: ["open",fileListEntry.path,"0","0",self.isReadOnly ? "1" : "0"])
                } else {
                    guard let codeEditor = CodeEditorViewController(project: project, url: URL(fileURLWithPath: fileListEntry.path), isReadOnly: self.isReadOnly) else {
                        return
                    }
                    let fileVC = UINavigationController(rootViewController: codeEditor)
                    fileVC.modalPresentationStyle = .overFullScreen
                    self.present(fileVC, animated: true)
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if is选择ing {
            selectedPaths.remove(entries[indexPath.row].path)
            
            tableView.cellForRow(at: indexPath)?.accessoryType = (entries[indexPath.row].type == .dir) ? .disclosureIndicator : .none
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: 文件ListCell.reuseIdentifier, for: indexPath) as! 文件ListCell
            
        let entry = entries[indexPath.row]
        cell.configure(with: entry)
            
        return cell
    }
    
    ///
    /// Private: Function to add or replace a file or files in the array
    ///
    private func add文件(destination: URL) {
        self.entries.append(文件ListEntry.getEntry(ofPath: destination.path))
        let newIndexPath = IndexPath(row: self.entries.count - 1, section: 0)
        self.tableView.insertRows(at: [newIndexPath], with: .automatic)
    }
    
    private func replace文件(destination: URL) {
        let index = self.entries.firstIndex(where: { $0.name == destination.lastPathComponent} )
        if let index {
            self.entries.remove(at: index)
            let oldIndexPath = IndexPath(row: index, section: 0)
            self.tableView.deleteRows(at: [oldIndexPath], with: .automatic)
        }
        
        self.entries.append(文件ListEntry.getEntry(ofPath: destination.path))
        let newIndexPath = IndexPath(row: self.entries.count - 1, section: 0)
        self.tableView.insertRows(at: [newIndexPath], with: .automatic)
    }
    
    private func replaceOrAdd文件(destination: URL) {
        if 文件Manager.default.fileExists(atPath: destination.path) {
            replace文件(destination: destination)
        } else {
            add文件(destination: destination)
        }
    }
}

func share(url: URL, remove: Bool = false) {
    let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    
    if remove {
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            do {
                try 文件Manager.default.removeItem(at: url)
            } catch {
                print("删除文件失败：\(error)")
            }
        }
    }
    
    activityViewController.modalPresentationStyle = .popover

    DispatchQueue.main.async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = keyWindow.rootViewController else {
            print("未找到 key window 或根视图控制器。")
            return
        }

        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = topController.view
            popoverController.sourceRect = CGRect(
                x: topController.view.bounds.midX,
                y: topController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popoverController.permittedArrowDirections = []
        }

        topController.present(activityViewController, animated: true)
    }
}
