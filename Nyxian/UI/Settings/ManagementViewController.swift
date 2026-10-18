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

class NXManagementUISingleFlight {
    private static let slot = DispatchSemaphore(value: 1)
    private static let queue = DispatchQueue(label: "org.emexlabs.nyxian.mgmt.singleflight", qos: .userInitiated)
    
    @discardableResult static func run(_ body: @escaping () -> Void) -> Bool {
        guard slot.wait(timeout: .now()) == .success else { return false }
        queue.async {
            defer { self.slot.signal() }
            body()
        }
        return true
    }
}

class ManagementViewController: NXUITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "管理"
        view.backgroundColor = .systemBackground
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch(section) {
            case 0:
                return 1
            case 1:
                return 1
            case 2:
                return 2
            default:
                return 6
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let tableViewCell: UITableViewCell = UITableViewCell()
        
        switch(indexPath.section) {
            case 0:
                tableViewCell.textLabel?.text = "浏览虚拟文件系统"
                tableViewCell.accessoryType = .disclosureIndicator
            case 1:
                tableViewCell.textLabel?.text = "已安装的根证书"
                tableViewCell.accessoryType = .disclosureIndicator
            case 2:
                if indexPath.row == 0 {
                    tableViewCell.textLabel?.text = "已安装的应用"
                    tableViewCell.accessoryType = .disclosureIndicator
                } else if indexPath.row == 1 {
                    tableViewCell.textLabel?.text = "已安装的 KEXT"
                    tableViewCell.accessoryType = .disclosureIndicator
                }
            default:
                if indexPath.row == 0 {
                    tableViewCell.textLabel?.text = "清除图标缓存"
                } else if indexPath.row == 1 {
                    tableViewCell.textLabel?.text = "用户态重启"
                } else if indexPath.row == 2 {
                    tableViewCell.textLabel?.text = "重载守护进程"
                } else if indexPath.row == 3 {
                    tableViewCell.textLabel?.text = "清除应用缓存"
                    tableViewCell.textLabel?.textColor = .systemRed
                } else if indexPath.row == 4 {
                    tableViewCell.textLabel?.text = "重置虚拟环境"
                    tableViewCell.textLabel?.textColor = .systemRed
                } else if indexPath.row == 5 {
                    tableViewCell.textLabel?.text = "重置全部数据"
                    tableViewCell.textLabel?.textColor = .systemRed
                }
        }
        
        return tableViewCell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch(indexPath.section) {
        case 0:
            navigationController?.pushViewController(FileListViewController(isSublink: true, path: NXBootstrap.shared().rootfsURL.path), animated: true)
        case 1:
            print("pressed on list RootCAs")
        case 2:
            if indexPath.row == 0 {
                navigationController?.pushViewController(ApplicationManagementViewController(style: .insetGrouped), animated: true)
            } else {
                navigationController?.pushViewController(KEXTManagementViewController(style: .insetGrouped), animated: true)
            }
        default:
            if indexPath.row == 0 {
                ProjectTableCell.iconCache.removeAllObjects()
            } else if indexPath.row == 1 {
                NXManagementUISingleFlight.run {
                    PEUserspaceManager.shared().rebootUserspace()
                }
            } else if indexPath.row == 2 {
                NXManagementUISingleFlight.run {
                    PEUserspaceManager.shared().reloadDaemons()
                }
            } else if indexPath.row == 3 {
                let alert = UIAlertController(
                    title: "清除应用缓存",
                    message: "所有应用缓存将被清空，这可能带来一些影响，但会减少占用的数据量。（有人出于性能考虑喜欢这样做）",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: nil, message: "正在清除应用缓存", preferredStyle: .alert)
                        
                        let activityIndicator = UIActivityIndicatorView(style: .medium)
                        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                        activityIndicator.startAnimating()
                        
                        alert.view.addSubview(activityIndicator)
                        
                        NSLayoutConstraint.activate([
                            activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
                            activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
                        ])
                        
                        guard let self = self else {
                            return
                        }
                        self.present(alert, animated: true) { [weak self] in
                            guard let self = self else {
                                return
                            }
                            DispatchQueue.global().async { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                let success = PEUserspaceManager.shared().clearApplicationCaches()
                                DispatchQueue.main.async { [weak self] in
                                    guard let self = self else {
                                        return
                                    }
                                    alert.dismiss(animated: true)
                                    if !success {
                                        let alert = UIAlertController(
                                            title: "错误",
                                            message: "清除应用缓存失败",
                                            preferredStyle: .alert
                                        )
                                        
                                        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
                                        
                                        self.present(alert, animated: true)
                                    }
                                }
                            }
                        }
                    }
                })
                
                alert.addAction(UIAlertAction(title: "保留缓存", style: .cancel))
                
                self.present(alert, animated: true)
            } else if indexPath.row == 4 {
                let alert = UIAlertController(
                    title: "重置虚拟环境",
                    message: "虚拟环境中的所有应用、KEXT、二进制和数据容器都将被清空。",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: nil, message: "正在重置", preferredStyle: .alert)
                        
                        let activityIndicator = UIActivityIndicatorView(style: .medium)
                        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                        activityIndicator.startAnimating()
                        
                        alert.view.addSubview(activityIndicator)
                        
                        NSLayoutConstraint.activate([
                            activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
                            activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
                        ])
                        
                        guard let self = self else {
                            return
                        }
                        self.present(alert, animated: true) { [weak self] in
                            guard let self = self else {
                                return
                            }
                            DispatchQueue.global().async { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                let success = PEUserspaceManager.shared().restore()
                                DispatchQueue.main.async { [weak self] in
                                    guard let self = self else {
                                        return
                                    }
                                    alert.dismiss(animated: true)
                                    if !success {
                                        let alert = UIAlertController(
                                            title: "错误",
                                            message: "重置失败",
                                            preferredStyle: .alert
                                        )
                                        
                                        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
                                        
                                        self.present(alert, animated: true)
                                    }
                                }
                            }
                        }
                    }
                })
                
                alert.addAction(UIAlertAction(title: "保留数据", style: .cancel))
                
                self.present(alert, animated: true)
            } else if indexPath.row == 5 {
                let alert = UIAlertController(
                    title: "重置全部数据",
                    message: "虚拟环境中的所有工程、配置、KEXT、应用、二进制和数据容器都将被清空。",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "继续", style: .destructive) { [weak self] _ in
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: nil, message: "正在重置", preferredStyle: .alert)
                        
                        let activityIndicator = UIActivityIndicatorView(style: .medium)
                        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                        activityIndicator.startAnimating()
                        
                        alert.view.addSubview(activityIndicator)
                        
                        NSLayoutConstraint.activate([
                            activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
                            activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
                        ])
                        
                        guard let self = self else {
                            return
                        }
                        self.present(alert, animated: true) { [weak self] in
                            guard let self = self else {
                                return
                            }
                            DispatchQueue.global().async { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                let success = PEUserspaceManager.shared().restoreEverything()
                                DispatchQueue.main.async { [weak self] in
                                    guard let self = self else {
                                        return
                                    }
                                    alert.dismiss(animated: true)
                                    if !success {
                                        let alert = UIAlertController(
                                            title: "错误",
                                            message: "重置失败",
                                            preferredStyle: .alert
                                        )
                                        
                                        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
                                        
                                        self.present(alert, animated: true)
                                    }
                                }
                            }
                        }
                    }
                })
                
                alert.addAction(UIAlertAction(title: "保留数据", style: .cancel))
                
                self.present(alert, animated: true)
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
