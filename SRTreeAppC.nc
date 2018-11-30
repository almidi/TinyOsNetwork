#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

#if defined(DELUGE) //defined(DELUGE_BASESTATION) || defined(DELUGE_LIGHT_BASESTATION)
	components DelugeC;
#endif

	components MainC, ActiveMessageC;
	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as LostTaskTimerC;
	components new TimerMilliC() as EpochTimerC;
	components new TimerMilliC() as SlotTimerC;
	
	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;
	components new AMSenderC(AM_NOTIFYPARENTMSG) as NotifySenderC;
	components new AMReceiverC(AM_NOTIFYPARENTMSG) as NotifyReceiverC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	components new PacketQueueC(SENDER_QUEUE_SIZE) as NotifySendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as NotifyReceiveQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as DataQueueC;


	components RandomMlcgC as RandomC;
	
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;
	
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.LostTaskTimer->LostTaskTimerC;
	SRTreeC.EpochTimer->EpochTimerC;
	SRTreeC.SlotTimer->SlotTimerC;


	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	
	SRTreeC.NotifyPacket->NotifySenderC.Packet;
	SRTreeC.NotifyAMPacket->NotifySenderC.AMPacket;
	SRTreeC.NotifyAMSend->NotifySenderC.AMSend;
	SRTreeC.NotifyReceive->NotifyReceiverC.Receive;
	
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	SRTreeC.NotifySendQueue->NotifySendQueueC;
	SRTreeC.NotifyReceiveQueue->NotifyReceiveQueueC;
	SRTreeC.DataQueue->DataQueueC;

	SRTreeC.RandomGenerator -> RandomC;
	SRTreeC.GeneratorSeed -> RandomC.SeedInit;
	
}
