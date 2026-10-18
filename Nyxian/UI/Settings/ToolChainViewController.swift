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
import CoreCompiler

class ToolChainViewController: NXUITableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(ToggleTableCell.self, forCellReuseIdentifier: ToggleTableCell.reuseIdentifier)
        
        self.title = "Toolchain"
        
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.rowHeight = UITableView.automaticDimension
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (section == 3) ? 2 : 1
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "增量编译只重新编译代码中改动的部分，避免整个工程全量重编，从而缩短编译时间。"
        case 1:
            return "远程守护进程模式下，Nyxian 不直接编译代码，而是交给一个同样运行在你设备上的独立守护进程。这样即使 LLVM 崩溃也不会带走 Nyxian，还能保证编译结束后内存被彻底释放、不会残留损坏的 LLVM 状态。"
        case 2:
            return "多线程编译指编译器将解析、代码生成、优化等任务分配到多个 CPU 线程并行执行，以加快构建速度。"
        case 3:
            return "清除为提升性能而创建的缓存。"
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "功能"
        case 3:
            return "操作"
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        
        switch indexPath.section {
        case 0:
            cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableCell.reuseIdentifier, for: indexPath) as! ToggleTableCell
            (cell as! ToggleTableCell).configure(title: "增量编译", key: "LDEIncrementalBuild", defaultValue: true)
            break
        case 1:
            cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableCell.reuseIdentifier, for: indexPath) as! ToggleTableCell
            (cell as! ToggleTableCell).configure(title: "远程编译守护进程", key: "LDERemoteCompileService", defaultValue: true)
            break
        case 2:
            let optimCpuCount: Int = (Int)(CCGetMaximumPerformanceCores())
            cell = StepperTableCell(title: "编译线程数", key: "cputhreads", defaultValue: optimCpuCount, minValue: 1, maxValue: optimCpuCount)
            break
        default:
            switch(indexPath.row) {
            case 0:
                cell = UITableViewCell()
                cell.textLabel?.text = "清除模块缓存"
                break
            default:
                cell = UITableViewCell()
                cell.textLabel?.text = "清除工程缓存"
                break
            }
            break
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if(indexPath.section == 3) {
            // TODO: use the indication popup for cache clearing
            switch(indexPath.row) {
            case 0:
                NXBootstrap.shared().clear(NXBootstrap.shared().swiftModuleCacheURL)
                break
            default:
                NXBootstrap.shared().clear(NXBootstrap.shared().cacheURL)
                break
            }
            try? FileManager.default.removeItem(at: NXBootstrap.shared().swiftModuleCacheURL)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
