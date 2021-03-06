//
//  ThemeManager.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-04-12.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2018 1024jp
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

import Foundation

@objc protocol ThemeHolder: AnyObject {
    
    func changeTheme(_ sender: AnyObject?)
}



// MARK: -

final class ThemeManager: SettingFileManaging {
    
    typealias Setting = Theme
    
    typealias ThemeDictionary = [String: NSMutableDictionary]  // use NSMutableDictionary for KVO
    
    
    // MARK: Public Properties
    
    static let shared = ThemeManager()
    
    
    // MARK: Setting File Managing Properties
    
    static let directoryName: String = "Themes"
    let filePathExtensions: [String] = DocumentType.theme.extensions
    let settingFileType: SettingFileType = .theme
    
    private(set) var settingNames: [String] = []
    private(set) var bundledSettingNames: [String] = []
    var cachedSettings: [String: Setting] = [:]
    
    
    
    // MARK: -
    // MARK: Lifecycle
    
    private init() {
        
        // cache bundled setting names
        self.bundledSettingNames = Bundle.main.urls(forResourcesWithExtension: self.filePathExtension, subdirectory: ThemeManager.directoryName)!
            .filter { !$0.lastPathComponent.hasPrefix("_") }
            .map { self.settingName(from: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        
        // cache user setting names
        self.checkUserSettings()
    }
    
    
    
    // MARK: Public Methods
    
    /// load theme dict in which objects are property list ready.
    func settingDictionary(name: String) -> ThemeDictionary? {
        
        guard let themeURL = self.urlForUsedSetting(name: name) else { return nil }
        
        return try? self.loadSettingDictionary(at: themeURL)
    }
    
    
    /// save setting file
    func save(settingDictionary: ThemeDictionary, name: String, completionHandler: (() -> Void)? = nil) throws {  // @escaping
        
        // create directory to save in user domain if not yet exist
        try self.prepareUserSettingDirectory()
        
        let fileURL = self.preparedURLForUserSetting(name: name)
        let data = try JSONSerialization.data(withJSONObject: settingDictionary, options: .prettyPrinted)
        
        try data.write(to: fileURL, options: .atomic)
        
        // invalidate current cache
        self.cachedSettings[name] = nil
        
        self.updateCache { [weak self] in
            self?.notifySettingUpdate(oldName: name, newName: name)
            
            completionHandler?()
        }
    }
    
    
    /// create a new untitled setting
    func createUntitledSetting(completionHandler: ((_ settingName: String) -> Void)? = nil) throws {  // @escaping
        
        // append number suffix if "Untitled" already exists
        let name = self.savableSettingName(for: "Untitled".localized)
        
        try self.save(settingDictionary: self.blankSettingDictionary, name: name) {
            completionHandler?(name)
        }
    }
    
    
    
    // MARK: Setting File Managing
    
    /// load setting from the file at given URL
    func loadSetting(at fileURL: URL) throws -> Setting {
        
        return try Theme(contentsOf: fileURL)
    }
    
    
    /// load settings in the user domain
    func checkUserSettings() {
        
        // get user setting names if exists
        let userSettingNames = self.userSettingFileURLs
            .map { self.settingName(from: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        
        self.settingNames = OrderedSet(self.bundledSettingNames + userSettingNames).array
        
        // reset user default if not found
        if !self.settingNames.contains(UserDefaults.standard[.theme]!) {
            UserDefaults.standard.restore(key: .theme)
        }
    }
    
    
    
    // MARK: Private Methods
    
    /// Load ThemeDictionary from a file at the URL.
    ///
    /// - parameter fileURL: URL to a setting file.
    /// - throws: CocoaError
    private func loadSettingDictionary(at fileURL: URL) throws -> ThemeDictionary {
        
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers)
        
        guard let themeDictionry = json as? ThemeDictionary else {
            throw CocoaError.error(.fileReadCorruptFile, url: fileURL)
        }
        
        return themeDictionry
    }
    
    
    /// plain setting to be based on when creating a new one
    private var blankSettingDictionary: ThemeDictionary {
        
        let url = self.urlForBundledSetting(name: "_Plain")!
        
        return try! self.loadSettingDictionary(at: url)
    }
    
}
