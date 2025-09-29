#ifndef _LARIX_SRT_STATS_H
#define _LARIX_SRT_STATS_H

#import <Foundation/Foundation.h>

@interface PlayerSrtStats: NSObject

    @property int64_t   msTimeStamp;                // time since the UDT entity is started, in milliseconds
    @property int64_t   pktSentTotal;               // total number of sent data packets, including retransmissions
    @property int64_t   pktRecvTotal;               // total number of received packets
    @property int      pktSndLossTotal;            // total number of lost packets (sender side)
    @property int      pktRcvLossTotal;            // total number of lost packets (receiver side)
    @property int      pktRetransTotal;            // total number of retransmitted packets
    @property int      pktSentACKTotal;            // total number of sent ACK packets
    @property int      pktRecvACKTotal;            // total number of received ACK packets
    @property int      pktSentNAKTotal;            // total number of sent NAK packets
    @property int      pktRecvNAKTotal;            // total number of received NAK packets
    @property int64_t  usSndDurationTotal;         // total time duration when UDT is sending data (idle time exclusive)

    @property int      pktSndDropTotal;            // number of too-late-to-send dropped packets
    @property int      pktRcvDropTotal;            // number of too-late-to play missing packets
    @property int      pktRcvUndecryptTotal;       // number of undecrypted packets
    @property uint64_t byteSentTotal;              // total number of sent data bytes, including retransmissions
    @property uint64_t byteRecvTotal;              // total number of received bytes
    @property uint64_t byteRcvLossTotal;           // total number of lost bytes
    @property uint64_t byteRetransTotal;           // total number of retransmitted bytes
    @property uint64_t byteSndDropTotal;           // number of too-late-to-send dropped bytes
    @property uint64_t byteRcvDropTotal;           // number of too-late-to play missing bytes (estimate based on average packet size)
    @property uint64_t byteRcvUndecryptTotal;      // number of undecrypted bytes

   // local measurements
    @property int64_t  pktSent;                    // number of sent data packets, including retransmissions
    @property int64_t  pktRecv;                    // number of received packets
    @property int      pktSndLoss;                 // number of lost packets (sender side)
    @property int      pktRcvLoss;                 // number of lost packets (receiver side)
    @property int      pktRetrans;                 // number of retransmitted packets
    @property int      pktRcvRetrans;              // number of retransmitted packets received
    @property int      pktSentACK;                 // number of sent ACK packets
    @property int      pktRecvACK;                 // number of received ACK packets
    @property int      pktSentNAK;                 // number of sent NAK packets
    @property int      pktRecvNAK;                 // number of received NAK packets
    @property double   mbpsSendRate;               // sending rate in Mb/s
    @property double   mbpsRecvRate;               // receiving rate in Mb/s
    @property int64_t  usSndDuration;              // busy sending time (i.e., idle time exclusive)
    @property int      pktReorderDistance;         // size of order discrepancy in received sequences
    @property double   pktRcvAvgBelatedTime;       // average time of packet delay for belated packets (packets with sequence past the ACK)
    @property int64_t  pktRcvBelated;              // number of received AND IGNORED packets due to having come too late

    @property int      pktSndDrop;                 // number of too-late-to-send dropped packets
    @property int      pktRcvDrop;                 // number of too-late-to play missing packets
    @property int      pktRcvUndecrypt;            // number of undecrypted packets
    @property uint64_t byteSent;                   // number of sent data bytes, including retransmissions
    @property uint64_t byteRecv;                   // number of received bytes
    @property uint64_t byteRcvLoss;                // number of retransmitted bytes
    @property uint64_t byteRetrans;                // number of retransmitted bytes
    @property uint64_t byteSndDrop;                // number of too-late-to-send dropped bytes
    @property uint64_t byteRcvDrop;                // number of too-late-to play missing bytes (estimate based on average packet size)
    @property uint64_t byteRcvUndecrypt;           // number of undecrypted bytes

   // instant measurements
    @property double   usPktSndPeriod;             // packet sending period, in microseconds
    @property int      pktFlowWindow;              // flow window size, in number of packets
    @property int      pktCongestionWindow;        // congestion window size, in number of packets
    @property int      pktFlightSize;              // number of packets on flight
    @property double   msRTT;                      // RTT, in milliseconds
    @property double   mbpsBandwidth;              // estimated bandwidth, in Mb/s
    @property int      byteAvailSndBuf;            // available UDT sender buffer size
    @property int      byteAvailRcvBuf;            // available UDT receiver buffer size

    @property double   mbpsMaxBW;                  // Transmit Bandwidth ceiling (Mbps)
    @property int      byteMSS;                    // MTU

    @property int      pktSndBuf;                  // UnACKed packets in UDT sender
    @property int      byteSndBuf;                 // UnACKed bytes in UDT sender
    @property int      msSndBuf;                   // UnACKed timespan (msec) of UDT sender
    @property int      msSndTsbPdDelay;            // Timestamp-based Packet Delivery Delay

    @property int      pktRcvBuf;                  // Undelivered packets in UDT receiver
    @property int      byteRcvBuf;                 // Undelivered bytes of UDT receiver
    @property int      msRcvBuf;                   // Undelivered timespan (msec) of UDT receiver
    @property int      msRcvTsbPdDelay;            // Timestamp-based Packet Delivery Delay

    @property int      pktSndFilterExtraTotal;     // number of control packets supplied by packet filter
    @property int      pktRcvFilterExtraTotal;     // number of control packets received and not supplied back
    @property int      pktRcvFilterSupplyTotal;    // number of packets that the filter supplied extra (e.g. FEC rebuilt)
    @property int      pktRcvFilterLossTotal;      // number of packet loss not coverable by filter

    @property int      pktSndFilterExtra;          // number of control packets supplied by packet filter
    @property int      pktRcvFilterExtra;          // number of control packets received and not supplied back
    @property int      pktRcvFilterSupply;         // number of packets that the filter supplied extra (e.g. FEC rebuilt)
    @property int      pktRcvFilterLoss;           // number of packet loss not coverable by filter
    @property int      pktReorderTolerance;        // packet reorder tolerance value

    // New stats in 1.5.0

    // Total
    @property int64_t  pktSentUniqueTotal;         // total number of data packets sent by the application
    @property int64_t  pktRecvUniqueTotal;         // total number of packets to be received by the application
    @property uint64_t byteSentUniqueTotal;        // total number of data bytes, sent by the application
    @property uint64_t byteRecvUniqueTotal;        // total number of data bytes to be received by the application

   // Local
    @property int64_t  pktSentUnique;              // number of data packets sent by the application
    @property int64_t  pktRecvUnique;              // number of packets to be received by the application
    @property uint64_t byteSentUnique;             // number of data bytes, sent by the application
    @property uint64_t byteRecvUnique;             // number of data bytes to be received by the application
@end

#endif
