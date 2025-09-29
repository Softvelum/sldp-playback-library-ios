
#import <Foundation/Foundation.h>
#import "AC3_Reader.h"

static const int AC3_SAMPLE_RATE[] = {
    48000, 44100, 32000
};

static const int AC3_NFCHANS[] = {
    2, 1, 2, 3, 3, 4, 4, 5
};

static const uint32_t AC3_FRAME_SIZE_W16[][3] = {
    { 64,   69,   96 },
    { 64,   70,   96 },
    { 80,   87,   120 },
    { 80,   88,   120 },
    { 96,   104,  144 },
    { 96,   105,  144 },
    { 112,  121,  168 },
    { 112,  122,  168 },
    { 128,  139,  192 },
    { 128,  140,  192 },
    { 160,  174,  240 },
    { 160,  175,  240 },
    { 192,  208,  288 },
    { 192,  209,  288 },
    { 224,  243,  336 },
    { 224,  244,  336 },
    { 256,  278,  384 },
    { 256,  279,  384 },
    { 320,  348,  480 },
    { 320,  349,  480 },
    { 384,  417,  576 },
    { 384,  418,  576 },
    { 448,  487,  672 },
    { 448,  488,  672 },
    { 512,  557,  768 },
    { 512,  558,  768 },
    { 640,  696,  960 },
    { 640,  697,  960 },
    { 768,  835,  1152 },
    { 768,  836,  1152 },
    { 896,  975,  1344 },
    { 896,  976,  1344 },
    { 1024, 1114, 1536 },
    { 1024, 1115, 1536 },
    { 1152, 1253, 1728 },
    { 1152, 1254, 1728 },
    { 1280, 1393, 1920 },
    { 1280, 1394, 1920 },
};

@implementation AC3_Reader

+(bool) processAC3Header:(const uint8_t*) buffer size: (uint32_t) size sample_rate: (int*) sample_rate frame_size: (uint32_t*) frame_size {
    if (size < 7) {
        return false;
    }

    uint8_t fscod = (buffer[4] & 0b11000000) >> 6;
    if (fscod < 0 || fscod >= sizeof(AC3_SAMPLE_RATE) / sizeof(AC3_SAMPLE_RATE[0])) {
        return false;
    }
    *sample_rate = AC3_SAMPLE_RATE[fscod];

    uint8_t frmsizecod = buffer[4] & 0b00111111;
    if (fscod < 0 || fscod >= sizeof(AC3_FRAME_SIZE_W16[0]) / sizeof(AC3_FRAME_SIZE_W16[0][0]) ||
        frmsizecod < 0 || frmsizecod >= sizeof(AC3_FRAME_SIZE_W16) / sizeof(AC3_FRAME_SIZE_W16[0])) {
        return false;
    }
    *frame_size = 2 * AC3_FRAME_SIZE_W16[frmsizecod][fscod];
    return true;
}

+(uint32_t) getMpeg2tsDuration:(int) sample_rate {
    uint32_t mpeg2ts_duration = 0;
    if (sample_rate == 48000) {
        mpeg2ts_duration = 2880;
    } else if (sample_rate == 32000) {
        mpeg2ts_duration = 4320;
    } else {
        mpeg2ts_duration = 1536 * 90000 / sample_rate;
    }
    return mpeg2ts_duration;
}

+(bool) getChannelLayout:(const uint8_t*) buffer size:(uint32_t) size layout: (uint8_t*) channel_layout {
    if (size < 7) {
        return false;
    }

    uint8_t acmod = (buffer[6] & 0b11100000) >> 5;
    int skip = 0;
    if (acmod == 2) {
        skip += 2; // dsurmod
    } else {
        if (acmod != 1 && acmod & 1) {
            skip += 2; // cmixlev
        }

        //
        if (acmod & 4) {
            skip += 2; // surmixlev
        }
    }

    uint8_t lfeon = 0;
    if (skip == 0) {
        lfeon = (buffer[6] & 0b00010000) >> 4;
    } else if (skip == 2) {
        lfeon = (buffer[6] & 0b00000100) >> 2;
    } else if (skip == 4) {
        lfeon = (buffer[6] & 0b00000001);
    } else {
        return false;
    }

    *channel_layout = (acmod << 1) | lfeon;
    return true;
}

+(bool) processAC3Bitstream:(const uint8_t*) buffer size: (uint32_t) size frames:(NSMutableArray<AC3_Frame*>*) frame_list part: (AC3_Frame*) frame_part {
    // http://atsc.org/wp-content/uploads/2015/03/A52-201212-17.pdf

    [frame_list removeAllObjects];
    [frame_part reset];

    while (true) {

        if (size < 1) {
            break;
        }

        if (buffer[0] != 0xb) {
            if (frame_list.count == 0) {
                // resync
                buffer += 1; size -= 1;
                continue;
            }
            // inconsistent frame
            return false;
        }


        if (size < 2) {
            // incomplete sync sequnce
            frame_part.buffer = buffer;
            frame_part.buffer_size = size;
            break;
        }
        
        // syncword
        if (buffer[1] != 0x77) {
            if (frame_list.count == 0) {
                // resync
                buffer += 1; size -= 1;
                continue;
            }
            // inconsistent frame
            return false;
        }

        if (size < 5) {
            // incomplete header
            frame_part.buffer = buffer;
            frame_part.buffer_size = size;
            break;
        }
                
        AC3_Frame* ac3_frame = [[AC3_Frame alloc]init];
        ac3_frame.buffer = buffer;
        int sample_rate = 0;
        uint32_t frame_size = 0;
        if (![self processAC3Header:buffer size:size sample_rate: &sample_rate frame_size: &frame_size]) {
            return false;
        }
        ac3_frame.sample_rate = sample_rate;
        ac3_frame.frame_size = frame_size;

        if (size < ac3_frame.frame_size) {
            // incomplete frame found
            frame_part = ac3_frame;
            frame_part.buffer_size = size;
            return true;
        }

        ac3_frame.buffer_size = ac3_frame.frame_size;

        // add complete frame
        [frame_list addObject:ac3_frame];

        buffer += ac3_frame.frame_size;
        size -= ac3_frame.frame_size;
    }

    return true;
}

+(int) ac3_channel_count:(const uint8_t) layout {
    int channel_count = 2;

    uint8_t acmod = layout >> 1;
    if (acmod < sizeof(AC3_NFCHANS) / sizeof(AC3_NFCHANS[0])) {
        channel_count = AC3_NFCHANS[acmod];

        if (layout & 0x1) {
            channel_count += 1;
        }
    }
    return channel_count;
}

+(AudioChannelLayoutTag) layoutToCoreAudioTag: (uint8_t) channel_layout {
    uint8_t acmod = channel_layout >> 1;
    if (acmod >= sizeof(AC3_NFCHANS) / sizeof(AC3_NFCHANS[0])) {
        return kAudioChannelLayoutTag_Stereo;
    }
    bool lfe = (channel_layout & 0b01) != 0; //Low-Frequency Effects (LFE) aka Subwoofer

    /*
     Table 5.8 Audio Coding Mode
     acmod | Audio Coding Mode | nfchans | Channel Array Ordering
     ‘000’      1+1                 2       Ch1, Ch2
     ‘001’      1/0                 1       C
     ‘010’      2/0                 2       L, R
     ‘011’      3/0                 3       L, C, R
     ‘100’      2/1                 3       L, R, S
     ‘101’      3/1                 4       L, C, R, S
     ‘110’      2/2                 4       L, R, SL, SR
     ‘111’      3/2                 5       L, C, R, SL, SR
     */
    switch (acmod) {
        case 0b000:
            return kAudioChannelLayoutTag_AC3_1_0_1;
        case 0b001:
            return lfe ? kAudioChannelLayoutTag_AC3_1_0_1 : kAudioChannelLayoutTag_Mono; // C [LFE]
        case 0b010:
            return lfe ? kAudioChannelLayoutTag_DVD_4 : kAudioChannelLayoutTag_Stereo; // L R [LFE]
        case 0b011:
            return lfe ? kAudioChannelLayoutTag_AC3_3_0_1 : kAudioChannelLayoutTag_AC3_3_0; // L C R [LFE]
        case 0b100:
            return lfe ? kAudioChannelLayoutTag_ITU_2_1 : kAudioChannelLayoutTag_AC3_2_1_1; // L R Cs [LFE]
        case 0b101:
            return lfe ? kAudioChannelLayoutTag_AC3_3_1_1 : kAudioChannelLayoutTag_AC3_3_1; // L C R Cs LFE
        case 0b110:
            return lfe ? kAudioChannelLayoutTag_DVD_18 : kAudioChannelLayoutTag_Logic_Quadraphonic; // L R Ls Rs [LFE]
        case 0b111:
            return lfe ? kAudioChannelLayoutTag_MPEG_5_1_C :  kAudioChannelLayoutTag_MPEG_5_0_C ; // L C R Ls Rs [LFE]
        default:
            break;
    }
    return kAudioChannelLayoutTag_Stereo;

}


@end
