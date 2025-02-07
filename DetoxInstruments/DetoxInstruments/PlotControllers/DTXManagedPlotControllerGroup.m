//
//  DTXManagedPlotControllerGroup.m
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 02/06/2017.
//  Copyright © 2017-2021 Wix. All rights reserved.
//

#import "DTXManagedPlotControllerGroup.h"
#import "DTXTimelineIndicatorView.h"
#import "DTXPlotRowView.h"
#import "DTXPlotTypeCellView.h"
#import "DTXPlotHostingTableCellView.h"
#import "NSColor+UIAdditions.h"
#import "DTXPlotController-Private.h"

@interface DTXManagedPlotControllerGroup () <DTXPlotControllerDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource>
{
	NSMutableArray<id<DTXPlotController>>* _managedPlotControllers;
	NSMutableArray<id<DTXPlotController>>* _visiblePlotControllers;
	NSMapTable<id<DTXPlotController>, NSMutableArray<id<DTXPlotController>>*>* _childrenMap;
	
	NSUInteger _ignoringPlotRangeNotificationsCount;
	DTXTimelineIndicatorView* _timelineView;
	DTXPlotRange* _savedPlotRange;
	DTXPlotRange* _savedGlobalPlotRange;
	DTXPlotRange* _savedHighlightRange;
	
	id<DTXPlotController> _currentlySelectedPlotController;
	
	NSTimeInterval _savedDataEnd;
}

@property (nonatomic, strong) NSOutlineView* hostingOutlineView;

@end

@interface NSUserDefaults ()

- (id)_initWithSuiteName:(id)i container:(id)p;

@end

@implementation DTXManagedPlotControllerGroup
{
	__weak DTXRecordingDocument* _document;
}

- (id<DTXPlotController>)selectedPlotController
{
	return _currentlySelectedPlotController;
}

- (instancetype)initWithHostingOutlineView:(NSOutlineView*)outlineView document:(DTXRecordingDocument*)document
{
	self = [super init];
	
	if(self)
	{
		_document = document;
		
		_managedPlotControllers = [NSMutableArray new];
		_visiblePlotControllers = [NSMutableArray new];
		_childrenMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory];
		
		_hostingOutlineView = outlineView;
		_hostingOutlineView.indentationPerLevel = 0;
		_hostingOutlineView.indentationMarkerFollowsCell = NO;
		_hostingOutlineView.dataSource = self;
		_hostingOutlineView.delegate = self;
//		_hostingOutlineView.usesAutomaticRowHeights = YES;
		
		_timelineView = [DTXTimelineIndicatorView new];
		_timelineView.tableView = _hostingOutlineView;
		_timelineView.translatesAutoresizingMaskIntoConstraints = NO;

		[_hostingOutlineView.enclosingScrollView.superview addSubview:_timelineView positioned:NSWindowAbove relativeTo:_hostingOutlineView.superview.superview];

		[NSLayoutConstraint activateConstraints:@[
												  [_hostingOutlineView.enclosingScrollView.topAnchor constraintEqualToAnchor:_timelineView.topAnchor],
												  [_hostingOutlineView.enclosingScrollView.leadingAnchor constraintEqualToAnchor:_timelineView.leadingAnchor],
												  [_hostingOutlineView.enclosingScrollView.trailingAnchor constraintEqualToAnchor:_timelineView.trailingAnchor],
												  [_hostingOutlineView.enclosingScrollView.bottomAnchor constraintEqualToAnchor:_timelineView.bottomAnchor]
												  ]];
	}
	
	return self;
}

- (NSArray<id<DTXPlotController>> *)plotControllers
{
	return _managedPlotControllers;
}

- (NSArray<id<DTXPlotController>> *)visiblePlotControllers
{
	return _visiblePlotControllers;
}

- (void)setHeaderPlotController:(id<DTXPlotController>)headerPlotController
{
	_headerPlotController = headerPlotController;
	_headerPlotController.delegate = self;
	
	if(_savedGlobalPlotRange)
	{
		[headerPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	}
	
	if(_savedPlotRange)
	{
		[headerPlotController setPlotRange:_savedPlotRange];
	}
}

- (void)setTouchBarPlotController:(id<DTXPlotController>)touchBarPlotController
{
	_touchBarPlotController = touchBarPlotController;
	
	_touchBarPlotController.delegate = self;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		//Delay cached updates to next runloop to let data load.
		if(_savedGlobalPlotRange)
		{
			[_touchBarPlotController setGlobalPlotRange:_savedGlobalPlotRange];
		}
		
		if(_savedPlotRange)
		{
			[_touchBarPlotController setPlotRange:_savedPlotRange];
		}
		
		if(_savedHighlightRange)
		{
			[_touchBarPlotController shadowHighlightRange:_savedHighlightRange];
		}
	});
}

- (void)_plotControllerRequiredHeightDidChange:(NSNotification*)note
{
	if([self.visiblePlotControllers containsObject:note.object])
	{
		[NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
			context.duration = 0.0;
			[_hostingOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:[_hostingOutlineView rowForItem:note.object]]];
		}];
	}
}

- (void)addPlotController:(id<DTXPlotController>)plotController
{
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_plotControllerRequiredHeightDidChange:) name:DTXPlotControllerRequiredHeightDidChangeNotification object:plotController];
	
	[self _insertPlotController:plotController afterPlotController:_managedPlotControllers.lastObject parentPlotController:nil inCollection:_managedPlotControllers];
}

- (void)removePlotController:(id<DTXPlotController>)plotController
{
	plotController.delegate = nil;
	[_managedPlotControllers removeObject:plotController];
	[_visiblePlotControllers removeObject:plotController];
}

- (void)_insertPlotController:(id<DTXPlotController>)plotController afterPlotController:(id<DTXPlotController>)afterPlotController parentPlotController:(id<DTXPlotController>)parentPlotController inCollection:(NSMutableArray<id<DTXPlotController>>*)collection
{
	NSInteger idx;
	
	if(afterPlotController == nil)
	{
		//This will make sure we insert at index 0.
		idx = -1;
	}
	else if(collection.firstObject == afterPlotController)
	{
		idx = 0;
	}
	else if(collection.lastObject == afterPlotController)
	{
		idx = collection.count - 1;
	}
	else
	{
		idx = [collection indexOfObject:afterPlotController];
	}
	
	if(idx == NSNotFound)
	{
		return;
	}
	
	[collection insertObject:plotController atIndex:idx + 1];
	plotController.delegate = self;
	
	if(_savedGlobalPlotRange)
	{
		[plotController setGlobalPlotRange:_savedGlobalPlotRange];
	}
	
	if(_savedPlotRange)
	{
		[plotController setPlotRange:_savedPlotRange];
	}
	
	if(_savedHighlightRange)
	{
		[plotController shadowHighlightRange:_savedHighlightRange];
	}
	
	if(collection == _managedPlotControllers)
	{
		if([self isPlotControllerVisible:plotController])
		{
			[self _insertPlotControllerToVisibleControllers:plotController animated:NO];
		}
	}
	else
	{
		[self _noteOutlineViewOfInsertedAtIndex:idx + 1 forItem:parentPlotController animated:NO];
	}
}

- (void)_selectFirstPlotControllerIfNeeded
{
#if ! PROFILER_PREVIEW_EXTENSION
	if(_hostingOutlineView.selectedRowIndexes.count == 0)
	{
		[_hostingOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
#endif
}

- (void)_insertPlotControllerToVisibleControllers:(id<DTXPlotController>)plotController animated:(BOOL)animated
{
	__block NSUInteger idxToInsert = 0;
	
	if(_managedPlotControllers.lastObject == plotController && _managedPlotControllers.count == _visiblePlotControllers.count - 1)
	{
		idxToInsert = _managedPlotControllers.count - 1;
	}
	else
	{
		NSUInteger idxOfPlotController = [_managedPlotControllers indexOfObject:plotController];
		
		if(_managedPlotControllers.count == _visiblePlotControllers.count)
		{
			idxToInsert = idxOfPlotController;
		}
		else
		{
			for(id<DTXPlotController> obj in _visiblePlotControllers)
			{
				NSUInteger idxOfCandidate = [_managedPlotControllers indexOfObject:obj];
				
				if(idxOfCandidate > idxOfPlotController)
				{
					break;
				}
				
				idxToInsert += 1;
			}
		}
	}
	
	[_visiblePlotControllers insertObject:plotController atIndex:idxToInsert];
	
	[self _noteOutlineViewOfInsertedAtIndex:idxToInsert forItem:nil animated:animated];
	
	[self _selectFirstPlotControllerIfNeeded];
}

- (void)_removePlotControllerFromVisibleControllers:(id<DTXPlotController>)plotController animated:(BOOL)animated
{
	NSUInteger idx = [_visiblePlotControllers indexOfObject:plotController];
	[_visiblePlotControllers removeObject:plotController];
	
	if(_hostingOutlineView.selectedRow == idx)
	{
		[self.delegate managedPlotControllerGroup:self didSelectPlotController:nil];
	}
	
	[self _noteOutlineViewOfRemovedAtIndex:idx forItem:nil animated:animated];
	
	[self _selectFirstPlotControllerIfNeeded];
}

- (void)_setPlotController:(id<DTXPlotController>)plotController visible:(BOOL)visible
{
	NSMutableDictionary* plotControllerVisibility = [[_document objectForPreferenceKey:@"plotControllerVisibility"] mutableCopy] ?: NSMutableDictionary.new;
	
	plotControllerVisibility[NSStringFromClass(plotController.class)] = @(visible);
	
	if(visible)
	{
		[self _insertPlotControllerToVisibleControllers:plotController animated:YES];
		[self.delegate managedPlotControllerGroup:self didShowPlotController:plotController];
	}
	else
	{
		[self _removePlotControllerFromVisibleControllers:plotController animated:YES];
		[self.delegate managedPlotControllerGroup:self didHidePlotController:plotController];
	}
	
	[_document setObject:plotControllerVisibility forPreferenceKey:@"plotControllerVisibility"];
}

- (void)setPlotControllerVisible:(id<DTXPlotController>)plotController
{
	[self _setPlotController:plotController visible:YES];
}

- (void)setPlotControllerHidden:(id<DTXPlotController>)plotController
{
	[self _setPlotController:plotController visible:NO];
}

- (BOOL)isPlotControllerVisible:(id<DTXPlotController>)plotController
{
	return [([_document objectForPreferenceKey:@"plotControllerVisibility"][NSStringFromClass(plotController.class)] ?: @YES) boolValue];
}

- (void)resetPlotControllerVisibility
{
	[_document setObject:nil forPreferenceKey:@"plotControllerVisibility"];
	
	NSIndexSet* removed = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _visiblePlotControllers.count)];
	
	[_visiblePlotControllers removeAllObjects];
	
	[self _noteOutlineViewOfRemovedAtIndexSet:removed forItem:nil animated:YES];
	
	[_visiblePlotControllers addObjectsFromArray:_managedPlotControllers];
	
	NSIndexSet* added = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _visiblePlotControllers.count)];
	[self _noteOutlineViewOfInsertedAtIndexSet:added forItem:nil animated:YES];
	
	[self _selectFirstPlotControllerIfNeeded];
}

- (void)_noteOutlineViewOfInsertedAtIndexSet:(NSIndexSet*)indexSet forItem:(id<DTXPlotController>)item animated:(BOOL)animated
{
	NSTableViewAnimationOptions animationOptions = animated ? (indexSet.count == 1 ? NSTableViewAnimationSlideRight : NSTableViewAnimationEffectNone) : NSTableViewAnimationEffectNone;
	
	[_hostingOutlineView beginUpdates];
	[_hostingOutlineView insertItemsAtIndexes:indexSet inParent:item withAnimation:animationOptions];
	[_hostingOutlineView endUpdates];
}

- (void)_noteOutlineViewOfInsertedAtIndex:(NSUInteger)index forItem:(id<DTXPlotController>)item animated:(BOOL)animated
{
	[self _noteOutlineViewOfInsertedAtIndexSet:[NSIndexSet indexSetWithIndex:index] forItem:item animated:animated];
}

- (void)_noteOutlineViewOfRemovedAtIndexSet:(NSIndexSet*)indexSet forItem:(id<DTXPlotController>)item animated:(BOOL)animated
{
	NSTableViewAnimationOptions animationOptions = animated ? (indexSet.count == 1 ? NSTableViewAnimationSlideRight : NSTableViewAnimationEffectNone) : NSTableViewAnimationEffectNone;
	
	[_hostingOutlineView beginUpdates];
	[_hostingOutlineView removeItemsAtIndexes:indexSet inParent:item withAnimation:animationOptions];
	[_hostingOutlineView endUpdates];
}

- (void)_noteOutlineViewOfRemovedAtIndex:(NSUInteger)index forItem:(id<DTXPlotController>)item animated:(BOOL)animated
{
	[self _noteOutlineViewOfRemovedAtIndexSet:[NSIndexSet indexSetWithIndex:index] forItem:item animated:animated];
}

- (NSMutableArray<id<DTXPlotController>>*)_childrenArrayForPlotController:(id<DTXPlotController>)plotController create:(BOOL)create
{
	NSMutableArray* rv = [_childrenMap objectForKey:plotController];
	
	if(create == YES && rv == nil)
	{
		rv = [NSMutableArray new];
		[_childrenMap setObject:rv forKey:plotController];
	}
	
	return rv;
}

- (NSArray<id<DTXPlotController>>*)childPlotControllersForPlotController:(id<DTXPlotController>)plotController;
{
	return [self _childrenArrayForPlotController:plotController create:YES];
}

- (void)addChildPlotController:(id<DTXPlotController>)childPlotController toPlotController:(id<DTXPlotController>)plotController
{
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_plotControllerRequiredHeightDidChange:) name:DTXPlotControllerRequiredHeightDidChangeNotification object:plotController];
	
	childPlotController.parentPlotController = plotController;
	NSMutableArray* children = [self _childrenArrayForPlotController:plotController create:YES];
	[self _insertPlotController:childPlotController afterPlotController:children.lastObject parentPlotController:plotController inCollection:children];
}

- (void)removeChildPlotController:(id<DTXPlotController>)childPlotController ofPlotController:(id<DTXPlotController>)plotController
{
	childPlotController.delegate = nil;
	[_managedPlotControllers removeObject:childPlotController];
}

- (void)_enumerateAllPlotControllersIncludingChildrenIn:(NSMutableArray<id<DTXPlotController>>*)plotControllers usingBlock:(void (NS_NOESCAPE ^)(id<DTXPlotController> obj))block
{
	[plotControllers enumerateObjectsUsingBlock:^(id<DTXPlotController>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		block(obj);
		
		NSMutableArray<id<DTXPlotController>>* children = [_childrenMap objectForKey:obj];
		if(children != nil)
		{
			[self _enumerateAllPlotControllersIncludingChildrenIn:children usingBlock:block];
		}
	}];
}

- (void)_resetSavedPlotRange:(DTXPlotRange*)plotRange updatePlotControllers:(BOOL)update notifyDelegate:(BOOL)notify byUser:(BOOL)byUser
{
	_savedPlotRange = plotRange;
	
	_ignoringPlotRangeNotificationsCount ++;
	if(update)
	{
		[_headerPlotController setPlotRange:plotRange];
		[_touchBarPlotController setPlotRange:plotRange];
		[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
			[obj setPlotRange:plotRange];
		}];
	}
	_ignoringPlotRangeNotificationsCount --;
	
	if(notify)
	{
		[self _updateDelegateForScrollerChangeByUser:byUser];
	}
}

- (void)_updateDelegateForScrollerChangeByUser:(BOOL)byUser
{
	CGFloat proportion = _savedPlotRange.length / _savedGlobalPlotRange.length;
	CGFloat value = _savedPlotRange.position / (_savedGlobalPlotRange.length - _savedPlotRange.length);
	
	NSEventType type = _hostingOutlineView.window.currentEvent.type;
	BOOL isUserEvent = type == NSEventTypeMagnify || type == NSEventTypeLeftMouseDragged || type == NSEventTypeScrollWheel;
	
	[self.delegate managedPlotControllerGroup:self updateScrollerToProportion:proportion value:value initiatedByUser:isUserEvent && byUser];
}

- (void)setDataStartTimestamp:(NSDate*)startTimestamp endTimestamp:(NSDate*)endTimestamp
{
	_savedDataEnd = endTimestamp.timeIntervalSinceReferenceDate - startTimestamp.timeIntervalSinceReferenceDate;
}

- (void)scrollToDataEnd
{
	NSTimeInterval length = _savedPlotRange.length;
	[self _resetSavedPlotRange:[DTXPlotRange plotRangeWithPosition:MAX(0, _savedDataEnd - length) length:length] updatePlotControllers:YES notifyDelegate:YES byUser:NO];
}

- (void)setLocalStartTimestamp:(NSDate*)startTimestamp endTimestamp:(NSDate*)endTimestamp
{
	[self _resetSavedPlotRange:[DTXPlotRange plotRangeWithPosition:0 length:endTimestamp.timeIntervalSinceReferenceDate - startTimestamp.timeIntervalSinceReferenceDate] updatePlotControllers:NO notifyDelegate:YES byUser:NO];
}

- (void)setGlobalStartTimestamp:(NSDate*)startTimestamp endTimestamp:(NSDate*)endTimestamp ignoreSmaller:(BOOL)ignoreSmaller
{
	NSTimeInterval length = endTimestamp.timeIntervalSinceReferenceDate - startTimestamp.timeIntervalSinceReferenceDate;
	
	if(ignoreSmaller == YES && length < _savedGlobalPlotRange.length)
	{
		[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
			[obj setDataLimitRange:[DTXPlotRange plotRangeWithPosition:0 length:_savedDataEnd]];
		}];
		
		return;
	}
	
	_savedGlobalPlotRange = [DTXPlotRange plotRangeWithPosition:0 length:length];
	
	_ignoringPlotRangeNotificationsCount ++;
	[_headerPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	[_touchBarPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		[obj setDataLimitRange:_savedGlobalPlotRange];
		[obj setGlobalPlotRange:_savedGlobalPlotRange];
	}];

	_ignoringPlotRangeNotificationsCount --;
	
	[self _updateDelegateForScrollerChangeByUser:NO];
}

- (void)zoomIn
{
	//Zooming in or out one plot controller will propagate to others using the plotController:didChangeToPlotRange: delegate method.
	[_visiblePlotControllers.firstObject zoomIn];
}

- (void)zoomOut
{
	//Zooming in or out one plot controller will propagate to others using the plotController:didChangeToPlotRange: delegate method.
	[_visiblePlotControllers.firstObject zoomOut];
}

- (void)zoomToFitAllData
{
	//Zooming in or out one plot controller will propagate to others using the plotController:didChangeToPlotRange: delegate method.
	[_visiblePlotControllers.firstObject zoomToFitAllData];
}

- (void)scrollToValue:(CGFloat)value
{
	value = value - (value * _savedPlotRange.length / _savedGlobalPlotRange.length);
	
	DTXPlotRange* newPlotRange = [DTXPlotRange plotRangeWithPosition:value * _savedGlobalPlotRange.length length:_savedPlotRange.length];
	
	[self _resetSavedPlotRange:newPlotRange updatePlotControllers:YES notifyDelegate:YES byUser:NO];
}

- (void)plotControllerUserDidClickInPlotBounds:(id<DTXPlotController>)pc
{
	if([_hostingOutlineView selectedRow] == [_hostingOutlineView rowForItem:pc])
	{
		return;
	}
	
#if ! PROFILER_PREVIEW_EXTENSION
	[_hostingOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[_hostingOutlineView rowForItem:pc]] byExtendingSelection:NO];
#endif
	[_hostingOutlineView.window makeFirstResponder:_hostingOutlineView];
}

#pragma mark DTXPlotControllerDelegate

- (void)plotController:(id<DTXPlotController>)pc didChangeToPlotRange:(DTXPlotRange *)plotRange
{
	if(_ignoringPlotRangeNotificationsCount > 0)
	{
		return;
	}
	
	_ignoringPlotRangeNotificationsCount ++;
	
	[self _resetSavedPlotRange:plotRange updatePlotControllers:NO notifyDelegate:YES byUser:YES];
	
	if(pc != _headerPlotController)
	{
		[_headerPlotController setPlotRange:plotRange];
	}
	
	if(pc != _touchBarPlotController)
	{
		[_touchBarPlotController setPlotRange:plotRange];
	}
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_visiblePlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		[obj setPlotRange:plotRange];
	}];
	
	_ignoringPlotRangeNotificationsCount --;
}

- (void)plotController:(id<DTXPlotController>)pc didHighlightRange:(DTXPlotRange*)highlightRange
{
	_savedHighlightRange = highlightRange;
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_visiblePlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		if([obj respondsToSelector:@selector(shadowHighlightRange:)])
		{
			[obj shadowHighlightRange:highlightRange];
		}
	}];
	
	if([_touchBarPlotController respondsToSelector:@selector(shadowHighlightRange:)])
	{
		[_touchBarPlotController shadowHighlightRange:highlightRange];
	}
}

- (void)plotControllerDidRemoveHighlight:(id<DTXPlotController>)pc
{
	_savedHighlightRange = nil;
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_visiblePlotControllers usingBlock:(id)^(id<DTXPlotControllerPrivate> obj) {
		if(obj == pc)
		{
			return;
		}
		
		[obj _removeHighlightNotifyingDelegate:NO];
	}];
	
	[(id<DTXPlotControllerPrivate>)_touchBarPlotController _removeHighlightNotifyingDelegate:NO];
}

#pragma mark NSOutlineView Data Source & Delegate

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if(item == nil)
	{
		return _visiblePlotControllers.count;
	}
	
	return [[self _childrenArrayForPlotController:item create:NO] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[self _childrenArrayForPlotController:item create:NO] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if(item == nil)
	{
		return _visiblePlotControllers[index];
	}
	
	id<DTXPlotController> plotController = item;
	return [[self _childrenArrayForPlotController:plotController create:NO] objectAtIndex:index];
}

- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
	auto rv = [DTXPlotRowView new];
	rv.tableView = outlineView;
	
	return rv;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	id<DTXPlotController> controller = item;
	
	if([tableColumn.identifier isEqualToString:@"DTXTitleColumnt"])
	{
		DTXPlotTypeCellView* cell = [outlineView makeViewWithIdentifier:@"InfoTableViewCell" owner:nil];
		cell.textField.font = controller.titleFont;
		cell.textField.stringValue = controller.displayName;
		cell.textField.toolTip = controller.toolTip ?: controller.displayName;
		cell.textField.allowsDefaultTighteningForTruncation = YES;
#if ! PROFILER_PREVIEW_EXTENSION
		cell.imageView.image = controller.displayIcon;
#else
		cell.imageView.image = controller.smallDisplayIcon;
#endif
		cell.secondaryImageView.image = controller.secondaryIcon;
		cell.secondaryImageView.hidden = controller.secondaryIcon == nil;
		cell.toolTip = controller.toolTip ?: controller.displayName;
#if ! PROFILER_PREVIEW_EXTENSION
		if([controller respondsToSelector:@selector(supportsQuickSettings)] && controller.supportsQuickSettings == YES)
		{
			NSMenu* menu = controller.quickSettingsMenu;
			
			if(menu != nil)
			{
				cell.settingsButton.hidden = YES;
				cell.settingsMenuButton.hidden = NO;
				cell.settingsMenuButton.menu = menu;
			}
			else
			{
				cell.settingsMenuButton.hidden = YES;
				cell.settingsButton.hidden = NO;
				cell.settingsButton.target = controller;
				cell.settingsButton.action = @selector(showQuickSettings:);
			}
		}
		else
		{
			cell.settingsButton.hidden = YES;
			cell.settingsMenuButton.hidden = YES;
		}
#else
		cell.settingsMenuButton.hidden = YES;
#endif
		
		if(controller.legendTitles.count > 1)
		{
			cell.topLegendTextField.hidden = cell.bottomLegendTextField.hidden = NO;
			cell.topLegendTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", controller.legendTitles.firstObject ?: @""] attributes:@{NSForegroundColorAttributeName: controller.legendColors.firstObject ?: NSColor.labelColor}];
			cell.bottomLegendTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", controller.legendTitles.lastObject ?: @""] attributes:@{NSForegroundColorAttributeName: controller.legendColors.lastObject ?: NSColor.labelColor}];
		}
		else
		{
			cell.topLegendTextField.hidden = cell.bottomLegendTextField.hidden = YES;
		}
		
		return cell;
	}
	else if([tableColumn.identifier isEqualToString:@"DTXGraphColumn"])
	{
		DTXPlotHostingTableCellView* cell = [outlineView makeViewWithIdentifier:@"PlotHostingTableViewCell" owner:nil];
		cell.plotController = controller;
		return cell;
	}
	
	return nil;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
	return [item requiredHeight];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
#if ! PROFILER_PREVIEW_EXTENSION
	return [item canReceiveFocus];
#else
	return NO;
#endif
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self plotControllerDidRemoveHighlight:nil];
	
	id<DTXPlotController> plotController = [_hostingOutlineView itemAtRow:_hostingOutlineView.selectedRow];
	_currentlySelectedPlotController = plotController;
	
	if(plotController == nil)
	{
		return;
	}
	
	[self.delegate managedPlotControllerGroup:self didSelectPlotController:plotController];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
	//Tell the system to precache the whole outline area.
	_hostingOutlineView.preparedContentRect = _hostingOutlineView.bounds;
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
	//Tell the system to precache the whole outline area.
	_hostingOutlineView.preparedContentRect = _hostingOutlineView.bounds;
}

@end
