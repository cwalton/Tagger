//
//  MP3Tags.mm
//  VGTagger
//
//  Created by Bilal Syed Hussain on 19/07/2011.
//  Copyright 2011  All rights reserved.
//

#import "MPEGTags.h"
#import "TagStructs.h"
#import "NSString+Convert.h"
#import "NSImage+bitmapData.h"
#include "TagPrivate.h"

#include <mpegfile.h>
#include <id3v2tag.h> 
#include <id3v2frame.h>
#include <textidentificationframe.h>
#include <attachedPictureFrame.h>
#include <commentsframe.h>

#import "Logging.h"
LOG_LEVEL(LOG_LEVEL_ERROR);

namespace MPEGFields {	// can not be put in the header for some reason
	const char *ALBUM_ARTIST = "TPE2";
	const char *COMPOSER     = "TCOM";
	const char *GROUPING     = "TIT1";
	
	const char *COMPILATION  = "TCMP";
	const char *BPM          = "TBPM";
	
	const char *TRACK_NUMBER = "TRCK";
	const char *TOTAL_TRACKS = "TRCK";
	const char *DISK_NUMBER  = "TPOS";
	const char *TOTAL_DISKS  = "TPOS";
	
	const char *ENCODER      = "TENC";
	const char *COVER        = "APIC";
	const char *URL          = "WXXX";
	const char *COMMENT      = "COMM";
}

@interface MPEGTags()
- (NSString*) getFieldWithString:(const char*)field;
- (void) setNumberPair:(const char *)field
			firstValue:(NSNumber*)firstValue
		   secondValue:(NSNumber*)secondValue;
- (BOOL) removeAllImagesMP3:(TagLib::ID3v2::Tag*) tag
					 ofType:(TagLib::ID3v2::AttachedPictureFrame::Type) imageType;
- (BOOL) removeAllImagesMP3:(TagLib::ID3v2::Tag*) tag;
@end

using namespace TagLib;
using namespace MPEGFields;
@implementation MPEGTags

#pragma mark -
#pragma mark init/alloc

- (id) initWithFilename:(NSString *)filename
{
    self = [super initWithFilename:filename];
    if (self) {
		data->f->mpeg = new MPEG::File([filename UTF8String]);
		data->file = data->f->mpeg;
		[self initFields];
		kind = @"MP3";
    }
    
    return self;	
}

-(void) initFields
{	
	[super initFields];
	NSString *temp = nil;
	NSRange   range;
	
	albumArtist = [self getFieldWithString:ALBUM_ARTIST];
	composer    = [self getFieldWithString:COMPOSER];
	grouping    = [self getFieldWithString:GROUPING];
	
	temp        = [self getFieldWithString:BPM];
	bpm         = temp ? [NSNumber numberWithInt:[temp intValue]] : nil;
	
	temp        = [self getFieldWithString:COMPILATION];
	compilation = [NSNumber numberWithBool: temp ? YES : NO];
	
	temp  = [self getFieldWithString:TRACK_NUMBER];
	if (temp){
		range = [temp rangeOfString:@"/" options:NSLiteralSearch];
		
		if(range.location != NSNotFound && range.length != 0) {
			int i = [[temp substringFromIndex:range.location+1] intValue];
			totalTracks	=  i == 0 ? nil : [NSNumber numberWithInt:  i];
		}else{
			totalTracks = nil;
		}	
	}

	temp  = [self getFieldWithString:DISK_NUMBER];
	if (temp){
		range = [temp rangeOfString:@"/" options:NSLiteralSearch];
		
		if(range.location != NSNotFound && range.length != 0) {
			int i = [[temp substringToIndex:range.location] intValue];
			disc        = i == 0 ? nil : [NSNumber numberWithInt:  i];
			i = [[temp substringFromIndex:range.location+1] intValue];
			totalDiscs	= i == 0 ? nil : [NSNumber numberWithInt:  i];
		}else{
			disc       = nil;
			totalDiscs = nil;
		}	
	}	
	
	url = [self getFieldWithString:URL];
	const ID3v2::Tag *tag = data->f->mpeg->ID3v2Tag();
	ID3v2::FrameList listOfMp3Frames = tag->frameListMap()[COVER];
	if (!listOfMp3Frames.isEmpty()){
		ID3v2::AttachedPictureFrame *picture = static_cast<ID3v2::AttachedPictureFrame *>(listOfMp3Frames.front());
		if (picture){
			TagLib::ByteVector bv = picture->picture();
			cover = [[[NSImage alloc] initWithData: [NSData dataWithBytes:bv.data() length:bv.size()]] autorelease];	
		}
	}
	
}

- (void)dealloc
{
    [super dealloc];
}

#pragma mark -
#pragma mark Fields helpers

- (NSString*) getFieldWithString:(const char*)field
{
	const ID3v2::Tag *tag = data->f->mpeg->ID3v2Tag();
	TagLib::ID3v2::FrameList l = tag->frameList(field);
	return l.isEmpty() ? nil : [[NSString  alloc] initWithTagString:l.front()->toString()];
}


- (bool) setFieldWithString:(const char*)field
					   data:(NSString *)newValue
{
	DDLogVerbose(@"%s '%@'", field, newValue);
	(TagLib::ID3v2::FrameFactory::instance())->setDefaultTextEncoding(TagLib::String::UTF8);
	ID3v2::Tag *tag = data->f->mpeg->ID3v2Tag();	
	tag->removeFrames(field);
	//  Total tracks on it own does not work without this
	data->f->mpeg->strip(MPEG::File::ID3v1);
	if(nil != newValue) {
		ID3v2::TextIdentificationFrame *frame = new ID3v2::TextIdentificationFrame(field, TagLib::String::UTF8);
		frame->setText([newValue tagLibString]);
		tag->addFrame(frame);
	}
	return data->file->save();
}

- (void) setNumberPair:(const char *)field
			firstValue:(NSNumber*)firstValue
		   secondValue:(NSNumber*)secondValue
{
	NSString *text = nil;
	if (firstValue != nil && secondValue != nil){
		text = [[NSString alloc] initWithFormat:@"%@/%@",firstValue, secondValue];
		DDLogVerbose(@"1 %@",text);
	}else if (firstValue != nil){
		text = [[NSString alloc] initWithFormat:@"%@/",firstValue];
		DDLogVerbose(@"2 %@",text);
	}else if (secondValue != nil){
		text = [[NSString alloc] initWithFormat:@"/%@",secondValue];
		DDLogVerbose(@"3 %@",text);
	}
	
	[self setFieldWithString:field data:text];		
}

#pragma mark -
#pragma mark Setters

- (void) removeAllTags
{
	DDLogRelease(@"removing tags");
	data->f->mpeg->strip(MPEG::File::ID3v1);
	data->f->mpeg->save(MPEG::File::NoTags, true);
}

- (void) setAlbumArtist:(NSString *)newValue
{ 
	TAG_SETTER_START(albumArtist);
	[self setFieldWithString:ALBUM_ARTIST data:newValue];
}

- (void) setComposer:(NSString *)newValue
{
	TAG_SETTER_START(composer);
	[self setFieldWithString:COMPOSER data:newValue];
}

- (void) setGrouping:(NSString *)newValue
{ 
	TAG_SETTER_START(grouping);
	[self setFieldWithString:GROUPING data:newValue];
}

- (void) setBpm:(NSNumber *)newValue
{
	TAG_SETTER_START(bpm);
	[self setFieldWithString:BPM data:[newValue stringValue]];	
}

- (void) setCompilation:(NSNumber *)newValue
{
	TAG_SETTER_START(compilation);
	[self setFieldWithString:COMPILATION data:[newValue boolValue] ? @"1" : nil ];		
}

- (void) setTrack:(NSNumber *)newValue
{
	TAG_SETTER_START(track);
	[self setNumberPair:TRACK_NUMBER firstValue:track secondValue:totalTracks];
}

- (void) setTotalTracks:(NSNumber *)newValue
{
	TAG_SETTER_START(totalTracks);
	[self setNumberPair:TRACK_NUMBER firstValue:track secondValue:totalTracks];
}

- (void) setDisc:(NSNumber *)newValue
{
	TAG_SETTER_START(disc);
	[self setNumberPair:DISK_NUMBER firstValue:disc secondValue:totalDiscs];
}

- (void) setTotalDiscs:(NSNumber *)newValue
{
	TAG_SETTER_START(totalDiscs);
	[self setNumberPair:DISK_NUMBER firstValue:disc secondValue:totalDiscs];
}

- (void) setUrl:(NSString *)newValue
{
	TAG_SETTER_START(url);
	[self setFieldWithString:URL data:newValue];
}

// need fixing?
- (void) setCover:(NSImage *)newValue
{
	TAG_SETTER_START(cover);
	
	ID3v2::Tag *tag = data->f->mpeg->ID3v2Tag();
	tag->removeFrames(COVER);
	data->f->mpeg->save();
//	[self removeAllImagesMP3:tag];
	if (cover){
	
		ID3v2::AttachedPictureFrame *frame = new TagLib::ID3v2::AttachedPictureFrame;
		frame->setMimeType("image/jpeg");		

		ID3v2::AttachedPictureFrame::Type type =ID3v2::AttachedPictureFrame::FrontCover;
		frame->setType(type);

		NSData *imageData = [cover bitmapDataForType:NSJPEGFileType];
		frame->setPicture(ByteVector((const char *)[imageData bytes], (uint)[imageData length]));	
		
//		[self removeAllImagesMP3:tag ofType:type];
		
		tag->addFrame(frame);

	}	
	data->f->mpeg->save();
}


- (BOOL) removeAllImagesMP3:(TagLib::ID3v2::Tag*) tag
{
	if (tag) {
		TagLib::ID3v2::FrameList frameList= tag->frameList("APIC");
		if (!frameList.isEmpty()){
			std::list<TagLib::ID3v2::Frame*>::const_iterator iter = frameList.begin();
			while (iter != frameList.end()) {
				std::list<TagLib::ID3v2::Frame*>::const_iterator nextIter = iter;
				nextIter++;
				tag->removeFrame(*iter);
				iter = nextIter;
			}
		}
	}
	
	return YES;
}

- (BOOL) removeAllImagesMP3:(TagLib::ID3v2::Tag*) tag
					 ofType:(TagLib::ID3v2::AttachedPictureFrame::Type) imageType
{
	if (tag) {
		TagLib::ID3v2::FrameList frameList= tag->frameList("APIC");
		if (!frameList.isEmpty()){
			std::list<TagLib::ID3v2::Frame*>::const_iterator iter = frameList.begin();
			while (iter != frameList.end()) {
				TagLib::ID3v2::AttachedPictureFrame *frame =
				static_cast<TagLib::ID3v2::AttachedPictureFrame *>( *iter );
				std::list<TagLib::ID3v2::Frame*>::const_iterator nextIter = iter;
				nextIter++;
				if (frame && frame->type() == imageType){
					tag->removeFrame(*iter);
				}
				iter = nextIter;
			}
		}
	}
	
	return YES;
}


- (void) setComment:(NSString *)newValue
{
	TAG_SETTER_START(comment);
	(TagLib::ID3v2::FrameFactory::instance())->setDefaultTextEncoding(TagLib::String::UTF8);
	ID3v2::Tag *tag = data->f->mpeg->ID3v2Tag();	
	tag->removeFrames("COMM");
	if(nil != newValue) {
		ID3v2::CommentsFrame *frame =  new ID3v2::CommentsFrame();
		frame->setText([newValue tagLibString]);
		frame->setLanguage("eng");
		tag->addFrame(frame);
	}
	data->file->save();
}

@end
