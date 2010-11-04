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

#import "AirPortClownAppDelegate.h"

// This Framework will allow us to run things with superuser privileges
// We need superuser privileges for "ifconfig" and possibly "airport"
#import <Security/Security.h>

// This is our reference to the authorization object
// We will need it later to store our superuser authorization session in it
AuthorizationRef authorization;

// Here we will store the MAC address that the user requested and use
// the value to determine whether it actually changed successfully or not
NSString *lastRequestedMAC;

// We need to find out later whether the separate Thread has finished loading the vendor Table
BOOL vendorsLoaded = NO;

@implementation AirPortClownAppDelegate

// These variables hold the objects in our GUI
@synthesize window, drawer, prefWindow;               // Windows and their Drawers
@synthesize vendorController;                         // Other Controllers
@synthesize addressLabel, statusLabel;                // Labels (i.e. TextFields not intended for edit)
@synthesize addressField, vendorSearch;               // TextFields and SearchFields
@synthesize interfaceBox;
@synthesize applyButton, randomButton, vendorButton;  // Buttons
@synthesize randomSlider, activityIndicator;          // Other fancy GUI items

/****************************************************************
 * Beginning here we do what it takes to bootstrap AirPortClown *
 ****************************************************************/

/*
 * Let the fun begin. This is the first method which is called when
 * AirPortClown is started. It bootstraps the Application, so to speak.
 */
- (void) applicationDidFinishLaunching:(NSNotification *)aNotification {
  [self log:@"AirPortClown in the house"];

  // Initiating the Authorization Reference. Don't ask, it just needs to be done once :)
  [self log:@"Initiating Authorization Reference"];
  OSStatus status = AuthorizationCreate (NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorization);
  
  // Just making sure things worked out so far.
  if (status != errAuthorizationSuccess) {
    [self log:@"Oops, could not initiate the authorization reference"];
  }
  
  // Loading all available interfaces and populating the combo box in the
  // preferences pane with them.
  NSArray *interfaces = [self getInterfaces];
  [interfaceBox addItemWithTitle:@"(Auto)"];
  [interfaceBox addItemsWithTitles:interfaces];

  // Setting the default application preferences
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  [dictionary setObject:@"(Auto)" forKey:@"Interface"];
  [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:dictionary];
  
  
  
  
  
  // At first we would like to show the current MAC address to the user ASAP.
  [self updateCurrentMAC:nil];
  
  // However, we would like to keep the current address updated every second.
  // So we start a Timer here that will take care of that, quite independently.
  // NOTE: This functionality is currently disabled as it is unprobable that the
  // end user changes his address manually while AirPortClown is still running.
  // [self log:@"Starting Timer for updating the current MAC address"];
  // [NSTimer scheduledTimerWithTimeInterval:(1) target:self  selector:@selector(updateCurrentMAC:) userInfo:nil repeats:YES];

  // For convenience, we fill in a random MAC address into the TextField.
  // The user can choose whether he wants this one or not.
  [self randomizeMAC:nil];
  
  // When the main window is closed, we would like to quit the application.
  // Otherwise, the window will be gone but the Application is still alive.
  // So we register here for the window telling us that it is about to be closed.
  // And whenever it tells us that it's going to close, we'll simply exit AirPortClown.
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:window];

  // Ensuring that the preferences window doesn't show nonesense. So we load the
  // values each time the preferences window get's the focus
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesOpened:) name:NSWindowDidBecomeMainNotification object:prefWindow];

  // We have quite a big list of MAC-prefixes and the corresponding vendor.
  // If we would load it synchronously, it would block our application for some seconds.
  // That's why we run a separate Thread now that will handle populating the Table in the Drawer.
  [self log:@"Starting Thread for loading the vendor list"];
  [NSThread detachNewThreadSelector:@selector(loadVendors:) toTarget:self withObject:nil];
}

/* This method gets evoked as separate Thread and takes care of loading the vendors from
 * the vendors.plist file and telling the VendorArrayController to fill it's Table with them.
 */
- (void) loadVendors:(id)sender {
  // This AutoreleasePool is mandatory for every Thread. Basically, it prevents
  // the code between here and "[pool drain]" to blow your memory into pieces somehow.
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  // First, we load the vendors from the file into a NSDictionary object
  NSString *vendorsDBPath = [[NSBundle mainBundle] pathForResource:@"vendors" ofType:@"plist"];
  [self log:@"Thread: Loading the vendor file into an NSDictionary"];
  NSDictionary *vendorsDB = [[NSDictionary alloc] initWithContentsOfFile:vendorsDBPath];
  // Then we instruct the VendorArrayController (a child of NSArrayController) to deal with it.
  [self log:@"Thread: Asking the VendorArrayController to populate the Table"];
  // You can ignore the compiler warning for this following line. It *will* respond to "populate" :)
  [vendorController populate:vendorsDB];
  // We have no way of finding out whether the user clicked on a vendor in the Table.
  // So we register here to the VendorArrayController and ask him to be so kind to tell us
  // whenever the user has clicked in the Table. That will evoke "observeValueForKeyPath".
  [self log:@"Thread: Registering the Observer for Table selections"];
  [vendorController addObserver:self forKeyPath: @"selectionIndex" options:NSKeyValueObservingOptionNew context:NULL];
  // Let us inform the rest of the Application that we're done loading the vendors file
  // via this Thread. In other words, it is now safe to open the Drawer.
  vendorsLoaded = YES;
  // "Leaving" the AutoreleasePool 
  [self log:@"Thread: Closing the AutoreleasePool of the Thread"];
  [pool drain];
}

/*************************************************
 * Here starts the big brain of this application *
 *************************************************/

/*
 * Major action. This method is called if the user hits the "Apply"-Button.
 */
- (IBAction) applyAddress:(id)sender {
  // Start the spinning thing
  [self.activityIndicator startAnimation:self];
  
  NSString *requestedMAC = [addressField stringValue];
  // Before continuing, we make sure the address has a correct format
  [addressField setStringValue:[self sanitizeMACAddress:requestedMAC]];
  if ([requestedMAC length] != 17) {
    // Apparently the user doesn't know what a MAC address is
    [self log:@"The entered MAC address is invalid"];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:@"Invalid MAC address"];
    [alert setInformativeText:@"Please enter the MAC address either in the format aabbccddeeff or aa:bb:cc:dd:ee:ff."];
    [alert setAlertStyle:NSWarningAlertStyle];
    [self log:@"Showing warning message that the address is invalid"];
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
    // Don't do anything at all
    [self.activityIndicator stopAnimation:self];
    return;
  }
  
  // At this point we have a valid MAC address.
  // Save the requested address to check later whether it was successful
  [self log:@"Saving copy of currently requested MAC to double-check later"];
  lastRequestedMAC = [[addressField stringValue] copy];

  // Now, we get the current status of the AirPort
  [self log:@"Am going to request the current AirPort status"];
  NSDictionary *airportStatus = [self getAirPortStatus];
  
  // Check if AirPort is currently turned off
  if ([airportStatus objectForKey:@"POWER"]) {
    // Yes, it is turned off! Let's give a message to the user.
    [self log:@"The AirPort is turned off"];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:@"Your AirPort is turned off"];
    [alert setInformativeText:@"For this to work you will need to turn on your AirPort."];
    [alert setAlertStyle:NSWarningAlertStyle];
    [self log:@"Showing warning message that the AirPort is turned off"];
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
    [self.activityIndicator stopAnimation:self];
    // Don't do anything at all
    return;
  }
  
  // Check if AirPort is currently associated with a Network
  if ([airportStatus objectForKey:@"NOISE_CTL_AGR"]) {
    // Yes, we have a noise ratio, which means that we are connected to something.
    [self log:@"Detected that the AirPort is associated to a network"];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:@"Your AirPort is connected to a WLAN"];
    [alert setInformativeText:@"Please disassociate from all wireless networks first."];
    [alert setAlertStyle:NSWarningAlertStyle];
    [self log:@"Showing warning message that the AirPort is associated"];
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
    [self.activityIndicator stopAnimation:self];
    // Don't do anything at all
    return;
  }
  
  // This is what AirPortClown is all about, a simple ifconfig command ;)
  // The superuser command execution is so "secure", that it will only accept character arrays
  // and not strings represented by pointers. So we define the command as character arrays now.
  //[self log:@"Putting together the ifconfig command parameters"];
  char *command = "/sbin/ifconfig";
  // There is a compiler warning for the next line that we're loosing our pointer by this. Of course we do!
  char *arguments[] = {[[self currentInterface] UTF8String], "ether", [[addressField stringValue] UTF8String]};  

  // Do the magic. 
  //[self log:[[NSString alloc] initWithFormat:@"Requesting privileges for <ifconfig en1 ether %@>", [addressField stringValue]]];
  OSStatus status = AuthorizationExecuteWithPrivileges(authorization, command, kAuthorizationFlagDefaults, arguments, nil);
  
  /*
  * Making sure that we *can* do magic :) Even though we're not going to check
  * for *all* errors that Authorization.h offers:
  *
  * errAuthorizationSuccess                = 0        Success.
  * errAuthorizationInvalidSet             = -60001   The authorization rights are invalid.
  * errAuthorizationInvalidRef             = -60002   The authorization reference is invalid.
  * errAuthorizationInvalidTag             = -60003   The authorization tag is invalid.
  * errAuthorizationInvalidPointer         = -60004   The returned authorization is invalid.
  * errAuthorizationDenied                 = -60005   The authorization was denied.
  * errAuthorizationCanceled               = -60006   The authorization was cancelled by the user.
  * errAuthorizationInteractionNotAllowed  = -60007   The authorization was denied since no user interaction was possible.
  * errAuthorizationInternal               = -60008   Unable to obtain authorization for this operation.
  * errAuthorizationExternalizeNotAllowed  = -60009   The authorization is not allowed to be converted to an external format.
  * errAuthorizationInternalizeNotAllowed  = -60010   The authorization is not allowed to be created from an external format.
  * errAuthorizationInvalidFlags           = -60011   The provided option flag(s) are invalid for this authorization operation.
  * errAuthorizationToolExecuteFailure     = -60031   The specified program could not be executed.
  * errAuthorizationToolEnvironmentError   = -60032   An invalid status was returned during execution of a privileged tool.
  * errAuthorizationBadAddress             = -60033   The requested socket address is invalid (must be 0-1023 inclusive).
  */
  switch (status) {
    case errAuthorizationSuccess:
      // Success! Nothing to see here, move along...
      [self log:@"Authorization granted"];
    break;
    case errAuthorizationToolEnvironmentError:
      case -2129264641:
        // To be honest, I can't explain these two errors. All I know is that they happen each time
        // I am in X-Code and have selected "Debug" as Target. Unfortunately this also happens
        // in Release mode about 1 out of 10 times. If you're a developer in X-Code, I hope that you
        // read the logs, because then you would see that you need to switch to "Release" mode.
        [self log:@"ifconfig did not accept the MAC address or was not executed with superuser privileges. Either you cancelled the authentication or you are in X-Code and did not choose the Target <Release> or the MAC address is simply a bad choice."];
        [self.activityIndicator stopAnimation:self];
        //return;
      break;
    break;      
    default:
      // It was not the user who provoked this error? Hm. Lets have a look at it.
      [self log:[[NSString alloc] initWithFormat:@"The authentication request failed. Reason: %d", status]];
      [self.activityIndicator stopAnimation:self];
      return;
    break;
  }

  // We have no chance of determining whe the ifconfig command finished
  // So we just wait half a second (should be enough for ifconfig to work out) and then test whether it worked or not in "verifyChangedMAC".
  //[self log:@"Starting Timer to verify in half a second whether ifconfig changed the address successfully or not"];
  [NSTimer scheduledTimerWithTimeInterval:(0.5) target:self  selector:@selector(verifyChangedMAC:) userInfo:nil repeats:NO];

  // Stop the spinning thing
  [self.activityIndicator stopAnimation:self];
}


/* This method gets called shortly after the MAC address was changed.
 * We would like to check here whether the change was successful or not.
 */
- (void) verifyChangedMAC:(id)sender {
  [self log:@"Verifying MAC address change"];
  NSString *actual = [self getCurrentMAC];
  // Everything alright, the current MAC has changed to what the user wanted. Get outta here.
  if ([actual isEqualToString:lastRequestedMAC]) {
    [self log:@"Success"];
    [self updateCurrentMAC:nil];
    return;
  }
  
  // Hey, your MAC should have changed, but it didn't.
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert addButtonWithTitle:@"OK"];
  [alert setMessageText:@"This MAC address didn't work out"];
  [alert setInformativeText:@"Sorry, your AirPort doesn't accept this address. Please try another vendor prefix."];
  [alert setAlertStyle:NSWarningAlertStyle];
  [self log:@"Failure, show message that the address didn't work"];
  [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

/**********************************************
 * Following here we have some helper methods *
 **********************************************/

/* This method runs "ifconfig" without superuser privileges to determine 
 * the current MAC address. It returns it as NSString.
 */
- (NSString*) getCurrentMAC {
  // Getting the Task bootstrapped
  NSTask *ifconfig = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  NSFileHandle *file = [pipe fileHandleForReading];
  
  // Configuring the ifconfig command
  [ifconfig setLaunchPath: @"/sbin/ifconfig"];
  [ifconfig setArguments: [NSArray arrayWithObjects: [self currentInterface], nil]];
  [ifconfig setStandardOutput: pipe];
  // Starting the Task
  [ifconfig launch];
  
  // Reading the result from the stdout
  NSData *data = [file readDataToEndOfFile];
  NSString *cmdResult = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  // Searching for the MAC address in the result
  NSString *currentMAC = [[[[cmdResult componentsSeparatedByString:@"ether "] lastObject] componentsSeparatedByString:@" "] objectAtIndex:0] ; 
  return currentMAC;
}

/* This method runs "airport" without superuser privileges to receive 
 * the status information about the AirPort. Such as whether it's turned on or not.
 */
- (NSDictionary*) getAirPortStatus {
  // This command follows the same structure as in "getCurrentMAC".
  // I refer you to the comments in that method instead of copying them over here.
  NSTask *airportInfo = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  NSFileHandle *file = [pipe fileHandleForReading];
  
  [airportInfo setLaunchPath:@"/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport"];
  [airportInfo setArguments:[NSArray arrayWithObjects: @"--getinfo", @"--xml", nil]];
  [airportInfo setStandardOutput:pipe];
  [airportInfo launch];
  
  NSData *data = [file readDataToEndOfFile];
  // The "airport" command is so kind to provide us with a plist result, that can be turned into an NSDictionary.
  NSDictionary *airportStatus = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListMutableContainers format:nil errorDescription:nil];
  return airportStatus;
}

- (NSString*) currentInterface {
  NSDictionary *prefsValues = [[NSUserDefaultsController sharedUserDefaultsController] values];
  NSString *chosenInterface = [prefsValues valueForKey:@"Interface"];
  if ([chosenInterface isEqualToString:@"(Auto)"]) {
    return @"en1";
  } else {
    return chosenInterface;
  }
}

/* 
 * 
 */
- (NSArray*) getInterfaces {
	// This command follows the same structure as in "getCurrentMAC".
	// I refer you to the comments in that method instead of copying them over here.
	NSTask *ifconfig = [[NSTask alloc] init];
	NSPipe *pipe = [NSPipe pipe];
	NSFileHandle *file = [pipe fileHandleForReading];
	
	[ifconfig setLaunchPath: @"/sbin/ifconfig"];
	[ifconfig setArguments: [NSArray arrayWithObjects: @"-lu", nil]];    // -lu will show all Interfaces that are UP
	[ifconfig setStandardOutput: pipe];
	[ifconfig launch];
	
	NSData *data = [file readDataToEndOfFile];
	NSString *cmdResult = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  // Removing some unwanted interfaces and the newline character
  cmdResult = [cmdResult stringByReplacingOccurrencesOfString:@"lo0 " withString:@""];
  cmdResult = [cmdResult stringByReplacingOccurrencesOfString:@"lo1 " withString:@""];
  cmdResult = [cmdResult stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	NSArray *interfaces = [cmdResult componentsSeparatedByString:@" "]; 
	return interfaces;
}

/* Some MAC address roulette.
 * Returns a random, full MAC address, separated by colons.
 */
- (NSString*) generateRandomMAC {
  // We will perform this with an Array that holds the HEX values
  NSMutableArray *components = [[[NSMutableArray alloc] init] autorelease];
  // Six times we will add something to the Array
  for (NSInteger i = 0; i < 6; i++) {
    // Each time we add two random HEX values combined in one NSString. E.g. "AF" or "5C"
    NSString *component = [[[NSString alloc] initWithFormat:@"%1X%1X", arc4random() % 15, arc4random() % 15] autorelease];
    // Please in lower case
    [components addObject:[component lowercaseString]];
  }
  // Put it all together by joining the six components with colons
  return [components componentsJoinedByString:@":"];
}

/* This method takes some junk string as input and tries to format it as MAC address
 * separated by colons. Note that it won't check for valid characters, it will only
 * deal with the colons. The character validity is guaranteed via the MacAddressFormatter.
 */
- (NSString*) sanitizeMACAddress:(NSString*)address {
  // Stripping all existing colons
  address = [address stringByReplacingOccurrencesOfString:@":" withString:@""];
  // Adding fresh colons
  NSMutableString* formatted = [[address mutableCopy] autorelease];
  if ([formatted length] > 10) [formatted insertString:@":" atIndex:10];
  if ([formatted length] > 8) [formatted insertString:@":" atIndex:8];
  if ([formatted length] > 6) [formatted insertString:@":" atIndex:6];
  if ([formatted length] > 4) [formatted insertString:@":" atIndex:4];
  if ([formatted length] > 2) [formatted insertString:@":" atIndex:2];
  return formatted;
}

/*******************************************
 * These are our Interface Builder Actions *
 *******************************************/

- (void) preferencesOpened:(id)sender {
  NSLog(@"Applying prefereces stored in the system to the preferences GUI");
  NSDictionary *prefsValues = [[NSUserDefaultsController sharedUserDefaultsController] values];
  NSString *prefInterface = [prefsValues valueForKey:@"Interface"];
  [interfaceBox selectItemWithTitle:prefInterface];
}

- (IBAction) savePreferences:(id)sender {
  NSLog(@"Saving Preferences");
  id currentPrefsValues = [[NSUserDefaultsController sharedUserDefaultsController] values];
  // Current Interface
	[currentPrefsValues setValue:[[interfaceBox selectedItem] title] forKey:@"Interface"];
  // "Updating" the rest of the application
  [self updateCurrentMAC:nil];
}


/* This method updates the text label that shows the
 * current MAC address.
 */
- (IBAction) updateCurrentMAC:(id)sender {
  [addressLabel setStringValue:[self getCurrentMAC]];
}

/* This method populates the MAC address TextField  
 * with a random MAC address.
 */
- (IBAction) randomizeMAC:(id)sender {
  [addressField setStringValue:[self generateRandomMAC]];
}

/* This method updates the prefix of the MAC address
 * in the TextField with a given prefix.
 */
- (void) applyVendorID:(NSString*)vendorID {
  [addressField setStringValue:vendorID];
  [self randomizeDeviceID:self];
}

/* This method changes the last six HEX values of the
 * MAC address shown in the TextField
 */
- (IBAction) randomizeDeviceID:(id)sender {
  // First we sanitize the colons of the currently entered address
  [addressField setStringValue:[self sanitizeMACAddress:[addressField stringValue]]];
  // If there is none, or if it's too short, stop here.
  if ([[addressField stringValue] length] < 8) return;
  // Preserving the first six values
  NSString *currentVendorID = [[addressField stringValue] substringToIndex:8];
  // Taking six fresh, random HEX values 
  NSString *randomDeviceID = [[self generateRandomMAC] substringToIndex:8];
  // Merging the current prefix with the random suffix
  [addressField setStringValue:[currentVendorID stringByAppendingFormat:@":%@",randomDeviceID]];
}

/* This is pretty basic, I guess. When the "Vendors"-button is clicked,
 * the Drawer opens or closes.
 */
- (IBAction) toggleDrawer:(id)sender {
  if (!vendorsLoaded) {
    // Well, the vendor Table is not done yet filling in all the vendors
    // which were loaded from file. We will actually crash the application
    // if the Drawer is opened while the population takes place.
    // We will indicate activity and run a Timer to try again in one second.
    [self log:@"Preventing opening of Drawer because vendor list not ready yet"];
    [self log:@"Starting Timer to try again in one second"];
    [self.activityIndicator startAnimation:self];
    [NSTimer scheduledTimerWithTimeInterval:(1) target:self  selector:@selector(toggleDrawer:) userInfo:nil repeats:NO];
    return;
  }
  // Alright, we can toggle the Drawer now. Stop the activity indicator.
  [self.activityIndicator stopAnimation:self];
  if ([drawer state] == NSDrawerClosedState) {
    // So the Drawer is closed. Let's open it and right after
    // that give focus to the SearchField which is about to appear.
    [self log:@"Opening Drawer"];
    [drawer toggle:self];
    [window makeFirstResponder:vendorSearch];
  } else {
    [self log:@"Closing Drawer"];
    // The Drawer is wide open. Put the focus back to the
    // main MAC address TextField and close the Drawer.
    [window makeFirstResponder:addressField];
    [drawer toggle:self];
  }
}

/* Opening the website of AirPortClown, because I have no
 * real Help file yet. Would you like to create one for me?
 */
- (IBAction) showHelp:(id)sender {
  NSURL *url = [ [ NSURL alloc ] initWithString: @"http://blog.funkensturm.de/2010/01/22/airportclown-simple-mac-address-spoof-for-snow-leopard" ];
  [[NSWorkspace sharedWorkspace] openURL:url]; 
}

/* Just so that an end-user can enjoy the credits and
 * the MIT license, we pop it up here as an NSAlert.
 */
- (IBAction) showLicense:(id)sender {
  NSString *licensePath = [[NSBundle mainBundle] pathForResource:@"MIT-LICENSE" ofType:@""];
  NSString *license = [[NSString alloc] initWithContentsOfFile:licensePath];
  // Spill out the license in a messagebox
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert addButtonWithTitle:@"OK"];
  [alert setMessageText:@"License"];
  [alert setInformativeText:license];
  [alert setAlertStyle:NSInformationalAlertStyle];
  [self log:@"Presenting license"];
  [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

/*************************************
 * Lastly, some minor helper methods *
 *************************************/

/* If we would not have this method, NSAlert boxes would
 * stay in your face forever. Also, here we can check whether
 * the user clicked "OK" or "Cancel" in the future when needed.
 */
- (void) alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
}

/* This hook gets called if the user clicks on the Table
 * that holds the vendor list. It updates the TextField accordingly.
 */
- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
  // Getting the vendor entry object of the selected row
  NSArray *selectedVendor = [[object selectedObjects] lastObject];
  // Applying the vendor MAC prefix to the address in the TextField
  [self applyVendorID:[self sanitizeMACAddress:[selectedVendor valueForKey:@"mac"]]];
}

/*
- (void) prefWindowWillClose:(id)sender {
  [prefWindow ...];
}
*/

/* A wrapper so that we can guide the internal debugging log
 * message somewhere. Currently, it all goes out to NSLog.
 */
- (void) log:(NSString*)message {
  // I'm sorry upfront for spamming your Console.
  NSLog(message);
}

/******************************************************
 * The rest is purely experimental and documentary :) *
 ******************************************************/

/*
 * It would be nice, if there was a command to turn the AirPort on.
 * Unfortunately "ifconfig en1 ether up" only works if the command
 * "ifconfig en1 ether down" was used to turn it off. That means,
 * if the user clicked "Turn AirPort Off" we cannot get it up again :(
 * I would be happy for solutions.
 */
/*
- (void) turnAirPortOn {
  char *command = "/sbin/ifconfig";
  char *arguments[] = {"en1", "ether", "up"};  
  OSStatus status = AuthorizationExecuteWithPrivileges(authorization, command, kAuthorizationFlagDefaults, arguments, NULL);
}
*/

/* We can automatically disassociate from all WLANs via "sudo airport --disassociate"
 * For some strange reason, the "airport" command will not be executed with superuser
 * privileges. You can try it if you like to, but I couldn't get it running so far.
 */
/*
 - (BOOL) disassociateFromAllNetworks {
 [self log:@"Disassociating from all networks."];
 
 // For this to work we need to call "airport --disassociate" with superuser privileges
 char *command = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport";
 char *arguments[] = {"--disassociate"};  
 FILE *commandOutput = NULL;
 
 // This asks the user for his credentials and runs the command
 OSStatus status = AuthorizationExecuteWithPrivileges(authorization, command, kAuthorizationFlagDefaults, arguments, &commandOutput);
 
 // By reading the airport's command output we will see "need root-privileges" if it didn't work out.
 
 #define READ_BUFFER_SIZE 1024
 char readBuffer[READ_BUFFER_SIZE];
 NSMutableString *processOutputString = [NSMutableString string];
 size_t charsRead;
 while ((charsRead = fread(readBuffer, 1, READ_BUFFER_SIZE, commandOutput)) != 0) {
   NSString *bufferString = [[NSString alloc] initWithBytes:readBuffer length:charsRead encoding:NSUTF8StringEncoding];
   [processOutputString appendString:bufferString];
   [bufferString release];
 }
 fclose(commandOutput);
 return TRUE;
}
*/

@end
