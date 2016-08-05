//
//  ViewController.m
//  Conflict Notification
//
//  Created by KUMATA Tomokatsu on 31/07/2016.
//  Copyright © 2016 KUMATA Tomokatsu. All rights reserved.
//

#import "ViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface ViewController () <CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralManagerDelegate>
{
    BOOL isFirstImmediate;
    BOOL isFirstNear;
    BOOL isFirstFar;
    int isBeforePosition;
    float beforeRSSI;
    //BOOL isNearing;
    int includeTimes;
    NSString *rangeMessage;
    NSString *myUUID;
}

@property (nonatomic) CLLocationManager *locationManager;
@property (nonatomic) NSUUID *proximityUUID;
@property (nonatomic) NSUUID *sendUUID;
@property (nonatomic) CLBeaconRegion *beaconRegion;
@property (nonatomic) CBCentralManager *centralManager;
@property (nonatomic) CBPeripheralManager *peripheralManager;
@property (nonatomic) NSDictionary *beaconPeripheralData;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    isFirstImmediate = false;
    isFirstNear = false;
    isFirstFar = false;
    includeTimes = 0;
    beforeRSSI = -52;
    
    // Regist notification settings
    if ([UIApplication instancesRespondToSelector:@selector(registerUserNotificationSettings:)]) {
        [[UIApplication sharedApplication] registerUserNotificationSettings:
         [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound
                                           categories:nil]];
    }
    
    // Create CBPeripheralManager (BLE) sender
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
    
    // Create CBCentralManager (BLE) recipter
    NSDictionary *option = @{CBCentralManagerOptionShowPowerAlertKey: [NSNumber numberWithBool:YES]};
    self.centralManager = [[CBCentralManager alloc]
                           initWithDelegate:self
                           queue:dispatch_get_main_queue()
                           options:option];
    
    
    // Init Location Manager (BLE)
    if ([CLLocationManager locationServicesEnabled]) {
        if([CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied ||
           [CLLocationManager authorizationStatus] == kCLAuthorizationStatusRestricted) { // check my app in location list
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Location Service Disabled"
                                                                                     message:@"Please enable Location Services.\nSettings - Privacy - Location Services - this App"
                                                                              preferredStyle:UIAlertControllerStyleActionSheet];
            [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                                style:UIAlertActionStyleDefault
                                                              handler:nil]];
            [self presentViewController:alertController animated:YES completion:nil];
        } else {
            if ([CLLocationManager isMonitoringAvailableForClass:[CLCircularRegion class]]) {
                self.locationManager = [[CLLocationManager alloc] init];
                self.locationManager.delegate = self;
                [self.locationManager requestAlwaysAuthorization];
                self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
                self.proximityUUID = [[NSUUID alloc] initWithUUIDString:@"244CFBCC-F801-40D0-A103-72F0488F0C16"];
                self.beaconRegion = [[CLBeaconRegion alloc]
                                     initWithProximityUUID:self.proximityUUID
                                     identifier:@"com.example.kmt"];
                [self.locationManager startMonitoringForRegion:self.beaconRegion];
            }
            
        }
    }
    
    // Get Background Apps Refresh status
    UIBackgroundRefreshStatus status = [UIApplication sharedApplication].backgroundRefreshStatus;
    switch (status) {
        case UIBackgroundRefreshStatusAvailable:
        {
            NSLog(@"%@", @"Background OK");
            break;
        }
        case UIBackgroundRefreshStatusRestricted:
        case UIBackgroundRefreshStatusDenied:
        {
            NSLog(@"%@", @"Background Deny");
            UIAlertController *alertController2 = [UIAlertController alertControllerWithTitle:@"Background App Refresh Disabled"
                                                                                     message:@"Please enable Background App Refresh.\nSettings - General - Background App Refresh"
                                                                              preferredStyle:UIAlertControllerStyleActionSheet];
            [alertController2 addAction:[UIAlertAction actionWithTitle:@"OK"
                                                                style:UIAlertActionStyleDefault
                                                              handler:nil]];
            [self presentViewController:alertController2 animated:YES completion:nil];
            break;
        }
        default:
            //どんなケースで入るのか不明
            NSLog(@"%@", @"Background Unknown");
            break;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Advertise

-(void)peripheralManagerDidUpdateState:(CBPeripheralManager*)peripheral {
    if (peripheral.state == CBPeripheralManagerStatePoweredOn) {
        NSLog(@"Start Advertising.");
        [self startAdvertising];
    } else if (peripheral.state == CBPeripheralManagerStatePoweredOff) {
        [self.peripheralManager stopAdvertising];
        NSLog(@"Stop Advertising.");
    } else if (peripheral.state == CBPeripheralManagerStateUnsupported) {
        NSLog(@"Unsupported.");
    }
}

-(void)runBackgroundTaskAdvertise {
    UIApplication *application = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // already exec, to stop background task process
            if (bgTask != UIBackgroundTaskInvalid) {
                [application endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
        });
    }];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Start getting location
        [self startAdvertising];
    });
}

- (void)startAdvertising {
    NSDate *nowdate = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"mmss"];
    NSString *mojidate = [formatter stringFromDate:nowdate];
    int datesuuji = [mojidate intValue];
    
    self.sendUUID = [[NSUUID alloc] initWithUUIDString:@"244CFBCC-F801-40D0-A103-72F0488F0C16"];
    CLBeaconRegion *beaconRegion2 = [[CLBeaconRegion alloc]
                                     initWithProximityUUID:self.sendUUID
                                     major:200
                                     minor:datesuuji
                                     identifier:@"com.example.kmt.arusmaA"];
    NSDictionary *beaconPeripheralData = [beaconRegion2 peripheralDataWithMeasuredPower:nil];
    
    // Start Advertising
    NSLog(@"Advertise Minor: %d", datesuuji);
    [self.peripheralManager startAdvertising:beaconPeripheralData];
    
    NSLog(@"Advertised.");
}

// check bluetooth
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state != CBCentralManagerStatePoweredOn) {
        //self.message2.text = @"Please start Bluetooth.";
        UIAlertController *alertController3 = [UIAlertController alertControllerWithTitle:@"Bluetooth Disabled"
                                                                                  message:@"Please enable Bluetooth.\nSettings - Bluetooth"
                                                                           preferredStyle:UIAlertControllerStyleActionSheet];
        [alertController3 addAction:[UIAlertAction actionWithTitle:@"OK"
                                                             style:UIAlertActionStyleDefault
                                                           handler:nil]];
        [self presentViewController:alertController3 animated:YES completion:nil];
    }
}

// discover BLE peripherals
- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI
{
    NSLog(@"Found peripheral w/ RSSI: %@ \n AdvData: %@", RSSI, advertisementData);
    NSLog(@"Services found: %lu", peripheral.services.count);
    NSLog(@"identifier %@, name: %@, services: %@", [peripheral identifier],[peripheral name],[peripheral services]);
    for (CBService *service in peripheral.services) {
        NSLog(@"Found service: %@ w/ UUID %@", service, service.UUID);
    }
}

// Background Central Manager
- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    [self runBackgroundTask];
}
// Exec Background Task
-(void)runBackgroundTask {
    UIApplication *application = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // already exec, to stop background task process
            if (bgTask != UIBackgroundTaskInvalid) {
                [application endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
        });
    }];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Start getting location
        [self.locationManager requestStateForRegion:self.beaconRegion];
    });
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    switch (state) {
        case CLRegionStateInside: // in region
        {
            if ([region isMemberOfClass:[CLBeaconRegion class]] && [CLLocationManager isRangingAvailable]) {
                [self.locationManager startRangingBeaconsInRegion:self.beaconRegion];
                //[self sendLocalNotificationForMessage:@"in Region"];
            }
            break;
        }
        case CLRegionStateOutside:
        case CLRegionStateUnknown:
        default:
        {
            NSLog(@"Exit Region and stop raging.");
            if ([region isMemberOfClass:[CLBeaconRegion class]] && [CLLocationManager isRangingAvailable]) {
                [self.locationManager stopRangingBeaconsInRegion:(CLBeaconRegion *)region];
            }
            break;
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    //[self sendLocalNotificationForMessage:@"Enter Region"];
    if ([region isMemberOfClass:[CLBeaconRegion class]] && [CLLocationManager isRangingAvailable]) {
        [self.locationManager startRangingBeaconsInRegion:(CLBeaconRegion *)region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    //[self sendLocalNotificationForMessage:@"Exit Region"];
    if ([region isMemberOfClass:[CLBeaconRegion class]] && [CLLocationManager isRangingAvailable]) {
        [self.locationManager stopRangingBeaconsInRegion:(CLBeaconRegion *)region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region
{
    if (beacons.count > 0) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"proximity != %d", CLProximityUnknown];
        NSArray *validBeacons = [beacons filteredArrayUsingPredicate:predicate];
        CLBeacon *beacon = validBeacons.firstObject;
        NSString *uuidStr = [beacon.proximityUUID UUIDString];
        NSString *substr = [uuidStr substringToIndex:36];
        NSLog(@"%@", substr);
        
        CLBeacon *nearestBeacon = beacons.firstObject;
        
        switch (nearestBeacon.proximity) {
            case CLProximityImmediate:
            {
                //rangeMessage = @"Range Near: ";
                rangeMessage = @"Near. ";
                if (beforeRSSI < (long)nearestBeacon.rssi && (long)nearestBeacon.rssi != 0) {
                    includeTimes += 1;
                } else if (beforeRSSI > (long)nearestBeacon.rssi) {
                    if (includeTimes > 0) {
                        includeTimes -= 0.5;
                    }
                }
                if (includeTimes >= 4) {
                    [self sendNotificationFunc];
                    includeTimes = 0;
                }
                beforeRSSI = (long)nearestBeacon.rssi;
                NSLog(@"inc: %d", includeTimes);
                break;
            }
            case CLProximityNear:
            case CLProximityFar:
            default:
            {
                //rangeMessage = @"Range Far: ";
                rangeMessage = @"Far. ";
                if (beforeRSSI < (long)nearestBeacon.rssi && (long)nearestBeacon.rssi != 0) {
                    includeTimes += 1;
                } else {
                    if (includeTimes > 0) {
                        includeTimes -= 1;
                    }
                }
                if (includeTimes >= 200) {
                    //[self sendNotificationFunc];
                    includeTimes = 0;
                }
                beforeRSSI = (long)nearestBeacon.rssi;
                break;
            }
        }
        
//        self.beaconMessage.text = [NSString stringWithFormat:@" UUID: %@\n Major: %@\n Minor: %@\n Accuracy: %f\n Range: %@\n RSSI: %ld", substr, nearestBeacon.major, nearestBeacon.minor, nearestBeacon.accuracy, rangeMessage, (long)nearestBeacon.rssi];
    } else {
        NSLog(@"no beacon %lu", (unsigned long)beacons.count);
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error
{
    //[self sendLocalNotificationForMessage:@"Error Exit Region"];
    NSLog(@"Location manager failed: %@", error);
}


// Notification
- (void)sendNotificationFunc {
    NSString *mess = [NSString stringWithFormat:@"Heads up!!"];
    [self sendLocalNotificationForMessage:[rangeMessage stringByAppendingString:mess]];
}
- (void)sendLocalNotificationForMessage:(NSString *)message {
    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
    [localNotification setTimeZone:[NSTimeZone defaultTimeZone]];
    [localNotification setFireDate:[NSDate date]];
    localNotification.alertBody = message;
    [localNotification setSoundName:(NSString *) UILocalNotificationDefaultSoundName];
    [localNotification setHasAction:NO];
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}

@end
