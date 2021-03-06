//
//  SFViewController.m
//  SFBLEDeviceExample
//
//  Created by Thomas Billicsich on 2014-04-07.
//  Copyright (c) 2014 Thomas Billicsich. All rights reserved.

#import "SFViewController.h"



@interface SFViewController ()
@property (nonatomic) SFBLEDeviceFinder* finder;
@property (nonatomic) SFBLEDevice* device;
@end




NSString* const BLEServiceHeartRate         = @"180D";
NSString* const BLECharHeartRateMeasurement = @"2A37";




@implementation SFViewController


- (void)viewDidLoad
{
  [super viewDidLoad];
  
  NSDictionary* HRServsAndCharacs = @{
                                      [CBUUID UUIDWithString:BLEServiceHeartRate] : @[[CBUUID UUIDWithString:BLECharHeartRateMeasurement]]
                                      };
  
  self.finder = [SFBLEDeviceFinder finderForDevicesWithServicesAndCharacteristics:HRServsAndCharacs advertising:@[[CBUUID UUIDWithString:BLEServiceHeartRate]]];
  self.finder.delegate = self;
}


- (void)setDevice:(SFBLEDevice*)device
{
  if (_device == device)
    return;
  
  [_device unlink];
  _device.delegate = nil;
  
  _device = device;
  
  _device.delegate = self;
}




#pragma mark -
#pragma mark User Interaction


- (IBAction)startFind:(id)sender
{
  self.device = nil;
  [self.finder findDevices:3.5];
  self.stateLabel.text = @"Finding…";
}


- (IBAction)link:(id)sender
{
  [self.device link];
  self.stateLabel.text = @"Linking…";
}


- (IBAction)unlink:(id)sender
{
  [self.device unlink];
}




#pragma mark -
#pragma mark SFBLEDeviceFinderDelegate


- (void)finderFoundDevices:(NSArray*)bleDevices error:(NSError*)error
{
  if (bleDevices.count) {
    self.stateLabel.text = @"Found";
    self.device = bleDevices.firstObject;
  }
  else {
    self.stateLabel.text = @"Not found";
  }
}


- (void)finderStoppedFindWithError:(NSError*)error
{

}


- (void)bluetoothNotAvailable
{

}


- (void)bluetoothAvailableAgain
{

}




#pragma mark -
#pragma mark SFBLEDeviceDelegate


- (void)deviceLinkedSuccessfully:(SFBLEDevice*)device
{
  NSAssert(self.device == device, @"We should not connect to any other device, than the one in the ivar");
  
  [device subscribeToCharacteristic:[CBUUID UUIDWithString:BLECharHeartRateMeasurement]];
  self.stateLabel.text = @"Linked";
}


- (void)device:(SFBLEDevice*)SFBLEDevice failedToLink:(NSError*)error
{
  self.stateLabel.text = @"Link failed";
}


- (void)device:(SFBLEDevice*)SFBLEDevice unlinked:(NSError*)error
{
  self.stateLabel.text = @"Unlinked";
}


- (void)device:(SFBLEDevice*)device receivedData:(NSData*)data fromCharacteristic:(CBUUID*)uuid
{
  UInt8 heartRate;
  [data getBytes:&heartRate range:NSMakeRange(1, 1)];
  self.hrLabel.text = @(heartRate).stringValue;
}


@end
