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

#import "MacAddressFormatter.h"

@implementation MacAddressFormatter

- (BOOL) getObjectValue:(id*)obj forString:(NSString*)string errorDescription:(NSString**)error {
  *obj = string;
  return(YES);
}

- (NSString *)stringForObjectValue:(id)anObject {
  if([anObject isKindOfClass:[NSString class]]) {
    return(anObject);
  } else {
    return(nil);
  }
}

- (BOOL) isPartialStringValid:(NSString*)partialString newEditingString:(NSString**)newString errorDescription:(NSString**)error {
  
  NSRange foundRange;
  NSCharacterSet *disallowedCharacters = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789:abcdefABCDEF"] invertedSet];
  foundRange = [partialString rangeOfCharacterFromSet:disallowedCharacters];
  if(foundRange.location != NSNotFound) {
    *error = @"MAC Adress contains invalid characters";
    NSBeep();
    return NO;
  }
  
  if([partialString length] > 17) {
    *error = @"MAC Adress is too long.";
    NSBeep();
    return(NO);
  }

  *newString = partialString; 
  return YES;
}

@end