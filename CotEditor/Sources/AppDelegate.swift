//
//  AppDelegate.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2004-12-13.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2013-2018 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Cocoa

private extension NSSound {
    
    static let glass = NSSound(named: "Glass")
}


private enum BundleIdentifier {
    
    static let ScriptEditor = "com.apple.ScriptEditor2"
}



@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: Enums
    
    private enum AppWebURL: String {
        case website = "https://coteditor.com"
        case issueTracker = "https://github.com/coteditor/CotEditor/issues"
        
        var url: URL {
            return URL(string: self.rawValue)!
        }
    }
    
    
    // MARK: Public Properties
    
    @objc dynamic let supportsWindowTabbing: Bool
    
    
    // MARK: Private Properties
    
    private lazy var acknowledgmentsWindowController: NSWindowController = {
        
        let windowController = NSStoryboard(name: "WebDocumentWindow", bundle: nil).instantiateInitialController() as! NSWindowController
        windowController.contentViewController?.representedObject = Bundle.main.url(forResource: "Acknowledgments", withExtension: "html")
        return windowController
    }()
    
    @IBOutlet private weak var encodingsMenu: NSMenu?
    @IBOutlet private weak var syntaxStylesMenu: NSMenu?
    @IBOutlet private weak var themesMenu: NSMenu?
    @IBOutlet private weak var whatsNewMenuItem: NSMenuItem?
    
    
    
    // MARK: -
    // MARK: Lifecycle
    
    override init() {
        
        // add tab window
        if #available(macOS 10.12, *) {
            self.supportsWindowTabbing = true
        } else {
            self.supportsWindowTabbing = false
        }
        
        // register default setting values
        UserDefaults.standard.register(defaults: DefaultSettings.defaults)
        NSUserDefaultsController.shared.initialValues = DefaultSettings.defaults
        
        // instantiate DocumentController
        _ = DocumentController.shared
        
        // wake text finder up
        _ = TextFinder.shared
        
        // register transformers
        ValueTransformer.setValueTransformer(HexColorTransformer(), forName: HexColorTransformer.name)
        
        super.init()
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func awakeFromNib() {
        
        // store key bindings in MainMenu.xib before menu is modified
        MenuKeyBindingManager.shared.scanDefaultMenuKeyBindings()
        
        // append the current version number to "What’s New" menu item
        let shortVersionRange = AppInfo.shortVersion.range(of: "^[0-9]+\\.[0-9]+", options: .regularExpression)!
        let shortVersion = String(AppInfo.shortVersion[shortVersionRange])
        self.whatsNewMenuItem?.title = String(format: "What’s New in CotEditor %@".localized, shortVersion)
        
        // build menus
        self.buildEncodingMenu()
        self.buildSyntaxMenu()
        self.buildThemeMenu()
        ScriptManager.shared.buildScriptMenu()
        
        // manually insert Share menu on macOS 10.12 and earlier
        if floor(NSAppKitVersion.current.rawValue) <= NSAppKitVersion.macOS10_12.rawValue {
            (DocumentController.shared as? DocumentController)?.insertLegacyShareMenu()
        }
        
        // observe setting list updates
        NotificationCenter.default.addObserver(self, selector: #selector(buildEncodingMenu), name: didUpdateSettingListNotification, object: EncodingManager.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(buildSyntaxMenu), name: didUpdateSettingListNotification, object: SyntaxManager.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(buildThemeMenu), name: didUpdateSettingListNotification, object: ThemeManager.shared)
    }
    
    
    
    // MARK: Application Delegate
    
    #if !APPSTORE
    /// setup Sparkle framework
    func applicationWillFinishLaunching(_ notification: Notification) {
    
        UpdaterManager.shared.setup()
    }
    #endif
    
    
    /// just after application did launch
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // setup KeyBindingManager
        MenuKeyBindingManager.shared.applyKeyBindingsToMainMenu()
        
        // register Services
        NSApp.servicesProvider = ServicesProvider()
        
        // setup touchbar
        if #available(macOS 10.12.2, *) {
            NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        }
    }
    
    
    /// store last version before termination
    func applicationWillTerminate(_ notification: Notification) {
        
        // store the latest version
        //   -> The bundle version (build number) must be Int.
        let thisVersion = AppInfo.bundleVersion
        let isLatest: Bool = {
            guard
                let lastVersionString = UserDefaults.standard[.lastVersion],
                let lastVersion = Int(lastVersionString)
                else { return true }
            
            return Int(thisVersion)! >= lastVersion
        }()
        if isLatest {
            UserDefaults.standard[.lastVersion] = thisVersion
        }
    }
    
    
    /// creates a new blank document
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        
        let behavior = NoDocumentOnLaunchBehavior(rawValue: UserDefaults.standard[.noDocumentOnLaunchBehavior]) ?? .untitledDocument
        
        switch behavior {
        case .untitledDocument:
            return true
        case .openPanel:
            NSDocumentController.shared.openDocument(nil)
            return false
        case .none:
            return false
        }
    }
    
    
    /// drop multiple files
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        
        let isAutomaticTabbing: Bool = {
            if #available(macOS 10.12, *) {
                return (DocumentWindow.userTabbingPreference == .inFullScreen) && (filenames.count > 1)
            }
            return false
        }()
        
        var remainingDocumentCount = filenames.count
        var firstWindowOpened = false
        
        for filename in filenames {
            guard !self.application(sender, openFile: filename) else {
                remainingDocumentCount -= 1
                continue
            }
            
            let url = URL(fileURLWithPath: filename)
            
            DocumentController.shared.openDocument(withContentsOf: url, display: true) { (document, documentWasAlreadyOpen, error) in
                defer {
                    remainingDocumentCount -= 1
                }
                
                if let error = error {
                    NSApp.presentError(error)
                    
                    let cancelled = (error as? CocoaError)?.code == .userCancelled
                    NSApp.reply(toOpenOrPrint: cancelled ? .cancel : .failure)
                }
                
                // on first window opened
                // -> The first document needs to open a new window.
                if #available(macOS 10.12, *), isAutomaticTabbing, !documentWasAlreadyOpen, document != nil, !firstWindowOpened {
                    DocumentWindow.tabbingPreference = .always
                    firstWindowOpened = true
                }
            }
        }
        
        // reset tabbing setting
        if #available(macOS 10.12, *), isAutomaticTabbing {
            // wait until finish
            while remainingDocumentCount > 0 {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
            
            DocumentWindow.tabbingPreference = nil
        }
    }
    
    
    /// open file
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        
        let url = URL(fileURLWithPath: filename)
        
        // perform install if the file is CotEditor theme file
        guard DocumentType.theme.extensions.contains(url.pathExtension) else { return false }
        
        // ask whether theme file should be opened as a text file
        let alert = NSAlert()
        alert.messageText = String(format: "“%@” is a CotEditor theme file.".localized, url.lastPathComponent)
        alert.informativeText = "Do you want to install this theme?".localized
        alert.addButton(withTitle: "Install".localized)
        alert.addButton(withTitle: "Open as Text File".localized)
        
        let returnCode = alert.runModal()
        
        guard returnCode == .alertFirstButtonReturn else { return false }  // = Open as Text File
        
        // import theme
        do {
            try ThemeManager.shared.importSetting(fileURL: url)
            
        } catch {
            // ask whether the old theme should be repleced with new one if the same name theme is already exists
            let success = NSApp.presentError(error)
            
            guard success else { return true }  // cancelled
        }
        
        // feedback for success
        let themeName = ThemeManager.shared.settingName(from: url)
        let feedbackAlert = NSAlert()
        feedbackAlert.messageText = String(format: "A new theme named “%@” has been successfully installed.".localized, themeName)
        
        NSSound.glass?.play()
        feedbackAlert.runModal()
        
        return true
    }
    
    
    
    // MARK: Action Messages
    
    /// activate self and perform "New" menu action
    @IBAction func newDocumentActivatingApplication(_ sender: Any?) {
        
        NSApp.activate(ignoringOtherApps: true)
        NSDocumentController.shared.newDocument(sender)
    }
    
    
    /// activate self and perform "Open..." menu action
    @IBAction func openDocumentActivatingApplication(_ sender: Any?) {
        
        NSApp.activate(ignoringOtherApps: true)
        NSDocumentController.shared.openDocument(sender)
    }
    
    
    /// show standard about panel
    @IBAction func showAboutPanel(_ sender: Any?) {
     
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        #if APPSTORE
            // Remove Sparkle from 3rd party code list
            if let creditsURL = Bundle.main.url(forResource: "Credits", withExtension: "html"),
                let attrString = try? NSMutableAttributedString(url: creditsURL, documentAttributes: nil),
                let range = attrString.string.range(of: "Sparkle.*\\n", options: .regularExpression)
            {
                attrString.replaceCharacters(in: NSRange(range, in: attrString.string), with: "")
                let creditsKey = NSApplication.AboutPanelOptionKey(rawValue: "Credits")  // macOS 10.13
                options[creditsKey] = attrString
            }
        #endif
        
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
    
    
    /// show preferences window
    @IBAction func showPreferences(_ sender: Any?) {
        
        PreferencesWindowController.shared.showWindow(sender)
    }
    
    
    /// show console panel
    @IBAction func showConsolePanel(_ sender: Any?) {
        
        ConsolePanelController.shared.showWindow(sender)
    }
    
    
    /// show acknowlegements
    @IBAction func showAcknowledgments(_ sender: Any?) {
        
        self.acknowledgmentsWindowController.showWindow(sender)
    }
    
    
    /// open OSAScript dictionary in Script Editor
    @IBAction func openAppleScriptDictionary(_ sender: Any?) {
        
        let appURL = Bundle.main.bundleURL
        
        NSWorkspace.shared.open([appURL], withAppBundleIdentifier: BundleIdentifier.ScriptEditor,
                                additionalEventParamDescriptor: nil, launchIdentifiers: nil)
    }
    
    
    /// open a specific page in Help contents
    @IBAction func openHelpAnchor(_ sender: AnyObject) {
        
        guard let identifier = (sender as? NSUserInterfaceItemIdentification)?.identifier else { return }
        
        NSHelpManager.shared.openHelpAnchor(identifier.rawValue, inBook: AppInfo.helpBookName)
    }
    
    
    /// open web site (coteditor.com) in default web browser
    @IBAction func openWebSite(_ sender: Any?) {
        
        NSWorkspace.shared.open(AppWebURL.website.url)
    }
    
    
    /// open bug report page in default web browser
    @IBAction func reportBug(_ sender: Any?) {
        
        NSWorkspace.shared.open(AppWebURL.issueTracker.url)
    }
    
    
    /// open new bug report window
    @IBAction func createBugReport(_ sender: Any?) {
        
        // load template file
        let url = Bundle.main.url(forResource: "ReportTemplate", withExtension: "md")!
        guard let template = try? String(contentsOf: url) else { return }
        
        // fill template with user environment info
        let report = template
            .replacingOccurrences(of: "%BUNDLE_VERSION%", with: AppInfo.bundleVersion)
            .replacingOccurrences(of: "%SHORT_VERSION%", with: AppInfo.shortVersion)
            .replacingOccurrences(of: "%SYSTEM_VERSION%", with: ProcessInfo.processInfo.operatingSystemVersionString)
        
        // open as document
        guard let document = (try? NSDocumentController.shared.openUntitledDocumentAndDisplay(false)) as? Document else { return }
        document.displayName = "Bug Report".localized(comment: "document title")
        document.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: report)
        document.setSyntaxStyle(name: BundledStyleName.markdown)
        document.makeWindowControllers()
        document.showWindows()
    }
    
    
    
    // MARK: Private Methods
    
    /// build encoding menu in the main menu
    @objc private func buildEncodingMenu() {
        
        let menu = self.encodingsMenu!
        
        EncodingManager.shared.updateChangeEncodingMenu(menu)
    }
    
    
    /// build syntax style menu in the main menu
    @objc private func buildSyntaxMenu() {
        
        let menu = self.syntaxStylesMenu!
        
        menu.removeAllItems()
        
        // add None
        menu.addItem(withTitle: BundledStyleName.none, action: #selector(SyntaxHolder.changeSyntaxStyle), keyEquivalent: "")
        menu.addItem(.separator())
        
        // add syntax styles
        for styleName in SyntaxManager.shared.settingNames {
            menu.addItem(withTitle: styleName, action: #selector(SyntaxHolder.changeSyntaxStyle), keyEquivalent: "")
        }
        menu.addItem(.separator())
        
        // add item to recolor
        let recolorAction = #selector(SyntaxHolder.recolorAll)
        let shortcut = MenuKeyBindingManager.shared.shortcut(for: recolorAction)
        let recoloritem = NSMenuItem(title: "Re-Color All".localized, action: recolorAction, keyEquivalent: shortcut.keyEquivalent)
        recoloritem.keyEquivalentModifierMask = shortcut.modifierMask  // = default: Cmd + Opt + R
        menu.addItem(recoloritem)
    }
    
    
    /// build theme menu in the main menu
     @objc private func buildThemeMenu() {
        
        let menu = self.themesMenu!
        
        menu.removeAllItems()
        
        for themeName in ThemeManager.shared.settingNames {
            menu.addItem(withTitle: themeName, action: #selector(ThemeHolder.changeTheme), keyEquivalent: "")
        }
    }
    
}
