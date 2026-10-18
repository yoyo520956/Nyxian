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

import Foundation

func getTopViewController(base: UIViewController? = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {
    
    if let nav = base as? UINavigationController {
        return getTopViewController(base: nav.visibleViewController)
    }
    
    if let tab = base as? UITabBarController {
        return getTopViewController(base: tab.selectedViewController)
    }
    
    if let presented = base?.presentedViewController {
        return getTopViewController(base: presented)
    }
    
    return base
}

fileprivate func errorFallback(title: String, message: String) {
    let alert = UIAlertController(
        title: title,
        message: message,
        preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "关闭", style: .default))

    DispatchQueue.main.async {
        NXWindowServer.shared().rootViewController?.present(
            alert,
            animated: true
        )
    }
}

func checkSigningSetup(completionHandler: @escaping (Bool) -> Void = { _ in }, showAlert: Bool = true) {
    if !NXApplicationState.extensionExists {
        if showAlert {
            errorFallback(title: "未找到扩展", message: """
所需的 NSExtension 未找到。

请确保安装 App 时扩展完整保留，且未在签名或安装过程中被移除。

当前处于无扩展模式：在此问题解决前，App 将无法在 Nyxian 内运行。
""")
        }
        completionHandler(false)
        return
    }
    
    if !NXApplicationState.extensionCorrectlyEntitled {
        if showAlert {
            errorFallback(title: "不支持的描述文件", message: """
扩展缺少 "get-task-allow" 权限。

不支持分发（Distribution）证书。必须使用 Apple 签发的开发者（Developer）证书。

7 天免费证书就是开发者证书。

当前处于无扩展模式：在此问题解决前，App 将无法在 Nyxian 内运行。
""")
        }
        completionHandler(false)
        return
    }
    
    LCUtils.validateCertificate { status, someWords in
        completionHandler(status == 0)
        if status == 0 || !showAlert {
            return
        }
        
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: {
                    switch status {
                    default:
                        return "尚未设置签名"
                    }
                }(),
                message: {
                    switch status {
                    default:
                        return "Nyxian 需要签名证书才能安装并运行你构建的 App。没有证书你仍可以写代码和编译，但无法在本设备上运行。"
                    }
                }(), preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "暂不", style: .cancel))
            alert.addAction(UIAlertAction(title: "设置签名", style: .default) { _ in
                let importPopup: CertificateImporter = CertificateImporter(style: .insetGrouped)
                let importSettings: UINavigationController = UINavigationController(rootViewController: importPopup)
                importSettings.modalPresentationStyle = .formSheet
                
                // dynamic size
                if UIDevice.current.userInterfaceIdiom == .phone {
                    if let sheet = importSettings.sheetPresentationController {
                        sheet.animateChanges {
                            sheet.detents = [
                                .custom { _ in
                                    return 200
                                }
                            ]
                        }
                        
                        sheet.prefersGrabberVisible = true
                    }
                }
                
                getTopViewController()?.present(importSettings, animated: true)
            })
            
            getTopViewController()?.present(alert, animated: true)
        }
    }
}
