/*
SPDX-License-Identifier: AGPL-3.0-or-later

Copyright (C) 2026 Kyle-Ye
Copyright (C) 2026 emexlab

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
import UIOnboarding

// Let me cry alone :<
@_cdecl("NXSlotMain")
public func NXSlotMain() -> UnsafeMutableRawPointer? {
    let defaults = UserDefaults.standard
    
    let enforcement: PEEnforcementMode
    switch defaults.string(forKey: "nyxian.boot.entitlements.mode") {
    case "permissive": enforcement = .permissive
    case "disabled": enforcement = .disabled
    default: enforcement = .enforcing
    }
    
    if !trust_enforcement_set_mode(enforcement) {
        assertionFailure("trust_enforcement_mode() was read before trust_enforcement_set_mode()")
    }
    
    if !klog_set_obfuscation(defaults.bool(forKey: "nyxian.boot.log.obfuscated")) {
        assertionFailure("klog_obfuscation_enabled() was read before klog_set_obfuscation()")
    }
    
    NXApplicationState.loadKernelExtensions = defaults.bool(forKey: "nyxian.boot.kextLoading")
    
    PEUserspaceManager.shared().boot(withKextLoadingEnabled: NXApplicationState.loadKernelExtensions)
    NXBootstrap.shared().bootstrap()
    
    _ = UIViewController.swizzlePresentAndDismissOnce
    _ = UIBarButtonItem.swizzleBarButtonitem
    RevertUI()
    
    let root = SlotCoordinator.shared.makeRootViewController()
    return Unmanaged.passRetained(root).toOpaque()
}

@_cdecl("NXSlotCreateWindow")
public func NXSlotCreateWindow(_ scenePtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let scene = Unmanaged<UIWindowScene>.fromOpaque(scenePtr).takeUnretainedValue()
    guard let window = NXWindowServer.shared(with: scene) else { return nil }
    return Unmanaged.passRetained(window).toOpaque()
}

@_cdecl("NXSlotDidAppear")
public func NXSlotDidAppear() {
    SlotCoordinator.shared.didAppear()
}

@objc class NXApplicationState: NSObject {
    @objc static var extensionExists: Bool = {
        return PEGetLiveProcessBundle() != nil
    }()
    
    @objc static var extensionCorrectlyEntitled: Bool = {
        return PEExtensionHasGetTaskAllowed()
    }()
    
    @objc static var extensionLessMode: Bool = {
        return !extensionExists || !extensionCorrectlyEntitled;
    }()
    
    private static var actualLoadKernelExtensions: Bool = false
    @objc static var loadKernelExtensions: Bool {
        get {
            if UserDefaults.standard.bool(forKey: "LDEDisableKernelExtensionsForce") {
                UserDefaults.standard.removeObject(forKey: "LDEDisableKernelExtensionsForce")
                return false
            }
            return self.actualLoadKernelExtensions;
        }
        set {
            if UserDefaults.standard.bool(forKey: "LDEDisableKernelExtensionsForce") {
                return
            }
            actualLoadKernelExtensions = newValue
        }
    }
    
    @objc static var fileListRequiresToSendRequests: Bool = false
    
    @objc static func restartAppWithoutKEXTLoadingEnabled() {
        UserDefaults.standard.set(true, forKey: "LDEDisableKernelExtensionsForce")
        PERestartSelf()
    }
}

final class SlotCoordinator: NSObject, UITabBarControllerDelegate, UIOnboardingViewControllerDelegate {
    static let shared = SlotCoordinator()
    
    private weak var tabController: UITabBarController?
    
    func makeRootViewController() -> UIViewController {
        let themedTabViewController = NXUITabBarController()
        
        let contentNavigationController = UINavigationController(rootViewController: ContentViewController())
        let settingsNavigationController = UINavigationController(rootViewController: NX设置TableViewController())
        
        contentNavigationController.tabBarItem = UITabBarItem(title: "工程", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 0)
        settingsNavigationController.tabBarItem = UITabBarItem(title: "设置", image: UIImage(systemName: "gear"), tag: 1)
        
        var viewControllers: [UIViewController] = [contentNavigationController, settingsNavigationController]
        
        if UIDevice.current.userInterfaceIdiom == .phone {
            if #available(iOS 26.0, *) {
                if !NXApplicationState.extensionLessMode {
                    let fakeViewController = UIViewController()
                    fakeViewController.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 2)
                    fakeViewController.tabBarItem.title = "切换器"
                    fakeViewController.tabBarItem.image = UIImage(systemName: "iphone.app.switcher")
                    viewControllers.append(fakeViewController)
                }
            }
        }
        
        themedTabViewController.viewControllers = viewControllers
        themedTabViewController.delegate = self
        tabController = themedTabViewController
        return themedTabViewController
    }
    
    func didAppear() {
        if UserDefaults.standard.object(forKey: "NXOnboardingSentinel") is NSNumber {
            checkSigningSetup()
            return
        }
        
        guard let tabController else { return }
        
        let onboardingConfiguration = UIOnboardingViewConfiguration(
            appIcon: UIOnboardingHelper.setUpIcon(),
            firstTitleLine: UIOnboardingHelper.setUpFirstTitleLine(),
            secondTitleLine: UIOnboardingHelper.setUpSecondTitleLine(),
            features: UIOnboardingHelper.setUpFeatures(),
            textViewConfiguration: UIOnboardingHelper.setUpNotice(),
            buttonConfiguration: UIOnboardingHelper.setUpButton())
        let onboardingController = UIOnboardingViewController(withConfiguration: onboardingConfiguration)
        onboardingController.delegate = self
        onboardingController.backgroundColor = LDETheme.currentTheme!.backgroundColor
        onboardingController.modalTransitionStyle = .crossDissolve
        
        tabController.present(onboardingController, animated: true)
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if tabBarController.selectedViewController === viewController && NXBuilder.builds {
            return false
        }
        if viewController.tabBarItem.tag == 2 {
            NXWindowServer.shared().showApp切换器External()
            return false
        }
        return true
    }
    
    func didFinishOnboarding(onboardingViewController: UIOnboarding.UIOnboardingViewController) {
        onboardingViewController.modalTransitionStyle = .crossDissolve
        onboardingViewController.dismiss(animated: true, completion: nil)
        
        UserDefaults.standard.set(NSNumber(booleanLiteral: true), forKey: "NXOnboardingSentinel")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            checkSigningSetup()
        }
    }
}

struct UIOnboardingHelper {
    static func setUpIcon() -> UIImage {
        if #unavailable(iOS 26.0) {
            return .init(named: "IconPreviewDefaultOld")!
        } else {
            let object = LDEApplicationObject(nsBundle: Bundle.main)!
            return Gib26Icon(object.icon, object.darkIcon, CGSize(width: 1024, height: 1024), UIScreen.main.scale)
        }
    }
    
    static func setUpFirstTitleLine() -> NSMutableAttributedString {
        .init(string: "欢迎使用", attributes: [.foregroundColor: UIColor.label])
    }
    
    static func setUpSecondTitleLine() -> NSMutableAttributedString {
        .init(string: Bundle.main.displayName ?? "Nyxian", attributes: [
            .foregroundColor: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.79, green: 0.66, blue: 0.89, alpha: 1.0) : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0) }
        ])
    }
    
    static func setUpFeatures() -> Array<UIOnboardingFeature> {
        return .init([
            .init(icon: UIImage(systemName: "hammer.fill")!,
                  iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.55, green: 0.78, blue: 0.98, alpha: 1.0) : UIColor(red: 0.30, green: 0.58, blue: 0.88, alpha: 1.0) },
                  title: "全栈开发",
                  description: "完整的开发环境，支持 Swift、C、C++、Objective-C 与 Objective-C++，可运行于任何 iOS 18.0+ 的 iPhone 或 iPad。"),
            .init(icon: UIImage(systemName: "wrench.and.screwdriver.fill")!,
                  iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.78, green: 0.71, blue: 0.95, alpha: 1.0) : UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1.0) },
                  title: "移动开发套件",
                  description: "完全开源的 LLVM、Swift、Clang 与 LLD 工具链，在 iOS 上原生运行，全程在设备本地完成编译与链接，无需任何昂贵的云服务或订阅。"),
            .init(icon: UIImage(systemName: "cpu.fill")!,
                  iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.60, green: 0.88, blue: 0.80, alpha: 1.0) : UIColor(red: 0.30, green: 0.68, blue: 0.58, alpha: 1.0) },
                  title: "原生性能",
                  description: "自研微内核 ksurface，提供真实的进程管理、Mach IPC（例如通过 task_for_pid() 获取 task port）、POSIX 语义与自定义内核扩展——你可以亲手扩展 ksurface，还能通过 shimcache 在用户态为系统调用添加更多重绑定，一切都在你受限的 iOS 设备上为你的工程服务。"),
            .init(icon: UIImage(systemName: "exclamationmark.triangle.fill")!,
                  iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.82, blue: 0.45, alpha: 1.0) : UIColor(red: 0.85, green: 0.60, blue: 0.12, alpha: 1.0) },
                  title: "温馨提示",
                  description: "这是 Nyxian 的 Beta 版本，别期待毫无 bug 的成品，请保持友善与尊重——开发这类软件非常不易。欢迎到我们的 GitHub 反馈任何问题、提出任何疑问，我们有充足的时间与热情为你解答、让 Nyxian 变得更好。"),
        ])
    }
    
    static func setUpNotice() -> UIOnboardingTextViewConfiguration {
        return .init(icon: UIImage(systemName: "heart.fill")!,
                     text: "贡献、反馈与 Star 让这个项目保持活力。",
                     linkTitle: "在 GitHub 上参与贡献",
                     link: "https://github.com/emexlab/Nyxian",
                     linkColor: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.79, green: 0.66, blue: 0.89, alpha: 1.0) : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0) })
    }
    
    static func setUpButton() -> UIOnboardingButtonConfiguration {
        let lightBackground = LDETheme.currentTheme!.backgroundColor.resolvedColor(with: .init(userInterfaceStyle: .light))
        
        return .init(title: "继续", titleColor: lightBackground, backgroundColor: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.79, green: 0.66, blue: 0.89, alpha: 1.0) : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0) })
    }
}
