#import "SldpHttpParser.h"

@implementation SldpHttpParser

@synthesize statusCode = statusCode;
@synthesize statusText = statusText;
@synthesize header = header;

-(id)initWithDelegate:(id)delegate {
    _delegate = delegate;
    [self reset];
    return self;
}

-(void)reset {
    state = kInterleaved;
    statusCode = -1;
    statusText = nil;
    contentLenght = 0;
    header = [[NSMutableDictionary alloc] init];
    _authBasic = [[NSMutableDictionary alloc] init];
    _authDigest = [[NSMutableDictionary alloc] init];
}


-(Boolean)parse_status_line:(NSString*)s {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"HTTP\\/\\d.\\d\\s+(\\d\\d\\d)\\s+(.+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:s options:0 range:NSMakeRange(0, [s length])];
    
    if(match.numberOfRanges != 3) {
        return false;
    }
    
    NSRange codeRange = [match rangeAtIndex:1];
    statusCode = [[s substringWithRange:codeRange] intValue];
    NSLog(@"code=%d", statusCode);
    
    
    NSRange textRange  = [match rangeAtIndex:2];
    statusText = [s substringWithRange:textRange];
    NSLog(@"text=%@", statusText);
    
    return true;
}

-(NSString*)trimWhiteSpaces:(NSString*)s {
    return [s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
}

-(Boolean)parse_hdr_line:(NSString*)s {

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\S+):\\s?(.*)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:s options:0 range:NSMakeRange(0, [s length])];
    
    if(match.numberOfRanges != 3) {
        return false;
    }
    
    NSRange nameRange = [match rangeAtIndex:1];
    NSString* name = [s substringWithRange:nameRange];
    name = [[self trimWhiteSpaces:name] uppercaseString];
    
    NSRange valueRange = [match rangeAtIndex:2];
    NSString* value = [s substringWithRange:valueRange];
    value = [self trimWhiteSpaces:value];
                      
    if([name caseInsensitiveCompare:@"Content-length"] == NSOrderedSame) {
        contentLenght = value.intValue;
    } else if([name caseInsensitiveCompare:@"WWW-Authenticate"] == NSOrderedSame) {
        // <scheme> <key>="<value>",<key>="<value>",...,<key>="<value>"
        NSRange range = [value rangeOfString:@" "];
        if(range.length == 1) {
        
            //NSString
            
            NSString* authScheme = [value substringToIndex:range.location];
            NSString* authParams = [value substringFromIndex:range.location+1];
            if([authScheme caseInsensitiveCompare:@"Digest"]  == NSOrderedSame) {
                [self parseAuthTo:_authDigest authParams:authParams];
            } else if([authScheme caseInsensitiveCompare:@"Basic"] == NSOrderedSame) {
                [self parseAuthTo:_authBasic authParams:authParams];
            } else {
                NSLog(@"unsupported auth scheme=%@", authScheme);
            }
        }
        
    } else {
        header[name] = value;
    }
    return true;
}

-(void)parseAuthTo:(NSMutableDictionary*)dst authParams:(NSString*)authParams {
    NSArray* paramList = [authParams componentsSeparatedByString:@","];
    for(int i = 0; i < paramList.count; i++) {
    
        NSString* param = paramList[i];
        NSRange range = [param rangeOfString:@"="];
        if(range.length != 1) {
            continue;
        }
        
        NSString* paramName = [self trimWhiteSpaces:[param substringToIndex:range.location]];
        if(paramName.length <= 0) {
            continue;
        }
        paramName = [[self trimWhiteSpaces:paramName] uppercaseString];
        
        NSString* paramValue = [self trimWhiteSpaces:[param substringFromIndex:range.location + 1]];
        paramValue = [paramValue stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        
        dst[paramName] = paramValue;
    }
}

-(int)get_line:(Byte*)buffer offset:(int)offset len:(int)len result:(NSString**)result  {
    Boolean cr = false;
    
    for(int i = offset; i < len; i++) {
        
        if(cr && buffer[i] == '\n') {
            *result = [[NSString alloc] initWithBytes:(buffer + offset) length: (i - offset - 1) encoding:NSASCIIStringEncoding];
            return i - offset + 1;
        }
        
        cr = false;
        if(buffer[i] == '\r') {
            cr = true;
        }
    }
    return -1;
}

-(int)parse:(Byte*)buffer length:(int)len {
    int offset = 0;
    
    while(len > 0) {
        
        int parsed = 0;
        
        switch (state) {
            case kInterleaved:
                [self reset];
                
                if (len < 4) {
                    return 0;
                } else if (buffer[offset] == 'H' &&
                           buffer[offset + 1] == 'T' &&
                           buffer[offset + 2] == 'T' &&
                           buffer[offset + 3] == 'P') {
                    state = kStatusLine;
                } else {
                    return offset;
                }
                break;
                
            case kStatusLine:
            {
                NSString* statusLine = nil;
                parsed = [self get_line:buffer offset:offset len:len result: &statusLine];
                if (-1 == parsed) {
                    // no crlf found
                    return offset;
                }
                offset += parsed;
                
                if (![self parse_status_line:statusLine])  {
                    NSLog(@"unable to parse status line %@", statusLine);
                    state = kInterleaved;
                    return -1;
                }
                state = kHeaderLine;
                break;
            }
                
            case kHeaderLine:
            {
                NSString* headerLine = nil;
                parsed = [self get_line:buffer offset:offset len:len result:&headerLine];
                if (-1 == parsed) {
                    // no crlf found
                    return offset;
                }
                offset += parsed;
                
                if(headerLine != nil && headerLine.length > 0) {
                    if(![self parse_hdr_line:headerLine]) {
                        NSLog(@"unable to parse header line: %@", headerLine);
                        state = kInterleaved;
                        return -1;
                    }
                } else {
                    // header complete
                    if(contentLenght > 0) {
                        state = kBody;
                    } else {
                        [_delegate onComplete:self];
                        
                        state = kInterleaved;
                        return offset;
                    }
                }
                break;
            }
            case kBody:
                if(len < contentLenght) {
                    // wait for the whole body
                    return offset;
                }
                
                // TBD process body
                
                offset += contentLenght;
                [_delegate onComplete:self];
                
                state = kInterleaved;
                return offset;
                
            default:
                break;
        }
        
    }
    return 0;
}
@end
