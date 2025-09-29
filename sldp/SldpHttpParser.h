#import <Foundation/Foundation.h>

@class SldpHttpParser;

@protocol SldpHttpParserDelegate <NSObject>
@required
-(void)onComplete:(SldpHttpParser*)httpParser;
@end

typedef NS_ENUM(NSUInteger, SldpHttpParserState) {
    kInterleaved,
    kStatusLine,
    kHeaderLine,
    kBody
};

@interface SldpHttpParser : NSObject {
    __weak id _delegate;
    SldpHttpParserState state;
    int statusCode;
    NSString* statusText;
    int contentLenght;
    NSMutableDictionary* header;
}

@property (readonly)int statusCode;
@property (readonly)NSString* statusText;
@property (readonly)NSMutableDictionary* header;
@property (readonly)NSMutableDictionary* authDigest;
@property (readonly)NSMutableDictionary* authBasic;

-(id)initWithDelegate:(id)delegate;
-(int)parse:(Byte*)buffer length:(int)len;
@end
