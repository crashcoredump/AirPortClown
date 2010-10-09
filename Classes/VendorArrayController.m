/* 
 * AirPortClown is released under
 * The MIT License
 * 
 * Copyright (c) 2010 funkensturm.com
 *
 * Inspired by the Automator script of Ryan:
 * http://iamthekiller.net/2009/12/spoof-your-mac-address-with-services
 *
 * Improved with ideas of JosteinB:
 * http://josteinb.com/2009/10/spoofing-your-mac-address-in-snow-leopard
 *
 * And the helpful comments of our visitors:
 * http://blog.funkensturm.de/2010/01/22/airportclown-simple-mac-address-spoof-for-snow-leopard
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "VendorArrayController.h"

#import <Foundation/NSKeyValueObserving.h>

@implementation VendorArrayController

- (void)search:(id)sender {
  [self setSearchString:[sender stringValue]];
  [self rearrangeObjects];    
}

- (void) populate:(NSDictionary*)db {
  for (NSString *address in db) {
    id newVendor = [super newObject];
    [newVendor setValue:[db valueForKey:address] forKey:@"vendor"];
    [newVendor setValue:address forKey:@"mac"];
    [self addObject:newVendor];
  }
}

- (NSArray*) arrangeObjects:(NSArray*)objects {
	
  if ((searchString == nil) || ([searchString isEqualToString:@""])) {
		newObject = nil;
		return [super arrangeObjects:objects];   
	}

  NSMutableArray *matchedObjects = [NSMutableArray arrayWithCapacity:[objects count]];
  NSString *lowerSearch = [searchString lowercaseString];
  
	NSEnumerator *oEnum = [objects objectEnumerator];
  id item;
  while (item = [oEnum nextObject]) {
		if (item == newObject) {
      [matchedObjects addObject:item];
			newObject = nil;
		} else {
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
			NSString *lowerName = [[item valueForKeyPath:@"vendor"] lowercaseString];
			if ([lowerName rangeOfString:lowerSearch].location != NSNotFound) {
				[matchedObjects addObject:item];
			} else {
				lowerName = [[item valueForKeyPath:@"mac"] lowercaseString];
				if ([lowerName rangeOfString:lowerSearch].location != NSNotFound) {
					[matchedObjects addObject:item];
				}
			}
			[pool release];
		}
  }
  return [super arrangeObjects:matchedObjects];
}

- (void) dealloc {
  [self setSearchString: nil];    
  [super dealloc];
}

- (NSString*) searchString {
	return searchString;
}

- (void) setSearchString:(NSString*)newSearchString {
  if (searchString != newSearchString) {
    [searchString autorelease];
    searchString = [newSearchString copy];
  }
}

@end
