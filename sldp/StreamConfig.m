#import "StreamConfig.h"

const int SLDP_SRT_MIN_PASSPHRASE_LEN = 10;
const int SLDP_SRT_MAX_PASSPHRASE_LEN = 80;
const int SLDP_SRT_MAX_STREAMID_LEN = 512;


@implementation StreamConfig : NSObject

-(id)init {
    self = [super init];
    if (self) {
        _uri = [[NSURL alloc]init];
        _buffering = 1500;
        _threshold = 1000;
        _mode = kSldpStreamModeVideoAudio;
        _connectMode = kPlayerSrtConnectModePull;
        _preferredBitrate = 65 * 1000;
        _disableMediaSync = false;
        _externalDecoding = false;
        _videoChatMode = false;
    }
    return self;
}

-(id _Nullable)init:(NSURL* _Nonnull)url  {
    return [self init: url parseQuery:true];
}


-(id _Nullable)init:(NSURL* _Nonnull)url parseQuery:(BOOL) parseQuery {
    self = [super init];
    if (self) {
        _uri = url;
        _buffering = 1500;
        _threshold = 1000;
        _mode = kSldpStreamModeVideoAudio;
        _connectMode = kPlayerSrtConnectModePull;
        _preferredBitrate = 65 * 1000;
        _disableMediaSync = false;
        _externalDecoding = false;
        _videoChatMode = false;
        
        if (parseQuery == false || url.query == nil || url.query.length == 0) {
            return self;
        }
        
        NSURLComponents* urlComp = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
        if (urlComp == nil) {
            return nil;
        }
        //BOOL isSrt = [urlComp.scheme isEqualToString:@"srt"];
        NSMutableArray<NSURLQueryItem*>* remainItems = [[NSMutableArray alloc]init];
        for (NSURLQueryItem* item in urlComp.queryItems) {
            BOOL keepItem = NO;
            if ([item.name isEqualToString:@"buffering"]) {
                int buffering = [item.value intValue];
                if (buffering > 0) {
                    _buffering = buffering;
                }
            } else if ([item.name isEqualToString:@"offset"]) {
                _offset = [item.value intValue];
            } else if ([item.name isEqualToString:@"bitrate"]) {
                _preferredBitrate = [item.value intValue];
            } else if ([item.name isEqualToString:@"steady"]) {
                _steady = [item.value boolValue];
            } else if ([item.name isEqualToString:@"mode"]) {
                if ([item.value isEqualToString:@"rendezvous"]) {
                    _connectMode = kPlayerSrtConnectModeRendezvous;
                } else if ([item.value isEqualToString:@"listener"]) {
                    _connectMode = kPlayerSrtConnectModeListen;
                } else {
                    _connectMode = kPlayerSrtConnectModePull;
                }
            } else if ([item.name isEqualToString:@"latency"]) {
                int latency = [item.value intValue];
                if (latency > 0) {
                    _latency = latency;
                }
            } else if ([item.name isEqualToString:@"maxbw"]) {
                int maxbw = [item.value intValue];
                if (maxbw > 0) {
                    _maxbw = maxbw;
                }
            } else if ([item.name isEqualToString:@"pbkeylen"]) {
                int keylen = [item.value intValue];
                if (keylen == 16 || keylen == 24 || keylen == 32) {
                    _pbkeylen = keylen;
                }
            } else if ([item.name isEqualToString:@"passphrase"]) {
                _passphrase = item.value;
            } else if ([item.name isEqualToString:@"streamid"]) {
                _streamid = item.value;
            } else {
                keepItem = YES;
                if (![item.name isEqualToString:@"wmsAuthSign"]) {
                    NSLog(@"Unknown parameter: %@", item.name);
                }
            }
            if (keepItem) {
                [remainItems addObject:item];
            }
        }
        NSURLComponents* urlCopy = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
        urlCopy.queryItems = remainItems;
        _uri = urlCopy.URL;
    }
    return self;

}

@end
