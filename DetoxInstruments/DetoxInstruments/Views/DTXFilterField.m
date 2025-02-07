//
//  DTXFilterField.m
//  DetoxInstruments
//
//  Created by Artal Druk on 28/08/2017.
//  Copyright © 2017-2021 Wix. All rights reserved.
//

#import "DTXFilterField.h"

@implementation DTXFilterField
{
	IBOutlet NSImageView* _filterImageView;
	IBOutlet NSButton* _cancelButton;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	
	self.delegate = self;
	self.centersPlaceholder = NO;
	
	[self setSearchIconWithHighlight:NO];
	
	self.wantsLayer = YES;
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
	self.canDrawSubviewsIntoLayer = YES;
	
	[((NSSearchFieldCell*)self.cell).searchButtonCell setTransparent:YES];
	[((NSSearchFieldCell*)self.cell).searchButtonCell setEnabled:NO];
	[((NSSearchFieldCell*)self.cell).cancelButtonCell setTransparent:YES];
	[((NSSearchFieldCell*)self.cell).cancelButtonCell setEnabled:NO];
	
	_cancelButton.hidden = YES;
}

- (void)setSearchIconWithHighlight:(BOOL)highlighted
{
	if(@available(macOS 11.0, *))
	{
		_filterImageView.image = [NSImage imageWithSystemSymbolName:[NSString stringWithFormat:@"line.horizontal.3.decrease.circle%@", highlighted ? @".fill" : @""] accessibilityDescription:nil];
	}
	else
	{
		_filterImageView.image = [NSImage imageNamed:[NSString stringWithFormat:@"SearchFilter%@", highlighted ? @"On" : @"Off"]];
	}
	
	_filterImageView.contentTintColor = highlighted ? NSColor.controlAccentColor : nil;
}

- (NSRect)rectForSearchTextWhenCentered:(BOOL)isCentered
{
	return CGRectOffset([super rectForSearchTextWhenCentered:isCentered], 3, 0);
}

- (void)searchFieldDidStartSearching:(NSSearchField *)sender
{
	[self setSearchIconWithHighlight:YES];
	_cancelButton.hidden = NO;
}

- (void)searchFieldDidEndSearching:(NSSearchField *)sender
{
	[self setSearchIconWithHighlight:NO];
	_cancelButton.hidden = YES;
	
	//Ensure UI updates after search ends
	[self.filterDelegate filterFieldTextDidChange:self];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	[self.filterDelegate filterFieldTextDidChange:self];
}

- (void)setFrame:(NSRect)frame
{
	[super setFrame:frame];
	
	[self setNeedsDisplay:YES];
}

- (IBAction)clearFilter:(id)sender
{
	[self clearFilter];
}

- (void)clearFilter
{
	NSButtonCell* buttonCell = ((NSSearchFieldCell*)self.cell).cancelButtonCell;
	[NSApp sendAction:buttonCell.action to:buttonCell.target from:buttonCell];
}

@end
