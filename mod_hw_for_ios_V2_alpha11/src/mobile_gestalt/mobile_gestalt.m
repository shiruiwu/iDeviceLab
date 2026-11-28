// FFXDH54F0F0V----357348295622732----35734829562273----a8:81:7e:ed:95:26----a8:81:7e:ed:95:25----0x0006AD40B17D001E----a5d122ea870b2a0fe69faa5aa5f3c06ab4c1c191----F3Y74893ZMQC73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDHC6K0F0V----357344868936790----35734486893679----a8:81:7e:a6:db:0c----a8:81:7e:a6:db:0b----0x0006E0537010001E----798ebbf4302b1a93df3812fc4958c511bbae6e0f----F3Y74482CYGC73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDHQYY0F0V----357348897812654----35734889781265----a8:81:7e:e7:95:a0----a8:81:7e:e7:95:9f----0x000694256BEA001E----875120695a9f58af613f0e1a7b02654add9f8f6c----F3Y74681EGHU73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDHBL80F0V----357341707793991----35734170779399----a8:81:7e:97:47:43----a8:81:7e:97:47:42----0x00061930CED5001E----4eeba4d3469627a0dcf6439ff0fcc15ed9cd1a1e----F3Y74274GDGZ73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDHUV80F0V----357340742233426----35734074223342----a8:81:7e:ae:3d:a2----a8:81:7e:ae:3d:a1----0x00065683E813001E----e4133b957f2e4b9304991e4447384dba7b64c857----F3Y74079MBPY73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDHMF30F0V----357348716981934----35734871698193----a8:81:7e:5e:6c:3a----a8:81:7e:5e:6c:39----0x00069AA54689001E----36614a13d4b9675a0a823b59252507c398902e8c----F3Y74673KTJJ73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDHY3J0F0V----357344722338940----35734472233894----a8:81:7e:7b:24:11----a8:81:7e:7b:24:10----0x0006C296B517001E----d30436e71d72e13428bcc03ac892e8fe65461c0e----F3Y74672YXQV73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// FFXDH6JL0F0V----357344835568950----35734483556895----a8:81:7e:d0:ab:9a----a8:81:7e:d0:ab:99----0x00066C4B6C80001E----4c379a6c8981c877d0599c9aab93fc8f09d4beca----F3Y74285WQJH73WC----iPhone13,2----3H523KH/A----d53gap----t8101----18D61----12.5.5
// 序列号-IMEI-MEID-Wlan地址-蓝牙地址-ECID-UDID-主板序列号-产品类型-销售型号-硬件模型-芯片型号-编译版本-固件版本

// 什么是Apple ID锁？
// AppleID锁是苹果在iOS 7.0及更高系统推出的苹果设备防盗功能，又称ID锁、激活锁等。在设备的“设置--iCloud”中打开“查找我的iPhone/iPad”后，就会开启Apple ID锁；
// 若开启Apple ID锁，抹除所有资料和设置或刷机后，都需要输入对应的Apple ID和密码才能激活设备，否则设备将无法使用。

// 什么是序列号匹配？
// 苹果设备的序列号和销售型号、硬盘容量这两项是有对应关系的，如果爱思验机里面提示序列号匹配为“否”，则说明此设备的序列号、销售型号、硬盘容量这三项最少有一项是被修改过的。

// 什么是五码匹配？
// 苹果设备的UDID是由IMEI号（iPad、iPod为ECID）、序列号、WiFi地址、蓝牙地址这四项生成的，所以如果爱思验机里面提示五码匹配为“否”，则说明此设备这五项最少有一项是被修改过的。

#import <dlfcn.h>
#import <Security/Security.h>
#include <stdint.h>
#include <string.h>
#import <sys/stat.h>
#include <unistd.h>
#if __arm64e__
#include <ptrauth.h>
#endif

static void *MGSymbolReadable(void *pointer) {
#if __arm64e__
  if (pointer != NULL) pointer = ptrauth_strip(pointer, ptrauth_key_function_pointer);
#endif
  return pointer;
}

static void *MGSymbolCallable(void *pointer) {
#if __arm64e__
  if (pointer != NULL) pointer = ptrauth_sign_unauthenticated(
      ptrauth_strip(pointer, ptrauth_key_function_pointer),
      ptrauth_key_function_pointer, 0);
#endif
  return pointer;
}
#import <stdio.h>

#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/in.h>
#include <net/if_dl.h>
#include <pthread.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <execinfo.h>
#include <signal.h>
#include <objc/runtime.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFString.h>
#include <Foundation/NSData.h>
#include <CoreFoundation/CFData.h>
#include <Foundation/Foundation.h>
#include "mobile_gestalt/mobile_gestalt.h"
#include "captain_hook/CaptainHook.h"
#include "cydia_substrate_hook/HookUtil.h"
#include "third_party/IOKit/IOKitLib.h"
#include "third_party/uidevice-extension/UIDevice-IOKitExtensions.h"
#include "mg_copy_answer_table.h"
#include "CoreTelephony.h"

static NSMutableDictionary* cf_device = nil;
static NSString *gModHWConfigSource = @"none";
static BOOL gModHWConfigLoaded = NO;
static BOOL gModHWMGCopyAnswerInstalled = NO;
static BOOL gModHWMGCopyMultipleAnswersInstalled = NO;
static BOOL gModHWSysctlByNameInstalled = NO;

OBJC_EXPORT const char *object_getClassName(id obj);

static BOOL IsArm64()
{
  static BOOL arm64 = NO ;
  static dispatch_once_t once ;
  dispatch_once(&once, ^{
    arm64 = sizeof(int *) == 8 ;
  });
  return arm64 ;
}
// Configuration values are untrusted input. Accept only the exact byte
// lengths used by the corresponding hardware-address fields.
static BOOL IsHexStringOfLength(NSString *value, NSUInteger expectedLength) {
  if (![value isKindOfClass:[NSString class]] || value.length != expectedLength) return NO;
  NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
  return [value rangeOfCharacterFromSet:nonHex].location == NSNotFound;
}

static NSData* dataFromHexString(NSString* str) {
  if (!IsHexStringOfLength(str, 12)) return nil;
  UInt8 bytes[6] = {0};
  for (NSUInteger i = 0; i < 6; i++) {
    NSString *pair = [str substringWithRange:NSMakeRange(i * 2, 2)];
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:pair];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) return nil;
    bytes[i] = (UInt8)value;
  }
  return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}
static CFDataRef HexToByte(const char* hex_str){
  if (hex_str == NULL) return NULL;
  size_t length = strlen(hex_str);
  if (length == 0 || (length % 2) != 0 || (length / 2) > 1024) return NULL;
  UInt8 bytes[1024] = {0};
  for (size_t index = 0; index < length; index += 2) {
    unsigned char high = (unsigned char)hex_str[index];
    unsigned char low = (unsigned char)hex_str[index + 1];
    if (strchr("0123456789abcdefABCDEF", high) == NULL ||
        strchr("0123456789abcdefABCDEF", low) == NULL) return NULL;
    char pair[3] = {(char)high, (char)low, '\0'};
    char *end = NULL;
    unsigned long value = strtoul(pair, &end, 16);
    if (end == pair || *end != '\0' || value > 0xFF) return NULL;
    bytes[index / 2] = (UInt8)value;
  }
  return CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)(length / 2));
}
/*
 From Apple open source: SecTrustSettings.c (APSL license)
 Return a (hex)string representation of a CFDataRef.
 */
static CFStringRef APCopyHexStringFromData(CFDataRef data)
{
  CFIndex ix, length;
  const UInt8 *bytes;
  CFMutableStringRef string;
  
  if (data) {
    length = CFDataGetLength(data);
    bytes = CFDataGetBytePtr(data);
  } else {
    length = 0;
    bytes = NULL;
  }
  string = CFStringCreateMutable(kCFAllocatorDefault, length * 2);
  for (ix = 0; ix < length; ++ix)
    CFStringAppendFormat(string, NULL, CFSTR("%02X"), bytes[ix]);
  
  return string;
}
/* Adapted from StackOverflow: */
/* http://stackoverflow.com/a/12535482 */
static CFDataRef APCopyDataFromHexString(CFStringRef string)
{
  if (string == NULL || CFGetTypeID(string) != CFStringGetTypeID()) return NULL;
  NSString *hex = (__bridge NSString *)string;
  // A UDID is 20 bytes represented by exactly 40 hexadecimal characters.
  if (!IsHexStringOfLength(hex, 40)) return NULL;
  UInt8 bytes[20] = {0};
  for (NSUInteger i = 0; i < 20; i++) {
    NSString *pair = [hex substringWithRange:NSMakeRange(i * 2, 2)];
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:pair];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) return NULL;
    bytes[i] = (UInt8)value;
  }
  return CFDataCreate(kCFAllocatorDefault, bytes, sizeof(bytes));
}
static int NumberCountOfString(NSString* str,const char a){
  int count=0;
  int len = (int)[str length];
  for(int i=0;i<len;i++){
    unsigned char c = [str characterAtIndex:i];
    if(c==a){
      count++;
    }
  }
  return count;
}
static void CFShowType(CFTypeRef err_test){
  if (err_test) {
    NSLog(@"CFShowType:%@!!!!!!!!!!!!!!!!",
          CFCopyTypeIDDescription(CFGetTypeID(err_test)));
  }
}
static bool IsNil(NSString* aString) {
  return !(aString && aString.length);
}
static BOOL PreferenceBooleanIsTrue(NSDictionary *dictionary, NSString *key) {
  id value = dictionary[key];
  if (!value) return NO;
  CFTypeRef ref = (__bridge CFTypeRef)value;
  return CFGetTypeID(ref) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)ref);
}
static bool IsCFData(CFTypeRef data){
  return (CFGetTypeID(data)==CFDataGetTypeID());
}
static bool IsCFString(CFTypeRef data){
  return (CFGetTypeID(data)==CFStringGetTypeID());
}
static CFStringRef ComToStrRef(CFTypeRef data){
  CFStringRef va = nil;
  if (data) {
    va = CFStringCreateWithFormat(NULL,NULL,CFSTR("%@"),data);
  }
  return va;
}
static int GetIdLength(CFTypeRef data){
  // NSLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  // CFShowType(data);
  // if (!data) {
  //   // NSLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  //   return 0;
  // }
  if (CFGetTypeID(data)==CFStringGetTypeID()){
    // NSLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    CFIndex len = CFStringGetLength((__bridge CFStringRef)data);
    return (int)len;
  }
  else if (CFGetTypeID(data) == CFDataGetTypeID()){
    // NSLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    CFIndex len = CFDataGetLength((__bridge CFDataRef)data);
    return (int)len;
  }
  else{
    // NSLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    return 0;
  }
}
static void Show(NSString* title,NSString* msg){
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                  message:msg
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil];
  [alert show];
  [alert release];
}
void initPrefFile(){
  // Primary Rootless preference path shared with the manager and package layout.
  static NSString* kPref = @"/var/mobile/Library/Preferences/com.modhw.ios.devices.plist";
  static NSString* profileRoot = @"/var/mobile/Library/Preferences/com.modhw.ios.profiles";
  // Keep the original temporary path as a compatibility fallback for existing setups.
  static NSString* legacyPref = @"/tmp/devices.plist";
  NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
  NSString *profilePref = nil;
  NSCharacterSet *invalidBundleChars = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
  if ([bundleID isKindOfClass:[NSString class]] && bundleID.length > 0 &&
      [bundleID rangeOfCharacterFromSet:invalidBundleChars].location == NSNotFound &&
      ![bundleID hasPrefix:@"."] && [bundleID rangeOfString:@".."].location == NSNotFound &&
      ![bundleID hasSuffix:@"."]) {
    profilePref = [[profileRoot stringByAppendingPathComponent:bundleID] stringByAppendingPathExtension:@"plist"];
  }
  NSString *selectedPref = (profilePref && [[NSFileManager defaultManager] fileExistsAtPath:profilePref])
      ? profilePref : ([[NSFileManager defaultManager] fileExistsAtPath:kPref] ? kPref : legacyPref);
  if (profilePref != nil && [selectedPref isEqualToString:profilePref]) gModHWConfigSource = @"per-app";
  else if ([selectedPref isEqualToString:kPref]) gModHWConfigSource = @"global";
  else gModHWConfigSource = @"legacy";
  gModHWConfigLoaded = NO;
  NSLog(@"[mod_hw] Loading configuration from %@.", [selectedPref isEqualToString:profilePref] ? @"per-app profile" : ([selectedPref isEqualToString:kPref] ? @"global profile" : @"legacy fallback"));
  if (cf_device != nil) {
    [cf_device release];
    cf_device = nil;
  }
  cf_device = [[NSMutableDictionary alloc] init];
  for (int i=0;i<3;i++) {
    NSDictionary *aa = [NSDictionary dictionaryWithContentsOfFile:selectedPref];
    if (![aa isKindOfClass:[NSDictionary class]]) {
      NSLog(@"[mod_hw] No valid preference dictionary found; hooks will use original system values.");
      break;
    }
    [cf_device release];
    cf_device = [[NSMutableDictionary alloc] initWithDictionary:aa];
    if ([cf_device count]) {
      CFDataRef a;
      NSString* device_id = (NSString*)[cf_device objectForKey:@"UniqueDeviceID"];
      if (!device_id) {
        break;
      }
      a = APCopyDataFromHexString((__bridge CFStringRef)device_id);
      if (a == NULL) {
        NSLog(@"[mod_hw] Invalid UniqueDeviceID hex value; configuration ignored.");
        [cf_device removeAllObjects];
        break;
      }
      const UInt8* b = CFDataGetBytePtr(a);
      CFIndex c = CFDataGetLength(a);
      //refences:http://blog.timac.org/?tag=mgcopyanswer
      if (PreferenceBooleanIsTrue(aa, @"UniqueDeviceIDData")) {
        [cf_device setValue:[NSData dataWithBytes:b length:(NSUInteger)c] forKey:@"UniqueDeviceIDData"];
      }
      else{
        [cf_device setValue:nil forKey:@"UniqueDeviceIDData"];
      }
      if (PreferenceBooleanIsTrue(aa, @"WifiAddressData")) {
        NSString* mac = (NSString*)[cf_device objectForKey:@"WifiAddress"];
        if (mac!=nil&&([mac length]>0)) {
          mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
          NSData* data = dataFromHexString(mac);
          if (data != nil) [cf_device setValue:data forKey:@"WifiAddressData"];
          else [cf_device setValue:nil forKey:@"WifiAddressData"];
        }
      }
      else{
        [cf_device setValue:nil forKey:@"WifiAddressData"];
      }
      if (PreferenceBooleanIsTrue(aa, @"BluetoothAddressData")) {
        NSString* ss1 = @"BluetoothAddress";
        NSString* buletooth = (NSString*)[cf_device objectForKey:ss1];
        if (buletooth!=nil&&([buletooth length]>0)) {
          buletooth = [buletooth stringByReplacingOccurrencesOfString:@":" withString:@""];
          NSData* data = dataFromHexString(buletooth);
          if (data != nil) [cf_device setValue:data forKey:@"BluetoothAddressData"];
          else [cf_device setValue:nil forKey:@"BluetoothAddressData"];
        }
      }
      else{
        [cf_device setValue:nil forKey:@"BluetoothAddressData"];
      }
      CFRelease(a);
      break;
    }
    break;
  }
  gModHWConfigLoaded = (cf_device != nil && cf_device.count > 0 &&
                        [cf_device[@"UniqueDeviceID"] isKindOfClass:NSString.class]);
  // if (![cf_device count]) {
  //   NSLog(@"cf_device init failed.");
  // }
  // else{
  //   NSLog(@"cf_device init ok:%@.",cf_device);
  // }
}

static void WriteModHWRuntimeStatus(NSString *phase) {
  @autoreleasepool {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *cache = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Caches"];
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:cache
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0700}
                                                    error:&directoryError];
    if (directoryError != nil) {
      NSLog(@"[mod_hw] Cannot create Hook status directory: %@.", directoryError.localizedDescription);
      return;
    }
    NSDictionary *status = @{
      @"bundleIdentifier": bundleID,
      @"configSource": gModHWConfigSource ?: @"none",
      @"configLoaded": @(gModHWConfigLoaded),
      @"phase": phase ?: @"unknown",
      @"mgCopyAnswerInstalled": @(gModHWMGCopyAnswerInstalled),
      @"mgCopyMultipleAnswersInstalled": @(gModHWMGCopyMultipleAnswersInstalled),
      @"sysctlByNameInstalled": @(gModHWSysctlByNameInstalled),
      @"processID": @(getpid()),
      @"timestamp": [NSDate date]
    };
    NSString *statusPath = [cache stringByAppendingPathComponent:@".modhw-hook-status.plist"];
    if (![status writeToFile:statusPath atomically:YES] || chmod(statusPath.fileSystemRepresentation, 0600) != 0) {
      NSLog(@"[mod_hw] Cannot persist Hook runtime status for %@.", bundleID);
    }
  }
}
//////////////////////////////////////////////////////////
//IMEI/WifiAddress
//////////////////////////////////////////////////////////
#define HOOK_IOKIT(RET, ...) HOOK_FUNCTION(RET, /System/Library/Frameworks/IOKit.framework/Versions/A/IOKit, __VA_ARGS__)
HOOK_IOKIT(CFTypeRef,IORegistryEntrySearchCFProperty,
           io_registry_entry_t entry,
           const io_name_t plane,
           CFStringRef key,
           CFAllocatorRef allocator,
           IOOptionBits options){
  CFTypeRef rv = _IORegistryEntrySearchCFProperty(entry,plane,
                                                    key,allocator,options);
  // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
  if (key!=nil&&(CFStringGetLength(key)>0)) {
    unsigned int mask = NSCaseInsensitiveSearch;
    NSString *key_str = (__bridge NSString*)key;
    if([key_str compare:@"IOPlatformSerialNumber" options:mask]==NSOrderedSame){
      NSString* SerialNumber = [[NSString alloc] init];
      SerialNumber = [cf_device objectForKey:@"SerialNumber"];
      if (SerialNumber!=nil&&(GetIdLength(SerialNumber)>0)&&IsCFString(SerialNumber)) {
        // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
        return CFStringCreateCopy(kCFAllocatorDefault,(__bridge CFStringRef)SerialNumber);
      }
    }
    if ([key_str compare:@"device-imei" options:mask]==NSOrderedSame) {
      NSString* ss1 = @"InternationalMobileEquipmentIdentity";
      CFTypeRef imei = [cf_device objectForKey:ss1];
      if (imei!=nil&&(GetIdLength(imei)>0)&&IsCFString(imei)) {
        // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
        return CFStringCreateCopy(kCFAllocatorDefault,(__bridge CFStringRef)imei);
      }
    }
    if ([key_str compare:@"local-mac-address" options:mask]==NSOrderedSame) {
      NSString* mac = (NSString*)[cf_device objectForKey:@"BluetoothAddress"];
      if (mac!=nil&&([mac length]>0)) {
        mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
        NSData* data = dataFromHexString(mac);
        // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
        if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);
      }
    }
    if ([key_str compare:@"product-id" options:mask]==NSOrderedSame) {
      NSString* mac = (NSString*)[cf_device objectForKey:@"ProductId"];
      if (mac!=nil&&([mac length]>0)) {
        NSData* data = dataFromHexString(mac);
        // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
        if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);
      }
    }
    if ([key_str compare:@"unique-chip-id" options:mask]==NSOrderedSame) {
      NSString* mac = (NSString*)[cf_device objectForKey:@"UniqueChipId"];
      if (mac!=nil&&([mac length]>0)) {
        NSData* data = dataFromHexString(mac);
        // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
        if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);
      }
    }
    // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
  }
  return rv;
}
//////////////////////////////////////////////////////////
//SerialNumber/WifiAddress/BluetoothAddress
//////////////////////////////////////////////////////////
HOOK_IOKIT(CFTypeRef,IORegistryEntryCreateCFProperty,
           io_registry_entry_t entry,
           CFStringRef key,
           CFAllocatorRef allocator,
           IOOptionBits options){
  CFTypeRef result = nil;
  result = _IORegistryEntryCreateCFProperty(entry,key,allocator,options);
  if (result==nil){
    return result;
  }
  // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
  NSString* key_str = (__bridge NSString*)key;
  const char* ssss = [key_str UTF8String];
  const char target_key_a[] = "mac-address-wifi";
  const char target_key_b[] = "mac-address-bluetooth";
  unsigned int mask = NSCaseInsensitiveSearch;
  //NSLog(@"%s:hook_%@=%@",__func__,key,result);
  if([key_str compare:@"IOPlatformSerialNumber" options:mask]==NSOrderedSame){
    NSString* SerialNumber = [[NSString alloc] init];
    SerialNumber = [cf_device objectForKey:@"SerialNumber"];
    if (SerialNumber!=nil&&(GetIdLength(SerialNumber)>0)&&IsCFString(SerialNumber)) {
      // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,rv);
      return CFStringCreateCopy(kCFAllocatorDefault,(__bridge CFStringRef)SerialNumber);
    }
  }
  else if([key_str compare:@"IOMacAddress" options:mask]==NSOrderedSame){
    NSString* mac = (NSString*)[cf_device objectForKey:@"WifiAddress"];
    if (mac!=nil&&([mac length]>0)) {
      mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
      NSData* data = dataFromHexString(mac);
      // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
      if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);
    }
  }
  else if([key_str compare:@"local-mac-address" options:mask]==NSOrderedSame){
    NSString* data = [[NSString alloc] init];
    data = [cf_device objectForKey:@"BluetoothAddress"];
    if (data!=nil&&[data length]>0) {
      // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
      result = (__bridge CFStringRef)data;
    }
  }
  else if(!memcmp(ssss,target_key_a,sizeof(target_key_a)-sizeof(char))){
    NSString* mac = (NSString*)[cf_device objectForKey:@"WifiAddress"];
    if (mac!=nil&&([mac length]>0)) {
      mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
      NSData* data = dataFromHexString(mac);
      // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
      if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);
    }
    return result;
  }
  else if(!memcmp(ssss,target_key_b,sizeof(target_key_b)-sizeof(char))){
    NSString* mac = (NSString*)[cf_device objectForKey:@"BluetoothAddress"];
    if (mac!=nil&&([mac length]>0)) {
      mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
      NSData* data = dataFromHexString(mac);
      // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
      if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);
    }
    return result;
  }
  // NSLog(@"%s:hook_iokit: %@-%@",__func__,key,result);
  return result;
}
// static void(*orig_CTServerConnectionCopyMobileEquipmentInfo)(struct CTResult* result, CTServerConnectionRef conn, CFMutableDictionaryRef* dicts) = NULL;
// static void replace_CTServerConnectionCopyMobileEquipmentInfo(struct CTResult* result, CTServerConnectionRef conn, CFMutableDictionaryRef* dicts){
//   @autoreleasepool {
//     NSLog(@"hook_CTServerConnectionCopyMobileEquipmentInfo");
//     orig_CTServerConnectionCopyMobileEquipmentInfo(result, conn, dicts);
//   }
// }
// static void HookCoreTelephony(){
//   void *lib1 = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
//   void* ptr = dlsym(lib1, "_CTServerConnectionCopyMobileEquipmentInfo");
//   if (ptr!=NULL) {
//     // NSLog(@"_CTServerConnectionCopyMobileEquipmentInfo found:%p",ptr);
//     CallMSHookFunction((void*)ptr, (void*)replace_CTServerConnectionCopyMobileEquipmentInfo, (void**)&orig_CTServerConnectionCopyMobileEquipmentInfo);
//     if (orig_CTServerConnectionCopyMobileEquipmentInfo != NULL) {
//       // NSLog(@"Hook_CTServerConnectionCopyMobileEquipmentInfo success.");
//     }
//     return;
//   }
//   else{
//     // NSLog(@"_CTServerConnectionCopyMobileEquipmentInfo failed:%p",ptr);
//     return;
//   }
// }
// HOOK_MESSAGE(id,AADeviceInfo,appleIDClientIdentifier){
//   NSString* ss1 = @"appleIDClientIdentifier";
//   id aaa = [cf_device objectForKey:ss1];
//   if (aaa==nil) {
//     return _AADeviceInfo_appleIDClientIdentifier(self,sel);
//   }
//   return aaa;
// }
//////////////////////////////////////////////////////////
//DeviceDataFilter
//////////////////////////////////////////////////////////
static CFTypeRef (*HookNextMGCopyAnswer)(CFTypeRef prop,uint32_t *outTypeCode);
static CFTypeRef (*HookMGCopyAnswer)(CFTypeRef prop);
static CFTypeRef ChooseCallHookedMGCopyAnswer(CFTypeRef prop,uint32_t *outTypeCode,bool is_show){
  CFTypeRef result = nil;
  if (IsArm64()) {
    result = HookNextMGCopyAnswer(prop,outTypeCode);
    if (is_show) {
      NSLog(@"hook_FN_MGCopyAnswer_prop_arm64:%@---value:%@",
            prop,result);
      if (result != nil) {
        NSLog(@"hook_FN_MGCopyAnswer_prop_arm64:%@---value:%@-type:%s",
              prop,result,object_getClassName(result));
      }
    }
  }
  else{
    result = HookMGCopyAnswer(prop);
    if (is_show) {
      NSLog(@"hook_FN_MGCopyAnswer_prop_armv7:%@---value:%@",
            prop,result);
      if (result != nil) {
        NSLog(@"hook_FN_MGCopyAnswer_prop_armv7:%@---value:%@-type:%s",
              prop,result,object_getClassName(result));
      }
    }
  }
  return result;
}
static CFTypeRef DeviceDataFilter(CFTypeRef prop,uint32_t *outTypeCode){
  CFTypeRef return_value = nil;
  return_value = ChooseCallHookedMGCopyAnswer(prop, outTypeCode, false);
  // NSLog(@"hook_key_no:%@=%@",prop, return_value);
  if (return_value==nil) {
    return return_value;
  }
  CFStringRef pkey = CFStringCreateCopy(kCFAllocatorDefault, prop);
  NSString* key = (NSString*)CFBridgingRelease(pkey);
  id aaaaa = [cf_device objectForKey:key];
  if (aaaaa == nil) {
    for (int i = 0; keyMappingTable[i].obfuscatedKey != NULL; ++i) {
      if (!strcmp(keyMappingTable[i].obfuscatedKey, key.UTF8String) && keyMappingTable[i].key!=NULL) {
        key = [NSString stringWithUTF8String:keyMappingTable[i].key];
        break;
      }
    }
    aaaaa = [cf_device objectForKey:key];
    if (aaaaa == nil) {
      // NSLog(@"hook_key_no:%@=%@:%s=%@",prop, return_value, object_getClassName(return_value));
      return return_value;
    }
  }
  if (strcmp(object_getClassName(return_value), object_getClassName(CFBridgingRetain(aaaaa))) != 0){
    // NSLog(@"hook_key_except:%@=%@:%s=%s",prop, return_value, object_getClassName(return_value), object_getClassName(aaaaa));
    return return_value;
  }
  // NSLog(@"hook_key_to:%@=%@:%@", prop, return_value, aaaaa);
  // NSLog(@"hook_key_to:%@=%@:%s=%s", prop, return_value, object_getClassName(return_value), object_getClassName(CFBridgingRetain(aaaaa)));
  return CFBridgingRetain(aaaaa);
}
static CFTypeRef FN_NextMGCopyAnswer(CFTypeRef prop, uint32_t *outTypeCode){
  @autoreleasepool {
    CFTypeRef result;
    if (prop == NULL || prop == nil) {
      result = HookNextMGCopyAnswer(prop, outTypeCode);
    }
    else{
      result = DeviceDataFilter(prop, outTypeCode);
    }
    return result;
  }
}
static CFTypeRef FN_MGCopyAnswer(CFTypeRef prop){
  @autoreleasepool {
    CFTypeRef result;
    if (prop == NULL || prop == nil) {
      result = HookMGCopyAnswer(prop);
    }
    else{
      result = DeviceDataFilter(prop, NULL);
    }
    return result;
  }
}
//sftp://127.0.0.1:2222/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
//////////////////////////////////////////////////////////
//MGCopyAnswer
//////////////////////////////////////////////////////////
static void MGCopyAnswerHookImpl(const void* mg_copy_answer_addr){
  HookMGCopyAnswer = NULL;
  HookNextMGCopyAnswer = NULL;
  if (mg_copy_answer_addr == NULL) {
    NSLog(@"[mod_hw] MGCopyAnswer symbol address is null.");
    return;
  }
  if (IsArm64()) {
    // On ARM64 the exported MGCopyAnswer entry is a short thunk. Do not
    // blindly hook +8: newer iOS builds branch to the internal routine at
    // a branch-relative address. Decode the actual B immediate instead.
    const uint8_t *readableEntry = (const uint8_t *)MGSymbolReadable((void *)mg_copy_answer_addr);
    if (readableEntry == NULL) {
      NSLog(@"[mod_hw] MGCopyAnswer entry cannot be PAC-stripped.");
      return;
    }
    uint32_t firstInstruction = 0, branchInstruction = 0;
    memcpy(&firstInstruction, readableEntry, sizeof(firstInstruction));
    memcpy(&branchInstruction, readableEntry + 4, sizeof(branchInstruction));
    if (firstInstruction != 0xD2800001 ||
        (branchInstruction & 0xFC000000) != 0x14000000) {
      NSLog(@"[mod_hw] Unsupported MGCopyAnswer thunk: first=0x%08x branch=0x%08x; skipping unsafe hook.",
            firstInstruction, branchInstruction);
      return;
    }
    int64_t immediate26 = (int64_t)(branchInstruction & 0x03FFFFFF);
    if (immediate26 & 0x02000000) immediate26 -= 0x04000000;
    intptr_t branchOffset = (intptr_t)(immediate26 * 4);
    void *internalAddress = (void *)(readableEntry + 4 + branchOffset);
    NSLog(@"[mod_hw] MGCopyAnswer internal target resolved at %p (offset=%ld).",
          internalAddress, (long)branchOffset);
    CallMSHookFunction(MGSymbolCallable(internalAddress), (void *)FN_NextMGCopyAnswer, (void **)&HookNextMGCopyAnswer);
    gModHWMGCopyAnswerInstalled = (HookNextMGCopyAnswer != NULL);
    if (HookNextMGCopyAnswer == NULL) {
      NSLog(@"[mod_hw] MGCopyAnswer internal hook installation failed.");
    } else {
      NSLog(@"[mod_hw] MGCopyAnswer internal hook installed.");
    }
  } else {
    CallMSHookFunction((void *)mg_copy_answer_addr, (void *)FN_MGCopyAnswer, (void **)&HookMGCopyAnswer);
    gModHWMGCopyAnswerInstalled = (HookMGCopyAnswer != NULL);
    if (HookMGCopyAnswer == NULL) NSLog(@"[mod_hw] 32-bit MGCopyAnswer hook installation failed.");
    else NSLog(@"[mod_hw] 32-bit MGCopyAnswer hook installed.");
  }
}

static void HookerForMGCopyAnswer(){
  const char* name = "MGCopyAnswer";
  void *lib1 = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
  MSImageRef image = CallMSGetImageByName("/usr/lib/libMobileGestalt.dylib");
  const void* ptr = CallMSFindSymbol(image, name);
  if (!ptr) {
    ptr = dlsym(lib1, "MGCopyAnswer");
  }
  if (!ptr) {
    ptr = CallMSFindSymbol(image, "_MGCopyAnswer");
    if (!ptr) {
      ptr = CallMSFindSymbol(NULL, "_MGCopyAnswer");
    }
  }
  if (ptr!=NULL) {
    // NSLog(@"MGCopyAnswer found:%p",ptr);
    MGCopyAnswerHookImpl(ptr);
    return;
  }
  else{
    NSLog(@"MGCopyAnswer failed:%p",ptr);
    return;
  }
}
//////////////////////////////////////////////////////////
//MGCopyMultipleAnswers
//////////////////////////////////////////////////////////
static CFPropertyListRef (*HookMGCopyMultipleAnswers)(CFArrayRef questions, int unknown0);
static CFPropertyListRef FnMGCopyMultipleAnswers(CFArrayRef questions, int unknown0){
  CFPropertyListRef original = HookMGCopyMultipleAnswers(questions, unknown0);
  if (original == NULL || questions == NULL ||
      CFGetTypeID(original) != CFDictionaryGetTypeID() ||
      CFGetTypeID(questions) != CFArrayGetTypeID()) {
    return original;
  }

  CFMutableDictionaryRef modified = CFDictionaryCreateMutableCopy(
      kCFAllocatorDefault, 0, (CFDictionaryRef)original);
  if (modified == NULL) return original;

  BOOL changed = NO;
  CFIndex count = CFArrayGetCount(questions);
  for (CFIndex index = 0; index < count; index++) {
    CFTypeRef key = CFArrayGetValueAtIndex(questions, index);
    if (key == NULL || CFGetTypeID(key) != CFStringGetTypeID()) continue;

    CFTypeRef replacement = DeviceDataFilter(key, NULL);
    if (replacement == NULL) continue;
    CFTypeRef previous = CFDictionaryGetValue((CFDictionaryRef)original, key);
    if (previous == NULL || !CFEqual(previous, replacement)) {
      CFDictionarySetValue(modified, key, replacement);
      changed = YES;
    }
    CFRelease(replacement);
  }

  if (!changed) {
    CFRelease(modified);
    return original;
  }
  CFRelease(original);
  return modified;
}

static void MGCopyMultipleAnswersImpl(const void* ptr){
  HookMGCopyMultipleAnswers = NULL;
  CallMSHookFunction((void*)((unsigned long)ptr), (void*)FnMGCopyMultipleAnswers, (void**)&HookMGCopyMultipleAnswers);
  gModHWMGCopyMultipleAnswersInstalled = (HookMGCopyMultipleAnswers != NULL);
  if(HookMGCopyMultipleAnswers!=NULL){
    // NSLog(@"HookMGCopyMultipleAnswers success.");
  }
  else{
    NSLog(@"HookMGCopyMultipleAnswers failed.");
  }
}

static void HookerForMGCopyMultipleAnswers(){
  const char *name = "_MGCopyMultipleAnswers";
  MSImageRef image = CallMSGetImageByName("/usr/lib/libMobileGestalt.dylib");
  void *library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
  const void *ptr = CallMSFindSymbol(image, name);
  if (ptr == NULL && library != NULL) ptr = dlsym(library, name);
  if (ptr == NULL) ptr = CallMSFindSymbol(NULL, name);
  if (ptr == NULL && library != NULL) ptr = dlsym(library, "MGCopyMultipleAnswers");
  if (ptr != NULL) {
    MGCopyMultipleAnswersImpl(ptr);
  } else {
    NSLog(@"[mod_hw] MGCopyMultipleAnswers symbol unavailable; single-answer Hook remains active.");
  }
}
//////////////////////////////////////////////////////////
//MGCopyAnswer/MGCopyMultipleAnswers
//////////////////////////////////////////////////////////
void MobileGestaltHooker(){
  @autoreleasepool {
    HookerForMGCopyAnswer();
    HookerForMGCopyMultipleAnswers();
  }
}
static char* MachineData = NULL;
static int MachineDataLen = 0;
static char* ModelData = NULL;
static int ModelDataLen = 0;
void initGlobalSysCtl() {
  if (MachineData == NULL || !MachineDataLen) {
    NSString* ProductType = [cf_device objectForKey:@"ProductType"];
    if (ProductType != nil) {
      MachineData = malloc(ProductType.length + 1);
      memset(MachineData, 0, ProductType.length + 1);
      strlcpy(MachineData, ProductType.UTF8String, ProductType.length + 1);
      MachineDataLen = ProductType.length + 1;
      // NSLog(@"hook_key_to1:%s:%@", MachineData, ProductType);
    }
  }
  if (ModelData == NULL || !ModelDataLen) {
    NSString* HWModelStr = [cf_device objectForKey:@"HWModelStr"];
    if (HWModelStr != nil) {
      ModelData = malloc(HWModelStr.length + 2);
      memset(ModelData, 0, HWModelStr.length + 2);
      strlcpy(ModelData, HWModelStr.UTF8String, HWModelStr.length + 1);
      ModelDataLen = HWModelStr.length + 1;
      // NSLog(@"hook_key_to1:%s:%@", ModelData, HWModelStr);
    }
  }
}
//////////////////////////////////////////////////////////
//sysctlbyname
//////////////////////////////////////////////////////////
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int replace_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen){
  int ReturnValue = 0;
  if(oldp && oldlenp) {
    if(!strcmp(name, "hw.model") && ModelDataLen) {
      strlcpy(oldp, ModelData, ModelDataLen);
      *oldlenp = ModelDataLen;
      return ReturnValue;
    } 
    else if(!strcmp(name, "hw.machine") && MachineDataLen) {
      strlcpy(oldp, MachineData, MachineDataLen);
      *oldlenp = MachineDataLen;
      return ReturnValue;
    }
  } 
  else if(!oldp && oldlenp) {
    if(!strcmp(name, "hw.model") && ModelDataLen) {
      *oldlenp = ModelDataLen;
      return ReturnValue;
    } 
    else if(!strcmp(name, "hw.machine") && MachineDataLen) {
      *oldlenp = MachineDataLen;
      return ReturnValue;
    }
  }
  // size_t size;
  // orig_sysctlbyname(name, NULL, &size, NULL, 0);
  ReturnValue = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
  // if (oldp != NULL) {
  //   NSLog(@"hook_sysctlbyname %s:%s", name, oldp);
  // }
  // if (name!=NULL && (!strcmp(name, "hw.machine") || !strcmp(name, "hw.product") || !strcmp(name, "hw.model") || !strcmp(name, "hw.target"))){
  //   char *machine = malloc(*oldlenp + 1);
  //   memset(machine, 0, *oldlenp + 1);
  //   strlcpy(machine, oldp, size);
  //   NSLog(@"hook_sysctlbyname %s:%s:%d\0", name, machine, size);
  //   free(machine);
  // }
  return ReturnValue;
}

static void hook_sysctlbyname() {
  CallMSHookFunction((void*)sysctlbyname, (void*)replace_sysctlbyname, (void**)&orig_sysctlbyname);
  gModHWSysctlByNameInstalled = (orig_sysctlbyname != NULL);
}
//////////////////////////////////////////////////////////
//sysctl
//////////////////////////////////////////////////////////
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
int replace_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
  int ReturnValue = 0;
  ReturnValue = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
  if (namelen == 2 && name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_MODEL)) {
    NSLog(@"hook_sysctl name=%p oldp=%p", (void *)name, oldp);
  }
  return ReturnValue;
}
static void hook_sysctl() {
  CallMSHookFunction((void*)sysctl, (void*)replace_sysctl, (void**)&orig_sysctl);
}

//////////////////////////////////////////////////////////
//IMEI Cache
//////////////////////////////////////////////////////////
CHDeclareClass(CTMobileEquipmentInfo);
CHOptimizedMethod1(self, void, CTMobileEquipmentInfo, setIMEI, NSString*, imei) {
  static NSString* MY_IMEI = nil;
  if (MY_IMEI == nil) {
    MY_IMEI = (NSString*)[cf_device objectForKey:@"InternationalMobileEquipmentIdentity"];
    MY_IMEI = [MY_IMEI copy];
  }
  if (MY_IMEI != nil) {
    // NSLog(@"hook_imei:%@:%@", imei, MY_IMEI);
    return CHSuper1(CTMobileEquipmentInfo, setIMEI, MY_IMEI);
  }
  return CHSuper1(CTMobileEquipmentInfo, setIMEI, imei);
}
void CTMobileEquipmentInfo_setIMEI() {
  dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
  CHLoadLateClass(CTMobileEquipmentInfo);
  CHClassHook1(CTMobileEquipmentInfo, setIMEI);
}
//////////////////////////////////////////////////////////
//MEID Cache
//////////////////////////////////////////////////////////
CHDeclareClass(CTMobileEquipmentInfo);
CHOptimizedMethod1(self, void, CTMobileEquipmentInfo, setMEID, NSString*, meid) {
  static NSString* MY_MEID = nil;
  if (MY_MEID == nil) {
    MY_MEID = (NSString*)[cf_device objectForKey:@"MobileEquipmentIdentifier"];
    MY_MEID = [MY_MEID copy];
  }
  if (MY_MEID != nil) {
    return CHSuper1(CTMobileEquipmentInfo, setMEID, MY_MEID);
  }
  return CHSuper1(CTMobileEquipmentInfo, setMEID, meid);
}
void CTMobileEquipmentInfo_setMEID() {
  dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
  CHLoadLateClass(CTMobileEquipmentInfo);
  CHClassHook1(CTMobileEquipmentInfo, setMEID);
}
//////////////////////////////////////////////////////////
//IDFA
//////////////////////////////////////////////////////////
CHDeclareClass(ASIdentifierManager);
CHOptimizedMethod0(self, NSUUID*, ASIdentifierManager, advertisingIdentifier) {
  NSString *configuredIDFA = [cf_device objectForKey:@"IDFA"];
  if (![configuredIDFA isKindOfClass:[NSString class]] || configuredIDFA.length == 0) {
    return CHSuper0(ASIdentifierManager, advertisingIdentifier);
  }
  NSUUID *replacement = [[NSUUID alloc] initWithUUIDString:configuredIDFA];
  if (replacement == nil) return CHSuper0(ASIdentifierManager, advertisingIdentifier);
  return [replacement autorelease];
}
void HOOK_IDFA() {
  CHLoadLateClass(ASIdentifierManager);
  CHClassHook0(ASIdentifierManager, advertisingIdentifier);
}
//////////////////////////////////////////////////////////
//IDFV
//////////////////////////////////////////////////////////
CHDeclareClass(UIDevice);
CHOptimizedMethod0(self, NSUUID*, UIDevice, identifierForVendor) {
  NSString *configuredIDFV = [cf_device objectForKey:@"IDFV"];
  if (![configuredIDFV isKindOfClass:[NSString class]] || configuredIDFV.length == 0) {
    return CHSuper0(UIDevice, identifierForVendor);
  }
  NSUUID *replacement = [[NSUUID alloc] initWithUUIDString:configuredIDFV];
  if (replacement == nil) return CHSuper0(UIDevice, identifierForVendor);
  return [replacement autorelease];
}
void HOOK_IDFV() {
  CHLoadLateClass(UIDevice);
  CHClassHook0(UIDevice, identifierForVendor);
}
static BOOL IsValidKeychainCleanupBundleID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > 255) return NO;
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
  return [value rangeOfCharacterFromSet:invalid].location == NSNotFound &&
         ![value hasPrefix:@"."] && ![value hasSuffix:@"."] && ![value containsString:@".."];
}

static BOOL IsValidKeychainCleanupRequestID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 32) return NO;
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
  return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

typedef CFTypeRef (*ModHWSecTaskCreateFromSelfFn)(CFAllocatorRef allocator);
typedef CFTypeRef (*ModHWSecTaskCopyValueForEntitlementFn)(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);

static NSString *CurrentApplicationIdentifier(void) {
  static void *securityHandle = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    securityHandle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL);
  });

  void *createAddress = securityHandle ? dlsym(securityHandle, "SecTaskCreateFromSelf") : NULL;
  void *copyAddress = securityHandle ? dlsym(securityHandle, "SecTaskCopyValueForEntitlement") : NULL;
  if (createAddress == NULL) createAddress = dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
  if (copyAddress == NULL) copyAddress = dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
  if (createAddress == NULL || copyAddress == NULL) {
    NSLog(@"[mod_hw] SecTask entitlement APIs are unavailable in this OS build.");
    return nil;
  }

  ModHWSecTaskCreateFromSelfFn createTask = (ModHWSecTaskCreateFromSelfFn)createAddress;
  ModHWSecTaskCopyValueForEntitlementFn copyEntitlement = (ModHWSecTaskCopyValueForEntitlementFn)copyAddress;
  CFTypeRef task = createTask(kCFAllocatorDefault);
  if (task == NULL) return nil;
  CFTypeRef entitlement = copyEntitlement(task, CFSTR("application-identifier"), NULL);
  CFRelease(task);
  if (entitlement == NULL) return nil;

  id value = CFBridgingRelease(entitlement);
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static void ProcessPendingKeychainCleanup(void) {
  @autoreleasepool {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!IsValidKeychainCleanupBundleID(bundleID)) return;

    NSString *cacheDirectory = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Caches"];
    NSString *requestPath = [cacheDirectory stringByAppendingPathComponent:@".modhw-keychain-clean.request.plist"];
    NSString *resultPath = [cacheDirectory stringByAppendingPathComponent:@".modhw-keychain-clean.result.plist"];
    struct stat requestStat;
    if (lstat(requestPath.fileSystemRepresentation, &requestStat) != 0 ||
        !S_ISREG(requestStat.st_mode) || requestStat.st_uid != getuid() ||
        (requestStat.st_mode & 0777) != 0600) return;

    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:requestPath];
    if (![request isKindOfClass:NSDictionary.class] ||
        ![request[@"bundleIdentifier"] isEqualToString:bundleID]) return;
    NSString *requestID = request[@"requestID"];
    if (!IsValidKeychainCleanupRequestID(requestID)) return;

    NSMutableArray *itemResults = [NSMutableArray array];
    BOOL overallSuccess = YES;
    NSString *applicationIdentifier = nil;
    NSString *failureReason = nil;

    applicationIdentifier = CurrentApplicationIdentifier();
    NSString *requiredSuffix = [@"." stringByAppendingString:bundleID];
    if (![applicationIdentifier isKindOfClass:NSString.class] ||
        applicationIdentifier.length <= requiredSuffix.length ||
        ![applicationIdentifier hasSuffix:requiredSuffix]) {
      overallSuccess = NO;
      failureReason = @"无法读取或验证目标 App 的 application-identifier Entitlement。";
    } else {
      NSArray *classes = @[
        @{@"name": @"generic-password", @"class": (__bridge id)kSecClassGenericPassword},
        @{@"name": @"internet-password", @"class": (__bridge id)kSecClassInternetPassword},
        @{@"name": @"certificate", @"class": (__bridge id)kSecClassCertificate},
        @{@"name": @"key", @"class": (__bridge id)kSecClassKey},
        @{@"name": @"identity", @"class": (__bridge id)kSecClassIdentity}
      ];
      for (NSDictionary *entry in classes) {
        NSDictionary *query = @{
          (__bridge id)kSecClass: entry[@"class"],
          (__bridge id)kSecAttrAccessGroup: applicationIdentifier,
          (__bridge id)kSecAttrSynchronizable: @NO
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        BOOL okay = status == errSecSuccess || status == errSecItemNotFound;
        if (!okay) overallSuccess = NO;
        [itemResults addObject:@{
          @"class": entry[@"name"],
          @"status": @(status),
          @"success": @(okay)
        }];
      }
    }

    NSMutableDictionary *result = [@{
      @"bundleIdentifier": bundleID,
      @"requestID": requestID,
      @"success": @(overallSuccess),
      @"applicationIdentifier": applicationIdentifier ?: @"",
      @"scope": @"private application-identifier group; local non-synchronizable items only",
      @"items": itemResults,
      @"completedAt": [NSDate date]
    } mutableCopy];
    if (failureReason) result[@"error"] = failureReason;

    BOOL saved = [result writeToFile:resultPath atomically:YES];
    if (saved) {
      [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                       ofItemAtPath:resultPath error:nil];
      unlink(requestPath.fileSystemRepresentation);
      NSLog(@"[mod_hw] Keychain cleanup %@ for %@ (private app-ID group only).",
            overallSuccess ? @"completed" : @"failed", bundleID);
    } else {
      NSLog(@"[mod_hw] Keychain cleanup result could not be saved for %@.", bundleID);
    }
  }
}

//////////////////////////////////////////////////////////
//_MSInitialize
//////////////////////////////////////////////////////////
// UIKit processes are admitted by the Substrate filter, but only processes with a valid profile install hooks.
__attribute__((__constructor__)) static void _MSInitialize(void) {
  ProcessPendingKeychainCleanup();
  initPrefFile();
  if (cf_device == nil || [cf_device count] == 0) {
    NSLog(@"[mod_hw] No valid profile for this process; skipping Hook installation.");
    WriteModHWRuntimeStatus(@"no-valid-profile");
    return;
  }
  dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
  initGlobalSysCtl();
  MobileGestaltHooker();
  hook_sysctlbyname();
  CTMobileEquipmentInfo_setIMEI();
  CTMobileEquipmentInfo_setMEID();
  HOOK_IDFA();
  HOOK_IDFV();
  WriteModHWRuntimeStatus(@"hooks-initialized");
}
//////////////////////////////////////////////////////////
//CoreTelephony
//////////////////////////////////////////////////////////
#define HOOK_CORE_TELEPHONY(RET, ...) HOOK_FUNCTION(RET, /System/Library/Frameworks/CoreTelephony.framework/CoreTelephony, __VA_ARGS__)
// #define FIRMWARE_VERSION "5.30.01"
// #define IMEI             "010113006310121"
// #define ICCID            "310090521813935"
// #define IMSI             "8901090382521813935"
// #define MEID             "A100001AEF8D32"
// #define SubscriberId     "2062760895"
// extern  CFStringRef kCTMobileEquipmentInfoIMEI, kCTMobileEquipmentInfoICCID, kCTMobileEquipmentInfoIMSI, kCTMobileEquipmentInfoMEID;
// extern  CFStringRef kCTMobileEquipmentInfoCurrentSubscriberId, kCTMobileEquipmentInfoCurrentMobileId, kCTMobileEquipmentInfoMIN;


HOOK_CORE_TELEPHONY(CFStringRef, _CTSettingCopyMyPhoneNumber) {
  // NSLog(@"xxxxxxx0");
  return CFSTR("972-364-4415");
}

HOOK_CORE_TELEPHONY(CFStringRef, _CTSIMSupportGetSIMStatus) {
  // NSLog(@"xxxxxxx00");
  return CFSTR("kCTSIMSupportSIMStatusReady");
}

HOOK_CORE_TELEPHONY(CFStringRef, _CTSIMSupportGetSIMTrayStatus) {
  // NSLog(@"xxxxxxx001");
  return CFSTR("kCTSIMSupportSIMTrayInsertedWithSIM");
}

// HOOK_CORE_TELEPHONY(PINT, _CTServerConnectionCopyFirmwareVersion, PCORE_TELEPHONY_ERROR_STATUS Status, PVOID Connection, CFStringRef *FirmwareVersion) {
//   // NSLog(@"xxxxxxx1");
//   PINT Data = __CTServerConnectionCopyFirmwareVersion(Status, Connection, FirmwareVersion);
//   // if (FirmwareVersion != NULL) {
//     // NSLog(@"xxxxxxx1:%@", FirmwareVersion);
//     // *FirmwareVersion = CFStringCreateWithCString(0, FIRMWARE_VERSION, kCFStringEncodingMacRoman);
//     // NSLog(@"xxxxxxx1:%@", FirmwareVersion);
//   // }
//   return Data;
// }

// HOOK_CORE_TELEPHONY(PINT, _CTServerConnectionCopyMobileEquipmentInfo, struct CTResult* Status, CTServerConnectionRef conn, CFMutableDictionaryRef* Dictionary) {
//   CFStringRef Keys[7];
//   CFStringRef Values[7];
//   CFStringRef FirmwareVersion;
//   Keys[0] = kCTMobileEquipmentInfoIMEI;
//   Keys[1] = kCTMobileEquipmentInfoICCID;
//   Keys[2] = kCTMobileEquipmentInfoIMSI;
//   Keys[3] = kCTMobileEquipmentInfoMEID;
//   Keys[4] = kCTMobileEquipmentInfoCurrentMobileId;
//   Keys[5] = kCTMobileEquipmentInfoMIN;
//   Keys[6] = kCTMobileEquipmentInfoCurrentSubscriberId;
//   Values[0] = CFSTR(IMEI);
//   Values[1] = CFSTR(ICCID);
//   Values[2] = CFSTR(IMSI);
//   Values[3] = CFSTR(MEID);
//   Values[4] = CFSTR(MEID);
//   Values[5] = CFSTR(SubscriberId);
//   Values[6] = CFSTR(SubscriberId);
//   NSLog(@"xxxxxxx2");
//   PINT Data = __CTServerConnectionCopyMobileEquipmentInfo(Status, conn, Dictionary);
//   // NSLog(@"MobileEquipmentInfo:%@", Dictionary);
//   Data = $_CTServerConnectionCopyFirmwareVersion(Status, conn, &FirmwareVersion);
//   *Dictionary = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
//   for(INT i = 0; i < 7; i++) {
//     CFDictionaryAddValue(*Dictionary, Keys[i], Values[i]); 
//   }
//   return Data;
// }

// HOOK_CORE_TELEPHONY(PINT, _CTServerConnectionCopyMobileIdentity, PCORE_TELEPHONY_ERROR_STATUS Status, PVOID Connection, CFStringRef *Imei){
//   NSLog(@"xxxxxxx3");
//   PINT Data = __CTServerConnectionCopyMobileIdentity(Status, Connection, Imei);
//   *Imei = CFStringCreateWithCString(0, IMEI, kCFStringEncodingMacRoman);
//   return Data;
// }




// %hook UIDevice

// - (NSString *)systemVersion {
//     return @"15.4.1";
// }

// %end

// %hook NSProcessInfo

// - (NSOperatingSystemVersion)operatingSystemVersion {
//     NSOperatingSystemVersion version;
//     version.majorVersion = 15;
//     version.minorVersion = 4;
//     version.patchVersion = 1;
//     return version;
// }

// %end

// %hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
//     if (strcmp(name, "kern.osversion") == 0) {
//         if (oldp)
//             strcpy((char *)oldp, IOS_BUILD);
//         *oldlenp = strlen(IOS_BUILD);
//     }
//     return %orig(name, oldp, oldlenp, newp, newlen);
// }

// %end