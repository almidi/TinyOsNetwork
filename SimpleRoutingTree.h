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
	MAX_DEPTH=200,
	EPOCH_PERIOD_MILLI= 61440,
	TIMER_FAST_PERIOD=20,
	LOST_TASK_PERIOD=5,
	TCT_UPPER_BOUND=60,
	TCT_LOWER_BOUND=10
};

// Routing Message Struct
typedef nx_struct RoutingMsg{
	nx_uint8_t depth;
	nx_uint8_t query;
} RoutingMsg;

typedef nx_struct RoutingMsgTiNA{
	nx_uint8_t depth;
	nx_uint8_t query;
	nx_uint8_t tct;
} RoutingMsgTiNA;

#endif
