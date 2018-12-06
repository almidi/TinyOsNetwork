#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#define COLORS

enum{
	SENDER_QUEUE_SIZE=100,
	RECEIVER_QUEUE_SIZE=100,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	SEND_CHECK_MILLIS=70000,
	MAX_DEPTH=15,
	EPOCH_PERIOD_MILLI= 61440,
	TIMER_FAST_PERIOD=200,
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/

// Routing Message Struct
typedef nx_struct RoutingMsg
{
	nx_uint8_t senderID;
	nx_uint8_t depth;
	nx_uint8_t query ;
} RoutingMsg;

// Notify Parent Message Struct
typedef nx_struct NotifyParentMsg
{
	nx_uint16_t senderID;
	nx_uint16_t parentID;
	nx_uint8_t  depth;
	nx_uint32_t SUM;
	nx_uint32_t COUNT;
	nx_uint32_t MAX;
} NotifyParentMsg;

typedef nx_struct NotifyParentMsgSingle
{
	nx_uint16_t senderID;
	nx_uint16_t parentID;
	nx_uint8_t  depth;
	nx_uint32_t Num[1];
} NotifyParentMsgSingle;

typedef nx_struct NotifyParentMsgDouble
{
	nx_uint16_t senderID;
	nx_uint16_t parentID;
	nx_uint8_t  depth;
	nx_uint32_t Num[2];
} NotifyParentMsgDouble;

typedef nx_struct NotifyParentMsgTriple
{
	nx_uint16_t senderID;
	nx_uint16_t parentID; 
	nx_uint8_t  depth;
	nx_uint32_t Num[3];
} NotifyParentMsgTriple;

typedef nx_struct NotifyParentMsgQuad
{
	nx_uint16_t senderID;
	nx_uint16_t parentID; 
	nx_uint8_t  depth;
	nx_uint32_t Num[4];
} NotifyParentMsgQuad;


#endif
