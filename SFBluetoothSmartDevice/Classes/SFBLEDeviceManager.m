//
//  SFBLEDeviceManager.m
//  SFBluetoothLowEnergyDevice
//
//  Created by Thomas Billicsich on 2014-01-13.
//  Copyright (c) 2014 Thomas Billicsich. All rights reserved.


#import "SFBLEDeviceManager.h"
#import "SpacemanBlocks.h"
#import "Log4Cocoa.h"

#import "SFBLEDevice.h"
#import "SFBLECentralManagerDelegate.h"


#define DISPATCH_ON_MAIN_QUEUE(statement) do { \
dispatch_async(dispatch_get_main_queue(), ^{ \
statement; \
}); } while(0)
#define DISPATCH_ON_BLE_QUEUE(statement) do { \
dispatch_async(SFBLEDeviceManager.bleQueue, ^{ \
statement; \
}); } while(0)




@interface SFBLEDeviceManager () {
  __block SMDelayedBlockHandle _scanTimeoutBlock;
}

@property (nonatomic) NSMutableDictionary* discoveredDevices;
@property (nonatomic, copy) NSUUID* identifierToScanFor;
@property (atomic) BOOL shouldScan;
@property (nonatomic) NSTimeInterval scanTimeout;

@property (readwrite) NSDictionary* servicesAndCharacteristics;
@property (nonatomic, copy) NSArray* advertisedServices;
@property (nonatomic) SFBLECentralManagerDelegate* centralDelegate;
@end




@implementation SFBLEDeviceManager

static dispatch_queue_t __bleQueue;
+ (void)initialize
{
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    __bleQueue = dispatch_queue_create("com.simpliflow_ble.queue", DISPATCH_QUEUE_SERIAL);
    [[L4Logger rootLogger] setLevel:[L4Level all]];
    if ([L4Logger rootLogger].allAppenders.count == 0) {
      [[L4Logger rootLogger] addAppender: [[L4ConsoleAppender alloc] initTarget:YES withLayout: [L4Layout simpleLayout]]];
    }
  });
}


+ (dispatch_queue_t)bleQueue
{
  return __bleQueue;
}


+ (NSError*)error:(SFBluetoothSmartError)errorCode
{
  NSString* description = nil;
  switch (errorCode) {
    case SFBluetoothSmartErrorNoBluetooth:
      description = @"Bluetooth not available";
      break;
    case SFBluetoothSmartErrorNoDeviceFound:
      description = @"No device found";
      break;
    case SFBluetoothSmartErrorSpecificDeviceNotFound:
      description = @"Specific device not found";
      break;
    case SFBluetoothSmartErrorProblemsInConnectionProcess:
      description = @"Problems in connection process";
      break;
    case SFBluetoothSmartErrorProblemsInDiscoveryProcess:
      description = @"Problems in discovery process";
      break;
    case SFBluetoothSmartErrorConnectionClosedByDevice:
      description = @"Connection closed by device";
      break;
    case SFBluetoothSmartErrorOtherCBError:
      description = @"Other CoreBluetooth error";
      break;
    case SFBluetoothSmartErrorUnknown:
      description = @"Unknown error";
      break;
      
    default:
      break;
  }
  
  return [NSError errorWithDomain:@"SFBluetoothSmartError"
                             code:errorCode
                         userInfo:@{
                                    NSLocalizedDescriptionKey:description
                                    }];
}


+ (instancetype)managerForDevicesWithServicesAndCharacteristics:(NSDictionary*)servicesAndCharacteristics advertising:(NSArray*)advertisedServices
{
  return [[SFBLEDeviceManager alloc] initWithServicesAndCharacteristics:servicesAndCharacteristics advertising:advertisedServices];
}
- (id)initWithServicesAndCharacteristics:(NSDictionary*)servicesAndCharacteristics advertising:(NSArray*)advertisedServices
{
  if (self = [super init]) {
    // Check
    //   * the keys of servicesAndCharacteristics
    //   * the elements within the arrays that are the values of servicesAndCharacteristics
    //   * the services that are expected to be advertised
    //  to be of the class CBUUID.
    NSArray* characteristics = [servicesAndCharacteristics.allValues valueForKeyPath:@"@unionOfArrays.self"];
    for (NSArray* shouldBeUUIDs in @[servicesAndCharacteristics.allKeys, characteristics, advertisedServices]) {
      for (id shouldBeUUID in servicesAndCharacteristics.allKeys) {
        if (![shouldBeUUID isKindOfClass:[CBUUID class]])
          return nil;
      }
    }
    // Check
    //   * if the characteristics are unique
    NSMutableArray* characteristicsCheck = [@[] mutableCopy];
    for (CBUUID* maybeUniqueUUID in characteristics) {
      if ([characteristicsCheck indexOfObject:maybeUniqueUUID] != NSNotFound) {
        return nil;
      }
      [characteristicsCheck addObject:maybeUniqueUUID];
    }
    
    self.advertisedServices = advertisedServices;
    self.servicesAndCharacteristics = servicesAndCharacteristics;
    
    _centralDelegate = [SFBLECentralManagerDelegate centralDelegateForDeviceManager:self withBLEQueue:SFBLEDeviceManager.bleQueue];
  }
  return self;
}




#pragma mark -
#pragma mark Scanning


- (void)scanFor:(NSUUID*)identifier timeout:(NSTimeInterval)timeout
{
  if (self.shouldScan)
    return;
  
  self.shouldScan = YES;
  DISPATCH_ON_BLE_QUEUE(
                        if (timeout > 0) {
                          self.scanTimeout = timeout;
                          [self startScanTimer];
                        }
                        self.identifierToScanFor = identifier;
                        self.discoveredDevices = [@{} mutableCopy];
                        [self.centralDelegate scanForPeripheralsAdvertising:self.advertisedServices];
  );
}


- (void)startScanTimer
{
  _scanTimeoutBlock = perform_block_after_delay(self.scanTimeout, SFBLEDeviceManager.bleQueue, ^{
    [self scanTimedOut];
  });
}


- (void)invalidateScanTimer
{
  if (_scanTimeoutBlock) {
    cancel_delayed_block(_scanTimeoutBlock);
    _scanTimeoutBlock = nil;
  }
}


- (void)scanTimedOut
{
  NSAssert(self.shouldScan, @"Raise condition");

  [self executeStoppingScanDuties];
  
  if (self.discoveredDevices.count == 0) {
    NSError* bleError = nil;
    if (self.identifierToScanFor) {
      log4Info(@"BLE-Manager: scan timed out. Specific device not found");
      bleError = [SFBLEDeviceManager error:SFBluetoothSmartErrorSpecificDeviceNotFound];
    }
    else {
      log4Info(@"BLE-Manager: scan timed out. No device found");
      bleError = [SFBLEDeviceManager error:SFBluetoothSmartErrorNoDeviceFound];
    }
    
    DISPATCH_ON_MAIN_QUEUE(self.shouldScan = NO; [self.delegate managerStoppedScanWithError:bleError]);
  }
  else {
    log4Info(@"BLE-Manager: scan timed out. Found %d device(s).", self.discoveredDevices.count);
    DISPATCH_ON_MAIN_QUEUE(self.shouldScan = NO; [self.delegate managerFoundDevices:self.discoveredDevices.allValues]);
  }
}


- (void)didDiscoverPeripheral:(CBPeripheral*)peripheral RSSI:(NSNumber*)RSSI;
{
  NSAssert(self.shouldScan, @"Peripheral discovered altough should not scan");
  if (!self.shouldScan)
    return;
  
  // An RSSI value of 127 is not valid, but it has been encountered regularly
  if (RSSI.integerValue == 127)
    return;
  
  if ([self.identifierToScanFor isEqual:peripheral.identifier]) {
    log4Debug(@"BLE-Manager: did discover suitable peripheral: %@", peripheral);
    [self executeStoppingScanDuties];
    
    SFBLEDevice* suitableDevice = [SFBLEDevice deviceWithPeripheral:peripheral centralDelegate:self.centralDelegate servicesAndCharacteristics:self.servicesAndCharacteristics];
    DISPATCH_ON_MAIN_QUEUE(self.shouldScan = NO; [self.delegate managerFoundDevices:@[suitableDevice]]);
  }
  else if (!self.identifierToScanFor) {
    if (![self.discoveredDevices.allKeys containsObject:peripheral.identifier]) {
      log4Info(@"BLE-Manager: new suitable peripheral %p (%@, %@). RSSI: %@", peripheral, peripheral.identifier, peripheral.name, RSSI);
      self.discoveredDevices[peripheral.identifier] = [SFBLEDevice deviceWithPeripheral:peripheral centralDelegate:self.centralDelegate servicesAndCharacteristics:self.servicesAndCharacteristics];
    }
    else {
//      log4Debug(@"BLE-Manager: rediscovered suitable peripheral %p. RSSI: %@", peripheral, RSSI);
    }
  }
  else {
    log4Debug(@"BLE-Manager: did discover unsuitable peripheral: %@", peripheral);
  }
}


- (void)stopScan
{
  self.shouldScan = NO;
  DISPATCH_ON_BLE_QUEUE([self executeStoppingScanDuties]);
}
- (void)executeStoppingScanDuties
{
  [self.centralDelegate stopScan];
  [self invalidateScanTimer];
}




#pragma mark -
#pragma mark Bluetooth State


- (void)bluetoothNotAvailable
{
  if ([self.delegate respondsToSelector:@selector(bluetoothNotAvailable)]) {
    [self.delegate bluetoothNotAvailable];
  }
}


- (void)bluetoothAvailableAgain
{
  if ([self.delegate respondsToSelector:@selector(bluetoothAvailableAgain)]) {
    [self.delegate bluetoothAvailableAgain];
  }
}


@end


#undef DISPATCH_ON_MAIN_QUEUE
#undef DISPATCH_ON_BLE_QUEUE