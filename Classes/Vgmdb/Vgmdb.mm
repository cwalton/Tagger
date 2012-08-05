//
//  Vgmdb.m
//  Tagger
//
//  Created by Bilal Hussain on 23/07/2012.
//  Copyright (c) 2012 All rights reserved.
//

#include <AvailabilityMacros.h>
#include <TargetConditionals.h>

#import "Vgmdb.h"
#import "Vgmdb+private.h"

#import "NSString+Convert.h"
#import "NSString+Regex.h"
#import "RegexKitLite.h"

#import "Logging.h"
LOG_LEVEL(LOG_LEVEL_VERBOSE);

#include <string>
#include <iostream>
#include <set>
#include <list>
#include <map>

#include <htmlcxx/html/ParserDom.h>

#include "hcxselect.h"
#include "VgmdbStruct.h"


static const NSDictionary *namesMap;

using namespace std;
using namespace hcxselect;


@implementation Vgmdb

#pragma mark -
#pragma mark init


- (id)init
{
    self = [super init];
    if (self) {

    }
    return self;
}

+ (void)initialize
{
    namesMap = [NSDictionary dictionaryWithObjectsAndKeys:
                @"@english", @"en",
                @"@kanji",   @"ja",
                @"@romaji",  @"ja-Latn",
                @"@english", @"English",
                @"@kanji",   @"Japanese",
                @"@romaji",  @"Romaji",
                @"latin",    @"",
                nil];
}

#pragma mark -
#pragma mark Searching 

- (NSArray*) searchResults:(NSString*)search
{
    NSString *baseUrl = @"http://vgmdb.net/search?q=";
    NSString *tmp = [baseUrl stringByAppendingString:search];
    NSString *_url = [tmp stringByAddingPercentEscapesUsingEncoding:NSUnicodeStringEncoding];
    NSError *err = nil;
    string *html  = [self cppstringWithContentsOfURL:[NSURL URLWithString:_url]
                                              error:&err];
    
    if (!err){
        htmlcxx::HTML::ParserDom parser;
        tree<htmlcxx::HTML::Node> dom = parser.parseTree(*html);
        Selector s(dom);
        
        NSMutableArray *rows = [[NSMutableArray alloc] init];
        
        Selector res = s.select("div#albumresults tbody > tr");
//        cout << "Selector num:" << res.size() << "\n";
        
        Selector::iterator it = res.begin();    
        for (; it != res.end(); ++it) {
//            [self printNode:*it inHtml:html];
            
            Node *catalog_td = (*it)->first_child;
            string _catalog = catalog_td->first_child->first_child->data.text();
            NSString *catalog = [[NSString alloc] initWithCppString:&_catalog];
            
            Node *title_td = catalog_td->next_sibling->next_sibling;
            Node *first_title = title_td->first_child->first_child;
            NSDictionary *album =[self splitLanguagesInNodes:first_title];
            
            Node *url_a = title_td->first_child;
            url_a->data.parseAttributes();
            map<string, string> att= url_a->data.attributes();
            string _url = att["href"];
            NSString *url = [[NSString alloc] initWithCppString:&_url];
            
            Node *year_td = title_td->next_sibling;
            Node *year_t = year_td;
            while(year_t->data.isTag()){
                year_t = year_t->first_child;
            }
            
            
            string _year = year_t->data.text();
            NSString *year = [[NSString alloc] initWithCppString:&_year];

            [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                             catalog, @"catalog" ,
                             year,    @"released",
                             album,   @"album",
                             url,     @"url",
                             nil]];
        }
        
        return rows; 
        
    }else {
        DDLogInfo(@"%@", [err localizedFailureReason]);
    }
    
    return [NSArray new];
}

#pragma mark -
#pragma mark Album data


- (NSDictionary*)getAlbumData:(NSURL*) url
{
    NSMutableDictionary *data = [NSMutableDictionary new];
    
    NSError *err;
    string *html = [self cppstringWithContentsOfURL:url error:&err];
    
    if (html == NULL){
        NSLog(@"Error %@", [err localizedDescription]);
        return data;
    }
    
    htmlcxx::HTML::ParserDom parser;
    tree<htmlcxx::HTML::Node> dom = parser.parseTree(*html);
    Selector s(dom);
    
    [data setValue:[self getAlbumTitles:dom forHtml:*html]
            forKey:@"album"];
    
    [self storeMetadata:dom forHtml:*html in:data];
    [self storeNotes:dom forHtml:*html in:data];
    [self storeTracks:dom forHtml:*html in:data];

    
    [data setValue:url forKey:@"url"];
    return data;
}


- (void) storeTracks:(const tree<htmlcxx::HTML::Node>&)dom
            forHtml:(const std::string&)html
                 in:(NSDictionary*)data
{
    
    Selector s(dom);
    NSMutableArray *refs = [NSMutableArray new];
    Selection res = s.select("ul#tlnav>li>a");
    
    for (Selector::iterator it = res.begin(); it != res.end(); ++it) {
        Node *n =*it;
        string text =n->first_child->data.text();
        
        NSString *_lang = [NSString stringWithCppStringTrimmed:&text];
        NSString *lang = [namesMap objectForKey:_lang];

        
        n->data.parseAttributes();
        map<string, string> att= n->data.attributes();
        map<string, string>::iterator itLang= att.find("rel");
        
        string _rel  = itLang->second;
        NSString *rel =  [NSString stringWithCppStringTrimmed:&_rel];
        
        NSDictionary *map = @{ @"lang" : lang, @"ref" : rel };
        [refs addObject:map];
    }
    
    for (NSDictionary *ref in refs) {
        NSString *_sel = [NSString stringWithFormat:@"span#%@>table", [ref valueForKey:@"ref"]];
        
        string *sel = [_sel cppString];
        Selector discTables = s.select(*sel);
        delete sel;
        
        unsigned long num_discs = discTables.size();
        [data setValue:@(num_discs) forKey:@"totalDiscs"];
        
        int disc_num = 1;
        for (Selector::iterator it = discTables.begin(); it != discTables.end(); ++it) {
            Node *disc = *it;
            Node *track_tr = disc->first_child;
            
            while (track_tr) {
                if (!track_tr->data.isTag()) {
                    track_tr = track_tr->next_sibling;
                    continue;
                }
                
                Node *track_num = track_tr->first_child->next_sibling;
                string _num = track_num->first_child->first_child ->data.text();
                long num = strtol(_num.c_str(),NULL, 10);
                
                
                
                track_tr = track_tr->next_sibling;
            }
            
            
            disc_num++;
        }
        
    }
    
}


- (void) storeNotes:(const tree<htmlcxx::HTML::Node>&)dom
            forHtml:(const std::string&)html
                    in:(NSDictionary*)data
{
    Selector s(dom);
    Selector res = s.select("div.page > table > tr > td > div > div[style].smallfont");
    
    string buf;
    Node *n = *res.rbegin();
    n = n->first_child;
    
    while (n){
        if (!n->data.isTag()){
            buf.append( n->data.text());
        }else if(n->data.tagName().compare("br") ==0){
            buf.append("\n");
        }
        n= n->next_sibling;
    }
    
    NSString *notes = [[NSString stringWithCppStringTrimmed: &buf] stringByDecodingXMLEntities];
    [data setValue:notes forKey:@"comment"];
}

- (NSDictionary*) getAlbumTitles:(const tree<htmlcxx::HTML::Node>&)dom
                         forHtml:(const std::string&)html
{
    Selector s(dom);
    Selector res = s.select("h1>span.albumtitle");
    Node *n = *res.begin();
//    [self printNode:n inHtml:html];
    NSDictionary *titles = [self splitLanguagesInNodes:n];
    
    return titles;
}


string _html;

- (void) storeMetadata:(const tree<htmlcxx::HTML::Node>&)dom
               forHtml:(const std::string&)html
                in:(NSDictionary*)data
{

    _html = html;
    Selector s(dom);
    Selector meta = s.select("table#album_infobit_large");
    
    /* Catalog */
    Selector catalogElem = meta.select("tr td[width='100%']");
    Node *ncat = *catalogElem.begin();
    
    string _catalog = ncat->first_child->data.text();
    NSString *catalog = [NSString stringWithCppStringTrimmed:&_catalog];
    [data setValue:catalog forKey:@"catalog"];
    
    Node *m = *meta.begin();
    
    // Get the text value of the specifed node
    NSString* (^get_data)(Node*) = ^(Node *n){
        Node *m = n->last_child;
        while (m->data.isTag()) {
            m = m ->first_child;
        }
        string temp =  m->data.text();
        return [NSString stringWithCppStringTrimmed:&temp];
	};
    
    Node *ndate = m->first_child->next_sibling->next_sibling->next_sibling;
    NSString *date = get_data(ndate);
    [data setValue:date forKey:@"date"];
    
    NSRegularExpression* dateRegex = [NSRegularExpression regularExpressionWithPattern:@"\\d{4}$"
                                                                               options:0
                                                                                 error:nil];
    NSTextCheckingResult *yresult =[dateRegex firstMatchInString:date
                                                    options:0
                                                      range:NSMakeRange(0, [date length])];
    NSString *year = [date substringWithRange:yresult.range];
    [data setValue:year forKey:@"year"];
    
    
    Node *npub = ndate->next_sibling->next_sibling;
    NSString *pub = get_data(npub);
    [data setValue:[self spiltMutiMetadataString:pub] forKey:@"publishedFormat"];
    
    Node *nprice = npub->next_sibling->next_sibling;
    [data setValue:get_data(nprice) forKey:@"price"];

    Node *nfor = nprice->next_sibling->next_sibling;
    [data setValue:get_data(nfor) forKey:@"mediaFormat"];
    
    Node *nclas = nfor->next_sibling->next_sibling;
    NSString *clas = get_data(nclas);
    [data setValue:[self spiltMutiMetadataString:clas] forKey:@"classification"];
    
    Node *npubl = nclas->next_sibling->next_sibling;
    [data setValue: [self get_spilt_data:npubl] forKey:@"publisher"];
    
    Node *ncom = npubl->next_sibling->next_sibling;
    NSArray *com = [self get_spilt_data:ncom];
    [data setValue: com forKey:@"composer"];
    [data setValue: com forKey:@"artist"];
    
    Node *narr = ncom->next_sibling->next_sibling;
    [data setValue: [self get_spilt_data:narr] forKey:@"arranger"];
    
    Node *nper = narr->next_sibling->next_sibling;
    [data setValue: [self get_spilt_data:nper] forKey:@"performer"];
    
    Selector stats = s.select("td#rightcolumn  div.smallfont");
    Node *nstats = *stats.begin();
    
    Node *nrat = nstats->first_child->next_sibling;
    string _rat = nrat->last_child->prev_sibling->first_child-> data.text();
    [data setValue:[NSString stringWithCppStringTrimmed:&_rat] forKey:@"rating"];
    
    
    Node *ncoll = nrat->next_sibling->next_sibling;
    
    Node *nwish = ncoll->next_sibling->next_sibling;

    Node *ngenre = nwish->next_sibling->next_sibling;
    string _genre = ngenre->last_child->data.text();
    NSArray *genres = @[[NSString stringWithCppStringTrimmed:&_genre]];
    [data setValue:genres forKey:@"genre"];
    [data setValue:genres forKey:@"category"];
    
    Node *nprod = ngenre->next_sibling->next_sibling;
    NSMutableArray *prods = [NSMutableArray new];
    Node *current = nprod->first_child;
    while (current) {
        if ( current->data.tagName().compare("a") ==0){
            [prods addObject:[self splitLanguagesInNodes: current->first_child]];
        }
        else if(!current->data.isTag()){
            string s = current->data.text();
            NSString *prod = [NSString stringWithCppStringTrimmed:&s];
            if ([prod hasVaildData]){
                [prods addObject:@{@"@english": prod}];
            }
        }
        
        current = current->next_sibling;
    }
    [data setValue:prods forKey:@"products"];
    
    Node *nplat = nprod->next_sibling->next_sibling;
    if (nplat->last_child){
        string _plat = nplat->last_child->data.text();
        NSString *plat = [NSString stringWithCppStringTrimmed:&_plat];
        [data setValue:[self spiltMutiMetadataString:plat] forKey:@"platforms"];
    }
    
}
 
- (NSArray*)get_spilt_data:(Node *)n
{
    NSMutableArray *arr = [NSMutableArray new];
    Node *current = n->last_child->first_child;
    
    while (current) {
        if (!current) {
            current = current->next_sibling;
            continue;
        }else if (!current->data.isTag()){
            string _text = current->data.text();
            NSString *text = [NSString stringWithCppStringTrimmed:&_text];
            if ([text hasVaildData]){
                NSString *result = [text stringByReplacingOccurrencesOfRegex:@", *" withString:@""];
                if (![text isMatchedByRegex:@"^\\("]){
                    [arr addObject:@{ @"@english" : result }];
                    current = current->next_sibling;
                    continue;
                }
            }
        }
        
        if (!current->next_sibling) { // Only Text
            Node *m = current;
            while (m->data.isTag()) {
                m = m ->first_child;
            }
            string _text = m->data.text();
            NSString *text = [NSString stringWithCppStringTrimmed:&_text];
            if ([text hasVaildData]){
                [arr addObject:@{ @"@english" : text }];
            }
        }else{
            Node *first_lang = current->first_child;
            NSDictionary *results = [self splitLanguagesInNodes:first_lang];
            if ([results count] != 0){
                [arr addObject:results];
            }
        }
        current = current->next_sibling;
    }
    return arr;
  
        
    
};

#pragma mark -
#pragma mark Common

// String multiple values in a string into an array.
- (NSArray*) spiltMutiMetadataString:(NSString *)metadata
{
    if (!metadata) return nil;
    NSArray *arr = [metadata componentsSeparatedByRegex:@"[,&] ?"];
    if ([arr count] != 0){
        return arr;
    }else{
        return @[[metadata trimWhiteSpace]];
    }
}

- (NSDictionary*)splitLanguagesInNodes:(Node*)node
{
    NSMutableDictionary *titles= [NSMutableDictionary new];
    while (node) {
        // for text only node
        if (!node->data.isTag()){
            string _title = node->data.text();
            NSString *title = [NSString stringWithCppStringTrimmed:&_title];
            if([title hasVaildData]){
                [titles setValue:title forKey:@"@english"];
                node = node->next_sibling;
                continue;
            }
        }
        
        node->data.parseAttributes();
        map<string, string> att= node->data.attributes();
//        cout << att.size();
        map<string, string>::iterator itLang= att.find("lang");
        
        NSString *lang;
        if (att.end() != itLang){
            string _lang  = itLang->second;
            lang = [[NSString alloc] initWithCppString:&_lang];
            lang = [namesMap valueForKey:lang];
        }else{
            lang = @"@english";
        }
        
        if (node->first_child){
            Node *titleNode = node->first_child;
            while(titleNode->data.isTag()){
                if (!titleNode->next_sibling){
                    titleNode = titleNode->first_child;
                }else{
                    titleNode = titleNode->next_sibling;
                }
            }
            
            string _title = titleNode->data.text();
            NSString *title = [[NSString alloc] initWithCppString:&_title];
            
            [titles setValue: title forKey:lang];
        }
        
        node = node->next_sibling;
    }
    return titles;
}

#pragma mark -
#pragma mark Html helpers  

- (void)printNode:(Node*)node
           inHtml:(std::string)html
{
    cout << html.substr(node->data.offset(), node->data.length()) << "\n\n\n";
}

- (std::string*) cppstringWithContentsOfURL:(NSURL*)url
                                     error:(NSError**)error
{
    NSString *_html = [NSString stringWithContentsOfURL: url
                                               encoding:NSUTF8StringEncoding
                                                  error:error];
    if (!(*error)){
        return new string([_html UTF8String]);
    }
    return NULL;
}

@end
