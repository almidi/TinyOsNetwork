#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	SEND_CHECK_MILLIS=70000,
	MAX_DEPTH=6, //UNUSED
	EPOCH_PERIOD_MILLI= 61440,
	TIMER_FAST_PERIOD=200,
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/

// Routing Message Struct
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t depth;
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

#endif
