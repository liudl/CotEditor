/*
 
 StatusBarController.swift
 
 CotEditor
 https://coteditor.com
 
 Created by 1024jp on 2014-07-11.
 
 ------------------------------------------------------------------------------
 
 © 2014-2016 1024jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 */

import Cocoa

class StatusBarController: NSViewController {
    
    // MARK: Private Properties
    
    private let byteCountFormatter = ByteCountFormatter()
    private dynamic var editorStatus: AttributedString?
    private dynamic var documentStatus: AttributedString?
    private dynamic var showsReadOnly = false
    
    
    
    // MARK: 
    // MARK: Lifecycle
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        for key in self.dynamicType.observedDefaultKeys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
    }
    
    
    
    // MARK: View Controller Methods
    
    /// setup
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.byteCountFormatter.isAdaptive = false
        
        // observe change of defaults
        for key in self.dynamicType.observedDefaultKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
    }
    
    
    /// request analyzer to update editor info
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.documentAnalyzer?.needsUpdateStatusEditorInfo = true
    }
    
    
    /// request analyzer to stop updating editor info
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        self.documentAnalyzer?.needsUpdateStatusEditorInfo = false
    }
    
    
    // MARK: KVO
    
    /// apply change of user setting
    override func observeValue(forKeyPath keyPath: String?, of object: AnyObject?, change: [NSKeyValueChangeKey : AnyObject]?, context: UnsafeMutablePointer<Void>?) {
        
        guard let keyPath = keyPath else { return }
        
        if self.dynamicType.observedDefaultKeys.contains(keyPath) {
            self.updateEditorStatus()
            self.updateDocumentStatus()
        }
    }
    
    
    
    // MARK: Public Methods
    
    weak var documentAnalyzer: CEDocumentAnalyzer?
        {
        willSet {
            self.documentAnalyzer?.needsUpdateStatusEditorInfo = false
            NotificationCenter.default.removeObserver(self)
        }
        didSet {
            guard let analyzer = documentAnalyzer else { return }
            
            analyzer.needsUpdateStatusEditorInfo = !self.view.isHidden
            
            NotificationCenter.default.addObserver(self, selector: #selector(updateEditorStatus), name: .CEAnalyzerDidUpdateEditorInfo, object: analyzer)
            NotificationCenter.default.addObserver(self, selector: #selector(updateDocumentStatus), name: .CEAnalyzerDidUpdateFileInfo, object: analyzer)
            NotificationCenter.default.addObserver(self, selector: #selector(updateDocumentStatus), name: .CEAnalyzerDidUpdateModeInfo, object: analyzer)
            
            self.updateEditorStatus()
            self.updateDocumentStatus()
        }
    }
    
    
    
    // MARK: Private Methods
    
    /// default keys to observe update
    private static let observedDefaultKeys = [CEDefaultShowStatusBarLinesKey,
                                              CEDefaultShowStatusBarCharsKey,
                                              CEDefaultShowStatusBarLengthKey,
                                              CEDefaultShowStatusBarWordsKey,
                                              CEDefaultShowStatusBarLocationKey,
                                              CEDefaultShowStatusBarLineKey,
                                              CEDefaultShowStatusBarColumnKey,
                                              
                                              CEDefaultShowStatusBarEncodingKey,
                                              CEDefaultShowStatusBarLineEndingsKey,
                                              CEDefaultShowStatusBarFileSizeKey,
                                              ]
    
    
    /// update left side text
    func updateEditorStatus() {
        
        guard !self.view.isHidden else { return }
        guard let info = self.documentAnalyzer else { return }
        
        let status = NSMutableAttributedString()
        let defaults = UserDefaults.standard
        
        if defaults.bool(forKey: CEDefaultShowStatusBarLinesKey) {
            status.appendFormattedState(value: info.lines, label: "Lines")
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarCharsKey) {
            status.appendFormattedState(value: info.chars, label: "Chars")
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarLengthKey) {
            status.appendFormattedState(value: info.length, label: "Length")
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarWordsKey) {
            status.appendFormattedState(value: info.words, label: "Words")
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarLocationKey) {
            status.appendFormattedState(value: info.location, label: "Location")
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarLineKey) {
            status.appendFormattedState(value: info.line, label: "Line")
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarColumnKey) {
            status.appendFormattedState(value: info.column, label: "Column")
        }
        
        self.editorStatus = status
    }
    
    
    /// update right side text and readonly icon state
    func updateDocumentStatus() {
        
        guard !self.view.isHidden else { return }
        guard let info = self.documentAnalyzer else { return }
        
        let status = NSMutableAttributedString()
        let defaults = UserDefaults.standard
        
        if defaults.bool(forKey: CEDefaultShowStatusBarEncodingKey) {
            status.appendFormattedState(value: info.charsetName, label: nil)
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarLineEndingsKey) {
            status.appendFormattedState(value: info.lineEndings, label: nil)
        }
        if defaults.bool(forKey: CEDefaultShowStatusBarFileSizeKey) {
            let fileSize = self.byteCountFormatter.string(for: info.fileSize)  // TODO: Int64?
            status.appendFormattedState(value: fileSize, label: nil)
        }
        
        self.documentStatus = status
        self.showsReadOnly = info.isReadOnly
    }
    
}



// MARK:

private extension NSMutableAttributedString {
    
    /// append formatted state
    func appendFormattedState(value: String?, label: String?) {
        
        if self.length > 0 {
            self.append(AttributedString(string: "   "))
        }
        
        if let label = label {
            let localizedLabel = String(format: NSLocalizedString("%@: ", comment: ""),
                                        NSLocalizedString(label, comment: ""))
            let attrLabel = AttributedString(string: localizedLabel,
                                             attributes: [NSForegroundColorAttributeName: NSColor.labelColor()])
            self.append(attrLabel)
        }
        
        let attrValue: AttributedString
        if let value = value {
            attrValue = AttributedString(string: value)
        } else {
            attrValue = AttributedString(string: "-",
                                         attributes: [NSForegroundColorAttributeName: NSColor.disabledControlTextColor()])
        }
        self.append(attrValue)
    }
    
}