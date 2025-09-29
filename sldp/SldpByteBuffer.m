#import "SldpByteBuffer.h"

@implementation SldpByteBuffer {
    int _increment;
}

-(id)initWithCapacity:(int)capacity {
    return [self initWithCapacity:capacity bufferLimit:capacity];
}

-(id)initWithCapacity:(int)capacity bufferLimit:(int)bufferLimit {
    self = [super init];
    if (self) {
        _limit = 0;
        _capacity = capacity;
        _bufferLimit = bufferLimit;
        
        _data = malloc(_capacity);
        
        _bytesSent = 0;
        _bytesRecv = 0;
        _increment = capacity;
    }
    return self;
}

-(void)dealloc {
    
    if(_data != NULL) {
        free(_data);
        _data = NULL;
    }
}

-(void)reset {
    _limit = 0;
}

-(void)rewind: (int)pos {
    if (pos >= 0 && pos < _capacity) {
        _limit = pos;
    }
}

-(void)rewindBy: (int)offset {
    int newPos = _limit + offset;
    if (newPos >= 0 && newPos < _capacity) {
        _limit = newPos;
    }
}


- (void)incBytesSent:(int) count {
    _bytesSent += count;
}

-(void)skip:(int)bytesToSkip {
    if (_data == NULL) {
        NSLog(@"ByteBuffer has no buffer allocated");
        return;
    }

    if(bytesToSkip >= _limit) {
        _limit = 0;
        return;
    }
    
    memcpy(_data, _data + bytesToSkip, _limit - bytesToSkip);
    _limit -= bytesToSkip;
}


- (Boolean)put:(const void *)src len:(int)len {
    //NSLog(@"put %d bytes", len);
    if (_data == NULL) {
        NSLog(@"ByteBuffer has no buffer allocated");
        return false;
    }
    if (![self reserve:len]) {
        return false;
    }
    
    memcpy(_data + _limit, src, len);
    _limit += len;
    //NSLog(@"bytesToSend=%d", _limit);
    return true;
}

- (Boolean)fillZeroes:(int)len {
    if (_data == NULL) {
        NSLog(@"ByteBuffer has no buffer allocated");
        return false;
    }
    if (![self reserve:len]) {
        return false;
    }
    
    memset(_data + _limit, 0, len);
    _limit += len;
    return true;
}



- (Boolean)hasBytesToSend {
    if(_limit > 0) {
        return true;
    }
    return false;
}


- (Boolean)send:(NSOutputStream *)s {
    if (_data == NULL) {
        NSLog(@"ByteBuffer has no buffer allocated");
        return false;
    }

    int bytesSent = (int)[s write:_data maxLength:_limit];
    //NSLog(@"%d bytes sent", bytesSent);
    if(bytesSent <= 0) {
        return false;
    }
    
    _bytesSent += bytesSent;
    
    [self skip:bytesSent];
    return true;
}

- (Boolean)recv:(NSInputStream *)s {
    if (_data == NULL) {
        NSLog(@"ByteBuffer has no buffer allocated");
        return false;
    }

    int reminder = _capacity - _limit;
    if(reminder <= 0) {
        return false;
    }
    
    int bytesRecv = (int)[s read:_data + _limit maxLength:reminder];
    //NSLog(@"%d bytes recv", bytesRecv);
    if(bytesRecv <= 0) {
        return false;
    }
    
    _bytesRecv += bytesRecv;
    
    _limit += bytesRecv;
    return true;
}

- (Boolean)reserve: (int)len {
    if (len <= _capacity - _limit) {
        return true;
    }
    if (_capacity >= _bufferLimit) {
        return false;
    }
        
    if (len + _limit < _bufferLimit) {
        NSLog(@"old capacity: %d bytes, max capacity: %d bytes", _capacity, _bufferLimit);
        int inc = _increment;
        int shortage = len - (_capacity - _limit);
        if (shortage > inc) {
            inc = ((shortage + inc  - 1) / inc) * inc;
        }
        int new_capacity = MIN(_bufferLimit,  _capacity + inc);
        uint8_t* new_data = realloc(_data, new_capacity);
        if (new_data == NULL) {
            NSLog(@"Failed to reallocate buffer (%d bytes)", new_capacity);
            return false;
        }
        _capacity = new_capacity;
        _data = new_data;
        NSLog(@"new capacity: %d bytes, max capacity: %d bytes", _capacity, _bufferLimit);
        return true;
    } else {
        return false;
    }
}

-(uint8_t*)nextData {
    return _data + _limit;
}

@end
