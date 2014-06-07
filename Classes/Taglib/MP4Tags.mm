//
//  MP4Tags.m
//  Tagger
//
//  Created by Bilal Syed Hussain on 14/07/2011.
//  Copyright 2011  All rights reserved.
//

#import "MP4Tags.h"
#import "TagStructs.h"
#import "NSString+Convert.h"
#import "NSString+Tag.h"
#import "NSImage+bitmapData.h"
#import "Fields.h"
#include "TagPrivate.h"

#include <mp4tag.h> 
#include <mp4file.h>

#import <AVFoundation/AVFoundation.h>

#import "Logging.h"
LOG_LEVEL(LOG_LEVEL_VERBOSE);


using namespace TagLib;
using namespace std;
@implementation MP4Tags

#pragma mark -
#pragma mark init/alloc

- (id) initWithFilename:(NSString *)filename
{
    self = [super initWithFilename:filename];
    if (self) {
		kind = @"MP4";
		data->f->mp4 = new MP4::File([filename UTF8String]);
		data->file = data->f->mp4;
		[self initFields];
    }
    
    return self;	
}

-(void) initFields
{
    NSMutableDictionary *metadata = [self dictionaryAssetWithURL:self.fileUrl];
    DDLogVerbose(@"metadata %@", metadata);
    
    self.metadata = metadata;
    
    title = metadata[AVMetadataiTunesMetadataKeySongName];
    
    NSData *d;
    d=metadata[AVMetadataiTunesMetadataKeyTrackNumber];
    track = @(intgerForDataWithRange(d, 0, 4));
    totalTracks = @(intgerForDataWithRange(d, 4, 2));
    
    d=metadata[AVMetadataiTunesMetadataKeyDiscNumber];
    disc = @(intgerForDataWithRange(d, 0, 4));
    totalDiscs = @(intgerForDataWithRange(d, 4, 2));
    
    DDLogVerbose(@"end initFields");
    
}

    
# pragma mark Read/Write

- (void) setTitle:(NSString *)newValue
{
    TAG_SETTER_START(title);
    self.metadata[AVMetadataiTunesMetadataKeySongName] = title;
    [self writeMeta];
}

- (void) setTrack:(NSNumber *)newValue
{
	TAG_SETTER_START(track);
    NSData *trackData = dataForIntegerPair( [track unsignedIntegerValue], [totalTracks unsignedIntegerValue]);
    self.metadata[AVMetadataiTunesMetadataKeyTrackNumber] =trackData;
    [self writeMeta];
}

- (void) setTotalTracks:(NSNumber *)newValue
{
	TAG_SETTER_START(totalTracks);
    NSData *trackData = dataForIntegerPair( [track unsignedIntegerValue], [totalTracks unsignedIntegerValue]);
    self.metadata[AVMetadataiTunesMetadataKeyTrackNumber] =trackData;
    [self writeMeta];
}

- (void) setDisc:(NSNumber *)newValue
{
	TAG_SETTER_START(disc);
    NSData *trackData = dataForIntegerPair( [disc unsignedIntegerValue], [totalDiscs unsignedIntegerValue]);
    self.metadata[AVMetadataiTunesMetadataKeyDiscNumber] =trackData;
    [self writeMeta];
}

- (void) setTotalDiscs:(NSNumber *)newValue
{
	TAG_SETTER_START(totalDiscs);
    NSData *trackData = dataForIntegerPair( [disc unsignedIntegerValue], [totalDiscs unsignedIntegerValue]);
    self.metadata[AVMetadataiTunesMetadataKeyDiscNumber] =trackData;
    [self writeMeta];
}


#pragma mark AV translate

- (void) writeMeta
{
    BOOL res = [self writeAssetToURL:self.fileUrl
                      withDictionary:self.metadata
                         andFileType:self.fileUrlType
                           andFormat:AVMetadataFormatiTunesMetadata
                         andKeySpace:AVMetadataKeySpaceiTunes];
    
    if (!res){
        DDLogError(@"write failed for %@", self.fileUrl);
    }
}

NSUInteger intgerForDataWithRange(NSData *theData, NSUInteger theLocation, NSUInteger theLength)
{
    if (!theData) return 0;
    NSUInteger i = *(NSInteger*)([theData subdataWithRange:NSMakeRange(theLocation, theLength)].bytes);
    return (NSUInteger)((theLength < 4) ? EndianU16_BtoN(i) : EndianU32_BtoN(i));
}

NSData *dataForInteger(NSUInteger theInteger)
{
    int i = (sizeof(theInteger) < 4) ? EndianU16_NtoB(theInteger) : EndianU32_NtoB(theInteger);
    return [NSData dataWithBytes:&i length:sizeof(i)];
}

NSData *dataForIntegerPair(NSUInteger fst, NSUInteger snd)
{
    int i = (sizeof(fst) < 4) ? EndianU16_NtoB(fst) : EndianU32_NtoB(fst);
    //  second byte is the inverse order
    int k = (sizeof(fst) < 4) ? EndianU32_NtoB(snd) : EndianU16_NtoB(snd);

    NSMutableData *mut = [NSMutableData  dataWithBytes:&i length:sizeof(i)];
    [mut appendBytes:&k length:sizeof(k)];
    return mut;
}


#pragma mark AV

- (BOOL)writeAssetToURL:(NSURL *)theURL
          withDictionary:(NSDictionary *)assetDict
             andFileType:(NSString *)theFileType
               andFormat:(NSString *)theAVFormat
             andKeySpace:(NSString *)theKeySpace
{
    
    DDLogVerbose(@"writeAssetToURL");
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:theURL options:nil];
    if (!asset || ![asset isExportable]) {
        DDLogVerbose(@"Not isExportable");
        return NO;
    }
    AVAssetExportSession *session = [AVAssetExportSession
                                     exportSessionWithAsset:asset
                                     presetName:AVAssetExportPresetPassthrough];
    
    if (![[session supportedFileTypes] containsObject:theFileType]) {
        DDLogVerbose(@"Not supportedFileTypes");
        return NO;
    }
    
    NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sadasdasdasd"];
    NSURL *exportUrl = [NSURL fileURLWithPath:exportPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:exportPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:exportPath error:nil];
    }
    
    NSMutableDictionary *mutableMetadataDict = [NSMutableDictionary dictionaryWithDictionary:assetDict];
    
    DDLogVerbose(@"load mutableMetadataDict: %@", mutableMetadataDict);
    
    [mutableMetadataDict removeObjectForKey:@"com.apple.iTunes.iTunSMPB"];
    [mutableMetadataDict removeObjectForKey:@"com.apple.iTunes.iTunMOVI"];
    [mutableMetadataDict removeObjectForKey:@"com.apple.iTunes.iTunNORM"];
    [mutableMetadataDict removeObjectForKey:@"meta"];

    
    NSMutableArray *newMetadata = [NSMutableArray array];
    for (id key in [mutableMetadataDict keyEnumerator]) {
		id value = [mutableMetadataDict objectForKey:key];
		if (value) {
			AVMutableMetadataItem *newItem = [AVMutableMetadataItem metadataItem];
			newItem.key = key;
			if (nil != theKeySpace) {
				newItem.keySpace = theKeySpace;
			}
			else {
				newItem.keySpace = AVMetadataKeySpaceCommon;
			}
			newItem.value = value;
			[newMetadata addObject:newItem];
		}
	}
    DDLogVerbose(@"load newMetadata: %@", newMetadata);
    session.outputURL      = exportUrl;
    session.outputFileType = theFileType;
    session.metadata       = newMetadata;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block BOOL result   = NO;
    [session exportAsynchronouslyWithCompletionHandler:^{
        
        switch (session.status) {
            case AVAssetExportSessionStatusFailed:
                
                DDLogVerbose(@"Export Status %@", session.error);
                
                break;
            case AVAssetExportSessionStatusCancelled:
                
                DDLogVerbose(@"Export canceled");
                
                break;
            case AVAssetExportSessionStatusExporting:
                
                DDLogVerbose(@"Export Exporting");
                
                break;
            case AVAssetExportSessionStatusCompleted:
                
                DDLogVerbose(@"Export completed");
                
                result = YES;
                break;
            default:
                break;
        }
        
        if (result) {
            NSError *err;
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:theURL.path]) {
                [fm removeItemAtPath:theURL.path error:&err];
                
                DDLogVerbose(@"Removing file: %@", err);
                
            }
            err = nil;
            [fm moveItemAtURL:exportUrl toURL:theURL error:&err];
            if (err) {
                result = NO;
            }
            
            DDLogVerbose(@"Moving file: %@", err);
            
        }
        
		dispatch_semaphore_signal(semaphore);
    }];
    
    long r = 0;
	do {
        r = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
	} while ( r );
    return result;
}


- (NSMutableDictionary*) dictionaryAssetWithURL:(NSURL *)theURL
{
    AVURLAsset *ast = [AVURLAsset URLAssetWithURL:theURL
                                          options:nil];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *fmt in [ast availableMetadataFormats]) {
		NSArray *items = [ast metadataForFormat:fmt];
		if ([items count]) {
			for (AVMetadataItem *item in items) {
                if (nil != fmt) {
                    NSString *keyAsString = nil;
                    if ([item.key isKindOfClass:[NSString class]]) {
                        keyAsString  = (NSString *)item.key;
                    } else if ([item.key isKindOfClass:[NSNumber class]]) {
                        keyAsString = stringForOSType([(NSNumber *)item.key unsignedIntValue]);
                    } else if ([item.key isKindOfClass:[NSObject class]]) {
                        keyAsString = [(NSObject *)item.key description];
                    } else {
                        // Do nothing.
                    }
                    [dict setObject:item.value forKey:keyAsString];
                } else {
                    [dict setObject:item.value forKey:item.commonKey];
                }
            }
		}
	}
    [dict removeObjectForKey:@"com.apple.iTunes.iTunSMPB"];
    [dict removeObjectForKey:@"com.apple.iTunes.iTunMOVI"];
    [dict removeObjectForKey:@"com.apple.iTunes.iTunNORM"];
    [dict removeObjectForKey:@"meta"];
    [dict removeObjectForKey:@"titl"];
    return dict;
}

NSString *stringForOSType(OSType theOSType)
{
    // Taken from: https://developer.apple.com/library/mac/samplecode/avmetadataeditor/Introduction/Intro.html
    
	size_t len = sizeof(OSType);
	long addr = (unsigned long)&theOSType;
	char cstring[5];
	
	len = (theOSType >> 24) == 0 ? len - 1 : len;
	len = (theOSType >> 16) == 0 ? len - 1 : len;
	len = (theOSType >>  8) == 0 ? len - 1 : len;
	len = (theOSType >>  0) == 0 ? len - 1 : len;
	
	addr += (4 - len);
	
	theOSType = EndianU32_NtoB(theOSType);
	
	strncpy(cstring, (char *)addr, len);
	cstring[len] = 0;
	
	return [NSString stringWithCString:(char *)cstring encoding:NSMacOSRomanStringEncoding];
}




@end
