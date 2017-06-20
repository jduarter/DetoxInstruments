//
//  DTXLineLayer.m
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 19/06/2017.
//  Copyright © 2017 Wix. All rights reserved.
//

#import "DTXLineLayer.h"

@implementation DTXLineLayer

-(instancetype)initWithFrame:(CGRect)newFrame
{
	self = [super initWithFrame:newFrame];
	
	if(self)
	{
		self.needsDisplayOnBoundsChange = NO;
	}
	
	return self;
}

-(void)renderAsVectorInContext:(nonnull CGContextRef)context
{
	if ( self.hidden ) {
		return;
	}
	
	CGContextSetLineWidth(context, 2.0);
	
	CGContextSetStrokeColorWithColor(context, _lineColor);
	CGContextSetFillColorWithColor(context, _lineColor);
	CGContextMoveToPoint(context, self.bounds.size.width / 2.0, 0);    // This sets up the start point
	CGContextAddLineToPoint(context, self.bounds.size.width / 2.0, self.bounds.size.height);
	CGContextStrokePath(context);
	
	CGContextFillEllipseInRect(context, CGRectMake(-3.5 + self.bounds.size.width / 2.0, -3.5 + _dataPoint, 7, 7));
}

- (void)setDataPoint:(CGFloat)dataPoint
{
	_dataPoint = dataPoint;
	
	[self setNeedsDisplay];
}

- (void)setLineColor:(CGColorRef)lineColor
{
	if(_lineColor != nil)
	{
		CGColorRelease(_lineColor);
	}
	_lineColor = CGColorRetain(lineColor);
	
	[self setNeedsDisplay];
}

@end
