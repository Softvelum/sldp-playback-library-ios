#import "SldpTcpConnection.h"

static const int INIT_RCV_SIZE = 254 * 1024;
static const int MAX_RCV_SIZE = 4 * 1024 * 1024;
static const int MAX_SND_SIZE = 8 * 1024;

@implementation SldpTcpConnection {
    
    SldpByteBuffer* outBuffer;
    SldpByteBuffer* inBuffer;

    bool useSSL_;
    NSRunLoop* _runLoop;
}

- (id)initWithConnectionId:(int)connectionId host:(NSString*)host port:(int)port useSSL:(bool)useSSL mode:(SldpStreamMode)mode connectionListener:(id<SldpConnectionListener>) connectionListener {
    NSLog(@"Connection::initWithConnectionId:%d host:%@ port:%d mode:%d useSSL:%d", connectionId, host, port, mode, useSSL);
    
    self = [super initWithConnectionId: connectionId host:host port:port mode:mode connectionListener:connectionListener];

    useSSL_ = useSSL;
    
    inBuffer  = [[SldpByteBuffer alloc] initWithCapacity: INIT_RCV_SIZE bufferLimit:MAX_RCV_SIZE];
    outBuffer = [[SldpByteBuffer alloc] initWithCapacity: MAX_SND_SIZE];
        
    _streamConnectionQueue = dispatch_queue_create("com.softvelum.larix.stream.connection_queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0));
    _dataQueue = dispatch_queue_create("com.softvelum.larix.stream.data_queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0));
    
    nw_parameters_configure_protocol_block_t configure_tls = NW_PARAMETERS_DISABLE_PROTOCOL;
    if (useSSL_) {
        _verifyQueue = dispatch_queue_create("com.softvelum.larix.stream.verify_queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0));
        
        configure_tls = ^(nw_protocol_options_t tls_options) {
            sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls_options);
            sec_protocol_options_set_verify_block(options, ^(sec_protocol_metadata_t metadata, sec_trust_t trust_ref, sec_protocol_verify_complete_t sec_protocol_verify_complete) {
                // forget safety, trust anyone
                sec_protocol_verify_complete(true);
            }, self.verifyQueue);
        };
    }
    
    nw_parameters_configure_protocol_block_t configure_tcp = ^(nw_protocol_options_t tcp_options) {
        nw_tcp_options_set_connection_timeout(tcp_options, 10);
    };
    
    nw_connection_state_changed_handler_t state_handler = ^(nw_connection_state_t state, nw_error_t error) {
        NSLog(@"-> tcp %d", state);
        switch (state) {
            case nw_connection_state_preparing:
                break;
            case nw_connection_state_ready:
                [self startInactivityTimer];
                [self OnConnect];
                [self receiveLoop];
                break;
            case nw_connection_state_waiting:
            case nw_connection_state_failed:
                [self Close];
                break;
            case nw_connection_state_invalid:
            case nw_connection_state_cancelled:
                break;
        }
    };
    
    const char *host_str = [host UTF8String];
    const char *port_str = [[@(port) stringValue] UTF8String];
    
    nw_endpoint_t endpoint = nw_endpoint_create_host(host_str, port_str);
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(configure_tls, configure_tcp);
    
    _streamConnection = nw_connection_create(endpoint, parameters);
    
    if (_streamConnection != nil) {
        nw_connection_set_queue(_streamConnection, _streamConnectionQueue);
        nw_connection_set_state_changed_handler(_streamConnection, state_handler);
    }
    
    nw_connection_start(_streamConnection);

    return self;
}

-(Boolean)Send:(NSString*)s {
    
    NSData* data = [s dataUsingEncoding:[NSString defaultCStringEncoding]];

    return [self Send: data.bytes length:(int)data.length];
}

-(Boolean)AppendByte:(uint8_t)value {
    return [self Append:&value length:1];
}

-(Boolean)SendByte:(uint8_t)value {
    return [self Send:&value length:1];
}

-(Boolean)Append:(const void*)data length:(int)len {
    if(![outBuffer put: (void*)data len: len]) {
        [self Close];
        return false;
    }
    return true;
}

-(Boolean)Send:(const void*)data length:(int)len {
    
    if(![outBuffer put: (void*)data len: len]) {
        [self Close];
        return false;
    }
    
    [self sendBuffer];
    return true;
}

-(void)sendBuffer {
    if (_streamConnection == nil) return;
    dispatch_data_t d = dispatch_data_create(outBuffer.data, outBuffer.limit, _dataQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    outBuffer.bytesSent += outBuffer.limit;
    [outBuffer skip:outBuffer.limit];
    
    [self resetInactivityTimer];
    
    nw_connection_send(_streamConnection, d, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t _Nullable error) {
        //NSLog(@"Network.framework::send");
        if (error != NULL) {
            //errno = nw_error_get_error_code(error);
            [self Close];
        }
    });


}


-(void)skipRecvBuffer: (int)bytesToSkip {
    [inBuffer skip:bytesToSkip];
}

-(uint64_t)getBytesSent {
    if(nil == outBuffer) {
        return 0;
    }
    return outBuffer.bytesSent;
}

-(uint64_t)getBytesRecv {
    if(nil == inBuffer) {
        return 0;
    }
    return inBuffer.bytesRecv;
}

-(void) Close {
    
    [super Close];

    if (_streamConnection != nil) {
        nw_connection_cancel(_streamConnection);
        _streamConnection = nil;
    }
}

-(void)notifyOnStateChange:(SldpConnectionState)state Status:(int)status {
    [self.connectionListener connectionStateDidChangeId: self.connectionID State:state Status:status];
}

-(NSString*)base64Encode:(NSString *)s {
    NSData* data = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSString* s_base64 = [data base64EncodedStringWithOptions:0];
    return s_base64;
}

- (void)receiveLoop {
    nw_connection_receive(_streamConnection, 1, MAX_RCV_SIZE, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t receive_error) {
        
        dispatch_block_t schedule_next_receive = ^{
            if (is_complete && context != NULL && nw_content_context_get_is_final(context)) {
                return;
            }
            if (receive_error == NULL) {
                [self receiveLoop];
            }
        };
        
        if (content != NULL) {
            const void *buffer = NULL;
            size_t size = 0;
            dispatch_data_t data = dispatch_data_create_map(content, &buffer, &size);
            //NSLog(@"Network.framework::receive");
            if (data != NULL) {
                [self->inBuffer put:(void*)buffer len:(int)size];
                [self resetInactivityTimer];
                [self OnReceive:self->inBuffer];
            }
        }
        schedule_next_receive();
    });
   
}

-(void)notImplemented {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"%@ is not implemented", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)OnConnect {
    [self notImplemented];
}

- (void)OnReceive:(SldpByteBuffer*)buffer {
    [self notImplemented];
}


-(void)sendPlayWithStreams:(NSArray<SldpPlayRequest*>*)playRequests {
    [self notImplemented];
}

-(void)sendCancelWithStreams:(NSArray*)streams {
    [self notImplemented];
}

-(NSDictionary*)getStreams {
    [self notImplemented];
    return @{};
}



@end
