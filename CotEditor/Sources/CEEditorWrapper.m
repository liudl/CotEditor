/*
 
 CEEditorWrapper.m
 
 CotEditor
 http://coteditor.com
 
 Created by nakamuxu on 2004-12-08.
 
 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
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

#import "CEEditorWrapper.h"
#import "CEDocument.h"
#import "CEDocumentAnalyzer.h"
#import "CEEditorViewController.h"
#import "CELayoutManager.h"
#import "CEWindowController.h"
#import "CESplitViewController.h"
#import "CENavigationBarController.h"
#import "CEThemeManager.h"
#import "CESyntaxStyle.h"
#import "CEGoToSheetController.h"
#import "CEToggleToolbarItem.h"
#import "CETextFinder.h"

#import "CEDefaults.h"
#import "Constants.h"

#import "NSString+CENewLine.h"
#import "NSString+CERange.h"
#import "NSString+Indentation.h"


@interface CEEditorWrapper () <CETextFinderClientProvider, NSTextStorageDelegate>

@property (nonatomic, nullable, weak) NSTimer *outlineMenuTimer;

@property (nonatomic, nullable) IBOutlet CESplitViewController *splitViewController;


// readonly
@property (readwrite, nonatomic) BOOL canActivateShowInvisibles;

@end


@interface CEEditorWrapper (PrivateSyntaxParsing)

@property (readonly, nonatomic) BOOL canHighlight;


- (void)setupOutlineMenuUpdateTimer;

@end




#pragma -

@implementation CEEditorWrapper

// ------------------------------------------------------
/// initialize instance
- (nonnull instancetype)init
// ------------------------------------------------------
{
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        _canActivateShowInvisibles = ([defaults boolForKey:CEDefaultShowInvisibleSpaceKey] ||
                                      [defaults boolForKey:CEDefaultShowInvisibleTabKey] ||
                                      [defaults boolForKey:CEDefaultShowInvisibleNewLineKey] ||
                                      [defaults boolForKey:CEDefaultShowInvisibleFullwidthSpaceKey] ||
                                      [defaults boolForKey:CEDefaultShowOtherInvisibleCharsKey]);
        
        _showsInvisibles = [defaults boolForKey:CEDefaultShowInvisiblesKey];
        _showsLineNum = [defaults boolForKey:CEDefaultShowLineNumbersKey];
        _showsNavigationBar = [defaults boolForKey:CEDefaultShowNavigationBarKey];
        _wrapsLines = [defaults boolForKey:CEDefaultWrapLinesKey];
        _verticalLayoutOrientation = [defaults boolForKey:CEDefaultLayoutTextVerticalKey];
        _showsPageGuide = [defaults boolForKey:CEDefaultShowPageGuideKey];
    }
    return self;
}


// ------------------------------------------------------
/// clean up
- (void)dealloc
// ------------------------------------------------------
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_outlineMenuTimer invalidate];
    [[self textStorage] setDelegate:nil];
}


// ------------------------------------------------------
/// setup UI
- (void)awakeFromNib
// ------------------------------------------------------
{
    [[self window] setNextResponder:self];
    
    // Yosemite 未満の場合は手動で Responder Chain に入れる
    // （Yosemite 以降は自動的に追加されるためか以下の一行が入るとハングしてしまう）
    if (NSAppKitVersionNumber < NSAppKitVersionNumber10_10) {
        [self setNextResponder:[self splitViewController]];
    }
    
    // detect indent style
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultDetectsIndentStyleKey]) {
        switch ([[[self textStorage] string] detectIndentStyle]) {
            case CEIndentStyleTab:
                [self setAutoTabExpandEnabled:NO];
                break;
            case CEIndentStyleSpace:
                [self setAutoTabExpandEnabled:YES];
                break;
            case CEIndentStyleNotFound:
                break;
        }
    }
    
    [[self textStorage] setDelegate:self];
    
    CEEditorViewController *editorViewController = [self createEditorBasedViewController:nil];
    
    // focus text view
    [[self window] makeFirstResponder:[editorViewController textView]];
    
    // observe syntax/theme change
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeSyntaxStyle:)
                                                 name:CEDocumentSyntaxStyleDidChangeNotification
                                               object:[self document]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didUpdateTheme:)
                                                 name:CEThemeDidUpdateNotification
                                               object:nil];
}



#pragma mark Protocol

//=======================================================
// NSMenuValidation Protocol
//=======================================================

// ------------------------------------------------------
/// メニュー項目の有効・無効を制御
- (BOOL)validateMenuItem:(nonnull NSMenuItem *)menuItem
// ------------------------------------------------------
{
    NSInteger state = NSOffState;
    NSString *title;
    
    if ([menuItem action] == @selector(toggleLineNumber:)) {
        title = [self showsLineNum] ? @"Hide Line Numbers" : @"Show Line Numbers";
        
    } else if ([menuItem action] == @selector(toggleNavigationBar:)) {
        title = [self showsNavigationBar] ? @"Hide Navigation Bar" : @"Show Navigation Bar";
        
    } else if ([menuItem action] == @selector(toggleLineWrap:)) {
        title = [self wrapsLines] ? @"Unwrap Lines" : @"Wrap Lines";
        
    } else if ([menuItem action] == @selector(toggleLayoutOrientation:)) {
        NSString *title = [self isVerticalLayoutOrientation] ? @"Use Horizontal Orientation" :  @"Use Vertical Orientation";
        [menuItem setTitle:NSLocalizedString(title, nil)];
        
    } else if ([menuItem action] == @selector(toggleAntialias:)) {
        state = [self usesAntialias] ? NSOnState : NSOffState;
        
    } else if ([menuItem action] == @selector(togglePageGuide:)) {
        title = [self showsPageGuide] ? @"Hide Page Guide" : @"Show Page Guide";
        
    } else if ([menuItem action] == @selector(toggleInvisibleChars:)) {
        title = [self showsInvisibles] ? @"Hide Invisible Characters" : @"Show Invisible Characters";
        [menuItem setTitle:NSLocalizedString(title, nil)];
        
        if (![self canActivateShowInvisibles]) {
            [menuItem setToolTip:NSLocalizedString(@"To show invisible characters, set them in Preferences and re-open the document.", nil)];
        }
        
        return [self canActivateShowInvisibles];
        
    } else if ([menuItem action] == @selector(toggleAutoTabExpand:)) {
        state = [[self focusedTextView] isAutoTabExpandEnabled] ? NSOnState : NSOffState;
        
    } else if ([menuItem action] == @selector(changeLineHeight:)) {
        CGFloat lineSpacing = [[menuItem title] doubleValue] - 1.0;
        state = CEIsAlmostEqualCGFloats([[self focusedTextView] lineSpacing], lineSpacing) ? NSOnState : NSOffState;
        
    } else if ([menuItem action] == @selector(changeTabWidth:)) {
        state = ([[self focusedTextView] tabWidth] == [menuItem tag]) ? NSOnState : NSOffState;
        
    } else if ([menuItem action] == @selector(closeSplitTextView:)) {
        return ([[[[self splitViewController] view] subviews] count] > 1);
        
    } else if ([menuItem action] == @selector(changeTheme:)) {
        state = [[[self theme] name] isEqualToString:[menuItem title]] ? NSOnState : NSOffState;
        
    } else if ([menuItem action] == @selector(recolorAll:)) {
        return [self canHighlight];
    }
    
    if (title) {
        [menuItem setTitle:NSLocalizedString(title, nil)];
    } else {
        [menuItem setState:state];
    }
    
    return YES;
}


//=======================================================
// NSToolbarItemValidation Protocol
//=======================================================

// ------------------------------------------------------
/// ツールバー項目の有効・無効を制御
- (BOOL)validateToolbarItem:(nonnull NSToolbarItem *)theItem
// ------------------------------------------------------
{
    if ([theItem action] == @selector(recolorAll:)) {
        return [self canHighlight];
    }
    
    // validate button image state
    if ([theItem isKindOfClass:[CEToggleToolbarItem class]]) {
        CEToggleToolbarItem *imageItem = (CEToggleToolbarItem *)theItem;
        
        if ([theItem action] == @selector(toggleLineNumber:)) {
            [imageItem setState:[self showsLineNum] ? NSOnState : NSOffState];
            
        } else if ([theItem action] == @selector(toggleNavigationBar:)) {
            [imageItem setState:[self showsNavigationBar] ? NSOnState : NSOffState];
            
        } else if ([theItem action] == @selector(toggleLineWrap:)) {
            [imageItem setState:[self wrapsLines] ? NSOnState : NSOffState];
            
        } else if ([theItem action] == @selector(toggleLayoutOrientation:)) {
            [imageItem setState:[self isVerticalLayoutOrientation] ? NSOnState : NSOffState];
            
        } else if ([theItem action] == @selector(togglePageGuide:)) {
            [imageItem setState:[self showsPageGuide] ? NSOnState : NSOffState];
            
        } else if ([theItem action] == @selector(toggleInvisibleChars:)) {
            [imageItem setState:[self showsInvisibles] ? NSOnState : NSOffState];
            
            // disable button if item cannot be enable
            if ([self canActivateShowInvisibles]) {
                [theItem setToolTip:NSLocalizedString(@"Show or hide invisible characters in document", nil)];
            } else {
                [theItem setToolTip:NSLocalizedString(@"To display invisible characters, set them in Preferences and re-open the document.", nil)];
                return NO;
            }
            
        } else if ([theItem action] == @selector(toggleAutoTabExpand:)) {
            [imageItem setState:[self isAutoTabExpandEnabled] ? NSOnState : NSOffState];
        }
    }
    
    return YES;
}



#pragma mark Delegate

//=======================================================
// NSTextStorageDelegate Protocol
//=======================================================

// ------------------------------------------------------
/// text did edit
- (void)textStorageDidProcessEditing:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    NSTextStorage *textStorage = [notification object];
    
    // ignore if only attributes did change
    if (([textStorage editedMask] & NSTextStorageEditedCharacters) == 0) { return; }
    
    // update editor information
    // -> In case, if "Replace All" performed without moving caret.
    [[[self document] analyzer] invalidateEditorInfo];
    
    // parse syntax
    [self setupOutlineMenuUpdateTimer];
    if ([self canHighlight]) {
        // invalidate only edited lines
        NSRange updateRange = [[textStorage string] lineRangeForRange:[textStorage editedRange]];
        // perform highlight in the next run loop to give layoutManager time to update temporary attribute
        CESyntaxStyle *syntaxStyle = [self syntaxStyle];
        dispatch_async(dispatch_get_main_queue(), ^{
            [syntaxStyle highlightRange:updateRange];
        });
    }
    
    // update incompatible chars list
    [[[self window] windowController] updateIncompatibleCharsIfNeeded];
}


#pragma mark Notification

- (void)textViewDidChangeSelection:(nonnull NSNotification *)notification
{
    // update document information
    [[[self document] analyzer] invalidateEditorInfo];
}

//=======================================================
// Notification  < CEThemeManager
//=======================================================

// ------------------------------------------------------
/// テーマが更新された
- (void)didUpdateTheme:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    NSString *oldThemeName = [notification userInfo][CEOldNameKey];
    NSString *newThemeName = [notification userInfo][CENewNameKey];
    
    if ([oldThemeName isEqualToString:[[self theme] name]]) {
        [self setThemeWithName:newThemeName];
    }
}



#pragma mark Public Methods

// ------------------------------------------------------
/// return textView focused on
- (nullable CETextView *)focusedTextView
// ------------------------------------------------------
{
    return [[[self splitViewController] focusedSubviewController] textView];
}


// ------------------------------------------------------
/// 現在のエンコードにコンバートできない文字列をマークアップ
- (void)markupRanges:(nonnull NSArray<NSValue *> *)ranges
// ------------------------------------------------------
{
    NSColor *color = [[[self focusedTextView] theme] markupColor];
    NSArray<NSLayoutManager *> *layoutManagers = [self layoutManagers];
    
    for (NSValue *rangeValue in ranges) {
        NSRange documentRange = [rangeValue rangeValue];
        NSRange range = [[[self textStorage] string] convertRange:documentRange
                                                  fromNewLineType:[[self document] lineEnding]
                                                    toNewLineType:CENewLineLF];
        
        for (NSLayoutManager *manager in layoutManagers) {
            [manager addTemporaryAttribute:NSBackgroundColorAttributeName value:color
                         forCharacterRange:range];
        }
    }
}


// ------------------------------------------------------
/// 背景色(検索のハイライト含む)の変更を取り消し
- (void)clearAllMarkup
// ------------------------------------------------------
{
    NSArray<NSLayoutManager *> *managers = [self layoutManagers];
    
    for (NSLayoutManager *manager in managers) {
        [manager removeTemporaryAttribute:NSBackgroundColorAttributeName
                        forCharacterRange:NSMakeRange(0, [[manager attributedString] length])];
    }
}


// ------------------------------------------------------
/// ソフトタブの有効／無効を返す
- (BOOL)isAutoTabExpandEnabled
// ------------------------------------------------------
{
    CETextView *textView = [self focusedTextView];
    
    if (textView) {
        return [textView isAutoTabExpandEnabled];
    } else {
        return [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultAutoExpandTabKey];
    }
}


// ------------------------------------------------------
/// ソフトタブの有効／無効をセット
- (void)setAutoTabExpandEnabled:(BOOL)enabled
// ------------------------------------------------------
{
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [[viewController textView] setAutoTabExpandEnabled:enabled];
    }];
}


// ------------------------------------------------------
/// ナビゲーションバーを表示する／しないをセット
- (void)setShowsNavigationBar:(BOOL)showsNavigationBar animate:(BOOL)performAnimation
// ------------------------------------------------------
{
    _showsNavigationBar = showsNavigationBar;
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [viewController setShowsNavigationBar:showsNavigationBar animate:performAnimation];
    }];
    
    if (showsNavigationBar && ![[self outlineMenuTimer] isValid]) {
        [self invalidateOutlineMenu];
    }
}


// ------------------------------------------------------
/// 行番号の表示をする／しないをセット
- (void)setShowsLineNum:(BOOL)showsLineNum
// ------------------------------------------------------
{
    _showsLineNum = showsLineNum;
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [viewController setShowsLineNum:showsLineNum];
    }];
}


// ------------------------------------------------------
/// 行をラップする／しないをセット
- (void)setWrapsLines:(BOOL)wrapsLines
// ------------------------------------------------------
{
    _wrapsLines = wrapsLines;
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [viewController setWrapsLines:wrapsLines];
    }];
}


// ------------------------------------------------------
/// 横書き／縦書きをセット
- (void)setVerticalLayoutOrientation:(BOOL)isVerticalLayoutOrientation
// ------------------------------------------------------
{
    _verticalLayoutOrientation = isVerticalLayoutOrientation;
    
    NSTextLayoutOrientation orientation = isVerticalLayoutOrientation ? NSTextLayoutOrientationVertical : NSTextLayoutOrientationHorizontal;
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [[viewController textView] setLayoutOrientation:orientation];
    }];
}


// ------------------------------------------------------
/// フォントを返す
- (nullable NSFont *)font
// ------------------------------------------------------
{
    return [[self focusedTextView] font];
}


// ------------------------------------------------------
/// フォントをセット
- (void)setFont:(NSFont *)font
// ------------------------------------------------------
{
    [[self focusedTextView] setFont:font];
}


// ------------------------------------------------------
/// アンチエイリアスでの描画の許可を得る
- (BOOL)usesAntialias
// ------------------------------------------------------
{
    CELayoutManager *manager = (CELayoutManager *)[[self focusedTextView] layoutManager];
    
    return [manager usesAntialias];
}


// ------------------------------------------------------
/// テーマを適用する
- (void)setThemeWithName:(nonnull NSString *)themeName
// ------------------------------------------------------
{
    CETheme *theme = [[CEThemeManager sharedManager] themeWithName:themeName];
    
    if (!theme) { return; }
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [[viewController textView] setTheme:theme];
        
        // re-select to update current line highlight
        [[viewController textView] setSelectedRanges:[[viewController textView] selectedRanges]];
    }];
    
    [self invalidateSyntaxHighlight];
}


// ------------------------------------------------------
/// 現在のテーマを返す
- (nullable CETheme *)theme
// ------------------------------------------------------
{
    return [[self focusedTextView] theme];
}


// ------------------------------------------------------
/// ページガイドを表示する／しないをセット
- (void)setShowsPageGuide:(BOOL)showsPageGuide
// ------------------------------------------------------
{
    _showsPageGuide = showsPageGuide;
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [[viewController textView] setShowsPageGuide:showsPageGuide];
        [[viewController textView] setNeedsDisplayInRect:[[viewController textView] visibleRect] avoidAdditionalLayout:YES];
    }];
}


// ------------------------------------------------------
/// 不可視文字の表示／非表示を設定
- (void)setShowsInvisibles:(BOOL)showsInvisibles
// ------------------------------------------------------
{
    _showsInvisibles = showsInvisibles;
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [viewController setShowsInvisibles:showsInvisibles];
    }];
}



#pragma mark Action Messages

// ------------------------------------------------------
/// 行番号表示をトグルに切り替える
- (IBAction)toggleLineNumber:(nullable id)sender
// ------------------------------------------------------
{
    [self setShowsLineNum:![self showsLineNum]];
}


// ------------------------------------------------------
/// ナビゲーションバーの表示をトグルに切り替える
- (IBAction)toggleNavigationBar:(nullable id)sender
// ------------------------------------------------------
{
    [self setShowsNavigationBar:![self showsNavigationBar] animate:YES];
}


// ------------------------------------------------------
/// ワードラップをトグルに切り替える
- (IBAction)toggleLineWrap:(nullable id)sender
// ------------------------------------------------------
{
    [self setWrapsLines:![self wrapsLines]];
}


// ------------------------------------------------------
/// 横書き／縦書きを切り替える
- (IBAction)toggleLayoutOrientation:(nullable id)sender
// ------------------------------------------------------
{
    [self setVerticalLayoutOrientation:![self isVerticalLayoutOrientation]];
}


// ------------------------------------------------------
/// 文字にアンチエイリアスを使うかどうかをトグルに切り替える
- (IBAction)toggleAntialias:(nullable id)sender
// ------------------------------------------------------
{
    BOOL usesAntialias = ![(CELayoutManager *)[[self focusedTextView] layoutManager] usesAntialias];
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [viewController setUsesAntialias:usesAntialias];
    }];
}


// ------------------------------------------------------
/// 不可視文字表示をトグルに切り替える
- (IBAction)toggleInvisibleChars:(nullable id)sender
// ------------------------------------------------------
{
    BOOL showsInvisibles = ![self showsInvisibles];
    [self setShowsInvisibles:showsInvisibles];
}


// ------------------------------------------------------
/// ソフトタブの有効／無効をトグルに切り替える
- (IBAction)toggleAutoTabExpand:(nullable id)sender
// ------------------------------------------------------
{
    BOOL isEnabled = [[self focusedTextView] isAutoTabExpandEnabled];
    
    [self setAutoTabExpandEnabled:!isEnabled];
}


// ------------------------------------------------------
/// ページガイド表示をトグルに切り替える
- (IBAction)togglePageGuide:(nullable id)sender
// ------------------------------------------------------
{
    [self setShowsPageGuide:![self showsPageGuide]];
}


// ------------------------------------------------------
/// change tab width from the main menu
- (IBAction)changeTabWidth:(nullable id)sender
// ------------------------------------------------------
{
    NSUInteger tabWidth = [sender tag];
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [[viewController textView] setTabWidth:tabWidth];
    }];
}


// ------------------------------------------------------
/// change line height from the main menu
- (IBAction)changeLineHeight:(nullable id)sender
// ------------------------------------------------------
{
    CGFloat lineSpacing = (CGFloat)[[sender title] doubleValue] - 1.0;  // title is line height
    
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [[viewController textView] setLineSpacingAndUpdate:lineSpacing];
    }];
}


// ------------------------------------------------------
/// 新しいテーマを適用
- (IBAction)changeTheme:(nullable id)sender
// ------------------------------------------------------
{
    NSString *name = [sender title];
    
    if ([name length] > 0) {
        [self setThemeWithName:name];
    }
}


// ------------------------------------------------------
/// テキストビュー分割を行う
- (IBAction)openSplitTextView:(nullable id)sender
// ------------------------------------------------------
{
    CEEditorViewController *currentEditorViewController;
    
    // find target CEEditorViewController
    id view = [sender isMemberOfClass:[NSMenuItem class]] ? [[self window] firstResponder] : sender;
    while (view) {
        if ([[view identifier] isEqualToString:@"EditorView"]) {
            currentEditorViewController = [[self splitViewController] viewControllerForSubview:view];
            break;
        }
        view = [view superview];
    }
    
    if (!currentEditorViewController) { return; }
    
    // end current editing
    [[[NSTextInputContext currentInputContext] client] unmarkText];
    
    CEEditorViewController *newEditorViewController = [self createEditorBasedViewController:currentEditorViewController];
    
    [self invalidateSyntaxHighlight];
    [self invalidateOutlineMenu];
    
    // adjust visible areas
    [[newEditorViewController textView] setSelectedRange:[[currentEditorViewController textView] selectedRange]];
    [[currentEditorViewController textView] centerSelectionInVisibleArea:self];
    [[newEditorViewController textView] centerSelectionInVisibleArea:self];
    
    // move focus to the new editor
    [[self window] makeFirstResponder:[newEditorViewController textView]];
}


// ------------------------------------------------------
//// 分割されたテキストビューを閉じる
- (IBAction)closeSplitTextView:(nullable id)sender
// ------------------------------------------------------
{
    CEEditorViewController *currentEditorViewController;
    
    // find target CEEditorViewController
    id view = [sender isMemberOfClass:[NSMenuItem class]] ? [[self window] firstResponder] : sender;
    while (view) {
        if ([[view identifier] isEqualToString:@"EditorView"]) {
            currentEditorViewController = [[self splitViewController] viewControllerForSubview:view];
            break;
        }
        view = [view superview];
    }
    
    if (!currentEditorViewController) { return; }
    
    // end current editing
    [[[NSTextInputContext currentInputContext] client] unmarkText];
    
    // move focus to the next text view if the view to close has a focus
    if ([[self window] firstResponder] == [currentEditorViewController textView]) {
        NSArray<__kindof NSView *> *subViews = [[[self splitViewController] view] subviews];
        NSUInteger count = [subViews count];
        NSUInteger deleteIndex = [subViews indexOfObject:[currentEditorViewController view]];
        NSUInteger index = deleteIndex + 1;
        if (index >= count) {
            index = count - 2;
        }
        NSTextView *nextTextView = [[[self splitViewController] viewControllerForSubview:subViews[index]] textView];
        [[self window] makeFirstResponder:nextTextView];
    }
    
    // close
    [[self splitViewController] removeSubviewForViewController:currentEditorViewController];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// apply text styles from text view
- (void)invalidateStyleInTextStorage
// ------------------------------------------------------
{
    [[self focusedTextView] invalidateStyle];
}


// ------------------------------------------------------
/// サブビューに初期値を設定
- (nonnull CEEditorViewController *)createEditorBasedViewController:(nullable CEEditorViewController *)baseViewController
// ------------------------------------------------------
{
    CEEditorViewController *editorViewController = [[CEEditorViewController alloc] initWithTextStorage:[[self document] textStorage]];
    
    // instert new editorView just below the editorView that the pressed button belongs to or has focus
    [[self splitViewController] addSubviewForViewController:editorViewController relativeTo:[baseViewController view]];
    
    [editorViewController setShowsInvisibles:[self showsInvisibles]];
    [editorViewController setShowsLineNum:[self showsLineNum]];
    [editorViewController setShowsNavigationBar:[self showsNavigationBar] animate:NO];
    [editorViewController setWrapsLines:[self wrapsLines]];
    [[editorViewController textView] setLayoutOrientation:([self isVerticalLayoutOrientation] ?
                                                           NSTextLayoutOrientationVertical : NSTextLayoutOrientationHorizontal)];
    [[editorViewController textView] setShowsPageGuide:[self showsPageGuide]];
    
    [editorViewController applySyntax:[self syntaxStyle]];
    
    // copy textView states
    if (baseViewController) {
        [[editorViewController textView] setFont:[[baseViewController textView] font]];
        [[editorViewController textView] setTheme:[[baseViewController textView] theme]];
        [[editorViewController textView] setLineSpacing:[[baseViewController textView] lineSpacing]];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textViewDidChangeSelection:)
                                                 name:NSTextViewDidChangeSelectionNotification
                                               object:[editorViewController textView]];
    
    return editorViewController;
}


// ------------------------------------------------------
/// ウインドウを返す
- (NSWindow *)window
// ------------------------------------------------------
{
    return [[[self splitViewController] view] window];
}


// ------------------------------------------------------
/// text storage を返す
- (NSTextStorage *)textStorage
// ------------------------------------------------------
{
    return [[self document] textStorage];
}


// ------------------------------------------------------
/// return all layoutManagers
- (NSArray<NSLayoutManager *> *)layoutManagers
// ------------------------------------------------------
{
    return [[[self document] textStorage] layoutManagers];
}


// ------------------------------------------------------
/// documentを返す
- (CEDocument *)document
// ------------------------------------------------------
{
    return [[[self window] windowController] document];
}

@end




#pragma mark -

@implementation CEEditorWrapper (SyntaxParsing)

#pragma mark Public Methods

// ------------------------------------------------------
/// シンタックススタイル名を返す
- (nullable CESyntaxStyle *)syntaxStyle
// ------------------------------------------------------
{
    return [[self document] syntaxStyle];
}


// ------------------------------------------------------
/// 全テキストを再カラーリング
- (void)invalidateSyntaxHighlight
// ------------------------------------------------------
{
    [[self syntaxStyle] highlightWholeStringWithCompletionHandler:nil];
}


// ------------------------------------------------------
/// アウトラインメニューを更新
- (void)invalidateOutlineMenu
// ------------------------------------------------------
{
    [[self outlineMenuTimer] invalidate];
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultEnableSyntaxHighlightKey]) { return; }
    
    NSString *wholeString = [[self textStorage] string] ? : @"";
    
    // 規定の文字数以上の場合にはインジケータを表示
    // （ただし、CEDefaultShowColoringIndicatorTextLengthKey が「0」の時は表示しない）
    NSUInteger indicatorThreshold = [[NSUserDefaults standardUserDefaults] integerForKey:CEDefaultShowColoringIndicatorTextLengthKey];
    if (indicatorThreshold > 0 && indicatorThreshold < [wholeString length]) {
        [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
            [[viewController navigationBarController] showOutlineIndicator];
        }];
    }
    
    // extract outline and pass result to navigationBar
    CESplitViewController *splitViewController = [self splitViewController];
    [[self syntaxStyle] parseOutlineWithCompletionHandler:^(NSArray<CEOutlineItem *> * _Nonnull outlineItems)
     {
         [splitViewController enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
             [[viewController navigationBarController] setOutlineItems:outlineItems];
             // -> The selection update will be done in the `setOutlineItems` method above, so you don't need invoke it (2008-05-16)
         }];
    }];
}



#pragma mark Action Messages

// ------------------------------------------------------
/// ドキュメント全体を再カラーリング
- (IBAction)recolorAll:(nullable id)sender
// ------------------------------------------------------
{
    [self invalidateSyntaxHighlight];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// シンタックススタイル名をセット
- (void)didChangeSyntaxStyle:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    CESyntaxStyle *syntaxStyle = [[self document] syntaxStyle];
    [[self splitViewController] enumerateEditorViewsUsingBlock:^(CEEditorViewController * _Nonnull viewController) {
        [viewController applySyntax:syntaxStyle];
    }];
    
    [self invalidateSyntaxHighlight];
    [self invalidateOutlineMenu];
}


// ------------------------------------------------------
/// アウトラインメニュー更新
- (void)updateOutlineMenuWithTimer:(nonnull NSTimer *)timer
// ------------------------------------------------------
{
    [self invalidateOutlineMenu];  // (The outlineMenuTimer will be invalidated in this invalidateOutlineMenu method.)
}

@end


@implementation CEEditorWrapper (PrivateSyntaxParsing)

// ------------------------------------------------------
/// return if sytnax highlight works
- (BOOL)canHighlight
// ------------------------------------------------------
{
    BOOL isHighlightEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultEnableSyntaxHighlightKey];
    BOOL isHighlightable = ([self syntaxStyle] != nil) && ![[self syntaxStyle] isNone];
    
    return isHighlightEnabled && isHighlightable;
}


// ------------------------------------------------------
/// let parse outline after a delay
- (void)setupOutlineMenuUpdateTimer
// ------------------------------------------------------
{
    if (![self canHighlight]) { return; }
    
    NSTimeInterval interval = [[NSUserDefaults standardUserDefaults] doubleForKey:CEDefaultOutlineMenuIntervalKey];
    if ([[self outlineMenuTimer] isValid]) {
        [[self outlineMenuTimer] setFireDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
    } else {
        [self setOutlineMenuTimer:[NSTimer scheduledTimerWithTimeInterval:interval
                                                                   target:self
                                                                 selector:@selector(updateOutlineMenuWithTimer:)
                                                                 userInfo:nil
                                                                  repeats:NO]];
    }
}

@end




#pragma mark -

@implementation CEEditorWrapper (TextEditing)

#pragma mark Public Methods

// ------------------------------------------------------
/// textView の文字列を返す（改行コードはLF固定）
- (nonnull NSString *)string
// ------------------------------------------------------
{
    return [[self focusedTextView] string] ?: @"";
}


// ------------------------------------------------------
/// 指定された範囲の textView の文字列を返す
- (nonnull NSString *)substringWithRange:(NSRange)range
// ------------------------------------------------------
{
    return [[self string] substringWithRange:range];
}


// ------------------------------------------------------
/// メイン textView で選択された文字列を返す
- (nonnull NSString *)substringWithSelection
// ------------------------------------------------------
{
    return [[self string] substringWithRange:[[self focusedTextView] selectedRange]];
}


// ------------------------------------------------------
/// 選択文字列を置換する
- (void)insertTextViewString:(nonnull NSString *)string
// ------------------------------------------------------
{
    [[self focusedTextView] insertString:string];
}


// ------------------------------------------------------
/// 選択範囲の直後に文字列を挿入
- (void)insertTextViewStringAfterSelection:(nonnull NSString *)string
// ------------------------------------------------------
{
    [[self focusedTextView] insertStringAfterSelection:string];
}


// ------------------------------------------------------
/// 全文字列を置換
- (void)replaceTextViewAllStringWithString:(nonnull NSString *)string
// ------------------------------------------------------
{
    [[self focusedTextView] replaceAllStringWithString:string];
}


// ------------------------------------------------------
/// 文字列の最後に新たな文字列を追加
- (void)appendTextViewString:(nonnull NSString *)string
// ------------------------------------------------------
{
    [[self focusedTextView] appendString:string];
}


// ------------------------------------------------------
/// 選択範囲を返す
- (NSRange)selectedRange
// ------------------------------------------------------
{
    NSTextView *textView = [self focusedTextView];
    
    return [[textView string] convertRange:[textView selectedRange]
                           fromNewLineType:CENewLineLF
                             toNewLineType:[[self document] lineEnding]];
}


// ------------------------------------------------------
/// 選択範囲を変更
- (void)setSelectedRange:(NSRange)charRange
// ------------------------------------------------------
{
    NSTextView *textView = [self focusedTextView];
    NSRange range = [[textView string] convertRange:charRange
                                    fromNewLineType:[[self document] lineEnding]
                                      toNewLineType:CENewLineLF];
    
    [textView setSelectedRange:range];
}

@end




#pragma mark -

@implementation CEEditorWrapper (Locating)

#pragma mark Action Messages

// ------------------------------------------------------
/// show Go To sheet
- (IBAction)gotoLocation:(nullable id)sender
// ------------------------------------------------------
{
    CEGoToSheetController *sheetController = [[CEGoToSheetController alloc] init];
    [sheetController beginSheetForEditor:self];
}



#pragma mark Public Methods

// ------------------------------------------------------
/// convert minus location/length to NSRange
- (NSRange)rangeWithLocation:(NSInteger)location length:(NSInteger)length
// ------------------------------------------------------
{
    NSString *documentString = [[self string] stringByReplacingNewLineCharacersWith:[[self document] lineEnding]];
    
    return [documentString rangeForLocation:location length:length];
}


// ------------------------------------------------------
/// editor 内部の textView で指定された部分を文字単位で選択
- (void)setSelectedCharacterRangeWithLocation:(NSInteger)location length:(NSInteger)length
// ------------------------------------------------------
{
    NSRange range = [self rangeWithLocation:location length:length];
    
    if (range.location == NSNotFound) { return; }
    
    [self setSelectedRange:range];
}


// ------------------------------------------------------
/// editor 内部の textView で指定された部分を行単位で選択
- (void)setSelectedLineRangeWithLocation:(NSInteger)location length:(NSInteger)length
// ------------------------------------------------------
{
    // you can ignore actuall line ending type and directly comunicate with textView, as this handle just lines
    NSTextView *textView = [self focusedTextView];
    
    NSRange range = [[textView string] rangeForLineLocation:location length:length];
    
    if (range.location == NSNotFound) { return; }
    
    [textView setSelectedRange:range];
}


// ------------------------------------------------------
/// 選択範囲を変更する
- (void)gotoLocation:(NSInteger)location length:(NSInteger)length type:(CEGoToType)type
// ------------------------------------------------------
{
    switch (type) {
        case CEGoToLine:
            [self setSelectedLineRangeWithLocation:location length:length];
            break;
        case CEGoToCharacter:
            [self setSelectedCharacterRangeWithLocation:location length:length];
            break;
    }
    
    NSTextView *textView = [self focusedTextView];
    [[textView window] makeKeyAndOrderFront:self]; // 対象ウィンドウをキーに
    [textView scrollRangeToVisible:[textView selectedRange]]; // 選択範囲が見えるようにスクロール
    [textView showFindIndicatorForRange:[textView selectedRange]];  // 検索結果表示エフェクトを追加
}

@end
