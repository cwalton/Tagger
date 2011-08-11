//
//  NSString+Convert.m
//  VGTagger
//
//  Created by Bilal Syed Hussain on 15/07/2011.
//  Copyright 2011  All rights reserved.
//

#import "NSString+Convert.h"

@implementation NSString (NSString_Convert)

- (NSString*) initWithTagString:(TagLib::String) cppString
{
	return [[NSString alloc] initWithUTF8String:cppString.toCString(true)];
}

+ (NSString*) stringWithTagString:(TagLib::String) cppString
{
	return [NSString stringWithUTF8String: cppString.toCString(true)];
}

- (TagLib::String) tagLibString
{
	TagLib::String s = TagLib::String([self UTF8String], TagLib::String::UTF8);
	return s;
}

- (NSString*) initWithCppString:(std::string*) cppString
{
	return [[NSString alloc] initWithUTF8String:cppString->c_str() ];
}

- (std::string*) cppString
{
	std::string *s  = new std::string([self UTF8String]);
	return s;
}


@end